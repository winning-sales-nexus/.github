---
name: caching
description: >
  Caching rules for nexu-api: CachePort, in-memory driver, key naming, TTLs, and what must
  never be cached. Use this skill whenever adding caching, creating cache keys, or reaching for
  Redis. Triggers on: "cache", "TTL", "memoize", "Redis", "Upstash", "invalidation", "CachePort".
---

# Caching — nexu-api

## The port

All caching goes through `CachePort` (abstract class — see architecture skill). MVP driver:
**in-memory LRU with TTL**, per instance. No Redis, no ElastiCache.

```typescript
abstract class CachePort {
  abstract get<T>(key: string): Promise<T | null>;
  abstract set<T>(key: string, value: T, ttlSeconds: number): Promise<void>;
  abstract del(key: string): Promise<void>;
}
```

## The one law

**Cache is always disposable.** If flushing the cache breaks correctness — duplicated sends, wrong
tenant data, lost idempotency — the data was in the wrong place. Correctness lives in Postgres:
idempotency keys, locks (`SKIP LOCKED` / advisory), rate-limit windows, state machines. This is a
design invariant, not a preference.

## What belongs in cache

- Provider API access tokens (their TTL is the cache TTL, minus a safety margin).
- Read-mostly config resolved per company (company settings, feature toggles) — short TTL (60s),
  because the in-memory driver has no cross-instance invalidation and 60s of staleness is
  acceptable for config, never for money.
- Expensive derived reads where staleness is explicitly OK (dashboard aggregates).

## Keys

`<area>:<companyId>:<rest>` — e.g. `settings:0198f3aa-...:active`, `crm-token:0198f3aa-...`.
- Tenant-scoped entries ALWAYS carry companyId in the key — a cross-tenant cache hit is a data
  leak, and the naming makes it structurally impossible.
- Global entries use `global:` prefix.
- Key builders are constants/functions next to the module that owns them — no ad-hoc string
  concatenation at call sites.

## Invalidation

TTL-first. Explicit `del()` only when the same instance wrote the change. No pub/sub invalidation
schemes on the in-memory driver — if a use case NEEDS cross-instance invalidation, that's the
trigger to introduce the distributed driver, not to build workarounds.

## When Redis arrives (deliberate upgrade, not a drift)

Trigger: multiple instances + a real need (global rate limiting, cross-instance invalidation,
hot config). Order of preference: **Upstash** (serverless, pay-per-request) or ElastiCache
Serverless **Valkey**. It's a new driver behind the same port — feature code must not change. The
one law above still applies: Redis is still not a database.
