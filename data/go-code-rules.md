---
title: Go code rules and the check gate
summary: Read docs/coding-style.md before writing Go; use internal/assert, errs and logx; make check (gofmt, vet, race, noassert) is the gate.
tags: [go, coding-style, testing, assert, errs, logx, make-check]
aliases: [style guide, test rules, noassert, fuzz]
updated: 2026-11-16
---

# Go code rules and the check gate

## Where the rules are

- `docs/coding-style.md`: the short rules in strata's terms, with a checklist. Read it first.
- `docs/go-coding-style.md`: the house guide with templates (layout, contracts, errors, logging,
  the top-level reporter, the Result pattern). Not edited for strata.
- `docs/go-testing.md`: the house testing guide (spec tables, coverage, fuzzing, contract suites,
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
and per-dependency deadline defaults. `docs/coding-style.md` marks these.
