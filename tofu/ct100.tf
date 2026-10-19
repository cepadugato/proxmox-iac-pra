# Feuille 1.6 : CT100 (wiki) importe (import-ct100.tf, id pve/100).
# Base : sortie de `-generate-config-out` relue a la main (fichier jetable, hors Git).
# Pieges traites : description decodee (%XX), hwaddr exact, snapshot parent autoup ignore
# (non gere ici), features (keyctl/fuse exigent root@pam) et password/template_file_id
# (non relisibles) en ignore_changes borne. Aucun apply sans accord (recettes/lance-1.6-apply.sh).
resource "proxmox_virtual_environment_container" "ct100" {
  node_name     = var.node
  vm_id         = 100
  description   = "Wiki DokuWiki — asso IP/ — Docker host (etape 4, deploy 2026-06-30)\n"
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
    keyctl  = var.features_root ? true : null
    fuse    = var.features_root ? true : null
  }

  initialization {
    hostname = "wiki"
    ip_config {
      ipv4 {
        address = "10.0.0.20/24"
        gateway = "10.0.0.254"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["100"]
  }

  operating_system {
    type             = "debian"
    template_file_id = var.template_file_id # non relisible apres creation
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      timeout_start,                        # defaut provider (deprecie), absent de l'etat importe
      features,                             # keyctl/fuse : root@pam requis, le jeton ne peut pas les ecrire
      operating_system[0].template_file_id, # non relisible
      initialization[0].user_account,       # password/cles : non relisibles
      vm_id,                                # l'import laisse vm_id vide dans l'etat ; la valeur de config sert a la recreation
    ]
  }
}
