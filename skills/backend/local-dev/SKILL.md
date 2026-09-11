---
name: local-dev
description: >
  Local development environment for nexu-api: docker compose services, env generation,
  simulating queues/ticks/email locally. Use this skill whenever setting up the project locally,
  adding a compose service, debugging local infra, or wiring a new external dependency for dev.
  Triggers on: "local", "docker compose", "LocalStack", "Mailpit", "ambiente local", "rodar
  localmente", "env", ".env", "seed", "tick local".
---

# Local Development — nexu-api

Everything runs in `docker compose`; the app runs on the host (`npm run start:dev`).

## Services

| Service    | Image                 | Ports                   | Purpose                                          |
| ---------- | --------------------- | ----------------------- | ------------------------------------------------ |
| postgres   | postgres:16           | 5432                    | dev database (normal volume; tmpfs is for tests) |
| localstack | localstack/localstack | 4566                    | SQS + SSM + KMS emulation                        |
| mailpit    | axllent/mailpit       | 1025 (SMTP) / 8025 (UI) | catches all outbound email                       |
| lgtm       | grafana/otel-lgtm     | 4318 (OTLP) / 3000 (UI) | local Grafana+Loki+Tempo+Prometheus              |

- **Mailpit, not Mailhog** (Mailhog is unmaintained). MailPort's SMTP driver points at 1025; every
  email the app sends appears at `localhost:8025` — also queryable via REST API in E2E tests.
- **LocalStack**: AWS SDK v3 redirects via `AWS_ENDPOINT_URL=http://localhost:4566` — an env var,
  never conditional code. `compose/localstack-init/` holds the bootstrap script creating queues +
  DLQs on container start (names imported from the same shared constants the CDK uses).
- **lgtm**: local telemetry stays local — dev traffic never pollutes the real Grafana. Same OTLP
  pipeline as prod; only the endpoint differs.

## Env

- `.env` is **generated, never hand-maintained**: `npm run env:pull` composes it from the
  versioned dev config (non-secrets) + SSM via SSO profile when needed (real secrets) + local
  overrides for compose endpoints. `.env.example` is documentation of the shape only.
- Local defaults NEVER contain real provider credentials — sandbox/test accounts only (see the rule
  below).

## Simulating the world

- **Queues**: BullMQ over the Redis Cluster the compose file brings up — consumers run inside
  `start:dev` normally.
- **Cron ticks**: cron commands register locally too, so the schedule really fires. When you don't
  want to wait for the next boundary, `npm run tick -- <name>` publishes the tick by hand (e.g. the
  WhatsApp connection health sweep).
- **Webhooks**: `npm run webhook:replay -- <fixture>` posts a stored provider payload (from
  `test/fixtures/webhooks/`) to the local endpoint — the fixtures double as integration test input.
- **Email**: just send — Mailpit catches everything. There is no path to a real mailbox from local.
- **LLM** (every task behind `core/llm`): `LLM_DRIVER=mock` echoes and costs nothing. `bedrock` uses
  the AWS credential chain of the dev account and needs every model priced in `LLM_PRICE_TABLE`.
  `claude-code` runs the machine's own `claude -p` on the developer's plan — no API key, no token in
  `.env`, it reads the login Claude Code already has; boot refuses it outside `IS_LOCAL=true`. Models
  are the CLI aliases (`LLM_MODEL_ID=haiku`, `LLM_MODEL_ID_RICH=sonnet`). The tool loop runs inside
  Claude Code, so per-round model routing, `maxTokens` and `temperature` do not apply there.

## Safety rails (non-negotiable)

- Local/dev always points at **provider sandboxes and test accounts** (HubSpot test account, Meta
  test number) — never production credentials of anyone.
- Message sending in non-prod requires the sandbox/no-real-send guard: WhatsApp/email drivers in
  dev refuse non-allowlisted recipients. A dev environment that can message a real person is an
  incident, not a convenience.

## First run

```
docker compose up -d
npm run env:pull
npm run migrate:latest && npm run codegen
npm run seed:dev          # creates a dev Company + User (invite flow pre-completed)
npm run start:dev
```

`seed:dev` is idempotent — safe to re-run. It seeds ONLY local-obvious data (company "Dev Corp",
user dev@nexu.local) and refuses to run when NODE_ENV=production.
