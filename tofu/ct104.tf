# Feuille 5.7b (D28) : CT104 (minetest) decrit d'apres `pct config 104` (lecture seule) et importe (import-ct104.tf, id pve/104).
# Meme methode que ct108.tf (5.7a) : hwaddr exact, description decodee (%XX), snapshot parent non gere,
# features (root@pam), password/template_file_id non relisibles -> ignore_changes borne.
resource "proxmox_virtual_environment_container" "ct104" {
  node_name     = var.node
  vm_id         = 104
  description   = "Serveur de jeu Minetest/Luanti — asso IP (port 30000/udp)\n"
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

  initialization {
    hostname = "minetest"
    dns {
      servers = ["10.0.0.254"]
    }
    ip_config {
      ipv4 {
        address = "10.0.0.30/24"
        gateway = "10.0.0.254"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["104"]
    firewall    = true
  }

  operating_system {
    type             = "debian"
    template_file_id = var.template_file_id # non relisible apres creation
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      timeout_start,                        # defaut provider, absent de l'etat importe
      operating_system[0].template_file_id, # non relisible
      initialization[0].user_account,       # password/cles : non relisibles
      vm_id,                                # l'import laisse vm_id vide dans l'etat (cf. 1.6)
    ]
  }
}
