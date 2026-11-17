# Deterministic simulation testing

How strata finds distributed bugs before production. Researched 2026-11-16 from the projects
listed at the end. Index: [README.md](README.md).

**This is meant to drive the project, not to be added later.** Not every feature needs it, but
every feature is asked the question, and the code is written from the first commit so that the
answer can be yes.

## What it is

Run the real code of several strata processes inside one test process, with everything that is
not deterministic replaced by something the test controls: time, randomness, the network, the
dependencies, and crashes. One **seed** decides the whole run: the workload, every fault and
every delay. Then:

- A failure **replays exactly** from its seed and commit. No "cannot reproduce".
- Simulated time costs nothing, so minutes of testing cover days of timeouts, retries and
  flushes.
- Faults that take months to meet in production (a reply lost at the wrong moment, a paused
  process that wakes after a takeover) are met thousands of times a night.
- It finds **combinations**. A fuzz test with one fault per step does not find "the reply was
  lost *and* the re-read failed"; a long seeded run does.

It only finds what something checks. Simulation without assertions and a checker is a slow way
to run the happy path.

## Does this feature go in the simulation?

Ask it for every feature, in its design. The default is **yes** when any of these is true:

- An answer to the eight questions in [distributed-algorithms.md](distributed-algorithms.md) is
  yes.
- It decides something from time: a timeout, a retry, a lease, a flush interval, a breaker.
- It reads or writes stable storage (the log, object storage, Postgres) or recovers from it.
- It takes part in ownership, ordering, hand-over or fencing.
- It has a queue, a mailbox or a background loop whose timing can interleave with requests.

It is **no** for: a pure function (table tests cover it), an adapter to a real service (the
contract suite and the fault harness cover it; see Limits), command-line wiring, formatting.

A "no" is written down with its reason, like any other sheet that does not apply.

## Rules for all code, from day one

These cost little now and cannot be added afterwards without a rewrite. That retrofit is what
pushed other Go projects to patched runtimes and WebAssembly builds.

1. **No wall clock.** No `time.Now`, `Since`, `After`, `NewTimer`, `NewTicker`, `Sleep`. Take an
   injected clock.
2. **Deadlines are on that clock too.** No `context.WithTimeout` or `WithDeadline`. A simulated
   "now" with real-time contexts is incoherent, because code compares the two.
3. **No ambient randomness or ids.** No package-level `math/rand`, no `crypto/rand`, no uuid
   package. Take an injected random source and an id generator.
4. **Order never comes from a map.** Where order can change behaviour or output, sort the keys.
   This is the most common leak in every Go project surveyed.
5. **No outcome decided by which goroutine ran first.** One goroutine per actor with a mailbox;
   no `select` whose result depends on which of several ready cases wins; fan-in is ordered.
6. **Worker counts can be set to 1**, so the simulation can remove parallel interleaving.
7. **Decisions are pure functions** of their inputs (already a rule in
   [rules.md §1](rules.md#1-structure-domain-vs-integration)). The more logic is a step function
   `(state, event) → (state, effects)`, the less the simulation has to control.
8. **Every dependency is behind a port** that strata owns, with a fake that takes the clock and
   has fault switches.
9. **Assertions stay on** in simulation and crash the run.
10. **Logs carry no wall-clock field that the trace compares.**

The clock, random and id seams, their fakes and a lint test that enforces rules 1 to 3 on every
package by default (with a short, reasoned exempt list) are built with the first feature that
needs them. Until then the rules hold by review. Real adapters (the Redpanda, object storage and
Postgres clients) are exempt: they run on real time by nature.

## Why Go needs this discipline

Go's scheduler, `select` and map iteration are not deterministic, and nothing in the standard
library or any maintained tool gives seed-replayable goroutine interleavings.

- `testing/synctest` gives a fake clock and a way to wait until every goroutine is blocked. It
  does **not** order goroutines, and a mutex or a real socket stalls it. It is a clock and
  quiescence tool, and a useful part of a simulator, not a simulator.
- `GOMAXPROCS=1` does not give determinism. `-race` shuffles scheduling at random, which is
  worth running always and replays nothing.
- Source rewriters and runtime patches exist. They are experimental, pinned to old Go versions
  or need a forked toolchain.
- A deterministic hypervisor (Antithesis) needs no code changes and has a Go SDK. It costs from
  about $3,000 a month. It is an addition for later, not a substitute.

So in Go, **exact replay comes from architecture and from a test that proves it**.

## The shape of the simulator

```
seed ─► named random streams ─► knobs · workload · fault schedule
                                        │
   clients ─► simulated network ─► gateway ─► owner ─► fake log (Redpanda)
                (delay, loss,                 │   └──► Valkey stand-in
                 duplicate, partition)        ▼
              control plane ─► fake store (Postgres)   flusher ─► fake object storage
                                        │
                     one event loop on one simulated clock ─► trace ─► checker
```

**The loop.** One thing happens per step:

1. Let every goroutine run until all are blocked (quiescence).
2. The checker looks at the state. The step's trace lines are written.
3. Pick the earliest of: the clock's next timer, the next scheduled event (a crash, a restart, a
   partition, a message delivery). Ties break by a fixed rule.
4. Advance the clock to it and fire exactly that one thing. Repeat.

The order of effects is then the order of events on the clock, not the scheduler's.

**Randomness.** One seed is split into **named streams**: one per client, per tenant, per fault
class, per link. A stream never depends on another's draws. Turning one fault class off, or
adding a draw in one place, then leaves every other schedule unchanged, and old seeds stay
useful. A class that is off makes no draws.

**The network.** A call is two messages on the clock, the request and the reply. Each can be
delayed, lost or delivered twice, and a partition loses both directions or one. A request whose
caller gave up **still lands and runs**. A process killed while serving never sends its reply.

**Fakes.** Fake the port strata owns, not the wire protocol.

| Port | The fake must | Faults |
|---|---|---|
| Log (Redpanda) | Keep one total order per tenant; be linearizable | Append fails; append applies and the reply is lost; slow; unavailable for a period |
| Object storage | Honour create-if-absent and compare-and-swap exactly | Read or write fails; write applies and the reply is lost; a write **lands late**, after its caller gave up; stall; outage |
| Control plane store (Postgres) | Be a linearizable compare-and-swap that refuses an epoch going down | Unavailable; slow; a notification lost or late |
| Valkey | Apply commands in order | Apply fails; process dies and loses everything |

Every fake waits on the simulated clock, so a stall makes real deadlines fire inside it.

**Crashes.** A crash first cuts a **gate**: from that instant every call the dead process makes
to stable storage fails with no effect. Then its contexts are cancelled. A restart builds a new
process that has only what was in stable storage. A crashed process's in-flight writes may still
land afterwards: that is the zombie, and it is on by default.

**Faults are scheduled by a nemesis**, each class on its own stream: partition, kill then restart
or replace, move a tenant, create a tenant mid-run, storage outage, control plane outage, cache
loss.

**Knobs come from the seed too** (swarm testing): the number of nodes, tenants and clients, the
flush interval, batch sizes, queue capacities, timeouts, and which fault classes are on and at
what rate. Correctness must not depend on tuning, and a third of runs with a class turned off
reach states the others never do.

## Fault rules

- **Inject both failures of every external call**: "failed, nothing happened" and "happened, the
  reply was lost". The second is the unknown outcome of an append or a write, and the bugs are
  there.
- **Bound faults to what the design claims to survive.** A run that destroys every copy proves
  nothing; its failure is noise.
- **Do not be too nice.** Faults that always heal by themselves hide livelocks. Make some
  failures permanent.
- **Be fine-grained.** A lost reply, a late write, a single stale read. Coarse faults miss what
  fine ones find.
- **Damp or stop faults late in the run**, so that recovery is exercised and liveness can be
  judged.
- **Fault points in the code** (the BUGGIFY idea) are allowed where a stub cannot reach: a
  helper that is always false outside simulation and, inside it, is enabled per site per run,
  then fires with a probability. Use it to return an error from something that normally
  succeeds, to add a delay, or to shrink a limit to its minimum.

## What is checked

Each of these is a property from a design's module specification
([distributed-algorithms.md](distributed-algorithms.md)).

| When | Property |
|---|---|
| Every answer | No write is applied twice; "duplicate" is reported only for a write an earlier attempt may have applied; a refused write was not applied |
| Every read | Every acknowledged write is present; nothing unknown; nothing that every answer said did not happen; commit order holds |
| Every step | One owner per (tenant, epoch); epochs only rise; a new manifest extends the last one and is a prefix of the history |
| A node starts serving a tenant | Its state holds every write acknowledged so far. strata acknowledges after the log append, so **no acknowledged write may be lost by any crash or takeover** |
| End of the run | The same against the final state; the client history is **linearizable** (a checker such as Porcupine) |
| After faults stop | **Liveness**: every tenant is owned and serving within a bound |

Rules for the checker:

- **Unknown outcomes stay unknown.** A write that timed out is "maybe", and "maybe" is sticky for
  that request id. A later attempt, or an earlier one landing late, may apply it. The client
  that got the timeout is handled as the linearizability literature requires: its operation has
  no finish time.
- **Judge by commit time, not by when the client heard.**
- **Marks.** Each write leaves its request id in the data, so the checker can read any stored
  state and say which writes it holds and how often.
- **Liveness is tested explicitly**: heal a set of nodes, freeze the remaining faults, and
  require convergence within a bound. Never assert liveness while faults are still arriving.
- **A checker needs teeth.** For each property there is a deliberately broken variant (a
  mutant: duplicate detection off, the fence skipping its final step) that the simulation must
  catch within a few seeds. A property no mutant can break is not being tested.
- **Expect checker bugs.** When a seed fails, suspect the model first. Published projects report
  as many false violations from the checker as real ones early on.
- **Coverage probes**: a mark in the code that a named test or a run count must reach. They show
  that rare branches are met, and that a fault class has any effect.

## Determinism is itself tested

A test runs the same seeds twice and compares a hash of the full trace, with and without
`-race`. When it fails, a rule above was broken; find the leak before trusting any other result.
Leaks that this test has caught in practice: plans made in map order; several requests woken
together racing to one actor (fixed by letting one through per step, lowest arrival first);
periodic loops started in the same step creating their timers in scheduler order (fixed by a
random phase before each); two goroutines writing trace lines in one step (fixed by one trace
stream per goroutine, sorted within a step).

## Running it

- **On every change**: a few fixed seeds per simulation, plus the determinism test. Seconds.
- **Swarm**, nightly or continuous on `main`: thousands of fresh seeds with scaled fault rates,
  a time budget per run.
- **A failure prints**: the seed, the knobs it drew, the violated property, the last trace lines
  and **the exact command that replays it**. Seed plus commit is the identity of a run.
- **Shrink before debugging**: turn the drawn schedule into an explicit script, cut the run to
  just past the first violation, delete script steps by halves, turn off fault classes one at a
  time, cut clients and tenants. Keep a change only while the run fails **in the same failure
  class**, so the shrinker does not wander to a different bug.
- **Keep the shrunk case** as a saved vector that a test replays forever. Move it from "open" to
  "fixed" with the fix.

## Limits, and what covers them

| Not covered by simulation | Covered by |
|---|---|
| The real client libraries and their timeouts | The adapter contract suite run three ways and the fault harness ([rules.md §8](rules.md#8-testing-what-every-change-needs)) |
| A fake that drifts from the real service | **The same contract suite runs against the fake and the real service** |
| A crash in the middle of a step | Model-based fuzz of the component; crash-point tests |
| Performance and capacity | Load tests |
| The real processes and their wiring | A small end-to-end suite on the compose stack, with process kills |
| What no workload generates | Review of the workload against the API; coverage probes |

Simulation also does not replace the lower levels. Table tests and a model-based fuzz of one
component are faster and point closer to the bug. The simulation is where components meet.

## What the surveyed projects contribute

| Project | Idea taken |
|---|---|
| FoundationDB | Everything behind interfaces from day one; in-code fault points; swarm testing; faults tuned to keep the state space wide |
| TigerBeetle | Seed + commit as identity; faults bounded to the recoverable; the liveness mode with a healed core; state checkers outside the system; assertions always on |
| Resonate (Go server, to v0.7) | In Go, do not rely on goroutine scheduling; run each seed twice and diff; check against both a fake and the real store |
| S2 | Timed-out operations as indefinite in the linearizability check; a meta-test for determinism; the object-storage and log shape strata shares |
| RisingWave | Fake dependencies at the client API, not the wire; a few seeds per change and an unbounded daily run; adding tests alone stops finding bugs, so tune the workload |
| Cassandra | Checkers have bugs too |
| etcd/raft, LifeRaft | The algorithm as a pure step function with I/O left to the caller |
| Faultline, RaftSim | Named random streams; a disabled fault makes no draws; re-run a failure and compare trace hashes |
| Ananke, RaftSim | A deliberately broken variant for every check |
| Turmoil, MadSim | The fault vocabulary: partition, one-way partition, hold and release, latency, loss, kill, restart, pause |

## Tests the simulation itself needs

- Same seed, same trace hash, twice, with and without `-race`.
- One failing history per checker property (the checker's own table tests).
- Each mutant is caught.
- Every saved vector replays and passes.
- The lint catches a file that breaks every seam rule.

## Smells

- `time.Now` "just for a log line" inside a package that decides something.
- A fake that sleeps in real time.
- A fault class that can never fire with the default knobs.
- A seed that fails once and passes on replay.
- A property with no mutant.
- A linearizability check that is switched off when faults are on.
- Faults that all heal before the run ends.
- A failure message without its replay command.
- "We will add simulation once the feature works."
