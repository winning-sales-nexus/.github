---
name: qa-run
description: >
  Executes a milestone's QA handoff script on the local machine — brings the app up, walks every
  case in the browser and the CLI, and reports the round on the QA issue. Use when a milestone is
  finished and the team asks for the manual validation round. Triggers on: "rodar QA", "QA da
  milestone", "validação manual", "handoff de QA", "rodar os casos de teste".
argument-hint: '[milestone-slug]'
effort: high
---

# QA run — nexu

You execute a script somebody else wrote. That is the whole job, and the discipline is the point.

A QA round is worth what its honesty is worth. A round that says "22 ✓" because the agent nudged
the seed, retried until it worked and called an ambiguous screen a pass is worse than no round at
all — the milestone ships believing it was validated.

## The rules that govern everything

**Run what is written.** You do not invent cases, and you do not skip one because a unit test seems
to cover it. If the script is wrong or incomplete, that goes in the report, at the end — you still
run what is there.

**Do not fix.** You are testing code you did not write and must not want to succeed. If you diagnose
the cause while investigating a failure, that diagnosis belongs in the bug you open, not in a
commit. A tester with a stake in the result stops being a tester.

**Three outcomes, never two.** `✓ passou`, `✗ falhou`, `⊘ bloqueado`. Blocked is for a case you
could not run through no fault of the code — a Meta test number not yet verified, a HubSpot
test-account token missing from `.env`, a sandbox that is down. **Blocked is never a pass and never a bug.** Collapsing
it into either is the most common way a QA round lies.

**One retry, then it failed.** Flakiness is a finding. If a case passes on the second attempt, it
failed — record both attempts in the report and say so.

## 1. Load the script

The argument is the milestone slug. One call brings the whole epic:

```
gh issue list --milestone "<slug>" --state all --limit 100 --json number,title,labels,body
```

The issue labelled `type: qa` is the script. Read it whole: environment setup, external
preconditions, the cases, and what is explicitly out of scope.

Read the `type: prd` issue too. You are not reviewing against it, but the cases will use domain
words — *leitura*, *raio X*, *temperatura*, *fase padronizada* — and the PRD is where they mean
something.

If there is no `type: qa` issue, stop and say so. Do not write a script yourself: a round against
cases you invented proves that you agree with yourself.

## 2. Bring the environment up

The script's "Preparo do ambiente" is authoritative. What follows is what it does not repeat,
because it is true of every round and has cost real hours.

**Check out the milestone branch — in a worktree, not by switching `main`.** Worktrees live at
`<repo>-wt/<nome-curto>`, and a copy carries no `node_modules` and no `.env`. Most epics span two
repos: bring both branches up (`nexu-api` and `nexu-fe`), and point the FE at the local
API.

**Change the port when you copy the `.env`.** Two apps on the same port fail in a way that looks
like a broken feature.

**Change `BULL_PREFIX` too — this one is silent.** Redis is a single local cluster shared by every
worktree. With the default prefix, an app from another session consumes the jobs your round
produces and yours logs `no handler`. Every queue-driven case then fails for a reason that has
nothing to do with the milestone. Set a prefix unique to this round before you start.

**Postgres is also shared.** A migration from another branch blocks `migrate:latest` and `codegen`
brings back tables that do not belong to this epic. If migrations refuse to apply, say so and stop
— do not delete anyone's migration to get moving.

**Confirm every external precondition before the first case**, using the check the script gives.
A precondition that is not met turns specific cases into `⊘ bloqueado` — decide that now, at the
start, not halfway through when it looks like a bug.

**Safety, non-negotiable.** Local only, provider sandboxes and test accounts only (HubSpot test
account, Meta test number), and the dev send-guard stays on. Never point a round at production, and
never touch a production connection. A QA round that messages a real person or writes into a real
CRM is an incident.

## 3. Walk the cases

In order, one at a time, from the state the setup left. Announce each case before running it and
report the outcome as you go — a round is long, and a silent agent that surfaces 22 results at the
end gives the person watching no chance to stop you.

**Screens: drive Chrome.** Load the `claude-in-chrome` skill first, open your own tab rather than
reusing the user's, and never click something that raises a browser dialog — it freezes the
extension and ends the round.

**Everything behind the screen: drive the CLI.** That is where most of this product lives.

| To check | Use |
| --- | --- |
| a scheduled step really fires | `npm run tick -- <name>` instead of waiting for the boundary |
| a provider webhook arrives | `npm run webhook:replay -- <fixture>` |
| an email went out, and what it says | Mailpit at `localhost:8025` (also has a REST API) |
| what the flow actually did | the structured log — `requestId` ties the whole run together |
| the state that resulted | the database, read-only |

**Evidence for every case, pass or fail.** A screenshot for a screen, the log line with its
`requestId`, the Mailpit message, the provider's response body. A pass with no evidence is an
opinion.

**Judge against what is written.** The expectation in the case is the bar — not your sense that the
screen looks reasonable. If the case says `R$ 1.240,00` and the screen says `R$ 1.240`, that is a
finding, and the report says what you saw.

## 4. Report

**A comment on the QA issue**, one per round, in pt-BR:

- A first line with the count: `Rodada 07/09 — 20 ✓ · 1 ✗ · 1 ⊘`, and the branches and commits you
  ran, so the round can be tied to a state of the code.
- A table: case, outcome, one line.
- Then a block per `✗` and per `⊘`: what you did, what you expected, what happened, the evidence,
  and — for a blocked one — the precondition that was missing.

**A `type: bug` issue per failure**, in the same milestone, filled as the bug template asks: what
happens, what should happen, how to reproduce (the case's own steps, they are already a repro),
`requestId`, environment `local`, severity, and impact. Link the QA issue and the card the
behaviour came from. **Never open a bug for a blocked case** — a missing precondition is not a
defect, and a board full of them teaches everyone to ignore the label.

**Close the report with what the script itself is missing.** Cases that were ambiguous, a step that
no longer matches the interface, behaviour you saw working that no case covers. That paragraph is
how the script gets better for the next epic — and it is the only place where you are allowed to
talk about cases nobody wrote.
