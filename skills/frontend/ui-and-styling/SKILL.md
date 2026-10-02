---
name: ui-and-styling
description: >
  Design system rules for nexu-fe: Tailwind v4 semantic tokens in src/index.css, fonts, dark mode,
  shared/ui primitives (cva, Radix), pt-BR money/date formatting, loading/empty/error states and
  feedback. Use whenever building UI, styling, adding a component to shared/ui, picking a colour or
  formatting a value, or when eslint says "Cor literal fora dos tokens do design system". Triggers
  on: "componente", "component", "estilo", "style", "tailwind", "cor", "color", "token", "tema",
  "dark mode", "tabela", "table", "moeda", "formatar", "skeleton", "empty state", "toast", "modal",
  "catalog", "design system".
---

# UI & Styling — nexu-fe

Tailwind CSS **v4** (CSS-first: no `tailwind.config`, loaded by `@tailwindcss/vite`), primitives from
**Radix** (checkbox, dropdown-menu, popover, radio-group, select, switch, tabs, toggle-group, tooltip)
wrapped in `src/shared/ui`, `lucide-react` icons, `class-variance-authority` for variants.
There is no shadcn/ui; the primitives are ours.

## Tokens live in `src/index.css`

Everything is declared in the `@theme { ... }` block as CSS variables Tailwind turns into utilities.
**Never write a raw colour in a component.** ESLint rejects `bg-[#DA2640]`, `[rgb(`, `[rgba(`,
`[hsl(`, `[oklch(` in strings/templates and a literal `#`/`rgb(`/`hsl(`/`oklch(` as the value of
`color`, `backgroundColor`, `borderColor`, `fill`, `stroke`, `outlineColor` in a style object.
SVG charts therefore use classes (`fill-brand`, `stroke-rule`) or `currentColor`.

| Group            | Tokens (utility = `bg-`/`text-`/`border-` + name)                                              |
| ---------------- | ----------------------------------------------------------------------------------------------- |
| Surfaces         | `bg`, `surface`, `surface-2`, `sidebar`, `rule` (border), `rule-soft`                           |
| Text             | `ink`, `ink-2`, `ink-3` (also `content`, `content-muted`, `content-subtle`)                     |
| Brand            | `brand` (`#da2640`), `brand-2`, `brand-soft`, `brand-ink`, `on-brand`                            |
| Status           | `good`/`good-soft`, `warn`/`warn-soft`, `crit`/`crit-soft` (aliases `positive`, `caution`, `critical`, `*-50`) |
| Data-viz         | `s1`, `s2`, `fc1..4`, `fn1..4`, `ic1..3`, `wine`, `team`                                          |
| Dark/hero blocks | `dark-1..3`, `hero-*`, `on-dark` (used by the `dark-block`, `hero-panel`, `glass-card` utilities)  |

Also tokenised: fonts, a custom type scale (`text-2xs`, `text-xs`, `text-sm`=13px, `text-md`, `text-base`=15px...
`text-5xl`), radii (`rounded-control`, `rounded-card`), shadows (`shadow-card`, `shadow-menu`),
spacing (`p-page-x`, `w-sidebar`), containers (`max-w-content`) and animations.
Custom utilities: `numeric` (mono, tabular figures), `label-caps`, `focus-ring`, `surface-card`,
`card-refined`, `dark-block`, `hero-panel`.

A new colour enters `index.css` as a token with a stated purpose **in both** the `@theme` block and the
`.dark` block; only then is it used. Prefer the existing semantic tokens (`crit` for failure,
`good` for success, `warn` for attention, `brand` for primary actions).

### Fonts

Self-hosted via `@fontsource` imports at the top of `index.css`: **Karla** (`font-sans`, body),
**Josefin Sans** (`font-display`), **JetBrains Mono** (`font-mono`, figures through `numeric`).
`font-wordmark` (Arial) is only for the logo. Do not add a Google Fonts link.

### Dark mode

A token flip, not a second set of components. `ThemeProvider` (`app/providers`) puts the `.dark` class
on `<html>` (`light` | `dark` | `system`, remembered in `localStorage` key `nexu.theme`, synced to the
account), `@custom-variant dark` maps `dark:` to it, and `.dark { --color-... }` redefines the tokens.
Because tokens flip, most components never write `dark:`; reach for it only for opacity tweaks
(`dark:bg-critical/10`) that a token cannot express. Verify any new screen in both themes.

## Composition rules

1. `shared/ui` holds **generic** primitives: `Button`, `Field`/`TextField`, `Modal`, `ConfirmDialog`,
   `Table`, `Card`, `Tag`/`Chip`, `Alert`, `EmptyState`, `Skeleton*`, `Toast`, `Tabs`, `Menu`,
   `SelectMenu`, `Pagination`, `KpiTile`/`BigKpi`, `Gauge`... Domain components live in the feature
   (`features/deals/components/`) or, if two features render them, in `shared/<domain>/`
   (frontend-architecture skill). Lint does not check domain-freeness of `shared/ui`; review does.
2. **Variants come from `cva`**, with the variant props type written by hand and the constant annotated
   (see `shared/ui/button.tsx`): `const buttonVariants: (props?: ButtonVariantProps) => string = cva(...)`.
   Merge call-site classes with `cn()` (`shared/lib/cn`: `clsx` + `tailwind-merge`). Tone lookups are
   `Record<Tone, string>` tables (`Alert`), not conditional class soup.
3. One component per file, named export, kebab-case file name, props as an exported `interface XProps`
   with `readonly` members, explicit `ReactElement` return type.
4. Every list/table/section that loads data implements **four states**: loading (a `Skeleton*` shaped
   like the real layout inside `<Loading label="...">`, which sets `role="status"`), empty
   (`<EmptyState title description action />`, with the action that fills it), error
   (`<FailureAlert />` or `<Alert />`, with a retry when it makes sense) and content.
5. Accessibility is part of the component: icon-only controls use `IconButton` with a label,
   focus uses `focus-ring`/`:focus-visible`, motion respects `prefers-reduced-motion` (see how
   `Skeleton` uses `motion-reduce:animate-none`), and the `--spacing-touch` token (44px) is the minimum for tappable targets.
6. Keep every function component under **40 lines** (`max-lines-per-function`, JSX included; the repo
   lint is being lowered from 80 to 40, so write to 40 now). Split JSX into subcomponents, one per
   visual block, and push class/branch logic into lookup tables or pure helpers.
7. Everything that fits in a screen has a responsive story: shell collapses to a menu on mobile;
   use `useMediaQuery` (`shared/lib`) only for behaviour, Tailwind breakpoints for layout.

## Money, numbers and dates (`src/shared/format`, pt-BR)

- Money is **integer cents + currency** in the data; format only at the edge:
  `formatMoney(cents, currency)`, `formatMoneyCompact`, `formatCents` (BRL), `formatCentsCompact`.
  Never `toFixed`, never a float amount. Formatters replace non-breaking spaces with plain spaces.
- `formatPercent(ratio)`, `formatInteger`, `formatDays`, `formatMinutes`, `formatMultiplier`.
- Form inputs for amounts use `parseAmount(text)` → `{ ok, cents }` and `amountText(cents)`.
- Dates come from the API as UTC ISO strings and are shown **in the company's time zone**, never the
  browser's: `formatDate`, `formatShortDate`, `formatTime`, `formatDateTime`, `formatLongDate`,
  `formatRelative` ("há 3 horas", "ontem"), `formatUpcoming`, all taking a `timezone` argument that
  defaults to `DEFAULT_TIMEZONE` (`America/Sao_Paulo`). Pass the company's zone
  (`shared/config/timezones.ts` lists the options).
- Figures in tables and KPIs use the `numeric` utility so columns align.

## Copy

Screen text is pt-BR and lives in pure `*-copy.ts` functions beside the feature (`deal-copy.ts`,
`kpi-copy.ts`, `shared/call-points/call-point-copy.ts`) so it is unit-tested and out of the JSX.
Code identifiers stay English (conventions skill).

## Feedback

- Destructive actions use `ConfirmDialog` (`destructive`) with a description naming the consequence,
  never "Tem certeza?".
- Toasts: `const { show } = useToast()` and a `ToastRequest` built by a `*-toasts.ts` function using
  `TOAST_TONES` (`positive`, `neutral`, `caution`, `critical`). Success toasts are past tense and say
  what happened; critical toasts do not auto-dismiss (`durationMs: 0`); the stack shows at most 3.
  Errors: `failureToast(title, error)` (keeps the API `detail`).
- Anything above ~400 ms shows progress (`Button loading`, skeletons).

## Seeing it

`/catalog` (and `/catalogo`) renders the component catalog (`features/catalog`) and exists only in
`vite dev` (`import.meta.env.DEV`, otherwise `notFound()`). Add a new `shared/ui` primitive to a
section there.
