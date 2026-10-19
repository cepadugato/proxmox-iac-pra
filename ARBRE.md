# Arbre de décomposition — infra-as-code (OpenTofu + bpg/proxmox) et PRA de pve

> Étape 3a, 2026-10-16. Entrées : recettes/releve-etape1.md (relevé, noté « relevé »), sources/SOURCES.md (noté « SOURCES »).
> Une feuille = une BRIQUE testable seule, ≤ ~30 appels d'outils. Lecture : `feuille.py ARBRE.md <id>`.
> Rien ne se modifie sur pve avant la Porte 1. Le risque `fort` = fait externe ou action irréversible (destruction,
> écriture sur pve, création de jeton, mise en service du runner). Motif de vérification : celui de
> annuaire/acces.yaml + matrice-acces.py `--check` (ici `tofu plan -detailed-exitcode` : 0 = conforme, 2 = dérive).
> Objectifs : O1 import CT 100/101/122 jusqu'à plan vide · O2 CT jetable créé, détruit, recréé · O3 état chiffré + plan en CI Forgejo · O4 PRA sur Proxmox imbriqué (poste).
> Règle commune : `tofu apply` n'est lancé que si le plan ne montre ni modification ni destruction d'un CT existant.
> Recherche d'un outil existant : `bibliotheque.py "opentofu proxmox infra as code"` (2026-10-16) → aucun skill tofu/proxmox ; briques citées : porte-authelia (motif), parc-as-code/tests/run.sh (style de tests).
> Révision 2026-10-16 après le NO-GO de la Porte 1, passage 1 (recettes/porte1-passage1.md) : réponses objection par objection dans recettes/porte1-reponses.md.
> Décompte (recompté) : voir la dernière section.

## Décisions de l'admin
- D1 — Lieu du labo PRA : tranchée 2026-10-16 (Proxmox imbriqué en KVM sur le POSTE, réseau libvirt étanche, jamais sur pve ; coquille par tofu + données par les sauvegardes rapatriées)
- D2 — Forme de l'objectif 2 : tranchée 2026-10-16 (CT jetable de démonstration, VMID et IP libres, détruit puis recréé par le code ; LXC 122 sondage reste en production, il est importé et non recréé)
- D3 — Où tourne le runner Forgejo : tranchée 2026-10-16 (runner sur le POSTE, à côté de Forgejo, API pve jointe par tunnel ssh -L 8006 ; aucun service ajouté sur pve)
- D4 — Backend de l'état OpenTofu : tranchée 2026-10-16 (fichier d'état local chiffré, hors Git, recopié avec les sauvegardes (rsync/pCloud))
- D5 — Droits des jetons API Proxmox : tranchée 2026-10-16 (deux jetons bornés : lecture seule pour la CI, écriture limitée pour le poste ; jamais root@pam en CI ; features en ignore_changes)
- D6 — Services prioritaires du PRA (labo : 16-24 Go de RAM, 300 Go de disque sur 628 Go libres / 49 Go de RAM disponibles) : tranchée 2026-10-16 (deux vagues : V1 identité/accès 114, 108, 123, 121, 128, 100 ; V2 101, 122, VM 106, 110 ; VM de test exclues ; amendée par D13 le 2026-10-16 : V2 = CT 101 et 122 seulement, les VM 106 et 110 passent en vague 3 hors de cet arbre)
- D7 — Circularité du coffre (LXC 114 sur pve) et de la phrase GPG des sauvegardes (sur pve) : tranchée 2026-10-16 (noyau d'amorçage KeePassXC hors ligne (coffre-mdp L5) avec phrase GPG, clé d'état tofu et accès pCloud, sur deux supports chez deux détenteurs ; amendée par D12 le 2026-10-16 : le noyau est créé hors de ce projet, constat en 4.0 et 5.0)
- D8 — Forme des sauvegardes à rapatrier (chiffrées ou en clair) : tranchée 2026-10-16 (rapatrier les .gpg chiffrées et les déchiffrer dans le labo ; amendée par D8bis le 2026-10-16 : la source des .gpg est pCloud, plus pve ; puis par D24 (1) le 2026-10-17 : déchiffrement sur le poste)
- D9 — Dépôt Git du code et du workflow : tranchée 2026-10-16 (dépôt dédié git/infra-as-code sur Forgejo, exclu du binder IP)
- D10 — Lancer chercheur-sources sur les faits non sourcés (feuilles 1.2, 4.1, 5.1) avant la Porte 1 : tranchée 2026-10-16 (oui : chercheur-sources sur 1.2, 4.1, 5.1 avant la Porte 1)
- D11 — Montée du Forgejo local : tranchée 2026-10-16 (de 14.0.3 à 15.0 LTS, AVANT le runner, par la brique 4.9 avec sauvegarde `forgejo dump` et retour arrière testé)
- D12 — Noyau d'amorçage L5 (coffre-mdp) : tranchée 2026-10-16 (créé tout de suite par l'admin, hors de ce projet, avec coffre-mdp/creer-noyau-amorcage.sh ; dans l'arbre, dépendance externe vérifiée par les feuilles de constat 4.0 (volet O3) et 5.0 (volet O4))
- D13 — Ordre des invités du PRA : tranchée 2026-10-16 (conteneurs d'abord ; les VM 106 et 110 forment une vague 3 ultérieure, hors de cet arbre, ligne datée 2026-10-16 ; la VM 110 reste exclue des sauvegardes)
- D14 — Version du labo PRA : tranchée 2026-10-16 (installé depuis l'ISO 9.2-1, mis à jour en 9.2.21 par un NAT temporaire AVANT toute sauvegarde, puis isolé ; l'isolement est vérifié et daté, feuille 5.11)
- D15 — Sauvegarde des CT 108, 123, 128 et 129 : tranchée 2026-10-16 (ajoutés à INVITES par le fil principal, dans /etc/default/sauvegarde-hebdo sur pve, copie .avant-2026-10-16, et dans proxmox/sauvegarde ; premier passage les contenant : dimanche 2026-10-18 02:00 ; 5.2 vérifie leur présence dans le MANIFESTE de S42)
- D16 — Utilisateurs d'API pve : tranchée 2026-10-16 (deux utilisateurs distincts, tofu-ro@pve et tofu-rw@pve, validé)
- D17 — Identité d'OpenTofu dans le labo : tranchée 2026-10-16 (pas de root@pam : le labo reprend le modèle de pve, avec tofu-rw@pve créé dans le labo, `features` en ignore_changes, features restaurées par `pct restore` depuis l'archive, commande lancée en root sur l'hôte du labo hors OpenTofu ; si ce chemin ne tient pas, décision ouverte et non retour à root@pam)
- D8bis — Source des sauvegardes rapatriées : tranchée 2026-10-16 (le labo tire les `.gpg` DEPUIS pCloud par rclone, pas depuis pve : `sauvegarde-hebdo.sh` (l. 736-738, GARDER_CLAIR_LOCAL=1) efface les `.gpg` locaux après envoi vérifié et tank ne garde que le clair ; rclone est absent du poste (`which rclone` = 127) et l'accès pCloud vient du noyau L5 ; transfert poste vers labo par disque virtuel ; déchiffrement dans le labo avec la phrase du noyau ; amendée par D24 (1) le 2026-10-17 : déchiffrement SUR LE POSTE, la clé ne quitte pas le poste, le clair n'est écrit que dans le labo)
- D18 — Où tourne OpenTofu pour le labo : tranchée 2026-10-17, REMPLACÉE le même jour par D23 (texte d'origine : ARBRE-historique.md § D18)
- D19 — Jetons Forgejo en clair dans les URL de remote de 12 dépôts du poste (dont IP/.git/config, sur NTFS lisible par tous) : tranchée 2026-10-17 (restent en place, risque accepté par l'admin ; en conséquence le runner ne doit pouvoir lire NI /mnt NI /media : InaccessiblePaths=-/mnt -/media, feuille 4.5)
- D20 — Dump Forgejo /var/backups/forgejo-montee-15 (875 Mo, feuille 4.9) : tranchée 2026-10-17 (gardé 30 jours, suppression le 2026-11-16)
- D21 — Réseau du runner (objection 9 du contradicteur 4.5) : tranchée 2026-10-17 (local seulement : IPAddressDeny=any + IPAddressAllow=localhost ; ni Internet ni LAN ; workflows sans action qui télécharge, tofu installé ; la mention antérieure « décision de l'admin : non restreint » était erronée, l'admin n'avait rien tranché)
- D22 — Duplication du noyau L5 sur clés USB (feuille 4.0) : tranchée 2026-10-17 par l'admin (« on laisse de côté cette partie par clef usb ») : REPORTÉE. Le noyau existe en un seul exemplaire sur le poste (rempli le 2026-10-17 : clés de sauvegarde par noyau-remplir.sh, phrase d’état générée, box, root pve, pCloud) ; 4.0 reste ouverte ; risque accepté : perte du poste = perte du noyau ; amendée par D24 (4) le 2026-10-17 : 4.0 et 5.0 passent sur l'exemplaire unique + Vaultwarden, avec réserve écrite.
- D23 — Pilotage du labo PRA (remplace D18, rejetée par le contradicteur : recettes/contradicteur-D18.md) : tranchée 2026-10-17 par l'admin (« Le poste pilote le labo (Recommandé) ») : OpenTofu tourne SUR LE POSTE et pilote pra-lab par le réseau étanche lab-pra ; le poste reçoit une adresse sur virbr-pra (geste sudo de l'admin) ; lab-pra reste sans forward (ni Internet ni LAN) ; un pare-feu du poste refuse toute connexion initiée depuis virbr-pra ; code, état chiffré, phrase et jetons restent sur le poste ; endpoint du labo distinct de celui de pve (127.0.0.1:8006).
- D24 — Lot de décisions de la Porte 1 D23 : tranchées 2026-10-17 par l'admin : (1) archives pCloud déchiffrées SUR LE POSTE, la clé ne quitte pas le poste (écart assumé à la lettre de D8bis) ; (2) lien poste↔labo SÉPARÉ 10.255.70.0/30 (deuxième adresse du labo), aucune adresse 10.0.0.x côté poste ; (3) état du labo chiffré avec la MÊME phrase que pve (celle du noyau) ; (4) 4.0 et 5.0 amendées selon D22 : copie unique du noyau + Vaultwarden acceptée avec réserve ; (5) skill pra-labo-proxmox à mettre à jour pour D23.
- D25 — Verrou de cible dans le code (5.6a, NO-GO du juge recettes/verif-5.6a-juge.md : motif garde.yml contournable par 12 variantes) : tranchée 2026-10-18 par l'admin (« Oui, verrou dans le code (Recommandé) ») : ressource `terraform_data` portant `var.cible` en `triggers_replace` avec `prevent_destroy` dans chaque état ; tout plan qui croise état et cible échoue, quelle que soit la commande ; coût accepté : un apply unique sur l'état de pve (écrit l'état seul, aucun appel d'écriture à l'API), geste de l'admin ; la CI montre « 1 à ajouter » jusqu'à cet apply
- D26 — Périmètre du PRA entièrement en code (5.7) : tranchée 2026-10-18 par l'admin (« Tout passer en code ») contre la recommandation « restauration directe » : les 5 CT du périmètre sans code (108, 114, 121, 123, 128) sont décrits en OpenTofu et importés dans l'état de pve comme 100/101/122 en O1 (feuille 5.7a, nouvelle) avant la coquille du labo ; coût accepté : imports sur l'état de pve (gestes de l'admin, CI en « à importer » jusqu'à l'apply), juge par feuille
- D27 — Cible de secours générique : tranchée 2026-10-18 par l'admin (« Oui » à l'ajout d'une feuille en fin d'O4) : le PRA doit pouvoir viser n'importe quel Proxmox de l'asso, pas seulement le labo ; feuille 5.15 après la recette 5.10
- D28 — Labo identique à pve (amende D6 et D13) : tranchée 2026-10-18 par l'admin (« il faudrait que tous les services fonctionnent avec les mêmes IP et conf que sous le pve de l'asso » ; « Tous les services en marche (Recommandé) » ; « Ouvrir une feuille pour l'étudier ») : (1) périmètre = tout invité EN MARCHE sur pve ET présent dans la sauvegarde pCloud : vague 3 = CT 104, 115, 117, 118, 119, 120, 129, 9020 et VM 106, décrits en code et importés sur pve (D26), restaurés dans le labo ; les invités arrêtés et les VM de test restent dehors ; (2) hôte du labo en 10.0.0.10 comme pve (fait 2026-10-18, 10.255.70.2 inchangé) ; (3) CT 254 « box-labo » en 10.0.0.254 dans le labo seulement : DHCP .200-.249, ni DNS ni routage, outil de test hors code (proposé par l'admin ; un réseau KVM du poste en .254 refusé : le Wi-Fi du poste est en 10.0.0.0/24 avec sa box en .254) ; VM 190 « navigateur » (Mint, .181) outil de test hors code ; (4) ce que la sauvegarde ne contient pas (VM 110 FOG, VM 102 poste type, montages liés /tank/miroir-apt, /tank/scripts-http, /tank/partage/Fiches, /tank/iso-netboot) : feuille 5.16, à trancher chiffres en main ; (5) VM 106 hors code, restaurée par qmrestore (l'admin : « Restauration directe, hors code (Recommandé) » ; le provider exige VM.Config.Disk, droit d'écriture que le jeton de CI en lecture seule ne doit pas avoir, D5)

Questions pour l'admin (options, puis recommandation) :
- D3. (a) LXC dédié sur pve : joint l'API 10.0.0.10:8006 directement, tourne sans le poste, mais ajoute un exécuteur de code distant sur l'hyperviseur et une écriture sur pve. (b) runner sur le poste, tunnel `ssh -L 8006` vers pve par l'IP publique : Forgejo est déjà sur le poste, rien de nouveau sur pve, le runner survit à la perte de pve (cohérent avec le PRA), mais le poste doit être allumé et le tunnel dépend de l'accès SSH public. (c) VM/LXC sur un autre hôte : aucun disponible. Recommandation : (b).
- D4. (a) fichier local sur le poste, chiffré par OpenTofu, copié par rsync + pCloud, hors Git. (b) état chiffré versionné dans un dépôt Forgejo privé. (c) backend distant (S3/HTTP) : un service de plus à maintenir. Recommandation : (a), car le runner (D3 b) est sur le poste ; le chiffrement AES-GCM rend (b) possible plus tard.
- D5. (a) un seul utilisateur `tofu@pve`, rôle limité, un jeton. (b) jeton sur `root@pam` pour pouvoir changer features (nesting/keyctl/fuse), au prix d'un jeton tout-puissant en CI. (c) deux jetons : lecture seule pour la CI (plan), écriture limitée (CT sur `tank`, VMID de démonstration) pour le poste ; `features` des CT importés en `ignore_changes`. Recommandation : (c). Aucun accès root@pam pour la CI.
- D6. Cible vue les ressources : T1 = coffre 114, annuaire 108, portail 123, heimdall 121, homarr 128, wiki 100 (identité et accès) ; T2 = demandes 101, sondage 122, VM 106 Snipe-IT, VM 110 fog ; T3 = le reste (minetest 104, freshrss 119, shaarli 120, miroir 115, captures 118, import-fiches 129, provisionnement 117). Les VM de test (102-107, 190-195, 9105) et 256 Go de disques sont exclues. Première répétition : T1 + CT 101 + VM 106 (~35 Go de disque). Recommandation : T1 d'abord, T2 à la 2e répétition, T3 hors périmètre.
- D7. Le coffre est sur pve : sa perte emporte les secrets nécessaires pour restaurer. (a) noyau d'amorçage KeePassXC hors ligne (lot L5 de coffre-mdp, statut non confirmé) contenant phrase GPG, phrase d'état tofu et accès pCloud. (b) en plus, copie papier chez un second détenteur. (c) ne rien changer (risque accepté). Recommandation : (a)+(b) ; sans cela le PRA n'est pas réalisable, et la feuille 4.2 reste en geste humain bloquant.
- D8. Relevé : les deux derniers passages restent en clair sur tank, les `.gpg` existent pour les autres. (a) rapatrier les `.gpg` et déchiffrer au labo avec la phrase du noyau : répète le vrai PRA, nécessite D7. (b) rapatrier le clair : plus simple mais des secrets en clair sur le poste. Recommandation : (a), avec contrôle des `.sha256`.
- D9. (a) dépôt dédié `git/infra-as-code` (secrets de CI limités à ce dépôt, remote propre). (b) sous-dossier de `git/IP` : les workflows et secrets s'appliquent à tout IP, dont beaucoup de fichiers non liés. (c) réutiliser `git/infra-proxmox`. Recommandation : (a). Le remote de IP contient le jeton Forgejo en clair : ne pas le copier.
- D10. Faits à confier : (1) privilèges minimaux d'un jeton pour LXC en PVE 9 ; (2) compatibilité forgejo-runner 13.2.0 avec Forgejo 14.0.3 et action setup-opentofu ; (3) ISO PVE 9.2 (URL, sha256), `pct restore` vers un autre hôte. Recommandation : oui, avant la Porte 1.

## Niveau 1 — Squelette de bout en bout (début de O1) : provider, jeton, import de CT100, plan vide
### Feuille 1.1 — Installer OpenTofu 1.13.1 sur le poste
- preuve : `tofu version` affiche `OpenTofu v1.13.1` ; sha256 de l'archive = celui de la release ; `terraform` v1.13.1 non utilisé
- statut : établi 2026-10-17 (recettes/preuve-1.1.md ; oracle recettes/oracle/1.1-20261017-091507.txt)
- motif : tofu absent du poste (relevé §2)
- source : SOURCES §1 (https://api.github.com/repos/opentofu/opentofu/releases/latest, v1.13.1, 2026-10-01)
- risque : faible
- rôle : producteur
- parallélisable : socle
- nature : fonction
- oracle : `tofu version | grep -q 'v1.13.1'`
- brique : release officielle → binaire dans ~/.local/bin (sans sudo) · dépend de - · réutilise : création : rien d'existant

### Feuille 1.2 — Établir les privilèges minimaux d'un jeton pour gérer des LXC (PVE 9)
- preuve : fiche `sources/privileges-jeton.md` (consultée 2026-10-16, verdict PARTIEL : liste officielle des privilèges et composition des rôles établies, liste minimale pour créer/détruire un LXC « non trouvé ») ; l'ensemble de départ ci-dessous est écrit et sert de point d'entrée aux essais de 3.2
- statut : établi avec réserve 2026-10-17 : fiche PARTIEL sources/privileges-jeton.md + ensemble de départ ; éprouvé en 3.2
- motif : la doc bpg ne donne pas la liste (SOURCES §3 « non trouvé ») ; la fiche confirme que ni PVE ni bpg ne la donnent
- source : sources/privileges-jeton.md (D10, 2026-10-16) ; https://pve.proxmox.com/pve-docs/chapter-pveum.html (privilèges, jetons privsep) ; https://raw.githubusercontent.com/bpg/terraform-provider-proxmox/main/docs/index.md (SDN.Use ou SDN.Audit requis pour voir les ponts)
- ensemble de départ (rôle `TofuCT`, [hypothèse] à éprouver en 3.2) : VM.Allocate, VM.Audit, VM.Config.Disk, VM.Config.CPU, VM.Config.Memory, VM.Config.Network, VM.Config.Options, VM.PowerMgmt (le provider démarre le CT par défaut, `started = true`), SDN.Use, Sys.Audit, Datastore.AllocateSpace, Datastore.Audit. Chemins d'ACL : `/vms/<vmid-demo>`, `/storage/tank` (rootfs) ET `/storage/local` (le template debian-13 est sur `local`), `/sdn/zones/localnetwork`, `/nodes/pve`. Jamais Sys.Modify ni Permissions.Modify (fiche : « to be handled with care »). Les flags de `features` hors nesting, `arch` et les bind mounts exigent root@pam (fiche, § C et D) : le CT de démonstration n'en utilise aucun
- repli : au plus N = 3 essais ; chaque essai ajoute UN seul privilège ou chemin, et consigne dans `recettes/essais-privileges.md` (erreur 403/500 citée, privilège ajouté, date) ; la feuille qui joue les essais est 3.2 (rôle connecteur : elle prépare les commandes `pveum`, l'admin les exécute) ; si le troisième essai échoue : arrêt, retour arrière du rôle, et geste de l'admin daté dans `recettes/essais-privileges.md` : soit amender D5 (création unique du CT de démonstration par un jeton root@pam éphémère, hors CI, révoqué dans l'heure), soit abandonner O2 ; aucun jeton root@pam n'est conservé
- risque : fort
- rôle : chercheur-sources
- parallélisable : socle
- nature : fonction
- brique : doc officielle PVE → fiche de faits datée + ensemble de départ · dépend de - · réutilise : agent chercheur-sources

### Feuille 1.3 — Squelette du code : versions, provider, ignores, verrou
- preuve : `tofu init` exit 0, `tofu fmt -check` exit 0, `tofu validate` exit 0 ; `.terraform.lock.hcl` présent ; `git check-ignore terraform.tfstate .terraform terraform.tfvars` liste les 3 chemins ; `bash tests/scan-secrets.sh` exit 0 sur `tofu/` et `recettes/` (test rouge d'abord : un faux jeton `PVEAPIToken=x@pve!y=00000000-0000-0000-0000-000000000000` placé dans un fichier jetable doit le faire échouer)
- statut : établi 2026-10-17 (recettes/preuve-1.3.md ; oracle recettes/oracle/1.3-20261017-092157.txt)
- motif : aucun code tofu dans IP (relevé §5)
- source : SOURCES §1 (bpg v0.116.1, OpenTofu >= 1.6), §6 (verrou à versionner, `.terraform/` hors Git)
- risque : faible (ligne de risque : bpg 0.116.1 a été publiée la veille, 2026-10-15, et OpenTofu n'est pas dans la matrice de test de bpg [relevé du juge, passage 1] ; version épinglée, `.terraform.lock.hcl` versionné, aucune montée de version sans `tofu plan` vide avant et après)
- rôle : producteur (skill superpowers:test-driven-development pour les contrôles)
- parallélisable :
- nature : fonction
- oracle : `cd tofu && tofu init -backend=false && tofu validate`
- brique : versions épinglées bpg 0.116.1 + tofu ~> 1.13, endpoint en variable, jeton par l'environnement `PROXMOX_VE_API_TOKEN` (jamais dans un fichier versionné) ; `tests/scan-secrets.sh` (motifs : `PVEAPIToken=`, UUID de secret de jeton, `passphrase` suivie d'une valeur, clé privée PEM) rejoué avant chaque commit et sur `recettes/` · dépend de 1.1 · réutilise : création : rien d'existant

### Feuille 1.4 — Créer l'utilisateur tofu-ro@pve, le rôle lecture seule et son jeton privsep=1 (geste sur pve)
- preuve : `ssh pve pveum user token list tofu-ro@pve` liste le jeton avec `privsep` = 1 ; `ssh pve pveum acl list` montre PVEAuditor sur `/` pour l'utilisateur ET pour le jeton `tofu-ro@pve!lecture` (le jeton a sa propre ACL, il n'hérite pas de l'écriture) ; `ssh pve pveum user token permissions tofu-ro@pve lecture` (commande confirmée par `pveum help` avant usage) ne liste que des privilèges *.Audit ; `curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: PVEAPIToken=..." https://127.0.0.1:8006/api2/json/version` renvoie 200 par le tunnel de 1.7 ; POST de test défini : `curl -sk -X POST -H "Authorization: PVEAPIToken=..." https://127.0.0.1:8006/api2/json/nodes/pve/lxc/999999/status/start` (VMID 999999 absent, vérifié par `ssh pve pct status 999999` ≠ 0) doit renvoyer 403 ; une réponse 500 « does not exist » signifie que le jeton peut écrire : NO-GO et retour arrière immédiat ; le secret (affiché une seule fois par pveum) est rangé dans `~/.config/infra-as-code/ro.env` (chmod 600, hors dépôt) et dans le coffre, jamais collé dans `recettes/` : `bash tests/scan-secrets.sh` exit 0 après le geste
- statut : établi 2026-10-17 (recettes/verif-1.4.log ; commit 60dd096)
- motif : seul root@pam existe, aucun jeton (relevé §1) ; l'exemple de la doc bpg crée le jeton avec `--privsep=0` (permissions identiques à l'utilisateur) : refusé ici, privsep=1 et ACL explicite sur le jeton
- source : SOURCES §3 (https://raw.githubusercontent.com/bpg/terraform-provider-proxmox/main/docs/index.md) ; sources/privileges-jeton.md (« Separated privileges are the default for new tokens », permissions effectives = intersection utilisateur et jeton ; PVEAuditor = privilèges *.Audit)
- risque : fort
- rôle : connecteur (prépare les commandes dans recettes/ ; l'admin les exécute, suivant D5)
- parallélisable :
- nature : fonction
- brique : commandes `pveum` prêtes à coller (`user add tofu-ro@pve`, `aclmod / -user tofu-ro@pve -role PVEAuditor`, `user token add tofu-ro@pve lecture --privsep 1`, `aclmod / -token 'tofu-ro@pve!lecture' -role PVEAuditor`), copie de sûreté de /etc/pve/user.cfg avant, retour arrière écrit (`pveum user token remove`, `pveum user delete tofu-ro@pve`) · dépend de 1.2, 1.7, D5 · réutilise : création : rien d'existant

### Feuille 1.5 — Brancher le provider : lecture seule de pve
- preuve : `tofu plan` exit 0 avec un data source en lecture seule qui renvoie le nœud `pve` (nom du data source relevé dans la doc bpg 0.116.1, `tofu version`/`providers` notés), endpoint `https://127.0.0.1:8006` par le tunnel de 1.7 et le réglage TLS retenu en 1.7 ; tunnel coupé, le même plan échoue exit 1 ; aucune ressource gérée
- statut : établi 2026-10-17 (recettes/verif-1.5-1.6-1.7.md, GO)
- motif : jeton et squelette pas encore là
- source : SOURCES §3 (docs/index.md bpg, authentification par jeton, SSH facultatif)
- risque : moyen
- rôle : producteur
- parallélisable :
- nature : fonction
- brique : endpoint + jeton de lecture → `tofu plan` qui lit pve et affiche le nœud · dépend de 1.3, 1.4 et 1.7 · réutilise : création : rien d'existant

### Feuille 1.6 — Importer CT100 (wiki) jusqu'au plan vide
- preuve : avant : `tofu plan` annonce « 1 to import » ; après l'import : `tofu plan -detailed-exitcode` exit 0 ; `ssh pve pct config 100` identique avant/après (diff vide)
- statut : établi 2026-10-17 (recettes/verif-1.5-1.6-1.7.md, GO ; recettes/preuve-1.6-apply.log)
- motif : CT100 hors état tofu
- source : SOURCES §2 (https://opentofu.org/docs/language/import/ ; id `pve/100` ; `-generate-config-out` expérimental) et doc bpg container
- risque : moyen
- rôle : producteur
- parallélisable :
- nature : fonction
- oracle : `cd tofu && tofu plan -detailed-exitcode -input=false; test $? -eq 0`
- brique : bloc `import {}` + `-generate-config-out` relu à la main ; pièges relevé §1 (hwaddr, description %XX, snapshot parent autoup, features : seul `nesting` est modifiable avec un jeton, `keyctl` et `fuse` exigent root@pam (fiche privileges-jeton § D, 2026-10-16) donc `ignore_changes = [features]` borné, password et template_file_id non relisibles) traités par valeurs exactes ou `ignore_changes` borné ; `prevent_destroy = true` ; l'`apply` n'écrit que l'état (retour arrière : `tofu state rm`, pve non touché) · dépend de 1.5 · réutilise : création : rien d'existant

### Feuille 1.7 — Tunnel `ssh -L 8006` et TLS de l'API pve (poste hors LAN)
- preuve : `systemctl --user is-active tunnel-pve` = active ; `ss -ltn | grep 127.0.0.1:8006` non vide ; `curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8006/api2/json/version` répond (401 sans jeton, code ≠ 000) ; l'empreinte `openssl s_client -connect 127.0.0.1:8006 </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256` égale celle lue par `ssh pve openssl x509 -noout -fingerprint -sha256 -in /etc/pve/local/pve-ssl.pem` ; `recettes/tunnel-tls.md` consigne le choix TLS et sa preuve : (a) CA de pve épinglée par `SSL_CERT_FILE` si le nom utilisé figure dans les SAN du certificat (`openssl x509 -text`), sinon (b) `insecure = true` limité à ce tunnel de boucle locale, avec contrôle de l'empreinte rejoué avant chaque plan contre une empreinte de référence stockée dans `~/.config/infra-as-code/pve-tls.fpr` (écrite une seule fois par le compte de l'admin via `ssh pve`, relue sans ssh par les plans et par le runner) ; l'option choisie est justifiée par la lecture des paramètres TLS de la doc bpg ; tunnel interrompu (unité arrêtée), `tofu plan` exit 1, jamais un faux vert
- statut : établi 2026-10-17 (recettes/verif-1.7.md + recettes/verif-1.5-1.6-1.7.md, GO ; recettes/preuve-1.7-tunnel-coupe.log)
- motif : le poste ne voit pas le LAN (relevé §11) et aucune feuille ne créait le tunnel posé par D3 ; le certificat de pve n'est pas reconnu par un client non préparé [hypothèse, mesurée dans cette feuille]
- source : SOURCES §3 (docs/index.md bpg : paramètre `insecure`, à relire ici) ; relevé §1, §3, §11 ; man ssh(1) (`-L`, `ExitOnForwardFailure`, `ServerAliveInterval`)
- risque : moyen
- rôle : producteur
- parallélisable : socle
- nature : fonction
- brique : unité systemd utilisateur du compte de l'admin (pas du runner) `ssh -N -L 127.0.0.1:8006:10.0.0.10:8006 pve` avec `ExitOnForwardFailure=yes`, `ServerAliveInterval=15`, `Restart=on-failure` ; la clé ssh de pve reste au compte de l'admin, le runner (4.5) ne voit que le port local ; rien n'est modifié sur pve ; retour arrière : désactiver l'unité utilisateur et la supprimer · dépend de - · réutilise : accès `ssh pve` existant (relevé §1)

## Niveau 2 — Suite de O1 : CT101, CT122, garde-fou rejouable, recette réelle

### Feuille 2.1 — Importer CT101 (demandes) jusqu'au plan vide
- preuve : `tofu plan -detailed-exitcode` exit 0 avec CT100 et CT101 ; `pct config 101` inchangé (diff vide) ; nameserver 10.0.0.254 et 1 cœur reportés
- statut : établi 2026-10-17 (recettes/verif-2.1-2.3.md, GO ; recettes/preuve-2.1-apply.log)
- motif : CT101 hors état
- source : SOURCES §2 ; relevé §1 (config CT101)
- risque : moyen
- rôle : producteur
- parallélisable : imports
- nature : fonction
- brique : même boucle que 1.6, spécifique : nameserver, 1 cœur · dépend de 1.6 · réutilise : le code de 1.6

### Feuille 2.2 — Importer CT122 (sondage, Pollaris) jusqu'au plan vide
- preuve : `tofu plan -detailed-exitcode` exit 0 avec les 3 CT ; `pct config 122` inchangé ; aucun fichier de secret Pollaris dans le dépôt (`git grep -il pollaris | xargs grep -il password` vide)
- statut : établi 2026-10-17 (recettes/verif-2.1-2.3.md, GO ; recettes/preuve-2.2-apply.log)
- motif : CT122 hors état ; il porte des données réelles, il ne doit jamais être recréé
- source : SOURCES §2 ; relevé §1 (CT122 : 2 cœurs, 2048 Mo, 12G)
- risque : moyen
- rôle : producteur
- parallélisable : imports
- nature : fonction
- brique : même boucle que 1.6 ; `prevent_destroy` et `ignore_changes` bornés · dépend de 1.6 · réutilise : le code de 1.6

### Feuille 2.3 — Script de contrôle `verifier.sh` (équivalent de `--check`)
- preuve : `tests/run.sh` : test rouge d'abord (dérive simulée = exit 2 attendu), puis vert ; `verifier.sh` exit 0 sur la prod après 2.1 et 2.2
- statut : établi 2026-10-17 (recettes/verif-2.1-2.3.md, GO ; oracle recettes/oracle/2.3-20261017-112540.txt)
- motif : pas de script
- source : motif interne annuaire/acces.yaml + matrice-acces.py (`--valider`, `--check`) ; SOURCES §6 ; code `plan -detailed-exitcode` : 0, 1 erreur, 2 changements
- risque : faible
- rôle : producteur (skill superpowers:test-driven-development)
- parallélisable :
- nature : fonction
- oracle : `bash tests/run.sh`
- brique : `fmt -check` + `validate` (statique, sans réseau) puis `plan -detailed-exitcode` (réseau) · dépend de 2.1 et 2.2 · réutilise : motif porte-authelia ; style parc-as-code/tests/run.sh

### Feuille 2.4 — Recette réelle de O1 : plan vide après une vraie vie du système
- preuve : `verifier.sh` exit 0 le jour de l'import ET après le passage suivant des timers `maj-securite-invites` (journal `ssh pve journalctl -u 'maj-securite*' --since ...` cité avec date) ET après la sauvegarde hebdomadaire du dimanche (`proxmox/sauvegarde/sauvegarde-hebdo.sh`, snapshots vzdump ; journal cité avec date) ; si `reboot-si-besoin.sh` a redémarré pve entre-temps (`ssh pve uptime -s` comparé), le noter ; sortie collée
- statut : manque : attend le passage des timers maj-securite et la sauvegarde du dimanche 2026-10-18 02:00 (point de reprise dans ETAT.md)
- motif : l'état vierge ne prouve pas la robustesse aux snapshots autoup-* ; préalables nommés : les reboots automatiques (`proxmox/maintenance/reboot-si-besoin.sh`) et le vzdump du dimanche modifient l'état des CT
- source : relevé §1 (snapshots autoup-* hors gestion tofu), §6
- risque : moyen
- rôle : verificateur
- parallélisable :
- nature : recette-réelle
- brique : verifier.sh + journal des timers + journal de la sauvegarde du dimanche → verdict GO/NO-GO daté · dépend de 2.3 · réutilise : agent verificateur

## Niveau 3 — O2 : CT jetable de démonstration, détruit puis recréé

### Feuille 3.1 — Choisir un VMID et une IP libres (sonde en lecture seule)
- preuve : `recettes/choix-ct-demo.md` : VMID absent de `pct list`, `qm list` et `/etc/pve/nodes/pve/*/` ; IP ne répond à aucun `ssh pve ping -c1 -W1 <ip>` ni `arping` ; plage DHCP de la box notée comme inconnue si non lue
- statut : établi 2026-10-17 (recettes/choix-ct-demo.md ; juge Opus GO avec réserves : recettes/verif-3.1-3.3.md)
- motif : relevé : 9020 et 9121 déjà pris ; plage DHCP de la box non relevée
- source : relevé §6 (inventaire VMID et IP .10 à .37, .199)
- risque : faible
- rôle : connecteur
- parallélisable :
- nature : fonction
- brique : sondes ssh → VMID et IP choisis hors plage 9xxx déjà utilisée et hors .14-.37 · dépend de 1.5 · réutilise : création : rien d'existant

### Feuille 3.2 — Créer le jeton d'écriture limité tofu-rw@pve (geste sur pve)
- preuve : `ssh pve pveum acl list` montre le rôle `TofuCT` (ensemble de départ de 1.2) attribué à l'utilisateur `tofu-rw@pve` ET au jeton `tofu-rw@pve!ecriture` (privsep = 1) uniquement sur `/vms/<vmid>` (VMID de 3.1), `/storage/tank`, `/storage/local`, `/sdn/zones/localnetwork`, `/nodes/pve` ; POST de test du rw sur CT100 : `curl -sk -X POST -H "Authorization: PVEAPIToken=tofu-rw@pve!ecriture=..." https://127.0.0.1:8006/api2/json/nodes/pve/lxc/100/status/start` renvoie 403 (CT100 déjà démarré : inoffensif) ; le POST de test du jeton de lecture de 1.4 reste 403 ; essais selon le repli de 1.2 : au plus 3, journalisés dans `recettes/essais-privileges.md`, au troisième échec arrêt et geste de l'admin daté ; le secret est rangé dans `~/.config/infra-as-code/rw.env` (chmod 600, hors dépôt) et dans le coffre, jamais dans `recettes/` : `bash tests/scan-secrets.sh` exit 0
- statut : préparée 2026-10-17 (recettes/geste-3.2-fred.md, verif-3.2.sh) : attend le geste de l'admin
- motif : un jeton d'écriture n'existe pas
- source : SOURCES §3 (docs/index.md : « Not all Proxmox API operations are supported via API Token » ; privilèges PVE 9 changés) ; sources/privileges-jeton.md ; ensemble de départ et repli de la feuille 1.2
- risque : fort
- rôle : connecteur (suivant D5 ; prépare les commandes, l'admin exécute chaque essai)
- parallélisable :
- nature : fonction
- brique : commandes `pveum` prêtes (`role add TofuCT -privs ...`, `user add tofu-rw@pve`, `user token add tofu-rw@pve ecriture --privsep 1`, ACL utilisateur et jeton) + retour arrière (révocation du jeton, suppression de l'utilisateur et du rôle) + copie de /etc/pve/user.cfg avant · dépend de 1.4, 1.2, 3.1, D5 · réutilise : création : rien d'existant

### Feuille 3.3 — Code du CT jetable et plan « 1 to add »
- preuve : `tofu plan` annonce `Plan: 1 to add, 0 to change` sans aucune suppression ; `tofu show -json <plan> | jq` montre `unprivileged` = true et `started` = true ; `verifier.sh` n'est pas modifié dans son comportement sur les 3 CT
- statut : établi 2026-10-17 (recettes/preuve-3.3.md ; juge Opus GO : recettes/verif-3.1-3.3.md)
- motif : pas de ressource de démonstration ; `unprivileged` vaut false par défaut dans bpg, il est donc écrit explicitement
- source : SOURCES §2 (doc bpg container : template_file_id, clone, tags minuscules) ; relevé §1 (templates debian-13 sur `local`, `tank` pour rootfs, `local-lvm` plein à ne pas utiliser)
- risque : faible
- rôle : producteur
- parallélisable :
- nature : fonction
- brique : ressource LXC `unprivileged = true`, debian-13, rootfs `tank` 4G, 1 cœur, 256 Mo, tag `tofu-demo`, aucun secret, SANS `prevent_destroy` (sinon 3.5 serait refusée) · dépend de 3.1 et 2.3 · réutilise : le squelette de 1.3

### Feuille 3.4 — Créer le CT jetable par `tofu apply` (écriture sur pve)
- preuve : `ssh pve pct status <vmid>` = running ; `ssh pve pct config <vmid>` contient `unprivileged: 1` ; `tofu plan -detailed-exitcode` exit 0 ; `pct list` montre CT100, 101, 122 inchangés (même état et même uptime ≥ avant)
- statut : établi avec réserve 2026-10-17 (recettes/preuve-3.4-apply.log ; juge recettes/verif-3.4-3.6.md, passages 1 et 2 ; CT 130 détruit ensuite à la demande de l'admin)
- motif : première création par le code
- source : SOURCES §2 et §3 ; doc bpg container 0.116.1
- risque : fort
- rôle : connecteur
- parallélisable :
- nature : fonction
- brique : jeton d'écriture de 3.2 + plan de 3.3 relu → CT en service ; retour arrière : le destroy ciblé de 3.5 · dépend de 3.2 et 3.3 · réutilise : le code de 3.3

### Feuille 3.5 — Détruire le CT jetable (destruction ciblée)
- preuve : avant : `cat tofu/*.tf | grep -c 'prevent_destroy = true'` compte (tous fichiers confondus) les blocs des CT 100, 101 et 122 (3 attendus) et le bloc du CT de démonstration n'en porte pas ; `tofu plan -destroy -target=proxmox_virtual_environment_container.<nom-demo>` (adresse de la ressource ENTIÈRE, sans index ni attribut) ne liste que la ressource de démonstration ; après : `tofu apply -destroy -target=<même adresse>`, `ssh pve test ! -e /etc/pve/lxc/<vmid>.conf` ; `pct list` montre toujours 100, 101, 122 ; `tofu destroy` global jamais lancé (il serait refusé par `prevent_destroy`) ; oracle sur le plan JSON : `tofu plan -destroy -target=<adresse> -out=p && tofu show -json p | jq -e '[.resource_changes[] | select(.change.actions | index("delete") or index("replace")) | .address] == ["<adresse du CT de démo>"]'` (aucune action delete ou replace hors de l'adresse du CT de démo, y compris les CT 100, 101, 122) ; `git diff` avant chaque apply : aucun bloc de CT 100/101/122 retiré du code
- statut : établi avec réserve 2026-10-17 (recettes/preuve-3.5-destroy.log, preuve-3.6bis-code-constant.log ; juge recettes/verif-3.4-3.6.md ; réserve : marqueur, citation de l'admin absente du log bis)
- motif : tranché en D2 ; la destruction est irréversible pour le CT lui-même. Piège : retirer un bloc de ressource fait tomber son `prevent_destroy` (le plan détruirait alors le CT) ; la doc réserve `-target` aux circonstances exceptionnelles et aux adresses de ressource entière : usage assumé ici pour ce seul CT sans donnée
- source : sources/destroy-et-jeton-forgejo.md F1 à F5 (2026-10-16) ; https://opentofu.org/docs/cli/commands/plan/ ; https://opentofu.org/docs/language/resources/behavior/ (prevent_destroy) ; le numéro 1.13 n'est pas affiché dans les pages rendues [hypothèse : page courante]
- risque : fort
- rôle : connecteur
- parallélisable :
- nature : fonction
- brique : plan de destruction relu, CT sans donnée, retour arrière = recréation par 3.6 ; `prevent_destroy = true` posé sur les CT importés 100, 101, 122 (feuilles 1.6, 2.1, 2.2) et maintenu · dépend de 3.4 · réutilise : création : rien d'existant

### Feuille 3.6 — Recréer le CT jetable et prouver l'identité
- preuve : `tofu apply` crée 1 ressource ; `tofu plan -detailed-exitcode` exit 0 ; `ssh pve pct config <vmid>` identique à l'avant-destruction hors hwaddr (diff collé)
- statut : établi 2026-10-17 (cycle à code constant recettes/preuve-3.6bis-code-constant.log ; juge recettes/verif-3.4-3.6.md, passage 2, recettes/verif-3.4-3.6/passage2/rejoue.out)
- motif : le cycle suppression puis recréation n a jamais été joué
- source : SOURCES §2 ; objectif O2 (D2)
- risque : fort
- rôle : verificateur
- parallélisable :
- nature : recette-réelle
- brique : code de 3.3 seul → même CT recréé · dépend de 3.5 ET du second geste de 3.2 (ACL `/vms/130` re-posées, `verif-3.2.sh --apres-destruction` exit 0) · réutilise : le code de 3.3

## Niveau 4 — O3 : état chiffré (phrase au coffre) et plan automatique en CI Forgejo

### Feuille 4.0 — Constat : le noyau d'amorçage L5 existe (copie unique + Vaultwarden, acceptée avec réserve : D22, D24)
- preuve : l'admin indique le chemin de l'exemplaire unique du `.kdbx` sur le poste ; `test -s <noyau>` ; `sha256sum <noyau>` noté dans `recettes/constat-4.0.md` ; `file <noyau>` contient « Keepass password database 2.x » ; `git ls-files '*.kdbx'` vide dans tous les dépôts du poste ; attestation écrite et datée de l'admin dans le même fichier : (1) les entrées du noyau existent aussi dans Vaultwarden (CT 114), titres seulement ; (2) réserve D22 acceptée : perte du poste = perte du noyau, et Vaultwarden vit sur pve, donc il manque dans un vrai PRA ; le contenu n'est jamais ouvert ni affiché par la feuille ; la duplication sur deux supports chez deux détenteurs (D7) est reportée (D22), hors de cet arbre
- statut : ÉTABLIE 2026-10-18 avec réserves (juge sonnet GO avec réserves : recettes/verif-4.0-5.0-5.1-juge.md ; constat recettes/constat-4.0.md) ; exemplaire unique ~/noyau-amorcage-ip/noyau-amorcage-ip.kdbx (sha256 afba0598…, KDBX 2.x), aucun .kdbx suivi dans 44 dépôts ; attestation de l'admin « Oui, toutes » (Vaultwarden) ; réserve D22 tranchée D24 (4) ; empreinte valable à 08:46, la base évolue
- motif : D22 (2026-10-17) reporte la duplication sur clés USB ; D24 (4) accepte l'exemplaire unique plus Vaultwarden, avec réserve écrite, pour que 4.0 puis 5.0 puissent passer ; le noyau a été rempli le 2026-10-17 (D22)
- source : coffre-mdp/STATUS.md ; coffre-mdp/L5-noyau-amorcage.md ; coffre-mdp/creer-noyau-amorcage.sh ; D22, D24
- risque : moyen
- rôle : connecteur (constat en lecture ; rend la main à l'admin si rouge)
- parallélisable : ci
- nature : fonction
- brique : cas : (a) exemplaire présent, empreinte notée, attestation avec réserve signée → vert avec réserve, 4.2 et 5.0 débloquées ; (b) exemplaire absent ou attestation refusée → rouge, 5.0 à 5.12b restent à l'arrêt, seules les feuilles sans secret avancent · dépend de D12, D22 et D24 · réutilise : agent coffre-noyau-amorcage (procédure)

### Feuille 4.1 — Établir les faits de la CI (runner, setup-opentofu, secrets, montée de Forgejo)
- preuve : fiche `sources/ci-forgejo.md` complétée : (1) le couple runner ↔ Forgejo 15.0 (notes de version 15.0 et du runner), sinon « non trouvé » daté ; (2) usage de setup-opentofu sur Forgejo ; (3) chemin des secrets de dépôt ; plus la fiche `sources/destroy-et-jeton-forgejo.md` F6 à F8 (portée de jeton, enregistrement du runner, montée 14 → 15 et sauvegarde `forgejo dump`) déjà livrée le 2026-10-16
- statut : manque (fiche ci-forgejo PARTIEL livrée 2026-10-16 ; compatibilité 13.2.0 / 14.0.3 « non trouvé » ; Forgejo 14.0 fin de vie 2026-04-30, 15.0 LTS jusqu'au 2027-07-15 d'après le release-schedule lu par le juge le 2026-10-16 ; D11 : montée en 15.0 décidée)
- motif : SOURCES §5 : action non vérifiée sur Forgejo, UI des secrets non documentée ; aucune déclaration officielle de compatibilité du runner
- source : sources/ci-forgejo.md ; sources/destroy-et-jeton-forgejo.md ; https://forgejo.org/docs/v15.0/admin/actions/runner-installation/ et https://code.forgejo.org/forgejo/runner/releases
- repli : la compatibilité se prouve par l'essai en 4.5 (workflow `echo ok` en `success`) avec au plus N = 2 versions de runner (13.2.0, puis la dernière stable), journalisées ; échec des deux : arrêt et geste de l'admin ; pour tofu, binaire téléchargé en ligne de workflow avec contrôle sha256 sans action tierce (attribué à 4.7)
- risque : fort
- rôle : chercheur-sources
- parallélisable : ci
- nature : fonction
- brique : docs officielles → fiche de faits datée · dépend de - · réutilise : agent chercheur-sources

### Feuille 4.9 — Monter le Forgejo local de 14.0.3 à 15.0 LTS (D11), avant le runner
- preuve : avant : `forgejo --version` = 14.0.3 ; sauvegarde complète `forgejo dump` (zip, taille et sha256 notés, `unzip -t` vert) faite instance arrêtée, plus copie du binaire 14.0.3 et de `/etc/forgejo/app.ini` hors du dossier de données ; retour arrière testé à sec : le dump restauré dans un dossier jetable démarre Forgejo 14.0.3 sur un port libre (3001) avec une page d'accueil 200 ; après : `forgejo --version` = 15.0.x, `curl -s localhost:3000/api/v1/version` 200, nombre de dépôts identique avant/après (`/api/v1/repos/search`), `git ls-remote` sur `git/IP` réussit ; chaque rupture de 15.0 (nom des cookies : reconnexion de tous, portées des jetons, option `ADD_CO_COMMITTER_TRAILERS` supprimée) cochée applicable ou non dans `recettes/forgejo-15.md` ; état du jeton `FORGEJO_TOKEN` du poste vérifié après la montée
- statut : établi avec réserves 2026-10-17 (recettes/verif-4.9.md, preuve-4.9.md)
- motif : D11 (2026-10-16) : Forgejo 14.0 est hors support (fin 2026-04-30) ; le runner ne doit pas être branché sur une version sans correctifs
- source : sources/destroy-et-jeton-forgejo.md F8 (https://forgejo.org/docs/v15.0/admin/upgrade/ ; notes https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/release-notes-published/15.0.0.md) ; étapes spécifiques 14 → 15 « non trouvées » dans la fiche (fin des notes non lue)
- risque : fort
- rôle : connecteur (l'admin valide l'arrêt du service, qui coupe le Git local quelques minutes)
- parallélisable : ci
- nature : fonction
- brique : arrêt, dump, remplacement du binaire natif, démarrage ; retour arrière = binaire 14.0.3 + restauration du dump (la base migre, le binaire seul ne suffit pas) · dépend de 4.1 · réutilise : création : rien d'existant

### Feuille 4.2 — Geste humain : ranger la phrase d'état dans le noyau L5 (D7, D12)
- preuve : l'admin confirme par écrit daté que la phrase (≥ 32 caractères, générée hors dépôt) est dans le noyau d'amorçage hors ligne ET dans le coffre, et que les DEUX copies du `.kdbx` ont été resynchronisées (`sha256sum` des deux copies identiques de nouveau) ; `git grep` de la phrase = vide. Cas par réponse : (a) rangée et copies identiques → vert ; (b) rangée dans une seule copie → rouge, resynchroniser ; (c) non rangée → arrêt, 4.3 reste bloquée ; puis rejouer le contrôle de 4.8 sur l'état chiffré (`grep -c encrypted_data` > 0, sha256 inchangé après un push CI) — report accepté par l'admin le 2026-10-17
- statut : ÉTABLIE 2026-10-17 avec réserve (juge : NO-GO à la lettre, recettes/verif-4.2-4.3-juge.md ; l'admin le 2026-10-17 « Accepter : noyau + coffre ») : phrase de 40 caractères dans le noyau (un exemplaire, D22) ET dans le Vaultwarden ; copie USB du noyau reportée (4.0 ouverte) ; contrôle 4.8 rejoué sur l'état chiffré : run 11 success
- motif : sans clé l'état est perdu (SOURCES §4 : « unrecoverable without the appropriate encryption key ») ; le noyau lui-même est créé hors projet (D12), constat en 4.0
- source : SOURCES §4 (https://opentofu.org/docs/language/state/encryption/) ; coffre-mdp/L5-noyau-amorcage.md
- risque : moyen
- rôle : connecteur (rend la main à l'admin)
- parallélisable : ci
- nature : fonction
- brique : phrase générée localement → deux emplacements confirmés · dépend de 4.0 et D7 · réutilise : agent coffre-noyau-amorcage (procédure)

### Feuille 4.3 — Chiffrer l'état (PBKDF2 + AES-GCM) avec migration, chemin unique `etat/pve.tfstate`
- preuve : copie de l'état clair sauvegardée avant (hors dépôt, chmod 600) ; le backend local est fixé à `etat/pve.tfstate` (dossier `tofu/etat/` ignoré par Git : `git check-ignore tofu/etat/pve.tfstate`), migration par `tofu init -migrate-state` ; après : `grep -c encrypted_data tofu/etat/pve.tfstate` ≥ 1 et `grep -c proxmox_virtual_environment tofu/etat/pve.tfstate` = 0 ; `tofu plan -detailed-exitcode` exit 0 avec la phrase, exit ≠ 0 sans ; `bash tests/run.sh` et `verifier.sh` rejoués après le déplacement : exit 0 ; ce nom (`etat/pve.tfstate`) est le seul utilisé ensuite par 4.4, 4.7, 4.8, 5.6
- statut : ÉTABLIE 2026-10-17 avec réserves (juge GO : recettes/verif-4.2-4.3-juge.md ; contradicteur passage 2 GO) ; état chiffré tofu/etat/pve.tfstate (P1 à P7 verts), CI sur copie chiffrée ; réserves : 3 plan-*.tfplan en clair dans recettes/, sauvegarde en clair jusqu'au 2026-11-16, M1 à M3 ouvertes
- motif : l'état est en clair par défaut ; un nom d'état différent selon les feuilles (terraform.tfstate, etat/pve.tfstate) cassait les scripts et la CI
- source : SOURCES §4 (bloc `key_provider "pbkdf2"`, `method "aes_gcm"`, `fallback` + `unencrypted` pour migrer, `enforced`)
- risque : moyen
- rôle : producteur
- parallélisable :
- nature : fonction
- oracle : `cd tofu && test -s etat/pve.tfstate && ! grep -q '"type": "proxmox_virtual_environment' etat/pve.tfstate`
- brique : phrase par variable d'environnement, jamais en fichier versionné ; retour arrière = état clair sauvegardé + fallback · dépend de 4.2 et 3.6 · réutilise : création : rien d'existant

### Feuille 4.4 — Sauvegarde et restauration de l'état chiffré (suivant D4)
- preuve : `sauvegarde-etat.sh` copie `tofu/etat/pve.tfstate` (chiffré) + sha256 vers la destination de D4 ; restauration dans un dossier jetable puis `tofu plan -detailed-exitcode` exit 0 ; test bash vert dans `tests/run.sh`
- statut : manque
- motif : l'état est un point unique sur le poste
- source : SOURCES §6 (backend local par défaut, `.terraform/` hors Git) ; relevé §9 (Forgejo et runner hors pve)
- risque : moyen
- rôle : producteur
- parallélisable :
- nature : fonction
- brique : état chiffré → copie vérifiée et restaurable · dépend de 4.3, D4 · réutilise : style de tests de 2.3

### Feuille 4.10 — Créer le dépôt privé git/infra-as-code sur Forgejo et y pousser le squelette (D9)
- preuve : dépôt `git/infra-as-code` créé par l'API de l'instance locale (jeton `FORGEJO_TOKEN` du `~/.bashrc`, jamais affiché ; propriétaire `git` vérifié par `GET /api/v1/users/git`) : `GET /api/v1/repos/git/infra-as-code` renvoie `private` = true et `has_pull_requests` = false (réglé par PATCH) ; forks : `GET /api/v1/repos/git/infra-as-code/forks` vide et dépôt privé (pas de fork par un tiers) ; le réglage exact « forks interdits » est lu dans le swagger de l'instance (`/api/swagger`) avant usage [hypothèse] ; repli si aucun réglage n'existe : dépôt privé + `forks` vide vérifié, noté dans `recettes/forks.md` ; push par clé ssh : `git remote -v` ne contient aucun jeton (`grep -c 'token'` = 0), `git ls-remote origin` réussit ; `bash tests/scan-secrets.sh` exit 0 AVANT le push ; le squelette de 1.3 (et ses tests) est visible sur le dépôt distant
- statut : établi avec réserve 2026-10-17 (push par jeton en env, accepté par l'admin ; recettes/verif-4.10.md, preuve-4.10.md)
- motif : aucune feuille ne créait le dépôt dédié décidé en D9 ; le runner (4.5) est enregistré à la portée de ce seul dépôt
- source : API de l'instance Forgejo 15 locale (`/api/swagger`, à lire dans cette feuille) ; fiche F6 du dossier sources/ (portées de jeton Forgejo) ; relevé §3
- risque : moyen
- rôle : connecteur
- parallélisable : ci
- nature : fonction
- brique : API Forgejo + clé ssh de l'admin → dépôt privé avec le code ; retour arrière : supprimer le dépôt distant (aucune donnée de production) et retirer le remote · dépend de 4.9, 1.3 et D9 · réutilise : création : rien d'existant

### Feuille 4.5 — Mettre le runner en service sur le poste, isolé (suivant D3)
- preuve : `forgejo-runner --version` ; isolation : `id forgejo-runner` montre un utilisateur dédié hors des groupes docker et sudo, `sudo -l -U forgejo-runner` vide, `sudo -u forgejo-runner ls ~fred/.ssh` refusé, `sudo -u forgejo-runner test -r /var/run/docker.sock` échoue, unité systemd avec `ProtectHome=yes`, `NoNewPrivileges=yes`, `PrivateTmp=yes` (relues par `systemd-analyze security`) ; le runner est enregistré à la portée du seul dépôt `git/infra-as-code` (pas de portée instance), avec un label d'exécution directe `host` borné (syntaxe lue dans la doc de configuration et confirmée par `forgejo-runner --help`) ; le dépôt est privé, les forks et `pull_request` sont inactifs ; un workflow `echo ok` de test réussit (statut `success` via `/api/v1/repos/.../actions/tasks`) ; retour arrière écrit et testé à sec : désenregistrement, arrêt et suppression de l'unité, suppression de l'utilisateur ; essais de version de runner selon le repli de 4.1 (N = 2, journalisés)
- statut : ÉTABLIE 2026-10-17 avec réserves (juge GO : recettes/verif-4.5-juge.md) ; runner v13.2.0 actif, workflow 820c6c9 success, retour arrière à sec sur l'état installé (recettes/preuve-4.5-retour-a-sec.log) ; réserves : 1 seul essai de version (réussi), retour réel non exécuté ; script recettes/runner-4.5.sh
- motif : aucun runner (relevé §3) ; le runner exécute du code distant (SOURCES §5) sur le poste qui porte la clé ssh de pve et le jeton Forgejo : donc compte dédié, aucun accès aux clés de l'admin
- source : SOURCES §5 (https://forgejo.org/docs/latest/admin/actions/runner-installation/ : « Forgejo Runner performs remote code execution » ; v13.2.0) ; sources/ci-forgejo.md ; sources/destroy-et-jeton-forgejo.md F7 (enregistrement par l'interface `/{owner}/{repo}/settings/actions/runners` ou `forgejo forgejo-cli actions register`)
- risque : fort
- rôle : connecteur
- parallélisable :
- nature : fonction
- brique : binaire + enregistrement + label ; l'accès à l'API pve passe par le port local 127.0.0.1:8006 du tunnel de 1.7 (tenu par le compte de l'admin, le runner ne détient pas la clé ssh) · dépend de 4.1, 4.9, 4.10, 1.7 et D3 · réutilise : création : rien d'existant

### Feuille 4.6 — Jetons et secrets de CI (création de jeton)
- preuve : le jeton Forgejo de portée `read:repository` seule [estimation, fiche F6] n'est créé QUE si, à la demande de 4.7 (qui porte le repli « checkout KO → jeton » et note l'essai dans `recettes/ci-checkout.md`), l'étape de récupération du dépôt échoue avec le jeton automatique de la tâche ; 4.6 ne dépend pas de 4.7 ; sa seule utilisation est cette étape de `git clone` (secret `FORGEJO_READ`), il est listé par l'API sans afficher sa valeur ; sinon aucun jeton n'est créé et la ligne est close « sans objet » ; secrets de dépôt `TOFU_ENC_PASSPHRASE` et `PVE_TOKEN_RO` présents (jamais affichés) ; le runner est enregistré par l'interface admin ou `forgejo forgejo-cli actions register` (aucun jeton d'API nécessaire, fiche F7) ; le remote local ne contient plus de jeton (`git remote -v | grep -c '@'` = 0, authentification par clé ssh ou assistant d'identifiants) ; `bash tests/scan-secrets.sh` exit 0 ; retour arrière : révocation du jeton et suppression des secrets
- statut : ÉTABLIE 2026-10-17 avec réserves (juge GO : recettes/verif-4.6-4.7-juge.md) ; PVE_TOKEN_RO posé ; FORGEJO_READ sans objet (checkout par jeton de tâche OK) ; TOFU_ENC_PASSPHRASE reportée à 4.2 ; retour arrière non exécuté
- motif : l'URL du remote de IP contient le jeton Forgejo (relevé §3)
- source : sources/destroy-et-jeton-forgejo.md F6 et F7 (https://forgejo.org/docs/v15.0/user/token-scope/ ; https://forgejo.org/docs/v15.0/admin/actions/registration/) ; SOURCES §5 (contexte `secrets` = secrets du dépôt, vide pour les PR de fork) ; relevé §3
- risque : fort
- rôle : connecteur (geste de l'admin pour l'interface si l'API ne suffit pas)
- parallélisable :
- nature : fonction
- brique : jeton de lecture pve de 1.4 + phrase de 4.2 → secrets du dépôt de D9 · dépend de 4.5, 4.2, 1.4 et D9 · réutilise : création : rien d'existant

### Feuille 4.7 — Workflow `tofu-plan.yml` à chaque push
- preuve : fichier `.forgejo/workflows/tofu-plan.yml` avec `runs-on` = le label `host` de 4.5, déclencheur `push` seul (aucun `pull_request`) ; étapes `fmt -check`, `validate`, `plan -detailed-exitcode -input=false -lock=false` ; le job échoue si exit 1 ou 2 ; le plan passe par `./tofu-cible.sh pve plan -detailed-exitcode …` (si 5.6 n'est pas encore faite, 4.7 crée le script à une seule cible `pve` et 5.6 l'étend à `labo`) ; une étape d'empreinte TLS lit `pve-tls.fpr` (1.7) et la passe au provider ; lecture seule de l'état : une étape copie `$TOFU_ETAT_CI/pve.tfstate` dans `tofu/etat/pve.tfstate` de l'espace de travail ; `TOFU_ETAT_CI` = `/srv/infra-as-code/etat-ci/`, dossier de mode 750 appartenant à l'admin avec le groupe `forgejo-runner`, fichiers en 640 (`stat -c '%a %U:%G'` noté), l'empreinte TLS de référence `pve-tls.fpr` (1.7) y est publiée aussi, le runner ne lisant jamais `~fred` et la phrase vient du secret de 4.6, le plan n'écrit jamais l'état maître ; `publier-etat-ci.sh` (test dans `tests/run.sh`) copie `etat/pve.tfstate` (chiffré) avec son sha256 vers `$TOFU_ETAT_CI` après chaque `tofu apply` ; une copie périmée donne un rouge (sens sûr), jamais un faux vert ; aucune valeur de secret dans le journal (`grep` du journal de tâche sur le motif du jeton = vide)
- statut : ÉTABLIE 2026-10-17 avec réserves (recettes/verif-4.6-4.7-juge.md ; reports acceptés par l'admin : tofu-cible.sh -> 5.6, empreinte remplacée par la CA (SSL_CERT_FILE) ; détail : ARBRE-historique.md § 4.7)
- motif : aucun workflow (relevé §3) ; sans accès à l'état local chiffré le plan de la CI verrait tout à créer (exit 2)
- source : SOURCES §5 (https://forgejo.org/docs/latest/user/actions/reference/ : `uses:` en URL complète) + fiche de 4.1 ; sources/ci-forgejo.md
- risque : moyen
- rôle : producteur
- parallélisable :
- nature : fonction
- brique : verifier.sh de 2.3 + secrets de 4.6 + tunnel de 1.7 → job de CI ; tofu installé par téléchargement de la release avec contrôle sha256 (repli de 4.1), ou `uses: https://github.com/opentofu/setup-opentofu@v2` après un essai · repli de l'étape de récupération du dépôt : checkout KO avec le jeton automatique → jeton `FORGEJO_READ` de 4.6 (c'est 4.7 qui porte ce repli, 4.6 ne porte que les secrets) · dépend de 4.6, 4.10, 2.3 et 4.4 · réutilise : verifier.sh, tofu-cible.sh

### Feuille 4.8 — Recette réelle de O3 : vert propre, rouge sur dérive
- preuve : hors créneau de la sauvegarde hebdomadaire du dimanche (`sauvegarde-hebdo.sh`) et vérification qu'aucun `reboot-si-besoin.sh` n'est imminent (`ssh pve systemctl list-timers`) ; push propre → tâche `success` ; push d'une branche avec une dérive volontaire dans le code (pas dans pve) → tâche `failure` avec exit 2 ; état maître toujours chiffré et de sha256 inchangé après les deux (`grep -c encrypted_data`) ; copie CI volontairement périmée → `failure`
- statut : ÉTABLIE 2026-10-17 avec réserves (juge : recettes/verif-4.8-juge.md ; report « état maître chiffré » vers 4.2 accepté par l'admin le 2026-10-17) ; tâches 149/150 success, 146 failure (dérive code, branche essai-derive-4.8), 147 failure (copie périmée) ; état maître sha256 inchangé ; créneau rejoué dans recettes/preuve-4.8.log
- motif : jamais joué
- source : relevé §3 ; SOURCES §5
- risque : moyen
- rôle : verificateur
- parallélisable :
- nature : recette-réelle
- brique : push → verdict GO/NO-GO daté · dépend de 4.7 et 4.4 · réutilise : agent verificateur

## Niveau 5 — O4 : PRA vers un Proxmox imbriqué sur le poste (à dérouler en plusieurs vagues)

### Feuille 5.0 — Constat : le noyau L5 contient ce qu'exige le PRA (dépendance externe, D12, D24)
- preuve : le constat de 4.0 (daté de moins de 90 jours, sinon refait) est vert avec sa réserve D22 ; l'admin exécute lui-même `keepassxc-cli ls <noyau.kdbx>` et ne communique que les TITRES des entrées (jamais les valeurs) : phrase GPG des sauvegardes, accès pCloud, phrase d'état tofu (la même chiffre `etat/pve.tfstate` et `etat/labo.tfstate`, D24 (3)) ; attestation datée dans `recettes/constat-5.0.md`, réserve recopiée : exemplaire unique sur le poste, aussi dans Vaultwarden (D22, D24 (4))
- statut : ÉTABLIE 2026-10-18 avec réserves (même rapport ; constat recettes/constat-5.0.md) ; titres phrase GPG, accès pCloud et phrase d'état présents (liste collée par l'admin) ; réserves : contenu de la phrase GPG testé seulement en 5.12b, sortie réelle de noyau-remplir.sh non archivée, exemplaire unique (D22)
- motif : D7 et D12 : sans la phrase GPG hors de pve, les `.gpg` de pCloud ne se déchiffrent pas ; D24 (1) : le déchiffrement a lieu sur le poste, là où vit le noyau, la clé ne quitte pas le poste
- source : coffre-mdp/L5-noyau-amorcage.md ; feuille 4.0 ; D22, D24
- risque : moyen
- rôle : connecteur (constat ; rend la main à l'admin si rouge)
- parallélisable : pra
- nature : fonction
- brique : titres d'entrées + constat 4.0 → feu vert pour déchiffrer sur le poste (5.12b) ; rouge = 5.13, 5.3, 5.12b et 5.8 à 5.10 restent à l'arrêt · dépend de 4.0, D12 et D24 · réutilise : agent coffre-noyau-amorcage

### Feuille 5.1 — Établir les faits du PRA (ISO, restauration croisée)
- preuve : fiche `sources/pra-faits.md` (2026-10-16) : URL et sha256 de l'ISO PVE (9.2-1, sha256 4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c) ; options de `pct restore` (--storage, --net0, --force, --unique, --rootfs, --unprivileged) ; sinon « non trouvé » daté
- statut : ÉTABLIE 2026-10-18 avec réserves (même rapport ; sources/pra-faits.md revérifiée) ; ISO 9.2-1 et sha256 inchangés ; options de pct restore citées depuis `pct help restore --verbose` sur pve 9.2.21 (deux citations de la fiche du 16/10 corrigées) ; restauration sur un autre hôte : non trouvé daté, [hypothèse] jouée en 5.8
- motif : SOURCES §9 : restauration vers un autre nœud non traitée ; la seule ISO publiée est 9.2-1 alors que pve est en 9.2.21 : l'égalité de version exige apt, donc un réseau
- source : sources/pra-faits.md ; https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso ; https://pve.proxmox.com/pve-docs/pct.1.html
- repli : D14 : installer depuis l'ISO 9.2-1, la mettre à jour en 9.2.21 par un NAT temporaire (feuille 5.11) avant toute sauvegarde dans le labo ; règle unique, celle de 5.11 : N = 2 essais d'`apt full-upgrade` journalisés, l'écart de version (chaîne `pveversion` du labo comparée à `pve-manager/9.2.21` de pve) est mesuré et noté, puis arrêt et geste de l'admin ; aucune restauration n'est tentée sur un labo en retard sans accord daté de l'admin ; la restauration croisée est jouée en 5.8 avec les options écrites là-bas
- risque : fort
- rôle : chercheur-sources
- parallélisable : pra
- nature : fonction
- brique : docs officielles → fiche de faits datée · dépend de - · réutilise : agent chercheur-sources

### Feuille 5.2 — Périmètre et ordre de reprise (suivant D6, amendée par D13)
- preuve : `pra/perimetre.yaml` ; script de contrôle exit 0 : (1) chaque VMID est un CT de `ssh pve pct list` (V1 : 114, 108, 123, 121, 128, 100 ; V2 : 101, 122) ; (2) chaque CT a une archive dans le MANIFESTE du dernier passage (`grep` par VMID) ; (3) deux contrôles, car le root de l'installeur PVE est plafonné à hdsize/4, soit 96 GiB au plus (wiki Installation) : (3a) sur le root du labo, archives déchiffrées (5.12b : déchiffrées sur le poste en tube, D24 (1), écrites seulement dans le labo ; les `.gpg` restent sur le poste) + template + 20 Go de marge ≤ `root_labo_go` (96 par défaut, lu dans le fichier) ; (3b) sur le pool de données du labo, somme des rootfs + 20 Go de marge ≤ `data_labo_go` (lu dans le fichier, 300 − root par défaut) ; le dossier de déchiffrement est écrit dans le fichier (`dechiffrement_dir`, `/root/pra/clair/` sur le labo) ; (4) RAM cumulée des CT ≤ RAM du labo − 4 Go de marge pour l'hôte imbriqué, la RAM du labo étant lue dans le fichier (16 Go par défaut) ; les VM 106 et 110 n'y figurent pas (vague 3, voir D13). Point (2) : 108, 123, 128 (et 129) ont été ajoutés à `INVITES` le 2026-10-16 (D15) ; le premier passage qui les contient est celui du dimanche 2026-10-18 02:00, donc ce contrôle se joue sur le MANIFESTE de S42 (avant, il est rouge par construction) ; cas d'échec : un CT absent du MANIFESTE de S42 est marqué « sans sauvegarde » et rendu à l'admin
- statut : ÉTABLIE 2026-10-18 avec réserves (juge sonnet GO avec réserves : recettes/verif-5.2-juge.md ; R1 unité inconnue et R2 template dans le fichier levées le même jour, test rouge dans recettes/preuve-5.2.log) ; pra/perimetre.yaml + pra/perimetre.sh exit 0 sur le MANIFESTE 2026-S42 (8 CT, 26.8/96 Go, 84/204 Go, 9472/12288 Mo) ; réserves : dechiffrement_dir lu mais exploité seulement en 5.12b, swap non compté (conforme), RAM/disques du labo pris aux valeurs par défaut du fichier
- motif : périmètre non défini (relevé §6, §8) ; la vague 3 (VM 106 et 110) est hors de cet arbre, ligne datée 2026-10-16 ; la VM 110 reste exclue des sauvegardes (`EXCLUS_ASSUMES`, sauvegarde-hebdo.sh:62)
- source : relevé §6 (inventaire), §8, §11 (ressources du poste : 49 Go de RAM disponibles, 628 Go libres) ; proxmox/sauvegarde/sauvegarde-hebdo.sh (INVITES, EXCLUS_ASSUMES) ; D15
- risque : faible
- rôle : producteur
- parallélisable : pra
- nature : fonction
- brique : inventaire + choix D6 amendé → fichier déclaratif et contrôle statique · dépend de D6, D13 et D15 · réutilise : motif acces.yaml

### Feuille 5.13 — Installer rclone sur le poste et configurer pCloud en lecture seule depuis le noyau (D8bis)
- preuve : `rclone version` (version et sha256 de l'archive de la release notés) ; remote `pcloud-pra` configuré par l'admin à partir de l'entrée « accès pCloud » du noyau (le secret n'est jamais affiché ni collé) dans `~/.config/rclone/rclone.conf` (chmod 600, hors dépôt) ; `rclone lsd pcloud-pra:` liste le dossier des sauvegardes ; lecture seule : le script `pra/tirer-pcloud.sh` n'appelle que `lsf`, `copy`, `copyto` (pcloud-pra comme SOURCE) et `check`, contrôlé par une liste BLANCHE : toute invocation `rclone <sous-commande>` du script doit appartenir à {`lsf`, `copy`, `copyto`, `check`, `version`}, la source de `copy`/`copyto` étant `pcloud-pra:` et la destination jamais `pcloud-pra:` (test dans `tests/run.sh`) ; test rouge nommé : `tests/run.sh` ajoute `rclone sync` puis `rclone copy /x pcloud-pra:y` à une copie du script, et les deux doivent échouer ; `bash tests/scan-secrets.sh` exit 0
- statut : ÉTABLIE 2026-10-18 avec réserves (juge sonnet GO avec réserves : recettes/verif-5.13-juge.md ; preuve recettes/rclone-essais.md) ; rclone v1.75.2 (zip sha256 349ac8fb…, SHA256SUMS signé FBF737EC…) dans ~/.local/bin ; remote pcloud-pra (eapi.pcloud.com) ; réserves : jeton recopié de pve et non issu du noyau (l'admin ne retrouve pas l'identifiant pCloud, choix tranché 2026-10-18 « Recopier le jeton de pve ») : identifiant pCloud retrouvé par l'admin et rangé dans le noyau (03-Sauvegardes) et le Vaultwarden le 2026-10-18 (déclaratif de l'admin, non vérifiable sans le mot de passe maître) ; un jeton commun pve/poste : une révocation côté pve coupe aussi le poste ; liste blanche = garde contre l'erreur, pas contre l'intention ; `.sha256` présents sur pCloud (hypothèse de 5.3 levée)
- motif : D8bis : les `.gpg` ne vivent plus que sur pCloud ; rclone est absent du poste (`which rclone` = 127, constaté 2026-10-16)
- source : source à établir (documentation officielle rclone : installation et backend pCloud, https://rclone.org/pcloud/) ; la portée réduite d'un jeton pCloud est une [hypothèse] non établie
- repli : au plus N = 2 essais (installation par la release officielle avec contrôle sha256, puis par le paquet de la distribution ; configuration manuelle du remote) journalisés dans `recettes/rclone-essais.md` ; échec : arrêt et geste de l'admin ; faute d'un jeton pCloud à portée réduite, la lecture seule repose sur le script limité aux commandes de lecture (ci-dessus), pas sur le remote
- risque : moyen
- rôle : connecteur (installation ; la configuration du remote est un geste de l'admin à partir du noyau)
- parallélisable : pra
- nature : fonction
- brique : release rclone + entrée pCloud du noyau → remote lisible ; retour arrière : supprimer le binaire et `rclone.conf`, révoquer l'accès côté pCloud si l'admin le souhaite · dépend de 5.0 et D8bis · réutilise : création : rien d'existant

### Feuille 5.3 — Tirer les sauvegardes chiffrées depuis pCloud sur le poste (D8bis)
- preuve : `pra/tirer-pcloud.sh` (5.13) copie les `.gpg` du périmètre de 5.2 pour le passage S42 (premier qui contient 108, 123, 128, 129) ; `rclone lsf` montre un `.gpg` par VMID du périmètre ; `sha256sum -c` vert sur les `.sha256` correspondants s'ils sont présents sur pCloud, sinon `rclone check --download` contre pCloud lui-même [hypothèse : présence des `.sha256` sur pCloud, à constater] ; le `MANIFESTE` du passage est tiré aussi et chaque VMID y est retrouvé (`grep` noté) ; taille et durée notées (S41 : 26 Go, débit WAN non mesuré) ; aucun déchiffrement ici : il a lieu en 5.12b, sur le poste (D24 (1), D8bis amendée), la clé ne quitte pas le poste ; place libre du poste notée (`df -h` du dossier de travail ≥ taille du passage + 10 %) ; rien n'est lu sur pve
- statut : ÉTABLIE 2026-10-18 avec réserves (juge sonnet GO avec réserves : recettes/verif-5.3-juge.md ; preuve recettes/preuve-5.3.log) ; 8 .gpg du périmètre S42 dans ~/pra-tirage/2026-S42 (5,8 Go, 2 min 33, ≈ 39 Mo/s), sha256sum -c 8/8, rclone check 0 différence, MANIFESTE tiré ; réserves : débit non rejouable, df évalué avant tirage (29 Go), 129 cité par la feuille mais hors périmètre de 5.2
- motif : D8bis : sur pve, `sauvegarde-hebdo.sh` (l. 736-738, GARDER_CLAIR_LOCAL=1) supprime les `.gpg` locaux après envoi vérifié ; tank ne garde que le clair et des `.sha256` orphelins
- source : relevé §7 et §11 ; proxmox/sauvegarde/sauvegarde-hebdo.sh (l. 736-738) ; source rclone : voir 5.13 (à établir)
- risque : moyen
- rôle : connecteur
- parallélisable : pra
- nature : fonction
- brique : rclone lecture depuis pCloud → fichiers `.gpg` sur le poste · dépend de 5.2, 5.13 et D8bis · réutilise : proxmox/sauvegarde (essai-restauration.sh pour le style)

### Feuille 5.4 — Réseau libvirt étanche `lab-pra`
- preuve : `virsh net-dumpxml lab-pra` sans `<forward>` ; `ip -br addr` : bridge sans route vers 10.0.0.0/24 réel ; depuis une VM du réseau, `ping -c1 -W1 10.0.0.10` = 100 % de perte ; capture `tcpdump` sur l'interface sortante du poste sans paquet du labo pendant le test
- statut : établi avec réserves 2026-10-17 (recettes/verif-5.4.md, juge Opus GO)
- motif : HostOnly existe (192.168.200.0/24) mais l'adressage de pve est 10.0.0.0/24 (relevé §11)
- source : relevé §11 ; SOURCES §11 (principe de bridge isolé, https://pve.proxmox.com/wiki/Network_Configuration)
- risque : moyen
- rôle : producteur
- parallélisable : pra
- nature : fonction
- brique : définition XML libvirt → réseau étanche prouvé · dépend de - · réutilise : réseaux libvirt existants (HostOnly)

### Feuille 5.5 — Proxmox imbriqué installé dans le labo
- preuve : installation depuis l'ISO 9.2-1 de 5.1 (sha256 vérifié) ; la chaîne exacte de `pveversion` du labo est notée (« 9.2-1 » désigne l'ISO, pas le paquet ; la forme attendue est `pve-manager/<x.y.z>/...`) et comparée à `pve-manager/9.2.21` de pve ; `egrep -c 'vmx' /proc/cpuinfo` > 0 dans l'invité ; l'interface web répond depuis le poste via le réseau lab-pra ; RAM 16-24 Go, 8 vCPU, disque 300 Go ; `pvesm status` du labo noté (stockage rootfs retenu) ; deux cartes : lab-pra et une carte NAT TEMPORAIRE (`virsh domiflist`), la seconde retirée en 5.11
- statut : établie avec réserves 2026-10-17 (recettes/verif-5.5-5.11.md, juge Opus GO avec réserves : web depuis le poste via lab-pra impossible par construction, remplacé par NAT puis local) ; D23 : accès du poste au labo par lab-pra, voir 5.14 ; correction 2026-10-18 (5.7, essai 1) : le stockage des rootfs du labo est local-lvm (lvmthin, content rootdir,images) ; « local » (dir) n'accepte pas rootdir
- motif : labo inexistant
- source : SOURCES §8 (https://pve.proxmox.com/wiki/Nested_Virtualization : `--cpu host`) ; sources/pra-faits.md ; relevé §11
- risque : moyen
- rôle : producteur (installation à l'écran : geste de l'admin possible)
- parallélisable :
- nature : fonction
- brique : ISO + réseau de 5.4 → hôte PVE imbriqué · dépend de 5.1 et 5.4 · réutilise : agent debian-sysadmin (cycle de vie virsh)

### Feuille 5.11 — Mettre le labo à niveau 9.2.21 par un NAT temporaire, puis l'isoler (D14)
- preuve : AVANT toute sauvegarde dans le labo : la chaîne `pveversion` passe de celle notée en 5.5 à `pve-manager/9.2.21/...` après `apt update && apt full-upgrade` (sortie collée, dépôt sans abonnement lu dans la doc des dépôts de paquets) ; au plus N = 2 essais, journalisés ; ensuite la carte NAT est retirée (`virsh detach-interface`), `virsh domiflist` ne montre plus que lab-pra ; isolement vérifié et daté dans `recettes/isolement-labo.md` : depuis le labo `ping -c1 -W1 10.0.0.10` et `ping -c1 -W1 1.1.1.1` perdent 100 % ; `tcpdump` sur l'interface sortante du poste sans paquet du labo ; la preuve de 5.4 est rejouée ; échec des deux essais ou isolement non prouvé : arrêt, geste de l'admin
- statut : établie avec réserves 2026-10-17 (recettes/verif-5.5-5.11.md, juge GO avec réserves : tcpdump côté poste = geste l'admin)
- motif : D14 (2026-10-16) : l'ISO 9.2-1 est la seule publiée ; le réseau d'une mise à jour contredit l'étanchéité de 5.4, donc il est temporaire, borné dans le temps et refermé avant que des données entrent
- source : https://pve.proxmox.com/wiki/Package_Repositories (à lire dans cette feuille) ; sources/pra-faits.md ; feuille 5.4
- risque : moyen
- rôle : producteur
- parallélisable :
- nature : fonction
- brique : carte NAT libvirt temporaire → mise à jour → carte retirée → preuve d'isolement ; retour arrière : snapshot libvirt du labo avant la mise à jour · dépend de 5.5 et 5.4 · réutilise : réseau libvirt NAT existant (virbr0)

### Feuille 5.14a — Lien poste ↔ labo, à sec : `pra/poste-labo.sh`, bibliothèque ssh et garde `--verifier` (D23, D24)
- preuve : `tests/test-poste-labo.sh` ROUGE (script absent) puis vert, sans root, doubles de `ip`, `nft`, `sysctl`, `arping`, `ssh` en tête de `PATH` : refus sans `--oui` (exit 2) ; ordre de pose lu dans le journal des doubles (sysctls de virbr-pra → `nft -c -f` → `nft -f` → `arping -D` 10.255.70.1 → adresse 10.255.70.1/30 → `--verifier`), retrait inverse (adresse jamais posée sans la table, sauf le mode de preuve `--rouge-sans-table --oui`, testé à sec avec `--retirer --oui`) ; refus exit 3, un rouge par raison (`nft -c` rouge, réponse ARP, /30 porté ailleurs, 10.0.0.x sur virbr-pra, `arping` absent) ; `--verifier` sans root (adresse, route, canari TCP et UDP tenté depuis le labo) : exit 4 « REFUS isolement : <raison> », un rouge par raison ; `pra/lib-ssh-labo.sh` aux options ssh figées, aucun ssh direct dans `pra/*.sh` ; `bash tests/run.sh` vert ; scan-secrets exit 0 ; critère détaillé : `recettes/criteres-lot5-D24.md` § 5.14a
- statut : préparée 2026-10-17 (recettes/preuve-5.14a.log ; l'orchestrateur rejoue l'oracle) ; créée 2026-10-17 en scindant 5.14, objection 9 ; D24 (2)
- motif : D24 (2) : lien 10.255.70.0/30, aucune adresse 10.0.0.x côté poste ; obj. 2, 4, 10, 14 de recettes/contradicteur-D23.md : le fichier de règles système du poste commence par `flush ruleset`, d'où la garde avant chaque pilotage ; `arping` absent (2026-10-17)
- source : sources/poste-labo-D24.md (`nft -c`, `flush ruleset`, `arping -D`, constats du poste ; 2026-10-17) ; man ssh_config(5) du poste
- risque : moyen
- rôle : producteur (à sec, sans root)
- parallélisable : pra
- nature : fonction
- oracle : `bash tests/test-poste-labo.sh`
- brique : doubles de commandes → script, ordre et garde prouvés sans toucher au réseau ; retour arrière : commit annulé, aucun état système modifié · dépend de 5.4, 5.11, D23 et D24 · réutilise : style des tests de 2.3

### Feuille 5.14b — Lien poste ↔ labo, en direct : pose par l'admin et preuve d'isolement (D23, D24)
- preuve : gestes de l'admin : `arping` installé ; `10.255.70.2/30` en deuxième adresse de vmbr0 du labo (console série, `ip -br a`) ; empreinte de l'hôte lue à la console avant `known_hosts-pra-lab` ; clé `~/.ssh/pra-lab` ; (1) rouge en direct sans la table : depuis le labo `</dev/tcp/10.255.70.1/22` réussit, canari UDP reçu ; (2) `sudo pra/poste-labo.sh --oui` (`nft -c -f` vert, `arping -D` exit 0) ; (3) `pra/scan-poste.sh` depuis le labo : toutes les adresses de `ip -br a` du poste (IPv4, IPv6 globales et ULA) par voisin statique (`ip neigh replace`), TCP 1-65535 sur 10.255.70.1 (`timeout 0.5`, 128 en parallèle), ports `ss -lntu` et canaris TCP+UDP ailleurs, IPv6 de virbr-pra vide : aucun port ouvert, aucun canari reçu, compteur du drop en hausse ; (4) transit refusé (route par défaut du labo via .1 : Internet et LAN injoignables) ; (5) du poste : ssh rc=0, API 8006 répond, `--verifier` exit 0 ; (6) `sudo nft delete table inet pra_poste` → `--verifier` exit 4 `canari-tcp`, table reposée ; (7) `--retirer --oui` : diff vide ; critère détaillé : `recettes/criteres-lot5-D24.md` § 5.14b ; preuve : `recettes/preuve-5.14b.md`
- statut : ÉTABLIE 2026-10-18 avec réserves (juge sonnet GO avec réserves : recettes/verif-5.14b-juge.md ; réserves 2 et 3 levées le même jour : témoin positif et transit forcé par /32, preuve-5.14b-balayage2.log et -transit2.log) ; synthèse recettes/preuve-5.14b.md ; réserves : compteur de drop non relevé avant balayage, « avant » du point 7 pris après un premier retrait, nft -c prouvé par le code seulement ; lien posé et en place
- motif : D23 ; le poste écoute sur 0.0.0.0, transfère (ip_forward=1) et porte une douzaine d'adresses visables par voisin statique (hôte faible) : parade principale = table `inet pra_poste` (entrée virbr-pra : established,related puis drop ; transit : drop) ; arp_ignore et disable_ipv6 en seconde couche
- source : https://wiki.nftables.org/wiki-nftables/index.php/Matching_connection_tracking_stateful_metainformation ; https://docs.kernel.org/networking/ip-sysctl.html ; sources/poste-labo-D24.md (2026-10-17) ; https://pve.proxmox.com/wiki/Network_Configuration
- repli : N = 2 essais journalisés ; sonde passée, canari reçu ou diff non vide = arrêt, `--retirer --oui`, rendu à l'admin ; ligne `address` refusée ([hypothèse] ifupdown2) : `ip addr add` à la console, non persistant
- risque : fort
- rôle : connecteur (sudo, console et clé ssh : gestes de l'admin)
- parallélisable : pra
- nature : fonction
- brique : virbr-pra + table nft → canal poste → labo seul ; rien de persistant au poste ; retour arrière : `--retirer --oui`, reboot du poste, snapshot libvirt du labo · dépend de 5.14a, 5.4 et 5.11 · réutilise : pra/poste-labo.sh (5.14a)

### Feuille 5.6a — Code portable et gardes : hôte cible en variable, un état par cible, `tofu-cible.sh`
- preuve : `tofu validate` exit 0 ; `verifier.sh` exit 0 sur pve ; `labo.tfvars` (endpoint `https://10.255.70.2:8006`, nœud `pra-lab`, stockages de 5.5, `labo_started = false`) ; `features` en `ignore_changes` (D17) ; `tofu-cible.sh <pve|labo>` fixe `TF_DATA_DIR`, `-var-file`, l'état `etat/<cible>.tfstate` (chiffré par 4.3, MÊME phrase que pve, D24 (3)) et les identifiants ; pour `labo`, `pra/poste-labo.sh --verifier` d'abord (exit 4 = refus) ; gardes endpoint, nœud (`GET /api2/json/nodes`), empreinte : exit 3 « REFUS cible=<c> : <raison> », identifiants absents exit 2 ; `tests/run.sh` ROUGES d'abord : chaque garde seule contre une API factice HTTPS locale, assertion sur la raison ; motif `.claude/garde.yml` contre tofu direct sur le labo hors `tofu-cible.sh`, prouvé par `bash .claude/tests/test-garde.sh` ; motif `pveum` dans scan-secrets + test rouge ; sha256 de `etat/pve.tfstate` inchangé ; job `tofu-plan` lu `success` par l'API Forgejo (`actions/tasks`) ; critère détaillé : `recettes/criteres-lot5-D24.md` § 5.6a
- statut : ÉTABLIE 2026-10-18 avec réserves (juge Opus, 3 passages : NO-GO puis GO avec réserves, recettes/verif-5.6a-juge.md ; preuve recettes/preuve-5.6a.log) ; tofu-cible.sh (gardes endpoint/empreinte/noeud/etat, options et environnement purgés, crochets d'essai bornés), verrou D25 lié à la cible ET à l'endpoint (tests/test-verrou.sh), motif garde.yml [9] de surface ; CI run 17 success avant D25, run 18 = 1 à ajouter (verrou_cible) seulement ; verrou posé dans l'état de pve par l'admin le 2026-10-18 10:00 (Apply 1 added, puis No changes ; pve.tfstate 9f81332f… ; copie CI republiée ; CI run 20 success, recettes/preuve-5.6a-verrou.log) ; réserves : tunnel 127.0.0.1 vers un autre hôte arrêté par l'empreinte seule ; labo.env/CA/empreinte du labo en 5.6b
- motif : endpoint, nœud et stockages sont propres à pve ; un apply du labo avec l'état de pve le corromprait ; 127.0.0.1:8006 = pve (tunnel) ; reports de 4.7 (tofu-cible.sh, CA par SSL_CERT_FILE)
- source : SOURCES §1 (bpg v0.116.1) ; relevé §1 ; feuilles 4.3 et 4.7 ; sources/privileges-jeton.md
- risque : moyen
- rôle : producteur
- parallélisable : pra
- nature : fonction
- oracle : `bash tests/run.sh`
- brique : variables node, endpoint, datastore → même code pour pve et labo, sans labo vivant ; retour arrière : commit annulé · dépend de 4.3, 3.6, 1.2, 1.7, 4.7 et 5.14a · réutilise : code de 1.x à 3.x, test-garde.sh

### Feuille 5.6b — Jeton et TLS du labo : `tofu-rw@pve`, ACL du périmètre, certificat au SAN 10.255.70.2
- preuve : par `pra/lib-ssh-labo.sh` (garde verte), commandes de 3.2 rejouées dans le labo : rôle `TofuCT` (1.2), `tofu-rw@pve`, jeton `ecriture` privsep=1 ; ACL sur chaque VMID de `pra/perimetre.yaml` (aucune sur `/vms`), `/storage/<labo>`, `/storage/local`, `/sdn/zones/localnetwork`, `/nodes/pra-lab`, comparées par script à `pveum acl list` ; jeton par `jq` vers `~/.config/infra-as-code/labo.env` (600, jamais affiché, jamais dans le labo) ; TLS `insecure = false`, CA du labo par `SSL_CERT_FILE` ; SAN lu par `openssl x509` : sans `IP Address:10.255.70.2`, certificat propre `pveproxy-ssl.pem` signé par la CA du labo ; empreinte enregistrée ; `./tofu-cible.sh labo plan` exit 0 ; scan-secrets exit 0 ; critère détaillé : `recettes/criteres-lot5-D24.md` § 5.6b
- statut : ÉTABLIE 2026-10-18 avec réserves (juge sonnet GO avec réserves : recettes/verif-5.6b-juge.md ; preuves recettes/preuve-5.6b.log, recettes/preuve-5.6b-plan.log) ; sur autorisation de l'admin (« tu peux creer l'utilisateur et son jeton ») : pra/labo-jeton.sh, rôle TofuCT (privilèges relus sur pve), tofu-rw@pve, jeton ecriture privsep=1 → labo.env (600), ACL 11 chemins = attendu ; pveproxy-ssl signé par la CA du labo, SAN IP 10.255.70.2, Verify 0, empreinte aca2cb19… enregistrée ; blocs import de pve désactivés (import-ct*.tf.importe, CI run 22 No changes, CT dans l'état) ; plan du labo par l'admin : 4 à créer, rc=0 ; réserves : preuve en .log et non .md, labo.tfstate créé seulement au premier apply (5.7)
- motif : D17 (pas de root@pam) ; le certificat d'installation précède la deuxième adresse ; objection 6
- source : sources/privileges-jeton.md (https://pve.proxmox.com/pve-docs/chapter-pveum.html) ; sources/poste-labo-D24.md (https://pve.proxmox.com/wiki/Certificate_Management) ; feuille 3.2
- repli : rôle insuffisant : N = 3 essais (un privilège à la fois), `recettes/essais-privileges-labo.md` ; certificat refusé ([hypothèse] signature par la CA du labo) : N = 2 essais, retour au certificat d'origine, rendu à l'admin ; jamais `insecure` ni root@pam
- risque : moyen
- rôle : producteur
- parallélisable : pra
- nature : fonction
- brique : labo vivant + gardes de 5.6a → API du labo jointe par jeton borné et TLS vérifié ; retour arrière : utilisateur retiré du labo, `labo.env` supprimé, `pveproxy-ssl.*` retirés · dépend de 5.6a, 5.14b, 5.5 et 5.2 · réutilise : commandes de 3.2

### Feuille 5.12a — Copier le template debian-13 vers le labo (ssh initié du poste)
- preuve : `pra/poste-labo.sh --verifier` exit 0 avant toute copie ; template `debian-13-*.tar.zst` tiré en lecture seule (`rsync`) depuis `local` de pve vers le poste par l'accès ssh de 1.7 (seul fichier tiré de pve, sha256 noté) ; copie vers `/var/lib/vz/template/cache/` du labo par `pra/lib-ssh-labo.sh` (scp, options figées de 5.14a) ; sha256 calculé dans le labo égal à celui du poste (comparé par script) ; `pveam list local` du labo le montre ; `virsh domiflist pra-lab` et `virsh domblklist pra-lab` inchangés (aucune carte ni disque ajouté) ; sorties dans `recettes/preuve-5.12a.log`
- statut : ÉTABLIE 2026-10-18 (juge sonnet GO : recettes/verif-5.12a-juge.md ; preuve recettes/preuve-5.12a.log) ; debian-13-standard_13.6-1 sha256 1a5e43d0… égal sur pve, poste et labo ; pveam list local du labo le montre ; cartes et disques de pra-lab inchangés
- motif : canal choisi (D23) : scp/ssh du poste vers le labo par le lien de 5.14b, initié par le poste seul, chiffré, sans service ouvert sur le poste et sans support à construire ; écartés : disque virtuel (D18, retirée) et téléversement par l'API du labo (couvre ISO et templates ; pour les archives vzdump, [hypothèse] non établie : un seul canal pour 5.12a et 5.12b)
- source : relevé §7, §11 ; man scp(1) et sha256sum(1) du poste
- risque : faible
- rôle : connecteur
- parallélisable : pra
- nature : fonction
- brique : template de pve → template dans le labo, prérequis de la coquille (5.7) seulement, sans rien de pCloud ; retour arrière : retirer le fichier copié du cache du labo · dépend de 5.14b, 5.11 et 1.7 · réutilise : pra/lib-ssh-labo.sh (5.14a)

### Feuille 5.7a — Décrire en code et importer dans l'état de pve les CT 108, 114, 121, 123, 128 (D26)
- preuve : un fichier `tofu/ct<vmid>.tf` par CT, écrit d'après `ssh pve pct config <vmid>` (lecture seule) sur le modèle de ct100.tf (node, datastore, started par variables ; `features`, `template_file_id`, `user_account`, `vm_id` en ignore_changes ; `prevent_destroy`) ; blocs `import` actifs le temps de l'import seulement ; variable `template_file_id` (défaut vide, labo.tfvars = `local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst`) ; `tofu validate` et `bash tests/run.sh` verts ; CI : le plan de pve annonce exactement 5 imports, 0 ajout, 0 changement, 0 destruction ; geste de l'admin : apply de l'import (état seul), puis CI « No changes » ; blocs import désactivés ensuite (`.importe`) ; sha256 de `etat/pve.tfstate` avant/après noté ; sorties dans `recettes/preuve-5.7a.log`
- statut : ÉTABLIE 2026-10-18 avec réserves (juge Opus GO avec réserves : recettes/verif-5.7a-juge.md ; preuves recettes/preuve-5.7a.log, recettes/preuve-5.7a-import.log) ; code des 5 CT conforme à pct config ; CI run 24 « 5 to import », apply par le fil principal sur « Oui » de l'admin : 5 imported, puis No changes (plan rejoué par le juge) ; pve.tfstate 9f81332f… → a92dc188… ; copie CI republiée (ci-publier-etat.sh) ; blocs import désactivés, CI run 25 success ; réserves : CT 128 timezone et tun non décrits (commentés dans ct128.tf), features keyctl/fuse de 114/123/128 non créables par le jeton (à traiter en 5.7 : coquille sans ces features, pct restore les remet en 5.8)
- motif : D26 : le PRA en code exige que chaque CT du périmètre de 5.2 soit décrit et dans l'état de pve
- source : feuilles 1.x (imports de 100/101/122), SOURCES §1 (bpg v0.116.1), sources/pra-faits.md
- risque : moyen
- rôle : producteur (code) ; apply de l'import = geste de l'admin
- parallélisable : non
- nature : fonction
- oracle : `bash tests/run.sh`
- brique : pct config de pve → code des 5 CT, importés sans changement · dépend de 5.2, 5.6a · réutilise : ct100.tf, recettes d'import de O1

### Feuille 5.7 — Coquille : appliquer le code au labo (chemin unique : coquille puis restauration --force)
- preuve : depuis le poste, `./tofu-cible.sh labo plan` (garde `--verifier` et gardes de 5.6a vertes) annonce les CT du périmètre de 5.2 (créations seulement, `started` = `labo_started` (false), rootfs de même taille que sur pve, stockage du labo noté en 5.5, `hwaddr` fixée) ; `./tofu-cible.sh labo apply` (tofu-rw@pve du labo, D17, jeton de 5.6b) ; `etat/labo.tfstate` créé chiffré sur le poste avec la phrase de pve (D24 (3) ; `grep -c encrypted_data` = 1) ; `pra/lib-ssh-labo.sh pct list` les liste stopped ; `verifier.sh` sur pve exit 0 et sha256 de `etat/pve.tfstate` inchangé ; sorties dans `recettes/preuve-5.7.log`
- statut : ÉTABLIE 2026-10-18 avec réserves (juge sonnet : NO-GO puis GO au passage 2, recettes/verif-5.7-juge.md ; preuve recettes/preuve-5.7.log) ; coquille des 8 CT du périmètre créée dans le labo par tofu-rw du labo, sur « Oui » de l'admin (essai 1 refusé : storage local sans rootdir ; essai 2 : 8 added) ; stopped, local-lvm, rootfs aux tailles du code, MAC de pve (var.macs, choix de l'admin) ; keyctl/fuse coupés pour le labo (features_root, D17 : remis par la restauration en 5.8) ; plans labo et pve « No changes », etat/labo.tfstate chiffré, CI run 27 success ; réserves : rootfs comparés au code, pas directement à pct config de pve
- motif : labo vide ; décision de chemin : la coquille tofu crée les CT vides sans flags de `features` (D1, D17), la feuille 5.8 y restaure les données par-dessus ; le chemin « restaurer puis `import {}` » (SOURCES §10) est écarté
- source : relevé §1 ; SOURCES §10 (pas d'attribut de restauration dans bpg : coquille tofu, données restaurées à part) ; sources/pra-faits.md
- risque : moyen
- rôle : producteur
- parallélisable :
- nature : fonction
- brique : code portable + labo.tfvars → CT du périmètre créés vides ; OpenTofu tourne sur le poste et joint l'API du labo par le lien 10.255.70.0/30 (D23, D24 (2)) ; le template debian-13 est dans le labo (5.12a) ; la liste des CT vient de 5.2, qui se joue sur le MANIFESTE de S42 (dimanche 2026-10-18 02:00) ; repli : un apply partiel se reprend par un nouveau `plan` (état du labo seul touché) ; si l'apply échoue sans être repris en N = 2 essais, retour au snapshot libvirt du labo pris avant l'apply · dépend de 5.5, 5.6b, 5.2, 5.11, 5.12a et 5.14b · réutilise : le code de 3.3

### Feuille 5.12b — Déchiffrer sur le poste, en flux, les archives du périmètre vers le labo (D24 (1))
- preuve : `pra/archives-vers-labo.sh` (à sec par défaut, `--oui` requis, `set -euo pipefail`) appelle d'abord `--verifier` ; par VMID de `pra/perimetre.yaml`, `.gpg` de 5.3 déchiffré DANS UN TUBE sur le poste (`gpg --batch --pinentry-mode loopback --passphrase-fd 3 --status-fd 4 -d … | tee >(sha256sum) | pra/lib-ssh-labo.sh "cat > <dechiffrement_dir>/<nom>"`) ; `PIPESTATUS` complet à 0 ; `--status-fd` : `DECRYPTION_OKAY`, pas `DECRYPTION_FAILED` ; phrase par `--source keepass` (chiffre-4.3.sh), jamais sur disque, en argument ni à l'écran ; sha256 du clair égal des deux côtés (transport) ; `zstd -t` et `./etc/vzdump/pct.conf` dans la liste (déchiffrement) ; aucun clair sur le poste (`find`) ; comptage = VMID du périmètre ; `tests/run.sh` : refus sans `--oui`, VMID absent du MANIFESTE, faux gpg en code 2 (rouges d'abord) ; scan-secrets exit 0 ; critère détaillé : `recettes/criteres-lot5-D24.md` § 5.12b
- statut : ÉTABLIE 2026-10-18 avec réserves (juge Opus : NO-GO puis GO avec réserves au passage 2, recettes/verif-5.12b-juge.md ; preuves recettes/preuve-5.12b-tests.log, recettes/preuve-5.12b.log) ; pra/archives-vers-labo.sh (c2e9e33 puis 788ef2c : GOODMDC, crochets PRA_TEST, %q, .partiel) ; 8 archives déchiffrées en flux vers /root/pra/clair du labo, deux passages aux mêmes sha256, zstd -t et pct.conf 8/8, aucun clair sur le poste ; clé GPG en mémoire de session (choix de l'admin) ; réserves : faux --verifier possible sous tests/.tmp-* avec PRA_TEST=1, dossiers tests/.tmp-* résiduels (ignorés par git)
- motif : D24 (1) : la clé ne quitte pas le poste (D8bis amendée) ; objection 11 : sha256 = transport, pas déchiffrement
- source : relevé §7 ; proxmox/sauvegarde/sauvegarde-hebdo.sh ; recettes/chiffre-4.3.sh ; man gpg(1) du poste
- risque : moyen
- rôle : connecteur (rend la main à l'admin pour le mot de passe du noyau)
- parallélisable :
- nature : fonction
- brique : `.gpg` du poste + phrase du noyau (5.0) → archives claires dans le labo ; écart = arrêt ; retour arrière : snapshot libvirt du labo, ou suppression des archives claires · dépend de 5.3, 5.0, 5.2 et 5.12a · réutilise : chiffre-4.3.sh, essai-restauration.sh

### Feuille 5.8 — Restaurer les données dans le labo (chemin unique)
- preuve : `pra/poste-labo.sh --verifier` exit 0 avant chaque série ; archives claires de 5.12b ; par CT du périmètre, depuis le poste par `pra/lib-ssh-labo.sh` (root du labo, hors OpenTofu, D17) : `pct restore <vmid> <archive> --force 1 --storage <stockage-labo> --unprivileged 1 --net0 name=eth0,bridge=vmbr0,ip=<ip>/24,gw=10.0.0.254,hwaddr=<hwaddr de l'état>` exit 0 (mode simple ; pas de `--unique`, la MAC vient de l'état) ; rootfs non vide (`du -sh`) ; `features` de l'archive reprises (`pct config` comparé à `pvesm extractconfig`) ; `./tofu-cible.sh labo plan -detailed-exitcode` exit 0 ; N = 2 essais par CT ; écart persistant = `ignore_changes` borné listé dans `labo.tfvars` (commité) ; démarrage dans l'ordre de `pra/perimetre.yaml`, `pct start` un par un, `labo_started = true` puis plan exit 0 ; durées notées ; critère détaillé : `recettes/criteres-lot5-D24.md` § 5.8 ; `pct restore --force` exige le marqueur `# AUTORISÉ-PAR-FRED` (garde.yml, l'admin)
- statut : ÉTABLIE 2026-10-18 avec réserves (juge sonnet GO avec réserves : recettes/verif-5.8-juge.md ; preuve recettes/preuve-5.8.log) ; instantané libvirt avant-5-8-20261018 ; restaurations forcées du labo sur accord de l'admin (« Oui, labo seulement », marqueur cité) ; 8 CT restaurés par pra/restaurer-labo.sh (24 à 76 s chacun ; 1er essai arrêté avant toute restauration : pvesm extractconfig refuse un chemin), features et net0 identiques à pve, CT 128 avec tun et timezone ; démarrage vague1 puis vague2 ; labo_started = true ; plans labo et pve « No changes » ; CI run 29 success ; réserves : host-managed=0 ajouté par le labo, rootfs non vide attesté par le journal
- motif : restauration jamais rejouée sur un autre Proxmox (relevé §7) ; options d'après la fiche
- source : SOURCES §9 (https://pve.proxmox.com/wiki/Backup_and_Restore) ; sources/pra-faits.md (pct.1) ; effet de `--force` sur une coquille tofu : [hypothèse] jusqu'à cet essai
- risque : moyen
- rôle : producteur
- parallélisable :
- nature : fonction
- brique : archives du labo + coquille → CT restaurés ; pilotage du poste sur 10.255.70.2 (D23, D24 (2)), aucune connexion initiée par le labo ; retour arrière : snapshot libvirt du labo avant la première restauration · dépend de 5.7, 5.12b et 5.0 · réutilise : essai-restauration.sh, pra/lib-ssh-labo.sh

### Feuille 5.9 — Vérifications applicatives du labo
- preuve : `pra/verifs.sh` exit 0, lancé sur le poste après `--verifier` exit 0, chaque contrôle par `pra/lib-ssh-labo.sh` (curl depuis l'hôte du labo ou `pct exec`) ; références tirées de LA MÊME archive S42 que celle restaurée : `pra/references.sh` extrait (`tar -xOf`) avant `pct start` le fichier de données de chaque ligne, note son sha256 et le copie dans le CT ; après démarrage, même requête et même binaire sur la copie et sur la base vive ; écart toléré : 0 sur les décomptes, titre exact, sha256 du fichier de données égal entre archive et rootfs ; ports et noms lus dans la config de l'archive ; `pra/references-S42.tsv`, `recettes/preuve-5.9.md`, écarts d'IP/DNS/certificats dans `pra/ecarts.md` ; critère détaillé (tableau par VMID : 100, 101, 108, 114, 121, 123, 128, 122) : `recettes/criteres-lot5-D24.md` § 5.9
- statut : FAITE AUTREMENT 2026-10-18, à juger : pra/verifs.sh compare ports d'écoute et titres de pages de chaque invité à une référence relevée sur pve (pra/references-pve.tsv, 35 contrôles) au lieu des références tirées des archives ; labo après répétition : 34/35 (Authelia du CT 121 exige Internet : écart du labo, noté dans PROCEDURE-PRA.md) ; preuves recettes/preuve-5.9-avant-repetition.log, recettes/preuve-5.10-repetition.log
- motif : « répond 200 » ne prouve pas que le service marche ; une valeur relevée sur pve après S42 n'est pas reproductible
- source : relevé §6, §9 ; annuaire/recette-wan.py (code ET contenu) ; rôles : annuaire/STATUS.md l. 3, portail/STATUS.md l. 18, 21, 24, framadate/STATUS.md, coffre-mdp/STATUS.md
- risque : moyen
- rôle : producteur
- parallélisable :
- nature : fonction
- oracle : `bash pra/verifs.sh`
- brique : labo restauré + archive S42 → contrôles par service comparés à l'archive ; retour arrière : copies de référence retirées des CT · dépend de 5.8 et 5.14b · réutilise : style de tests de 2.3

### Feuille 5.10 — Recette réelle du PRA : répétition chronométrée et procédure écrite
- preuve : `pra/PROCEDURE-PRA.md` suivie telle qu'écrite par une personne autre que le rédacteur ; durée totale (RTO) mesurée ; `pra/verifs.sh` exit 0 ; isolement re-contrôlé à la fin (preuves de 5.4 et de 5.14b rejouées : scan de toutes les adresses du poste, canaris, transit ; le labo ne joint ni Internet, ni le LAN, ni un port du poste) ; liste des gestes manuels (box, DNS, secrets, certificats) ; mention de la vague 3 (VM 106 et 110) comme non couverte ; section « Ce que la répétition ne prouve pas » dans `pra/PROCEDURE-PRA.md` : en vrai PRA l'hôte neuf est sur le LAN de l'asso et le poste le joint par le tunnel (1.7), pas par le lien dédié 10.255.70.0/30 ; les archives viennent de pCloud vers un hôte réel (débit WAN) ; le noyau n'existe qu'en un exemplaire, sur le poste (réserve D22, D24 (4)) : poste perdu = PRA impossible ; hôte imbriqué (RTO non transposable tel quel) ; IP, DNS, box et certificats réels non éprouvés (labo sans LAN)
- statut : RÉPÉTÉE 2026-10-18 avec réserves : labo vidé (accord de l'admin « Le labo pra-lab : répéter dessus ») puis rendu en 31 min par les scripts de pra/PROCEDURE-PRA.md (recettes/preuve-5.10-repetition.log ; arrêt à l'étape 4 : la destruction avec purge retire les ACL /vms du jeton, reposées, piège écrit) ; juge Sonnet GO avec réserves sur la préparation du jour J (recettes/verif-pret-demain-juge.md), réserves R1-R5 corrigées ; reste : suivi par une autre personne que le rédacteur, isolement re-contrôlé
- motif : aucun PRA répété
- source : relevé §7, §9, §11
- risque : moyen
- rôle : verificateur
- parallélisable :
- nature : recette-réelle
- brique : labo nu + sauvegardes → services du périmètre en marche, durée mesurée · dépend de 5.9, 5.11, 5.14b et 4.4 · réutilise : agent verificateur

## Décompte (recompté)
46 feuilles : lot 1 = 7 (début O1), lot 2 = 4 (fin O1), lot 3 = 6 (O2), lot 4 = 11 (O3), lot 5 = 18 (O4). O1 = lots 1-2 (11), O2 = 6, O3 = 11, O4 = 18. Révision D23 (2026-10-17) : 5.14 créée, 5.12 scindée ; révision D24 (2026-10-17) : 5.14 scindée en 5.14a (à sec) et 5.14b (en direct), 5.6 en 5.6a (code et gardes) et 5.6b (jeton et TLS) ; une sous-feuille ne se redécoupe pas.
12 feuilles fortes : 1.2, 1.4, 3.2, 3.4, 3.5, 3.6, 4.1, 4.5, 4.6, 4.9, 5.1, 5.14b (3 chercheur-sources : 1.2, 4.1, 5.1).
Gestes de l'admin : 1.4, 3.2, 4.0 (constat et attestation de réserve), 4.2, 4.6 (interface éventuelle), 4.9 (arrêt du service), 4.10, 5.0 (constat), 5.13 (configuration du remote pCloud), 5.14b (sudo, console série du labo, clé ssh), 5.12b (mot de passe du noyau) ; recettes réelles : 2.4, 3.6, 4.8, 5.10.
Nouvelles feuilles de la révision du 2026-10-16 : 1.7, 4.0, 4.9, 5.0, 5.11, 5.12 (scindée en 5.12a et 5.12b le 2026-10-17, D23) ; passage 2 : 4.10 (dépôt git/infra-as-code), 5.13 (rclone et pCloud) ; D24 : 5.6a, 5.6b, 5.14a, 5.14b.
### Feuille 5.15 — Cible de secours générique : redéployer sur n'importe quel Proxmox de l'association (D27)
- preuve : `tofu-cible.sh` accepte une 3e cible déclarée par un seul fichier `tofu/<cible>.tfvars` + une entrée dans une table unique (endpoint, nœud, datastore, empreinte, fichier d'identifiants, CA, chemin d'accès) ; plus aucune adresse du labo écrite en dur hors de cette table (`grep -rn 10.255.70.2` limité à la table, à labo.tfvars et aux preuves) ; `pra/labo-jeton.sh` généralisé en `pra/cible-jeton.sh <cible>` (rôle, utilisateur, jeton, ACL du périmètre, certificat au bon SAN) ; verrou D25 et précondition d'endpoint étendus à la nouvelle cible ; `tests/run.sh` : une cible factice `essai` passe toutes les gardes contre l'API factice, puis chaque garde rouge sur sa raison ; non-régression : CI pve « No changes », `./tofu-cible.sh labo plan` exit 0 ; `PROCEDURE-PRA.md` (5.10) complétée d'un chapitre « vrai PC de l'asso » : installer Proxmox (ISO de 5.1 + mise à niveau), réseau et accès depuis un poste (le poste de l'admin est hors LAN : tunnel ou poste sur place), conflit d'adresses 10.0.0.x si pve vit encore (règle : ne restaurer en adresses réelles que pve éteint), ordre de reprise de 5.2 ; relue par un juge, sans geste réel sur un autre PC
- statut : CODE PRÊT 2026-10-18, à prouver sur le vrai serveur le 2026-10-19 : cible secours (tofu-cible.sh, verrou, PRA_CIBLE des scripts), pra/secours-preparer.sh, pra/secours-basculer.sh (bascule par ajout de 10.0.0.10 après débranchement de pve, retour arrière), PROCEDURE-PRA.md ; non exercés en répétition : préparer, basculer, ssh-copy-id, état tofu vide, import du 9020 (juge : recettes/verif-pret-demain-juge.md)
- motif : D27 : l'objectif O4 vise un redéploiement « sur un autre Proxmox si pve tombe » ; le code ne connaît que pve et labo
- source : feuilles 5.6a, 5.6b, 5.10 ; sources/pra-faits.md
- risque : moyen
- rôle : producteur
- parallélisable : non
- nature : fonction
- oracle : `bash tests/run.sh`
- brique : cibles pve et labo prouvées → modèle de cible réutilisable + procédure pour un vrai PC · dépend de 5.10 · réutilise : tofu-cible.sh, pra/labo-jeton.sh, tests/test-tofu-cible.sh


### Feuille 5.7b — Décrire en code et importer sur pve les CT de la vague 3 : 104, 115, 117, 118, 119, 120, 129, 9020 (D28)
- preuve : un `tofu/ct<vmid>.tf` par CT d'après `ssh pve pct config <vmid>` (lecture seule), modèle ct108.tf ; montages liés (115, 129, 9020) et `features` décrits seulement si `var.features_root` (créables par root@pam seul) ; seconde carte (117 vmbr2, 9020 vmbr1) décrite ; 9020 privilégié (`unprivileged = false`) ; MAC dans `var.macs` ; `tofu validate` et `bash tests/run.sh` verts ; plan de pve (poste puis CI) : exactement 8 imports, 0 ajout, 0 changement, 0 destruction ; apply de l'import (état seul) sur « oui » de l'admin, puis « No changes » ; blocs import en `.importe` ; sha256 de `etat/pve.tfstate` avant/après ; sorties dans `recettes/preuve-5.7b.log`
- statut : ÉTABLIE 2026-10-18 (juge Sonnet GO : recettes/verif-5.7b-juge.md ; preuves recettes/preuve-5.7b.log, recettes/preuve-5.7b-import.log) ; plan 8 to import (poste puis CI run 32), apply sur « Oui » de l'admin : 8 imported, puis No changes ; pve.tfstate a92dc188… → 5cc5aaf7… ; copie CI republiée, CI run 33 success ; note du juge : features et mount_point en ignore_changes, couverts par la comparaison à pct config seulement
- motif : D28 (1) : périmètre élargi à tous les services en marche
- source : feuille 5.7a ; SOURCES §1 (bpg v0.116.1)
- risque : moyen
- rôle : producteur (code) ; apply de l'import = « oui » de l'admin
- parallélisable : non
- nature : fonction
- oracle : `bash tests/run.sh`
- brique : pct config de pve → code des 8 CT, importés sans changement · dépend de 5.7a · réutilise : ct108.tf, recettes/preuve-5.7a.log

### Feuille 5.7c — Décrire en code et importer sur pve la VM 106 Snipe-IT (D28)
- preuve : `tofu/vm106.tf` (ressource `proxmox_virtual_environment_vm`) d'après `ssh pve qm config 106` ; plan de pve : 1 import, 0 changement, 0 destruction ; écarts non relisibles en `ignore_changes` bornés et commentés ; apply de l'import sur « oui » de l'admin puis « No changes » ; sorties dans `recettes/preuve-5.7c.log`
- statut : NON RETENUE 2026-10-18 (D28 (5)) : le plan de pve exige VM.Config.Disk sur /vms/106 (« Permission check failed (/vms/106, VM.Config.Disk) », essai du 2026-10-18), un droit d'écriture refusé au jeton en lecture seule de la CI (D5) ; la VM 106 revient par qmrestore en 5.8b, hors code
- motif : D28 (1) : première VM du périmètre ; une VM ne se « coquille » pas comme un CT (disques restaurés par qmrestore)
- source : SOURCES §1 (bpg v0.116.1, ressource VM : documentation de la version installée)
- risque : moyen
- rôle : producteur ; apply = « oui » de l'admin
- parallélisable : non
- nature : fonction
- oracle : `bash tests/run.sh`
- brique : qm config de pve → code de la VM 106 importée sans changement · dépend de 5.7b

### Feuille 5.8b — Restaurer la vague 3 dans le labo (D28)
- preuve : labo préparé à l'identique de pve : ponts internes vmbr1 et vmbr2 (sans port), dossiers des montages liés créés vides (données hors sauvegarde : 5.16) ; archives S42 de la vague 3 tirées (5.3) et déchiffrées en flux (5.12b) ; CT non privilégiés : coquille OpenTofu puis `pra/restaurer-labo.sh` ; CT 9020 (privilégié) et VM 106 : restauration root (`pct restore`, `qmrestore`) puis import dans l'état du labo ; démarrage dans l'ordre de `pra/perimetre.yaml` ; `./tofu-cible.sh labo plan` et plan de pve « No changes » ; depuis la VM 190, chaque service répond à son nom `.local` ; sorties dans `recettes/preuve-5.8b.log`
- statut : ÉTABLIE 2026-10-18 avec réserves (juge Sonnet GO avec réserves : recettes/verif-5.8b-juge.md ; preuves recettes/preuve-5.8b.log, recettes/preuve-5.8b-dechiffrement.log) ; 9 archives déchiffrées en flux (sha256 égaux, aucun clair sur le poste) ; CT 9020 et VM 106 restaurés sans coquille ; apply labo sur « oui » de l'admin : 1 imported, 7 added, 1 changed ; 7 restaurations forcées des coquilles neuves ; 17 CT + VM 106 running ; plans labo et pve « No changes » ; CI run 34 success ; réserves : (a) CT 119 restauré depuis S41 (archive S42 tronquée chez pCloud, 1 écart sur 135 par pra/controle-pcloud.sh), 7 jours de retard de données ; (b) capacité jugée sur l'usage mesuré (instantané, pas un pic) : limites déclarées 22,8 Go de RAM pour 16 Go et 172 Go de disque pour 186 Go, risque accepté de surengagement ; (c) montages liés vides (5.16)
- motif : D28 (1)
- source : feuilles 5.7, 5.8, 5.12b
- risque : moyen
- rôle : producteur ; marqueur `# AUTORISÉ-PAR-FRED` pour chaque `pct restore --force` du labo (accord de l'admin à citer)
- parallélisable : non
- nature : fonction
- brique : code 5.7b/5.7c + archives S42 → vague 3 en marche dans le labo · dépend de 5.7b, 5.12b (5.7c non retenue : VM 106 par qmrestore)

### Feuille 5.16 — Ce que la sauvegarde ne couvre pas : FOG, poste type, montages liés (D28 (4))
- preuve : tableau chiffré par élément (VM 110 système et 1,5 To d'images dont 92 Go occupés, VM 102 poste type 101 Go, /tank/miroir-apt 17,5 Go, /tank/iso-netboot 8,4 Go, /tank/scripts-http, /tank/partage/Fiches) : taille compressée mesurée, durée d'envoi pCloud estimée au débit mesuré, place pCloud restante, et voie de reconstruction sans sauvegarde (miroir apt retéléchargeable, images FOG refaites depuis le poste type, scripts dans Git) ; options et recommandation posées à l'admin ; décision consignée ; `recettes/etude-5.16.md`
- statut : manque (créée 2026-10-18, D28 (4))
- motif : relevé du 2026-10-18 : le MANIFESTE S42 ne contient ni la VM 110 ni la VM 102, et vzdump exclut les montages liés
- source : MANIFESTE-2026_10_18-02_59_03.txt ; proxmox/sauvegarde/sauvegarde-hebdo.sh
- risque : moyen
- rôle : producteur (étude) ; décision = l'admin
- parallélisable : oui
- nature : fonction
- brique : relevé des volumes → options chiffrées → décision de l'admin · dépend de 5.2
