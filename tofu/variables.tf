variable "proxmox_endpoint" {
  description = "URL de l'API Proxmox VE (ex. https://pve.example:8006/). Aucune valeur par defaut : fournie par TF_VAR_proxmox_endpoint ou un fichier .tfvars non versionne."
  type        = string
}

variable "proxmox_insecure" {
  description = "Accepter un certificat TLS non reconnu (certificat interne de pve)."
  type        = bool
  default     = false
}

# Feuille 5.6a (D24) : le même code sert pve et le labo ; seules ces valeurs changent (pve.tfvars / labo.tfvars,
# choisis par ../tofu-cible.sh). Les défauts sont ceux de pve : un plan sans -var-file reste identique à avant 5.6a.
variable "node" {
  description = "Nom du noeud Proxmox qui porte les CT (pve = « pve », labo = « pra-lab »)."
  type        = string
  default     = "pve"
}

variable "datastore" {
  description = "Stockage du rootfs des CT (pve = « tank » ; labo = « local », feuille 5.5)."
  type        = string
  default     = "tank"
}

variable "labo_started" {
  description = "Etat de demarrage voulu des CT (true sur pve ; false dans le labo : demarrage par la feuille de reprise)."
  type        = bool
  default     = true
}

# Décision D25 (5.6a) : verrou de cible dans le code. Chaque .tfvars déclare sa cible ; verrou.tf la grave dans l'état.
# Un plan qui croise l'état d'une cible et le .tfvars de l'autre exige de remplacer le verrou, ce que prevent_destroy refuse.
variable "cible" {
  description = "Cible du plan : pve ou labo (fixée par pve.tfvars / labo.tfvars, jamais à la main)."
  type        = string
  default     = "pve"

  validation {
    condition     = contains(["pve", "labo", "secours"], var.cible)
    error_message = "cible doit valoir pve, labo ou secours."
  }
}

# Répétition du PRA secours sur le labo : posée par tofu-cible.sh seulement (cible secours, adresse du labo, PRA_REPETITION_LABO=1).
variable "repetition_labo" {
  description = "true : la cible secours est le labo imbriqué (répétition) ; son endpoint est alors exigé, et lui seul."
  type        = bool
  default     = false
}

# Feuille 5.7a (D26) : gabarit de creation des CT. Non relisible apres creation (ignore_changes) : sert seulement a une recreation
# (PRA). Vide sur pve (CT importes) ; labo.tfvars donne le gabarit present dans le stockage du labo.
variable "template_file_id" {
  description = "Gabarit LXC pour (re)creer un CT, ex. local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst. Vide = CT importe, jamais recree."
  type        = string
  default     = ""
}

variable "features_root" {
  description = "keyctl et fuse des CT (reservees a root@pam). true sur pve (deja poses, ignore_changes) ; false pour une cible ou le jeton cree la coquille : pct restore les remet."
  type        = bool
  default     = true
}

variable "macs" {
  description = "MAC par VMID (eth0) et par \"<VMID>-eth1\" (seconde carte). Defaut : celles de pve. Une cible peut les surcharger par <cible>.macs.tfvars, ecrit par pra/relever-macs.sh."
  type        = map(string)
  default = {
    "100" = "02:00:00:00:00:04"
    "101" = "02:00:00:00:00:05"
    "108" = "02:00:00:00:00:06"
    "114" = "02:00:00:00:00:07"
    "121" = "02:00:00:00:00:08"
    "122" = "02:00:00:00:00:09"
    "123" = "02:00:00:00:00:0A"
    "128" = "02:00:00:00:00:0B"
    # vague 3 (feuille 5.7b, D28)
    "104"  = "02:00:00:00:00:0C"
    "115"  = "02:00:00:00:00:0D"
    "117"  = "02:00:00:00:00:0E"
    "118"  = "02:00:00:00:00:0F"
    "119"  = "02:00:00:00:00:10"
    "120"  = "02:00:00:00:00:11"
    "129"  = "02:00:00:00:00:12"
    "9020" = "02:00:00:00:00:13"
    # seconde carte (pont PXE interne)
    "117-eth1"  = "02:00:00:00:00:14"
    "9020-eth1" = "02:00:00:00:00:15"
  }
}
