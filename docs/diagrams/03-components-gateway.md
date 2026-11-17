# 3. Components: gateway

Inside the gateway container from [02-containers.md](02-containers.md).

```mermaid
flowchart TB
    client(["<b>Client application</b>"])

    subgraph gw["Gateway"]
        direction TB
        listener["<b>RESP listener</b><br/>Accepts connections,<br/>parses Valkey wire protocol"]
        auth["<b>Authenticator</b><br/>AUTH / HELLO to tenant identity"]
        router["<b>Tenant router</b><br/>Tenant to owning data node"]
        table["<b>Routing table</b><br/>In-memory cache:<br/>tenant, node, credentials"]
        sync["<b>Control plane sync</b><br/>Keeps the table current"]
        pool["<b>Upstream pool</b><br/>Connections to owners;<br/>forwards and relays replies"]
        telemetry["<b>Telemetry</b><br/>Per-tenant metrics and logs"]
    end

    owner["<b>Owner</b><br/>(data node)"]
    cpapi["<b>Control plane API</b>"]

    client -- "RESP" --> listener
    listener --> auth
    auth --> router
    router --> pool
    pool -- "Forwards commands" --> owner

    auth -. "Looks up credentials" .-> table
    router -. "Looks up route" .-> table
    sync -- "Updates" --> table
    sync -. "Watches routes and credentials" .-> cpapi
    pool -. "Moved / not-owner reply:<br/>refresh this tenant" .-> sync
    listener -.-> telemetry
    pool -.-> telemetry
    telemetry -. "Reports" .-> cpapi

    classDef person fill:#08427b,stroke:#052e56,color:#ffffff
    classDef component fill:#85bbf0,stroke:#5d82a8,color:#000000
    classDef container fill:#438dd5,stroke:#2e6295,color:#ffffff
    class client person
    class listener,auth,router,table,sync,pool,telemetry component
    class owner,cpapi container
    style gw fill:none,stroke:#438dd5,stroke-width:2px,stroke-dasharray:6 4
```

## Components

| Component | What it does |
|---|---|
| **RESP listener** | Accepts client connections and parses the Valkey wire protocol. To the client this is a Valkey server. |
| **Authenticator** | Turns the connection's `AUTH` / `HELLO` into a tenant identity, checked against credentials in the routing table. Commands before a successful auth are refused. |
| **Tenant router** | Finds the data node that currently owns the tenant's data. This is the tenant mapping the gateway exists for. |
| **Routing table** | The in-memory map of tenant to owning node, plus the credentials needed to authenticate. It is a cache: the control plane holds the real mapping. |
| **Control plane sync** | Keeps the routing table current by watching the control plane. It also refreshes one tenant on demand when a node says it no longer owns it. |
| **Upstream pool** | Holds connections to owners, forwards each command to the right one and relays the reply. It keeps a connection's commands in order. |
| **Telemetry** | Counts and timings per tenant (connections, commands, errors, latency), reported to the control plane for observability. |

## Notes

- The gateway never talks to Valkey or Redpanda. It only knows owners.
- It keeps no tenant data and no state that cannot be refetched, so gateways scale out freely
  behind a load balancer.
- When a tenant moves, the old owner answers "not the owner". The pool asks the sync to refresh
  that tenant and retries on the new owner, so a move looks like a short pause to the client.
- If the control plane is unreachable, the gateway keeps serving with the table it has.
