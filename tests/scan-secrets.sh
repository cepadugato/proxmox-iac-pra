#!/usr/bin/env bash
# scan-secrets.sh — feuille 1.3. Cherche des secrets en clair dans des fichiers ou répertoires.
# Usage : scan-secrets.sh [chemin...]   (défaut : tofu/ et recettes/ du projet)
# Sortie : 0 = rien trouvé ; 2 = au moins une correspondance (code attendu par garde-sources
# pour une « vérification métier »). Les valeurs trouvées ne sont JAMAIS imprimées (fichier:ligne:motif seulement).
set -u
d="$(cd "$(dirname "$0")/.." && pwd)"
cd "$d" || exit 1
[ $# -eq 0 ] && set -- tofu recettes

# Motifs alignés sur .claude/garde.yml (secrets_extra). grep -E, sensible à la casse.
motifs=(
  'PVEAPIToken=[^[:space:]]+![^[:space:]]+=[0-9a-f-]{36}|jeton-pve'
  '(token_secret|secret)[[:space:]]*[:=][[:space:]]*["'\'']?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|secret-uuid'
  '(TOFU_ENC_PASSPHRASE|passphrase)[[:space:]]*[:=][[:space:]]*["'\'']?([^v[:space:]"'\''$]|v[^a[:space:]"'\''$]|va[^r[:space:]"'\''$]|var[^.[:space:]"'\''$])[^[:space:]"'\''$]{5,}|phrase-en-clair'
  '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|cle-privee-pem'
  '(^|[^[:alnum:]_])value("|'\''|[[:space:]]|:|=|\||│)+[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|valeur-jeton-pveum'
)

trouve=0
for cible in "$@"; do
  [ -e "$cible" ] || continue
  for m in "${motifs[@]}"; do
    re="${m%|*}"; nom="${m##*|}"
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      echo "SECRET[$nom] ${hit%%:*}:$(echo "$hit" | cut -d: -f2)"
      trouve=1
    done < <(grep -rEIn --exclude-dir=.terraform --exclude-dir=.git --exclude='*.tfstate*' -e "$re" "$cible" 2>/dev/null)
  done
done
[ $trouve -eq 0 ] && { echo "scan-secrets: rien trouvé dans: $*"; exit 0; }
echo "scan-secrets: ÉCHEC (valeurs masquées)" >&2
exit 2
