# strata

Go project. Module `github.com/nickstrad/strata`; the entry point is `cmd/strata`. `make help`
lists the targets (Go: `build`, `test`, `check`, `fuzz`, `cover`; local infrastructure: `infra-*`).

## Keep context small: read indexes first

This repo uses index files so an agent does not have to load everything. Start from the index
of the area you work in, then open only the files it points to:

- `docs/README.md`: every doc, one line each.
- `agent/AGENTS.md`: the agent workspace and its rules.
- `agent/scripts/INDEX.md`: every saved script, one line each.
- `docs/diagrams/README.md`: the architecture (C4 diagrams), one line per diagram, plus the
  core idea and the open design questions. Read it before you change how the parts fit together,
  and update the diagrams in the same change.
- The knowledge store (below): search it; do not read `data/` wholesale.

When you add a file to an indexed folder, add its line to that folder's index in the same change.

Agent instructions live in `AGENTS.md` files. Claude Code reads `CLAUDE.md`, not `AGENTS.md`, so
every `AGENTS.md` has a `CLAUDE.md` symlink beside it (`ln -s AGENTS.md CLAUDE.md`). Edit
`AGENTS.md`; never replace the symlink with a copy.

## Go code

Read `docs/coding-style/README.md` before you design, plan or write a component. It indexes the
rules (`rules.md`, with the done checklist), the resilience sheets (`rate-limiting.md`,
`backpressure.md`, `circuit-breakers-and-retries.md`), `concurrency-patterns.md`, `object-storage.md` and the full guides (`go-coding-style.md`,
`go-testing.md`).

Resilience and testing are part of the design, not a pass at the end. For every component,
answer the component design checklist in that README (what is bounded, what a refused caller
gets, deadlines, what is safe to retry, what users see when a dependency is down), and write
the tests the sheets name in the same change.

Use the shared packages: `internal/assert` (contracts), `internal/errs` (errors), `internal/logx`
(logs and the top-level reporter). `make check` is the gate before a change is done: gofmt,
`go vet`, `go test -race`, and the same tests with `-tags noassert`.

## Workflow

`main` is protected: every change goes through a pull request. Work on a branch in a worktree
under `.claude/worktrees/<branch>`, push the branch, and open a PR with `gh pr create`.

## Agent workspace (`agent/`)

`agent/` holds what agents make for their own use, outside the product code. Read
`agent/AGENTS.md` before you add to it. In short: a script you write ad hoc to check, test or
inspect something is saved in `agent/scripts/` and listed in `agent/scripts/INDEX.md`. Write
scripts in Go, unless the script mostly runs other commands (docker, make, curl, git), in which
case write it in Bash.

## Knowledge store (kb)

Search the knowledge store before answering questions about this project, its environment or
its tools, and before adding a finding (prefer updating an existing entry).

- `kb search "<question in plain words>" --caller claude` lists ranked hits (`--json` for
  structured output; `--expand section` for whole sections; `--budget N` to cap the size).
  Identifiers such as `foo_bar`, `pkg.Func` or `--flag` match exactly; put a query starting
  with `-` after `--`.
- `kb show <path>` (or `kb show REF:path` for another store's hit) reads a hit's entry. Do not
  read or grep the store's files directly.
- `kb add <draft.md>` saves a durable, non-obvious finding.
- Optional: `kb feedback <search_id> <rank> --useful` (or `--not-useful`, or `<search_id> --none`)
  records whether a search helped.
- Run `kb help` or `kb <command> --help` for details.

**Keep the store current.** Updating kb is part of every change, not a separate task:

- When a change makes an entry wrong or incomplete, edit that entry (`kb edit <path>`) in the
  same change, and set its `updated:` date.
- When you learn something durable and non-obvious (a decision, a port, a gotcha, how a tool
  behaves here), add an entry, or extend the closest existing one.
- When an entry is replaced, list the old one under `supersedes` in the new entry's front matter.

The store lives in `.kb/` (config, committed) and `data/` (entries, committed). The index
database `.kb/stores/*/kb.sqlite` is derived and ignored; after a fresh clone run `kb reindex --all`.
