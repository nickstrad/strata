# Coding style

How strata code is designed, written and tested. One line per doc; open only what you need.

| Doc | Read it when |
|---|---|
| [rules.md](rules.md) | Before you plan or write Go code. The short rules and the done checklist. |
| [rate-limiting.md](rate-limiting.md) | A component takes requests from tenants or other callers. |
| [backpressure.md](backpressure.md) | A component has a queue, a worker, a mailbox or a consumer loop. |
| [circuit-breakers-and-retries.md](circuit-breakers-and-retries.md) | A component calls anything over the network. |
| [concurrency-patterns.md](concurrency-patterns.md) | A component has goroutines that share state or wait for each other: the Go form of each pattern, lock ordering, starvation. |
| [object-storage.md](object-storage.md) | A component reads or writes object storage: manifests, conditional writes, fencing, cleanup, and what SlateDB and OpenData do. |
| [distributed-algorithms.md](distributed-algorithms.md) | **Every feature**: the eight questions that tell you whether you are writing a distributed algorithm. If yes: the vocabulary and the module specification form to use. |
| [simulation-testing.md](simulation-testing.md) | **Every feature**: whether it goes in the deterministic simulation, the rules all code follows so that it can, the simulator's shape, the fault model, what is checked. |
| [production-readiness.md](production-readiness.md) | A component is a process that starts, stops, is configured, is operated or is upgraded; or it adds something that accumulates, a format or a protocol: failure modes, steady state, start-up and shutdown, configuration, admin, releases with two versions running. |
| [authentication.md](authentication.md) | A component issues, carries or checks a token or a credential: the control plane's issuer, the gateway's verifier, any login. |
| [go-coding-style.md](go-coding-style.md) | You need detail or a template: layout, contracts, `errs`, `logx`, the Result pattern. |
| [go-testing.md](go-testing.md) | You write tests: spec tables, coverage, fuzzing, contract suites, fakes, e2e. |

`go-coding-style.md` and `go-testing.md` are the house guides, copied in unchanged. Do not edit
them for strata; strata's own rules go in the other files.

## Simulation drives the project

Deterministic simulation testing is how strata looks for distributed bugs before production:
the real code of several processes in one test, on a simulated clock, with faults and crashes
chosen by a seed that replays exactly. Not every feature needs it. Every feature is asked, and
all code follows the day-one rules in [simulation-testing.md](simulation-testing.md) so the
answer can be yes. The simulator and its supporting packages are built with the features that
need them, not ahead of them.

## Resilience and testing are part of the design

They are not a hardening pass at the end. When you design or build a component, work through the
resilience sheets (and the concurrency and object-storage sheets where they apply) and write the tests they name in the same change. The sheets are not
exhaustive; they are the questions to ask so that overload and failure have a decided answer
instead of an accidental one.

## How the patterns fit together

Each pattern guards a different boundary. They are not interchangeable, and the order matters.

| Pattern | Boundary | Question it answers | Healthy sign under stress |
|---|---|---|---|
| Rate limiting | The caller or tenant | May this caller use another unit of capacity? | Refusals start while the system is still healthy |
| Backpressure | This process: admission and execution | Can this process accept more work right now? | Bounded queue, visible refusals, flat memory |
| Bulkhead | A resource shared by workloads | Can one workload use up another's capacity? | One workload saturates alone |
| Circuit breaker | A call to a dependency | Should we keep calling something that is failing? | Fast local failure, the dependency gets room to recover |
| Retry with backoff | One failed attempt | Is another attempt safe and still useful? | Bounded retry volume, inside the deadline |

```
caller → rate limit → admission (backpressure) → bulkhead → circuit breaker → bounded retry → dependency
```

Every arrow needs a deadline. A missing piece shows up as a specific failure:

- Retries without backpressure multiply local work.
- A bounded queue without a breaker keeps feeding a dependency that is already failing.
- A breaker without a rate limit still lets one noisy tenant use all the admission capacity.
- Autoscaling without any of them adds callers to a dependency that is the real bottleneck: more
  pressure, not more capacity.

## Where they apply in strata

| Component | Rate limiting | Backpressure | Breakers and retries |
|---|---|---|---|
| Gateway | Per tenant, after the token check; a cheap guard before it for bad tokens | Bounded in-flight work per owner | A breaker per data node; no blind retry of writes |
| Owner | Per-tenant caps inside the node | Bounded tenant mailbox; a limit on tenant loads | Redpanda (append and replay), object storage (restore) |
| Flusher | Not needed | Pulls at its own pace; bounded batches; tracks the oldest unflushed write | Redpanda, object storage; retry is the next run |
| Control plane API | Per caller on the public API | Bounded pools for Postgres | Postgres; each data node for ownership calls |

## Component design checklist

Answer these in the design, then prove each one with a test.

1. **Callers.** Who calls this, and what identifies them for fairness?
2. **Capacity.** What does this protect, and what stays bounded when a dependency slows down?
3. **Over the limit.** What does a caller get when work is refused, and what should it do next?
4. **Promise.** Is refused work guaranteed not to have run? Is accepted work durable, or only
   admitted in memory?
5. **Deadlines.** What is the deadline of each unit of work and of each outbound call?
6. **Retries.** Which operations are safe to retry, who retries them, and what is the budget?
7. **Dependency down.** For each dependency: what do users see while it is down?
8. **Shutdown.** How does it stop: drain, cancel or refuse? What is the budget?
9. **Signals.** Which numbers show the protection working, and which show it failing?
10. **Accumulation.** What does it accumulate, and what removes each thing?
11. **Start.** What must be true before it accepts work, and what does it do when that fails?
12. **Versions.** Which formats and protocols does it read or write, and what happens while the
    previous release and the new one run together?
13. **Tests.** Which tests force each of the answers above to happen?
