---
name: data-access
description: >
  Database access rules for nexu-api: Kysely, repositories, BaseRepository with automatic
  companyId scoping, migrations (kysely-ctl) and type generation (kysely-codegen). Use this skill
  whenever creating a table, writing a migration, creating or changing a repository, writing any
  query, or handling transactions. Triggers on: "migration", "nova tabela", "new table", "query",
  "repository", "Kysely", "companyId", "soft delete", "deletedAt", "transaction", "codegen",
  "schema", "index", "banco", "database".
---

# Data Access — nexu-api

Postgres + **Kysely**. Migrations with **kysely-ctl**, types generated with **kysely-codegen**.
No ORM, no entities — repositories and typed SQL.

## Golden rules

1. **Kysely never leaves a repository.** Applications and services call repository methods;
   nobody else injects the `DB` provider. No exceptions — "just one quick query" is how god
   queries are born.
2. **Every tenant table extends the tenant base.** `companyId` scoping is automatic, never
   hand-written per query.
3. **The DB is the source of truth for types.** After migrating, run codegen; the generated
   `DB` interface is committed and never hand-edited.
4. **Raw SQL is a last resort, and "the builder can't do it" is almost always wrong.** The
   query builder covers far more than it looks like: subqueries via `eb.selectFrom(...)`,
   `.forUpdate()`, `.skipLocked()`, `.returning()`, `on conflict`, CTEs. A claim query with
   `UPDATE ... WHERE id IN (SELECT ... FOR UPDATE SKIP LOCKED) RETURNING` is fully expressible —
   and typed, so renaming a column breaks the build instead of failing at runtime.
   Raw `sql` is legitimate for: DDL in migrations (partial indexes, `IF EXISTS`), and
   Postgres features the builder genuinely lacks. When you do use it, say why in the PR.
   **Before reaching for raw SQL, compile the builder version and read the emitted SQL** —
   that is how you confirm the clause you need actually came out, since a test on a single
   connection cannot tell `SKIP LOCKED` from its absence.

## Table conventions (Zoppy style)

- Table names: **PascalCase plural** — `Companies`, `Users`, `WhatsAppConnections`.
- Columns: **camelCase** — `companyId`, `expiresAt`. (Kysely quotes identifiers automatically;
  in psql by hand you'll need `"quotes"` — known trade-off, accepted.)
- Every table: `id` (uuid, v7 — time-sortable), `createdAt`/`updatedAt` (`timestamptz`,
  default `now()`), `deletedAt` (`timestamptz` nullable) when soft-deletable.
- Tenant tables: `companyId` uuid NOT NULL referencing `Companies`. Composite indexes start with
  `companyId`.
- Global tables (no tenant): no `companyId` — e.g. `Companies` itself, lookup/config tables.
- Money: `bigint` cents, never float/numeric-with-decimals ambiguity. Currency column when needed.
- Enums: Postgres `text` + zod/const union in code (no native PG enums — migrations get painful).
- Provider payloads/raw webhook events: `jsonb`.

## Soft delete

- `delete()` sets `deletedAt = now()`. Reads exclude soft-deleted rows **by default** via the base
  repository; opting in requires the explicit `withDeleted()` variant.
- Hard delete exists only for compliance flows (LGPD erasure) — named `hardDelete`, and every call
  site is justified in the PR description (never in a code comment — see conventions).
- **Unique constraints must be partial indexes**: `CREATE UNIQUE INDEX ... WHERE "deletedAt" IS NULL`
  — otherwise a deleted row blocks re-creation forever.

## Repositories

Two bases, chosen by table kind:

```typescript
// tenant table → companyId applied automatically from request context (AsyncLocalStorage)
export class WhatsAppConnectionsRepository extends TenantRepository<'WhatsAppConnections'> { ... }

// global table → no tenant scoping
export class CompaniesRepository extends GlobalRepository<'Companies'> { ... }
```

`TenantRepository` guarantees, for every method (base helpers AND custom queries built on
`this.qb()`): `WHERE companyId = ctx.companyId` and `WHERE deletedAt IS NULL` on reads;
`companyId` stamped on inserts; updates/deletes scoped to the tenant. The companyId comes from
the session context (same AsyncLocalStorage as requestId — see observability skill); a repository
call without tenant context on a TenantRepository **throws** — it never silently queries across
tenants. Cross-tenant access (admin jobs, sweeps, pre-auth identity lookups) uses the explicit
`skipConstraint` escape hatch — greppable by design, and every use outside the identity module
is justified in the PR description (no code comment, not even here).

- One repository per table, injected ONLY by the domain that owns the aggregate (applications
  never touch repositories; repositories never inject each other). Other modules go through the
  owning module's exported services.
- Repository methods speak domain language (`revokeFamily`, `transitionHealth`), not SQL language
  (`selectWhereStatusAnd...`).
- Base API: `findOne`/`findMany`/`findAllPaginated` (public), `createRow`/`createManyRows`/
  `updateRow`/`updateManyRows`/`softDeleteRow` (protected — concrete repos expose domain-named
  methods), lifecycle hooks `before/afterCreate|Update|Delete` (sync mapping or job enqueueing;
  enqueueing waits for the afterCommit mechanism — publish-after-commit rule). Inputs of concrete
  create/update methods use `Pick<Insertable<T>, ...>` — no parallel DTO types.
- **Pagination** (`findAllPaginated`): Zoppy-style `PageRequest`/`Page` types live in
  `shared/pagination` (upper layers import from shared, NEVER from repository files).
  `searchFields`/`orderBy.property` are column names applied via dynamic refs — they must come from
  an allow-list constant in the application layer, never passed through from the frontend.

## Transactions

- Preferred: **`@UsingTransaction()`** on the application method — wraps it entirely, repositories
  join the ambient transaction automatically. `DatabaseClient.withTransaction(fn)` exists for the
  rare dynamic case. Feature code never passes `trx` around by hand.
- Post-commit work (queue publish, email enqueue) must live OUTSIDE the decorated method.
- Transactions wrap **state transitions**, not whole flows: keep them short, never hold one across
  an external HTTP call (provider APIs — Meta, SES, CRM) or queue publish.
- Concurrency on sweeps that claim rows: `FOR UPDATE SKIP LOCKED` — workers pick disjoint rows, no
  double-processing (see queues-and-scheduling skill).

## Migrations (kysely-ctl)

- Files in `migrations/`, TypeScript, `up`/`down`, named `<timestamp>_<verb>-<subject>.ts`
  (`..._create-whatsapp-connections.ts`, `..._add-health-to-whatsapp-connections.ts`).
- **Never edit an applied migration** — fix forward with a new one.
- Additive first: new column arrives nullable/defaulted, code deploys, backfill runs, constraint
  tightens in a later migration. No table rewrites on hot tables in a single step.
- Workflow: write migration → `kysely migrate:latest` → `kysely-codegen` → commit migration +
  regenerated types together. CI fails if codegen output differs from the committed file (drift
  guard).
- Migrations run in the deploy pipeline before the new app version receives traffic — never at
  app boot, never by IaC.

## Type generation and per-module models

- `kysely-codegen` reads the migrated database and generates the `DB` interface (single committed
  file). It is a build artifact: nobody reads it and nobody imports it directly.
- **Each module owns its model file** — `modules/<feature>/domain/<feature>.types.ts` — which is the
  ONLY place allowed to import from `core/database/generated` (enforced by `no-restricted-imports`).
  It exports the read and write aliases the module needs:
  `export type User = Selectable<Users>; export type NewUser = Insertable<Users>;`
- Repositories and domains import from that model file, never from the generated one. Concrete
  create/update inputs stay as `Pick<NewUser, 'email' | 'name'>`.
- Derived/domain types (status unions, value objects) live next to them in the same file.
