provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Name = "ranger"
    }
  }
}

// team module - handles all team stuff like vulnbox etc
module "team" {
  count                 = var.num_teams
  source                = "./team"
  cidr_block            = "10.32.${count.index + 1}.0/24"
  vpc_id                = aws_vpc.ranger_teams.id
  team_id               = count.index + 1
  ami                   = data.aws_ami.ubuntu.id
  instance_type         = var.vulnbox_instance_type
  admin_ssh_cidr        = var.admin_ssh_cidr
  main_vpc_cidr         = aws_vpc.ranger_main.cidr_block
  nat_gateway_id        = aws_nat_gateway.ranger_teams_nat.id
  peering_connection_id = aws_vpc_peering_connection.ranger_link.id
}
