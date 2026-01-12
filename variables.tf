# variable "gameserver_type" {
#   description = "A/D server variant"
#   type        = string
#   default     = "faust"
#   validation {
#     condition     = var.gameserver_type == can(regex("^(faust)$", var.gameserver_type))
#     error_message = "gameserver_type must be either 'faust'"
#   }
# }

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "num_teams" {
  description = "Number of Teams"
  type        = number
  default     = 4
}

variable "vulnbox_instance_type" {
  description = "Instance type for vulnboxes"
  type = string
  default = "t3.micro"
}

variable "router_instance_type" {
  description = "Instance type for router instances"
  type        = string
  default     = "t3.micro"
}

variable "thrower_instance_type" {
  description = "Instance type for thrower instances"
  type = string
  default = "t3.micro"
}

variable "gameserver_instance_type" {
  description = "Instance type for the gameserver"
  type = string
  default = "t3.micro"
}

variable "vpn_instance_type" {
  description = "Instance type for the VPN instances"
  type = string
  default = "t3.micro"
}

variable "checker_instance_type" {
  description = "Instance type for the checker server"
  type = string
  default = "t3.micro"
}

variable "monitor_instance_type" {
  description = "Instance type for the monitor server"
  type = string
  default = "t3.micro"
}

variable "admin_ssh_cidr" {
  description = "CIDR block allowed to SSH into admin instance. Use VPC CIDR (10.50.0.0/16) to allow all VPN users, or a narrower range for admin-only VPN clients."
  type        = string
  default     = "10.50.0.0/16"
}