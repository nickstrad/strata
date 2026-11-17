# Production readiness

What is worth taking from Michael T. Nygard, *Release It! Design and Deploy Production-Ready
Software* (Pragmatic Bookshelf, 2007), for strata. Index: [README.md](README.md).

## Verdict

**About half of this book is already in the other sheets.** Its stability patterns are where
timeouts, circuit breakers, bulkheads, fail fast and steady state got their names. This sheet
does not repeat them. It holds what the book adds: how a process starts, stops, is configured,
is operated, is observed from outside, stays the same size over time, and is replaced by its
next version without downtime.

| Part of the book | For strata |
|---|---|
| Ch. 3: stability, impulse and stress, failure modes, crackstoppers | **Take the vocabulary and the habit**: design the failure mode. Below |
| Ch. 4: integration points, cascading failures, blocked threads, slow responses, unbounded result sets | Already covered: [rules.md §5](rules.md), [backpressure.md](backpressure.md), [circuit-breakers-and-retries.md](circuit-breakers-and-retries.md), [concurrency-patterns.md](concurrency-patterns.md) |
| Ch. 4: chain reactions, scaling effects, unbalanced capacities, self-inflicted load, SLA inversion | **New rules below.** The other sheets touch them only in passing |
| Ch. 5: timeouts, circuit breaker, bulkheads, fail fast, test harness | Already covered. Three faults are added to the adapter fault table; see Tests |
| Ch. 5: steady state, handshaking | Steady state is one line in rules.md; **expanded below**. Handshaking is **new** |
| Ch. 7–10: capacity | Take two ideas: one constraint sets capacity, and pools and caches are bounded. Skip the rest (HTML size, sessions, JSP, garbage collector flags) |
| Ch. 11–12: network interfaces, least privilege, configured passwords | **New rules below** |
| Ch. 13: availability requirements | **New**: availability is stated per feature and measured from outside. Skip the load balancer and cluster product survey |
| Ch. 14: configuration, start-up and shutdown, administrative interfaces | **New rules below** |
| Ch. 17: transparency | Logging levels, message codes and the metric lists are already in rules.md §3 and §5. **New**: logs are written for the operator, and a probe outside the process |
| Ch. 17: SNMP, JMX, CIM, the operations database | Skip. Dated tooling |
| Ch. 18: releases without downtime | **New, and the largest gap in our sheets**: two versions run at once |
| Ch. 18: enterprise architecture, dependency injection, object design | Skip |

What the book does **not** cover, and strata needs: correctness under concurrency and failure.
The book keeps a system up; it does not prove that a write is not lost. That is the work of
[distributed-algorithms.md](distributed-algorithms.md),
[object-storage.md](object-storage.md) and [simulation-testing.md](simulation-testing.md).

## The ideas worth keeping

- **Feature complete is not production ready.** Tests show that the code does what was asked.
  They do not show that it survives a slow dependency, a month of uptime, or its own upgrade.
- **Impulse and stress.** An *impulse* is a sudden shock: ten thousand connections in a minute, a
  node that dies. A *stress* is a force that stays: a dependency that is slow all afternoon.
  A design answers both.
- **Design the failure mode.** Every system has failure modes. If you do not choose them, you get
  the ones that emerge. Decide which features must survive, and put a *crackstopper* between
  them and each thing that can fail.
- **Failures are not independent.** A slow dependency makes memory pressure more likely, which
  makes a crash more likely. "The chance of all three is tiny" is wrong when the first causes the
  second.
- **Unlikely events happen daily at volume.** Do not dismiss a failure because it needs a
  coincidence.
- **Longevity.** A process runs without hand-holding for at least the time between two deploys.
  The two things that end a long run are leaks and data growth, and short tests find neither.
- **Every time a person touches production is a chance for an error.** The system cleans up
  after itself, and what an operator must do is one scripted command.

## Decide before you build

| Question | Notes |
|---|---|
| Which features must keep working when each dependency is down? | Write the list. It sets where the crackstoppers go. |
| What is the availability target of each feature, and which dependencies are on its path? | A feature cannot be more available than the product of its hard dependencies. |
| How is "available" measured? | A probe from outside, with a time limit and a definition of a good answer. |
| What does this component accumulate, and what removes each thing? | One row per accumulator; see the table below. |
| What must be true before it accepts work? | The start-up checks, in order. |
| How does it stop, and how long may that take? | Drain, with one budget. |
| Which settings change per environment, and which are secrets? | Kept apart from wiring, and from each other. |
| What can an operator change without a restart? | Limits, breaker and retry settings, log level. |
| Which formats and protocols does it read or write, and how is each versioned? | Needed before the first release, not the second. |
| What happens when a node of this kind dies? | Where its load goes, and whether the survivors can take it. |

## Rules

**Failure modes**

- **Each design names its crackstoppers**: for each dependency and each shared resource, what
  stops its failure from reaching the features on the "must survive" list.
- **A feature's availability is at most the product of the availabilities of the dependencies
  it cannot work without.** Five hard dependencies at 99.9% give 99.5% at best. To do better,
  remove a dependency from the path: cache, queue, or degrade.
- **State availability per feature, not for "the system"**, and say how it is measured: the
  probe, how often, from where, the time limit, what counts as a good answer.
- **Do not promise more than the worst hard dependency gives.**

**Load moves when a node dies**

- **A dead node's load lands on the survivors.** One of eight gone is 15% more load on each of
  the rest; one of two gone is double. Size for the loss of a node at peak.
- **If the cause was in the load, it travels with the load.** A leak or a crash triggered by one
  workload repeats on the next node that receives that workload. Moving work off a failed node
  is rate limited, and a workload that has taken down a node more than once is held back, not
  moved again.
- **Recovery is a load of its own.** Reloading what the dead node held competes with serving. It
  runs in its own bounded pool ([backpressure.md](backpressure.md)).

**Scale changes the shape**

- **Zero, one, many.** Anything that is "many" in production is at least two in tests. A design
  that is correct one-to-one can fail one-to-many.
- **Count the fan-in.** For each dependency: callers × in-flight calls per caller, at the largest
  planned size. Compare it with what the dependency can serve. If the callers scale and the
  dependency does not, the callers hold a limit.
- **Connections between every pair of processes grow with the square of the count.** Say how far
  a point-to-point design is meant to go.
- **Stress both sides of an interface.** As the server: ten times the highest expected demand of
  the most expensive operation. Does it refuse and recover, or fall over? As the caller: the
  server stops answering.
- **One constraint sets capacity.** Find it with a load test: it is where throughput stops
  following demand. A metric of anything else does not predict capacity.

**Self-inflicted load**

- **Nothing makes every process act at the same moment.** A periodic refresh, a cache expiry, a
  key rotation, a reconnect after a dependency returns: each has jitter.
- **A cache flush is rate limited.** Flushing everything at once sends the full load to the
  dependency the cache protected.
- **A shared, single resource has a fallback.** Say what callers do when it is slow or gone.

**Handshaking**

- **A protocol we design lets the receiver say "not now".** The answers "busy", "draining" and
  "not ready yet" are part of the protocol, are distinct from a failure, and are cheap to send.
- **A caller treats "not now" as a refusal**: the work did not run, and the breaker does not
  count it ([circuit-breakers-and-retries.md](circuit-breakers-and-retries.md)).
- A breaker is what a caller uses when the other side cannot say "not now". Prefer the signal
  where we own both sides.

**Steady state**

- **Each thing that accumulates has a named remover, in the same change that adds it.** "Add
  purging later" is how the first release ships without it.

  | Accumulates | Removed by |
  |---|---|
  | Data on disk or in object storage | A cleanup that the application runs, because only it knows what is still referenced |
  | Rows in a database | A purge written with the feature, tested against the code that reads the table |
  | Entries in a cache or a per-key map | A size limit, and expiry or invalidation |
  | Log files | Rotation by size, and a cap on the total |
  | Connections, goroutines, timers | A lifetime: idle timeout, context, stop |

- **Two questions for every cache**: is the set of possible keys bounded, and can the cached
  value change? Unbounded keys need a size limit. A value that can change needs invalidation or
  an expiry. Do not cache what is cheap to make or changes more often than it is read.
- **A failure to write a log line never fails the request, and is never itself logged in a
  loop.** A full disk must not become an outage. Count dropped log lines.
- **No routine needs a person to log in.** If a restart or a manual cleanup is part of normal
  running, that is a defect to fix.

**Start-up**

- **Accept no work until start-up has finished.** Order: read and validate the configuration,
  build the components, check what the process cannot work without, then open the listener for
  traffic.
- **A start-up that cannot finish is announced.** Bad configuration: exit with the usage code
  and a message that names the setting. A dependency that is not there yet: stay up, not ready,
  and say why on the admin endpoint and in one log line. A stopped process cannot be asked what
  is wrong.
- **Start-up work is bounded and has jitter**, so a fleet that restarts together does not arrive
  at a dependency together.

**Shutdown**

- **Stop in order**: stop accepting, tell callers "draining", finish or cancel what is in
  flight, flush what must be durable, close. The whole sequence has one budget
  ([rules.md §5](rules.md)).
- **A drained process has handed off cleanly**: nothing it acknowledged depends on memory it is
  about to lose.
- **A crash is the other shutdown.** Start-up after a crash and start-up after a drain run the
  same recovery code. A clean stop is an optimisation, never a requirement for correctness.

**Configuration**

- **Settings that differ per environment are separate from wiring.** An operator can never
  break how components are connected by editing a setting.
- **Name a setting for what it is used for**, not for its type: `log_brokers`, not `hosts`.
- **Secrets are separate from other settings**, come from their own source, are never logged,
  never in an error message, and never in a metric label.
- **Settings that must be the same on every instance are separate from those that differ**, and
  each instance reports a version or hash of what it loaded, so drift is visible.
- **All configuration is validated at start-up**, as input ([rules.md §2](rules.md)).
- **Limits and thresholds can be changed at run time** without a restart, and each change is
  logged with the old and the new value.

**Administration**

- **Every operator action is a command or an API call.** If it cannot be scripted, it will not
  be done the right way under pressure.
- **Admin, health and metrics listen apart from tenant traffic**: their own listener and their
  own bounded capacity, so a flood of tenant work cannot hide the process from its operators.
- **Bind to the address the configuration names.** Not to every interface by default.
- **Restart the smallest part.** A stuck pool, breaker or per-tenant component can be reset by
  an operator without restarting the process and losing everything else it holds.

**Least privilege**

- No process needs root. Each component has its own identity and only the permissions it uses.
- A credential is scoped to what its holder does: a component that only reads a store holds a
  read-only credential.

**Transparency**

- **Logs are written for the operator, not for the author.** A message says what happened, what
  the system did about it, and whether a person must act. "Reset required" with no subject sends
  someone to reset the wrong thing.
- **No debug logging in production configuration.**
- **A process cannot report that it is dead or hung.** Each feature with an availability target
  has a synthetic probe that runs from outside, as a marked test caller, so its data can be told
  apart from real data.
- **Local views hide fleet problems.** The same metric from every instance can be seen side by
  side.
- **Expose state; keep policy outside.** Thresholds and alert rules are not in the code
  ([rules.md §5](rules.md)).

**Releases**

- **Two versions always run at once during a deploy.** Version N and N+1 share every store,
  every log and every connection between them. A change is designed for that overlap.
- **Every format that outlives a process and every protocol between processes carries a version
  from the first release.**
- **Readers before writers.** A reader accepts the new version before any writer produces it. A
  process that meets a version it does not know fails loudly on that item; it never guesses.
- **Change in three steps: expand, roll out, clean up.** Expand: add the new field, format or
  column so that the old code still works. Roll out: deploy the code. Clean up: remove the old
  form and add the constraints the old code would have broken. Each step can be a separate
  deploy, and each can be rolled back.
- **Schema changes follow the same steps.** Add a column as nullable; add `not null` and foreign
  keys in the clean-up. Name columns in every statement ([rules.md §7](rules.md)).
- **Planned downtime is downtime.** A deploy is routine, automated, and needs no window.
- **Do not ship to meet a date** when the checks have not passed.

## In strata

- **Features that must survive, and what they need.** Serving a loaded tenant needs the gateway,
  the owner, Valkey, and for writes Redpanda. It must not need object storage, Postgres or the
  control plane. Loading a tenant needs object storage and Redpanda. Control requests need
  Postgres. The availability target of each is **(not set yet)**; the write path can never be
  better than Redpanda.
- **Synthetic probe**: a reserved tenant that writes and reads a key through the gateway, from
  outside. How it is marked and kept out of usage data is **(not set yet)**.
- **A data node dies.** Its tenants are reloaded on other nodes. That is a burst of restores
  against object storage and Redpanda, and more memory on the survivors. Reassignment is paced
  by the control plane and loads run in the bounded load pool. Headroom per node for the loss of
  one node is **(not set yet)**.
- **A tenant that kills its node.** If one tenant's data or commands crash an owner, moving the
  tenant moves the crash. Reassignment needs a limit on how often a tenant is moved after its
  node failed, and an answer for what the tenant sees once it is held back. Both are
  **(not set yet)**.
- **Fan-in to Redpanda and to an owner**: data nodes × in-flight appends, and gateways ×
  in-flight commands per owner. Both are budgets in the design that adds a node type or changes
  a limit.
- **Refreshes with jitter**: gateway route and limit caches, signing keys, the flusher's
  schedule, reconnects to Redpanda after it returns.
- **Handshaking between gateway and owner.** This protocol is ours. It carries "busy" (mailbox
  full), "draining", "not the owner" and "tenant loading" as distinct answers, none of which
  counts against the gateway's breaker. The wire form is **(not set yet)**.
- **Accumulators.** Each needs its remover in the design that creates it:

  | Accumulates | Removed by |
  |---|---|
  | Redpanda log | The flusher, then retention below the checkpoint |
  | Segments in object storage | Compaction into snapshots, then cleanup |
  | Orphaned objects | Cleanup after the grace window ([object-storage.md](object-storage.md)) |
  | Tenants loaded in a node's memory | Unloading idle tenants: **(not set yet)** |
  | Client connections to a gateway | Idle timeout and a cap per tenant: **(not set yet)** |
  | Gateway caches (routes, limits, keys) and limiter keys | A size limit and expiry |
  | Postgres rows (ownership history, epochs, retired tenants) | A purge per table: **(not set yet)** |
  | Objects of a deleted tenant | Tenant deletion: **(not set yet)** |
  | Logs | Rotation, or stdout to a collector; never an unbounded file |

- **Start-up of an owner.** A node starts empty, so "ready" means "can load a tenant", not "has
  tenants". Start-up after a crash and after a drain are the same code: restore, then replay.
  The order of the start-up checks is **(not set yet)**.
- **Drain of an owner**: answer "draining", finish the commands in the mailboxes, wait for the
  log acks, give up ownership, exit. Nothing is flushed from memory: the log already has it. How
  ownership is handed back and the budget are **(not set yet)**.
- **Versioned from the first release**: the log record, the segment and snapshot formats, the
  checkpoint, the gateway–owner protocol, the token claims, the control plane API and the
  Postgres schema. A restore must read segments written by an older flusher for as long as they
  exist. How many versions back a reader supports is **(not set yet)**.
- **Deploy order** follows readers before writers: restore and replay code first, then the
  flusher and the owner's append path. The order across components is **(not set yet)**.
- **Credentials**: the gateway holds none. The flusher writes object storage; an owner only
  reads it for restore. Whether they get separate credentials is **(not set yet)**.
- **Admin listener** on every process, separate from the tenant port, serving health, metrics,
  the loaded configuration version and the run-time settings.

## Measure

Uptime of the process and the version and configuration hash it runs; time from start to ready;
drain duration against its budget; for each accumulator, its size and the age of its oldest
item; cache size against its limit, hit rate and evictions; dropped log lines; the synthetic
probe's success and latency per feature; the count of distinct versions running; items refused
for an unknown format version. Labels stay bounded.

Alert when:

- an accumulator grows over a period in which load did not
- the probe fails while every process reports healthy
- more than one version is running for longer than a deploy takes
- the same node set keeps restarting after receiving the same workload

## Tests

- Start-up: with a dependency missing the process stays up, is not ready, accepts no tenant work
  and says why; with bad configuration it exits with the usage code and names the setting.
- Shutdown: new work is refused with "draining"; in-flight work finishes or is cancelled inside
  the budget; no goroutine is left; nothing acknowledged is lost.
- Crash at any step of a drain, then start: the same state as after a clean drain.
- Each "not now" answer is distinct, does not run the work, and does not count against the
  caller's breaker.
- Each cache stays at its limit under many distinct keys, and a changed value is not served past
  its expiry.
- A log sink that fails or blocks does not fail or block a request.
- A secret does not appear in logs, errors or metrics (search the captured output).
- **Soak**: steady low load for hours with a quiet period in the middle. Memory, goroutines,
  connections and every accumulator end where they started. The quiet period finds idle
  connections that were dropped silently.
- **Mixed versions**: the previous release and the new one run together, in the simulation where
  the feature is simulated. Old readers meet new data only after the expand step; a reader that
  meets an unknown version refuses that item and nothing else.
- Format round trip: bytes written by the previous release are committed as test vectors and
  read by the current code.
- A migration runs against a database that the previous release is still using.
- At least two of every multi-instance component in simulation and e2e tests.
- Kill a node under load: the survivors stay inside their limits and the reloads are paced.
- Added to the adapter fault table in [rules.md §8](rules.md), from the book's test harness:

  | Fault | Expected |
  |---|---|
  | connection never accepted (sits in the listen queue) | fails at the connect timeout |
  | reply much larger than expected | cut off at the size limit, nothing partial kept |
  | well-formed reply of the wrong protocol or type | a protocol error, not a parse panic |

## Smells

- "We will add cleanup after launch."
- A map used as a cache with no size limit.
- A restart or a manual purge on a schedule.
- A process that takes traffic while it is still starting.
- A process that exits on a missing dependency, restarts, and exits again.
- Shutdown that is only tested as `kill -9`.
- One file that holds both wiring and environment settings; a setting named `host`.
- A secret in a log line or a core dump.
- An operator action that exists only as a sequence of clicks or a wiki page.
- Health and metrics on the tenant port.
- A format with no version field; a reader that skips what it does not understand.
- A deploy that needs every instance to change at the same moment.
- An availability number for "the system".
- A test topology with one of everything.
- Every instance refreshing on the same second.
- A log message that does not say who has to act.
