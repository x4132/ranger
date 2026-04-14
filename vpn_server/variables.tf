variable "vpn_subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "ami" {
  type = string
}

variable "num_teams" {
  description = "Number of team client configs to generate"
  type        = number
}

variable "key_name" {
  description = "EC2 key pair name for SSH access to the VPN server"
  type        = string
}

variable "vpn_port" {
  description = "UDP port for OpenVPN"
  type        = number
  default     = 1201
}

variable "vpn_cidr" {
  description = "VPN client CIDR pool"
  type        = string
  default     = "10.8.0.0/24"
}

variable "pushed_routes" {
  description = "VPC CIDRs pushed to VPN clients"
  type        = list(string)
}
