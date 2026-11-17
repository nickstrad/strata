# Backpressure

Main points from Luca Sepe, *Backpressure in Microservices* (Production Field Manuals), applied to
strata. Index and the other patterns: [README.md](README.md).

## What it is for

When work arrives faster than a process can finish it, the backlog goes somewhere: a channel, a
goroutine per request, a slice, a connection pool, a dependency. Backpressure makes that place
bounded and the overflow explicit. A process should be able to say one of these, quickly:

- I accepted this work, and what I hold is bounded.
- I refused this work before spending more on it.
- I dropped older, less valuable work to make room.
- I cancelled work that can no longer finish in time.
- I lowered my concurrency toward a dependency to protect it.

**The question to ask of every component: when a dependency slows down, which resource stays
bounded?**

Without it, a small slowdown runs like this: workers block longer, the queue grows because intake
is still open, callers time out and retry, goroutines and memory climb, autoscaling adds replicas
that behave the same way. The cause is not one metric; it is that nothing decides admission.

Backpressure keeps a system stable under abnormal load. It does not excuse one that is too small
for normal load.

## It is four boundaries, not a queue

| Boundary | Holds |
|---|---|
| Caller | Request rate, retries, deadlines, idempotency |
| Admission | A bounded queue, a non-blocking enqueue, refuse or drop |
| Execution | A bounded worker pool, a context per unit of work |
| Dependency | Outbound timeout, concurrency limit, retry budget, breaker |

Each one alone fails:

- A bounded queue without deadlines still completes stale work.
- A worker pool without bounded admission moves the overload into memory.
- A timeout without refusal still accepts more than the process can honour.

## Decide before you build

These are product decisions as much as code. Without answers, the accidental policy is "queue
until the host dies".

| Question | Notes |
|---|---|
| Which work may be refused? | The caller can retry later or go elsewhere. |
| Which work may be dropped after it was queued? | Only work whose loss is acceptable. |
| What does a refused caller receive? | A stable "not accepted" answer, distinct from a failure. |
| What is the longest useful wait in the queue? | See the queue age rule below. |
| Is the work safe to retry? | Needed before telling a caller to try again. |
| Does "accepted" mean durable, or only admitted in memory? | Very different promises. Say which. |
| Is the worker count per process, per tenant, per dependency, or global? | Replicas multiply it. |
| What happens to queued and running work on shutdown? | Drain, cancel or refuse. |

## Rules

**Queues**

- **No unbounded queue on a hot path**: no unbuffered-forever channel, no growing slice, no
  `go process(item)` in a request loop. A huge buffer is not a capacity plan.
- **Capacity is derived, then revisited**:
  `capacity ≈ acceptable queue delay ÷ average service time × workers`, then lowered for payload
  size and memory. It must survive a dependency slowdown.
- **Enqueue does not block on a request path.** A full queue answers "full" at once, so the
  caller's goroutine is free and the caller decides. Blocking enqueue is for batch work only.
- **One queue per kind of work.** Interactive requests, batch jobs and telemetry differ in value
  and freshness; a shared queue lets one starve the others.

**Policy when full**

| Policy | Use when | Examples |
|---|---|---|
| **Refuse new** (the default) | Accepted work must not disappear | Commands, writes |
| Drop oldest | Fresh data is worth more than complete data | Telemetry, status, progress |
| Drop newest or merge | The work is optional or redundant | Cache warming |
| Wait, with a bound | Throughput matters more than latency | Batch processing |
| Cancel | The work cannot finish inside its useful time | Anything with a deadline |

The default is: **refuse new + bounded queue + bounded workers + deadline + metrics**. Change the
policy only when the workload's meaning justifies it, and state it in the API contract.

**Admission**

- Admit before expensive work. If the process parses a large payload and queries a dependency and
  only then finds the queue full, the boundary is too late.
- For a consumer loop, admission is the decision to pull more. Stop pulling when the next stage
  is full.

**Queue age**

- Depth says how many are waiting. Age says whether they are still worth doing. 50 items waiting
  5 ms is fine; 50 items waiting 30 s against a 2 s caller timeout is a queue producing waste.
- `queue wait budget = caller deadline − expected service time − margin to reply`. Work that has
  waited longer is refused before admission (commands), replaced by newer state (freshness
  data), or cancelled when a worker picks it up.
- For command-like work, age leads to refusal at admission, never to a silent drop after
  acceptance.

**Workers**

- Workers turn queued work into bounded concurrency. Size them from CPU, the dependency's
  concurrency and the latency target. **More workers is not better** when the bottleneck is
  downstream: it spreads one slow dependency into a shared outage.
- Every worker has an owner and a lifecycle: started in a constructor, stopped on shutdown,
  drains or cancels by policy, honours deadlines, reports in-flight and finished work.
- No outbound call without a deadline, shorter than the caller's remaining time with room to
  answer.
- **Retries inside a worker need a budget.** Each retry turns one accepted item into several
  downstream calls.

**Local and shared**

- Every process has local bounded admission. It is fast and needs no remote decision.
- Coordinate across processes only for a scarce shared dependency, and keep the local bound
  anyway: the coordinator can fail.
- Replicas multiply concurrency. 10 processes × 32 workers is 320 concurrent calls; 50 is 1600.
  That is fine only if the dependency scales with them.
- Scale on a signal that means real capacity is short. If a process is blocked on a slow
  dependency, CPU looks low while latency is high. Scale on useful throughput or queue age, not
  on request volume inflated by retries, and not while the dependency is already slow.

**Under stress**

- Shedding gets cheaper under overload: enqueue stays O(1), a full queue answers at once, drops
  are counted, logs are sampled, metrics are aggregate.
- Shedding is never invisible. If work is refused or dropped and neither the response nor a
  metric shows it, protection cannot be told from data loss.

## In strata

- **Tenant mailbox (owner)**: bounded, **refuse new**. A write is acknowledged only after the log
  append, so a command refused at admission has not happened and is safe for the client to send
  again. Nothing accepted is ever dropped.
- **Mailbox capacity and the wait budget** are **(not set yet)**. The Valkey protocol carries no
  deadline, so the owner needs a default per-command deadline to judge queue age against.
- **Tenant loads (restore and replay)** run in their own bounded pool, apart from serving, so a
  burst of loads cannot starve tenants that are already loaded. A load is a bulkhead.
- **Gateway**: a bound on in-flight work per owner. When an owner is slow, the gateway refuses
  for that owner's tenants and keeps serving the others.
- **Flusher**: it pulls from Redpanda at its own pace, in bounded batches, so the log is its
  durable queue. It never holds an unbounded backlog in memory. If object storage is slow, it
  pulls less; the log grows instead, and **the age of the oldest unflushed write** is the signal.
- **Redpanda is the shared scarce dependency.** Every data node appends to it, so data node count
  times in-flight appends is the load to budget.
- **Telemetry** is the one place for drop-oldest: metrics and usage events may be dropped and
  counted; commands may not.
- **"Accepted" in strata means durable in the log.** Never report acceptance on in-memory
  admission alone.

## Measure

Queue depth and capacity; accepted, processed, refused, dropped and failed counts; in-flight
workers; **wait time from admission to pickup** (p50, p95, p99); the age of the oldest item;
timeouts; the dependency's latency. Labels stay bounded: component, queue, policy, dependency.

Alert when the protection is broken, not when it is active. A full queue with steady refusals and
flat memory is the design working.

- the queue is near capacity and refusals continue for minutes
- refusals are happening **and** the dependency is still slow
- queue wait exceeds the caller's budget

Reading the signals:

| Signals | Meaning | Do |
|---|---|---|
| Queue full, workers busy, dependency healthy | More work than configured capacity | Add capacity only if queue age stays in budget |
| Queue full, workers busy, dependency slow | The bottleneck is downstream | Do **not** add workers; lower concurrency, shorten deadlines, shed |
| Queue deep, workers idle | Blocked, deadlocked or not signalled | Take a goroutine dump |
| Queue low, memory high | The backlog is elsewhere | Look at payloads, leaks, retry buffers, logs |
| Refusals high, request rate rising | Callers retry at once | Enforce backoff; rate limit the caller |
| Processed rising, successes flat, queue age high | Work finishes after it is useful | Cancel at pickup; lower capacity |

When latency rises: check the dependency's p99, queue depth and age, refusals and drops, worker
use, then the callers' retry rate. Reduce intake or concurrency before adding workers.

## Tests

- A full queue refuses at once with the documented error; the enqueue never blocks.
- Refused work did not run (a fake counts the calls).
- Capacity and worker count are never exceeded under concurrent producers (`-race`).
- Each policy does what it says: refuse-new keeps queued work; drop-oldest evicts the oldest and
  counts it.
- Work past its deadline is cancelled at pickup and is not run.
- A slow fake dependency: memory, goroutines and queue depth stay bounded, and refusals rise.
- Shutdown: nothing new is accepted; queued work is drained or cancelled as the policy says; no
  goroutine is left (check the count).
- A worker panic reaches the parent and does not kill the pool silently.
- A model-based fuzz test: a script of enqueue, complete, slow down and shut down, compared with
  a plain model of what should be queued.
- Under load with a fault on the dependency, before calling the component done.

## Smells

- `make(chan T, 1000000)` as a capacity plan.
- `go handle(item)` inside a request or consume loop.
- A full-queue behaviour that is not written down.
- "Accepted" returned before the work is durable or even bounded.
- No queue age metric.
- An outbound call with no deadline.
- A retry loop inside a worker with no budget.
- Scaling up while the dependency's p99 is already high.
