# Circuit breakers and retries

Main points from Luca Sepe, *Circuit Breaker and Retries with Exponential Backoff* (Production
Field Manuals), applied to strata. Index and the other patterns: [README.md](README.md).

## What they are for

When a dependency fails or slows, a caller can keep sending and make it worse, or stop for a
while and protect everything else. A **circuit breaker** takes the second choice: repeated
failures become a fast local answer, the caller's goroutines and connections are released, and
the dependency gets room to recover.

A **retry with backoff** covers a different case: a failure that is likely to pass. It tries
again, but each time after a longer, randomised wait, so thousands of callers do not all retry in
the same millisecond.

- **Retries are useful only when bounded. Breakers are useful only when observable.**
- **The goal under stress is not that every request succeeds. It is that the caller stops making
  the outage worse.**
- Neither replaces capacity planning, idempotency or clear ownership.

Do not use them for local, deterministic work, and do not use them to hide a dependency that is
permanently too small.

## The retry storm

The failure these exist to prevent:

1. A dependency slows down.
2. Callers hit timeouts.
3. Callers retry at once, or all on the same schedule.
4. The dependency gets more traffic while it is unhealthy.
5. Callers pile up goroutines and connections; autoscaling adds callers.
6. More callers send more retries. One slow dependency is now a platform outage.

Usual causes: no jitter, too many attempts, a per-attempt timeout longer than the caller's
deadline, a threshold too high to trip, one breaker shared by unrelated operations, retried
writes that are not idempotent, no connection limit, a log line with a stack per failure.

## Decide before you build

| Decision | Notes |
|---|---|
| End-to-end deadline and per-attempt timeout | Start from the caller's deadline, not from a library default. |
| Is the operation idempotent? | If not, it is not retried without an idempotency key. |
| Which errors are retryable? | Written as an explicit list. |
| Base delay, maximum delay, jitter, maximum attempts | See the starting points below. |
| Breaker threshold, cool-down, number of probes | Per dependency. |
| What the caller does while the breaker is open | Fall back, serve stale, queue, or fail with a clear error. |
| What users see while the dependency is down | A written decision per dependency. |

## Rules

**Order of a protected call**

```
request → take the deadline → ask the breaker → attempt (with its own timeout) → classify the error
        → retry only if retryable, idempotent and the deadline allows → record the result in the breaker
```

The breaker is asked before **every** attempt, not once per request.

**Breaker**

| State | Behaviour |
|---|---|
| Closed | Calls go through; failures are counted |
| Open | Calls fail at once, without touching the dependency |
| Half-open | After the cool-down, a few probe calls go through. Success closes it; a failure opens it again |

- **One breaker per dependency and kind of operation.** A breaker shared by unrelated operations
  opens for the wrong reasons.
- **Count the dependency's health, not the caller's mistakes.** Timeouts, connection errors and
  server errors count. Bad input, "not found", "not authorised" and conflicts are answers.
- A call refused by an open breaker is a rejection, not a failure. Count it separately.
- At high request rates, use an error rate over a rolling window. A run of consecutive failures
  is simple but noisy.
- **Open before the caller's own resources run out.** Too loose and it opens too late; too tight
  and it cuts availability on a small burst of errors.
- Keep the state, failure count, opened time and probe count under one lock. The invariant is
  the unit of protection. The decision runs on every call, so it must be cheap.

**Retries**

- **Retry only retryable failures, and only idempotent operations.**

  | Retryable | Not retryable |
  |---|---|
  | Connection reset, timeout, temporary resolution failure | Invalid input |
  | "Unavailable", "busy", "try later" from the server | Not authenticated, not authorised |
  | Server errors | Not found, conflict (unless the domain says otherwise) |

- **Always jitter.** Full jitter: wait a random time between zero and the current cap. Cap the
  delay before randomising.
- **Stop when the context is done.** Never `time.Sleep` in a retry loop; wait on a timer and the
  context together.
- **Attempts fit inside the deadline.** Three attempts of 150 ms with waits of 50 and 100 ms are
  600 ms: that cannot fit a 500 ms budget. Do the sum.
- **One retry layer per call chain.** Turn library retries off or down to one. Layers multiply.
- **Writes are not retried by default.** After a timeout the outcome of a write is **unknown**:
  it may have applied. Resolve it with an idempotency key, a durable record of the command, or a
  re-read. Never by sending it again blind.
- **Retries spend a budget**, so a quiet hour's credit cannot pay for a storm.
- Reads are usually safe to retry, and a stale answer may be an acceptable fallback.

**Clients**

- One long-lived client per dependency, with connection limits and transport timeouts. Never a
  new client per call.
- No goroutine per attempt, no per-request retry history kept in the breaker, no large error
  strings built on the success path.

**Health checks and scaling**

- **Readiness does not fail because a dependency is down.** Otherwise one outage removes every
  caller from service and makes a larger one. Readiness means "this process can serve its core
  traffic"; dependency health is a metric.
- **Liveness never encodes dependency health.** Restarting healthy callers during a dependency
  outage throws away warm state and adds load.
- **Autoscaling can amplify.** Retry load looks like demand. Cap replicas for callers of a
  fragile dependency, and scale on useful throughput, not on request counts inflated by retries.

## Starting points

Starting values to validate with tests and drills, not to copy. Every value must fit the
operation's latency budget and the dependency's behaviour.

| Parameter | Start at | Note |
|---|---|---|
| Maximum attempts | 2–3 | 2 for anything a user waits on. More usually hurts p99 |
| Per-attempt timeout | 50–300 ms for internal calls | Inside the caller's deadline |
| Base backoff | 25–100 ms | Small for interactive work |
| Maximum backoff | 500 ms–2 s | Caps the tail |
| Jitter | Full | Required |
| Failure threshold | 5–20 in a row, or an error rate over a window | The window at high rates |
| Open cool-down | 5–30 s | Longer for fragile dependencies |
| Half-open probes | 1–10 | Few, so recovery is not flooded |
| Retry writes | No | Only with an idempotency key |

## In strata

- **Owner → Redpanda append is on the write path.** Redpanda's breaker open means **writes are
  refused** with a clear, retryable error. Whether reads keep working while it is open is
  **(not set yet)**.
- **An append that timed out is an unknown outcome.** The write may be in the log. The owner must
  not report failure and let the client resend something like `INCR`. Options to choose from
  **(not set yet)**: a producer that deduplicates its own retries, a request id in the log
  record, or reading the log back before answering.
- **Client commands are not idempotent in general** (`INCR`, `LPUSH`, `SPOP`). The gateway never
  retries a command toward an owner by itself. A client's retry after a timeout is safe only
  with a request id; that design is **(not set yet)**.
- **Breakers**: one each for Redpanda append, Redpanda replay, object storage and Postgres; one
  per data node in the gateway; one per data node in the control plane for ownership calls.
- **"Not the owner", a bad command and a bad token are answers.** They never count against a
  breaker.
- **Object storage open**: tenants already loaded are unaffected; loads wait; the flusher's next
  run retries; the unflushed tail grows and is alerted on.
- **Control plane down**: the data plane serves from cached routes and signing keys. It is never
  a readiness failure for a gateway or a data node.
- **Flusher**: its retry is the next run. No tight retry loop.
- No breaker or retry package exists in strata yet. Build them once, in `internal/`, with the
  tests below, and use them everywhere.

## Measure

Calls, allowed, rejected by the breaker, successes, failures, retries, retries exhausted, state
changes; breaker state as a gauge; probes in flight; duration of the whole call including
retries, of a single attempt, and of the backoff chosen. Labels stay bounded: component,
dependency, operation, outcome, state. Never a user id, request id, raw address or error text.

Alert on **retry rate and open breakers**, not only on error responses.

- Retries rising while the dependency's latency rises: amplification.
- Breaker open while the caller's latency falls: containment is working.
- An incident is over when retry volume, latency, saturation and breaker state are all back to
  baseline, not when the errors stop.

In an incident: lower attempts to 1 or 2, raise the backoff cap, lower the threshold, cap the
callers' replicas, shed non-critical traffic. These must be changeable at run time.

## Tests

- The breaker opens at the threshold.
- Open: the call is rejected and **the dependency is not called** (a fake counts calls).
- After the cool-down it goes half-open; a successful probe closes it; a failed probe reopens it.
- No more than the configured probes run at once in half-open.
- Errors that are answers do not count against the breaker.
- A non-idempotent operation is not retried.
- The retry loop stops when the context is cancelled, including during a backoff wait.
- Exhausted retries return an explicit error.
- Backoff stays within `[0, cap]` and grows per attempt (inject the random source and the clock).
- The total time never passes the caller's deadline.
- **Assert attempt counts, not elapsed time**; give any upper time bound seconds of slack.
- `-race` clean, with many goroutines through one breaker.
- Through a fault harness: refused connection, accepted-then-silent, slow body, server errors,
  and "applied but the reply was lost". The last one must be resolved, not misreported.
- Under load: add latency and errors to a dependency and check that retries stay bounded, the
  breaker opens, and the caller's goroutine count stays flat.

## Smells

- A retried write with no idempotency key.
- A retry after the deadline has passed.
- The same retry schedule in every process, with no jitter.
- `time.Sleep` in a retry loop.
- A breaker that counts validation errors.
- One breaker for a whole process.
- A new client per call.
- A log line with a stack for every retry.
- Readiness or liveness that checks a dependency.
- Alerts on error responses only.
