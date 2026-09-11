---
name: api-conventions
description: >
  DTO validation with zod, mandatory OpenAPI documentation, thin controllers and the error contract
  for the NestJS repositories. Use when creating DTOs or endpoints, documenting an API, or handling
  errors. For language, typing, lint and git rules see the conventions skill. Triggers on: "DTO",
  "validation", "zod", "swagger", "openapi", "controller", "error", "exception", "problem+json".
---

# API conventions — NestJS repositories

Complements the org-wide `conventions` skill, which owns language, typing, lint and git. Everything
here is specific to the NestJS side and is not synced to the frontend.

## Validation & DTOs — zod everywhere

One validation library for the whole system: **zod** (config already uses it).

- HTTP input: zod schema per endpoint (`create-company.schema.ts` in the module's `validation/`),
  wired via nestjs-zod pipe. The inferred type IS the DTO — no class-validator, no duplicated
  interfaces.
- Queue payloads and provider webhooks: same pattern — parse at the boundary, trust types inside.
- Rule: **parse, don't validate** — after the boundary, data is typed and never re-checked.

## API documentation (mandatory per endpoint)

Zod is the single source of truth for docs — schemas carry `.describe()` on EVERY field, and the
custom decorators in `core/http` render them into OpenAPI (no `patchNestJsSwagger` — it breaks with
@nestjs/swagger v11; `zodToOpenAPI` only):

- `@ApiTags('<module>')` on every controller; `@ApiOperation({ summary, description })` on every
  endpoint — description says what happens, not just what it is.
- Request: `@ApiZodBody(schema)` for bodies, `@ApiZodQuery(schema)` for query params (renders each
  param individually with description/required).
- Response: `@ApiZodResponse({ status, description, schema })` — response schemas live in the
  module's `validation/` next to the request schemas; paginated responses compose
  `pageSchemaOf(itemSchema)` from `shared/pagination`.
- Errors: `@ApiProblemResponse({ status, description, example? })` for every AppError the endpoint
  can throw — with a realistic example (real code, realistic ids). 400 zod is documented on every
  validated endpoint.
- An endpoint without these decorators does not pass review — undocumented API is unfinished API.

The frontend's types are generated from this OpenAPI document (`openapi-typescript` against
`/docs-json`). A missing `.describe()` or a wrong response schema does not stay a documentation
problem — it becomes a wrong type in the client.

## Controllers stay thin

A controller receives, delegates and serializes. Any shape conversion beyond that (schema
introspection, DTO assembly from multiple sources, formatting) belongs to a mapper in the module's
`services/` — testable in isolation, reusable by other entry points (queue consumers, scripts).

## Error contract

**Errors carry keys, never user text.** An `AppError` has `code`, `status`, `meta` and `cause` — no
human message. Each module owns a catalog (`<feature>.messages.ts`) mapping code → pt-BR text,
registered in its ApplicationModule at boot; the global exception filter translates on the way out,
interpolating `{placeholders}` from `meta`. Consequences:

- Logs and internal flow always use the CODE — Grafana queries stay language-independent.
- A code without translation falls back to a generic message and logs `warn` — the gap surfaces
  instead of leaking technical text to the user.
- i18n later = one catalog per locale chosen in the filter; zero domain changes.
- Translation belongs to the exception FILTER, not an interceptor: interceptors miss what guards and
  pipes throw (401 from the auth guard, 400 from zod).

Rules:

- HTTP errors: **problem+json shape** — `{ type, title, status, detail, requestId }`. `requestId`
  ALWAYS present (support can find the Loki trail from a screenshot).
- Domain errors are typed classes (`EmailAlreadyInUseError`) thrown by services/applications;
  a single global exception filter maps them to HTTP. Controllers never try/catch business errors.
- Never leak internals: stack traces, SQL, provider raw errors go to logs — the response gets the
  problem+json. `meta` is serialized into the response, so a provider's raw error body must never
  be put there.
- Expected business outcomes ("invite already accepted") are NOT exceptions when they're a normal
  branch — return a result; throw only for violated expectations.
