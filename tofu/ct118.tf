# Feuille 5.7b (D28) : CT118 (captures) decrit d'apres `pct config 118` (lecture seule) et importe (import-ct118.tf, id pve/118).
# Meme methode que ct108.tf (5.7a) : hwaddr exact, description decodee (%XX), snapshot parent non gere,
# features (root@pam), password/template_file_id non relisibles -> ignore_changes borne.
resource "proxmox_virtual_environment_container" "ct118" {
  node_name     = var.node
  vm_id         = 118
  description   = "Captures d ecran de la doc wiki (IP/wiki) - shot-scraper + Chromium headless. Cree le 2026-08-14.\n"
  unprivileged  = true
  start_on_boot = true
  started       = var.labo_started

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  cpu {
    architecture = "amd64"
    cores        = 2
  }

  memory {
    dedicated = 2048
    swap      = 512
  }

  disk {
    datastore_id = var.datastore
    size         = 8
  }

  features {
    nesting = true
  }

  initialization {
    hostname = "captures"
    dns {
      servers = ["10.0.0.254"]
    }
    ip_config {
      ipv4 {
        address = "10.0.0.26/24"
        gateway = "10.0.0.254"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["118"]
  }

  operating_system {
    type             = "debian"
    template_file_id = var.template_file_id # non relisible apres creation
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      timeout_start,                        # defaut provider, absent de l'etat importe
      features,                             # root@pam requis pour ecrire les features
      operating_system[0].template_file_id, # non relisible
      initialization[0].user_account,       # password/cles : non relisibles
      vm_id,                                # l'import laisse vm_id vide dans l'etat (cf. 1.6)
    ]
  }
}
