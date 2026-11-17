# Object storage

Main points from *Object Storage as Infrastructure* (Steve Publications, 2026), plus what SlateDB
and OpenData do in practice (researched 2026-11-16), applied to strata. Index:
[README.md](README.md). The short rules are in [rules.md §6](rules.md#6-object-storage).

Object storage is strata's source of truth, so most of this page is about correctness, not speed.

## What you get and what you give up

| You get | You give up |
|---|---|
| Durability and scale with nothing to operate | Changing an object in place |
| Compute that is separate from data and can be thrown away | Fast single operations: a call takes tens to hundreds of ms |
| Atomic single-object writes; strong read-after-write | Cheap listing |
| Conditional writes: create-if-absent and compare-and-swap | Transactions across objects |

Every design on object storage is a way around the right-hand column. The cost model matters too:
you pay per request as well as per byte, so many small objects cost more than their size suggests.

## The patterns

**Immutable data, one mutable pointer.** Write data objects once and never change them. Keep one
small object (a manifest, or checkpoint) that says which data objects are current. Then:

- **Write data first, publish the pointer second, trust only the pointer.** A data object that no
  pointer names does not exist, however valid it looks.
- Readers start from the pointer, so they never see a half-published change. That gives
  atomicity across many objects from a single-object write.
- Caches of immutable objects never need invalidation.

**Conditional writes are the coordination primitive.**

- *Create if absent* (`If-None-Match: *`): two writers of the same key, exactly one wins.
- *Compare and swap* (`If-Match: <etag>`): overwrite only if nobody changed it since I read it.
- On a lost race, re-read and decide again. Bound the retries and back off with jitter.
- They are good for low-contention metadata. They are the wrong tool for a hot key that many
  writers update.

**Names are computed, not discovered.**

- Design keys around how objects are read. If you know the tenant and the sequence, you can build
  the key; you never search for it.
- **No LIST on a request path.** Listing is slow, paged, costs money and is not ordered on every
  backend. Keep it for cleanup, repair tools and cold start.
- Zero-pad numbers in names (20 digits) so name order is numeric order.
- A tenant's objects live under one prefix, built by one function.

**Fencing.** A lease or lock that only expires by time cannot stop a paused process that wakes up
and keeps writing. Correctness needs a **fencing token**: a number that only rises, given to each
new owner and checked on every protected write, so a stale owner's write is refused.

- If the lock protects data, fence. If it only avoids duplicate work, a plain lease is enough.
- **Fence every structure that is written separately.** A new epoch on the manifest does not stop
  an old owner writing to the log.
- A fenced process must notice and stop itself: check the epoch before every commit, and poll
  when idle.

**Ambiguous outcomes.** After a timeout the write may have happened. Never assume either way.

- Make the operation idempotent, or make the retry detectable: a fixed key and content, a
  create-if-absent at a known position, or a unique id stored with the object.
- On "already exists" after a retry, read the object back. It may be your own earlier attempt.
  Only if it is someone else's are you fenced.
- Retry transient errors (timeouts, server errors, throttling). Do not retry answers (not found,
  not authorised, bad request).

**Integrity.** Verify on every read used for a restore: a checksum per object or per segment,
size, and a magic number so a wrong file is rejected. A corrupt segment is skipped and reported;
it must not make the whole tenant unreadable silently.

**Cleanup.** Objects pile up: superseded data, objects from failed publishes, old pointers.

- Delete only what **no current pointer or snapshot names**, and only after a **grace period**.
- Mind the gap between "uploaded" and "named by the pointer": cleanup must not delete an object
  that is about to be published.
- Cleanup never writes the pointer.
- A snapshot is a saved copy of the pointer. The data is shared, not copied, so cleanup must
  treat snapshots as references.

**Latency and cost.**

- **Batch.** One object of many records, not many objects of one record. Aim for megabytes per
  object. A size target plus a maximum wait keeps a quiet tenant from waiting forever.
- The trade is direct: a shorter flush interval means lower latency and more PUTs.
- Use throughput through parallelism: multipart uploads, ranged downloads.
- One long-lived client with a connection pool. A new connection per call costs more than the
  call.
- Cache in tiers: memory, then local disk, then object storage.

**Tenants.** A prefix per tenant is simple and depends on the code being right. Add a second
layer the code cannot bypass: storage credentials scoped to the prefix, or a key per tenant.

**Backends differ.** Conditional writes, listing order, multipart limits and versioning edge
cases vary between S3 and S3-compatible stores, and between versions. Write down which features
strata depends on, and test each backend for them, under concurrency, before trusting it.

## What SlateDB and OpenData do

Two public projects that solve the same problem. Read their design docs before designing the
matching part of strata. Facts below are from their docs, RFCs and source as of 2026-11-16; both
are young and changing.

**SlateDB** (slatedb.io; Apache-2.0; Rust; v0.18, pre-1.0) is an embedded key-value storage
engine that keeps all its data in object storage. It is single-writer by design. It has a Go
binding, which is cgo over the Rust library.

- **Manifest**: each update creates the next numbered object (`manifest/<20 digits>`) with
  create-if-absent. The highest number is current. They rejected a mutable "current" pointer.
- **Write-ahead log in object storage**: numbered objects, flushed every 100 ms by default. A
  write is durable only after that flush, so durable writes take the flush interval plus a PUT
  (tens of ms). Their own figure: a 100 ms interval costs about $130 a month in PUTs per writer.
- **Writer fencing, with no lease and no clock**: a new writer raises the epoch in the manifest,
  then creates an empty object in the next log slot. The old writer's next log write hits
  "already exists" and it closes itself. Whatever the old writer wrote **before** that slot is
  kept and replayed, never discarded.
- **Unknown outcomes**: each conditional write carries a unique id in the object's metadata, read
  back on "already exists" to tell "my retry" from "fenced".
- **Cleanup**: deletes only objects that no manifest or checkpoint names and that are older than
  a minimum age. Two bugs they wrote up are worth knowing:
  - *Create-if-absent forgets deleted names.* A stalled writer can re-create a manifest number
    that cleanup already deleted and believe it committed. Their fix is a low-watermark that only
    rises, which a writer checks after its create.
  - *A data object uploaded but not yet named* was deleted by cleanup. They call it an ordering
    problem, not a clock problem.
- **Idle cost**: finding the latest manifest by LIST made an idle database cost real money. They
  now remember the last number and probe the next one with a GET.
- **A log in front**: their draft "pluggable WAL" design says object-store writes are too slow
  for some uses and lets a faster log stand in, with Kafka as the example. Its rule: after the
  first write of a new epoch to the manifest or the log, no older epoch may write to either, and
  everything the old epoch left unflushed is replayed before serving. That is strata's design.

**OpenData** (opendata.dev; MIT; Rust; early) is a family of databases built on SlateDB: a
time-series store, a log, a vector store.

- Two acknowledgement levels, stated as fundamental to the design: *buffered* (in memory, at risk
  until the next flush) and *durable* (after the log reaches object storage).
- One single-threaded loop orders all writes and tracks three positions: applied, flushed,
  durable. They adopted it after real synchronization bugs.
- **No replicated log in front.** For fast ingest without Kafka they write batch objects and
  append their locations to one manifest with compare-and-swap. Their own numbers: about 0.5 s
  median and 2 s p99 end to end, and throughput that falls as more writers contend for the one
  manifest.
- Exactly-once needs the sink to store the data **and the position it came from** in one atomic
  step.

## In strata

Decisions these sources point to. Items marked **(not set yet)** are open.

- **A manifest per tenant** is the checkpoint: it names the tenant's snapshot and segments and
  records **the Redpanda offset they cover, in the same object**. Restore reads the manifest,
  loads what it names, and replays the log from the next offset. Data and position can then never
  disagree.
- **Publish by creating the next numbered manifest with create-if-absent.** Segments are written
  first, under names no reader will find by itself.
- **One manifest per tenant, not one for the platform.** A tenant has one owner and one flusher,
  so its manifest sees no contention; a shared one would cap throughput.
- **Fence both the log and object storage.** A new owner's epoch must stop the old owner from
  appending to Redpanda and stop a stale flusher from publishing a manifest. How the epoch is
  enforced on the Redpanda side is **(not set yet)**; it is the "two owners" open question in
  [the diagrams README](../diagrams/README.md).
- **Keep what the old owner logged before the fence.** Those writes were acknowledged to clients.
  A new owner replays up to the fence point, then serves.
- **Redpanda is why strata can be fast.** Without a log in front, a durable write waits for an
  object-storage PUT. With it, the flusher can batch for seconds and write megabyte objects.
- **Bound the restore.** Flush a tenant when its unflushed log passes a size, as well as on a
  timer, and track the age of the oldest unflushed write.
- **Redpanda retention must trail the manifest.** Log may expire only below the offset in the
  current manifest, with a margin.
- **Cleanup runs apart from the flusher**, deletes only unnamed objects past a grace period, and
  needs the two guards above (the low-watermark and the upload-to-publish gap).
- **Check conditional writes on SeaweedFS** in the topology used, under concurrent writers,
  before relying on them. Everything above depends on create-if-absent being atomic.
- **Build the storage format or use SlateDB?** **(not set yet)**. SlateDB already solves the
  manifest, fencing, compaction and cleanup, and its direction matches strata's. Against it: the
  Go binding needs cgo and a Rust library, the project is pre-1.0 with storage compatibility only
  between adjacent releases, and strata stores a snapshot plus a command log, not a key-value
  tree. Decide before writing the flusher's format.

## Tests

- **Create-if-absent race**: many writers, one key, exactly one wins. Run it against the fake and
  against every real backend.
- **Publish order**: crash after the segments and before the manifest. A restore sees the old
  state, and the next flush covers the same range without loss or duplication.
- **Fencing**: a stale owner or flusher, resumed after a new one took over, cannot publish, and
  it stops itself.
- **Old writes survive a takeover**: what the old owner logged before the fence is present after
  the new owner's restore.
- **Unknown outcome**: the write applied and the reply was lost. The retry is recognized as its
  own and not reported as a conflict.
- **Integrity**: a truncated object, a flipped byte and a wrong file are each rejected with a
  corruption error, and nothing is loaded from them.
- **Cleanup safety**: cleanup never deletes an object the current manifest or a snapshot names,
  nor one uploaded but not yet published. Model-based fuzz: flush, snapshot, clean up, crash,
  restore, compared with a plain model.
- **Restore equals history**: for a random script of commands, flushes, crashes and takeovers,
  the restored state equals the state of a model that applied every acknowledged write once.
- **No LIST on the request path**: a fake that fails the test if LIST is called while serving.
- **Faults**: the table in [rules.md §8](rules.md#8-testing-what-every-change-needs), through a
  misbehaving fake S3.

## Smells

- An object changed in place, or a name reused after a failed attempt.
- A reader that finds data by listing instead of from the manifest.
- A lease with an expiry and no fencing token, protecting data.
- An epoch checked on one structure and not on the other.
- "Already exists" treated as a conflict without reading the object back.
- Cleanup that deletes by age alone.
- The log position stored somewhere other than with the data it describes.
- One object per record.
- A new storage client per call.
- A backend used without a concurrent conditional-write test.
