# strata

Go project. Module `github.com/nickstrad/strata`; the entry point is `cmd/strata`. `make build`,
`make test`, `make vet`.

## Workflow

`main` is protected: every change goes through a pull request. Work on a branch in a worktree
under `.claude/worktrees/<branch>`, push the branch, and open a PR with `gh pr create`.

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

The store lives in `.kb/` (config, committed) and `data/` (entries, committed). The index
database `.kb/stores/*/kb.sqlite` is derived and ignored; after a fresh clone run `kb reindex --all`.
