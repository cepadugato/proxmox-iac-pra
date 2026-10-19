#!/usr/bin/env bash
# controle-pcloud.sh : contrôle en LECTURE SEULE de l'intégrité des archives chiffrées déjà présentes chez pCloud.
# Pour chaque passage (ou ceux donnés), compare le sha256 calculé par pCloud de chaque .gpg à celui de son .gpg.sha256
# (écrit par la sauvegarde au moment du chiffrement). Rien n'est téléchargé hormis les petits .sha256.
#   pra/controle-pcloud.sh [passage…]     ex. 2026-S41 2026-S42 ; sans argument : tous les passages
# Sous-commandes rclone employées : lsf, hashsum, cat (lecture seule). Exit 0 = tout conforme, 1 = au moins un écart.
set -u
export PATH="$HOME/.local/bin:$PATH"
R="pcloud-pra:association/sauvegardes-vm-conteneurs"
passages=("$@")
[ "${#passages[@]}" -gt 0 ] || mapfile -t passages < <(rclone lsf --dirs-only "$R/" | tr -d /)
ecarts=0; n=0
for p in "${passages[@]}"; do
  declare -A dist=()
  while read -r h f; do dist[$f]="$h"; done < <(rclone hashsum sha256 "$R/$p/" --include "*.gpg")
  while read -r h f; do
    n=$((n + 1))
    if [ -z "${dist[$f]:-}" ]; then echo "[KO] $p/$f : absent chez pCloud"; ecarts=$((ecarts + 1))
    elif [ "${dist[$f]}" != "$h" ]; then echo "[KO] $p/$f : sha256 pCloud ${dist[$f]:0:12}… ≠ attendu ${h:0:12}… ($(rclone lsf --format s "$R/$p/$f") octets)"; ecarts=$((ecarts + 1))
    fi
  done < <(rclone cat "$R/$p/" --include "*.gpg.sha256" 2>/dev/null)
  unset dist
done
echo "BILAN : $n archive(s) contrôlée(s) dans ${#passages[@]} passage(s), $ecarts écart(s)"
[ "$ecarts" -eq 0 ]
