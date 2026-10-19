#!/usr/bin/env bash
# fog-partage.sh : remet FOG (VM 110) et le partage de l'hôte (/tank/partage en SMB et NFS) sur la cible PRA_CIBLE
# (labo par défaut, ou secours), depuis le passage hors chaîne produit par recettes/sauver-fog-partage.sh.
#   pra/fog-partage.sh              à sec : contrôles locaux et plan
#   pra/fog-partage.sh --oui        déchiffrement en flux, FOG restauré ARRÊTÉ, disque d'images recréé, partage installé
#   pra/fog-partage.sh --demarrer   APRÈS la bascule : démarre FOG, publie pve.local (le nom du partage pour les postes)
# Idempotent : chaque étape faite est reconnue et sautée.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; PROJ="$(cd "$DIR/.." && pwd)"
PASSAGE=2026-S42-fog
TIRAGE="$HOME/pra-tirage/$PASSAGE"
CLE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/infra-as-code/cle-gpg"
VMID=110; TAILLE_IMAGES_GO=100
mode=sec
for a in "$@"; do case "$a" in --oui) mode=oui ;; --demarrer) mode=demarrer ;; *) echo "usage : $0 [--oui|--demarrer]" >&2; exit 64 ;; esac; done
. "$DIR/lib-ssh-labo.sh"
CLAIR="$(sed -n 's/^dechiffrement_dir:[[:space:]]*//p' "$DIR/perimetre.yaml")"; CLAIR="${CLAIR%/}"
DS="$(sed -n 's/^datastore[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TFVARS_CIBLE")"
[ -n "$CLAIR" ] && [ -n "$DS" ] || { echo "dossier clair ou stockage illisible" >&2; exit 2; }

if [ "$mode" = demarrer ]; then
  ssh_labo bash -s -- "$VMID" <<'CIBLE'
set -e
i="$1"
qm set "$i" --onboot 1 >/dev/null
qm status "$i" | grep -q running || qm start "$i"
# le nom mDNS que les postes utilisent pour le partage est celui de pve : publié pour la seule adresse de pve,
# pas en nom d'hôte (sinon toutes les adresses du serveur seraient annoncées, dont celles injoignables des postes)
# (un nom statique d'/etc/avahi/hosts entre en collision avec la fiche inverse de l'hôte : publication sans inverse, -R)
sed -i 's/^host-name=pve$/#host-name=/; /^192\.168\.1\.10 pve\.local$/d' /etc/avahi/avahi-daemon.conf /etc/avahi/hosts
cat > /etc/systemd/system/pra-pve-local.service <<'UNIT'
[Unit]
Description=Publie pve.local (mDNS) pour 10.0.0.10
After=avahi-daemon.service
Requires=avahi-daemon.service
[Service]
ExecStart=/usr/bin/avahi-publish -a -R pve.local 10.0.0.10
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
# le partage se présente sous le nom de pve (PVE) ; Samba ne s'annonce plus lui-même (il annoncerait le nom de l'hôte et
# toutes ses adresses) : l'annonce _smb._tcp pointe sur pve.local
grep -q '^[[:space:]]*netbios name = PVE$' /etc/samba/smb.conf || sed -i 's/^\[global\]$/[global]\n\tnetbios name = PVE\n\tmulticast dns register = no/' /etc/samba/smb.conf
cat > /etc/systemd/system/pra-pve-smb.service <<'UNIT'
[Unit]
Description=Annonce mDNS du partage PVE sur pve.local
After=pra-pve-local.service
Requires=avahi-daemon.service
[Service]
ExecStart=/usr/bin/avahi-publish -s -H pve.local PVE _smb._tcp 445
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable --now smbd nmbd nfs-server </dev/null >/dev/null 2>&1; systemctl restart avahi-daemon smbd nmbd 2>/dev/null; systemctl enable --now pra-pve-local pra-pve-smb >/dev/null 2>&1; sleep 3
systemctl is-active pra-pve-local pra-pve-smb | paste -sd' '; avahi-resolve -4 -n pve.local
timeout 5 avahi-browse -rtp _smb._tcp 2>/dev/null | grep '^=' | cut -d';' -f2,3,4,7,8,9
exportfs -ra
qm status "$i"; exportfs -v | head
CIBLE
  exit 0
fi

# --- contrôles locaux ---
for motif in 'vzdump-qemu-110-*.vma.zst.gpg' 'fog-110-images-*.tar.zst.gpg' 'pve-partage-*.tar.zst.gpg'; do
  f="$(ls "$TIRAGE"/$motif 2>/dev/null | tail -1)"; [ -n "$f" ] || { echo "ARRÊT : $motif absent de $TIRAGE" >&2; exit 1; }
  ( cd "$TIRAGE" && sha256sum --status -c "$(basename "$f").sha256" ) || { echo "ARRÊT : empreinte de $(basename "$f")" >&2; exit 1; }
done
[ -s "$TIRAGE/debs-partage.tar" ] && ( cd "$TIRAGE" && sha256sum --status -c debs-partage.tar.sha256 ) || { echo "ARRÊT : debs-partage.tar" >&2; exit 1; }
UUID_IMAGES="$(head -1 "$(ls "$TIRAGE"/fog-110-disque-images-*.txt | tail -1)")"
[[ "$UUID_IMAGES" =~ ^[0-9a-f-]{36}$ ]] || { echo "ARRÊT : UUID du disque d'images illisible" >&2; exit 1; }
if [ "$mode" = sec ]; then
  echo "À SEC ($PRA_CIBLE) : FOG $VMID restauré arrêté sur $DS, disque d'images ${TAILLE_IMAGES_GO} Go (UUID $UUID_IMAGES), partage /tank/partage (SMB + NFS)"
  echo "relancer avec --oui"; exit 3
fi
[ -s "$CLE" ] || { echo "clé absente : bash phrase-session.sh charger" >&2; exit 2; }
verifier_cible || { echo "REFUS : cible $PRA_CIBLE injoignable" >&2; exit 4; }

echo "== 1. déchiffrement en flux vers $PRA_CIBLE:$CLAIR"
ssh_labo "mkdir -p $CLAIR"
# une archive par sorte : la plus récente (horodatage dans le nom), si un passage en contient plusieurs
for f in $(for m in vzdump-qemu-110 fog-110-images pve-partage; do ls "$TIRAGE"/$m-*.zst.gpg | tail -1; done); do
  nom="$(basename "$f" .gpg)"
  if ssh_labo "test -s $CLAIR/$nom && zstd -t -q $CLAIR/$nom"; then echo "$nom : déjà là"; continue; fi
  # FOG déjà restauré avec ses images (repère posé sur le disque d'images) : ses archives ne servent plus
  case "$nom" in vzdump-qemu-110-*|fog-110-images-*)
    if ssh_labo "qm config $VMID 2>/dev/null | grep -q '^scsi1: $DS:'"; then echo "$nom : FOG déjà en place, sautée"; continue; fi ;;
  esac
  gpg --batch --pinentry-mode loopback --passphrase-fd 3 -d "$f" 3<"$CLE" 2>/dev/null | ssh_labo "cat > $CLAIR/$nom.partiel"
  ssh_labo "zstd -t -q $CLAIR/$nom.partiel && mv $CLAIR/$nom.partiel $CLAIR/$nom" || { echo "ARRÊT : $nom illisible après déchiffrement" >&2; exit 1; }
  echo "$nom : OK"
done
ssh_labo "test -s $CLAIR/debs-partage.tar" || cat "$TIRAGE/debs-partage.tar" | ssh_labo "cat > $CLAIR/debs-partage.tar"

echo "== 2. FOG : restauration (arrêtée), disque d'images neuf, images"
ssh_labo bash -s -- "$VMID" "$CLAIR" "$DS" "$UUID_IMAGES" "$TAILLE_IMAGES_GO" <<'CIBLE'
set -euo pipefail
i="$1"; clair="$2"; ds="$3"; uuid="$4"; go="$5"
if ! qm status "$i" >/dev/null 2>&1; then
  qmrestore "$(ls "$clair"/vzdump-qemu-"$i"-*.vma.zst | tail -1)" "$i" --storage "$ds" </dev/null > /tmp/restore-"$i".log 2>&1 || { tail -5 /tmp/restore-"$i".log; exit 1; }
fi
qm set "$i" --onboot 0 >/dev/null
# lignes de disque héritées de la source, retirées de la config sans toucher aucun volume :
# scsi1 hors du stockage cible, et unusedN absent de la cible ou désignant un volume déjà attaché (le disque système)
conf=/etc/pve/qemu-server/"$i".conf
for cle in $(sed -n '/^\[/q; s/^\(scsi1\|unused[0-9]*\): .*/\1/p' "$conf"); do
  vol="$(sed -n "/^\[/q; s/^$cle: \([^,]*\).*/\1/p" "$conf")"
  case "$cle" in
    scsi1) [ "${vol%%:*}" = "$ds" ] && continue ;;
    *) p="$(pvesm path "$vol" 2>/dev/null || true)"
       if [ -n "$p" ] && [ -e "$p" ] && ! sed -n '/^\[/q; /^unused/d; p' "$conf" | grep -qF "$vol,"; then continue; fi ;;
  esac
  echo "  ligne retirée de la config : $cle: $vol"
  sed -i "0,/^$cle: /{/^$cle: /d}" "$conf"
done
if ! qm config "$i" | grep -q "^scsi1: $ds:"; then
  qm set "$i" --scsi1 "$ds:$go" >/dev/null
  vol="$(qm config "$i" | sed -n 's/^scsi1: \([^,]*\),.*/\1/p')"; dev="$(pvesm path "$vol")"
  [ -b "$dev" ] || { echo "ARRÊT : $dev n'est pas un périphérique bloc"; exit 1; }
  mkfs.ext4 -q -U "$uuid" -L images "$dev"
fi
vol="$(qm config "$i" | sed -n 's/^scsi1: \([^,]*\),.*/\1/p')"; dev="$(pvesm path "$vol")"
[ "$(blkid -o value -s UUID "$dev")" = "$uuid" ] || { echo "ARRÊT : $dev ne porte pas l'UUID attendu $uuid"; exit 1; }
a="$(ls "$clair"/fog-110-images-*.tar.zst 2>/dev/null | tail -1 || true)"; repere=".pra-$(basename "${a:-aucune}" .tar.zst)"
m="$(mktemp -d)"; mount "$dev" "$m"
if [ -z "$a" ] && ls "$m"/.pra-fog-110-images-* >/dev/null 2>&1; then echo "  images déjà en place ($(cd "$m" && ls -d .pra-*))"
elif [ -z "$a" ]; then umount "$m"; echo "ARRÊT : archive d'images absente et disque d'images non rempli"; exit 1
elif [ -e "$m/$repere" ]; then echo "  images déjà en place ($repere)"
else
  tar -I zstd -xf "$a" --numeric-owner -C "$m" || { umount "$m"; echo "ARRÊT : extraction des images"; exit 1; }
  own="$(stat -c %u:%g "$m"/dev)"; chown "$own" "$m"; chmod 775 "$m"; touch "$m"/.mntcheck; chown "$own" "$m"/.mntcheck
  touch "$m/$repere"
fi
du -sh "$m"/* | sed 's/^/  /'; umount "$m"; rmdir "$m"
qm config "$i" | grep -E '^(scsi|ide|unused|net|onboot)'
CIBLE

echo "== 3. partage de l'hôte : paquets, contenu, Samba, NFS"
ssh_labo bash -s -- "$CLAIR" <<'CIBLE'
set -euo pipefail
clair="$1"
# une installation qui retire des paquets (ex. proxmox-ve pour une bibliothèque partagée) est refusée
sans_retrait() { if apt-get install -s -q "$@" </dev/null 2>/dev/null | grep "^Remv"; then echo "ARRÊT : apt retirerait les paquets ci-dessus"; exit 1; fi; }
if ! command -v smbd >/dev/null || ! command -v exportfs >/dev/null || ! command -v avahi-daemon >/dev/null || ! command -v avahi-publish >/dev/null; then
  sans_retrait samba nfs-kernel-server avahi-daemon avahi-utils
  apt-get install -y -q samba nfs-kernel-server avahi-daemon avahi-utils </dev/null >/tmp/apt-partage.log 2>&1 || {
    echo "pas d'Internet : paquets du passage, servis par un dépôt apt local"
    # dépôt local : apt choisit parmi les alternatives du lot, même sans aucune liste de paquets en ligne
    d=/root/pra/depot-debs; mkdir -p "$d"; tar -xf "$clair"/debs-partage.tar -C "$d"
    (cd "$d" && apt-ftparchive packages . > Packages)
    echo "deb [trusted=yes] file:$d ./" > /etc/apt/sources.list.d/pra-depot-debs.list
    apt-get update -q -o Dir::Etc::sourcelist=sources.list.d/pra-depot-debs.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 </dev/null >/tmp/apt-partage.log 2>&1
    sans_retrait --no-install-recommends samba nfs-kernel-server avahi-daemon avahi-utils
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends samba nfs-kernel-server avahi-daemon avahi-utils </dev/null >>/tmp/apt-partage.log 2>&1 || { rm -f /etc/apt/sources.list.d/pra-depot-debs.list; tail -8 /tmp/apt-partage.log; exit 1; }
    rm -f /etc/apt/sources.list.d/pra-depot-debs.list
  }
fi
t="$(mktemp -d)"; tar -I zstd -xf "$(ls "$clair"/pve-partage-*.tar.zst | tail -1)" -C "$t"
mkdir -p /tank/partage; cp -a "$t"/tank/partage/. /tank/partage/
[ -f /etc/samba/smb.conf.avant-pra ] || cp -a /etc/samba/smb.conf /etc/samba/smb.conf.avant-pra
cp "$t"/etc/samba/smb.conf /etc/samba/smb.conf
cat "$t"/etc/samba/partage-sharenfs.txt; rm -rf "$t"
mkdir -p /etc/exports.d
cat > /etc/exports.d/pra-partage.exports <<'EXP'
/tank/partage 10.0.0.0/24(rw,no_subtree_check,all_squash,anonuid=65534,anongid=65534,insecure)
/tank/iso-netboot 10.0.0.11/32(ro,no_subtree_check)
EXP
mkdir -p /tank/iso-netboot
# configuré mais NON servi avant la bascule : sinon le secours publierait un partage à côté de celui de pve
systemctl disable --now smbd nmbd nfs-server </dev/null >/dev/null 2>&1; exportfs -ra 2>/dev/null || true
echo "Samba et NFS configurés, arrêtés jusqu'à la bascule (--demarrer)"
testparm -s 2>/dev/null | grep -A3 '^\[partage\]'; exportfs -v
du -sh /tank/partage
CIBLE
echo "fait : FOG restauré ARRÊTÉ, partage servi par la cible. Après la bascule : bash pra/fog-partage.sh --demarrer"
