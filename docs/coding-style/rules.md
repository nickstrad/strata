# Coding style for strata

Read this before you plan or write Go code. It is the short version: the rules, with strata's
own names. Where a section links to a fuller doc, that doc wins on detail.

Rules that need a design decision strata has not made yet are marked **(not set yet)** instead of
being given a made-up value.

| Topic | Full doc | Covers |
|---|---|---|
| House Go style | [go-coding-style.md](go-coding-style.md) | layout, domain vs integration, contracts, errors, logging, concurrency, with templates |
| Testing | [go-testing.md](go-testing.md) | test levels, spec tables, coverage, fuzzing, contract suites, fakes, e2e |
| Rate limiting | [rate-limiting.md](rate-limiting.md) | fairness keys, placement, algorithms, the caller contract |
| Backpressure | [backpressure.md](backpressure.md) | bounded queues, full-queue policy, queue age, workers |
| Simulation testing | [simulation-testing.md](simulation-testing.md) | the day-one rules, when a feature is simulated, faults, checks |
| Distributed algorithms | [distributed-algorithms.md](distributed-algorithms.md) | when you are writing one, the terms, the specification form |
| Object storage | [object-storage.md](object-storage.md) | immutable data and a pointer, conditional writes, fencing, cleanup |
| Concurrency patterns | [concurrency-patterns.md](concurrency-patterns.md) | the Go form of each pattern, lock ordering, starvation |
| Breakers and retries | [circuit-breakers-and-retries.md](circuit-breakers-and-retries.md) | breaker states, what to retry, backoff, unknown outcomes |
| Production readiness | [production-readiness.md](production-readiness.md) | failure modes, steady state, start-up and shutdown, configuration, admin, versioned formats, deploys with two versions |
| Architecture | [../diagrams/README.md](../diagrams/README.md) | what the parts are and how they talk |

Shared packages that implement the rules: `internal/assert` (contracts), `internal/errs`
(well-formed errors), `internal/logx` (JSON logs, log IDs, the top-level reporter).

## 1. Structure: domain vs integration

- **Domain packages decide; they do no I/O and do not log.** No `net`, `net/http`, `os`,
  `database/sql`, Kafka, Valkey or S3 clients, and no `slog` in them. They reach the world through
  small interfaces they define (ports).
- **Decisions are pure functions.** For example: classify a command as read or write, plan which
  log records go in a segment, pick a data node for a tenant. A thin layer around them does the
  I/O. Test the pure part with tables.
- **Adapters are thin.** The Redpanda, Valkey, object-storage and Postgres adapters translate,
  validate, wrap errors and log. No business rules.
- **Wire only in `cmd/`.** `main` calls `realMain(ctx, args, stdout, stderr) int`. Exit 0 ok,
  1 expected error with a log ID, 2 usage, 70 bug, 130 interrupted.
- Standalone SQL lives in `.sql` files, embedded with `//go:embed`.
- No package-level mutable state; no `utils` or `models` packages; a `doc.go` names each package's
  role and its error module.

Full: [go-coding-style.md](go-coding-style.md) §1–2.

## 2. Validation vs contracts

- **Validate once at the edge** (config loaders, handlers, adapters) and return errors. **Never
  assert on input**: a client command, a token, a log record read back and an object read back are
  all input.
- **Contracts are for our own bugs**: `assert.That` panics. Write them in doc comments: `pre:`,
  `post:`, `Invariant:`. Run `invariant()` after mutations, never on reads; guard O(n) checks with
  `if assert.Enabled`.
- **Checked wrappers** on interfaces any future adapter could break.
- Never put assertions in a `defer` that also runs while a panic unwinds: the assertion fires
  first and hides the real panic.
- Each assertion must be able to fail in some test. Both builds pass: default and `-tags noassert`.

Full: [go-coding-style.md](go-coding-style.md) §3.

## 3. Errors and logging

- **Wrap once at the package boundary**:
  `errs.Wrap(module, err, "what failed; what changed; whether retry is safe")`. `Error()` is
  `message: cause`; never `%v` the cause into your message.
- **Sentinels with `errors.Is`, typed errors with `errors.As`.** Never branch on message text.
- **Three error classes, never mixed**: a dependency is unavailable (Redpanda, object storage,
  Postgres, a data node) → tell the client to retry later, WARN, sampled; a bug → internal error
  with a log ID, ERROR; bad input → a client error. A dependency outage is never reported as a
  bug: that pages someone with thousands of "bugs", and clients do not back off.
- **Log once, at the top or in the adapter**: `logx` JSON, UTC, log ID, whole chain, origin stack.
  Do not log and return. One stable message code per operational event.

Full: [go-coding-style.md](go-coding-style.md) §4–5.

## 4. Concurrency

- Goroutines report `{result, err, panic}` to the parent; the parent sets the policy.
- Whoever starts a goroutine makes sure it can stop: a ctx, result channels buffered to the sender
  count, one closer, and every result drained after the first error.
- Recover panics inside goroutines and re-panic in the parent.
- **No slow I/O while holding a lock the request path takes.**
- **Waiting is not working**: if a caller gives up, the work it started is interrupted or bounded
  too.

- **If code holds two locks, every path takes them in the same order**; better, hold one at a
  time. Never call out (a callback, an adapter, a channel operation, I/O) while holding a lock.
- **Every blocking operation also selects on the context.**
- **No wall clock, ambient randomness or generated ids** in code that decides something: no
  `time.Now`/`After`/`Sleep`/timers, no `context.WithTimeout`/`WithDeadline`, no package-level
  `math/rand`, `crypto/rand` or uuid. Take an injected clock, random source and id generator.
  **Order never comes from a map or from which goroutine ran first.** These are the day-one
  rules of [simulation-testing.md](simulation-testing.md).
- **Limit concurrency with a counted slot** (a buffered channel or a weighted semaphore),
  acquired with the context.

Full: [go-coding-style.md](go-coding-style.md) §6; patterns, deadlock and starvation:
[concurrency-patterns.md](concurrency-patterns.md).

## 5. Integration points: timeouts, retries, backpressure

Every call that leaves the process and every queue follows these rules. Integration points are
where failures start, and a missing timeout is how they spread: a dependency's hang becomes ours.
This section is the summary. The reasons, the decisions to make and the tests to write are in
[rate-limiting.md](rate-limiting.md), [backpressure.md](backpressure.md) and
[circuit-breakers-and-retries.md](circuit-breakers-and-retries.md). Work through the component
design checklist in [README.md](README.md) when you design a component.

| Point | On the request path? | Who retries |
|---|---|---|
| Client → gateway | yes | the client |
| Gateway → owner | yes | **(not set yet)** |
| Owner → Redpanda (append) | **yes, on every write, before the ack** | **(not set yet)** |
| Owner → Valkey process | yes | nobody: local, fails the request |
| Owner → object storage (restore) | only when a node loads a tenant | the adapter, idempotent reads only |
| Owner → Redpanda (replay) | only when a node loads a tenant | the adapter |
| Flusher → Redpanda, object storage | no | the next flush |
| Gateway, owner, flusher → control plane | no: served from caches | the next refresh |
| Control plane → Postgres | control requests only | the caller, after a re-read |

A new integration point is a design change: add a row here.

**Timeouts**

- **Every remote call has a deadline, background work included.** `context.Background()` and
  ticker contexts are roots, not budgets: derive a per-call deadline from them.
- **Bound transfers by time as well as size**, with a stall timeout. A response-header timeout
  does not protect a body that stops halfway.
- **Deadlines shrink on the way down.** An inner timeout is less than the outer one minus the
  work left; never retry past the caller's deadline.
- **Every pool checkout and semaphore acquire takes the ctx.**

**Retries**

- **One retry layer per call chain, at the layer that understands the outcome.** Turn library
  retries off or down to one. Layered retries multiply.
- **Retry only what is safe.** A write whose outcome is unknown is resolved by re-reading, never
  by blindly sending it again. For strata the first case is an append to Redpanda that timed out:
  it may or may not be in the log.
- **Exponential backoff with full jitter, a cap on attempts, and the server's retry hint
  honoured.** Retries spend a windowed budget.
- **Prefer "queue and retry later" to "retry now"** for background work. The flusher is the model:
  a failed flush leaves the log in Redpanda for the next run.

**Bulkheads and backpressure**

- **Every queue is bounded, and a full queue sheds; it never blocks the caller.** This includes
  each tenant's mailbox in the owner.
- **Each dependency has its own concurrency limit**, sized to its measured knee, so one slow
  dependency cannot take slots another needs.
- **Caps nest: tenant ≤ data node.**
- **Reserve capacity for control.** Health, metrics and ownership calls never queue behind tenant
  commands.
- **Bound every result set and listing.**

**Circuit breakers**

- **One breaker per remote dependency.** Only system failures count (timeouts, connection errors,
  5xx); "not found" and bad input are answers.
- **Open means fail fast**, with a retry hint.
- **What an open breaker means for users is a decision, written down.** Redpanda is on the
  write-ack path by design, so Redpanda open means writes are refused; whether reads continue is
  **(not set yet)**. Object storage open: tenants already loaded are unaffected, loads wait, and
  the unflushed tail grows.

**Fail fast, steady state, health**

- **Check what you need before expensive work**: token, ownership, breaker state and queue room.
- **Everything that accumulates has a reaper at least as fast**: the Redpanda log → the flusher
  and retention; segments → compaction into snapshots.
- **Track the age of the oldest unfinished thing** (the oldest unflushed write). A flat line is
  the health signal.
- **Liveness is not readiness, and readiness exercises the real path.** A process is not pulled
  from service for a remote dependency's outage.
- **Shutdown has one budget.**

**Running in production**

The reasons and the tests: [production-readiness.md](production-readiness.md).

- **Accept no work until start-up has finished.** Bad configuration exits with the usage code; a
  missing dependency leaves the process up, not ready, and saying why.
- **A crash and a clean stop recover through the same code.**
- **Each thing that accumulates gets its remover in the same change**: caches have a size limit
  and an expiry.
- **Every stored format and every protocol between processes carries a version.** Readers are
  deployed before writers; an unknown version is refused, never guessed. Changes go expand, roll
  out, clean up, so the previous release and the new one can run together.
- **Nothing makes every process act at the same moment**: refreshes and reconnects have jitter.
- **Secrets are separate from other settings and never logged.** Admin, health and metrics
  listen apart from tenant traffic.

**Observability**

- Per integration point: requests by outcome class, a latency histogram in which requests that
  never finished count at their deadline, in-flight and its high-water mark, breaker state, last
  success. Per pool or queue: size, in use, high water, times full.
- Export counters; keep alert thresholds out of the code.
- ERROR means someone must act; WARN means degraded and self-healing. Log state transitions, not
  every refusal; count refusals.

Deadlines, limits and breaker thresholds per dependency: **(not set yet)**. Measure, then add a
defaults table here.

## 6. Object storage

Object storage is the source of truth, so these are correctness rules. The reasons, the
patterns and what SlateDB and OpenData do: [object-storage.md](object-storage.md).

- **One tenant owns one prefix**, built in one function. Compute names; no LIST on a request path.
- **Write data first, publish the pointer second, trust only the pointer.** The flusher writes
  segments, then the checkpoint; a restore reads only what the checkpoint names.
- **Data objects are create-only.** Never reuse a name that was tried.
- **Every write to the checkpoint is conditional and carries a fencing value** that only rises, so
  an old owner or flusher cannot overwrite a newer one. **No clocks in correctness.**
- **After a write whose outcome is unknown, re-read before deciding.**
- **Verify size and checksum on every read** used for a restore.
- **Cleanup never deletes what the current checkpoint names**, and deletes orphans only after a
  grace window.
- **Check every S3 backend and version before use.** Conditional writes are not equally safe
  everywhere. On SeaweedFS in particular, check them on the exact topology you run: several filers
  with separate stores may not make them atomic.

## 7. SQL (Postgres, the control plane)

- **Values are always bind parameters.**
- **The connection owner owns the transaction.**
- **Upserts use `on conflict`**, never "select, then insert".
- **Invariants live in the schema**: `not null`, `check`, keys, foreign keys with the referencing
  side indexed.
- **No hot counter rows**: compute aggregates with `group by`.
- **Set-based over loops.**
- **Layout**: one clause per line, explicit joins, explicit insert column lists, lowercase.
- **Migrations**: numbered, transactional files, never edited after they are applied.

## 8. Testing (what every change needs)

Full: [go-testing.md](go-testing.md).

1. **Spec tables** per partition, with the on and off points of every boundary.
2. **Structural**: read the uncovered blocks. Error branch → inject with a fake; impossible →
   assertion; dead → delete.
3. **Fakes with fault switches** in `<pkg>test` packages, and **one contract suite run against
   every implementation**. For an adapter that means three runs: the fake, the real service, and
   the real service through a fault harness, because an interface-level fake cannot find a missing
   socket timeout. Minimum faults per adapter:

   | Fault | Expected |
   |---|---|
   | connection refused | fails fast, reported as unavailable |
   | accepted, no reply | fails at the operation timeout |
   | headers, then stall | fails at the stall timeout, nothing partial kept |
   | very slow body | fails at the size-derived deadline |
   | 5xx or throttling | exactly one retry layer; the breaker counts it |
   | applied, reply lost | resolved by a re-read, not misreported |
   | truncated or corrupt body | a corruption error, nothing loaded |
   | half-open after idle | the stale connection is recycled, no hang |

   strata has no fault harness yet. It needs two: a TCP fault proxy and a misbehaving fake S3
   server.
4. **Model-based fuzzing** for anything stateful; commit failing inputs to `testdata/fuzz/`. The
   owner is the first candidate: a script of commands, crashes and restores, compared with a
   plain map.
5. **Deterministic simulation** where components meet: several processes on a simulated clock,
   faults and crashes from a seed, a checker after every step. The design says whether the
   feature is in it and why. See [simulation-testing.md](simulation-testing.md).
6. **Adapter integration tests** including failure paths and error wrapping, gated by an
   environment variable so `go test ./...` passes without the stack (`make infra-up` starts it).
7. **Concurrency**: `-race`; many workers on the same key for compare-and-set paths.
8. **SQL**: every `.sql` file has a golden-output test; each constraint has an off-point test.
9. **Timing**: assert attempt counts, not elapsed time; upper bounds have seconds of slack.
10. **Under load and over time**: fault modes during a load run before calling a component done.

## 9. Checklist before done

- [ ] Domain code does no I/O and does not log; wiring only in `cmd/`
- [ ] Input validated at the edge; contracts documented and asserted where impactful
- [ ] Errors wrapped once at the boundary; messages say what changed and whether retry is safe;
      the error class is right (unavailable / bug / bad input)
- [ ] The feature has an agreed design in `docs/designs/`
- [ ] The design says whether the feature is in the simulation, and why; the day-one rules in
      [simulation-testing.md](simulation-testing.md) hold in the code
- [ ] The eight questions in [distributed-algorithms.md](distributed-algorithms.md) are answered;
      if any is yes, there is a module specification and a test per property
- [ ] The component design checklist in [README.md](README.md) is answered, and each answer has
      a test
- [ ] Every remote call has a deadline; one retry layer; every queue bounded and shedding
- [ ] Object storage: names from one function, data before pointer, conditional and fenced
      checkpoint writes, re-read after an unknown outcome, checksums verified
- [ ] SQL: bind parameters, constraints in the schema, golden tests
- [ ] Tests per §8; `make check` passes (gofmt, `go vet`, `go test -race`, `go test -tags noassert`)
- [ ] Production readiness: start-up and drain tested; each accumulator has a remover; formats
      and protocols versioned; the previous release and this one can run together
- [ ] New integration point → a row in §5 and the matching contract test
- [ ] Architecture changed → `docs/diagrams/` updated; a durable finding → a kb entry
