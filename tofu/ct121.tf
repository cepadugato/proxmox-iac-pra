# Feuille 5.7a (D26) : CT121 (heimdall) decrit d'apres `pct config 121` (lecture seule) et importe (import-ct121.tf, id pve/121).
# Meme methode que ct100/ct101/ct122 (feuille 1.6) : hwaddr exact, description decodee (%XX), snapshot parent autoup non gere,
# features (root@pam), password/template_file_id non relisibles -> ignore_changes borne.
resource "proxmox_virtual_environment_container" "ct121" {
  node_name     = var.node
  vm_id         = 121
  description   = "Heimdall - annuaire des services de l'asso (projet IP/portail). Interface : http://heimdall.local\n"
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
    dedicated = 1024
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
    hostname = "heimdall"
    dns {
      servers = ["10.0.0.254"]
    }
    ip_config {
      ipv4 {
        address = "10.0.0.32/24"
        gateway = "10.0.0.254"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["121"]
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
