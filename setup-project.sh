#!/usr/bin/env bash
# Prepara o project board da org winning-sales-nexus com os campos de gestão.
# Uso: ./setup-project.sh [número-do-project]
#   com número: adiciona os campos e vincula os repositórios num project existente (o da org é o 1)
#   sem número: cria um project novo antes
# Requer escopo project no gh:  gh auth refresh -h github.com -s project
set -euo pipefail

OWNER="winning-sales-nexus"
TITLE="nexu Roadmap"
NUMBER="${1:-}"

if [ -z "$NUMBER" ]; then
  echo "== criando project"
  NUMBER=$(gh project create --owner "$OWNER" --title "$TITLE" --format json | python3 -c "import json,sys; print(json.load(sys.stdin)['number'])")
fi
echo "   project #$NUMBER"

EXISTING=$(gh project field-list "$NUMBER" --owner "$OWNER" --format json | python3 -c "import json,sys; print('\n'.join(f['name'] for f in json.load(sys.stdin)['fields']))")

field() {
  if grep -qxF "$1" <<< "$EXISTING"; then
    echo "   campo já existe: $1"
    return
  fi
  gh project field-create "$NUMBER" --owner "$OWNER" --name "$1" --data-type "$2" ${3:+--single-select-options "$3"} > /dev/null
  echo "   campo: $1"
}

echo "== campos"
field "Priority"  SINGLE_SELECT "P0 — agora,P1 — próxima,P2 — planejado,P3 — algum dia"
field "Size"      SINGLE_SELECT "XS — até 2h,S — meio dia,M — 1-2 dias,L — 3-5 dias,XL — quebrar em partes"
field "Work"      SINGLE_SELECT "PRD,Feature,Bug,Tech debt,Chore,Spike"
field "Area"      SINGLE_SELECT "Identity,CRM,Reuniões,WhatsApp,E-mail,IA,Infra,Frontend,DX"
field "Epic"      TEXT
field "Target"    DATE
field "Spent (h)" NUMBER

echo "== vinculando repositórios"
for repo in nexu-api nexu-fe nexu-observability nexu-observability-infra; do
  gh project link "$NUMBER" --owner "$OWNER" --repo "$repo" > /dev/null && echo "   $repo"
done

echo
echo "Pronto: https://github.com/orgs/$OWNER/projects/$NUMBER"
echo "Ajuste as colunas de Status na UI (sugestão: Backlog · Refinement · Ready · In progress · In review · Done)."
