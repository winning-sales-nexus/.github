---
name: observability
description: >
  Logging, correlation, tracing, log search and alerting rules for nexu-api. Use this skill
  whenever writing log statements, creating a new flow entry point (endpoint, cron, queue consumer),
  propagating context to async jobs, wiring OpenTelemetry, investigating an incident through logs,
  or creating a dashboard or alert. Triggers on: "log", "logger", "logging", "requestId",
  "correlation", "trace", "tracing", "span", "OTel", "OpenTelemetry", "structuredMetadata",
  "LOG_IDENTIFIER", "pino", "observability", "Grafana", "Loki", "Tempo", "LogQL", "search logs",
  "buscar log", "investigar", "alerta", "alert", "dashboard", "cardinality", "cardinalidade".
---

# Observability — nexu-api

Structured JSON logs with **pino** (`nest-pino`), traces/metrics with **OpenTelemetry**, everything
shipped to Grafana Cloud via OTLP. Backend is config only — code never knows about Grafana.

## Correlation: requestId

One id finds the whole flow. Non-negotiable rules:

1. **Every flow entry point creates a requestId** (uuid v7) if none exists yet:
   HTTP request (middleware), cron tick, queue consumer receiving an EXTERNAL event (webhook).
2. **Everything downstream propagates it, never recreates it**: async jobs, fan-out, retries.
   - In-process: `AsyncLocalStorage`. The logger reads it automatically — code never passes
     requestId around by hand and never logs it explicitly.
   - Across the queue: the publisher copies requestId (and companyId) into the `QueueEnvelope`; the
     worker restores them into the context before any log line runs. This lives in the queue module
     — feature code never touches it.
3. Fan-out children keep the parent requestId. If a child needs its own identity (e.g. one job
   per connection in a health sweep), it ADDS `connectionId`/`jobId` — it never replaces requestId.

Searching `{requestId="..."}` in Loki must return the entire story: entry point → services →
queue hops → outbound calls. That is the acceptance test for this section.

## Log shape

Every log line carries (automatically, via logger context — not hand-passed):

| Field        | Source                  | Notes                            |
| ------------ | ----------------------- | -------------------------------- |
| `requestId`  | AsyncLocalStorage       | always                           |
| `companyId`  | AsyncLocalStorage       | whenever a tenant is in scope    |
| `identifier` | LOG_IDENTIFIER constant | always                           |
| `traceId`    | OTel context            | injected by pino instrumentation |
| `meta`       | call site               | structured payload, see below    |

### LOG_IDENTIFIER

Each service/flow declares one stable constant. It is the grep handle for "all logs of this
component", independent of message wording.

```typescript
const LOG_IDENTIFIER: string = 'whatsapp-webhook';

this.logger.info({ identifier: LOG_IDENTIFIER, meta: { eventId, type } }, 'webhook accepted');
```

Naming: kebab-case, `<feature>-<operation>`. Renaming one is a breaking change for saved Grafana
queries — treat it like renaming a public API.

### Structured metadata, static messages

- The `message` is **static text** — never interpolate data into it. Data goes in `meta`.
  Wrong: `` `connection ${id} is now ${health}: ${reason}` ``. Right: message
  `'whatsapp delivery health changed'`, meta `{ connectionId, health, reason }`.
- `meta` is one flat-ish object per call site. IDs, counts, enums, durations — yes.
  Whole entities, raw provider payloads, buffers — no (log the id, fetch the data in the DB).

### Error codes in logs

Log the error CODE (`identity.invalid_email_otp`), never the translated message. The message is a
presentation concern resolved at the HTTP boundary; the code is the stable handle for dashboards
and alerts.

### PII — hard rule

Never log personal data — of our users or of the people they talk to: name, email, phone,
document, message content, transcript text. Log the ids (`userId`, `connectionId`) instead. Raw
provider payloads are stored in the database, not in logs. There is no "just this once".

The same line applies to credentials, and a URL is where they hide: a webhook URL can end in the
token that authorizes posting as that provider. Log the shape, mask the secret —
`https://.../webhooks/<provider>/***`.

### Cardinality — labels vs structured metadata

Where a field lands decides what it costs. Loki bills by stream: every distinct combination of
**labels** is a new stream, and a tenant id as a label multiplies streams by customer.

- **Labels** (stream selector, `{}`): `service_name`, `deployment_environment_name`, `level`.
  That list is closed. Adding to it is a capacity decision, not a convenience.
- **Structured metadata** (filter with `|`): everything else — `identifier`, `requestId`,
  `companyId`, and every `meta` key. Filtering on these is cheap and does not create streams.
- **Metric labels**: `companyId` is **never** one. Allowed labels are closed sets — `provider`,
  `result`, `reason`, `queue`, `outcome`, `template`. Slicing by tenant is a job for logs and
  traces, never for metrics.

## Field reference

What exists to search on, by `identifier`. Adding an identifier or a `meta` key means updating this
table — same rule as renaming one.

| `identifier`                  | Covers                                                             | Distinctive `meta` keys                                                                                          |
| ----------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `identity-auth`               | Login, invite, OTP, TOTP lifecycle, password changes               | `userId`                                                                                                         |
| `auth-refresh-reuse`          | Refresh token reuse — family revoked                               | `familyId`, `revokedSessions`, `userId`                                                                          |
| `identity-company-onboarding` | Company creation                                                   | `companyId`, `ownerUserId`                                                                                       |
| `identity-company-settings`   | Company settings changes                                           | `companyId`                                                                                                      |
| `identity-team`               | Team invites, role changes and member removal                      | `companyId`, `userId`, `role`                                                                                    |
| `whatsapp-connection`         | Embedded signup: connect, disconnect, invalidation, failed step    | `wabaId`, `phoneNumberId`, `connectionId`, `step`, `reason`                                                      |
| `whatsapp-webhook`            | Meta webhook verification and delivery                             | `statusCount`, `inboundCount`, `externalMessageId`, `reason`                                                     |
| `whatsapp-health`             | Connection health sweep and per-connection transitions             | `connections`, `connectionId`, `health`, `reason`                                                                |
| `webhook-ingress`             | SQS bridge: consumer lifecycle, provider routing, handler outcome  | `provider`, `messageId`, `reason`, `detail`, `queueUrl`, `batchSize`                                             |
| `queue-consumer`              | Worker startup, enqueue failure, missing handler                   | `queue`, `type`, `detail`                                                                                        |
| `email-send`                  | Delivery                                                           | `template`                                                                                                       |
| `email-feedback`              | SES feedback via SNS → SQS: stored, suppressed, unroutable, failed | `type`, `eventType`, `providerMessageId`, `messageId`, `reason`, `detail`                                        |
| `realtime-publisher`          | Redis pub/sub emit (skipped without tenant, publish failure)       | `event`                                                                                                          |
| `realtime-gateway`            | WS connect/reject/disconnect, subscriber bridge, delivery failure  | `socketId`                                                                                                       |
| `http-error`                  | Unhandled exceptions, untranslated error codes                     | `code`, `err`                                                                                                    |
| `llm-bedrock`                 | Converse call retries and final failure                            | `modelId`, `attempt`, `maxAttempts`, `retryable`, `awsError`                                                     |
| `llm-claude-code`             | Local-only driver over `claude -p`: run summary, bridged tool calls, CLI failure | `modelId`, `purpose`, `durationMs`, `turns`, `costUsd`, `models`, `tool`, `toolUseId`, `resultChars`, `isError` |
| `llm-conversation`            | Tool-loop conversations: round cap, cost-cap refusal, tool failure | `name`, `used`                                                                                                   |
| `llm-metering`                | Monthly cap refusal, unmetered generation (no tenant)              | `period`                                                                                                         |
| `llm-pricing`                 | Model missing from `LLM_PRICE_TABLE` (cost recorded as zero)       | `modelId`                                                                                                        |
| `meetings-registration`       | Meeting occurrence registered, duplicate, skipped as internal, cancelled | `meetingId`, `platform`, `audience`, `source`, `botCancelled`                                              |
| `meetings-bot`                | Bot requested at the provider, lifecycle applied or ignored, unknown bot | `meetingId`, `provider`, `botId`, `lifecycle`, `detail`, `kind`                                            |
| `meetings-webhook`            | Provider webhook accepted, rejected, unparseable or unconfigured     | `kind`, `code`, `reason`, `setting`, `detail`                                                                    |
| `meetings-artifacts`          | Transcript and audio collected to the lake, or the meeting closed without them | `meetingId`, `transcriptArtifactId`, `audioArtifactId`, `durationSeconds`, `outcome`, `lifecycle`  |
| `meetings-reconcile`          | Reconciliation sweep fan-out                                        | `stale`, `awaitingOutcome`, `awaitingBot`                                                                        |
| `calendars-connection`        | Calendar connected, rejected or disconnected                        | `provider`, `connectionId`, `reason`                                                                             |
| `calendars-sweep`             | Calendar sweep fan-out, per-user outcome, failure, invalidation     | `connectionId`, `userId`, `provider`, `listed`, `registered`, `cancelled`, `withoutLink`, `alreadyStarted`, `kind` |

`message` is static by rule, so it is a reliable filter — but it travels as the **log line**, not as
structured metadata, so the filter is the line filter: ``|= `whatsapp connection failed` `` works
and ``| message=`whatsapp connection failed` `` silently matches nothing (measured on a production
Loki: zero hits where the line filter finds them). Because it is a substring match, two messages where one
contains the other cannot be told apart — name them so neither is a prefix of the other
(`... census company` / `... census summary`, never `... census` and `... census summary`).

## Searching

The entry point is almost always one of three handles.

**From a requestId** — the whole story, across HTTP, queue hops and workers:

```logql
{service_name="nexu-api"} | requestId="0199..."
```

**From a tenant** — everything that happened inside one company:

```logql
{service_name="nexu-api"} | companyId="0199..."
```

`companyId` is structured metadata, never a label, so this filter is cheap and creates no streams.

**From a component** — behaviour of one subsystem regardless of wording:

```logql
{service_name="nexu-api"} | identifier="whatsapp-health" | health="failing"
```

**Counting, not reading** — turn any filter into a rate to see shape instead of lines:

```logql
sum by (step) (count_over_time(
  {service_name="nexu-api"} | identifier="whatsapp-connection" |= `whatsapp connection failed` [1h]))
```

**Pivoting to the trace**: every line carries `trace_id` (injected by the pino instrumentation), so
a log line links straight into Tempo. Use logs to find _which_ execution, traces to see _where_ the
time went. `requestId` survives batching and manual replays and is what support asks the customer
for; `trace_id` is per-execution plumbing.

**What is deliberately absent**: no name, e-mail, phone, document, message content or transcript.
When an investigation needs the raw provider body, it is in the database, keyed by the `eventId` in
the log — not in Loki.

## Alerting

- **Alert on absence, not only on errors.** The failure mode of this product is silence: a stalled
  sync or sweep throws nothing, it just stops producing. Any periodic producer needs a
  "did not run in the last N" rule.
- **`NoData` must map to `Alerting`** on those rules. The Grafana default resolves no-data to OK,
  which is exactly backwards when the absence of the signal _is_ the incident.
- **An alert with no contact point is not an alert.** Routing is part of the definition of done.
- **Rules follow the data.** Provisioning dashboards and rules before telemetry flows produces
  permanent `NoData` noise, which teaches the team to ignore alerts — the worst possible outcome.
- Alert on the **age of the oldest waiting job**, not on queue depth. Depth alone hides a stuck
  consumer behind healthy-looking numbers.

## Levels

- `error` — flow broken, human may need to act. Always include the error and the ids to replay.
- `warn` — degraded but self-healing (retry scheduled, fallback used, circuit open).
- `info` — state transitions that matter: flow started/finished, entity state changed, message sent,
  webhook accepted/rejected. One line per meaningful transition — not per function call.
- `debug` — everything else. Off in production by default.

## Tracing

**Auto-instrumentation is the baseline; manual spans are the exception.** `src/tracing.ts` starts the
OTel SDK BEFORE any application import (first line of `main.ts`) — instrumentation patches modules at
load, so importing the app first silently disables everything. It also loads the env file itself,
because Nest's ConfigModule has not run yet.

What it gives for free: HTTP server/client, Postgres, AWS SDK (SQS/SES/S3/KMS) and pino log
correlation (`trace_id`/`span_id` in every line). **Never write a span per controller** — that is
noise. Write one only when the name is a business concept (`whatsapp.exchange_signup_code`) via
`TracingService.withSpan`.

**Queue propagation is mandatory and is the part everyone gets wrong.** The publisher injects the
W3C carrier into the envelope (`trace` field) and the consumer resumes it with
`TracingService.continueFrom`, so a webhook that is accepted, queued and processed by a worker is
ONE trace. Verified end to end: the same `trace_id` appears in the HTTP log and in the worker log.

**Attributes over span count.** Every span carries `companyId`, `requestId` and the domain ids that
matter (`connectionId`, `provider`). Same PII rule as logs — ids only, never personal data.

**Sampling**: 100% while volume is small (best debugging, fits the free tier). The trigger to move to
tail sampling with a Collector is the bill, not aesthetics.

**Traces don't replace metrics**: the same SDK exports OTel metrics (RED per route and per queue
handler). Use metrics for rates and percentiles, traces for the individual story.

requestId and traceId coexist on purpose: traceId is per-trace plumbing, requestId is the business
handle that survives batching and manual replays — and it is what support asks the customer for.

## Connection

Grafana stack: not created yet — record its slug and region here when it is (see the
nexu-observability README). Datasources when writing queries follow the Grafana Cloud defaults:
`grafanacloud-prom`, `grafanacloud-logs` (Loki), `grafanacloud-traces` (Tempo).

Local/dev env values live in `~/.config/nexu/grafana-otlp.env` (push token in a sibling file;
the service account token for the Grafana API is `grafana-sa-token`, next to it). In AWS they are
secrets injected into the task. Exporter is OTLP http/protobuf; switching backends is an env change,
never a code change. Self-hosting the LGTM stack is a deliberate future decision, triggered only
when Grafana Cloud free tier limits actually hurt.

**Logs travel the same pipe as traces.** A pino transport turns each line into an OTLP LogRecord and
ships it through the gateway already configured — one exporter, one auth, and `service.name` matches
the traces, so log↔trace correlation is free. A collector sidecar (Alloy) is the fallback for
scraping containers that are not ours, not the default.

Note the trap: `@opentelemetry/instrumentation-pino` only **injects `trace_id` into the line**. It
ships nothing. Enabling it without the transport produces logs that look correlated and never leave
stdout.
