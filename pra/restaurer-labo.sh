#!/usr/bin/env bash
# restaurer-labo.sh : restaure les archives claires (5.12b) par-dessus la coquille OpenTofu (5.7), dans le labo seulement.
#   pra/restaurer-labo.sh                  simulation : commandes prévues, rien n'est lancé
#   pra/restaurer-labo.sh --oui [vmid…]    restauration des invités du périmètre (ou de ceux donnés), un par un
#   pra/restaurer-labo.sh --demarrer --oui démarrage dans l'ordre de pra/perimetre.yaml (vague1, vague2, vague3, puis vm)
# CT avec coquille : restauration forcée, net0 repris de la coquille (ip, gw, hwaddr de l'état tofu) ;
# CT sans coquille (privilégié, le jeton ne sait pas le créer) : restauration simple, net0 de l'archive, puis import tofu ;
# VM (clé « vm ») : qmrestore, configuration de l'archive. Stockage de labo.tfvars ; unprivileged lu dans l'archive ;
# contrôles : rootfs non vide, features de l'archive reprises (pvesm extractconfig), net0 inchangé. N = 2 essais par CT.
# Seule voie : pra/lib-ssh-labo.sh après pra/poste-labo.sh --verifier. Retour arrière : instantané libvirt avant-5-8-*.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib-ssh-labo.sh"
lire() { sed -n "s/^$1:[[:space:]]*//p" "$DIR/perimetre.yaml" | head -1; }
CLAIR="$(lire dechiffrement_dir)"; CLAIR="${CLAIR%/}"
DS="$(sed -n 's/^datastore[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS_CIBLE")"
ORDRE="$(lire vague1) $(lire vague2) $(lire vague3)"; VMS="$(lire vm)"
oui=0; demarrer=0; ids=()
for a in "$@"; do
  case "$a" in --oui) oui=1 ;; --demarrer) demarrer=1 ;; [0-9]*) ids+=("$a") ;; *) echo "option inconnue : $a" >&2; exit 2 ;; esac
done
[ "${#ids[@]}" -gt 0 ] || read -r -a ids <<<"$ORDRE $VMS"
for i in "${ids[@]}"; do case " $ORDRE $VMS " in *" $i "*) ;; *) echo "REFUS : $i hors du périmètre" >&2; exit 2 ;; esac; done
est_vm() { case " $VMS " in *" $1 "*) return 0 ;; esac; return 1; }
[ -n "$DS" ] && [ -n "$CLAIR" ] || { echo "stockage ou dossier clair illisible" >&2; exit 2; }

if [ "$oui" -ne 1 ]; then
  for i in "${ids[@]}"; do
    if est_vm "$i"; then echo "[SIMUL] VM $i : qmrestore de $CLAIR/vzdump-qemu-$i-*.vma.zst sur $DS"
    else echo "[SIMUL] CT $i : restauration de $CLAIR/vzdump-lxc-$i-*.tar.zst sur $DS (forcée si coquille, net0 de la coquille ; sinon simple)"; fi
  done
  [ "$demarrer" -eq 1 ] && echo "[SIMUL] démarrage dans l'ordre : $ORDRE $VMS"
  echo "à sec : relancer avec --oui"; exit 0
fi
verifier_cible || { echo "REFUS : cible $PRA_CIBLE non vérifiée" >&2; exit 4; }

if [ "$demarrer" -eq 1 ]; then
  for i in $ORDRE; do
    t0=$(date +%s)
    ssh_labo "pct status $i | grep -q running || pct start $i; sleep 3; pct status $i"
    echo "CT $i : démarré en $(( $(date +%s) - t0 )) s"
  done
  for i in $VMS; do
    t0=$(date +%s)
    ssh_labo "qm status $i | grep -q running || qm start $i; sleep 3; qm status $i"
    echo "VM $i : démarrée en $(( $(date +%s) - t0 )) s"
  done
  exit 0
fi

ko=0
for i in "${ids[@]}"; do
  t0=$(date +%s)
  if est_vm "$i"; then
  ssh_labo bash -s -- "$i" "$CLAIR" "$DS" <<'LABO' || { echo "VM $i : ÉCHEC" >&2; ko=1; }
set -euo pipefail
i="$1"; clair="$2"; ds="$3"
a="$(ls "$clair"/vzdump-qemu-"$i"-*.vma.zst 2>/dev/null | head -1)"
[ -s "$a" ] || { echo "VM $i : archive claire absente"; exit 1; }
( cd "$clair" && sha256sum -c --quiet "$(basename "$a").sha256" ) || { echo "VM $i : empreinte de l'archive absente ou fausse"; exit 1; }
qm status "$i" >/dev/null 2>&1 && { echo "VM $i : existe déjà dans le labo, refus (aucune VM écrasée)"; exit 1; }
for essai in 1 2; do
  if qmrestore "$a" "$i" --storage "$ds" >/tmp/restore-$i.log 2>&1; then break; fi
  echo "VM $i : essai $essai en échec : $(tail -2 /tmp/restore-$i.log | tr '\n' ' ')"
  [ "$essai" = 2 ] && exit 1
done
echo "VM $i : restaurée ; $(qm config "$i" | grep -E '^(name|net0|scsi0|memory):' | tr '\n' ' ')"
LABO
  else
  ssh_labo bash -s -- "$i" "$CLAIR" "$DS" <<'LABO' || { echo "CT $i : ÉCHEC après 2 essais" >&2; ko=1; }
set -euo pipefail
i="$1"; clair="$2"; ds="$3"
a="$(ls "$clair"/vzdump-lxc-"$i"-*.tar.zst 2>/dev/null | head -1)"
[ -s "$a" ] || { echo "CT $i : archive claire absente"; exit 1; }
# seule une archive arrivée entière porte son .sha256 (écrit en dernier par archives-vers-labo.sh)
( cd "$clair" && sha256sum -c --quiet "$(basename "$a").sha256" ) || { echo "CT $i : empreinte de l'archive absente ou fausse"; exit 1; }
# configuration sauvegardée, lue dans l'archive (pvesm extractconfig attend un volume de stockage, pas un chemin)
conf="$(tar -I zstd -xOf "$a" ./etc/vzdump/pct.conf)" || { echo "CT $i : pct.conf illisible dans l'archive"; exit 1; }
attendu="$(sed -n '/^\[/q; s/^features: //p' <<<"$conf")"
unpriv="$(sed -n '/^\[/q; s/^unprivileged: //p' <<<"$conf")"; unpriv="${unpriv:-0}"
if pct status "$i" >/dev/null 2>&1; then
  net0="$(pct config "$i" | sed -n 's/^net0: //p')"
  [ -n "$net0" ] || { echo "CT $i : coquille sans net0"; exit 1; }
  case "$(pct status "$i")" in *stopped*) ;; *) echo "CT $i : pas arrêté, refus"; exit 1 ;; esac
  opts=(--force 1 --net0 "$net0"); mode="forcée sur la coquille"
else
  net0="$(sed -n '/^\[/q; s/^net0: //p' <<<"$conf")"; opts=(); mode="simple (sans coquille), net0 de l'archive"
fi
for essai in 1 2; do
  if pct restore "$i" "$a" "${opts[@]}" --storage "$ds" --unprivileged "$unpriv" >/tmp/restore-$i.log 2>&1; then break; fi
  echo "CT $i : essai $essai en échec : $(tail -2 /tmp/restore-$i.log | tr '\n' ' ')"
  [ "$essai" = 2 ] && exit 1
done
apres="$(pct config "$i")"
[ "$(sed -n 's/^net0: //p' <<<"$apres")" = "$net0" ] || { echo "CT $i : net0 changé"; exit 1; }
[ "$(sed -n 's/^features: //p' <<<"$apres")" = "$attendu" ] || { echo "CT $i : features ≠ archive ($attendu)"; exit 1; }
[ "$(sed -n 's/^unprivileged: //p' <<<"$apres")" = "$( [ "$unpriv" = 1 ] && echo 1 )" ] || { echo "CT $i : unprivileged ≠ archive ($unpriv)"; exit 1; }
pct mount "$i" >/dev/null
taille="$(du -sh /var/lib/lxc/"$i"/rootfs 2>/dev/null | cut -f1)"; n="$(ls /var/lib/lxc/"$i"/rootfs | wc -l)"
pct unmount "$i"
[ "$n" -gt 5 ] || { echo "CT $i : rootfs vide"; exit 1; }
echo "CT $i : restauré ($mode, unprivileged $unpriv) ; rootfs $taille ($n entrées) ; features [$attendu] ; net0 [$net0]"
LABO
  fi
  echo "$i : durée $(( $(date +%s) - t0 )) s"
done
[ "$ko" -eq 0 ] && echo "bilan : ${#ids[@]} CT restauré(s)" || { echo "bilan : au moins un CT en échec" >&2; exit 1; }
