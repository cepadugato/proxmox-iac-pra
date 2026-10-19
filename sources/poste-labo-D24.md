# Faits pour le lien poste ↔ labo (feuilles 5.14a, 5.14b, 5.6b), consultés le 2026-10-17

Lus par WebFetch (résumé de l'outil, citations reprises telles quelles) par le producteur le 2026-10-17. Niveau : documentation officielle de l'éditeur.

| # | Affirmation | Citation | URL | Consulté |
|---|---|---|---|---|
| 1 | `nft -c` valide un jeu de règles sans l'appliquer | « Check commands validity without actually applying the changes. » | https://www.netfilter.org/projects/nftables/manpage.html | 2026-10-17 |
| 2 | `flush ruleset` supprime TOUTES les tables, donc aussi `inet pra_poste` | « Clear the whole ruleset. Note that, unlike iptables, this will remove all tables and whatever they contain, effectively leading to an empty ruleset » ; « no packet filtering will happen anymore » | https://www.netfilter.org/projects/nftables/manpage.html | 2026-10-17 |
| 3 | `arping -D` : détection d'adresse dupliquée, code 0 si personne ne répond | « Duplicate address detection mode (DAD). See RFC2131, 4.4.1. » ; « Returns 0, if DAD succeeded i.e. no replies are received. » (iputils 20250605) | https://man7.org/linux/man-pages/man8/arping.8.html | 2026-10-17 |
| 4 | Certificat propre de l'API d'un nœud PVE : `/etc/pve/local/pveproxy-ssl.pem` et `.key` (clé sans phrase) ; le certificat par défaut `pve-ssl.pem` est signé par la CA `/etc/pve/pve-root-ca.pem` | « pveproxy uses /etc/pve/local/pveproxy-ssl.pem and /etc/pve/local/pveproxy-ssl.key » (résumé) | https://pve.proxmox.com/wiki/Certificate_Management | 2026-10-17 |
| 5 | La page ne dit pas quels noms ou IP porte le SAN du certificat par défaut | non trouvé | https://pve.proxmox.com/wiki/Certificate_Management | 2026-10-17 |

## Constats locaux (poste, 2026-10-17, lecture seule)
- `/etc/nftables.conf` l. 3 : `flush ruleset` ; `systemctl is-enabled nftables` = `disabled`.
- `command -v arping` vide (absent) ; `nmap`, `nc`, `python3`, `openssl` présents.
- `ip -br a` : Wi-Fi 10.0.0.21/24 et IPv6 globales 2a01:e0a:…, virbr0 192.168.100.1, virbr10 192.168.10.1, virbr1 192.168.200.1, ponts docker 172.17 à 172.23.0.1, ULA fc00:f853:ccd:e793::1 ; virbr-pra UP sans adresse.

## Non établi
- ifupdown2 (labo PVE 9) accepte deux lignes `address` sur vmbr0 : [hypothèse], constatée en 5.14b par `ip -br a`.
- Signature d'un certificat propre par la clé de la CA du labo (`/etc/pve/priv/pve-root-ca.key`) : [hypothèse], jouée en 5.6b.

## Sources
- https://www.netfilter.org/projects/nftables/manpage.html (2026-10-17)
- https://man7.org/linux/man-pages/man8/arping.8.html (2026-10-17)
- https://pve.proxmox.com/wiki/Certificate_Management (2026-10-17)
