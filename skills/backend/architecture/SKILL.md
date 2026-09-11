---
name: architecture
description: >
  Layered architecture and module rules for nexu-api. Use this skill whenever creating a new
  feature or module, adding providers, wiring dependency injection, deciding which layer can inject
  which, or reviewing structure. Triggers on: "new feature", "novo módulo", "nova feature", "create
  module", "camadas", "arquitetura", "which layer", "inject", "DI", "dependency injection", "port",
  "abstract class", "config", "registerAs", "module structure", "bounded context".
---

# Architecture — nexu-api

NestJS + TypeScript. Layered architecture in the Zoppy style, extended with a repository layer
(Kysely) and ports (abstract classes) for dependency inversion.

## Layers and injection rules

```
controller  →  application  →  domain (injectable)  →  repository
```

| Layer       | May inject                                                                        | NEVER injects                                                   |
| ----------- | --------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| Controller  | Applications of its own module only                                               | Domains, services, repositories                                 |
| Application | Domains (own module), ports, services EXPORTED by other modules, module services  | Repositories, other applications (own or foreign)               |
| Domain      | Its OWN repository, CHILD domains of the same aggregate (parent → child entity)   | Repositories of other aggregates, applications, foreign modules |
| Service     | Domains/ports of its own module                                                   | Applications, foreign repositories                              |
| Repository  | `DatabaseClient` (+ AppContext via base) only                                     | Any other repository, anything else                             |

Hard rules (these were broken before — treat as review blockers):

1. **Application never touches a repository.** Data access goes through the domain that owns the
   aggregate.
2. **Application never injects another application.** Not in the same module, not across modules.
3. **Repository never injects another repository.**
4. **Cross-module reuse = exported service.** Code a foreign application needs becomes a `service`
   in the OWNING module, exported by that module's `@Module`, and imported by the consumer module.
   Never a foreign application, domain or repository.

### ESLint enforces the hierarchy — it is not on your memory

`eslint.config.mjs` blocks the skipping imports directly, keyed on the file-name convention
(`*.domain.ts`, `*.repository.ts`, `*-application.module.ts`, `*-repository.module.ts`):

| Layer                          | Cannot import                                                        |
| ------------------------------ | -------------------------------------------------------------------- |
| **anything outside `domain/`** | **`*.repository` — no exceptions, `core/` included**                 |
| `access/**`                    | `*.domain`, `*-domain.module`, `*.repository`, `*-repository.module` |
| `services/**`                  | `*.application`, `*-application.module`, `access/**`                 |
| `application/**`               | `*.repository`, `*-repository.module`, **another `*.application`**   |
| `domain/**`                    | `*.application`, `*-application.module`, `access/**`                 |
| `repositories/*.repository.ts` | another `*.repository`, `*.domain`, `*.application`, `access/**`     |

**Only a domain injects a repository, and that holds in `core/` too.** A `core/<infra-module>` that
persists anything gets the same `domain/` + `repositories/` split a feature module gets — being
infrastructure buys no exemption. `*.module.ts` files are the one carve-out: they _register_
providers, they do not inject them.

**Application never injects another application, and a service never injects an application.** Both
point the dependency the wrong way: a service is what an application uses, so a service reaching up
creates a cycle the moment someone tries to extract it. When two applications need the same thing,
that thing is a domain or a service — not one of them.

Type imports still cross freely — `domain/<feature>.types.ts` is data, not an injectable, so a
controller may keep importing `Company` from it, and an application may import a payload type from
another application's file. The rules use `allowTypeImports`, so write those as `import type`. The
rule targets what gets **injected**.

### Persisting from a handler: enqueue, don't reach down

A queue handler is `access`. When it needs to write, it does not grow a repository — it publishes a
job, and that job walks the hierarchy like everything else:

```
handler (access) → publishes → handler (access) → application → domain → repository
```

`core/mail` is the worked example. The send handler talks to the provider and publishes
`email.send.recorded`; a second handler consumes it and the write lands through
`EmailSendLogApplication` → `EmailSendDomain` → `EmailSendsRepository`. The write is also off the
send path, so a slow database never delays an e-mail — and the job carries a deterministic `jobId`
built from the provider's message id, so a redelivery writes one row.

The base classes (`core/database/repositories/*`) and each `*-repository.module.ts` are outside the
repository rule on purpose: extending `TenantRepository` and registering repositories in their own
module are exactly what those files are for.

If a new layer import is genuinely needed, the answer is almost always a **service in the owning
module**, not an exception to the rule.

## Layered sub-modules per feature

Each feature is composed of one Nest module PER LAYER, chained by imports:

```
<Feature>Module (root)  →  imports <Feature>HttpModule only
<Feature>HttpModule     →  imports <Feature>ApplicationModule (controllers + guards live here)
<Feature>ApplicationModule → imports <Feature>DomainModule (+ core modules); providers:
                             applications + module services; exports: applications + cross-module services
<Feature>DomainModule   →  imports <Feature>RepositoryModule; exports domains
<Feature>RepositoryModule → imports DatabaseModule/ContextModule; exports repos (feature-internal ONLY)
```

- External consumers import the LAYER module they need (`IdentityDomainModule` for domains,
  `IdentityApplicationModule` for services) — never the root module, never RepositoryModule.
- `<Feature>RepositoryModule` is never imported outside its feature: data access from outside
  always goes through the owning domain.
- Reference implementation: `src/modules/identity/`.

## Workspace packages

Framework-agnostic code that talks to a third party lives in `packages/<name>/` as an npm workspace
package, not in `src/`. Today: `@nexu/whatsapp` (Meta Cloud API client) and `@nexu/storage`.

Rules for a package:

- **Zero framework**: no `@nestjs/*`, no DB, no AppContext, no queue. Plain classes, own tsconfig,
  own build. It receives data and returns normalized DTOs.
- **Neutral errors**: it throws its own error type (`WhatsAppError`), never an `AppError`. The app
  translates at the boundary — that mapping is the app's job, not the package's.
- **The app wires it**: adapters are instantiated in a Nest module (`useValue` list) and looked up
  by a registry service. Discovery/DI stays in `src/`.
- `index.ts` is the package's public API — the only sanctioned barrel file in the repo.
- Build order: `npm run build:packages` runs before build/test/start (wired in package.json).
- Extraction to a published registry is a later, separate decision (see the tech-debt issue).

## Folder structure: module-first, layers inside

```
src/
├── modules/<feature>/          # one folder per bounded context
│   ├── <feature>.module.ts
│   ├── access/                 # controllers, queue processors, ws gateways
│   ├── application/            # orchestration: domains + ports, no data access (module-private)
│   ├── domain/                 # <entity>.domain.ts injectable aggregates (own their repository)
│   │                           # + pure types, errors, validations/ (business rules that throw)
│   ├── services/               # module services; EXPORTED ones are the cross-module surface
│   ├── repositories/           # module-private, only injected by their own domain
│   ├── ports/                  # abstract classes this module defines
│   ├── config/                 # registerAs + zod namespace
│   └── validation/             # zod schemas for this module's boundaries
├── core/<infra-module>/        # cross-cutting WITH module discipline:
│   │                           # database/, context/, cache/, queue/, mail/, observability/
├── shared/                     # pure TS only (no Nest): constants (imported by CDK too), utils
├── config/                     # app-level config (registerAs + zod)
├── app.module.ts
└── main.ts
```

Boundaries are ENFORCED by eslint-plugin-boundaries (see `eslint.config.mjs`):

- `shared` imports nothing but shared; `core` imports core/shared; modules import
  core/shared/own-module; another module ONLY via its `*.module.ts` or `services/*` (exported
  services are the cross-module surface — type-only imports are free).
- `core/` is not a dumping ground — each entry is a real module with export discipline.
- `shared/` smell test: if it knows a business concept, it belongs to some module's `domain/`.

### Anti-god-module rules (hard limits)

1. A module exports **at most 3 applications**. Need a 4th? You have two bounded contexts — split.
2. **No central config file.** Each module declares its own config with `registerAs('<feature>', ...)`
   validated with zod at boot. A module reads ONLY its own namespace.
3. **No `shared`/`common` dumping ground.** Cross-cutting code lives in a purposeful module
   (`DatabaseModule`, `QueueModule`, `CacheModule`, `LogModule`) with the same export discipline.
4. Cross-module imports: `FeatureAModule` imports `FeatureBModule` and injects a service that
   FeatureB exports. Applications, domains and repositories are never importable across modules.

## Dependency injection: abstract class as port

Interfaces are erased at runtime — we use **abstract classes** as both contract and injection token.
No `@Inject()` decorator noise, easy refactors, mockable in tests.

```typescript
// ports/cache.port.ts
export abstract class CachePort {
    abstract get<T>(key: string): Promise<T | null>;
    abstract set<T>(key: string, value: T, ttlSeconds: number): Promise<void>;
    abstract del(key: string): Promise<void>;
}

// cache.module.ts
@Module({
    providers: [{ provide: CachePort, useClass: InMemoryCacheDriver }],
    exports: [CachePort]
})
export class CacheModule {}

// any service
constructor(private readonly cache: CachePort) {}
```

Use a port whenever there is (or will plausibly be) more than one implementation, or the dependency
touches the outside world: cache, CRM and messaging providers, queue producer, mail, LLM, clock.
Do NOT create a port for something with exactly one conceivable implementation — that's ceremony,
not architecture.

## Config pattern (per module)

```typescript
// config/whatsapp.config.ts
const schema = z.object({
  WHATSAPP_DRIVER: z.enum(['mock', 'cloud']).default('mock'),
  META_APP_ID: z.string().default(''),
  WHATSAPP_WEBHOOK_VERIFY_TOKEN: z.string().default('')
});

export const whatsappConfig = registerAs('whatsapp', () => schema.parse(process.env));
export type WhatsAppConfig = z.infer<typeof schema>;
```

- Boot fails fast on invalid/missing env — never a runtime surprise.
- A module injects `whatsappConfig.KEY` via `ConfigType<typeof whatsappConfig>` — never `ConfigService.get('...')`
  with magic strings, never someone else's namespace.

## Request context — AsyncLocalStorage, NEVER Scope.REQUEST

`Scope.REQUEST` is forbidden in this codebase. It virally degrades the DI graph to per-request
instantiation and doesn't exist for queue consumers/crons — which is most of this system.

All per-flow state lives in ONE `AppContext` on AsyncLocalStorage:
`{ requestId, companyId?, userId?, txExecutor? }`. Every provider stays a singleton and reads it
via the injectable context port.

Rules:

1. **Context is created at entry points only**: HTTP middleware (requestId), auth guard
   (userId/companyId), SQS consumer (restored from MessageAttributes), tick handler, dev script.
   No service mid-flow ever creates context. The guard uses `context.enrich()` (enterWith) —
   entry-point-only API.

### Cross-cutting decorators (preferred over explicit wrapping)

- `@UsingTransaction()` — wraps the whole method in a DB transaction (nested calls join it).
  Never put post-commit work (queue publish, email enqueue) inside a decorated method — split the
  orchestration: public method calls the decorated persistence method, then publishes.
- `@AsCompany()` — runs the method inside the tenant context of its **first parameter**
  (`companyId: string`). This is the sanctioned way to act as a tenant born mid-flow (onboarding)
  or during fan-out. Convention: tenant-entering methods take companyId first.

2. **Context is immutable.** To act as another tenant (fan-out, sweeps), RE-ENTER:
   `ctx.run({ ...parent, companyId }, fn)` — never mutate the stored object (mutation after an
   async fork leaks across `Promise.all` siblings).
3. **Missing context fails loud**: `TenantRepository` throws without `companyId`. Cross-tenant
   access uses the explicit `skipConstraint` escape hatch — greppable, and legitimate mostly in
   the identity module's pre-auth flows.
4. Session/context is never passed as a method parameter — that's what the ALS removes.

## Reference implementation

`src/modules/identity/` is the fully-wired reference: every layer, sub-modules per layer, config,
catalog of messages, exported services as the cross-module surface. When in doubt about where
something goes, copy what identity does.
