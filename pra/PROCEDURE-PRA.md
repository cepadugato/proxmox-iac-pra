# Procédure PRA : remettre les services de pve sur un autre Proxmox

But : si pve est perdu, faire tourner les services de l'asso sur un autre serveur, **avec les mêmes adresses**, depuis
les sauvegardes chiffrées de pCloud. Répétée sur le labo imbriqué (feuille 5.10) ; cible réelle « secours » (feuille 5.15).

Légende : 👤 = geste de l'admin · 💻 = commande sur le poste, dans `IP/infra-as-code` · ⏱ = durée mesurée en répétition.

## Version courte (3 gestes)

1. 👤 Installer Proxmox sur le serveur (§ 1 ci-dessous), noter son adresse `<IP>` et l'empreinte affichée à son écran.
2. 👤 Sur le poste, dans `IP/infra-as-code` : **`bash pra/secours.sh <IP>`**. Le script enchaîne les § 2 à 6 et ne
   s'arrête que pour : le mot de passe root du serveur (une fois), le mot de passe du noyau KeePassXC (une fois),
   « oui » avant de créer les coquilles, puis **« câble de pve débranché ? »** au moment de la bascule.
   Interrompu ? Relancer la même commande : ce qui est fait est sauté.
3. 👤 Tester au navigateur depuis un PC de l'asso.

Retour arrière : `bash pra/secours.sh --retour`, puis rebrancher pve. Le détail ci-dessous sert en cas de panne d'une étape.

## 0. Avant de partir (la veille)

- 💻 `bash pra/controle-pcloud.sh` : toutes les archives chez pCloud sont-elles intactes ? (un écart = prendre la semaine d'avant pour ce CT)
- 💻 `bash pra/tirer-pcloud.sh --tirer` : archives chiffrées du dernier passage sur le poste (`~/pra-tirage/<passage>`), sha256 vérifiés.
  Elles restent chiffrées : le poste peut voyager avec.
- 💻 `bash pra/verifs.sh --reference` : référence des services de pve (ports, titres de pages) tant que pve vit.
- 💻 `bash pra/comparer-pile.sh --reference` : référence de toute la pile de pve (invités, configurations, services en marche
  dans chaque CT, ports, minuteries de l'hôte, dossiers liés).
- 💻 `bash recettes/sauver-fog-partage.sh` : FOG (système + images en service), partage de l'hôte, automatisation de l'hôte
  (scripts, minuteries, courriel, scripts HTTP) et paquets hors ligne, chiffrés dans `~/pra-tirage/2026-S42-fog`.
- 👤 Le poste emporte : ce dépôt, `~/pra-tirage`, `~/.ssh/pra-secours`, `~/.config/infra-as-code/` (jetons, empreintes),
  l'ISO Proxmox (`/srv/data/ISO/proxmox-ve_9.2-1.iso`) et une clé USB pour la graver.

## 1. Installer Proxmox sur le serveur de secours 👤 (⏱ ~15 min)

1. Démarrer sur la clé USB, « Install Proxmox VE (Graphical) », disque par défaut (ext4, LVM).
2. Pays France, mot de passe root (le noter dans le coffre), e-mail de l'asso.
3. Réseau : nom **`pve-secours.lan.example`** (pas « pve » : la production s'appelle ainsi) ; garder l'adresse proposée
   par le DHCP de la box (ex. 10.0.0.1xx), passerelle et DNS 10.0.0.254. **Noter cette adresse = `<IP>`.**
4. Après redémarrage, à l'écran du serveur, en root : `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` → noter l'empreinte.

pve est toujours branché : rien de ce qui suit ne prend une adresse de production avant l'étape 6.

## 2. Ouvrir l'accès du poste 👤 (⏱ 2 min)

Sur le poste (branché au réseau de l'asso) :

    ssh-copy-id -i ~/.ssh/pra-secours.pub -o IdentitiesOnly=yes -o UserKnownHostsFile=~/.ssh/known_hosts-pra-secours root@<IP>

Comparer l'empreinte proposée à celle de l'étape 1.4 **avant** de répondre « yes », puis taper le mot de passe root.
Puis 👤 `bash phrase-session.sh charger` (mot de passe du noyau KeePassXC : phrase d'état + clé GPG en mémoire, 8 h).

## 3. Préparer le serveur 💻 (⏱ ~3 min)

    bash pra/secours-preparer.sh <IP>          # lecture seule : relevé, stockage retenu, certificat
    bash pra/secours-preparer.sh <IP> --oui    # ponts vmbr1/vmbr2, dossiers liés, gabarit, jeton, CA, secours.tfvars, empreinte, init

Toutes les commandes suivantes visent le secours : **`export PRA_CIBLE=secours`** dans le terminal.

## 4. Restaurer, services arrêtés 💻 (⏱ voir tableau)

    export PRA_CIBLE=secours                            # dans CHAQUE terminal utilisé (sinon les scripts visent le labo)
    bash pra/perimetre.sh                               # archives au MANIFESTE ; ses seuils de capacité sont ceux du LABO :
                                                        # comparer à la main au relevé df/free/pvesm de secours-preparer.sh
    bash pra/archives-vers-labo.sh --oui                # déchiffrement EN FLUX vers le secours (la clé ne quitte pas le poste)
    bash pra/restaurer-labo.sh --oui 9020 106           # CT privilégié et VM : restaurés directement
    cp tofu/import-ct9020.tf.importe tofu/import-ct9020.tf
    ./tofu-cible.sh secours plan                        # attendu : N to add, 1 to import (9020), 0 to change, 0 to destroy
    ./tofu-cible.sh secours apply                       # coquilles des CT (arrêtées : labo_started = false)
    rm tofu/import-ct9020.tf
    bash pra/restaurer-labo.sh --oui 100 101 104 108 114 115 117 118 119 120 121 122 123 128 129
                                                        # restauration forcée des coquilles neuves (accord de l'admin, marqueur)

À ce stade, tout est restauré et **arrêté** : aucun conflit avec pve.

## 5. Bascule 👤 puis 💻 (⏱ ~3 min)

1. 👤 **Débrancher le câble réseau de pve** (ne pas l'éteindre : on peut revenir en arrière en le rebranchant).
2. 💻 `PRA_CIBLE=secours bash pra/secours-basculer.sh` : vérifie que 10.0.0.10 ne répond plus.
3. 💻 `PRA_CIBLE=secours bash pra/secours-basculer.sh --oui` : le secours prend 10.0.0.10 **en plus** de `<IP>`, démarre les services
   dans l'ordre (coffre, annuaire, portail… puis le reste, Snipe-IT en dernier), puis plan tofu « No changes ».

## 6. Vérifier 💻 👤 (⏱ ~2 min)

- 💻 `PRA_CIBLE=secours bash pra/verifs.sh` : ports et titres de pages comparés à la référence de pve
  (Authelia du CT 121 ne démarre qu'avec Internet).
- 💻 `PRA_CIBLE=secours bash pra/comparer-pile.sh` : toute la pile comparée à pve, écart par écart.
- 💻 `PRA_CIBLE=secours bash pra/essai-urls.sh` : URL profondes (miroir, scripts HTTP, cache apt, FOG, applications)
  comparées à pve, à l'octet près pour les fichiers statiques (pve encore joignable seulement).
- 👤 Partage : `smb://pve.local/partage` depuis un poste. FOG : démarrer un vrai PC en réseau, le menu FOG doit paraître.
- 👤 Accès depuis Internet avec 2FA : depuis un téléphone en 4G (Wi-Fi coupé), `https://portail.example.org` → page
  Authelia → identifiant + code TOTP → services. Configuration d'Authelia, base des inscriptions TOTP, sites nginx et
  certificats : identiques à pve à l'empreinte près (relevé du 2026-10-18 au labo, 68 fichiers des CT 121 et 128).
- Sans Internet (labo), Authelia ne démarre pas, et LLDAP et le gestionnaire de mise à jour Mint semblent cassés : leurs
  pages chargent Bootstrap et des polices sur des CDN, et le cache apt revérifie les index Ubuntu en amont.
- 💻 Ménage : `PRA_CIBLE=secours bash pra/lib-ssh-labo.sh 'find /root/pra/clair -type f -delete'` (23 Go d'archives en clair).
- 👤 Depuis un PC de l'asso, au navigateur : wiki, coffre (`https://coffre.local`), annuaire, portail, sondages, Snipe-IT.

## Piège connu : refaire une cible déjà utilisée

Détruire un invité avec `--purge` retire aussi les droits du jeton sur `/vms/<id>` : le plan OpenTofu échoue alors en
« Permission check failed (/vms/<id>, VM.Audit) ». Remède : `PRA_CIBLE=<cible> bash pra/labo-jeton.sh --oui`
(répétition du 2026-10-18). Sur un serveur neuf, `secours-preparer.sh` pose ces droits avant les invités.

## Retour arrière

💻 `PRA_CIBLE=secours bash pra/secours-basculer.sh --retour --oui` : arrête tous les invités du secours et lui retire
10.0.0.10 (sinon, au redémarrage, ses CT reprendraient les adresses de pve). Puis 👤 **rebrancher pve**.
Rien n'a été modifié sur pve. Plan du CT 9020 : s'il annonce autre chose que « 1 to import » pour lui, ne pas répondre
« yes » et le signaler.

## Ce que le secours ne rend PAS (connu, feuille 5.16)

- **FOG (VM 110)** : rendu (`pra/fog-partage.sh`), avec les seules images Emmaus-Autotest et Mint-Testing ; les autres
  images restent listées dans FOG mais leur déploiement échoue. Disque d'images de 100 Go au lieu de 1,5 To.
  Prouvé au labo le 2026-10-18 par l'admin : déploiement d'une VM par FOG, script de premier démarrage tiré du miroir et
  script de fiche exécutés, partage `smb://pve.local/partage` ouvert en anonyme.
- **Partage de l'hôte** (`/tank/partage`, SMB invité + NFS, nom `pve.local`) : rendu (`pra/fog-partage.sh`).
- **Automatisation de l'hôte** (12 minuteries, cron de sauvegarde, courriel sortant, fail2ban, mises à jour) : rendue
  (`pra/hote-auto.sh`), activée seulement après la bascule, coupée au retour arrière.
- **Le poste type (VM 102)** : pas dans la sauvegarde.
- **Miroir apt (18 Go), ISO (8,4 Go) et pilotes (1,3 Go) de netbootxyz** : dans aucune sauvegarde ; `secours.sh` les copie
  de pve tant qu'il est branché (`pra/copier-donnees-liees.sh`). pve perdu : dossiers vides, à re-télécharger.
  Les scripts HTTP (1,6 Mo) sont, eux, dans l'archive chiffrée de l'automatisation de l'hôte.
- Services de base de pve absents d'un Proxmox neuf : rsyslog, anacron, winbind (relevé `comparer-pile.sh`).
- **Authelia (CT 121) exige Internet au démarrage** (contrôle du serveur de mail smtp.example.net) : sans Internet, il s'arrête.
- **CT 119 (freshrss)** : l'archive S42 avait été trouvée tronquée chez pCloud ; réparée le 2026-10-18
  (`recettes/preuve-reparation-119.log`) et retirée sur le poste. La répétition du labo avait utilisé S41.
- Les sauvegardes faites par le secours lui-même ne sont pas configurées (`proxmox/sauvegarde` à réinstaller si le secours dure).

## Durées mesurées (répétition du 2026-10-18 sur le labo)

Labo nu → services rendus : **31 min** (`recettes/preuve-5.10-repetition.log`), poste et labo sur la même machine.

| Étape | Durée |
|---|---|
| Contrôle du périmètre | < 1 min |
| Déchiffrement en flux de 17 archives (23 Go) | 7 min |
| CT 9020 + VM 106 (sans coquille) | 5 min |
| 15 coquilles OpenTofu | 3 min |
| 15 restaurations forcées | 12 min |
| Démarrage ordonné + plan « No changes » | 2 min |
| Contrôle des services (34/35 ; Authelia : pas d'Internet au labo) | 2 min |

Sur un vrai serveur de l'asso, le déchiffrement passe par le réseau local (Wi-Fi du poste ?) : prévoir plus long si le
poste n'est pas en filaire. Ajouter l'installation de Proxmox (~15 min) et la préparation (~5 min) : **~1 h au total**.
