terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.39.2"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.35.0"
    }
  }
}

variable "cloudflare_api_token" {}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

variable "digitalocean_token" {}

provider "digitalocean" {
  token = var.digitalocean_token
}
