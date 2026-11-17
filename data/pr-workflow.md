---
title: Changes reach main only through pull requests
summary: main is protected by the "protect-main" GitHub ruleset; work on a branch in a worktree and merge through a PR.
tags: [git, workflow, github]
updated: 2026-11-16
---

# Changes reach main only through pull requests

## Rule

Do not commit or push straight to `main`. The GitHub ruleset `protect-main` requires a pull
request for every change to the default branch, blocks force pushes and blocks deletion.
Nobody can bypass it.

## How to work

- Create a worktree on a new branch from `origin/main`:
  `git worktree add .claude/worktrees/<branch> -b <branch> origin/main`
- `.claude/worktrees/` is listed in `.git/info/exclude` of the main checkout, so the worktrees
  do not show as untracked files.
- Commit on the branch, push it, then open the PR with `gh pr create`.
- Version branches have names like `v0.0.1`.
