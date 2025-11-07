variable "team_id" {
  description = "The ID of the team"
  type = number
}

variable "vpc_id" {
  description = "The VPC ID of the team/subnet"
  type = string
}

variable "cidr_block" {
  description = "The CIDR block of the team's subnet"
  type = string
}