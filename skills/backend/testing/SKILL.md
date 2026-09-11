---
name: testing
description: >
  Test strategy for nexu-api: unit vs integration split, Testcontainers Postgres with
  template databases, transaction-rollback isolation, factories. Use this skill whenever writing
  or changing tests, setting up test infrastructure, or deciding what level to test at. Triggers
  on: "test", "teste", "spec", "unit", "integration", "e2e", "Testcontainers", "mock", "factory",
  "coverage", "vitest", "slow tests".
---

# Testing — nexu-api

Runner: **Vitest**. Two levels, chosen by what the code touches — not by habit.

## Levels

| Level | Scope | DB | External world |
|---|---|---|---|
| Unit | services/applications with logic | mocked repositories | mocked ports |
| Integration | repositories, flows through modules, migrations | **real Postgres** (Testcontainers) | ports mocked or LocalStack |

- **Logic gets unit tests; queries get integration tests.** Never mock Kysely internals — if a test
  wants to mock the query builder, it should be an integration test (or the logic should move out
  of the repository).
- Mock at **port boundaries only** (repositories, CachePort, MailPort, QueuePublisherPort,
  provider ports). Mocking a module's private service from another test is forbidden — test through
  the public application.
- E2E over HTTP: thin smoke layer (auth flow, one happy path per controller). Not the pyramid's
  base.

## Fast integration tests (the Zoppy-pain antidote)

Suite architecture — this is why the suite stays fast as it grows:

1. **One Postgres container per run** (Testcontainers), data dir on **tmpfs** — the DB lives in RAM.
2. **Template database**: migrations run ONCE into `nexu_template`; each Vitest worker gets
   `CREATE DATABASE test_w<N> TEMPLATE nexu_template` (~tens of ms) instead of re-migrating.
3. **Transaction rollback per test**: `beforeEach` opens a transaction, `afterEach` rolls back —
   no truncation, no cross-test residue, isolation for free.
4. **Parallel workers**, one database each — no shared state, no flakiness by contention.

Rules that keep it honest:
- A test that needs COMMITTED data (testing `FOR UPDATE SKIP LOCKED`, concurrent workers) opts out
  of rollback isolation explicitly and truncates in `afterEach` — documented in the test file.
- No `sleep()` in tests. Awaiting a condition = polling helper with timeout, or the design is wrong.
- Suite budget: unit suite < 30s, integration < 3min locally. When breached, fix the harness or
  split — don't normalize slowness.

## Test data

- **Factories** per entity (`makeCompany()`, `makeUser(overrides)`) with sane defaults and uuid v7
  ids — no fixture files, no shared seed data between tests.
- Every integration test creates its own Company and runs inside its tenant context
  (`ctx.run({ companyId }, ...)`) — matching production reality, and exercising TenantRepository
  scoping constantly for free.

## What NOT to test

- Generated types, Kysely itself, Nest wiring, zod schemas doing what zod does.
- Trivial pass-through applications (delegation with no branching) — the integration test of the
  flow covers them.
- **Coverage is a gate: 85% in lines, branches, functions and statements**, measured over unit +
  integration merged (`npm run coverage:gate`; the CI runs it after the integration suite and
  blocks below the threshold). The number is a floor, not a target — a meaningful state-machine
  transition test still beats ten getter tests, and a file below 85% is a hint about what is
  untested, not a reason to add a getter test. No new coverage exclusion without the reason in the
  PR body; the only standing ones are `*.module.ts`, `main.ts`, `tracing.ts` and the generated
  database types.
