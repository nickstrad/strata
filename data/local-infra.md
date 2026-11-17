---
title: Local infrastructure (compose stack) ports and checks
summary: compose.yaml runs Postgres, SeaweedFS, Redpanda and Valkey on 127.0.0.1; make infra-up/infra-down; agent/scripts/infra-smoke.sh checks it.
tags: [infra, docker, postgres, seaweedfs, redpanda, valkey]
updated: 2026-11-16
---

# Local infrastructure (compose stack) ports and checks

## Services and ports

`compose.yaml` (project name `strata`) runs four services. Every port is bound to 127.0.0.1.

| Service | Image | Host ports |
|---|---|---|
| Postgres (user, password and database all `strata`) | `postgres:18.7-alpine` | 5432 |
| SeaweedFS (`weed server -filer -s3`) | `chrislusf/seaweedfs:4.54` | 9333 master, 8888 filer, 8333 S3 |
| Redpanda (dev-container mode) | `redpandadata/redpanda:v26.2.7` | 19092 Kafka, 18081 schema registry, 18082 HTTP proxy, 19644 admin |
| Valkey (append-only file on) | `valkey/valkey:9.1.3-alpine` | 6379 |

Inside the compose network, Kafka clients use `redpanda:9092`; from the host, `localhost:19092`.

Postgres from the host: `postgres://strata:strata@localhost:5432/strata`; `make psql` opens a
shell. The Postgres 18 image keeps its data under `/var/lib/postgresql/18/docker`, so the volume
mounts `/var/lib/postgresql`, not `/var/lib/postgresql/data` as older images did.

## Commands

- `make infra-up` starts the stack and waits until all three are healthy.
- `make infra-down` stops it and keeps the data volumes; `make infra-clean` also deletes them.
- `agent/scripts/infra-smoke.sh` checks every service end to end.

## Port clash with other containers

SeaweedFS uses host ports 8333, 8888 and 9333, and Postgres 5432. If another container on the
machine already publishes one of them, `make infra-up` fails with "port is already allocated".
`docker ps` shows which container holds the port; stop it first.
