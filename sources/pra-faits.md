# Fiche 5.1 — faits du PRA : ISO PVE 9.2, restauration croisée (consultée 2026-10-16)

Réserve : WebFetch = modèle résumeur ; les pages man ont été rendues en RÉSUMÉ (l'outil l'a dit), pas en citation intégrale.

## ISO (éditeur) — https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso
- « Proxmox VE 9.2 ISO Installer », version 9.2-1, « Last Updated » May 21, 2026, fichier proxmox-ve_9.2-1.iso, 1.71 GB.
- SHA256 : 4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c
- URL : https://enterprise.proxmox.com/iso/proxmox-ve_9.2-1.iso
- (ARM64 : proxmox-ve_9.2-1-arm64.iso, sha256 b1619dcd1f5b1a6d67d77b59e7e2fa2033174551d1e1b9dc22b2171ec093abbd, hors sujet pour x86.)
- Écart : l'arbre cite pve en 9.2.21 (paquet pveversion) ; l'ISO est 9.2-1 ; mise à jour par apt nécessaire pour égaler 9.2.21 [hypothèse, non vérifié].

## PVE dans une VM KVM
- https://pve.proxmox.com/wiki/Installation : pas d'URL ISO ni de somme, pas de section « dans une VM » lisible (astuces en images). Voir SOURCES.md §8 (Nested_Virtualization, déjà consulté : `options kvm-intel nested=Y`, `qm set <vmid> --cpu host`). Procédure d'installation en VM : [non trouvé] page dédiée.

## pct restore — https://pve.proxmox.com/pve-docs/pct.1.html (RÉSUMÉ par l'outil, 100000 des 228622 caractères lus)
- Synopsis : `pct restore <vmid> <ostemplate> [OPTIONS]` ; vmid 100 à 999999999.
- --storage : « Default storage. Default local. » ; --unique : « Assigns a random Ethernet address. Requires `--restore`. » (formulation résumée) ; --force (écrase) ; --rootfs (volume racine : size, acl, ...) ; --mp[n] ; --net[n] (name, bridge, hwaddr, ip, gw, tag...) ; --unprivileged (« For restores, the default comes from the backup ») ; --features, --arch, --hostname, --start, --pool, --bwlimit, --ignore-unpack-errors, --ostype, --password.
- Aucune option de « réécriture » automatique du réseau n'est listée : on surcharge avec --net0.
## pct chapitre — https://pve.proxmox.com/pve-docs/chapter-pct.html (caractères 100000+)
- « Restoring container backups made with vzdump is possible using the pct restore command. » « By default, pct restore will attempt to restore as much of the backed up container configuration as possible. » « It is possible to override the backed up configuration by manually setting container options on the command line ».
- Mode simple (ni rootfs ni mpX donnés) : volumes créés sur --storage (défaut local) ; « Since bind and device mounts are never backed up, no files are restored in the last step » ; mode avancé : « This advanced mode completely ignores the rootfs and mpX configuration options contained in the backup archive » ; `pvesm extractconfig` affiche la config d'une archive. Section « autre hôte » : non traitée.
## qmrestore — https://pve.proxmox.com/pve-docs/qmrestore.1.html
- « qmrestore <archive> <vmid> [OPTIONS] » ; « --storage: Default storage. » ; « --unique: Assign a unique random ethernet address. » ; « --force: Allow to overwrite existing VM. » ; « --live-restore: ... PBS only. » ; « --start », « --pool », « --bwlimit ».
- Réseau : aucune option de réécriture ; édition par `qm set` après restauration [hypothèse].

## Verdict
ÉTABLI pour ISO (URL, sha256, date) et options pct/qmrestore (en résumé). PARTIEL : restauration sur un AUTRE hôte — aucune page officielle lue ne traite le cas ; ce qui se déduit (restore autonome depuis archive, --storage à adapter au stockage cible, --unique, --net0 pour le pont) reste [hypothèse] à confirmer au labo. Installation PVE en VM : non trouvé hors Nested_Virtualization.

---

## Revérification 2026-10-18

Réserve d'outil : pas de Bash/curl dans cette session ; WebFetch passe par un modèle résumeur qui limite chaque citation à 125 caractères. Les citations ci-dessous sont donc EXACTES mais FRAGMENTAIRES ; l'intégralité mot pour mot des entrées longues (--rootfs, --net[n]) n'a pas pu être obtenue. Essai de la source brute git.proxmox.com (pct.1-synopsis.adoc) : HTTP 404. Pages lues sur les 100000 premiers caractères seulement (pct.1.html : 228622 au total).

### 1. ISO — https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso (consultée 2026-10-18, niveau : éditeur)
- x86-64 : version « 9.2-1 », « Last Updated » « May 21, 2026 », SHA256 `4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c` = identique à la fiche.
- ARM64 : « 9.2-1-arm64 », « August 05, 2026 », SHA256 `b1619dcd1f5b1a6d67d77b59e7e2fa2033174551d1e1b9dc22b2171ec093abbd` = identique. L'ISO la plus récente par date est l'ARM64 ; la plus récente x86-64 reste 9.2-1. Aucun écart.

### 2. pct restore — https://pve.proxmox.com/pve-docs/pct.1.html (consultée 2026-10-18, niveau : officiel éditeur ; la section `pct restore` est identique à `pct create`)
- --storage : « Default Storage. » ; type `<storage ID>`, défaut `local`.
- --unique : « Assign a unique random ethernet address. » ; « Requires option(s): restore ».
  (ÉCART : la fiche citait « Assigns a random Ethernet address. Requires `--restore` » = formulation approximative ; la bonne est celle-ci.)
- --force : « Allow to overwrite existing container. » ; booléen.
- --rootfs : « Use volume as container root. » ; synopsis : « --rootfs [volume=]<volume> [,acl=<1|0>] [,idmap=<type:container:disk:range-size[;type:container:disk:range-size;...]>] » ; sous-clés suivantes non citées littéralement : mountoptions, quota, replicate, ro, shared, size.
- --net[n] : « Specifies network interfaces for the container. » ; synopsis (début) : « --net[n] name=<string> [,bridge=<bridge>] [,firewall=<1|0>] [,gw=<GatewayIPv4>] [,gw6=<GatewayIPv6>] » ; autres sous-clés : host-managed, hwaddr, ip, ip6, link_down, mtu, rate, tag, trunks, type.
- --unprivileged : « Makes the container run as unprivileged user. » et « For restore, the default is the value from the backup. » (création : défaut 1, à ne pas modifier à la main).
- Recoupement niveau code (éditeur), source https://raw.githubusercontent.com/proxmox/pve-container/master/src/PVE/API2/LXC.pm : storage « Default Storage. » ; unique « Assign a unique random ethernet address. » ; force « Allow to overwrite existing container. » ; restore « Mark this as restore task. ». Concordant. (--unprivileged : partie tronquée, non lue.)
  Note : la fiche écrivait « Default storage. Default local. » pour --storage : majuscule « Storage » dans la source.

### 3. Restauration d'une sauvegarde vzdump sur un AUTRE hôte/cluster
- https://pve.proxmox.com/wiki/Backup_and_Restore (consultée 2026-10-18, officiel) : aucun passage sur la restauration sur un autre hôte/cluster. Seul passage voisin : « In both cases, you might want to save those backups later to a tape drive, for off-site archiving. »
- https://pve.proxmox.com/pve-docs/chapter-pvecm.html (consultée 2026-10-18, officiel, 100000 des 186736 caractères lus) : « a joining node cannot hold any guests, since guest IDs could otherwise conflict. » et « you can create a backup of each guest (using vzdump) and restore it under a different ID after joining. » = seul texte officiel proche (adhésion à un cluster), pas une procédure de restauration sur un hôte distinct.
- Page officielle dédiée (docs/wiki) à « restaurer un vzdump sur un autre hôte/cluster » : NON TROUVÉ le 2026-10-18 (recherche web restreinte à proxmox.com/pve.proxmox.com/forum.proxmox.com).
- Forum (niveau secondaire, communauté, PAS staff), source https://forum.proxmox.com/threads/restore-backups-from-another-cluster.146552/ (consulté 2026-10-18) : « Copy them to your external storage before formatting and reinstalling your cluster. » / « Then after a clean install, copy them back to that directory. » (auteur : Member). Aucune réponse staff. Indicatif seulement.
- Conclusion inchangée : restauration croisée = [hypothèse] à confirmer au labo.

## Texte intégral de l'aide installée (pve, pve-manager/9.2.21, lu 2026-10-18 par `ssh pve pct help restore --verbose`)
Niveau : outil de l éditeur, version en production (lève la réserve « résumé/125 caractères » des passages WebFetch).
```
  --force    <boolean>
	     Allow to overwrite existing container.

  --ha-managed <boolean>   (default=0)
	     Add the CT as a HA resource after it was created.

--
  --net[n]   name=<string> [,bridge=<bridge>] [,firewall=<1|0>]
	     [,gw=<GatewayIPv4>] [,gw6=<GatewayIPv6>] [,host-managed=<1|0>]
	     [,hwaddr=<XX:XX:XX:XX:XX:XX>] [,ip=<(IPv4/CIDR|dhcp|manual)>]
	     [,ip6=<(IPv6/CIDR|auto|dhcp|manual)>] [,link_down=<1|0>]
	     [,mtu=<integer>] [,rate=<mbps>] [,tag=<integer>]
	     [,trunks=<vlanid[;vlanid...]>] [,type=<veth>]
--
  --rootfs   [volume=]<volume> [,acl=<1|0>]
	     [,idmap=<type:container:disk:range-size[;type:container:disk:r
	     ange-size;...]>] [,mountoptions=<opt[;opt...]>] [,quota=<1|0>]
	     [,replicate=<1|0>] [,ro=<1|0>] [,shared=<1|0>]
	     [,size=<DiskSize>]
	     Use volume as container root.
--
  --storage  <storage ID>   (default=local)
	     Default Storage.

  --swap     <integer> (0 - N)	 (default=512)
	     Amount of SWAP for the container in MB.

--
  --unique   <boolean>
	     Assign a unique random ethernet address.

	     Requires option(s): restore

  --unprivileged <boolean>   (default=0)
	     Makes the container run as unprivileged user. For creation,
	     the default is 1. For restore, the default is the value from
	     the backup. (Should not be modified manually.)

  --unused[n] [volume=]<volume>
```
