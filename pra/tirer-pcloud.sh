#!/usr/bin/env bash
# tirer-pcloud.sh : tire de pCloud, en LECTURE SEULE, les archives chiffrées du périmètre PRA (feuilles 5.13, 5.3).
#   tirer-pcloud.sh --version          version de rclone
#   tirer-pcloud.sh --lister           contenu du passage (pra/perimetre.yaml) sur pCloud
#   tirer-pcloud.sh --tirer            copie .gpg + .sha256 du périmètre et le MANIFESTE vers $PRA_TIRAGE/<passage>, puis sha256sum -c
#   tirer-pcloud.sh --controler        rclone check (empreintes) entre le dossier local et pCloud, sens unique
# Liste blanche (tests/test-tirer-pcloud.sh) : les seules sous-commandes rclone écrites ici sont lsf, copy, copyto,
# check et version ; pcloud-pra: n'est jamais une destination. Aucun déchiffrement ici (5.12b).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="$DIR/perimetre.yaml"
REMOTE="pcloud-pra:association/sauvegardes-vm-conteneurs"
lire() { sed -n "s/^$1:[[:space:]]*//p" "$F" | head -1; }
passage="$(lire passage)"; ids="$(lire vague1) $(lire vague2) $(lire vague3)"; vms="$(lire vm)"
[ -n "$passage" ] && [ -n "${ids// /}" ] || { echo "perimetre.yaml incomplet" >&2; exit 2; }
DEST="${PRA_TIRAGE:-$HOME/pra-tirage}/$passage"
filtres=(--include "MANIFESTE-*.txt")
for i in $ids; do filtres+=(--include "vzdump-lxc-$i-*.tar.zst.gpg" --include "vzdump-lxc-$i-*.tar.zst.gpg.sha256"); done
for i in $vms; do filtres+=(--include "vzdump-qemu-$i-*.vma.zst.gpg" --include "vzdump-qemu-$i-*.vma.zst.gpg.sha256"); done

case "${1:-}" in
  --version) rclone version ;;
  --lister) rclone lsf "$REMOTE/$passage/" ;;
  --tirer)
    mkdir -p "$DEST"
    rclone copy "$REMOTE/$passage/" "$DEST/" "${filtres[@]}" --stats-one-line --stats 30s || exit 1
    cd "$DEST" && sha256sum -c ./*.sha256 ;;
  --controler) rclone check "$REMOTE/$passage/" "$DEST/" "${filtres[@]}" --one-way ;;
  *) echo "usage : $0 --version|--lister|--tirer|--controler" >&2; exit 2 ;;
esac
