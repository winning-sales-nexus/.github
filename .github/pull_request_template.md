## O que muda

<!-- Uma frase: o efeito prático desta PR. -->

Fecha #

<!--
`Fecha` não fecha nada sozinho (o GitHub só entende `closes` em inglês, e só em merge na branch
default). É para quem lê. Quem fecha card é a milestone, encerrada quando o épico chega na main.

PR de milestone (`milestone/<slug>` → main): troque a linha acima por `Milestone: <slug>`.
É por ela que o reviewer carrega o PRD e todos os cards — sem ela, ele revisa só o diff.
-->

## Por quê

<!-- O motivo, não a descrição do diff. -->

## Como validar

<!-- Passos concretos: comando, endpoint, o que observar. -->

## Checklist

- [ ] Lint, typecheck e testes passando localmente
- [ ] Endpoints novos/alterados documentados no Swagger (request, response e erros)
- [ ] Migration é aditiva e compatível com a versão anterior em execução
- [ ] Nenhum PII em log; `requestId` e `companyId` presentes nos fluxos novos
- [ ] Skills/docs atualizadas se alguma regra mudou
- [ ] Novo recurso always-on na AWS? Custo mensal informado abaixo
- [ ] PR de milestone: PRD e todos os cards com a milestone `<slug>`, e o corpo acima preenchido
