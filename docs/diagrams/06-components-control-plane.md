# 3. Components: control plane API

Inside the control plane API container from [02-containers.md](02-containers.md).

```mermaid
flowchart TB
    admin(["<b>Tenant admin / operator</b>"])
    client(["<b>Client application</b>"])
    gw["<b>Gateway</b>"]
    owner["<b>Owner</b><br/>(data node)"]
    flusher["<b>Flusher</b>"]

    subgraph cp["Control plane API"]
        direction TB
        pub["<b>Public API</b><br/>Tenants, keys, usage [HTTPS]"]
        internal["<b>Internal API</b><br/>For gateways, owners<br/>and the flusher"]
        authn["<b>Identity and tokens</b><br/>Authenticates tenants;<br/>issues tenant tokens (JWT);<br/>publishes signing keys"]
        tenants["<b>Tenant registry</b><br/>Tenants, plans, limits,<br/>permissions"]
        nodes["<b>Node registry</b><br/>Data nodes, health,<br/>capacity"]
        place["<b>Placement</b><br/>Tenant to data node mapping;<br/>assigns and moves tenants"]
        obs["<b>Observability</b><br/>Metrics, usage, flush lag"]
    end

    pg[("<b>Control plane DB</b><br/>[Postgres]")]

    admin -- "HTTPS" --> pub
    client -. "Gets a tenant token [HTTPS]" .-> pub
    pub --> authn
    authn --> tenants
    pub --> obs

    gw -. "Watch routes and<br/>token signing keys" .-> internal
    internal --> authn
    owner -. "Register, heartbeat, ownership" .-> internal
    flusher -. "Flush progress" .-> internal
    gw -. "Telemetry" .-> internal

    internal --> place
    internal --> nodes
    internal --> obs
    tenants -- "New tenant needs a node" --> place
    nodes -- "Node lost: reassign its tenants" --> place

    tenants --> pg
    nodes --> pg
    place --> pg
    obs --> pg

    classDef person fill:#08427b,stroke:#052e56,color:#ffffff
    classDef component fill:#85bbf0,stroke:#5d82a8,color:#000000
    classDef container fill:#438dd5,stroke:#2e6295,color:#ffffff
    class admin,client person
    class pub,internal,authn,tenants,nodes,place,obs component
    class gw,owner,flusher,pg container
    style cp fill:none,stroke:#438dd5,stroke-width:2px,stroke-dasharray:6 4
```

## Components

| Component | What it does |
|---|---|
| **Public API** | What tenant admins, operators and client applications call: create and remove tenants, get a tenant token, read usage and health. |
| **Internal API** | What the data plane calls. Gateways watch routes and token signing keys; owners register, heartbeat and take ownership; the flusher reports progress. |
| **Identity and tokens** | The one place auth values are handled. It authenticates a tenant, then issues a signed tenant token (JWT) whose claims carry the tenant's identity and permissions. It publishes the public signing keys so the gateway can verify tokens by itself, and it rotates those keys. |
| **Tenant registry** | The record of each tenant: identity, plan, limits and permissions. The token's claims come from here. |
| **Node registry** | The record of each data node: address, health from heartbeats, and capacity. |
| **Placement** | The tenant-to-resource mapping. It decides which data node owns each tenant, hands out ownership, and moves tenants when a node is lost, full or drained. The gateway's routing table is a copy of this. |
| **Observability** | Collects metrics and usage from the gateways, owners and flusher, per tenant. |

## Notes

- **The approach.** The control plane follows the control plane / application plane model in Tod
  Golding's *Building Multi-Tenant SaaS Architectures* (O'Reilly, 2024). Tenant identity is bound
  into a token once, here, and every request to the data plane (the book's application plane)
  carries it. The gateway and the owners read the tenant context from the token and hold no
  credentials of their own.
- The control plane is not on the request path. Client commands never pass through it, and
  verifying a token needs only the cached signing keys.
- It decides; the data plane does. Placement names the owner of a tenant; the node's lifecycle
  agent and bootstrapper do the loading, and gateways pick up the new route.
- If the control plane is down, existing tenants keep working from cached routes. Creating,
  moving and recovering tenants wait until it is back.
- Starting and stopping data nodes (autoscaling) belongs with Placement and the node registry.
  It is not drawn as its own component yet.
- Control-plane features that are not business logic of the data path belong here as they arrive.
