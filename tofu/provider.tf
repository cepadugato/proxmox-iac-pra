# Le jeton d'API n'est JAMAIS dans un fichier : il vient de l'environnement
# (variable PROXMOX_VE_API_TOKEN, lue par le provider bpg/proxmox).
provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure
}
