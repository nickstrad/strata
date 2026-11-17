# Architecture diagrams

C4 diagrams of strata, written as Mermaid so GitHub renders them. Read them in order: each level
zooms into one box of the level above.

| File | C4 level | Shows |
|---|---|---|
| [01-system-context.md](01-system-context.md) | 1. Context | strata, the people who use it and the systems it depends on |
| [02-containers.md](02-containers.md) | 2. Containers | The processes and stores inside strata, and how they talk |
| [03-components-gateway.md](03-components-gateway.md) | 3. Components | Inside the gateway |
| [04-components-data-node.md](04-components-data-node.md) | 3. Components | Inside a data node: the owner and its Valkey process |
| [05-components-flusher.md](05-components-flusher.md) | 3. Components | Inside the flusher |
| [06-components-control-plane.md](06-components-control-plane.md) | 3. Components | Inside the control plane API |
| [07-dynamic-flows.md](07-dynamic-flows.md) | Dynamic | The write path, the flush, and a data node starting up |

## The idea in one paragraph

strata is multi-tenant Valkey as a service. Clients send Valkey commands, with a tenant token
(JWT) issued by the control plane, to a **gateway**. The gateway checks the token and maps the
tenant in it to the **data node** that currently owns its data. A data node
is a Valkey process with an **owner** process attached to it. The owner appends every write to a
**Redpanda** topic and then runs the command in Valkey. A background **flusher** moves the log
from Redpanda to **object storage**. A **control plane** handles tenants, auth, observability and
the mapping of tenants to resources.

Four rules follow from that:

- **The control plane owns auth.** It issues the tenant token; requests carry it; the gateway
  and owners act on its claims and hold no credentials. This is the control plane / application
  plane model from Tod Golding's *Building Multi-Tenant SaaS Architectures* (O'Reilly, 2024).

- **Object storage is the ultimate source of truth.** Everything else can be rebuilt from it.
- **Redpanda is the fast durable log.** It holds the writes that are not in object storage yet,
   and it replaces Valkey's AOF and any replication logic of our own.
- **Valkey is disposable compute.** It runs with no persistence. A data node starts empty, loads
   a tenant from object storage, replays the rest from Redpanda, and serves. Scaling out is
   starting more data nodes.

## Colours

| Colour | Meaning |
|---|---|
| Dark blue, rounded | A person or a client application |
| Blue | A strata process (container) |
| Light blue | A component inside a process |
| Blue cylinder | A store that strata runs |
| Grey | Something outside strata |

## Open questions

The diagrams assume an answer to each of these. Each assumption is marked where it is used.

1. **Tenants per Valkey process.** One process per tenant, or many tenants in one process? The
   diagrams say "one or more".
2. **Topic layout.** One Redpanda topic per tenant, or a shared topic with the tenant as the
   partition key? The diagrams say "the tenant's log".
3. **Reads.** The diagrams send reads through the owner (no log append) so the owner stays the
   only door to Valkey.
4. **Apply fails after the append.** The log is the truth, so a write that is in Redpanda has
   happened. If Valkey then fails to apply it, the owner must retry or rebuild, and must not
   serve that tenant until Valkey matches the log.
5. **Non-deterministic commands.** `SPOP`, relative `EXPIRE`, scripts that read the time: a replay
   must give the same result, so the owner must log the effect, not the command, as Valkey does
   for its own replication.
6. **Object format.** Log segments alone make a restore slower as a tenant ages. Periodic
   snapshots plus the segments after them bound the restore time.
7. **Two owners for one tenant.** A move or a crash can leave two nodes that both think they own
   a tenant. The diagrams show an ownership lease from the control plane; the fencing rule
   (an epoch in every log record, for example) is not designed yet.
8. **Control plane store.** The diagrams assume Postgres, which is in `compose.yaml`.
9. **How the token travels with Valkey commands.** The Valkey wire protocol (RESP) has no
   per-request header to put a JWT in. With a stock Valkey client the one place a client can
   present a value is `AUTH`, once per connection, with the JWT as the password. A token on every
   request needs something else: a wrapper command, or a client-facing API that is not raw RESP.
   The diagrams say "with a tenant token" and do not pick one.
10. **Token lifetime and revocation.** The gateway verifies tokens without calling the control
    plane, so a revoked token works until it expires. Short lifetimes plus refresh is the usual
    answer.
11. **Should the token carry the route?** The control plane could put the owning node and an
    ownership epoch in a short-lived token, and the gateway would route on that claim with no
    routing table. Clients would ask the control plane again when a node answers "not the owner"
    or the token expires. That makes the gateway smaller still (no routing table, no route sync),
    in exchange for short tokens and a resolve call from the client. The diagrams keep the routing
    table in the gateway.
