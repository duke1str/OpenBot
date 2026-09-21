# Senior — OpenBot Execution Layer

This tenant package attaches the OpenBot fork to the **COS Senior** architecture.

## Command hierarchy

1. **Senior / Chief of Staff** — portfolio supervisor and final coordinator.
2. **Project Seniors** — isolated execution agents for each active project.
3. **Tools / computers / MCP connectors** — capabilities granted explicitly per project.
4. **Mem / Coda / GitHub** — durable memory, operational state, and code/evidence sources.

OpenBot is the execution layer. It does **not** replace Senior's durable brain or project guardrails.

## Initial project agents

- Senior — Chief of Staff
- Pure Profit — Health & Diagnostics
- Morrow & Grain — Commerce Operations
- Luna & KK — Production
- Publishing & Growth — Architect of Value / UNLEASHED marketing and publishing operations

## Non-negotiable boundaries

- Fail closed: an agent without an explicit grant does not get the capability.
- Credentials are isolated by project and never copied into prompts, logs, or repository files.
- External writes must be auditable through OpenBot's gateway.
- Pure Profit is PAPER-only. The OpenBot agent is diagnostic/read-oriented and has no authority to submit, cancel, replace, or close brokerage orders.
- Existing Pure Profit risk controls remain authoritative.
- Supplier negotiations never disclose Morrow & Grain retail price, target selling price, margin, or internal charges.
- Personal information is not disclosed externally. Use business information only when necessary and authorized.
- Public-facing Architect of Value and UNLEASHED assets use **C.E. Carver**.
- Project agents report verified progress back to Senior; uncertain or blocked work is reported as such, never marked complete.

## Activate locally

Copy `.env.example` to `.env`, then set:

    TENANT_PACKAGE_DIR=../examples/senior

Complete the normal OpenBot prerequisites and start with `bash scripts/start.sh`.

Before granting any write-capable MCP connector, review the agent scope and the deployment `/admin/boundaries` rules.