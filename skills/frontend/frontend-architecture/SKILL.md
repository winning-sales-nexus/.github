---
name: frontend-architecture
description: >
  Folder structure, layer boundaries, routing and state ownership for nexu-fe. Use this skill
  whenever creating a page, a feature, a route, a provider, a shared domain module, or deciding
  where a file belongs, and whenever eslint reports "Import cruza fronteira proibida". Triggers on:
  "nova tela", "new page", "feature", "rota", "route", "router", "estrutura", "onde colocar",
  "provider", "context", "estado global", "state", "arquitetura", "componente novo", "boundaries",
  "fronteira", "max-lines-per-function", "função grande".
---

# Frontend Architecture — nexu-fe

React 19 + TypeScript strict, Vite, TanStack Router (file-based, type-safe), TanStack Query,
react-hook-form + zod, Tailwind v4 + Radix. Alias `@/` points to `src/`.

## Folder structure

```
src/
├── app/                 # what ties features together
│   ├── providers/       # Query, Session, Theme, Toast, Analytics, CopilotDeal providers
│   └── layouts/         # AppShell, PageHeader, RequireRole, OnboardingGate, CopilotDock...
├── routes/              # TanStack Router file tree (routeTree.gen.ts is generated)
├── features/<feature>/  # one folder per product area (deals, home, conversations, settings...)
│   ├── api/             # query/mutation hooks + <x>-keys.ts — the ONLY place that touches the client
│   ├── components/      # components that know this domain
│   ├── pages/           # route-level components (+ *-fixtures.ts used by the page specs)
│   ├── lib/             # pure functions (*-copy.ts), small feature hooks without fetching
│   ├── schemas/         # zod schemas for this feature's forms (*.schema.ts)
│   └── types.ts         # types derived from the generated API types
├── shared/              # knows no feature
│   ├── ui/              # design-system primitives (Button, Field, Modal, Table, Toast...)
│   ├── lib/             # cn, hooks, api/ (client + shared hooks), analytics/, realtime/
│   ├── format/          # date.ts, number.ts, amount.ts (pt-BR, Intl)
│   ├── config/          # env.ts (zod over import.meta.env), roles, app-target, timezones
│   └── <domain>/        # domain modules used by 2+ features (see below)
└── main.tsx
```

Big features nest sub-areas with the same shape (`features/home/customer-profile/{components,lib,types.ts}`,
`features/settings/crm-fields/...`). `hooks/` is not a folder here: hooks that fetch go to `api/`,
the rest to `lib/`.

## Boundaries (eslint-plugin-boundaries, `eslint.config.mjs`)

Four element types: `shared` (`src/shared`), `app` (`src/app`), `routes` (`src/routes`),
`feature` (`src/features/*`, captured by name). Policy is `default: disallow`; only these imports pass:

| From      | May import                                  |
| --------- | ------------------------------------------- |
| `shared`  | `shared` only                               |
| `app`     | `shared`, `app`, any `feature`              |
| `feature` | `shared`, `app`, **its own** feature        |
| `routes`  | `shared`, `app`, any `feature`, `routes`    |

Consequences:

1. **A feature never imports another feature** (the capture `{{ from.element.captured.feature }}`
   must match). Two features need the same thing → it goes up to `shared/`.
2. **`shared` never imports `app` or a feature.** That includes `useToast`
   (`app/providers/toast-provider`): shared components receive callbacks, they do not toast.
3. `app` may import features (the shell mounts the notifications feed, the copilot, etc.); a feature
   may import `app` (`useToast`, `usePageHeader`, `useSession`, `useRole`).
4. The boundary lint covers `src/**` only; `test/` helpers may import from anywhere.

### Shared domain modules (`src/shared/<domain>/`)

`shared/` also holds domain code: `alignment`, `call-points`, `commit-deals`, `conversations`,
`deals`, `health`, `losses`. They are **not** `shared/ui`: they exist because a domain concept is
rendered by two or more features (for example the alignment deviations appear on the call page and
in the knowledge base). The shape:

- types derived from the API (`conversation.types.ts`, `alignment.types.ts`), key factory
  (`call-points-keys.ts`), pure copy (`call-point-copy.ts`, `deviation-copy.ts`), components
  (`deviation-item.tsx`, `conversation-excerpts.tsx`);
- their **data hooks** live in `shared/lib/api/use-<x>.query.ts` (`use-call-points.query.ts`,
  `use-deviations.query.ts`, `use-conversation-excerpts.query.ts`, `use-commit-deals.query.ts`),
  because `shared/lib/api` is the shared place allowed to import the client (see data-fetching).

Rule of thumb: start the code in the feature that needs it; promote to `shared/<domain>/` in the
same PR that adds the second consumer, never earlier. A generic version with no domain knowledge goes
to `shared/ui` instead. Nothing in `shared/ui` should know what a deal is; boundaries do not check
this, review does.

## Other hard rules (eslint)

- Components do not call `fetch`; only `features/*/api`, `app/providers`, `features/auth/api` and
  `shared/lib/api` are exempt from the `fetch` ban and from the client-import ban (data-fetching skill).
- No default exports, no `enum`, no comments, no `else`, no literal colour (ui-and-styling skill).
- Small units: `complexity: 10`, `max-params: 8`, `max-depth: 3`, and
  **`max-lines-per-function: 40`** (blank lines skipped; the repo lint is being lowered from 80 to 40
  in a separate change, so write to 40 now). JSX counts. Stay under it by extracting a subcomponent
  per visual block (`<DealsToolbar />`, `<PortfolioTable />`), moving derived values into pure
  functions in `lib/*-copy.ts`, moving stateful logic into a `useX` hook in `lib/` or `api/`, and
  replacing branches with early returns or lookup tables (`Record<Tone, string>`). A page composes
  components; it does not contain the markup of every section.
- `useEffect` is a last resort: derived values are computed, server data is Query's, events are handlers.

## Routing (TanStack Router, file-based)

- Files in `src/routes/`; the Vite plugin (`tanstackRouter`, `autoCodeSplitting: true`) generates
  `src/routeTree.gen.ts` (committed, ignored by lint and coverage). Never edit it.
- **Routes stay thin**: `createFileRoute(...)` wiring `validateSearch`, guards and the page component.
  Example (`routes/_authenticated/deals.index.tsx`): `validateSearch` with zod, a tiny
  `DealsRoute` reading `Route.useSearch()` and rendering `<DealsPage search={search} />`.
- `__root.tsx` is `createRootRouteWithContext<{ session: SessionContext }>`; `main.tsx` passes the
  session in `RouterProvider context`. `_authenticated.tsx` is the protected layout: its `beforeLoad`
  redirects to `/login` with `search: { redirect }` (or `/admin/login` in the admin bundle) and renders
  `OnboardingGate > AppShell > Outlet`. Guards live in `beforeLoad`/layout routes, never inside pages;
  role gates inside the shell use `app/layouts/require-role`.
- Search params are typed with zod in `validateSearch` (`.optional().catch(undefined)` so a bad URL
  degrades instead of crashing). Filters, sort and pagination live in the URL; a refreshed page renders
  the same screen. Use `Route.useParams()` / `Route.useSearch()`, never `window.location`.
- Legacy or pt-BR aliases are redirect-only routes (`negocios.index.tsx` → `/deals` with
  `search: true`). URLs are English (conventions skill).
- Pathless/escaped segments follow the plugin's rules (`onboarding_.connect.tsx`,
  `company_.connect.$source.tsx`): the trailing `_` opts out of the parent layout nesting.
- **Two bundles from one codebase**: `VITE_APP_TARGET` = `unified` (default) | `tenant` | `admin`
  (`shared/config/app-target.ts`). `npm run dev:admin` sets `admin`; in the `tenant` build
  `routeFileIgnorePattern: 'admin'` drops every `admin*` route file from the tree. Admin features and
  routes must therefore keep `admin` in the file name.

Adding a screen: page in `features/<x>/pages/`, hooks in `features/<x>/api/`, a route file in
`src/routes/`, run `npm run dev` (or `vite build`) so the tree regenerates, commit `routeTree.gen.ts`.

## State ownership

| Kind of state                              | Where it lives                                      |
| ------------------------------------------ | --------------------------------------------------- |
| Server data (anything the API owns)        | TanStack Query — never mirrored into `useState`     |
| URL state (filters, sort, page, tab)       | route search params                                 |
| Form state                                 | react-hook-form                                     |
| Session (user, role, impersonation)        | `SessionProvider` (`useSession`, `useRole`)         |
| Theme                                      | `ThemeProvider` (`useTheme`)                        |
| Toasts, page title                         | `ToastProvider` (`useToast`), `usePageHeader`       |
| Ephemeral UI (modal open, hover)           | `useState` in the component                         |
| Per-user UI preference                     | `localStorage` behind a small hook, in try/catch    |

No global store library is installed; do not add one without a second real case.

## Auth

- The access token lives **in memory** (`shared/lib/api/token-store.ts`), never in
  `localStorage`/`sessionStorage`. The refresh token is an httpOnly cookie; `client.ts` calls
  `POST /auth/refresh` on a 401 and retries once (data-fetching skill). On boot `SessionProvider`
  restores the session (`isRestoring` shows `SessionSplash`).
- Login is a 6-digit e-mail code (or Google); there is no password and no TOTP.
- Roles are `admin`, `sales_lead`, `rep` (`USER_ROLES`); `isPlatform` marks platform staff who use the
  admin bundle and may impersonate a company.
