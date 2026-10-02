---
name: forms
description: >
  Form patterns for nexu-fe: react-hook-form + zod, submit states, API error display and
  accessibility with the shared Field component. Use whenever building or changing a form,
  validation, a modal with inputs, or handling submit errors. Triggers on: "form", "formulário",
  "input", "validação", "validation", "zod", "react-hook-form", "submit", "erro de campo",
  "field error", "modal de cadastro", "Field", "TextField".
---

# Forms — nexu-fe

**react-hook-form + `@hookform/resolvers/zod` (zod 3).** The schema lives in
`features/<feature>/schemas/<name>.schema.ts` (exempt from `typedef` so `z.infer` works) and is the
single source of truth for shape and messages. The input type is derived, never hand-written:

```typescript
export const emailSchema = z.object({
    email: z.string().trim().min(1, 'Informe seu e-mail').email('E-mail inválido')
});
export type EmailInput = z.infer<typeof emailSchema>;
```

```typescript
const form: UseFormReturn<EmailInput> = useForm<EmailInput>({
    resolver: zodResolver(emailSchema),
    mode: 'onTouched',
    defaultValues: { email: '' }
});
```

## Rules

1. **Mirror the API rules, do not invent new ones.** Messages are pt-BR and say what to do ("Informe
   o nome da empresa"). The API stays the authority; its `detail` is shown when it refuses.
2. **`mode: 'onTouched'`** — validate on blur, revalidate on change; never scream at an untouched field.
3. **Render fields with `Field`** (`shared/ui/field`, an alias of `TextField`): it binds `<label htmlFor>`,
   sets `aria-invalid` and `aria-describedby`, and renders the error with `role="alert"`. Spread
   `{...form.register('name')}` and pass `error={form.formState.errors.name?.message}`. The
   `<form>` gets `noValidate` and `onSubmit={(event): undefined => void submit(event)}`.
4. **Submit with `form.handleSubmit` + `mutateAsync` in a try/catch** (`void submit(...)` keeps
   `no-floating-promises` happy). On failure, `form.setFocus(firstField)` so focus returns to the form.
5. **Show the outcome**: a form inside a modal uses `<FailureAlert error={mutation.error} title="..." />`
   at the top of the form; a form that stays on the page uses `show(failureToast('...', error))` from
   `useToast()`. `FailureAlert` handles `ApiError` vs generic `Error` and the `requestId` rule
   (data-fetching skill).
6. **Disable submit while pending and say what is happening**: `<Button type="submit" loading={pending}>`
   with a label change ("Enviando…", "Criando…"). `Button` sets `aria-busy` and disables itself.
7. **A form component never navigates by itself**; it takes callbacks (`onCodeSent`, `onAuthenticated`,
   `onClose`) and the page decides what comes next.
8. A submit button outside the `<form>` (modal footer) uses `form={FORM_ID}` with the same id on `<form id>`.
9. Server-side field errors: `ApiError.fieldIssues()` returns `{ path, message }[]`; map each with
   `form.setError(path as keyof Input, { message })` and send path-less errors to `FailureAlert`.
   No form does this today; if you add it, put the mapping in one shared helper, not per form.
10. Keep each component under the 40-line function limit: split a long form into a `<XFields />`
    component receiving `form`, and move the submit handler into a `useXForm` hook.

## Sensitive fields

- E-mail code: 6 digits, `codeSchema` is `/^\d{6}$/`; the input is `shared/ui/code-input`. Login is
  by e-mail code or Google, so there are no password fields.
- Phones and money: parse with the shared helpers (`shared/format/amount.ts` `parseAmount` returns
  cents) and send integer cents to the API, never a float.
- Never log form values, never put them in query params, never persist drafts of anything touching
  credentials in `localStorage`.
