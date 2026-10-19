# Feuille 2.2 : CT122 (sondage, Pollaris) importe (import-ct122.tf, id pve/122). Meme methode que ct100/ct101.
# CT122 porte des DONNEES REELLES : prevent_destroy = true, ne jamais le recreer.
# Specifique : 2 coeurs, 2048 Mo, swap 512, rootfs 12G, nameserver 10.0.0.254, nesting seul, pas de description pve.
# Pieges traites comme CT100/CT101 : hwaddr exact, snapshot parent autoup non gere, features (root@pam),
# password/template_file_id non relisibles -> ignore_changes borne.
resource "proxmox_virtual_environment_container" "ct122" {
  node_name     = var.node
  vm_id         = 122
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
    size         = 12
  }

  features {
    nesting = true
  }

  initialization {
    hostname = "sondage"
    dns {
      servers = ["10.0.0.254"]
    }
    ip_config {
      ipv4 {
        address = "10.0.0.33/24"
        gateway = "10.0.0.254"
      }
    }
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.macs["122"]
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
