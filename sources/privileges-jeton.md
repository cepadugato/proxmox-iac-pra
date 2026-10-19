# Fiche 1.2 — privilèges d'un jeton PVE 9 pour LXC via bpg/proxmox 0.116.x (consultée 2026-10-16)

Réserve : WebFetch passe par un modèle résumeur ; guillemets = extraits rapportés par l'outil, non vérifiés au caractère.

## A. Liste officielle des privilèges (officiel, pve-docs)
URL : https://pve.proxmox.com/pve-docs/chapter-pveum.html (texte lu jusqu'au caractère 100000 sur 110867)
- « VM.Allocate: create/remove VM on a server » ; « VM.Audit: view VM config » ; « VM.Backup: backup/restore VMs » ; « VM.Clone: clone/copy a VM » ; « VM.Config.CDROM/CPU/Cloudinit/Disk/HWType/Memory/Network/Options » ; « VM.Console » ; « VM.Migrate » ; « VM.PowerMgmt: power management (start, stop, reset, shutdown, …) » ; « VM.Snapshot », « VM.Snapshot.Rollback ».
- « SDN.Use: access SDN vnets and local network bridges » ; « SDN.Audit: view SDN configuration ».
- « Datastore.Allocate: create/modify/remove a datastore and delete volumes » ; « Datastore.AllocateSpace: allocate space on a datastore » ; « Datastore.AllocateTemplate: allocate/upload templates and ISO images » ; « Datastore.Audit: view/browse a datastore ».
- « Sys.Audit: view node status/config, Corosync cluster config, and HA config » ; « Sys.Modify: create/modify/remove node network parameters » ; « Pool.Allocate », « Pool.Audit ». « Both Permissions.Modify and Sys.Modify should be handled with care. »
- Rôles : PVEAuditor « has read only access » ; PVEVMAdmin « fully administer VMs » ; PVEDatastoreUser « allocate backup space and view storage » ; PVEDatastoreAdmin « create and allocate backup space and templates ». La page ne donne PAS les listes de privilèges par rôle.
- Jetons : « Separated privileges are the default for new tokens. "Its effective permissions are calculated by intersecting user and token permissions." » ; privsep=0 : « The token's permissions are identical to that of the associated user. »
- La page ne dit PAS que certaines opérations sont réservées à root@pam (résumé outil).

## B. Composition des rôles (officiel, code source ; résumé outil, pas de citation littérale possible)
URL : https://git.proxmox.com/?p=pve-access-control.git;a=blob_plain;f=src/PVE/AccessControl.pm;hb=refs/heads/master (branche master, 2026-10-16 ; peut être en avance sur PVE 9.2)
- PVEAuditor = tous les privilèges « audit » : VM.Audit, VM.GuestAgent.Audit, Sys.Audit, Datastore.Audit, SDN.Audit, Pool.Audit, Mapping.Audit.
- PVEVMAdmin = privilèges VM admin+user+audit (23), dont VM.Allocate, VM.Config.Disk, VM.Migrate, VM.Console, VM.PowerMgmt, VM.Audit ; aucun Pool.*, aucun Datastore.*, aucun SDN.Use (SDN.Use est dans PVESDNUser/PVESDNAdmin/PVEAdmin).
- PVEDatastoreUser = Datastore.AllocateSpace + Datastore.Audit. PVEDatastoreAdmin = Datastore.Allocate, AllocateTemplate, AllocateSpace, Audit.
- Source citée littéralement : `$special_roles->{"PVETemplateUser"} = { 'VM.Clone' => 1, 'VM.Audit' => 1 };`

## C. Ce que bpg documente (officiel éditeur)
URL : https://raw.githubusercontent.com/bpg/terraform-provider-proxmox/main/docs/index.md (branche main)
- « -> Not all Proxmox API operations are supported via API Token. » ; « ~> The list of available privileges has changed in PVE 9.0. »
- Exemple de rôle : `pveum role add Terraform -privs "Realm.AllocateUser, VM.PowerMgmt, VM.GuestAgent.Unrestricted, Sys.Console, Sys.Audit, Sys.AccessNetwork, VM.Config.Cloudinit, VM.Replicate, Pool.Allocate, SDN.Audit, Realm.Allocate, SDN.Use, Mapping.Modify, ..."` (liste tronquée par l'outil) ; « The above list is only an example (and likely too permissive for most use cases). »
- « Keep `SDN.Audit` or `SDN.Use` in the role: PVE hides bridges from `GET /nodes/{node}/network` when the caller lacks either of them » ; `pveum aclmod / -user terraform@pve -role Terraform` ; `pveum user token add terraform@pve provider --privsep=0`.
- Erreurs documentées : « only root can set 'arch' config » (HTTP 500, création VM) ; « Permission check failed (changing feature flags for privileged container is only allowed for root@pam) » (HTTP 403, conteneur) ; « Permission check failed (user != root@pam) ».
- SSH : seulement pour opérations listées (snippets, idmap...) ; non-root : sudo sans mot de passe ; exemple « terraform ALL=(root) NOPASSWD: /usr/sbin/pvesm apiinfo ».

## D. Ressource conteneur bpg
URL : https://raw.githubusercontent.com/bpg/terraform-provider-proxmox/main/docs/resources/virtual_environment_container.md
- features : « The container feature flags. Changing flags (except nesting) is only allowed for `root@pam` authenticated user. » (nesting, fuse, keyctl, mount, mknod, défauts false).
- « Bind-mount a host directory (requires `root@pam` auth) » ; idmap : « written as `lxc.idmap` entries in the container configuration file via SSH » ; `cpu.architecture` défaut amd64 (le texte sur « arch réservé à root » vient de index.md).
- Migration : « Every migration needs `VM.Migrate` on the container and `Sys.Audit` on `/` ».
- La page ne liste pas les privilèges pour créer/détruire un LXC.

## Verdict
PARTIEL. Établi : liste officielle des privilèges, composition PVEAuditor/PVEVMAdmin/Datastore*, ce qui exige root@pam (flags features sauf nesting ; arch ; bind mount ; idmap via SSH). NON TROUVÉ : liste minimale officielle pour créer/modifier/détruire un LXC (ni PVE ni bpg ne la donne). [hypothèse] à valider par essais : PVEVMAdmin + PVEDatastoreAdmin ou Datastore.AllocateSpace/Audit sur /storage/<id> + SDN.Use sur /sdn/zones/... (ou /) + Sys.Audit ; Pool.* seulement si pool utilisé. Lecture seule (plan) : PVEAuditor (contient Sys.Audit, SDN.Audit, Datastore.Audit, VM.Audit) [fait, composition], suffisance pour le plan bpg non vérifiée.
