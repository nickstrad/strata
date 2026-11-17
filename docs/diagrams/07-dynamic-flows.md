# Dynamic flows

How the containers in [02-containers.md](02-containers.md) work together over time.

## A write

```mermaid
sequenceDiagram
    autonumber
    participant C as Client
    participant G as Gateway
    participant O as Owner
    participant R as Redpanda
    participant V as Valkey process

    C->>G: SET k v [RESP]
    G->>G: Tenant from the connection, look up its owner
    G->>O: SET k v for tenant T
    O->>R: Append the write to T's log
    R-->>O: Ack (durable, replicated)
    O->>V: SET k v
    V-->>O: OK
    O-->>G: OK
    G-->>C: OK
```

The write is durable at step 5, before Valkey sees it. The client gets `OK` only after both the
log and Valkey have it. A read skips steps 4 and 5.

## A flush

```mermaid
sequenceDiagram
    autonumber
    participant F as Flusher
    participant R as Redpanda
    participant S as Object storage

    loop Periodically, per tenant
        F->>S: Read T's checkpoint (last flushed offset)
        F->>R: Read T's log after that offset
        R-->>F: Records
        F->>S: Write segment objects
        F->>S: Write the new checkpoint
        Note over R,S: Log up to the new checkpoint may now expire from Redpanda
    end
```

After step 5, object storage alone can rebuild the tenant up to the new checkpoint.

## A data node takes a tenant

This is the same flow for a new node, a tenant moving between nodes, and recovery after a crash.

```mermaid
sequenceDiagram
    autonumber
    participant P as Control plane API
    participant O as Owner
    participant S as Object storage
    participant R as Redpanda
    participant V as Valkey process
    participant G as Gateway

    P->>O: You own tenant T
    O->>S: Read T's checkpoint and the objects it names
    S-->>O: Data up to the checkpoint offset
    O->>V: Load it
    O->>R: Read T's log after the checkpoint offset
    R-->>O: The unflushed writes
    O->>V: Replay them in order
    O->>P: T is ready
    P-->>G: Route for T is this node
    G->>O: Commands for T
```

Steps 2 to 4 use the source of truth; steps 5 to 7 add the writes that have not been flushed yet.
Together they bring Valkey to exactly the state of the log, with no data kept on the node itself.
