---
name: infrastructure
description: >
  AWS infrastructure (CDK) and CI/CD (GitHub Actions) rules for nexu-api: accounts,
  environments, pipelines, secrets, cost guardrails. Use this skill whenever touching infra/,
  workflows, deploys, environment config, SSM parameters, or AWS resources. Triggers on: "CDK",
  "deploy", "pipeline", "CI", "GitHub Actions", "infra", "SSM", "secrets", "environment", "OIDC",
  "Fargate", "RDS", "VPC", "custo", "cost".
---

# Infrastructure & CI/CD — nexu-api

## Accounts & environments

Two workload accounts, one environment each: **dev** and **prod** (both `000000000000` until the
accounts exist — replace in `infra/config/` and in the deploy workflows). A management account holds
org/billing/SSO only — **nothing deploys there, ever**. Region: **us-east-1**. Local AWS access: SSO
profiles `nexu-dev` / `nexu-prod` (`aws sso login --sso-session nexu`).

## CDK (TypeScript, `infra/` in this repo)

- Same repo as the app, same language. Environment differences are data
  (`infra/config/dev.ts` / `prod.ts`), not duplicated stacks.
- **Shared constants** (`shared/*.constants.ts`) are imported by BOTH app and CDK: queue names,
  schedule expressions, message types, SSM parameter names. Drift between infra and consumers must
  be a compile error.
- CDK owns long-lived infra: VPC, cluster, RDS, queues, schedules, roles, alarms. It does NOT own:
  DB schema (kysely-ctl in the pipeline), runtime data, feature config.
- Console changes to CDK-managed resources are forbidden — if it's worth changing, it's worth a PR
  (`cdk diff` makes the review concrete).

## Environment config & secrets

Three boxes (see also local-dev skill):

1. **Non-secret config → code**: typed per-env objects in `infra/config/`, injected as plain env
   vars into the task definition. Changing config = a reviewable PR diff.
2. **Real secrets → SSM Parameter Store** (SecureString, path `/nexu/<name>`), referenced by
   CDK and injected by ECS at task start. Few by design: DATABASE_URL, OTLP token, mail/WhatsApp
   credentials. Rotation = update parameter + force new deployment.
3. **Customer credentials are DATA, not config** (CRM OAuth tokens, WhatsApp access tokens):
   Postgres + KMS envelope encryption. Never in SSM, never in env, never in logs.

Secrets Manager is not used (SSM SecureString covers us; revisit only if we need automatic
rotation lambdas).

## Health and lifecycle

- `GET /health` is liveness: static, never touches dependencies — a slow database must not make ECS
  kill the task.
- `GET /health/ready` is readiness: checks the database and returns `degraded` on failure — the
  instance leaves the load balancer without being killed.
- `app.enableShutdownHooks()` is on: SIGTERM drains in-flight requests and stops queue consumers
  before exit, so a deploy never cuts a request mid-flight.

## CI/CD (GitHub Actions)

- **Runners**: GitHub-hosted `ubuntu-latest`. The org has no self-hosted runner fleet; minutes on
  private repos are metered, so keep the heavy suites where they are a gate (PR to `main`, push to
  `main`).
- **PR**: build packages → lint → typecheck → unit → integration (Testcontainers works on GH
  runners) → **migration drift guard** (runs migrate + codegen and fails if the committed generated
  types differ) → `cdk diff` posted as PR comment. Merge blocked on red.
- **main**: build image → push ECR → migrate (kysely-ctl, from the pipeline, before traffic) →
  `cdk deploy` → **dev auto-deploys**.
- **prod**: triggered by release tag, gated by GitHub **Environment `production` required
  approval**. Same artifact promoted — never rebuilt.
- **Auth = OIDC only**: each workflow assumes a deploy role in the matching account (dev workflow
  physically cannot touch prod). Zero long-lived AWS keys in GitHub — if a workflow asks for
  `AWS_ACCESS_KEY_ID`, the workflow is wrong.
- Hooks are local convenience; **CI is the enforcement** (conventions skill).

## Cost guardrails (side-project reality)

- A budget alarm lives in the management account, created together with the accounts. Treat
  approaching it as a design smell.
- **No NAT Gateway** (~US$ 32/mo idle): dev tasks in public subnets with tight security groups;
  VPC endpoints (SQS, ECR, SSM, KMS, CloudWatch) when private subnets become necessary.
- RDS: `t4g.micro` single-AZ in dev; prod starts single-AZ too (side project — restore-from-backup
  is the DR plan; document RTO honestly instead of paying for Multi-AZ theater).
- Fargate: 1 task dev / start with 1 in prod; SQS-depth-based scaling comes later.
- Anything always-on added to the stack needs a line in the PR description stating its monthly
  cost.

## Deploy safety

- Migrations are **expand → deploy → contract** (data-access skill) — the running old version must
  tolerate the new schema.
- Rollback = redeploy previous image tag (migrations don't roll back; they roll forward).
- A failed prod deploy leaves the previous task set serving — ECS circuit breaker on, rollback
  automatic.
