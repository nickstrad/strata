# Script index

One line per script in `agent/scripts/`. Rules: `agent/AGENTS.md`. Run from the repo root.

| Script | Lang | Run | What it does |
|---|---|---|---|
| `infra-smoke.sh` | bash | `agent/scripts/infra-smoke.sh` | Smoke-tests the compose stack (needs `make infra-up`): Redpanda produce/consume, schema registry and admin API, Postgres write/read (temp table), Valkey set/get, SeaweedFS status, filer write/read and S3 endpoint. Cleans up its test data. |
