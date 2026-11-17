# NNNN: <feature name>

| | |
|---|---|
| Status | Draft / Agreed / Implemented |
| Round | 1 |
| Components | <gateway, owner, flusher, control plane, …> |
| Review | <Waiting for review of round N / Reviewed> |

## 1. What and why

<Two to five sentences: what this adds or changes, and why now.>

**In scope:** <…>
**Out of scope:** <…>

## 2. Architecture and behaviour

### 2.1 C4 elements worked on

Which parts of the diagrams in [docs/diagrams/](../diagrams/README.md) this feature touches.
Name the box or arrow as it is labelled in the diagram.

| Level | Diagram | Element (box or arrow) | This feature |
|---|---|---|---|
| Context | [01-system-context.md](../diagrams/01-system-context.md) | | Unchanged / Uses / Implements / Changes / Adds / Removes |
| Container | [02-containers.md](../diagrams/02-containers.md) | | |
| Component | <03 gateway / 04 data node / 05 flusher / 06 control plane> | | |
| Dynamic | [07-dynamic-flows.md](../diagrams/07-dynamic-flows.md) | <which flow, which steps> | |

A level with nothing touched says "Unchanged".

**Diagram changes this design proposes:** <each box, arrow, label or step to add, change or
remove, and in which file. "None" if the diagrams already show it; then delete the "Proposed
diagrams" part below.>

**Proposed diagrams.** One remade diagram per diagram file that changes: the whole diagram as it
would look, not a fragment, so it can be reviewed by eye. New elements use the `added` class,
changed ones `changed`; removed elements are left out of the drawing and listed under it. The
files in docs/diagrams/ are replaced with these when the design is agreed, not before.

#### <02-containers.md> as proposed

```mermaid
flowchart TB
    %% Copy the current diagram from docs/diagrams/<file>, apply the changes, then mark them:
    %%   class newBox added
    %%   class changedBox changed
    %% Keep the existing classDef lines and add these two:
    classDef added fill:#2e7d32,stroke:#1b5e20,color:#ffffff,stroke-width:3px
    classDef changed fill:#ef6c00,stroke:#e65100,color:#ffffff,stroke-width:3px
```

Green: added. Orange: changed. **Removed:** <elements taken out, or "none">.
**Explanation text to change under the diagram:** <which paragraphs or table rows of the diagram
file's explanation change, and to what.>

**Open design questions it touches:** <numbers from the "Open questions" list in
docs/diagrams/README.md, and whether this design answers each one.>

### 2.2 Behaviour

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
| [production-readiness.md](../coding-style/production-readiness.md) | Yes / No | <start-up and drain, accumulators, settings and secrets, formats and versions> |
| [distributed-algorithms.md](../coding-style/distributed-algorithms.md) | Yes / No | <see section 4> |
| [simulation-testing.md](../coding-style/simulation-testing.md) | Yes / No | <see section 6.1; the day-one rules apply either way> |
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

### 3.7 Production readiness ([production-readiness.md](../coding-style/production-readiness.md))

- **Must survive:** <which features keep working when each dependency is down; the crackstopper for each>
- **Node loss:** <where this component's load goes when an instance dies; what paces the recovery>
- **Accumulators:** <each thing that grows, and what removes it; cache limits and expiry>
- **Start-up:** <the checks before accepting work; what happens when one fails>
- **Shutdown:** <the drain order and its budget; what a crash at each step leaves behind>
- **Settings:** <per-environment settings, secrets, what changes at run time>
- **Operator actions:** <each one, as a command or API call>
- **"Not now" answers:** <busy, draining, not ready: how each is carried and what the caller does>
- **Formats and protocols:** <each one read or written, its version field, what an unknown version does>
- **Release steps:** <expand, roll out, clean up for this change; what runs mixed and for how long>

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

### 6.1 Simulation

From [simulation-testing.md](../coding-style/simulation-testing.md). Decide this first; the
other levels are chosen around it.

**In the deterministic simulation? Yes / No.** <Why. The default is yes when section 4 has a
"yes", or the feature decides from time, touches stable storage, takes part in ownership,
ordering or hand-over, or has a queue or background loop.>

<If No, delete the rest of 6.1. The day-one rules below still apply.>

- **Processes in the run:** <which strata processes, how many of each>
- **Fakes needed:** <each port, what its fake must guarantee, new or existing>
- **Workload:** <operations the simulated clients send; the mark each write leaves so the checker
  can find it>
- **Faults:** <per dependency: fails / applied but reply lost / lands late / stall / outage;
  network: delay, loss, duplicate, partition; process: crash, restart, zombie, takeover>
- **Knobs drawn from the seed:** <node, tenant and client counts; intervals, batch and queue
  sizes, timeouts; fault classes and rates>
- **Fault bounds:** <what the design claims to survive, so faults stay inside it>
- **Checked after every step:** <safety properties from section 4, by number>
- **Checked at the end:** <history checks; linearizability; how unknown outcomes are treated>
- **Liveness:** <what must converge once faults stop, and within what bound>
- **Mutants:** <for each property, the deliberately broken variant the simulation must catch>
- **Determinism risks:** <maps iterated, goroutines woken together, loops started together; how
  each is ordered>
- **New code this needs:** <seams, fakes, simulator parts not built yet. They are built with
  this feature.>

**Day-one rules** (every feature, simulated or not): <confirm no wall clock, no
`context.WithTimeout`, no ambient randomness or generated ids, no order from a map or from
goroutine scheduling, worker counts settable to 1; list any justified exception.>

### 6.2 Levels

| Level | For this feature | Proves |
|---|---|---|
| Spec tables (partitions, on and off points) | | |
| Structural (uncovered blocks reviewed) | | |
| Fakes with fault switches + contract suite (fake and real) | | |
| Model-based fuzz / property | | |
| Deterministic simulation (see 6.1) | | |
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

## 7. Findings

What working through the design turned up, for the reviewer to check. One row each; do not leave
a finding only in the chat.

| # | Finding | Kind | Where it came from | What the design does about it |
|---|---|---|---|---|
| 1 | | Risk / Conflict with a diagram / Conflict with a sheet / Smell / Gap in the docs / Assumption / Fact checked | <sheet and section, diagram, kb entry, code> | <decision, open question #, or "accepted"> |

## 8. Alternatives

<One line each: what was considered and why it was not chosen.>

## 9. Open questions

| # | Question | Blocks implementation? | Owner |
|---|---|---|---|
| 1 | | Yes / No | |

## 10. Review

**How to review this round:** <which sections changed and what most needs a decision.>

Reviewer comments go here (or inline as `> REVIEW: …`). Each is answered in the next round and
kept, so the record shows why the design changed.

| # | Round | Section | Comment | Resolution |
|---|---|---|---|---|
| 1 | | | | |

## Change log

| Round | Date | What changed |
|---|---|---|
| 1 | YYYY-MM-DD | First draft |
