# Horizon Angel

Horizon Angel is the AI intelligence and operations layer of the Horizon Core ecosystem.

## Architecture

```text
Horizon Core
    │
    ├── Ledger / Blockchain
    ├── Horizon Switch
    ├── Horizon Backend
    ├── Licensing
    ├── Settlement
    ├── Industrial Monitoring
    └── Security / Infrastructure
             │
             ▼
       Horizon Angel
             │
             ▼
         Angel Agents
```

## Role

Angel Agents provide specialized intelligence for Horizon Core services.

They may analyze approved security, infrastructure, engineering, financial,
industrial, testing, database, customer, license, GIS and operational data.

## Security Boundary

Horizon Core remains authoritative for blockchain state, transactions,
licensing, settlement, cryptography and trusted execution.

Agents must never hold private keys, sign transactions or licenses,
authorize settlement, mutate the ledger, directly write production databases,
or bypass tenant isolation and security controls.

## Intended Flow

```text
Horizon Core
     ↓
Approved API / Event / Metric / Report
     ↓
Horizon Angel
     ↓
Angel Agent
     ↓
Analysis / Recommendation / Report
```
