# Rate limiting

Main points from Luca Sepe, *API Rate Limiting & Throttling* (Production Field Manuals), applied
to strata. Index and the other patterns: [README.md](README.md).

## What it is for

A rate limiter protects shared capacity from callers that send too much: a noisy tenant, a client
bug, a retry loop, an attack. It turns overload from a resource collapse into a decided answer.

- **It must refuse before the thing it protects fails.** If Redpanda or a data node is already
  saturated when refusals start, the limiter is late. The sign it works: refusals rise while
  latency, CPU and memory stay flat.
- **It is a contract, not a feature at the edge.** It says who may use capacity, how fast, and
  what happens over the limit.
- **Autoscaling does not replace it.** Scaling adds supply after demand rose; limiting controls
  demand at the boundary. A platform needs both.
- **Fairness is part of reliability.** One tenant must not spend another tenant's capacity.

Throttle (delay) when the caller can wait and the work is still useful later. Limit (refuse) when
excess work must be turned away now. Do not use a limiter to hide a system that is too small for
normal load.

## Decide before you build

| Question | Notes |
|---|---|
| What is the fairness key? | It must be stable, bounded and meaningful. For strata: the tenant from the token. |
| What is protected? | CPU, a dependency, a plan quota, cost, or another tenant's service. |
| Is the limit protective or contractual? | Protective limits can be approximate. A limit a customer pays for needs accuracy. |
| Which operations share a limit, and which get their own? | Cheap reads and expensive operations should not share one bucket. |
| What does the caller get over the limit? | A stable error, a retry hint, and the promise below. |
| Where does the state live, and is it bounded? | Local, shared, or both. A maximum number of keys, with eviction. |
| If the limiter itself fails: allow or refuse? | Decide per operation, and make the fallback visible. |
| Who changes limits, and how in an emergency? | A policy change must not need a new binary. |

## Rules

**Identity**

- Key by business identity, taken **after** authentication. An IP address alone is a poor key:
  shared addresses block innocent users, and it is not the customer.
- A limit applied before authentication is an abuse guard, not tenant fairness. Have both.
- Never trust a key the caller can make up freely. Unlimited distinct keys make the limiter the
  memory leak: bound the key count.
- One global limit in a multi-tenant product protects the cluster and lets one tenant starve the
  rest.

**Placement**

- Limit before expensive work. A limiter that runs after the lookup, the fan-out or the
  dependency call saves almost nothing.
- Check cheapest first: abuse guard, then tenant limit, then the dependency's own budget, then
  the work.
- A limit at the edge does not protect internal callers, expensive operations or background
  fan-out. Those need their own.

**Algorithm**

| Algorithm | Behaviour | Use for |
|---|---|---|
| Token bucket | A steady rate plus a short burst allowance | The default for requests |
| Fixed window | Counts per window; allows a double burst at the window edge | Simple quotas that are easy to explain |
| Sliding window | Counts over a rolling interval; fairer; more state | Strict rolling quotas |
| Leaky bucket | Drains queued work at a fixed rate | Pacing work that can wait; poor for request/reply, where queueing adds latency |

Add a concurrency cap next to the rate for expensive or slow operations.

**State: local or shared**

- **Local** (per process) is fast and has no dependency, but the total allowance grows with the
  number of processes. That is right when each process's limit protects that process.
- **Shared** is accurate but adds a network call and a new failure on the request path. A limiter
  that is less reliable than what it protects is a bad trade.
- Default: local token buckets for protection; a shared quota only where the business needs a
  global number; a local fallback for when the shared one is down.
- Ask what 5% over the limit for 30 seconds would cost. If the answer is "little", approximate is
  fine. Write down the accuracy the business asked for; do not let the code imply more.

**Under stress**

- The limiter gets cheaper under overload: it refuses early, allocates little, never blocks on a
  slow dependency and never queues without bound.
- Update a bucket's fields together under one lock. Atomics are for counters, not for state with
  several fields.
- Do not log every refusal. A refusal storm with a log line each moves the outage to logging.
  Sample the logs and keep exact counters.
- Benchmark the allow path and keep it free of allocation for known keys. The benchmark is a
  tripwire for regressions, not a capacity figure.

**Caller contract**

A limit changes the API. Document it like any other behaviour:

- a stable error that means "over the limit", distinct from a failure
- a hint for when to try again
- the promise that **refused work did not run**
- what the client should do: wait, lower concurrency, retry with backoff

Without this, clients retry at once and open more connections, and the limiter becomes an
amplifier.

## In strata

- **Gateway**: a token bucket per tenant, checked after the token is verified and before anything
  is forwarded. Before the token check, a cheap guard keyed by source address limits the cost of
  bad tokens (each one costs a signature check).
- **Limits come from the control plane** (the tenant's plan), are cached in the gateway, and can
  be changed without a deploy.
- **Several gateways multiply a local limit.** Whether a tenant's limit is per gateway or global
  is **(not set yet)**. Start local; add a shared quota only if a plan sells an exact number.
- **Owner**: a per-tenant cap inside the data node, so one tenant cannot fill a node that several
  tenants share. Caps nest: tenant ≤ data node.
- **Expensive commands** (large scans, big range reads, scripts) get a separate, lower limit or a
  concurrency cap. Which commands count as expensive is **(not set yet)**.
- **The refusal on the Valkey protocol** is an error reply. Its code and how the retry hint is
  carried are **(not set yet)**; pick one stable code and document it.
- **Control plane public API**: per caller; HTTP 429 with `Retry-After`.

## Measure

Allowed and refused counts, decision latency, tracked key count against its maximum, decisions
made in fallback mode, the active policy version. Labels stay bounded: component, operation
class, policy, decision. **Never a raw tenant id as a metric label**; use logs for one tenant.

Alert when the protection is broken, not when it is active:

- refusals are happening **and** the protected dependency is still slow (limit too high, too
  late, or bypassed)
- the key count is near its maximum
- decision latency is high

## Tests

- Allows up to rate and burst; refuses after; refills with time (use an injected clock).
- Fixed and sliding windows: the on and off points at the window edge.
- Bad configuration is rejected.
- The key count is bounded: many distinct keys do not grow memory past the maximum.
- Two tenants: one over its limit does not cause refusals for the other.
- A refused request did not reach the protected work (assert with a fake that counts calls).
- The refusal carries the documented error and retry hint.
- A cancelled context is honoured.
- Concurrent use under `-race`.
- A benchmark of the allow path with allocation reporting.
- Under load: with a slow fake dependency and too much traffic, refusals rise and the component
  still answers health checks; errors other than refusals stay near zero.

## Smells

- One global limit for all tenants.
- The limiter runs after the expensive work.
- A per-key map with no maximum.
- The tenant id, a user id or a raw path as a metric label.
- A log line per refusal.
- Refusals reported as generic failures.
- No decision on what happens when the limiter's own state store is down.
