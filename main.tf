
locals {
  base_domain        = "sikademo.com"
  cloudflare_zone_id = "f2c00168a7ecd694bb1ba017b332c019"
  cluster_name       = "okd0"
}

resource "digitalocean_custom_image" "fcos" {
  lifecycle {
    ignore_changes = [distribution]
  }
  name    = "${local.cluster_name}-fcos"
  url     = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/40.20240519.3.0/x86_64/fedora-coreos-40.20240519.3.0-digitalocean.x86_64.qcow2.gz"
  regions = ["fra1"]
}

resource "digitalocean_vpc" "vpc" {
  name     = local.cluster_name
  region   = "fra1"
  ip_range = "10.10.10.0/24"
}

resource "digitalocean_ssh_key" "ondrejsika" {
  name       = "ondrejsika"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "digitalocean_droplet" "bootstrap" {
  name      = "${local.cluster_name}-bootstrap"
  size      = "s-4vcpu-8gb"
  image     = digitalocean_custom_image.fcos.id
  region    = "fra1"
  vpc_uuid  = digitalocean_vpc.vpc.id
  ssh_keys  = [digitalocean_ssh_key.ondrejsika.id]
  user_data = file("bootstrap.ign")
  tags      = ["${local.cluster_name}-api"]
}

resource "digitalocean_loadbalancer" "api" {
  name   = "${local.cluster_name}-api"
  region = "fra1"

  forwarding_rule {
    entry_port     = 6443
    entry_protocol = "tcp"

    target_port     = 6443
    target_protocol = "tcp"
  }

  forwarding_rule {
    entry_port     = 22623
    entry_protocol = "tcp"

    target_port     = 22623
    target_protocol = "tcp"
  }

  healthcheck {
    port     = 6443
    protocol = "tcp"
  }

  vpc_uuid    = digitalocean_vpc.vpc.id
  droplet_tag = "${local.cluster_name}-api"
}


resource "digitalocean_loadbalancer" "apps" {
  name   = "${local.cluster_name}-apps"
  region = "fra1"

  forwarding_rule {
    entry_port     = 80
    entry_protocol = "tcp"

    target_port     = 80
    target_protocol = "tcp"
  }

  forwarding_rule {
    entry_port     = 443
    entry_protocol = "tcp"

    target_port     = 443
    target_protocol = "tcp"
  }

  healthcheck {
    port     = 443
    protocol = "tcp"
  }

  vpc_uuid    = digitalocean_vpc.vpc.id
  droplet_tag = "${local.cluster_name}-apps"
}


resource "cloudflare_record" "a" {
  for_each = {
    "api.${local.cluster_name}"       = digitalocean_loadbalancer.api.ip
    "api-int.${local.cluster_name}"   = digitalocean_loadbalancer.api.ip
    "apps.${local.cluster_name}"      = digitalocean_loadbalancer.apps.ip
    "bootstrap.${local.cluster_name}" = digitalocean_droplet.bootstrap.ipv4_address
  }
  zone_id = local.cloudflare_zone_id
  name    = each.key
  value   = each.value
  type    = "A"
}

resource "cloudflare_record" "cname" {
  for_each = {
    "*.apps.${local.cluster_name}" = cloudflare_record.a["apps.${local.cluster_name}"].hostname
  }
  zone_id = local.cloudflare_zone_id
  name    = each.key
  value   = each.value
  type    = "CNAME"
}

resource "digitalocean_droplet" "master" {
  count = 3

  name      = "master${count.index}"
  size      = "s-8vcpu-16gb"
  image     = digitalocean_custom_image.fcos.id
  region    = "fra1"
  vpc_uuid  = digitalocean_vpc.vpc.id
  ssh_keys  = [digitalocean_ssh_key.ondrejsika.id]
  user_data = file("master.ign")
  tags      = ["${local.cluster_name}-api"]
}

resource "cloudflare_record" "master" {
  count = 3

  zone_id = local.cloudflare_zone_id
  name    = "${digitalocean_droplet.master[count.index].name}.${local.cluster_name}"
  value   = digitalocean_droplet.master[count.index].ipv4_address
  type    = "A"
}

resource "digitalocean_droplet" "worker" {
  count = 3

  name      = "worker${count.index}"
  size      = "s-8vcpu-16gb"
  image     = digitalocean_custom_image.fcos.id
  region    = "fra1"
  vpc_uuid  = digitalocean_vpc.vpc.id
  ssh_keys  = [digitalocean_ssh_key.ondrejsika.id]
  user_data = file("worker.ign")
  tags      = ["${local.cluster_name}-apps"]
}


resource "cloudflare_record" "worker" {
  count = 3

  zone_id = local.cloudflare_zone_id
  name    = "${digitalocean_droplet.worker[count.index].name}.${local.cluster_name}"
  value   = digitalocean_droplet.worker[count.index].ipv4_address
  type    = "A"
}
