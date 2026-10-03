# nexo

Inteligência de vendas para o time comercial, da [Winning Sales](https://winningsales.com.br). O nexo lê o HubSpot, as reuniões
gravadas e as conversas de WhatsApp dos vendedores, mantém o CRM em dia com o que o cliente disse e mostra a cada vendedor o que
fazer hoje para bater a meta — com o trecho que sustenta cada leitura.

- Site: [nexo.winningsales.com.br](https://nexo.winningsales.com.br)
- App: [app.nexo.winningsales.com.br](https://app.nexo.winningsales.com.br)
- Integração com o HubSpot: [guia de configuração](https://nexo.winningsales.com.br/integracoes/hubspot)

O produto se chama **nexo**; os identificadores internos (`nexu-api`, `nexu-fe`, `@nexu/*`) mantêm o nome antigo.

## Produto

| Repositório | O que é |
| --- | --- |
| [nexu-api](https://github.com/winning-sales-nexus/nexu-api) 🔒 | API e workers: identidade multiempresa, integração com o HubSpot, reuniões, WhatsApp, IA e infraestrutura na AWS (NestJS + Kysely + CDK). O app do HubSpot vive em `hubspot-app/` |
| [nexu-fe](https://github.com/winning-sales-nexus/nexu-fe) 🔒 | Painel web e painel de admin (React + TS), publicados no Cloudflare Pages |
| [nexo-site](https://github.com/winning-sales-nexus/nexo-site) 🔒 | Site público: página inicial, guia da integração com o HubSpot, preços, suporte e textos legais (Astro + Tailwind, Cloudflare Pages) |

## Plataforma

| Repositório | O que é |
| --- | --- |
| [nexu-observability](https://github.com/winning-sales-nexus/nexu-observability) 🔒 | Grafana como código: dashboards, alertas e destinos de notificação, com pull, apply e drift por ambiente |
| [nexu-observability-infra](https://github.com/winning-sales-nexus/nexu-observability-infra) 🔒 | Stack LGTM self-hospedada — Grafana, Loki, Tempo e Prometheus numa EC2, com logs e traces no S3 |

## Padrões

| Repositório | O que é |
| --- | --- |
| [.github](https://github.com/winning-sales-nexus/.github) | Templates de issue e PR, padrões de gestão e as skills internas de engenharia |

🔒 = repositório privado.

Trabalho organizado no [project board da org](https://github.com/orgs/winning-sales-nexus/projects/1).
