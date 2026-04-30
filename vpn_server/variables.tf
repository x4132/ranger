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
  description = "Team-VPN client CIDR pool. Sized as a /16 so each team gets a deterministic /24 segment via OpenVPN CCD; submission's CTF_TEAMREGEX extracts the team id from the second octet."
  type        = string
  default     = "10.8.0.0/16"
}

variable "pushed_routes" {
  description = "VPC CIDRs pushed to VPN clients"
  type        = list(string)
}

variable "vulnbox_vpn_port" {
  description = "UDP port for the out-of-band vulnbox admin OpenVPN daemon"
  type        = number
  default     = 1200
}

variable "vulnbox_vpn_cidr" {
  description = "VPN client CIDR pool for the vulnbox admin channel"
  type        = string
  default     = "10.9.0.0/24"
}

variable "vulnbox_vpn_pushed_routes" {
  description = "CIDRs pushed to vulnbox admin VPN clients (typically only ranger_main)"
  type        = list(string)
}

variable "vulnbox_config_bucket" {
  description = "S3 bucket name where generated vulnbox_N.ovpn (and team_N.ovpn) configs are uploaded"
  type        = string
}

variable "teams_vpc_cidr" {
  description = "CIDR of the teams VPC. Used in iptables to skip MASQUERADE so vulnboxes see real VPN client source IPs."
  type        = string
}

variable "main_vpc_cidr" {
  description = "CIDR of the main VPC. Same purpose as teams_vpc_cidr — skip MASQUERADE so admin/gameserver/checker see real VPN client source IPs."
  type        = string
}

variable "iam_instance_profile" {
  description = "IAM instance profile name to attach to the VPN server"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used to configure the aws CLI in cloud-init)"
  type        = string
}
