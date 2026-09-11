---
name: queues-and-scheduling
description: >
  BullMQ queues, message contracts, consumers, idempotency and cron/scheduling rules for
  nexu-api. Use this skill whenever producing or consuming queue messages, creating a queue,
  adding a cron/scheduled job, handling retries, or doing fan-out. Triggers on: "queue", "fila",
  "BullMQ", "Redis", "SQS", "consumer", "producer", "job", "cron", "command", "schedule",
  "agendamento", "tick", "sweep", "fan-out", "DLQ", "retry", "idempotency", "idempotência".
---

# Queues & Scheduling — nexu-api

**BullMQ over Redis Cluster.** Every internal queue lives in Redis; cron is a BullMQ job scheduler
declared in code. The one exception is the webhook ingress, and it is an ingress only — see below.

## Async is the default

**Work goes on a queue unless the caller needs the result to answer the current request.** Doing it
inline is the exception, and the exception has to be argued: what breaks if this finishes two
seconds from now instead of now?

Creating a company is the worked example. The owner's invite already leaves by queue, so a company
whose side effects all completed inside the transaction still isn't usable until the queue delivers.
Having identity seed another module's defaults inline would buy a guarantee the invite next to it
doesn't have — and would cost a global module plus a port in `shared/` to get identity talking to
that module. Published as an event (`company.created`) instead, neither module knows the other.

Inline is right when the answer is part of the response: exchanging the WhatsApp embedded-signup
code on connect (the user must be told it failed), issuing a session, checking whether an e-mail is
already taken.

Two consequences of choosing async, both non-negotiable:

- **The handler is idempotent**, because delivery is at least once. Guard on state the handler
  itself can read — a row it already wrote, a status column — never on a flag the producer sets.
- **A lost message has a reconciliation path.** Same reasoning that makes a sweep beat per-item
  scheduling: an idempotent script or a sweep that re-derives the work from the database, so a
  message that never arrives is repairable without surgery.

### Naming: publish facts, not commands

The producer publishes **what happened in its own module** (`company.created`); it never names the
consumer's work. The consumer names the class for **the job it does**, not for the cause —
`OwnerInviteSenderHandler`, not `CompanyCreatedHandler`. It doesn't send an invite _because a
company was created_; it sends the owner's invite, and a company being created is merely one thing
that asks for it.

The event contract itself belongs to neither side: it lives in `shared/events/`, imported by both.

## Topology

- **One queue per consumer purpose** (`email-send`, `whatsapp-events`, `webhook-ingestion`) —
  never one giant queue with a type switch fanning to unrelated work.
- A job that exhausts its attempts lands in BullMQ's **failed set** and is logged at `error`
  (`jobExhausted`). A job sitting there is a bug report, not noise — `/admin/queues` lists them.
- Ordering is never assumed. Per-aggregate ordering is enforced by state-machine guards, not by the
  queue.
- Queue names, command keys, cron patterns and message types are **shared constants**
  (`shared/constants/queues.constants.ts`, `shared/constants/commands.constants.ts`) — declaration
  and consumer can't drift.

## Message contract

Every message is a typed envelope:

```typescript
{
  type: 'whatsapp.health.connection.requested', // from the shared constants registry
  requestId: string,                    // propagated, never regenerated
  companyId: string | null,
  occurredAt: string,                   // ISO, event time — not send time
  payload: { connectionId: string }     // ids, not entities — consumer re-reads state from DB
}
```

- `payload` carries **ids and minimal facts**, never full entities: state may have changed between
  publish and consume; the DB at consume time is the truth.
- `requestId`, `companyId` and the OTel carrier travel **in the envelope itself** (`trace`) — the
  publisher injects and the worker resumes them automatically; feature code never touches them.

## Producer

- Publishing goes through the queue module's port (`QueuePublisherPort`) — no raw BullMQ `Queue` in
  feature code.
- **Publish after commit** — enforced by `DatabaseClient.afterCommit(fn)`: inside a transaction the
  callback is queued and only runs when the OUTERMOST transaction commits; on rollback it is
  discarded; with no transaction it runs immediately. Repository hooks (`afterCreate`, …) enqueue
  through it, which is what makes hooks safe.
- A callback that throws is logged (`database-after-commit`) and never breaks the caller — after the
  commit there is nothing left to undo.
- **Known limitation, accepted on purpose**: `afterCommit` removes the phantom-message direction
  (message about state that rolled back) but not the reverse — a crash between commit and publish
  loses the message. Our messages tolerate it: a lost invite email is re-requested, a lost tick is
  healed by the next sweep (state lives in the database, sweeps are idempotent). **Trigger to
  upgrade to a transactional outbox**: the first message whose loss cannot be healed by a re-request
  or a sweep — lost money, a charge made twice, a write to a customer's system that must happen.

## Consumer

- A consumer is an **entry point**: it restores requestId/companyId/trace context before the first
  log line, then dispatches to a handler registered for the message `type`.
- **Idempotency is mandatory.** Delivery is at-least-once — a job retried after a crash mid-handler
  WILL be seen twice. Two sanctioned strategies:
  1. **State-machine guard** (preferred): conditional transition in SQL —
     `UPDATE ... WHERE status = 'expected'` affecting 0 rows means "already processed, ack and skip".
  2. **Idempotency key**: unique constraint on a processed-keys/events table; violation = skip.
     "It probably won't happen twice" is not a strategy.
- Long work either extends its lock or splits into smaller jobs — a handler that outlives its lock
  gets picked up by a second worker while the first is still running.
- Contention on one aggregate uses `@JobMutex`, which yields with `moveToDelayed` instead of burning
  an attempt.
- A handler that throws lets the message retry; a handler that detects a permanent error (invalid
  payload, business impossibility) logs at `error` and acks — poison messages must not cycle 5
  times before dying.

## Scheduling: commands (the only cron pattern)

```
BullMQ job scheduler (pattern declared by a BaseCommand, upserted at boot)
      → job on the queue {type: 'whatsapp.health.tick.requested'}
      → sweep: SELECT ... FOR UPDATE SKIP LOCKED LIMIT n   (or a read of the active rows)
      → fan-out: one job per item (same requestId, + itemId)
      → workers process items in parallel, idempotently
```

A **command** is a declaration and nothing else — key, queue, message type, cron pattern:

```typescript
@Injectable()
export class WhatsAppHealthCommand extends BaseCommand {
  public readonly key: CommandKey = COMMAND_KEYS.whatsappHealth;
  public readonly queue: QueueName = QUEUES.whatsappEvents;
  public readonly type: string = MESSAGE_TYPES.whatsappHealthTickRequested;
  public readonly pattern: string = CRON.everySixHours;
}
```

`CommandRegistrarService` discovers every `BaseCommand` at boot and reconciles Redis against code
**in both directions**: it upserts what code declares, and it removes any scheduler ending in
`-command` that code no longer declares. Upsert alone would let a deleted command fire forever,
putting a message type on a queue no handler claims.

- **The template is static.** A scheduler stores one template and replays it on every firing, so it
  cannot carry `requestId`, `occurredAt` or `trace` — freezing those would give every tick since the
  scheduler was created the same requestId, and searching it in Loki would return all of them at
  once. The worker mints them per job (`envelopeOf`): a cron tick is a flow entry point, and entry
  points create the requestId (observability skill).
- **Commands register in every environment**, so the cron path is exercised long before production —
  a schedule that only ever runs in prod is a schedule nobody has tested. `npm run tick -- <fila>`
  stays for when you need the tick _now_ instead of at the next pattern boundary (local-dev skill).
- Per-item schedules live in **data** (a `nextActionAt`-style column, indexed), never one scheduler
  per item. Minute-level precision is enough.
- Ticks are idempotent and cheap: a duplicate tick finds no rows (they're locked or already updated)
  and exits. Missing one tick is healed by the next.
- Adding a command means adding its key to `COMMAND_KEYS`. Renaming a key orphans the old scheduler,
  which the registrar then removes on the next boot — safe, but it means a rename skips one cycle.
- **In-app cron (`@nestjs/schedule`) is forbidden.** It fires once per instance, so two instances
  double the work. A command fires once per schedule regardless of how many instances are running.

## Side effects that must never happen twice

Most duplicates are an annoyance. Some are not: charging a customer, writing into a customer's
system, sending something a person will read. Those flows are defended in layers, because each
layer can fail on its own:

1. **Deterministic `jobId`** built from what makes the work unique (the id of the thing, plus the
   period when the work is periodic). A retried tick or a redelivered job enqueues nothing new. Key
   it by what really distinguishes two legitimate runs — a key too coarse swallows a real second one.
2. **`@JobMutex` by the aggregate** when two producers can fire for the same thing at the same
   moment. The loser yields with `moveToDelayed` and keeps its attempt.
3. **A partial unique index** (`WHERE status = 'pending'`) — the layer that holds when Redis is gone.
   The insert uses `onConflict doNothing`, so the loser gets `null` rather than an exception.
4. **Idempotent emission at the provider**, keyed by our own id — for the process that dies between
   the external call and recording it. The port driver must return the same result for the same id
   instead of creating a second one.

**The external call is never inside the transaction** — holding a database transaction open across
a network call is how you exhaust the pool. So the flow must be resumable: a crash after preparing
leaves a `pending` row, and the next attempt looks for it before deciding there is nothing to do.
Transitions after the call are conditional (`WHERE status = 'pending'`), so a late second attempt
updates zero rows and says so instead of overwriting the first.

**Failures are recorded, not just logged.** A failure table with the stage, the detail and a
`resolvedAt` is what an alert can count; a log line is only enough to debug. The dangerous stage is
the last one: the side effect exists at the provider and our side does not know it.

## The one SQS: webhook ingress

Internal queues are Redis. The **only** SQS is the front door for provider webhooks (Meta/WhatsApp
today), and it exists for one property Redis cannot give: if our application is down, the event is
not lost.

```
provider → API Gateway (dumb) → SQS → bridge → WebhookIngressRouter → provider's WebhookIngressPort → application
```

- The bridge is dumb about business rules — no token validation, no parse, no adapter. It hands the
  raw message to the router, which picks the `WebhookIngressPort` whose `supports(provider)` matches
  (ports are discovered at boot; a module adds a provider by providing one). From there inward
  everything runs exactly as it does for a local HTTP request.
- **Persist before acking.** The SQS message is deleted only after the port returns, so the port
  writes the raw event to Postgres before anything moves to Redis, and publishes only its id.
  Pushing the raw body through Redis instead would move durability into memory, where an eviction
  is a lost event — the exact hole this design exists to close.
- The provider's HTTP webhook route stays for local development and calls the same application the
  port calls. One code path, local and production converging at the first hop.
