---
name: pr-review
description: >
  Reviews a pull request against the invariants written in this repository's skills. Use when asked
  to review a PR or review code, or when the review action fires. Triggers on: "revisar PR",
  "review", "code review", "revisão de código".
argument-hint: '[pr-number]'
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash(git diff:*)
  - Bash(git log:*)
  - Bash(gh pr view:*)
  - Bash(gh pr diff:*)
  - Bash(gh pr comment:*)
  - Bash(gh issue view:*)
  - Bash(gh issue list:*)
effort: high
---

# PR review — nexu

You review **against what this repository has already decided**, not against generic best practice.

A reviewer who says "consider adding tests" is ignored within two weeks. A reviewer who says "this
contradicts the PII rule you wrote yourselves, and the log ships to Loki with 14-day retention" gets
read.

## The rule that governs everything

**Silence when there is nothing.** Don't write "LGTM", don't summarize the PR, don't compliment. If
you found nothing concrete, finish without commenting. That is what makes a comment mean something.

An invented finding costs more than a missed one: it teaches the team to ignore the next review.

## How to review

The argument is the **PR number**. Use it in every `gh` command — in a CI checkout `gh` cannot
detect the PR on its own, and a command without the number either fails or reviews the wrong thing.

### 1. Load what was decided — before the diff

The decisions are not in the diff. Read them first, or you will check the code against itself and
miss the only thing worth catching: code that ships something other than what was agreed.

Start from the branch: `gh pr view <number> --json headRefName,title,body`.

**A `milestone/<slug>` branch carries a whole epic.** The GitHub milestone is titled with that same
`<slug>` and holds every issue of the epic — one call brings all of it:

```
gh issue list --milestone "<slug>" --state all --limit 100 --json number,title,labels,body
```

- **The PRD.** Normally the issue labelled `type: prd`. Older epics predate that label and carry
  `type: feature` with a title starting `Épico:` or `[PRD]` — take that one when no issue in the
  milestone has the label. **Read it whole.** Its decision tables are the contract: where the
  product may never assert, which model runs which task, what each role is allowed to see.
  That is the business knowledge the diff cannot give you.
- **The cards** are the remaining issues. Read the context and the acceptance criteria of each.
- **The QA script** is the `type: qa` issue, when there is one. It is not a card and has no code
  of its own — never report it as undelivered. Read it as a second view of the same promise: a
  case describing behaviour you cannot find anywhere in the diff is worth a look.
- A milestone with no PRD is a flat list of cards. Review against the cards and don't invent a
  missing document.

**Any other branch is a single change.** The PR body is the context, plus any issue it cites
(`gh issue view <n>`).

If the milestone is missing or empty, open your comment with one line saying you reviewed without
the epic context, then review on the diff alone. **Do not reconstruct the epic from commit
messages** — a guessed context produces confident findings about rules nobody wrote.

### 2. Read the diff

`gh pr diff <number>`. If it is large, read the whole files that matter — a diff without context
produces false positives.

### 3. Load the skills relevant to what changed

They are the authority, not your memory. Which ones exist depends on the repo — `conventions` is
everywhere; a backend repo also carries `api-conventions`, `architecture`, `data-access`,
`observability`, `queues-and-scheduling`, `testing`. List `.claude/skills/` if you are unsure.

### 4. Walk the invariants below

### 5. Verify every finding before writing it

Open the file, confirm the problem exists in the code as it stands now, and build the concrete
scenario in which it fails. If you cannot describe input and consequence, it is not a finding.

### 6. Comment once, with every finding

`gh pr comment <number> --body "..."`

## Invariants

What lint already catches — layer hierarchy, explicit types, `any`, barrel files — is **not your
job**. If CI passed, it is settled. Focus on what no automated rule expresses.

### What was agreed

This section exists only when step 1 gave you a PRD or cards. It is the one place where you may find
a defect in code that is internally correct — and it is the reason the review reads the epic at all.

- **Code that contradicts a closed decision is a finding.** A PRD decision table is not a
  suggestion: "o writeback é aprovado campo a campo" means an endpoint that approves every field at
  once is a defect, however clean the code is.
- **An acceptance criterion with no code and no test is a finding.** Name the card and the
  criterion. A milestone PR that quietly drops a card is exactly what this review exists to catch,
  because no smaller PR was ever reviewed.
- **Behaviour no card describes is a finding.** It reached `main` without anyone agreeing to it.
- **A number that disagrees with the PRD** — a ceiling, a window, a price, a retry count, a
  percentage — goes at the top, with money. The PRD is the claim; the code is what will run.

Not a finding: something the PRD describes that this PR postponed **on purpose and says so** in its
body. Read the body before accusing. Nor is the PRD itself under review — it is the yardstick, and
disagreeing with the product decision is not your job.

### Money and number

- A monetary value is an **integer of cents**. A percentage is an **integer of basis points**. No
  `float` in a migration, a domain or an adapter.
- Division that produces a fraction of a cent needs explicit, tested rounding.

### Personal data

- **No PII in logs**: name, email, phone, document, message content, transcript text. This covers
  log `meta` and anything reaching `mirrorToJob`.
- The subject here is often **the customer's own contact** — the buyer on a call or in a WhatsApp
  chat, someone who never had a relationship with nexu. Raw provider bodies live in the database,
  not in the log.

### Secrets

- A secret environment variable has no `.default()` that is usable in production.
- A credential never appears in a log, in an API response, or in a column name.

The Database and Queues sections below apply to repos that have them. Skip a section the repo has
no surface for — a frontend PR is not deficient for lacking a migration.

### Database

- A migration is additive: a new column arrives nullable or with a default, the constraint tightens
  later.
- An applied migration is **never edited** — you fix forward.
- A partial unique index respects `deletedAt IS NULL`.
- A provider name never enters a column name.
- `skipConstraint` outside identity is justified in the PR body — never by a code comment.

### Queues

- A publish carries a deterministic `jobId`, or the PR explains why it does not need one.
- A handler is idempotent: redelivery must not charge, send, write to the CRM or record twice.
- No queue `EventEmitter` without an `error` listener.

### Published rules

- If the PR changes behaviour described in `docs/regras/`, the document changes in the same PR.
- If the PR **contradicts** something already published there, that is a finding — a published rule
  the product does not honour is a promise broken in front of the customer.

### Tests

- A new domain rule without an integration test is a finding. Generic coverage is not.

## Comment format

**On a milestone PR, the first line is the QA round.** Not a verdict, not a gate — a fact, stated
where the merge decision is made. Read the `type: qa` issue's comments; the newest round is the one
that counts:

> **Rodada de QA:** 07/09 — 20 ✓ · 1 ✗ · 1 ⊘. O ✗ (#851, reenvio do convite) segue aberto.

> **Rodada de QA:** nenhuma registrada nesta milestone.

Say it even when everything passed, and say it even when you found nothing else — this line is the
one exception to the silence rule, because its absence is indistinguishable from a clean round.
Never assert a round happened without a comment to point at, and never soften "nenhuma registrada"
into something that sounds fine.

Then open the findings with one line stating how many and at what severity. Then one block per finding:

**`path/to/file.ts:123` — what is wrong**

One sentence stating the defect. One sentence stating the concrete scenario in which it breaks —
input and consequence, not theory. If the fix is obvious, one line saying what it is.

Order by severity: money and personal data first, then a decision the code contradicts or a
card it dropped, then integrity, then the rest.

**Write the comment itself in pt-BR**, in full sentences — the skill is English because it is how we
build, but a PR comment is read by the team and belongs in the pt-BR column of the conventions
table. Keep the domain vocabulary untranslated: "negócio", "raio X", "leitura" are the words the team
uses. No arrow chains, no unexplained acronyms, no labels that only make sense to someone who read
the whole diff — the person reading your comment did not follow your reasoning.
