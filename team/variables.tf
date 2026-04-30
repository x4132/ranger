variable "team_id" {
  description = "The ID of the team"
  type        = number
}

variable "vpc_id" {
  description = "The VPC ID of the team/subnet"
  type        = string
}

variable "cidr_block" {
  description = "The CIDR block of the team's subnet"
  type        = string
}

variable "ami" {
  description = "AMI ID used for the team's EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type used for the team's EC2 instance"
  type        = string
}

variable "admin_ssh_cidr" {
  description = "CIDR block allowed to SSH into the team's vulnbox"
  type        = string
}

variable "main_vpc_cidr" {
  description = "CIDR block of the main VPC, used for peering routes and ingress rules"
  type        = string
}

variable "nat_gateway_id" {
  description = "NAT gateway ID used for team subnet egress"
  type        = string
}

variable "peering_connection_id" {
  description = "VPC peering connection ID between ranger_main and ranger_teams"
  type        = string
}

variable "iam_instance_profile" {
  description = "IAM instance profile name to attach to the vulnbox"
  type        = string
}

variable "vulnbox_config_bucket" {
  description = "S3 bucket holding per-vulnbox admin-VPN .ovpn configs"
  type        = string
}

variable "aws_region" {
  description = "AWS region (for the aws CLI inside the vulnbox)"
  type        = string
}

variable "admin_pubkey" {
  description = "Operator SSH public key installed on the vulnbox"
  type        = string
}

variable "vpn_cidr" {
  description = "Team-VPN tunnel CIDR. Routed back via the peering connection so vulnboxes see real VPN client source IPs."
  type        = string
}

variable "vulnbox_vpn_cidr" {
  description = "Vulnbox-admin VPN tunnel CIDR. Routed back via the peering connection."
  type        = string
}

variable "teams_vpc_cidr" {
  description = "CIDR of the teams VPC. Allowed in the vulnbox SG so peer teams can attack via their own vulnbox."
  type        = string
}
