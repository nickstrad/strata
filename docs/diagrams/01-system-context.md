# 1. System context

Who uses strata and what it depends on.

```mermaid
flowchart TB
    client(["<b>Client application</b><br/>Any Valkey or Redis client"])
    admin(["<b>Tenant admin / operator</b><br/>Manages tenants, keys and usage"])

    strata["<b>strata</b><br/>Multi-tenant Valkey as a service.<br/>Compute scales out; data lives in object storage."]

    obj[("<b>Cloud object storage</b><br/>S3 API<br/>SeaweedFS locally")]

    client -- "Valkey commands<br/>RESP over TCP" --> strata
    admin -- "Manages tenants<br/>HTTPS" --> strata
    strata -- "Stores and restores tenant data<br/>S3 API" --> obj

    classDef person fill:#08427b,stroke:#052e56,color:#ffffff
    classDef system fill:#1168bd,stroke:#0b4884,color:#ffffff
    classDef external fill:#8a8a8a,stroke:#5f5f5f,color:#ffffff
    class client,admin person
    class strata system
    class obj external
```

## Elements

| Element | What it is |
|---|---|
| **Client application** | A tenant's program. It uses an ordinary Valkey client library and does not know strata is behind the endpoint. |
| **Tenant admin / operator** | A person (or their automation) who creates tenants, issues credentials and reads usage and health. |
| **strata** | The system in this repo. It accepts Valkey commands, keeps each tenant's data durable, and scales compute by starting more Valkey processes. |
| **Cloud object storage** | The ultimate source of truth for tenant data. It is outside strata: a cloud bucket in production, SeaweedFS (S3 API) in local development. |

## Why it looks like this

- The client side is plain Valkey. Nothing custom is needed to use strata.
- Object storage is the only thing outside the system that must not be lost. Every process inside
  strata can be thrown away and rebuilt from it.
