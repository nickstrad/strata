# agent/

The agent workspace: tools and notes that agents make for their own use while working on strata.
Nothing here is product code, and nothing in `cmd/` or `internal/` imports it.

| Path | What it holds | Index |
|---|---|---|
| `scripts/` | Saved ad-hoc scripts | `scripts/INDEX.md` |

Read the index, not the folder. Open a script only when its index line says it is the one you need.

## Scripts (`agent/scripts/`)

Save a script here when you write it to check, test, inspect or set up something, and it could
be useful again. Before you write a new one, read `scripts/INDEX.md`: run or extend an existing
script before you add a near-copy.

**Language.** Write the script in Go. Use Bash only when the script mostly runs other commands
(docker, make, curl, git, kb) and has little logic of its own.

**Layout.**

- Go: one directory per script, `agent/scripts/<name>/main.go`, `package main`. It is part of
  the strata module, so run it with `go run ./agent/scripts/<name>` from the repo root. Use the
  standard library unless a dependency saves real work, and keep it passing `go vet ./...`.
- Bash: `agent/scripts/<name>.sh`, executable (`chmod +x`), starting with
  `#!/usr/bin/env bash` and `set -euo pipefail`. Run it from the repo root.
- Names are kebab-case and say what the script does (`infra-smoke`, not `test2`).
- The top of every script has a comment that says what it does, what it needs (for example,
  "the stack is up: `make infra-up`") and how to run it.

**Index.** Add one line per script to `scripts/INDEX.md` in the same change that adds the script.
Change the line when the script changes; remove it when the script is deleted.

**Knowledge.** If a script shows something durable and non-obvious, record it in kb too (see the
top-level `AGENTS.md`). A script is how to check a fact; kb is where the fact is recorded.
