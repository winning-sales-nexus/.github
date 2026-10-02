---
name: testing
description: >
  Test strategy for nexu-fe: Vitest + Testing Library + MSW, the shared render helpers, fixtures,
  how to mock the API and what the 85% coverage gate measures. Use whenever writing or changing
  tests, or when `npm run test:cov` fails the threshold. Triggers on: "test", "teste", "spec",
  "vitest", "testing library", "msw", "mock", "cobertura", "coverage", "fixture", "renderWithProviders",
  "renderRouterAt".
---

# Testing — nexu-fe

**Vitest 4 + Testing Library (+ user-event, jest-dom) + MSW 2**, environment `jsdom`. Same runner as
the API, one mental model.

| Command              | What it does                                                        |
| -------------------- | ------------------------------------------------------------------- |
| `npm test`           | `vitest run --config vitest.config.ts` (also the pre-push hook)     |
| `npm run test:cov`   | same with v8 coverage and the 85% gate (what CI runs)               |
| `npm run test:watch` | watch mode                                                          |

Run only the specs you touched while developing (`npx vitest run path/to/x.spec.tsx`); CI runs all.

## Layout and config

- Specs sit **next to the code**: `foo.ts` → `foo.spec.ts`, `foo.tsx` → `foo.spec.tsx`. The runner
  includes only `src/**/*.spec.{ts,tsx}`. `globals` is off: import `describe`, `it`, `expect`, `vi`
  from `vitest`.
- Shared test infrastructure is in `test/` at the repo root (outside `src/`, not aliased, so specs
  import it relatively: `'../../../../test/msw/server'`):
  - `test/setup.ts` — jest-dom matchers, MSW server lifecycle with **`onUnhandledRequest: 'error'`**,
    `cleanup` + `resetHandlers` after each test, `asyncUtilTimeout: 5000`, and jsdom stubs
    (`IntersectionObserver`, `ResizeObserver`, pointer capture, `scrollIntoView`, `scrollTo`).
  - `test/msw/server.ts` + `test/msw/handlers.ts` — default handlers returning **empty/neutral**
    payloads for the endpoints the app shell and most pages hit on mount (`*/crm/owners`, `*/pipelines`,
    `*/notifications`, `*/team/members`...). `auth/refresh` answers `401` by default (signed out).
  - `test/render.tsx` — `renderWithProviders(ui)`: Theme + QueryClient (`retry: false`) + Session +
    Toast + CopilotDeal + PageHeader providers. `renderInRouter(ui)` additionally mounts it under a
    memory-history router (needed for `Link`/`useNavigate`).
  - `test/router.tsx` — `renderRouterAt('/deals')` mounts the **real route tree**
    (`routeTree.gen.ts`) in memory history and returns the router, so you can assert
    `router.state.location`. Use it for pages, guards and search-param behaviour.
  - `test/fixtures/` — typed factories for large API objects (`fillPropertyOf(overrides)`).
- Page-level fixtures that are only for page specs live beside the page as `*-fixtures.ts`
  (`features/data-hygiene/pages/hygiene-fixtures.ts`), built with small `xOf(overrides: Partial<X>)`
  factories typed with the feature's `types.ts`.
- Config (`vitest.config.ts`): `maxWorkers: 4`, `testTimeout: 15_000`, `setupFiles: ['./test/setup.ts']`.

## Coverage gate

`coverage.thresholds`: **85%** for lines, branches, functions and statements, v8 provider, over
`src/**/*.{ts,tsx}` minus `*.spec.*`, `src/routeTree.gen.ts`, `*.d.ts` and `src/main.tsx`. The
gate is global, so a PR that adds untested code lowers the average for everyone: new logic ships with
its tests in the same PR. Sonar reads `coverage/lcov.info`. Coverage is a signal read on the diff,
not a number to game.

## What we test, at which level

| Level     | Scope                                                                   | Tools                      |
| --------- | ----------------------------------------------------------------------- | -------------------------- |
| Unit      | pure logic: `*-copy.ts`, `format/*`, `lib/*`, schemas, key factories    | Vitest                     |
| Hook      | providers and generic hooks (`renderHook`)                              | RTL `renderHook`           |
| Component | a component or whole page from the user's point of view                 | RTL + user-event + MSW     |

There is no E2E suite in this repo.

## Rules

1. **Query by role, label or text.** `getByRole`/`findByRole` with a name first. `data-testid` is a
   last resort (a handful exist, e.g. the catalog and card specs); if something is hard to query it
   is probably hard to use, so fix the accessibility first.
2. **The API is mocked at the network level with MSW**, never by stubbing feature hooks. Override a
   single endpoint per test with `server.use(http.get('*/path', () => HttpResponse.json(...)))`;
   paths are matched with the `*/` prefix. Error cases return the real problem+json shape
   (`{ type, title, status, detail, requestId }`) so `ApiError` and `FailureAlert` are exercised for real.
3. **Every request needs a handler** (`onUnhandledRequest: 'error'`). A new endpoint on a screen
   that other specs render means adding a neutral default to `test/msw/handlers.ts`; an endpoint
   specific to one page is `server.use` in that spec.
4. **Sign in with MSW, not with mocks**: a helper in the spec overrides `*/auth/refresh` (returns
   `{ accessToken }`) and `*/auth/me` (returns the user with the `role` under test), then
   `renderRouterAt(path)` (see `data-hygiene-page.spec.tsx`'s `signInAs`).
5. **Allowed `vi.mock`s are for things jsdom cannot do**: `@/shared/config/env` (via `vi.hoisted`),
   `socket.io-client` and `@/shared/lib/realtime/use-realtime-event`, `posthog-js`, browser-location
   helpers, `useNavigate` from the router in isolated component specs. Do not mock query hooks, the
   API client, or components.
6. **Test behaviour, not implementation**: "shows the score after loading", not "calls useQuery".
   Refactors must not break tests.
7. Every screen has at least: happy path, empty state, API error (message visible) and, when it has
   a form, one validation failure and one server refusal. Role-dependent screens test each role that
   sees something different.
8. `await screen.findBy...` over `waitFor` + `getBy`; use `waitFor` only to assert on non-DOM effects
   (a mock called, request body captured). No arbitrary `setTimeout`. `userEvent.setup()` per test.
9. Specs follow the same lint as the code: explicit types, no comments, no default exports (only
   `local/no-else` and `local/no-search-in-loop` are off in specs), and each `it`/helper stays under the
   40-line function limit, so extract `serveX()` / `signInAs()` helpers and fixtures rather than
   inlining 60 lines of setup.

## What NOT to test

Generated API types (`schema.d.ts`), `routeTree.gen.ts`, Tailwind classes, Radix internals, or that a
library does what its docs say.
