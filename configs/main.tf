terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.129.0"
    }
  }
  required_version = ">=1.8.4"
}

provider "yandex" {
  # token     = var.yc_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  service_account_key_file = file("~/.authorized_key.json")
  zone      = "ru-central1-a"
}

resource "yandex_vpc_network" "default" {
  name = "default-network"
}

resource "yandex_vpc_subnet" "default" {
  name           = "default-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.default.id
  v4_cidr_blocks = ["10.0.0.0/24"]
}

resource "yandex_vpc_security_group" "default" {
  name       = "default-sg"
  network_id = yandex_vpc_network.default.id

  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
        
  }

  egress {
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_compute_instance" "vm" {
  count       = 2
  name        = "nginx-vm-${count.index + 1}"
  platform_id = "standard-v1"
  zone        = "ru-central1-a"
  hostname    = "nginx-vm-${count.index + 1}"

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = "fd8jfh73rvks3qlqp3ck"
      type     = "network-hdd"
      size     = 10
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.default.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.default.id]
  }

  metadata = {
    user-data = file("cloud-init.yml")
  }
}

resource "yandex_lb_target_group" "my_tg" {
  name      = "my-target-group"
  region_id = "ru-central1"

  dynamic "target" {
    for_each = yandex_compute_instance.vm
    content {
      subnet_id = yandex_vpc_subnet.default.id
      address   = target.value.network_interface[0].ip_address
    }
  }
}

resource "yandex_lb_network_load_balancer" "my_nlb" {
  name = "my-network-load-balancer"

  listener {
    name = "my-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.my_tg.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/ping"
      }
    }
  }
}
