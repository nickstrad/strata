# 3. Components: control plane API

Inside the control plane API container from [02-containers.md](02-containers.md).

```mermaid
flowchart TB
    admin(["<b>Tenant admin / operator</b>"])
    gw["<b>Gateway</b>"]
    owner["<b>Owner</b><br/>(data node)"]
    flusher["<b>Flusher</b>"]

    subgraph cp["Control plane API"]
        direction TB
        pub["<b>Public API</b><br/>Tenants, keys, usage [HTTPS]"]
        internal["<b>Internal API</b><br/>For gateways, owners<br/>and the flusher"]
        authn["<b>Auth</b><br/>Who is calling,<br/>what they may do"]
        tenants["<b>Tenant registry</b><br/>Tenants, plans, limits,<br/>data-plane credentials"]
        nodes["<b>Node registry</b><br/>Data nodes, health,<br/>capacity"]
        place["<b>Placement</b><br/>Tenant to data node mapping;<br/>assigns and moves tenants"]
        obs["<b>Observability</b><br/>Metrics, usage, flush lag"]
    end

    pg[("<b>Control plane DB</b><br/>[Postgres]")]

    admin -- "HTTPS" --> pub
    pub --> authn
    authn --> tenants
    pub --> obs

    gw -. "Watch routes and credentials" .-> internal
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
    class admin person
    class pub,internal,authn,tenants,nodes,place,obs component
    class gw,owner,flusher,pg container
    style cp fill:none,stroke:#438dd5,stroke-width:2px,stroke-dasharray:6 4
```

## Components

| Component | What it does |
|---|---|
| **Public API** | What tenant admins and operators call: create and remove tenants, issue and revoke keys, read usage and health. |
| **Internal API** | What the data plane calls. Gateways watch routes and credentials; owners register, heartbeat and take ownership; the flusher reports progress. |
| **Auth** | Identifies the caller of the public API and decides what they may do. It also issues the credentials a tenant's clients present to the gateway. |
| **Tenant registry** | The record of each tenant: identity, plan, limits and data-plane credentials. |
| **Node registry** | The record of each data node: address, health from heartbeats, and capacity. |
| **Placement** | The tenant-to-resource mapping. It decides which data node owns each tenant, hands out ownership, and moves tenants when a node is lost, full or drained. The gateway's routing table is a copy of this. |
| **Observability** | Collects metrics and usage from the gateways, owners and flusher, per tenant. |

## Notes

- The control plane is not on the request path. Client commands never pass through it.
- It decides; the data plane does. Placement names the owner of a tenant; the node's lifecycle
  agent and bootstrapper do the loading, and gateways pick up the new route.
- If the control plane is down, existing tenants keep working from cached routes. Creating,
  moving and recovering tenants wait until it is back.
- Starting and stopping data nodes (autoscaling) belongs with Placement and the node registry.
  It is not drawn as its own component yet.
- Control-plane features that are not business logic of the data path belong here as they arrive.
