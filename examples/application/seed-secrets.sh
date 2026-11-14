#!/usr/bin/env bash
# Crée (UNE fois) le secret d'une application dans OpenBao : secret/<app>.
# Les clés sont générées au hasard, sauf celles que tu fournis. Relancer ne modifie JAMAIS un secret déjà créé.
#
# Usage :   ./seed-secrets.sh <app> CLE1 CLE2 ... [CLE3=valeur ...]
# Exemple : KEYCLOAK_CLIENT_SECRET=... ./seed-secrets.sh monapp DB_PASSWORD API_KEY KEYCLOAK_CLIENT_SECRET
#           (une clé listée SANS valeur est générée ; si une variable d'environnement du même nom existe, elle est utilisée)
#
# Prérequis : être dans le dépôt homelab (lit .secrets/openbao_init.json), OpenBao descellé (make unseal), SSH vers « tour ».
# SAUVEGARDER OpenBao : si le secret contient des clés de chiffrement, les perdre rend les données illisibles.
set -euo pipefail
APP="${1:?usage: $0 <app> CLE [CLE=valeur ...]}"; shift
[ "$#" -ge 1 ] || { echo "indique au moins une clé"; exit 1; }
SSH_HOST="${SSH_HOST:-tour}"
INIT="${OPENBAO_INIT_FILE:-.secrets/openbao_init.json}"
TOKEN="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['root_token'])" "$INIT")"

# Construit la liste CLE=valeur (valeur : fournie, sinon variable d'environnement du même nom, sinon générée côté OpenBao)
ARGS=""
for item in "$@"; do
  key="${item%%=*}"
  if [[ "$item" == *=* ]]; then val="${item#*=}"
  elif [[ -n "${!key:-}" ]]; then val="${!key}"
  else val="@RANDOM"; fi
  ARGS+="$key=$val"$'\n'
done

printf '%s\n%s' "$TOKEN" "$ARGS" | ssh "$SSH_HOST" "sudo k3s kubectl -n openbao exec -i openbao-0 -- sh -c '
set -eu
read -r BAO_TOKEN; export BAO_TOKEN BAO_ADDR=http://127.0.0.1:8200
if bao kv get secret/$APP >/dev/null 2>&1; then echo \"secret/$APP existe déjà : rien modifié\"; exit 0; fi
set --
while IFS== read -r k v; do
  [ -n \"\$k\" ] || continue
  [ \"\$v\" = \"@RANDOM\" ] && v=\"\$(head -c 24 /dev/urandom | od -An -tx1 | tr -d \" \\n\")\"
  set -- \"\$@\" \"\$k=\$v\"
done
bao kv put secret/$APP \"\$@\" >/dev/null && echo \"secret/$APP créé (\$# clés)\"
'"
