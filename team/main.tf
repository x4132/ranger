resource "aws_subnet" "ranger_team_subnets" {
  cidr_block = var.cidr_block
  vpc_id     = var.vpc_id

  tags = {
    Name = "ranger_team_${var.team_id}_subnet"
  }
}