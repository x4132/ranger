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
