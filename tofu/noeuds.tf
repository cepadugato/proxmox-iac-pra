# Feuille 1.5 : lecture seule. Data source bpg/proxmox 0.116.1 (docs/data-sources/virtual_environment_nodes.md).
# Aucune ressource geree.
data "proxmox_virtual_environment_nodes" "pve" {}

output "noeuds" {
  description = "Noms des noeuds Proxmox VE vus par l'API (lecture seule)."
  value       = data.proxmox_virtual_environment_nodes.pve.names
}
