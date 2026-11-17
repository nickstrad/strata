# Concurrency patterns

What is worth taking from Allen B. Downey, *The Little Book of Semaphores* (2nd ed.), for a Go
codebase. Index: [README.md](README.md).

## Verdict

**Most of the book is not needed here.** It teaches synchronization by building everything from
one primitive, the semaphore, and then solving puzzles with it. Go ships the finished pieces
(channels, `sync`, `context`, `errgroup`), so in strata you should almost never build a pattern
from raw semaphores.

| Part of the book | For strata |
|---|---|
| Ch. 1–2: what synchronization is, non-determinism, the semaphore | Worth knowing; one page below |
| Ch. 3: basic patterns (signal, rendezvous, mutex, multiplex, barrier, turnstile, queue) | **Take the vocabulary.** Each has a ready-made Go form; see the table |
| Ch. 4: producer-consumer, readers-writers, starvation, dining philosophers | **Take the hazards**: deadlock, starvation, and how to rule them out |
| Ch. 4.6–7: the puzzle collection (smokers, barbershop, Santa, H2O, river crossing, …) | Skip. Practice problems; none maps to a strata component |
| Ch. 8–9: Python and C specifics; building your own semaphore | Skip |

What the book does **not** cover, and Go work needs: cancellation, deadlines, goroutine lifetime,
error and panic propagation, and channel ownership. Those are in
[rules.md §4](rules.md#4-concurrency) and [go-coding-style.md §6](go-coding-style.md).

What our rules did not cover, and the book does: **bounded concurrency as a named pattern, lock
ordering, and starvation.** Those are the rules added below.

## The ideas worth keeping

- **Two kinds of constraint.** *Serialization*: A must happen before B. *Mutual exclusion*: A and
  B must not happen at the same time. Name which one you need before you pick a tool.
- **Assume any interleaving.** Between any two statements of one goroutine, any other goroutine
  may run any amount. If the code is correct only for the orderings you imagined, it is wrong.
- **A test that passes proves little.** Concurrency bugs depend on timing. Argue correctness from
  invariants, then test for the argument's weak points.
- **The three failures**: a *race* (unsynchronized access), a *deadlock* (everyone waits for
  someone), *starvation* (someone waits forever while others proceed).

## The basic patterns, in Go

Use the Go form. Do not rebuild these from a counting semaphore.

| Pattern | Meaning | In Go |
|---|---|---|
| Signal | "B may go after A finished" | Close a `chan struct{}`, or send one value |
| Rendezvous | Two goroutines meet; neither goes on alone | A send on an unbuffered channel |
| Mutex | One at a time in a critical section | `sync.Mutex` |
| **Multiplex** | At most N at a time | A buffered `chan struct{}` of capacity N, or `golang.org/x/sync/semaphore` when units have weights or acquire must take a context |
| Barrier | Wait until all N have arrived or finished | `sync.WaitGroup`, or `errgroup.Group` |
| Turnstile / gate | Hold everyone, then release all at once | Close a channel: every receiver wakes |
| Queue | Hand work from producers to consumers | A buffered channel (bounded: see [backpressure.md](backpressure.md)) |
| Run once | Initialize exactly once | `sync.Once`, `sync.OnceValue` |
| Wait for a condition | Sleep until state changes | Prefer a channel. `sync.Cond` only when a channel will not do, and always re-check the condition in a loop |

The multiplex is the one to remember: it is the bulkhead and the dependency concurrency limit in
the resilience sheets. Acquire with the context, so a waiter that gives up leaves the line:

```go
select {
case sem <- struct{}{}:
	defer func() { <-sem }()
case <-ctx.Done():
	return ctx.Err()
}
```

## Rules added from the book

**Deadlock**

- **A fixed lock order.** If code ever holds two locks, every path takes them in the same order,
  and the order is written at the type. (The dining philosophers deadlock is five goroutines each
  holding one lock and waiting for the next.)
- **Better: hold one lock at a time.** Design so that no path needs two.
- **Never call out while holding a lock**: no callback, no interface method that an adapter
  implements, no channel send or receive, no I/O. The callee may block or take another lock.
- **Never block forever.** Every blocking operation selects on the context as well. A wait with
  no way out is a deadlock that has not happened yet.
- An actor (one goroutine owns the state and reads a mailbox) removes lock ordering from the
  picture. It is the owner's model per tenant. Its own deadlock is two actors that each wait for
  a reply from the other: never make a blocking call from one mailbox loop into another.

**Starvation**

- **Bounded waiting is part of correctness.** "It makes progress" is not enough; ask whether one
  waiter can lose every time.
- `sync.Mutex` and `sync.RWMutex` already guard against it: a mutex that has waited long is
  handed the lock directly, and a waiting writer blocks new readers. Do not write your own
  fairness on top.
- **Never take a read lock twice in one goroutine** (`RLock` inside `RLock`). With a writer
  waiting between the two, it deadlocks.
- A buffered channel used as a semaphore gives no ordering guarantee among waiters. Where
  fairness between tenants matters, it comes from **one queue per tenant**, not from the lock.
- An `RWMutex` pays off only when reads are long and far more common than writes. Otherwise use a
  `Mutex`: it is simpler and often faster.

**Choosing**

- Share memory behind a mutex when you are protecting state. Use a channel when you are handing
  off work or ownership. Do not use a channel as a mutex or a mutex as a queue.
- Keep the critical section short and free of anything slow. Protect the whole invariant with one
  lock; do not split fields of one invariant across locks.
- Atomics are for single counters and flags, not for state with more than one field.
- A closed channel is a broadcast; a send wakes one receiver. Pick the one you mean. Only the
  owner closes.

## In strata

- **Tenant mailbox (owner)**: an actor. One goroutine per tenant owns the order of commands, so
  the log order and the apply order agree without a lock. No blocking call from one tenant's loop
  into another's.
- **Limits on tenant loads, appends in flight and object-storage transfers**: a multiplex each,
  acquired with the context.
- **Routing table, signing keys, breaker state, token buckets**: a mutex around the whole
  invariant. The routing table is read far more than written; measure before choosing `RWMutex`,
  or swap an immutable snapshot with `atomic.Pointer`.
- **Ownership changes** (a tenant moves while commands are queued) are the place two things must
  be ordered. Write the order down and test it with many goroutines on one tenant.

## Tests

- `go test -race` on everything; it finds races, **not** deadlocks or starvation.
- Many goroutines on the same key for every path that locks or compares-and-sets.
- A goroutine count check at the end of tests that start goroutines: no leak after shutdown.
- For timing-dependent code, `testing/synctest` runs goroutines against a fake clock, so the test
  does not sleep and does not flake.
- Deadlock: a test that would hang must fail instead. Give blocking test steps a deadline.
- Starvation: with one slow or greedy tenant, the others still finish within a bound.
- A model-based fuzz test for anything stateful: a script of operations compared with a plain
  model after each step.

## Smells

- Two locks taken in different orders on different paths.
- A lock held across a channel operation, a callback or I/O.
- A blocking receive or acquire with no `ctx.Done()` case.
- `RLock` taken twice on one path.
- A hand-built semaphore, barrier or condition loop where `sync` or a channel already does it.
- `time.Sleep` used to "let the other goroutine go first".
- A fix for a race that only makes it rarer.
