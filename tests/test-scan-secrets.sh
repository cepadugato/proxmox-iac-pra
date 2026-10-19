#!/usr/bin/env bash
# Test de tests/scan-secrets.sh : un faux jeton doit le faire échouer, un fichier propre doit passer.
# Les faux secrets sont assemblés à l'exécution pour ne pas figurer en clair dans ce fichier.
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
fail=0
mot="pass""phrase"
printf 'Authorization: PVEAPIToken=%s\n' 'x@pve!y=00000000-0000-0000-0000-000000000000' > "$tmp/faux.txt"
printf 'variable "endpoint" {}\n# var.%s ok\n' "$mot" > "$tmp/propre.txt"
printf '%s = "valeur-longue-123"\n' "$mot" > "$tmp/pp.txt"
printf -- '-----BEGIN %s PRIVATE KEY-----\n' RSA > "$tmp/pem.txt"
# feuille 5.6a : sortie de `pveum user token add` (JSON et tableau), « value » + UUID ; valeurs fictives assemblées ici
u="00000000-1111-2222-3333-444444444444"
printf '{"full-tokenid" : "x@pve!y",\n "value" : "%s"}\n' "$u" > "$tmp/pveum-json.txt"
printf '\xe2\x94\x82 value        \xe2\x94\x82 %s \xe2\x94\x82\n' "$u" > "$tmp/pveum-tab.txt"
printf 'valeur du champ value: absente\nvalue = 12\n' > "$tmp/pveum-propre.txt"
bash "$d/tests/scan-secrets.sh" "$tmp/pveum-json.txt" >/dev/null 2>&1 && { echo "ROUGE: pveum JSON (value + UUID) non détecté"; fail=1; }
bash "$d/tests/scan-secrets.sh" "$tmp/pveum-tab.txt" >/dev/null 2>&1 && { echo "ROUGE: pveum tableau (value + UUID) non détecté"; fail=1; }
bash "$d/tests/scan-secrets.sh" "$tmp/pveum-propre.txt" >/dev/null 2>&1 || { echo "ROUGE: texte voisin sans UUID rejeté"; fail=1; }
bash "$d/tests/scan-secrets.sh" "$tmp/faux.txt" >/dev/null 2>&1 && { echo "ROUGE: faux jeton non détecté"; fail=1; }
bash "$d/tests/scan-secrets.sh" "$tmp/propre.txt" >/dev/null 2>&1 || { echo "ROUGE: fichier propre rejeté"; fail=1; }
bash "$d/tests/scan-secrets.sh" "$tmp/pp.txt" >/dev/null 2>&1 && { echo "ROUGE: valeur de phrase non détectée"; fail=1; }
bash "$d/tests/scan-secrets.sh" "$tmp/pem.txt" >/dev/null 2>&1 && { echo "ROUGE: PEM non détecté"; fail=1; }
find "$tmp" -type f -delete; rmdir "$tmp"
[ $fail -eq 0 ] && echo "OK test-scan-secrets"
exit $fail
