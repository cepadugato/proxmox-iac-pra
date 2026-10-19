# Conception de la stack infra-as-code (étape 4, 2026-10-16)

Conception seule : rien n'est fabriqué ici (étape 5). Porte 1 : GO au passage 3 (`recettes/porte1-passage3.md`). Chaque élément cite sa feuille (YAGNI). Sorties de `bibliotheque.py` rejouées le 2026-10-16 avec `--projet IP/infra-as-code`.

## Tableau

| Élément | Feuilles | Décision | Sortie de `bibliotheque.py` |
|---|---|---|---|
| Skill `opentofu-proxmox` | 1.2, 1.5, 1.6, 2.1, 2.2, 3.3, 3.5, 4.3, 5.6 | CRÉER | « opentofu terraform proxmox » : `aucune brique existante … → création justifiée`. |
| Skill `pra-labo-proxmox` (PRA, rclone/pCloud inclus) | 5.1 à 5.13 | CRÉER | « PRA restauration sauvegarde labo » : `aucune brique existante`. « rclone pcloud » : `aucune brique existante`. |
| CI Forgejo : aucun skill, simple fiche `reference/ci-forgejo.md` du skill 1 | 4.1, 4.5, 4.6, 4.7, 4.8 | ADAPTER la fiche existante `sources/ci-forgejo.md` (copie de référence, pas de skill) | « forgejo actions runner CI » : seulement `dotenvx`, `figma-use` (hors sujet). |
| Méthode de test des scripts : `superpowers:test-driven-development` | 1.3, 2.3, 4.3, 4.7, 5.2, 5.6, 5.13 | RÉUTILISER (plugin installé, déjà nommé dans les feuilles) | « verifier plan oracle drift » : `executing-plans`, `writing-plans`, … rien sur tofu ; la méthode TDD vient de l'arbre. |
| `garde.yml` | 1.3, 3.2, 3.5, 4.2, 4.6, 5.13 | CRÉER, motif du `garde.yml` d'edr | « garde destruction hooks » : `meta-hook` (global), `hook-development` (plugin) : savoir-faire seulement, les 4 hooks du socle sont déjà en place. |
| `settings.json` du projet (4 hooks, ledger-tracker, pre/postcompact, `"advisorModel": "opus"`) | feuilles à risque fort : 1.2, 1.4, 3.2, 3.4, 3.5, 3.6, 4.1, 4.5, 4.6, 4.9, 5.1 | CRÉER depuis le gabarit de l'usine | Même requête : `usine` (global) est la brique. |
| Scripts du dépôt de code (`tests/scan-secrets.sh`, `verifier.sh`, `tofu-cible.sh`, `publier-etat-ci.sh`, `pra/*.sh`) | 1.3, 2.3, 4.7, 5.2, 5.6, 5.13 | HORS STACK : livrables des feuilles, écrits par le producteur pendant l'exécution. La stack ne fait que les brancher dans `garde.yml` (`verifications`). | « verifier plan oracle drift » : aucun script tofu existant ; style repris de `parc-as-code/tests/run.sh` (cité dans ARBRE ligne 10). |
| MCP | aucune | AUCUN | SOURCES §7 : MCP HashiCorp et OpenTofu secondaires ou non vérifiés, MCP Proxmox officiel « non trouvé » ; documentation seulement dans `reference/`. |
| Agents d'exception | aucune | AUCUN | Les 6 rôles génériques suffisent : producteur (Bash, Write), connecteur (Bash : ssh pve, curl API Forgejo, virsh, rclone), verificateur (Bash), chercheur-sources (WebFetch), contradicteur, orchestrateur. Aucun besoin d'outil absent. |
| `ETAT.md`, `JOURNAL.md`, `CLAUDE.md` ≤ 30 lignes | toutes (suivi) | CRÉER depuis `templates/` (étape 5) | `usine` (global). |

## Contenu prévu des éléments à créer

**Skill `opentofu-proxmox`** (`SKILL.md` < 500 mots, description en « Use when… » sans résumé du workflow) :
- `reference/methode-import.md` : import jusqu'au plan vide, `ignore_changes` borné (`features`, 5.6), oracle `plan -detailed-exitcode` (0 vide, 1 erreur, 2 écart), source SOURCES §1 et §6.
- `reference/pieges-bpg.md` : version épinglée bpg 0.116.1, flags `features` réservés à root@pam, empreinte TLS, état chiffré PBKDF2 + AES-GCM avec chemin unique `etat/pve.tfstate` (4.3, SOURCES §4).
- `reference/privileges.md` : copie de référence de `sources/privileges-jeton.md` (1.2, 1.4, 3.2), rôles `TofuCT`, jetons privsep=1, deux utilisateurs distincts (D16).
- `reference/ci-forgejo.md` : runner du poste, label `host`, `push` seul, secrets de dépôt (4.1 ; `sources/ci-forgejo.md` et `destroy-et-jeton-forgejo.md`).
- Pas de `scripts/` au départ : les scripts exécutables sont du code du dépôt (tableau). Un script n'entre dans le skill que s'il sert à deux feuilles ou plus après fabrication.

**Skill `pra-labo-proxmox`** : méthode du labo imbriqué (étanche, transfert par disque virtuel, restauration `pct restore`), ordre V1/V2 lu dans `pra/perimetre.yaml` (un seul ordre), lecture seule de pCloud par liste blanche de sous-commandes rclone, pièges (`--force`, MAC, dossier de déchiffrement). Références : `sources/pra-faits.md`, `sources/rclone-pcloud-et-depot.md`. Chargé par les seules feuilles 5.x.

**`garde.yml`** (marqueur `# AUTORISÉ-PAR-FRED`) :
- `livrables` : `ARBRE.md`, `sources/**/*.md`, `CONCEPTION-STACK.md` exclu (faits locaux, comme edr) ; `recettes/**` exclu.
- `destruction_extra` (feuilles 3.5, 5.8) : `tofu[[:space:]]+destroy`, `apply[^|;]*-destroy`, `tofu[^|;]*-target[^|;]*(pve|proxmox_virtual_environment)`, `pct[[:space:]]+destroy`, `qm[[:space:]]+destroy`, `pct[[:space:]]+restore[^|;]*--force`, `rclone[[:space:]]+(sync|delete|purge|move)`. Conséquence voulue : la destruction du CT jetable (3.5) et le `--force` du labo (5.8) exigent le marqueur humain de l'admin.
- `secrets_extra` (feuilles 1.3, 3.2, 4.2, 4.6, 5.13), motifs ancrés sur le nom de la clé pour ne pas bloquer les sorties de `sha256sum` : `PVEAPIToken=[^[:space:]]+![^[:space:]]+=[0-9a-f-]{36}`, UUID de secret de jeton après `secret`/`token_secret`, `(TOFU_ENC_PASSPHRASE|passphrase)[[:space:]]*[:=][[:space:]]*["']?[^[:space:]"'$]{8,}`, jeton Forgejo (`FORGEJO_(TOKEN|READ)[[:space:]]*[:=][[:space:]]*["']?[0-9a-f]{40}`), `rclone.conf` (`^(token|pass|client_secret)[[:space:]]*=` ), clé privée PEM.
- `verifications` : `tests/scan-secrets.sh` sur `tofu/**` et `recettes/**` (1.3).
- `jev` : non (état partant vers un tiers, et les feuilles touchent des secrets d'infra).

**`settings.json`** : hooks génériques (garde-sources, ledger-tracker, garde-secrets, garde-destruction, journal-etat, precompact/postcompact), `"advisorModel": "opus"`. Consigne de brief : le conseiller n'est consulté qu'une fois, au début, sur les feuilles à risque fort listées ci-dessus.

## Ce qui reste à la charge de l'admin ou ouvert
- [hypothèse] Les motifs de `destruction_extra` couvrent tous les chemins de destruction : à prouver à l'étape 5 par un test rouge de chaque motif (commande d'essai refusée sans marqueur, acceptée avec).
- [hypothèse] Le jeton d'un `-target` écrit en plusieurs mots (`-target=…` placé avant `destroy`) est capté par les motifs : même test.
- Geste de l'admin : accepter le marqueur sur 3.5 et 5.8 ; aucune installation de skill du catalogue n'est proposée.
- Ordre d'exécution de la fabrication (étape 5) : `garde.yml` et `settings.json` d'abord (ils protègent les feuilles à risque fort), puis `opentofu-proxmox`, puis `pra-labo-proxmox` (seulement avant 5.1).
