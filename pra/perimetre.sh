#!/usr/bin/env bash
# perimetre.sh : contrôle statique du périmètre PRA (pra/perimetre.yaml) contre pve, en lecture seule.
#   (1) chaque VMID des vagues est un CT de `pct list` (clé « vm » : une VM de `qm list`)
#   (2) chaque invité a une archive dans le MANIFESTE du passage nommé
#   (3a) archives du périmètre (taille du MANIFESTE) + template + marge ≤ root_labo_go
#   (3b) disque OCCUPÉ sur pve (zfs used) × 1,5 + marge ≤ data_labo_go (stockage du labo en allocation fine) ; total déclaré affiché
#   (4) RAM CONSOMMÉE sur pve (memory.current des CT + mémoire des VM) × 1,5 ≤ ram_labo_go − marge_ram_hote_go ; total déclaré affiché
# Exit 0 = tout vert ; exit 1 = au moins un contrôle rouge ; exit 2 = fichier ou accès illisible.
# Variable d'essai : PRA_PVE (défaut « ssh -o BatchMode=yes pve ») pour rejouer contre une sortie figée.
set -u
export LC_NUMERIC=C
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="${1:-$DIR/perimetre.yaml}"
PVE="${PRA_PVE:-ssh -o BatchMode=yes pve}"

lire() { local v; v="$(sed -n "s/^$1:[[:space:]]*//p" "$F" | head -1)"; [ -n "$v" ] || { echo "clé $1 absente de $F" >&2; exit 2; }; echo "$v"; }
[ -r "$F" ] || { echo "illisible : $F" >&2; exit 2; }
passage="$(lire passage)"; v1="$(lire vague1)"; v2="$(lire vague2)"; v3="$(sed -n "s/^vague3:[[:space:]]*//p" "$F" | head -1)"; vms="$(sed -n "s/^vm:[[:space:]]*//p" "$F" | head -1)"
ram="$(lire ram_labo_go)"; mram="$(lire marge_ram_hote_go)"
root="$(lire root_labo_go)"; data="$(lire data_labo_go)"; mdisque="$(lire marge_disque_go)"
TEMPLATE_GO="$(lire template_go)"; lire dechiffrement_dir >/dev/null
ids="$v1 $v2 $v3"

releve="$($PVE "pct list; echo ==MANIFESTE; cat /tank/sauvegardes/$passage/MANIFESTE-*.txt; qm list; for i in $ids; do echo ==CT \$i; pct config \$i | grep -E '^(memory|rootfs):'; echo \"memcur: \$(cat /sys/fs/cgroup/lxc/\$i/memory.current 2>/dev/null)\"; echo \"used: \$(zfs get -Hpo value used tank/subvol-\$i-disk-0 2>/dev/null)\"; done; for i in $vms; do echo ==VM \$i; qm config \$i | grep -E '^(memory|scsi0|virtio0|sata0):'; echo \"used: \$(zfs get -Hpo value used tank/vm-\$i-disk-0 2>/dev/null)\"; done")" ||
  { echo "relevé pve impossible" >&2; exit 2; }
liste="$(sed -n '1,/^==MANIFESTE$/p' <<<"$releve")"
manif="$(sed -n '/^==MANIFESTE$/,/^==CT /p' <<<"$releve")"
grep -q "^Passage   : $passage" <<<"$manif" || { echo "MANIFESTE du passage $passage introuvable" >&2; exit 2; }

rouge=0
ko() { echo "[KO] $*"; rouge=1; }
ok() { echo "[OK] $*"; }
go() { awk -v t="$1" 'BEGIN{n=t+0; u=t; sub(/^[0-9.]+/,"",u); if(u=="Go")print n; else if(u=="Mo")print n/1024; else if(u=="Ko")print n/1048576; else if(u=="To")print n*1024; else print -1}'; }

somme_arch=0; somme_rootfs=0; somme_ram=0; reel_ram=0; reel_disque=0
for i in $ids; do
  awk -v i="$i" '$1==i && $NF!=""{f=1} END{exit !f}' <<<"$liste" && ok "($i) CT présent dans pct list" || ko "($i) absent de pct list"
  a="$(grep -E "vzdump-lxc-${i}-[0-9_-]+\.tar\.zst\.gpg" <<<"$manif" | head -1)"
  if [ -n "$a" ]; then
    t="$(awk '{print $NF}' <<<"$a")"; g="$(go "$t")"
    [ "$g" = -1 ] && { ko "($i) taille d'archive illisible au MANIFESTE : $t"; continue; }
    ok "($i) archive au MANIFESTE $passage : $(awk '{print $1}' <<<"$a") ($t)"
    somme_arch="$(awk -v a="$somme_arch" -v b="$g" 'BEGIN{print a+b}')"
  else ko "($i) sans sauvegarde dans le MANIFESTE $passage"; fi
  cfg="$(sed -n "/^==CT $i\$/,/^==[CV]/p" <<<"$releve" | sed "1!{/^==/d}")"
  m="$(sed -n 's/^memory: //p' <<<"$cfg")"; r="$(sed -n 's/^rootfs: .*size=\([0-9]*\)G.*/\1/p' <<<"$cfg")"
  [ -n "$m" ] && [ -n "$r" ] || { ko "($i) memory ou rootfs illisible"; continue; }
  somme_ram=$((somme_ram + m)); somme_rootfs=$((somme_rootfs + r))
  mc="$(sed -n 's/^memcur: //p' <<<"$cfg")"; u="$(sed -n 's/^used: //p' <<<"$cfg")"
  [ -n "$mc" ] && [ -n "$u" ] || { ko "($i) consommation réelle illisible (memory.current ou zfs used)"; continue; }
  reel_ram=$((reel_ram + mc / 1048576)); reel_disque=$((reel_disque + u / 1048576))
done
for i in $vms; do
  grep -Eq "^[[:space:]]*$i[[:space:]]" <<<"$releve" && ok "($i) VM présente dans qm list" || ko "($i) VM absente de qm list"
  a="$(grep -E "vzdump-qemu-${i}-[0-9_-]+\.vma\.zst\.gpg" <<<"$manif" | head -1)"
  if [ -n "$a" ]; then
    t="$(awk '{print $NF}' <<<"$a")"; g="$(go "$t")"
    [ "$g" = -1 ] && { ko "($i) taille d'archive illisible au MANIFESTE : $t"; continue; }
    ok "($i) archive au MANIFESTE $passage : $(awk '{print $1}' <<<"$a") ($t)"
    somme_arch="$(awk -v a="$somme_arch" -v b="$g" 'BEGIN{print a+b}')"
  else ko "($i) VM sans sauvegarde dans le MANIFESTE $passage"; fi
  cfg="$(sed -n "/^==VM $i\$/,/^==[CV]/p" <<<"$releve" | sed "1!{/^==/d}")"
  m="$(sed -n 's/^memory: //p' <<<"$cfg")"; r="$(grep -E '^(scsi0|virtio0|sata0):' <<<"$cfg" | sed -n 's/.*size=\([0-9]*\)G.*/\1/p' | head -1)"; u="$(sed -n 's/^used: //p' <<<"$cfg")"
  [ -n "$m" ] && [ -n "$r" ] && [ -n "$u" ] || { ko "($i) mémoire, disque ou occupation de la VM illisible"; continue; }
  somme_ram=$((somme_ram + m)); somme_rootfs=$((somme_rootfs + r)); reel_ram=$((reel_ram + m)); reel_disque=$((reel_disque + u / 1048576))
done

besoin_root="$(awk -v a="$somme_arch" -v t="$TEMPLATE_GO" -v m="$mdisque" 'BEGIN{printf "%.1f", a+t+m}')"
awk -v b="$besoin_root" -v r="$root" 'BEGIN{exit !(b<=r)}' &&
  ok "(3a) root du labo : archives $(printf %.1f "$somme_arch") Go + template $TEMPLATE_GO + marge $mdisque = $besoin_root ≤ $root Go" ||
  ko "(3a) root du labo : $besoin_root Go > $root Go"
besoin_data=$(( reel_disque * 3 / 2 / 1024 + mdisque ))
[ "$besoin_data" -le "$data" ] && ok "(3b) données du labo : occupé sur pve $((reel_disque / 1024)) Go × 1,5 + marge $mdisque = $besoin_data ≤ $data Go (déclaré : $somme_rootfs Go, allocation fine)" ||
  ko "(3b) données du labo : $besoin_data Go > $data Go (déclaré : $somme_rootfs Go)"
dispo_ram=$(( (ram - mram) * 1024 ))
besoin_ram=$(( reel_ram * 3 / 2 ))
[ "$besoin_ram" -le "$dispo_ram" ] && ok "(4) RAM consommée sur pve $reel_ram Mo × 1,5 = $besoin_ram ≤ $ram − $mram Go = $dispo_ram Mo (limites déclarées : $somme_ram Mo)" ||
  ko "(4) RAM consommée $reel_ram Mo × 1,5 = $besoin_ram Mo > $dispo_ram Mo (limites déclarées : $somme_ram Mo)"

[ "$rouge" -eq 0 ] && echo "BILAN périmètre vert ($passage)" || echo "BILAN périmètre ROUGE ($passage)"
exit "$rouge"
