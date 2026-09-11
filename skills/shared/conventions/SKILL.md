---
name: conventions
description: >
  Language split, TypeScript & lint rules, git and PR conventions for every nexu repository.
  Use this skill whenever writing new code, naming things, committing, or opening PRs. For NestJS
  DTOs, OpenAPI decorators and the error contract, see the api-conventions skill (backend repos
  only). Triggers on: "naming", "eslint", "prettier", "typedef", "tipagem", "commit", "branch",
  "PR", "convention", "padrão", "estilo".
---

# Conventions — nexu

Applies to **every** repository in the org. Stack-specific rules live in their own skills
(`api-conventions`, `architecture`, `data-access`) and are synced only to the repos that need them.

## Language

The split is by **audience**, not by file type. How we build it is English; what it does and why we
chose it is pt-BR.

| English                                        | pt-BR                                               |
| ---------------------------------------------- | --------------------------------------------------- |
| Code: identifiers, types, file names           | Business rules (`docs/regras/`)                     |
| Routes and URLs (`/team`, `/whatsapp/connection`) | Interface labels (menu, títulos, botões)         |
| Log messages and `LOG_IDENTIFIER`              | Product decisions (`docs/<contexto>.md`)            |
| Error **codes** (`identity.invalid_email_otp`) | Error **messages** — the pt-BR catalogue per module |
| Skills (`.claude/skills/`)                     | Commits, issues, PR descriptions                    |
| Design docs (`docs/identity.md`)               | Anything a customer could read                      |

Three consequences worth spelling out, because each one has already caused a wrong guess:

- **A design doc and a business-rules doc about the same module are not duplicates.** One says the
  refresh token is opaque and rotates per family; the other says your session lasts 30 days and
  drops if someone reuses a credential. Different readers, different languages, both needed.
- **Don't translate the domain vocabulary — in prose.** "Negócio", "raio X", "leitura" are the
  words the team actually uses, and this is a BR-specific domain (PME brasileira, WhatsApp, LGPD).
  In conversation, docs, issues and interface labels, they stay in pt-BR.
- **In code, the same concept is English — and always the same English.** The code says `deal`,
  the screen says "Negócio". The risk the rule above guards against is real, so the mapping is fixed
  here instead of being decided again at each call site:

| pt-BR (fala, docs, interface) | English (code, route, identifier) |
| ----------------------------- | --------------------------------- |
| negócio                       | deal                              |
| carteira                      | portfolio                         |
| raio X                        | deal review                       |
| temperatura                   | temperature                       |
| leitura                       | reading                           |
| diagnóstico                   | diagnosis                         |
| negociação em risco           | at-risk deal                      |
| regra comercial               | sales rule                        |
| desvio de alinhamento         | rule deviation                    |
| base de conhecimento          | knowledge base                    |
| material                      | material                          |
| canvas                        | canvas                            |
| lente                         | lens                              |
| vendedor                      | rep                               |
| líder de vendas               | sales lead                        |
| gestor                        | manager                           |
| meta                          | goal                              |
| relatório do mês              | monthly report                    |
| pendência                     | pending item                      |
| tarefa                        | task                              |
| conversa                      | conversation                      |
| reunião / call                | meeting                           |
| transcrição                   | transcript                        |
| trecho                        | excerpt                           |
| vínculo                       | link                              |
| estado do negócio             | deal state                        |
| motivo de perda               | loss reason                       |
| funil                         | pipeline                          |
| etapa                         | stage                             |
| fase padronizada              | canonical phase                   |

A term missing from this table is a term that has not been decided: add the row in the same PR that
introduces it, so the second person to need it does not invent a synonym.

## Data conventions that every module inherits

Three shapes are fixed at the platform level so no module decides them again:

- **Money is an integer amount in cents, with its currency next to it** (`amountInCents: number`,
  `currency: 'BRL'`). Never a float, never a string with a decimal separator. Formatting
  (`R$ 57.300`) happens only in the front, with `Intl` in pt-BR.
- **Time is stored as `timestamptz` in UTC and read in the company's time zone.** Every company has
  `Companies.timezone` (IANA name, default `America/Sao_Paulo`). "Today", "at 7am", "this month"
  and the pace of a goal are computed in that zone — never in the server's, never in a hard-coded
  Brazil offset. A platform-wide schedule (a cron command) uses `CRON_TIMEZONE`.
- **Every external id and every idempotency key carries its provider** (`provider + externalId`,
  `hubspot:deal:123`, `jobId: \`wa-inbound-${externalMessageId}\``). Two providers can hand out the
  same id; the pair is what is unique.

## TypeScript & lint

**These rules are identical in every repo.** The eslint configs carry the same typing block; only
the exemption paths differ. A rule present in one repo and missing in another is a bug in the
config, not a difference of opinion.

- `tsconfig` strict, `noUncheckedIndexedAccess` on. ESLint `typescript-eslint` preset
  **strict-type-checked** + Prettier (formatting is Prettier's job, never ESLint's).
- **Explicit types everywhere** (`typedef`): every variable, member, property and parameter is
  annotated; every function/method declares its return type (`explicit-function-return-type` with
  `allowExpressions`, plus `explicit-module-boundary-types`); every class member declares
  accessibility. Also on: `prefer-readonly`, `no-import-type-side-effects`.
- Small units enforced: `max-lines-per-function: 40`, `complexity: 10`, `max-depth: 3`,
  `max-params: 8`.
- **No `any`** — `unknown` + narrowing. An `as` cast is replaced by a type guard.
- **No default exports. No barrel files** (`index.ts` re-exports) — they breed circular imports;
  import from the concrete file.
- File names kebab-case with the framework's suffixes: `invite.application.ts`,
  `users.repository.ts`, `use-team-members.query.ts`, `member-card.tsx`.
- Enums: `as const` object + union type, or plain string unions — never TS `enum`.

### The typedef exemption list — one reason, not a grab bag

`typedef.variableDeclaration` is off for a short list of files. The single criterion: **the
declaration is the source of a derived type, and annotating it destroys the derivation.** Anything
that fails that test is not exempt — annotate it.

| Exempt                          | What breaks if you annotate                                                                      |
| ------------------------------- | ------------------------------------------------------------------------------------------------ |
| `*.schema.ts` / `*.schemas.ts`  | `z.infer<typeof schema>` collapses to the annotation                                             |
| `types.ts` / `*.types.ts`       | `as const` maps lose the literal union (`(typeof THEMES)[keyof typeof THEMES]`)                  |
| `shared/config/*.ts`            | the config object IS the shape everything else reads                                             |
| `features/*/api/*-keys.ts` (FE) | query-key factories are consumed as `readonly [...]` tuples                                      |
| `routes/**/*.tsx` (FE)          | TanStack Router derives the route tree from the inferred `Route`                                 |
| `main.tsx` (FE)                 | `Register { router: typeof router }` — annotating `createRouter(...)` kills path typing app-wide |

Corollaries, each one learned the hard way:

- A hook's **call site** is not exempt. `const members: UseQueryResult<TeamMemberList> = useTeamMembers(1)`
  is the expected shape — the hook already declares that return type, so repeating it costs one line
  and keeps the rule uniform.
- `cva()` looks exempt-shaped but isn't: hand-write the variant props type and annotate
  (`const buttonVariants: (props?: ButtonVariantProps) => string = cva(...)`).
  `VariantProps<typeof buttonVariants>` still resolves from the annotation.
- Never annotate with a machine-generated structural blob (`UseFormReturn<{ code: string }, any, ...>`).
  Use the named type (`UseFormReturn<TotpCodeInput>`) — an annotation containing `any` is worse than
  no annotation at all.

### Flat config replaces, it does not merge

In eslint flat config, a later block that names a rule **replaces** the earlier configuration of
that rule for the matching files — options are not merged. Two blocks that both configure
`no-restricted-imports` for overlapping globs means the last one wins entirely, and the first one's
patterns silently stop firing. Order the blocks so the narrowest comes last, and absorb the broader
patterns into it rather than relying on both to apply.

## Git

- **Trunk-based**: short-lived branches off `main`, PR, squash-merge. No develop branch, no release
  branches.
- Branch names: `feat/identity-login`, `fix/webhook-dedup`, `chore/bump-kysely`.
- **Conventional commits** enforced by commitlint (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`,
  `test:`, `ci:`). Scope optional but encouraged: `feat(identity): ...`. `subject-case` rejects a
  leading uppercase — write the subject lowercase.
- Hooks (husky): pre-commit = lint-staged (ESLint fix + Prettier on staged files only);
  pre-push = typecheck + unit tests; commit-msg = commitlint. Hooks are convenience — **CI is the
  enforcement** and re-runs everything in full.
- PRs: small, one concern. Description says WHY. Skill/doc updates ride in the same PR as the
  change that makes them true — except skills themselves, which live in `winning-sales-nexus/.github` and
  are synced (see below).

### The milestone is the join key

An epic ships as a `milestone/<slug>` branch: each card is a PR against that branch, and the branch
reaches `main` in a single PR. That last PR is **the only one CI and the review ever see** —
`ci.yml` and `claude-review.yml` both filter `branches: [main]`, so a PR against the milestone runs
nothing.

Which makes one thing non-optional: **every issue of the epic — the PRD and every card — carries a
GitHub milestone whose title is exactly the branch slug.**

```
branch   milestone/fundacao
milestone            fundacao     ← same string, no prose, no accents
```

Set it when the issue is created (`gh issue create --milestone "<slug>"`), not later. It is what
lets the reviewer load the whole epic in one call and judge the code against the decisions instead
of against itself; it is also the gesture that closes the cards when the epic ships.

Planning an epic produces **three** things in that milestone, all before the first line of code:

| | |
|---|---|
| `type: prd` | one issue — the problem, the solution and the decisions |
| `type: feature` | one issue per card — a deliverable unit with acceptance criteria |
| `type: qa` | one issue — the handoff script, executed when the milestone closes (`qa-run`) |

The QA script is written **at planning time, not at the end**. Written afterwards it describes what
was built; written up front it describes what was promised, and the difference between the two is
the only thing the round is looking for.

The title is a slug on purpose. The milestone is a key, not a headline — the readable name of the
epic already lives in the PRD's title.

### "Fecha #123" does not close anything

Two independent reasons, both verified:

- GitHub only recognises `close/closes/fix/fixes/resolve/resolves` **in English**. `Fecha` is
  ordinary prose, and no link is recorded — `closingIssuesReferences` comes back empty.
- Auto-close only fires when the PR merges into the **default branch**. A card PR merges into
  `milestone/...`, so even `Closes #123` would not fire.

Write `Fecha #123` anyway — it is pt-BR and a human reads it. Just don't expect the board to move:
**closing the milestone when the epic reaches `main` is a manual step, and it is how the cards get
closed.** Skipping it is why the board accumulates delivered work marked open.

## Skills are synced, not edited in place

`.claude/skills/` in this repo is **generated**. The source of truth is `winning-sales-nexus/.github` under
`skills/<group>/<name>/SKILL.md`, and the sync action mirrors it here — a skill edited locally is
overwritten on the next sync, and one that no longer exists upstream is pruned.

To change a skill, open a PR against `winning-sales-nexus/.github`. The human approval there is the gate;
the push into this repo happens without further review because it already passed.

A skill that is genuinely specific to one repo can live locally, but it must be listed in
`sync-config.json` as an exception first — otherwise the prune deletes it.

## Comments

**No comments in code.** Clean code, small methods, strong typing — the code explains itself; if it
needs narration, refactor until it doesn't. Context that can't live in code goes in docs/ or the
skill. There is no exception — not even a `skipConstraint` outside the identity module: its
justification goes in the PR description (see data-access skill).
