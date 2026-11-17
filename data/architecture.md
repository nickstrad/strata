---
title: strata architecture in brief
summary: Multi-tenant Valkey service. Gateway routes tenants to data nodes (owner + Valkey); writes go to Redpanda first, a flusher moves the log to object storage, which is the source of truth.
tags: [architecture, gateway, owner, valkey, redpanda, object-storage, control-plane, flusher]
aliases: [design, c4, data plane, write path]
updated: 2026-11-16
---

# strata architecture in brief

The diagrams and full explanations are in `docs/diagrams/` (start at `docs/diagrams/README.md`).

## Parts

- **Gateway**: speaks the Valkey wire protocol (RESP) to clients. Maps a tenant to the data node
  that currently owns its data and forwards commands to that node's owner. Holds no tenant data.
- **Data node**: a Valkey process (persistence off) plus an **owner** process attached to it,
  actor-like. All commands go through the owner. Data nodes are the horizontally scaled compute.
- **Redpanda**: the durable, replicated write log. Replaces Valkey AOF and home-made replication.
- **Flusher**: background process that periodically moves the log from Redpanda to object storage
  and writes a checkpoint (the flushed offset).
- **Object storage**: the ultimate source of truth. A cloud bucket; SeaweedFS (S3 API) locally.
- **Control plane API**: tenants, auth, observability, tenant-to-resource mapping, and future
  control-plane features that are not data-path logic. State assumed to be in Postgres.

## Rules

- **Log first, then apply.** The owner appends a write to Redpanda, waits for the ack, then runs
  it in Valkey. Memory is never ahead of the log.
- **Valkey is disposable.** A node starts empty: restore the tenant from object storage, replay
  from Redpanda the writes after the checkpoint, then serve.
- **The checkpoint divides the stores.** Object storage is the truth up to the flushed offset;
  Redpanda holds what comes after and may expire only what is below it.
- The control plane is not on the request path; the data plane serves from cached routes.

## Not decided yet

Listed in `docs/diagrams/README.md` under "Open questions": tenants per Valkey process, topic
layout, read path, apply failure after append, non-deterministic commands, object format
(segments and snapshots), fencing of two owners, and the control plane store.
