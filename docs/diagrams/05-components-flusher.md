# 3. Components: flusher

Inside the flusher container from [02-containers.md](02-containers.md).

```mermaid
flowchart TB
    rp[("<b>Redpanda</b>")]

    subgraph flusher["Flusher"]
        direction TB
        sched["<b>Scheduler</b><br/>Starts a flush on a timer<br/>or when enough log has built up"]
        consumer["<b>Log consumer</b><br/>Reads each tenant's log<br/>from its last checkpoint"]
        builder["<b>Segment builder</b><br/>Packs records into<br/>segment objects"]
        writer["<b>Object writer</b><br/>Uploads segments"]
        ckpt["<b>Checkpoint writer</b><br/>Records the flushed offset,<br/>after the upload succeeds"]
        report["<b>Progress reporter</b><br/>Flush lag and errors"]
    end

    obj[("<b>Object storage</b>")]
    cpapi["<b>Control plane API</b>"]

    sched --> consumer
    rp -- "Log records [Kafka]" --> consumer
    consumer --> builder
    builder --> writer
    writer -- "1. Segment objects [S3]" --> obj
    writer --> ckpt
    ckpt -- "2. Checkpoint / manifest [S3]" --> obj
    ckpt -. "Offset is safe to expire" .-> rp
    ckpt --> report
    report -. "Reports" .-> cpapi

    classDef component fill:#85bbf0,stroke:#5d82a8,color:#000000
    classDef container fill:#438dd5,stroke:#2e6295,color:#ffffff
    classDef external fill:#8a8a8a,stroke:#5f5f5f,color:#ffffff
    class sched,consumer,builder,writer,ckpt,report component
    class rp,cpapi container
    class obj external
    style flusher fill:none,stroke:#438dd5,stroke-width:2px,stroke-dasharray:6 4
```

## Components

| Component | What it does |
|---|---|
| **Scheduler** | Decides when to flush: periodically, and sooner when a tenant's unflushed log grows large. |
| **Log consumer** | Reads a tenant's log from Redpanda, starting at the offset in that tenant's last checkpoint. |
| **Segment builder** | Packs the records into segment objects, in log order. Later it can also fold old segments into a snapshot to keep restores fast. |
| **Object writer** | Uploads the segments to object storage. |
| **Checkpoint writer** | After the upload succeeds, writes the tenant's checkpoint: which objects make up the tenant and the last log offset they cover. The checkpoint is what a bootstrapper reads first. |
| **Progress reporter** | Tells the control plane how far behind each tenant's flush is, and about failures. |

## Notes

- **Order matters: segments first, checkpoint second.** A crash between the two leaves extra
  objects that no checkpoint names. The next run flushes the same range again. Nothing is lost
  and nothing is counted twice, because a restore reads only what the checkpoint names.
- The checkpoint is the line between the two stores: object storage is the truth up to that
  offset, and Redpanda holds what comes after. Redpanda may expire log only below it.
- The flusher is not on the request path. If it stops, writes still succeed and stay durable in
  Redpanda; the unflushed tail just grows, and restores take longer.
- The flusher only reads Redpanda and writes object storage. It never touches Valkey.
