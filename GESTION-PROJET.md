# infra-as-code — Fiche de gestion de projet

> Association (anonymisée) · Famille : **Infra**
> Étape de cycle : **① Cahier des charges** · MAJ 2026-10-16
> Suivi machine : [`STATUS.md`](STATUS.md) · vue programme : [`../PORTEFEUILLE.md`](../PORTEFEUILLE.md)
> Détail des feuilles : [`ARBRE.md`](ARBRE.md) (`feuille.py ARBRE.md <id>`) · conception de la stack : [`CONCEPTION-STACK.md`](CONCEPTION-STACK.md)

## 1. Cahier des charges

### Contexte & besoin
L'hyperviseur `pve` porte les services de l'asso (CT 100 wiki, 101 demandes, 122 sondage, et d'autres) sans description rejouable : sa perte ne se répare que de mémoire. Le projet décrit ces CT dans du code OpenTofu (provider bpg/proxmox), le met en CI, et répète la reprise sur un Proxmox imbriqué du poste.

### Objectifs (le CDC, repris de `ARBRE.md`)
- **O1** — importer les CT 100, 101 et 122 jusqu'au plan vide (`tofu plan -detailed-exitcode` = 0).
- **O2** — un CT jetable de démonstration, créé, détruit puis recréé par le code, avec preuve d'identité.
- **O3** — état chiffré (PBKDF2 + AES-GCM) et plan automatique à chaque push dans une CI Forgejo.
- **O4** — PRA répété sur un Proxmox imbriqué du poste, réseau étanche, sauvegardes tirées de pCloud.

### Exigences fonctionnelles
- `tofu apply` n'est lancé que si le plan ne montre ni modification ni destruction d'un CT existant.
- Deux identités d'API distinctes (`tofu-ro@pve`, `tofu-rw@pve`), jamais root@pam.
- Aucun service ajouté sur pve : le runner de CI vit sur le poste.

### Contraintes
- **Libre = éliminatoire** · sobriété · souveraineté (OpenTofu, Forgejo, PVE sont libres ; pCloud est un stockage existant de l'asso).
- Rien n'est écrit sur pve avant la porte de la feuille concernée ; les gestes irréversibles sont ceux de l'admin.

### Nommage & adressage
Sans objet : le projet n'expose aucun service sur le réseau (les CT importés gardent leurs noms `.local`). Le tunnel `ssh -L 127.0.0.1:8006` du poste (feuille 1.7) n'est pas un service de l'asso.

### Secrets & comptes
Secrets créés ou utilisés, par leur NOM (valeurs au coffre ou dans le noyau d'amorçage L5, jamais ici) : jeton `tofu-ro@pve`, jeton `tofu-rw@pve`, phrase de chiffrement de l'état, secrets de CI Forgejo (`FORGEJO_READ` et les jetons de 4.6), accès pCloud (remote `pcloud-pra`), phrase GPG des sauvegardes. Rangement : coffre Vaultwarden ou noyau L5 selon la dépendance (D7, D12), inscrits à `../coffre-mdp/L0-inventaire-gabarit.md`. `.claude/garde.yml` bloque leur écriture en clair.

### Critères d'acceptation
- O1 : plan vide sur les trois CT après une vraie vie du système (feuille 2.4).
- O2 : CT recréé identique à l'original (feuille 3.6).
- O3 : job vert propre, rouge sur dérive (feuille 4.8).
- O4 : répétition chronométrée, procédure suivie par un autre que son rédacteur (feuille 5.10).
- Aucun secret en clair dans le dépôt ni au wiki.

### Périmètre / hors-périmètre
- **Dans** : CT 100, 101, 122 ; CT jetable ; PRA des CT du périmètre (vagues V1 et V2, D6 amendée par D13).
- **Hors** : VM 106 et 110 (vague 3 ultérieure) ; VM de test ; exposition d'un service.

## 2. Étude comparative

Les options ont été débattues feuille par feuille (questions D3, D4, D5, D7, D8, D9 de `ARBRE.md`). Faits externes : [`sources/SOURCES.md`](sources/SOURCES.md) et ses fiches.

| Décision | Choix | Écartée |
|---|---|---|
| D1 lieu du labo | Proxmox imbriqué KVM sur le poste, réseau étanche | labo sur pve |
| D3 runner CI | sur le poste, tunnel `ssh -L 8006` | LXC dédié sur pve |
| D4 état OpenTofu | fichier local chiffré, hors Git | état versionné, backend distant |
| D5/D16 droits d'API | deux utilisateurs bornés, `features` en `ignore_changes` | jeton root@pam |
| D7/D12 circularité du coffre | noyau d'amorçage hors ligne L5 | rien |
| D8bis sauvegardes | `.gpg` tirés de pCloud par rclone, déchiffrés dans le labo | clair rapatrié |
| D9 dépôt | `git/infra-as-code` dédié, exclu du binder | sous-dossier de `git/IP` |
| D11 Forgejo | montée 14.0.3 vers 15.0 LTS avant le runner | rester en 14 (fin de vie 2026-04-30) |

**Décision :** stack OpenTofu 1.13.1 + bpg/proxmox 0.116.1 ; liste complète D1 à D17 dans `ARBRE.md`.

## 3. Réalisé
- Relevé de l'existant : [`recettes/releve-etape1.md`](recettes/releve-etape1.md).
- Arbre de 42 feuilles, porte 1 GO au passage 3 : [`recettes/porte1-passage3.md`](recettes/porte1-passage3.md).
- Fiches de faits (sources) : `sources/` ; stack /projet : skills, garde.yml, settings.json, tests des motifs (2026-10-16).
- Rien d'installé ni d'écrit sur pve.

## 4. Où ça en est / reste à faire
**Étape ① Cahier des charges.**
- ⏳ Feuille 1.1 : OpenTofu sur le poste. Puis 1.2 à 1.7, import du CT 100.
- ⏳ Gestes de l'admin : 1.4, 3.2, 4.2, 4.6, 4.9, 4.10, 5.13 ; marqueur sur 3.5 et 5.8.

## Sources
- Faits externes, URL et dates de consultation (2026-10-16) : [`sources/SOURCES.md`](sources/SOURCES.md), `sources/privileges-jeton.md`, `sources/ci-forgejo.md`, `sources/pra-faits.md`, `sources/rclone-pcloud-et-depot.md`, `sources/destroy-et-jeton-forgejo.md`.
- Versions citées : OpenTofu 1.13.1 (https://api.github.com/repos/opentofu/opentofu/releases/latest), bpg/proxmox 0.116.1 (https://api.github.com/repos/bpg/terraform-provider-proxmox/releases/latest), consultées le 2026-10-16.
