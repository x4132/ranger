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
  count      = var.num_teams
  source     = "./team"
  cidr_block = "10.32.${count.index + 1}.0/24"
  vpc_id     = aws_vpc.ranger_teams.id
  team_id    = count.index + 1
}
