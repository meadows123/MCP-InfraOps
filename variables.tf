variable "admin_ssh_public_key" {
  description = "SSH key used to access admin user"
  type        = string
}

variable "home_wireguard_server_public_key" {
  description = "Public key for home WireGuard server"
  type        = string
}

variable "home_wireguard_server_endpoint" {
  description = "Endpoint for home WireGuard server"
  type        = string
}

variable "wireguard_client_private_key" {
  description = "Private key for WireGuard client"
  type        = string
  sensitive   = true
}

variable "wireguard_client_public_key" {
  description = "Public key for WireGuard client"
  type        = string
}

# Optional: Declare these too if you're using them
variable "client_id" {
  type = string
  description = "Azure client ID"
}

variable "client_secret" {
  type = string
  description = "Azure client secret"
  sensitive = true
}
