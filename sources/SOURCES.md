# SOURCES — infra-as-code (OpenTofu + bpg/proxmox) — consultées le 2026-10-16

Réserve générale : WebFetch passe par un modèle résumeur ; les citations ci-dessous sont celles rapportées par l'outil (courts extraits entre guillemets), pas des copies intégrales vérifiées au caractère. Registry.terraform.io est rendu en JS (inexploitable) : docs bpg lues sur raw.githubusercontent.com (dépôt de l'éditeur, branche main = peut être en avance sur la version publiée).

## 1. Versions et compatibilité
- [fait] OpenTofu dernière stable : v1.13.1, publiée 2026-10-01. https://api.github.com/repos/opentofu/opentofu/releases/latest (officiel)
- [fait] bpg/proxmox dernière : v0.116.1, publiée 2026-10-15. https://api.github.com/repos/bpg/terraform-provider-proxmox/releases/latest (officiel)
- [fait] Compat bpg : « Terraform 1.6+ (tested in CI) or OpenTofu 1.6+ (supported, not exercised in CI). » ; « Write-only attributes require Terraform 1.11+ or OpenTofu 1.10+. » ; PVE : « Proxmox VE 9.x. Proxmox VE 8.x works with some limitations and is not a testing priority; 7.x is not supported. » https://raw.githubusercontent.com/bpg/terraform-provider-proxmox/main/docs/index.md (officiel). Idem README : « Proxmox VE 8.x is supported, but some functionality might be limited… 7.x is NOT supported. »
- [fait] ÉCART OneUptime : https://oneuptime.com/blog/post/2026-02-23-how-to-configure-proxmox-provider-in-terraform/markdown (secondaire) dit « PVE 7.x or 8.x », « Terraform 1.0 or later », pin `~> 0.106`, ne mentionne pas OpenTofu. Contredit bpg (7.x non supporté, >=1.6). La doc bpg prévaut ; OneUptime obsolète/inexact. Conséquence : OpenTofu >=1.6 suffit pour bpg, mais OpenTofu n'est que « supporté, non testé en CI ».

## 2. Import d'un LXC
- [fait] ID d'import : `node_name/vm_id`. « Instances can be imported using the `node_name` and the `vm_id` » ; exemple `terraform import proxmox_virtual_environment_container.ubuntu_container first-node/1234`. https://raw.githubusercontent.com/bpg/terraform-provider-proxmox/main/docs/resources/virtual_environment_container.md (officiel)
- [fait] Bloc `import {}` : `to` + (`id` ou `identity`, exclusifs) ; traité au plan, appliqué à l'apply ; « A matching `resource` block must exist before import » (résumé outil). https://opentofu.org/docs/language/import/ (officiel). Version d'introduction non indiquée par la page.
- [fait] `tofu plan -generate-config-out=<nouveau fichier>` : « available in OpenTofu v1.6 as an experimental feature » ; chemin existant = erreur ; « For certain resources with complex schemas, OpenTofu may not be able to construct a valid configuration » ; attributs sensibles/write-only peuvent être mis à `null` ; à relire. https://opentofu.org/docs/language/import/generating-configuration/ (officiel)
- [fait] Limites dans la doc bpg container : `password` (user_account) « only applies when the container is created » → non relisible à l'import ; `template_file_id` = identifiant de template ; `tags` : Proxmox met en minuscules/trie → diff perpétuel, doc conseille `ignore_changes`. Même fichier. [hypothèse] diff perpétuel probable sur password/template_file_id/disk après import : non documenté explicitement, à tester par recette.

## 3. Authentification bpg
- [fait] « API Token — recommended for production and CI/CD » ; « SSH access is optional » ; SSH non requis pour « Creating, modifying, or deleting VMs and Containers ». docs/index.md (officiel)
- [fait] SSH requis pour : upload de snippets, idmap LXC (« Proxmox API doesn't support `lxc[n]` parameters ») ; utilisateur ssh non-root : sudo sans mot de passe. Token insuffisant : « Not all Proxmox API operations are supported via API Token », erreurs « only root can set 'arch' config », « Permission check failed (user != root@pam) ». « The list of available privileges has changed in PVE 9.0. » Même source.
- [non trouvé] Liste officielle des privilèges minimaux pour un LXC (doc bpg ne la donne pas dans ce qui a été lu ; seul `SDN.Audit`/`SDN.Use` cité). Secondaire (blogs communautaires) : VM.Allocate, VM.Config.*, Datastore.AllocateSpace/Audit, Sys.Audit, SDN.Use ; download_file demande Datastore.AllocateTemplate (résultat de recherche, non ouvert) — [hypothèse]. → voir « Complément D10 » ci-dessous (liste des privilèges établie ; minimum LXC toujours non trouvé).

## 4. Chiffrement de l'état
- [fait] https://opentofu.org/docs/language/state/encryption/ (officiel, doc v1.13.x) : `key_provider "pbkdf2" "nom" { passphrase = var.passphrase }`, `method "aes_gcm" "nom" { keys = key_provider.pbkdf2.nom }`, bloc `state { method = method.aes_gcm.nom }`, `plan{}` idem, option `enforced = true`.
- [fait] Migration depuis état en clair : `method "unencrypted" "migrate" {}` + `fallback { method = method.unencrypted.migrate }` puis retirer le fallback et envisager `enforced`.
- [fait] Avertissements : « When you enable encryption, your state and plan files become unrecoverable without the appropriate encryption key. » ; « make sure you have backups of your keys. »
- [non trouvé] Version d'introduction (1.7) : la page ne l'indique pas ; non vérifié.

## 5. Forgejo Actions
- [fait] Activation : « As of Forgejo v1.21, Actions is enabled by default » ; désactivation `ENABLED = false` dans `[actions]` d'app.ini ; workflows dans `.forgejo/workflows`. https://forgejo.org/docs/latest/admin/actions/runner-installation/ (officiel). Installation runner : binaire, Docker ou paquets ; enregistrement + choix de labels ; « Forgejo Runner performs remote code execution ».
- [fait] Runner : dernière release v13.2.0 (2026-09-18) ; v13.0.0 « breaking changes… security », retire compat Gitea, variables `GITEA_`, secrets pour auth registre, `set-output/set-env/add-path`. https://code.forgejo.org/forgejo/runner/releases (officiel)
- [fait] « GitHub Actions and Forgejo Actions are not the same and things might not work right away » ; `uses:` relatif résolu via `DEFAULT_ACTIONS_URL` (défaut https://data.forgejo.org) → préférer URL complète ; contexte `secrets` = secrets du dépôt, vide pour PR de fork. https://forgejo.org/docs/latest/user/actions/reference/ (officiel). Emplacement UI des secrets : non documenté sur cette page. → voir « Complément D10 » (chemins trouvés sur basic-concepts).
- [fait] setup-opentofu : `uses: opentofu/setup-opentofu@v2` avec `tofu_version` ; `github_token` « Defaults to the value of the GITHUB_TOKEN environment variable unless running on Forgejo or Gitea. » https://github.com/opentofu/setup-opentofu (éditeur). [hypothèse] utilisable sur Forgejo via URL complète github.com (action absente de data.forgejo.org non vérifié) ; à tester.

## 6. Bonnes pratiques
- [fait] Lock : « should include this file in your version control repository » ; `tofu init -upgrade` pour monter de version. https://opentofu.org/docs/language/files/dependency-lock/ (officiel)
- [fait] Backend : défaut `local` (fichier d'état local) ; identifiants via variables d'environnement ; `.terraform/` « Do not check this directory into Git ». https://opentofu.org/docs/language/settings/backends/configuration/ (officiel). Recommandation officielle local vs distant : non énoncée dans l'extrait.
- [fait] `ignore_changes` : « intended to be used when a resource is created with references to data that may change » ; « Only attributes defined by the resource type can be ignored. » https://opentofu.org/docs/language/resources/behavior/ (officiel)

## 7. MCP (rien installé)
- [fait] HashiCorp Terraform MCP server : dépôt hashicorp/terraform-mcp-server, doc https://developer.hashicorp.com/terraform/docs/tools/mcp-server/deploy (éditeur, via résultat de recherche, page non ouverte).
- [fait partiel] OpenTofu MCP server : `@opentofu/opentofu-mcp-server`, hébergé mcp.opentofu.org ; vu seulement sur agrégateurs (glama.ai, mcp.so), dépôt officiel non ouvert → secondaire. Fonction : recherche docs du registre (pas d'action sur l'infra).
- [non trouvé] MCP Proxmox officiel ; marketplace Anthropic non consultée.

## 8. PVE imbriqué
- [fait] https://pve.proxmox.com/wiki/Nested_Virtualization (officiel) : CPU AMD ou Intel récent ; hôte : `options kvm-intel nested=Y` (ou `kvm-amd nested=1`), recharger le module ; invité PVE : `qm set <vmid> --cpu host` ; vérifier vmx/svm dans /proc/cpuinfo. Sans extensions : « CT (LXC) will be faster, of course, quite usable » → LXC utilisables en imbriqué même sans accélération, VM KVM très lentes.

## 9. Restauration / reprise
- [fait] https://pve.proxmox.com/wiki/Backup_and_Restore (officiel) : `vzdump 777`, `--dumpdir … --mode snapshot` ; `pct restore 600 /mnt/backup/vzdump-lxc-777.tar` ; `qmrestore /mnt/backup/vzdump-qemu-888.vma 601` ; live-restore pour VM depuis PBS. Restauration vers un autre nœud/stockage : non traitée par cette page.
- [fait] https://pve.proxmox.com/pve-docs/chapter-pmxcfs.html (officiel) : /etc/pve = pmxcfs (corosync.conf, storage.cfg, datacenter.cfg, user.cfg, firewall, nodes/<NOM>/lxc|qemu-server, priv/) ; récupération : copier `/var/lib/pve-cluster/config.db` vers un nouvel hôte (arrêter pve-cluster, remplacer, perms 0600, aligner hostname/hosts) ; déplacer un guest = déplacer son .conf, seulement si disques sur stockage partagé, sinon « restore from backup ».
- [fait] https://pve.proxmox.com/pve-docs/chapter-pct.html : points de montage hors backup par défaut, bind/device mounts jamais sauvegardés par vzdump. Section pct restore (options) non lue (page tronquée). → lue au Complément D10.
- [fait] PBS : `proxmox-backup-client restore` (https://pbs.proxmox.com/docs/backup-client.html, officiel) ; rien sur /etc/pve. Restauration de CT/VM depuis PBS via GUI/pct non lue en détail → [non trouvé] page dédiée.

## 10. IaC + sauvegarde
- [fait] Doc bpg container : AUCUN attribut de restauration depuis archive vzdump. Bloc `clone` (`vm_id` = conteneur source, `datastore_id`, `node_name` source) ; `template_file_id` décrit seulement comme « The identifier for an OS template file » ; seul lien backup : `mount_point.backup`. Source : fichier du point 2 (officiel). Conséquence [hypothèse] : restaurer par `pct restore` (hors OpenTofu), puis `import {}` dans OpenTofu ; ou créer la coquille et restaurer les données séparément. Non documenté comme pratique recommandée.

## 11. Isolement réseau
- [fait] https://pve.proxmox.com/wiki/Network_Configuration (officiel) : bridge sans port physique via `bridge-ports none` (exemples routé/NAT) ; trafic sorti seulement par routage/NAT de l'hôte.
- [fait] https://pve.proxmox.com/pve-docs/chapter-pvesdn.html (officiel) : zone Simple : « It will create an isolated VNet bridge. » « This bridge is not linked to a physical interface, and VM traffic is only local on each the node. » ; SDN installé par défaut depuis PVE 8.1 ; changements « pending » puis Apply ; SNAT optionnel (désactiver pour étanchéité) ; DHCP dnsmasq opt-in.

## Complément D10 (2026-10-16)
Trois fiches détaillées (citations, URL, réserves) : `privileges-jeton.md` (feuille 1.2), `ci-forgejo.md` (feuille 4.1), `pra-faits.md` (feuille 5.1). Résumé :
- 1.2 PARTIEL. [fait, officiel] liste des privilèges VM.*, Datastore.*, Sys.*, SDN.*, Pool.* (https://pve.proxmox.com/pve-docs/chapter-pveum.html) ; PVEAuditor = tous les privilèges audit, PVEVMAdmin = VM.* sans Pool/Datastore/SDN.Use (code pve-access-control, résumé outil) ; jeton : privsep par défaut, droits effectifs = intersection utilisateur/jeton. Root@pam exigé (bpg container.md) : « Changing flags (except nesting) is only allowed for `root@pam` », bind mount, `arch` (« only root can set 'arch' config »), idmap via SSH. [non trouvé] liste minimale officielle pour créer/détruire un LXC : [hypothèse] PVEVMAdmin + Datastore.AllocateSpace/Audit + SDN.Use + Sys.Audit.
- 4.1 PARTIEL. [non trouvé] compatibilité runner 13.2.0 ↔ Forgejo 14.0.3 (aucun énoncé officiel) ; [fait] 14.0 : fin de vie 30 avril 2026 selon release-schedule. [fait] binaire (gpg, /usr/local/bin, `forgejo-runner daemon -c`), Docker `data.forgejo.org/forgejo/runner:13`, enregistrement UI `/…/settings/actions/runners` + CLI `forgejo forgejo-cli actions register --secret`, `register` marqué deprecated, `create-runner-file` non documenté ; secrets `/{owner}/{repo}/settings/actions/secrets`.
- 5.1 ÉTABLI (ISO) / PARTIEL (autre hôte). ISO proxmox-ve_9.2-1.iso, sha256 4e88fe41…ef2c6c, https://enterprise.proxmox.com/iso/proxmox-ve_9.2-1.iso ; options pct restore/qmrestore lues en RÉSUMÉ (--storage, --unique, --net[n], --rootfs, --force) ; restauration vers un autre hôte non traitée par la doc lue.
