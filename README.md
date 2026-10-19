# proxmox-iac-pra

Infrastructure as Code et plan de reprise d'activité (PRA) pour le serveur Proxmox VE d'une association.
Le serveur, ses 16 conteneurs LXC et sa VM sont décrits par du code OpenTofu. Une seule commande les reconstruit sur une autre machine.

> Version publique **anonymisée** d'un projet réel en production. Noms, domaine, adresses IP, adresses MAC et
> identifiants ont été remplacés par des valeurs fictives (`10.0.0.0/24`, `example.org`, `02:00:00:…`).
> Les journaux de preuve, l'état chiffré et la configuration des agents ne sont pas publiés.

## Résultat

Le PRA a été prouvé **en réel le 2026-10-19** :
- **Point de départ :** un PC neuf avec Proxmox fraîchement installé.
- **Commande :** `bash pra/secours.sh <ip>`, sans aucun arrêt pendant le déroulé.
- **Durée :** 111 min, gestes humains compris.
- **Contrôle automatique :** 35/35 contrôles applicatifs verts. La comparaison complète avec la production
  (invités, configurations, services, ports, minuteries, données) ne montre que des écarts attendus.
- **Recette humaine :**
  - toutes les applications testées ;
  - une image système déployée par FOG sur un PC physique ;
  - l'accès depuis Internet par le portail, avec authentification Authelia (2FA).

Avant ce test, le PRA avait été répété sur un Proxmox imbriqué (KVM dans KVM), isolé du réseau de production.

## Ce que montre le projet

| Domaine | Mise en œuvre |
|---|---|
| IaC | OpenTofu 1.13 + provider `bpg/proxmox` 0.116.1. CT existants **importés** sans les recréer (blocs `import`), plan « No changes » vérifié. |
| Sécurité de l'état | État chiffré nativement par OpenTofu (PBKDF2 + AES-GCM). Phrase de chiffrement gardée en mémoire de session, jamais sur disque. |
| Garde-fous | Verrou de cible (`tofu/verrou.tf`) : un `terraform_data` en `prevent_destroy` + une précondition. Un plan qui croise l'état d'une cible et l'endpoint d'une autre échoue (tests : `tests/test-verrou.sh`). |
| Moindre privilège | Jetons API Proxmox dédiés (lecture / écriture), ACL minimales, TLS vérifié par CA épinglée. |
| CI | Forgejo Actions : un `tofu plan` à chaque push, rouge en cas de dérive entre le code et la production. |
| PRA | Sauvegardes vzdump chiffrées hors site (rclone), déchiffrées sur le poste d'administration : la clé ne quitte jamais le poste. Restauration ordonnée en vagues, puis bascule d'adresse IP une fois la production débranchée. |
| Reprise sur incident | Chaque étape est idempotente : relancer la même commande reprend là où elle s'est arrêtée. |
| Tests | Suite shell (`tests/run.sh`) : verrou, aiguillage des cibles, scan de secrets, MAC, transferts d'archives. API Proxmox simulée par `tests/outils/api-factice.py`. |

## Organisation

```
tofu/          code OpenTofu : provider, CT (ct*.tf), imports, verrou, chiffrement de l'état
tofu-cible.sh  point d'entrée unique : choisit la cible (pve | labo | secours) et contrôle endpoint, nœud, jeton et TLS avant tout plan
pra/           scripts du PRA ; secours.sh = la commande de bout en bout ; PROCEDURE-PRA.md = la procédure humaine
tests/         tests automatisés
sources/       faits techniques sourcés et datés (documentation officielle consultée)
ARBRE.md       décomposition du projet en briques testables, avec les décisions tracées
```

## Méthode

Le projet a été conduit avec des agents IA (Claude Code), dans un cadre de travail strict :
- chaque brique a un critère de preuve défini avant d'être construite ;
- celui qui produit ne juge pas son propre travail : un relecteur contradicteur, sur un autre modèle, s'en charge ;
- toute action destructive ou irréversible exige l'accord explicite de l'administrateur ;
- les secrets ne passent jamais par le dépôt ni par la conversation.

`ARBRE.md` et `CONCEPTION-STACK.md` en gardent la trace.

Projet en français, comme la documentation destinée aux bénévoles de l'association.
