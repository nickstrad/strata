# Distributed algorithms

How to tell when a piece of strata is a distributed algorithm, and the terms to specify it in.
The terms are those of Cachin, Guerraoui and Rodrigues, *Introduction to Reliable and Secure
Distributed Programming* (2nd ed., Springer, 2011). Index: [README.md](README.md).

Most strata code is not a distributed algorithm. It calls one: Redpanda, Postgres or a
conditional write in object storage. The danger is the code in between, where we write one
without noticing. This page makes that moment explicit and gives it a fixed vocabulary, so a
design can say "this needs uniform agreement" and everyone means the same thing.

## Are you writing a distributed algorithm?

Answer these for every feature. **One "yes" means: stop, say so in the design, and write a module
specification (below) before any code.**

1. Do two or more processes have to **agree** on something: who owns a tenant, which write came
   first, whether an operation happened?
2. Does correctness depend on what **another process did, or will do**, when all we have are
   messages that may be lost, delayed, repeated or reordered?
3. Must something stay true **across a crash and a restart**: an acknowledged write, a decision,
   "exactly once"?
4. Does one process act because it believes **another process has failed**?
5. Is there a **hand-over**: a tenant moves, an owner is replaced, a flusher takes over?
6. Does one logical change touch **two stores or two processes** and need to be all-or-nothing?
7. Is anything **ordered** across processes: commands, log records, epochs?
8. Does a process act on a **copy** of state that another process owns: a cached route, a cached
   key, a cached limit?

Not a distributed algorithm: a pure function, one process with local state, a single call to a
dependency whose guarantee you rely on as given.

**The first move is always to reduce, not to invent.** Ask which existing abstraction the problem
is, and whether something strata already runs provides it:

| Need | Provided by | We write |
|---|---|---|
| Consensus / compare-and-swap | Postgres; a conditional write in object storage | The reduction to one compare-and-swap |
| Total order of a tenant's writes | A Redpanda partition | The use of it, and its fencing |
| Durable state across a crash (stable storage) | Redpanda, object storage, Postgres | What is stored, and when |

**strata does not implement consensus, total-order broadcast or a failure detector of its own.**
If a design seems to need a new one, that is a finding to raise, not a task to start.

## Vocabulary

Use these words with these meanings in designs, doc comments and reviews.

**Processes and failures**

- **Process**: one running participant (a gateway, an owner, the flusher, the control plane).
- **Correct / faulty**: a process is *correct* if it never fails in the run being considered;
  otherwise *faulty*. Properties say what correct processes get.
- **Crash-stop**: a process halts and never returns. **Crash-recovery**: it may halt and later
  resume, having forgotten everything not in **stable storage**. **Omission**: it drops messages.
  **Arbitrary (Byzantine)**: it may do anything, including lie.
- **Stable storage**: what survives a crash. A process `store`s to it and `retrieve`s on recovery.

**Timing**

- **Asynchronous**: no bound on delays. **Synchronous**: known bounds. **Partially synchronous**:
  bounds hold eventually, but nobody knows when. Real networks are the last.

**Links**

- **Fair-loss**: a message sent often enough gets through. **Stubborn**: it is delivered again
  and again. **Perfect** (reliable delivery, no duplication, no creation): exactly once, from
  retransmission plus duplicate elimination. **Logged perfect**: the same, across crashes.
  **FIFO**: in send order. **Authenticated**: the sender cannot be forged.

**Knowledge of failures**

- **Perfect failure detector (P)**: never wrong. Needs a synchronous system.
  **Eventually perfect (◇P)**: may suspect a live process, and eventually stops being wrong.
  **Eventual leader detector (Ω)**: eventually everyone trusts the same correct process.
- **Suspecting is not knowing.** With ◇P or Ω, a "dead" process may be alive and still acting.

**Models** (a process abstraction + a link abstraction + a failure detector)

| Model | Processes | Links | Failure information |
|---|---|---|---|
| Fail-stop | Crash-stop | Perfect | P |
| Fail-noisy | Crash-stop | Perfect | ◇P or Ω |
| Fail-silent | Crash-stop | Perfect | None |
| **Fail-recovery** | Crash-recovery, with stable storage | Stubborn | Ω |
| Fail-arbitrary | Byzantine | Authenticated perfect | Byzantine leader detector |
| Randomized | Any | Any | Uses random choices; holds with a probability |

**Properties**

- **Safety**: nothing bad ever happens. It can be broken at a point in time, and never repaired.
  **Liveness**: something good eventually happens. It can only be broken by waiting forever.
  Every property in a specification is one or the other; say which.
- **Uniform**: the property also binds processes that later crash. *Uniform agreement*: no two
  processes decide differently, **whether correct or faulty**. Regular agreement lets a process
  decide, tell a client, crash, and be contradicted by the survivors.
- **Quorum**: a set of processes such that any two quorums share a member. A majority is one.
- **Epoch**: a period with one leader, named by a **timestamp** that only rises.

**Abstractions** (the book's catalogue; name the one you mean)

| Abstraction | Guarantees, in short |
|---|---|
| Best-effort broadcast | Delivered by all correct processes if the sender is correct |
| Reliable broadcast | All correct processes deliver, or none does |
| Uniform reliable broadcast | The same, counting processes that crash after delivering |
| FIFO / causal broadcast | Delivery order respects send order / cause before effect |
| **Total-order broadcast** | Every process delivers the same messages in the same order |
| Regular register | A read returns the last written value, or one being written |
| **Atomic register** | Reads and writes appear to happen one at a time (linearizable) |
| **Consensus** | Termination, validity, integrity, agreement on one value |
| Epoch-change | Processes start epochs with rising timestamps and agree on each epoch's leader |
| Epoch consensus | Consensus inside one epoch, with **lock-in**: a value decided in an earlier epoch is never contradicted by a later one |
| Non-blocking atomic commit | All commit or all abort, across participants |
| Group membership / view synchrony | Agreement on who is in the group, and on what each view delivered |

## strata's model

State this in a design, and say where the feature differs.

- **Fail-recovery, partially synchronous.** Every process may crash and return. What it must not
  forget is in stable storage: Redpanda, object storage, Postgres. Valkey memory is not stable
  storage. Designs must name what is stored and **when, relative to the acknowledgement**.
- **Failure detection is ◇P at best.** A missed heartbeat means *suspected*. strata has no perfect
  failure detector, so every action taken because "that node is dead" must be safe if the node is
  alive. That is what fencing is for.
- **Not fail-arbitrary.** strata's own processes are trusted to follow the algorithm. Clients are
  not trusted, but that is input validation and authentication at the edge, not a Byzantine
  algorithm. Skip the book's Byzantine and randomized material unless the threat model changes.
- **Links.** TCP is not a perfect link across reconnects and restarts. Where a design needs "no
  duplication" across a retry, it must build it: a request id and duplicate elimination.

## Where strata meets these abstractions

| In strata | Abstraction | What to hold on to |
|---|---|---|
| Tenant ownership | **Epoch-change** | *Monotonicity*: a tenant's epoch only rises. *Consistency*: one owner per epoch. The compare-and-swap in Postgres provides both |
| A new owner takes over | **Epoch consensus, lock-in** | What the old owner had acknowledged must be kept by the new one: replay up to the fence before serving |
| A tenant's write log | **Uniform total-order broadcast** (Redpanda provides it) | *Uniform* is the point: a write acknowledged by an owner that then crashes must still be in the order everyone replays |
| Owner + Valkey applying the log | A state machine fed by that order | Same log, applied in order, deterministically, gives the same state. Non-deterministic commands break it |
| The manifest per tenant | **Atomic register**, updated by compare-and-swap | One writer per epoch; readers never see a half-published state |
| A gateway's cached route | A read of a register that may be **stale** | It is weaker than atomic by design; the owner's "not the owner" reply is what makes that safe |
| Heartbeats to the control plane | **◇P** | Suspicion only. Never a proof of a crash |
| Retried commands | **Perfect links**: no duplication | Needs a request id; at-least-once delivery alone duplicates |
| Moving a tenant (control plane, two owners, object storage) | Looks like **atomic commit** | Do not build one. Make it one compare-and-swap plus idempotent steps that any process can finish |

## How to specify one

Write the module the way the book does, in the design, before code.

```
Module:
  Name: TenantOwnership, instance to.

Events:
  Request:    ⟨to, Acquire | tenant⟩      A node asks to own tenant.
  Indication: ⟨to, Granted | tenant, epoch⟩   The node owns tenant in epoch.
  Indication: ⟨to, Revoked | tenant, epoch⟩   The node no longer owns tenant.

Properties:
  TO1 Monotonicity (safety):   epochs granted for a tenant only rise.
  TO2 Single owner (safety):   no two nodes are granted the same (tenant, epoch).
  TO3 Uniform lock-in (safety): a write acknowledged in epoch e is in the state every
                               owner of a later epoch serves.
  TO4 Fenced past (safety):    after Granted(tenant, e), no write of an epoch below e
                               is acknowledged.
  TO5 Eventual ownership (liveness): if nodes stop failing, some correct node is
                               eventually granted the tenant and keeps it.

Model:  fail-recovery, partially synchronous, ◇P from heartbeats.
Uses:   compare-and-swap (Postgres); uniform total-order broadcast (Redpanda partition);
        atomic register (tenant manifest).
```

(The example shows the form. It is not the agreed specification of ownership.)

Rules for a specification:

1. **Name the abstraction** from the catalogue, or say plainly that it is a new one.
2. **Events**: requests in, indications out. Nothing else crosses the boundary.
3. **Properties**: numbered, named, each marked *safety* or *liveness*, and each stating whether
   it is *uniform*.
4. **Model**: process failures, links, timing, failure detector.
5. **Uses**: the lower abstractions it relies on, and what provides each one in strata.
6. **Stable storage**: what is stored, and whether before or after each indication.
7. **Algorithm**: as handlers, `upon event ⟨…⟩ do`. In Go this is one goroutine reading a mailbox
   (see [concurrency-patterns.md](concurrency-patterns.md)); each handler runs to completion.
8. **Argue each property** in a sentence or two, from the properties of what it uses. An argument
   that needs "the other node is surely dead by now" is using P, which strata does not have.

## Tests

Each property in the specification gets a test that could fail. The simulation that runs them
is described in [simulation-testing.md](simulation-testing.md).

- **Safety**: checked after every step of a model-based fuzz or a deterministic simulation whose
  script includes **crash, recover, lose, delay, repeat and reorder a message, and a wrong
  suspicion**. A safety property must hold in every run, including the unfair ones.
- **Liveness**: checked as "within a bound, once the faults stop". Never assert liveness while
  faults are still being injected.
- **Uniform properties**: crash the process right after it produces the indication, and check the
  survivors agree with what it said.
- **Recovery**: crash between every pair of steps that touch stable storage. The classic bug is
  acknowledging before storing.
- **The zombie**: pause a process, let another take over, resume the first. It must not be able
  to do anything a correct owner's property forbids.
- Use injected clocks and seeded randomness so a failing run replays exactly.

## Smells

- "This can't happen unless the node is dead."
- A timeout treated as proof of a crash.
- Two stores updated in sequence and described as atomic.
- "Exactly once" with no request id and no duplicate elimination.
- An acknowledgement sent before the write is in stable storage.
- A property written without saying whether it binds processes that later crash.
- A design that needs a new agreement protocol.
- State kept only in Valkey memory that a later step assumes survived.
