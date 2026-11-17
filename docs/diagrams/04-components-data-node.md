# 3. Components: data node (owner + Valkey process)

Inside one data node from [02-containers.md](02-containers.md). The owner and its Valkey process
are two processes, drawn together because neither is useful alone.

```mermaid
flowchart TB
    gw["<b>Gateway</b>"]
    cpapi["<b>Control plane API</b>"]

    subgraph node["Data node"]
        direction TB

        subgraph owner["Owner process"]
            direction TB
            api["<b>Command API</b><br/>Receives commands<br/>from the gateway"]
            mailbox["<b>Tenant mailbox</b><br/>One command at a time per tenant,<br/>in arrival order (the actor)"]
            classify["<b>Command classifier</b><br/>Read or write?<br/>Rewrites non-deterministic writes"]
            logw["<b>Log writer</b><br/>Appends the write and<br/>waits for the ack"]
            exec["<b>Valkey executor</b><br/>Runs the command,<br/>returns the reply"]
            boot["<b>Bootstrapper</b><br/>Loads a tenant: restore,<br/>then replay"]
            life["<b>Lifecycle agent</b><br/>Registration, heartbeat,<br/>tenant ownership"]
        end

        valkey["<b>Valkey process</b><br/>In-memory data.<br/>No AOF, no RDB."]
    end

    rp[("<b>Redpanda</b>")]
    obj[("<b>Object storage</b>")]

    gw -- "Commands" --> api
    api --> mailbox
    mailbox --> classify
    classify -- "Write: step 1" --> logw
    logw -- "Append [Kafka]" --> rp
    logw -- "Acked: step 2" --> exec
    classify -- "Read" --> exec
    exec -- "RESP" --> valkey

    boot -- "Step 1: Reads checkpoint,<br/>snapshot and segments" --> obj
    boot -- "Step 2: Replays the tail after<br/>the checkpoint" --> rp
    boot -- "Loads data" --> exec
    boot -. "Tenant ready:<br/>open its mailbox" .-> mailbox

    life -. "Register, heartbeat,<br/>take / release ownership" .-> cpapi
    life -. "Load or drop a tenant" .-> boot

    classDef component fill:#85bbf0,stroke:#5d82a8,color:#000000
    classDef container fill:#438dd5,stroke:#2e6295,color:#ffffff
    classDef external fill:#8a8a8a,stroke:#5f5f5f,color:#ffffff
    class api,mailbox,classify,logw,exec,boot,life component
    class gw,cpapi,valkey,rp container
    class obj external
    style node fill:none,stroke:#438dd5,stroke-dasharray:2 3
    style owner fill:none,stroke:#438dd5,stroke-width:2px,stroke-dasharray:6 4
```

## Components of the owner

| Component | What it does |
|---|---|
| **Command API** | The door the gateway uses. It accepts a tenant's commands and returns their replies. It refuses a tenant this node does not own, so the gateway can refresh its route. |
| **Tenant mailbox** | The actor part. Commands for a tenant are handled one at a time in arrival order, so the order in the log is the order in Valkey. |
| **Command classifier** | Decides whether a command changes data. Reads go straight to the executor. Writes go to the log writer first. It also turns a non-deterministic write into its fixed effect, so a replay gives the same data. |
| **Log writer** | Appends the write to the tenant's log in Redpanda and waits until Redpanda acknowledges it as durable. Only then does the write continue. |
| **Valkey executor** | Runs the command in the Valkey process and passes the reply back. It is the only client the Valkey process has. |
| **Bootstrapper** | Brings a tenant into this node. It reads the tenant's checkpoint and data from object storage, loads that into Valkey, then replays from Redpanda every write after the checkpoint. When it has caught up, the tenant's mailbox opens. |
| **Lifecycle agent** | Registers the node with the control plane, sends heartbeats, and takes or releases ownership of tenants when the control plane says so. |

## The Valkey process

A stock Valkey server, configured with persistence off. It is a fast in-memory working copy and
nothing more: durability is the job of Redpanda and object storage. Only the owner connects to it.

## The write rule

**Log first, then apply.** A write is appended to Redpanda, and only after the acknowledgement is
it run in Valkey and answered to the client.

- A crash before the append: the write did not happen, and the client got no success reply.
- A crash after the append and before the apply: the write is in the log, so the next node that
  loads the tenant replays it. Memory is never ahead of the log.
- This is why Valkey needs no AOF: the Redpanda log plays that role, and it is replicated.

## Why an owner per Valkey process

One writer per Valkey process means one order of writes, with no coordination between nodes on the
data path. Scaling out is adding nodes and moving tenants between them, which the control plane
decides and the lifecycle agent and bootstrapper carry out.
