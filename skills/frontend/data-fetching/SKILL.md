---
name: data-fetching
description: >
  How nexu-fe talks to the API: generated OpenAPI types, the openapi-fetch client, TanStack Query
  hooks in features/*/api, query-key factories, invalidation, problem+json errors and the
  auth/refresh flow. Use whenever fetching or mutating data, creating a hook, handling API errors,
  or when eslint says "Componentes não chamam fetch" / "Só features/*/api pode importar o cliente".
  Triggers on: "fetch", "api", "query", "mutation", "useQuery", "useMutation", "cache",
  "invalidate", "erro da api", "loading", "openapi", "client", "tipos da api", "api:types",
  "refresh token", "queryKey", "realtime", "socket".
---

# Data Fetching — nexu-fe

## The client is generated, never hand-written

`npm run api:types` downloads the `nexu-api` OpenAPI document (`/docs-json`, needs `SWAGGER_USER` and
`SWAGGER_PASSWORD`, API running on `localhost:3333`) and regenerates `src/shared/lib/api/schema.d.ts`
with `openapi-typescript` (committed, ignored by lint). Without a running API, dump the document
offline from the `nexu-api` (`npm run openapi:dump -- file.json`) and run
`npx openapi-typescript file.json -o src/shared/lib/api/schema.d.ts` (see the README).

`src/shared/lib/api/client.ts` builds the typed client on top of it:

- `apiClient: Client<paths>` (`openapi-fetch`, `credentials: 'include'`, base URL `env.VITE_API_URL`).
- `unwrap<T>(result)` returns `data` or throws `ApiError`; `unwrapEmpty(result)` is the same for 204s.
- An auth middleware adds `Authorization: Bearer <token>` from `tokenStore` (in memory) and, on a
  `401`, calls `refreshSession()` (one shared in-flight `POST /auth/refresh`, cookie-based), then
  **retries the request once**. `/auth/refresh` itself is never retried. A failed refresh clears the token.

A breaking change in the API breaks the type-check at the exact call site; that is the point.

**Never redeclare an API type by hand.** Derive it from `paths` and give it a readable alias in the
feature's `types.ts`:

```typescript
export type DataHygiene = paths['/indicators/data-hygiene']['get']['responses']['200']['content']['application/json'];
export type HygieneCriterion = DataHygiene['criteria'][number];
```

Domain constants that mirror an API union are `as const satisfies Record<string, ApiUnion>` objects
next to the type (`CRITERION_KEYS`), never repeated string literals.

## Hooks are the only data access

Only these places may import `shared/lib/api/client` or call `fetch` (lint: `no-restricted-imports`
and `no-restricted-syntax` are off for them):

- `src/features/*/api/**` — every feature's hooks;
- `src/shared/lib/api/**` — the client itself and hooks for **shared domain modules**
  (`use-call-points.query.ts`, `use-deviations.query.ts`, `use-conversation-excerpts.query.ts`,
  `use-commit-deals.query.ts`, `use-owner-emails.query.ts`), since `shared/` cannot import features;
- `src/app/providers/**` (session, query provider) and `src/features/auth/api/**`.

Components and pages call hooks. File names: `use-<thing>.query.ts` (`useQuery`),
`use-<thing>.mutation.ts` / `.mutations.ts` (one or several `useMutation`), `<feature>-keys.ts`.
Always type the hook's return (`UseQueryResult<T>`, `UseMutationResult<TData, Error, TVars>`) and pass
`signal` to the client so cancellation works.

```typescript
export function useDealList(query: DealListQuery, enabled: boolean): UseQueryResult<DealList> {
    return useQuery({
        queryKey: dealKeys.list(JSON.stringify(query)),
        enabled,
        placeholderData: keepPreviousData,
        queryFn: async ({ signal }): Promise<DealList> => unwrap<DealList>(await apiClient.GET('/deals', { params: { query }, signal }))
    });
}
```

`keepPreviousData` is the default for filtered/paginated lists so the table does not flash.

## Query keys

One key factory per feature (or per shared domain), in `api/<x>-keys.ts` (`features/deals/api/deal-keys.ts`,
`shared/call-points/call-points-keys.ts`). It is exempt from the `typedef` rule (the tuples must stay
inferred), but is annotated with an explicit object type as in the real files:

```typescript
export const dealKeys: {
    all: readonly ['deals'];
    review: (dealId: string) => readonly ['deals', 'review', string];
} = {
    all: ['deals'] as const,
    review: (dealId: string): readonly ['deals', 'review', string] => [...dealKeys.all, 'review', dealId] as const
};
```

- Never inline a raw array as a key at a call site: invalidation stops being greppable.
- Everything that changes the result belongs in the key; if it is in the key it is usually in the
  URL search params too, so the screen is shareable.
- A key crossing feature boundaries (`['crm-owners', ...]`) is repeated as a literal tuple in each
  factory; the shared piece is `shared/lib/api/use-owner-emails.query.ts`.

## Mutations and invalidation

- After a mutation, invalidate the narrowest key that could have changed:
  `client.invalidateQueries({ queryKey: dealKeys.review(dealId) })`, or `adminKeys.companies()` after a
  create. `await` the invalidation in `onSuccess` when the UI must show fresh data when the promise resolves.
- Prefer writing the server's answer into the cache (`client.setQueryData(key, updater)`) when the
  mutation returns the updated resource (`use-deal-suggestion-decision.mutations.ts`), and mark the
  sibling key stale with `refetchType: 'none'` if it does not need an immediate refetch.
- Optimistic updates only where the operation is trivially reversible. Never for money or CRM writes.
- Toast text lives in a pure `*-toasts.ts` (`revokedToast(label)` returns a `ToastRequest`); the caller
  does `show(...)` from `useToast()`. Mutations that should be tracked in product analytics can carry
  `meta: track({ event: '...' })` (`shared/lib/analytics/track.ts`); the `QueryProvider` reports success and failure.
- Live data: `useRealtimeEvent(event, handler)` (`shared/lib/realtime`, socket.io, re-attaches when the
  token changes) is used by `*-live.ts` hooks to update or invalidate query data. Specs mock it.

## Errors: the API speaks problem+json

`ApiError` (`shared/lib/api/api-error.ts`) carries `problem: { type, title, status, detail, requestId, meta }`
plus `status`, `requestId` and `fieldIssues()` (parses `meta.errors` into `{ path, message }[]`). A
body that is not problem+json becomes a generic pt-BR message.

- **Show `detail`**; the API writes it to be displayed. Use the shared pieces instead of hand-rolling:
  `<FailureAlert error={mutation.error} title="Não foi possível criar a empresa" />` for an inline
  block and `failureToast('Não deu para entrar', error)` for a toast.
- `FailureAlert` shows the `requestId` (small, monospace) **only for status >= 500**; for 4xx the
  `detail` is the whole message. Keep that behaviour if you build another error surface.
- `401` is the client's business (refresh + retry once), never a component's.
- `error.problem.type` (for example `identity.invalid_code`) is the stable code to branch on; never
  match on `detail`, which is a pt-BR sentence.
- `ApiError.fieldIssues()` exists for mapping server validation to fields (forms skill); today the
  forms show a `FailureAlert`/toast rather than `setError`.

## Defaults (set once in `app/providers/query-provider.tsx`)

`staleTime: 30_000`; query retry up to 2 attempts and **never for `ApiError` below 500**; mutations
never retry. Override per hook only with a reason (`staleTime: Infinity` for immutable excerpts).
Loading states use skeletons of the real layout (ui-and-styling skill), not spinners.
