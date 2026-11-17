# NNNN: <feature name>

| | |
|---|---|
| Status | Draft / Agreed / Implemented |
| Round | 1 |
| Components | <gateway, owner, flusher, control plane, …> |
| Diagrams | <links into docs/diagrams/> |

## 1. What and why

<Two to five sentences: what this adds or changes, and why now.>

**In scope:** <…>
**Out of scope:** <…>

## 2. Behaviour

<What the feature does, as the caller sees it. Requests in, answers out, and what is promised
about each answer. Include what a refused or failed request receives.>

## 3. Coding style that applies

Every sheet is listed. A "No" has a reason.

| Sheet | Applies? | Why, and what this feature must decide |
|---|---|---|
| [rules.md](../coding-style/rules.md) | Yes | <domain packages, ports, error modules, integration points to add to §5> |
| [rate-limiting.md](../coding-style/rate-limiting.md) | Yes / No | <fairness key, placement, what a limited caller gets> |
| [backpressure.md](../coding-style/backpressure.md) | Yes / No | <queues, full-queue policy, wait budget, workers, shutdown> |
| [circuit-breakers-and-retries.md](../coding-style/circuit-breakers-and-retries.md) | Yes / No | <dependencies called, what is retryable, unknown outcomes> |
| [concurrency-patterns.md](../coding-style/concurrency-patterns.md) | Yes / No | <goroutines, shared state, locks and their order, bounded concurrency> |
| [object-storage.md](../coding-style/object-storage.md) | Yes / No | <objects written, manifest, fencing, cleanup> |
| [distributed-algorithms.md](../coding-style/distributed-algorithms.md) | Yes / No | <see section 4> |
| [go-testing.md](../coding-style/go-testing.md) | Yes | <see section 6> |

Each sheet marked Yes gets its subsection below, filled in with this feature's decisions and a
link to the rule each one comes from. Delete the subsection of a sheet marked No.

### 3.1 Structure and errors ([rules.md](../coding-style/rules.md))

- **Packages:** <domain packages (no I/O) and adapters; what each owns>
- **Ports:** <interfaces the domain defines, and what implements each>
- **Pure decisions:** <the functions that decide, tested with tables>
- **Validation at the edge:** <what is input here, where it is validated>
- **Contracts:** <pre/post/invariants worth asserting; any checked wrapper>
- **Errors:** <error module names; which failures are unavailable / bug / bad input>
- **New integration points:** <rows to add to rules.md §5>

### 3.2 Rate limiting ([rate-limiting.md](../coding-style/rate-limiting.md))

- **Fairness key:** <and where it comes from>
- **What is protected; protective or contractual:**
- **Placement:** <before which expensive work; what is checked first>
- **Algorithm and shape:** <token bucket rate and burst; any concurrency cap; separate limits for expensive operations>
- **State:** <local or shared; maximum keys and eviction; behaviour if the limiter's state is unavailable>
- **Over the limit:** <the reply, the retry hint, the promise that refused work did not run>
- **Changing limits at run time:**

### 3.3 Backpressure ([backpressure.md](../coding-style/backpressure.md))

- **What stays bounded when a dependency slows:**
- **Queues:** <each queue: what it holds, capacity and how it was derived, one per kind of work>
- **Full-queue policy:** <refuse new / drop oldest / wait with a bound / cancel, and why>
- **Admission point:** <before which expensive work; for a consumer loop, when it stops pulling>
- **Queue wait budget:** <caller deadline − service time − margin; what happens to work past it>
- **Workers:** <count, what it is sized from, per process or per tenant or per dependency>
- **Replicas:** <what the total concurrency becomes with N processes>
- **Shutdown:** <drain, cancel or refuse>
- **What "accepted" means:** <durable, or admitted in memory>

### 3.4 Circuit breakers and retries ([circuit-breakers-and-retries.md](../coding-style/circuit-breakers-and-retries.md))

| Dependency and operation | On request path? | Deadline | Idempotent? | Retried by | Breaker open means |
|---|---|---|---|---|---|
| | | | | | |

- **Retryable errors:** <explicit list; what counts against the breaker and what is an answer>
- **Unknown outcomes:** <for each write that can time out: how it is resolved>
- **Backoff and budget:** <starting values to validate>
- **Readiness and liveness:** <what they check; no dependency health>

### 3.5 Concurrency ([concurrency-patterns.md](../coding-style/concurrency-patterns.md))

- **Goroutines:** <each long-lived goroutine: owner, how it stops>
- **Shared state:** <each piece: actor, mutex or atomic snapshot; the invariant the lock covers>
- **Lock order:** <if two locks are ever held; otherwise "one lock at a time">
- **Bounded concurrency:** <each counted slot and its size>
- **Blocking points:** <each one selects on the context>
- **Fairness:** <where one tenant could starve another, and what prevents it>

### 3.6 Object storage ([object-storage.md](../coding-style/object-storage.md))

- **Objects and keys:** <each kind of object, its key, how the key is computed; no LIST on the request path>
- **Publish order:** <data first, then which pointer; what a reader sees after a crash in between>
- **Conditional writes:** <which writes are create-if-absent or compare-and-swap>
- **Fencing:** <the token, and every separately written structure it guards>
- **Position with data:** <where the log offset is stored relative to the data it covers>
- **Integrity:** <checksums and what a failed check does>
- **Cleanup:** <what may be deleted, the grace period, the upload-to-publish gap>
- **Batching and cost:** <object size target, maximum wait>
- **Backend assumptions:** <features relied on, and how each backend is checked>

## 4. Distributed algorithm check

**Is a distributed algorithm being written? Yes / No.**

| # | Question | Answer |
|---|---|---|
| 1 | Must two or more processes agree on something? | |
| 2 | Does correctness depend on what another process did or will do, over messages? | |
| 3 | Must something stay true across a crash and a restart? | |
| 4 | Does a process act because it believes another has failed? | |
| 5 | Is there a hand-over? | |
| 6 | Does one change touch two stores or processes and need to be all-or-nothing? | |
| 7 | Is anything ordered across processes? | |
| 8 | Does a process act on a copy of state another process owns? | |

<If every answer is No, say why in one line and delete the rest of this section.>

**Abstraction:** <from the catalogue> **Provided by:** <Redpanda / Postgres / conditional write / this feature>

```
Module:
  Name: <Name>, instance <id>.

Events:
  Request:    ⟨id, … | …⟩      <meaning>
  Indication: ⟨id, … | …⟩      <meaning>

Properties:
  X1 <name> (safety | liveness; uniform | regular): <statement>
  X2 …

Model:  <fail-recovery, partially synchronous, ◇P, …; say where it differs from strata's>
Uses:   <lower abstractions, and what provides each>
```

**Stable storage:** <what is stored, where, and whether before or after each indication or
acknowledgement.>

**Algorithm:** <handlers, `upon event ⟨…⟩ do …`. Round 1 may give an outline.>

**Why each property holds:** <one or two sentences per property, from the properties of what it
uses. Round 1 may leave this for the spec round.>

**Crash points and the zombie:** <what happens on a crash between each pair of steps that touch
stable storage; what a paused old process can and cannot do after a takeover.>

## 5. Component design checklist

From [coding-style/README.md](../coding-style/README.md). "Not applicable" needs a reason.

1. **Callers and fairness key:**
2. **What is protected; what stays bounded when a dependency slows:**
3. **What a refused caller gets, and should do next:**
4. **Promise: refused work did not run? accepted work is durable, or only admitted?**
5. **Deadlines, per unit of work and per outbound call:**
6. **Retries: what is safe, who retries, the budget:**
7. **Per dependency: what users see while it is down:**
8. **Shutdown: drain, cancel or refuse:**
9. **Signals: what shows the protection working, and failing:**
10. **Tests that force each answer above:** see section 6.

## 6. Testing approach

| Level | For this feature | Proves |
|---|---|---|
| Spec tables (partitions, on and off points) | | |
| Structural (uncovered blocks reviewed) | | |
| Fakes with fault switches + contract suite | | |
| Model-based fuzz / property | | |
| Deterministic simulation (crash, recover, lose, delay, repeat, reorder, wrong suspicion) | | |
| Adapter integration, incl. fault harness | | |
| Concurrency (`-race`, many workers on one key) | | |
| End to end (real processes, compose stack) | | |
| Under load with faults | | |

A level that is not used says "Not used" and why.

**Traceability.** Every decision in section 3, every property in section 4 and every answer in
section 5 maps to a test.

| Decision, property or answer | Test | Level |
|---|---|---|
| 3.3 Full-queue policy | | |
| 3.4 Unknown outcome of <write> | | |
| X1 | | |
| Checklist 4 | | |

**Test plan** (filled in the test round): each test's name, level, input or fault, oracle, and
the property it proves.

## 7. Alternatives

<One line each: what was considered and why it was not chosen.>

## 8. Open questions

| # | Question | Blocks implementation? | Owner |
|---|---|---|---|
| 1 | | Yes / No | |

## Change log

| Round | Date | What changed |
|---|---|---|
| 1 | YYYY-MM-DD | First draft |
