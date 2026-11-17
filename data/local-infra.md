---
title: Local infrastructure (compose stack) ports and checks
summary: compose.yaml runs SeaweedFS, Redpanda and Valkey on 127.0.0.1; make infra-up/infra-down; agent/scripts/infra-smoke.sh checks it.
tags: [infra, docker, seaweedfs, redpanda, valkey]
updated: 2026-11-16
---

# Local infrastructure (compose stack) ports and checks

## Services and ports

`compose.yaml` (project name `strata`) runs three services. Every port is bound to 127.0.0.1.

| Service | Image | Host ports |
|---|---|---|
| SeaweedFS (`weed server -filer -s3`) | `chrislusf/seaweedfs:4.54` | 9333 master, 8888 filer, 8333 S3 |
| Redpanda (dev-container mode) | `redpandadata/redpanda:v26.2.7` | 19092 Kafka, 18081 schema registry, 18082 HTTP proxy, 19644 admin |
| Valkey (append-only file on) | `valkey/valkey:9.1.3-alpine` | 6379 |

Inside the compose network, Kafka clients use `redpanda:9092`; from the host, `localhost:19092`.

## Commands

- `make infra-up` starts the stack and waits until all three are healthy.
- `make infra-down` stops it and keeps the data volumes; `make infra-clean` also deletes them.
- `agent/scripts/infra-smoke.sh` checks every service end to end.

## Port clash with other projects

Another local project, coldload, runs its own `coldload-seaweedfs` container on 8333, 8888 and
9333. If it is running, `make infra-up` fails with "port is already allocated". Stop it first
(`docker stop coldload-seaweedfs`).
