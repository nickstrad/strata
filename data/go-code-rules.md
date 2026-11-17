---
title: Go code rules and the check gate
summary: Read docs/coding-style/README.md before designing or writing Go; resilience sheets and tests are part of the design; use internal/assert, errs and logx; make check (gofmt, vet, race, noassert) is the gate.
tags: [go, coding-style, testing, object-storage, slatedb, fencing, manifest, concurrency, resilience, rate-limiting, backpressure, circuit-breaker, retries, assert, errs, logx, make-check]
aliases: [style guide, test rules, noassert, fuzz]
updated: 2026-11-16
---

# Go code rules and the check gate

## Where the rules are

All in `docs/coding-style/`; `README.md` there is the index and holds the component design
checklist.

- `rules.md`: the short rules in strata's terms, with the done checklist. Read it first.
- `rate-limiting.md`, `backpressure.md`, `circuit-breakers-and-retries.md`: the main points of
  each pattern, the decisions to make, how each applies to the gateway, owner, flusher and
  control plane, what to measure and which tests to write. Resilience and testing are designed
  in with each component, not added afterwards.
- `concurrency-patterns.md`: the Go form of each synchronization pattern, lock ordering,
  starvation, and which tests catch what (`-race` finds races, not deadlocks).
- `object-storage.md`: immutable data plus one manifest, conditional writes, fencing every
  separately written structure, unknown outcomes, safe cleanup, and how SlateDB and OpenData
  do each. Holds the open choice between building the storage format and using SlateDB.
- `go-coding-style.md`: the house guide with templates (layout, contracts, errors, logging,
  the top-level reporter, the Result pattern). Not edited for strata.
- `go-testing.md`: the house testing guide (spec tables, coverage, fuzzing, contract suites,
  fakes with fault switches, e2e). Not edited for strata.

## Shared packages

- `internal/assert`: `assert.That(cond, format, args...)` panics on a broken contract. On by
  default; `-tags noassert` compiles it out. Guard costly checks with `if assert.Enabled`.
- `internal/errs`: `errs.Wrap(module, err, msg)` at each package boundary; `Outermost`, `Chain`,
  `Stack` for the top level and logs.
- `internal/logx`: `logx.New` (JSON, UTC), `logx.NewID`, `logx.Open`, and `logx.Reporter`, which
  maps a top-level error to exit 1 (expected, known module) or 70 (bug) with a log ID.

## The gate

`make check` runs `go vet`, `go test -race`, vet and tests with `-tags noassert`, and fails if
`gofmt -l .` lists a file. Also: `make fuzz F=FuzzName P=./internal/pkg [T=30s]`, `make cover`.

## Not built yet

A fault harness (a TCP fault proxy and a misbehaving fake S3), circuit breakers, a retry package,
a rate limiter, and per-dependency deadline defaults. The docs mark these "(not set yet)".
