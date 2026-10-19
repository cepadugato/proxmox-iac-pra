# Cible labo (feuille 5.6a, D24 (2)) : Proxmox imbriqué joint par le lien dédié 10.255.70.0/30 (labo = .2).
# Choisi par ../tofu-cible.sh labo ; jamais en direct (garde.yml). Aucun secret.
proxmox_endpoint = "https://10.255.70.2:8006/"
node             = "pra-lab"
datastore        = "local-lvm" # rootfs des CT : lvmthin (content rootdir) ; « local » (dir) n'accepte pas rootdir (essai 1 de 5.7)
labo_started     = true
cible            = "labo"
template_file_id = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
features_root    = false # keyctl/fuse : root@pam seulement ; remis par pct restore (5.8)
