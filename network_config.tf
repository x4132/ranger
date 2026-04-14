# module "vpc" {
#   source = "terraform-aws-modules/vpc/aws"
#   version = "6.5.0"
#
#   name = "aws_vpc"
# }

# networking infra copied from PIWICTF 2024, thanks https://dev.jameslowther.com/Projects/Pls,-I-Want-In---2024#vpcs
resource "aws_vpc" "ranger_main" {
  cidr_block                       = "10.50.0.0/16"
  instance_tenancy                 = "default"
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name = "ranger_main"
  }
}

resource "aws_subnet" "ranger_public" {
  cidr_block                      = "10.50.0.0/25"
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.ranger_main.ipv6_cidr_block, 8, 0)
  assign_ipv6_address_on_creation = true
  vpc_id                          = aws_vpc.ranger_main.id

  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "ranger_public"
  }
}

resource "aws_subnet" "ranger_routers" {
  cidr_block = "10.50.1.0/24"
  vpc_id     = aws_vpc.ranger_main.id

  tags = {
    Name = "ranger_routers"
  }
}

resource "aws_internet_gateway" "ranger_gw" {
  vpc_id = aws_vpc.ranger_main.id

  tags = {
    Name = "ranger_gw"
  }
}

resource "aws_eip" "ranger_nat_eip" {
  domain = "vpc"

  tags = {
    Name = "ranger_nat_eip"
  }
}

resource "aws_nat_gateway" "ranger_nat" {
  subnet_id     = aws_subnet.ranger_public.id
  allocation_id = aws_eip.ranger_nat_eip.id

  tags = {
    Name = "ranger_nat"
  }

  depends_on = [aws_internet_gateway.ranger_gw]
}

resource "aws_route_table" "ranger_public_rt" {
  vpc_id = aws_vpc.ranger_main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ranger_gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.ranger_gw.id
  }

  route {
    cidr_block                = aws_vpc.ranger_teams.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.ranger_link.id
  }

  tags = {
    Name = "ranger_public_rt"
  }
}

resource "aws_route_table_association" "ranger_public_rta" {
  subnet_id      = aws_subnet.ranger_public.id
  route_table_id = aws_route_table.ranger_public_rt.id
}

resource "aws_route_table" "ranger_private_rt" {
  vpc_id = aws_vpc.ranger_main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ranger_nat.id
  }

  route {
    cidr_block                = aws_vpc.ranger_teams.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.ranger_link.id
  }

  tags = {
    Name = "ranger_private_rt"
  }
}

resource "aws_route_table_association" "ranger_routers_rta" {
  subnet_id      = aws_subnet.ranger_routers.id
  route_table_id = aws_route_table.ranger_private_rt.id
}

resource "aws_vpc" "ranger_teams" {
  cidr_block       = "10.32.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "ranger_teams"
  }
}

resource "aws_vpc_peering_connection" "ranger_link" {
  peer_vpc_id = aws_vpc.ranger_teams.id
  vpc_id      = aws_vpc.ranger_main.id
  auto_accept = true

  tags = {
    Name = "ranger_link"
  }
}

resource "aws_subnet" "ranger_teams_gateway" {
  cidr_block = "10.32.0.0/25"
  vpc_id     = aws_vpc.ranger_teams.id

  tags = {
    Name = "ranger_teams_gateway"
  }
}

resource "aws_internet_gateway" "ranger_teams_gw" {
  vpc_id = aws_vpc.ranger_teams.id

  tags = {
    Name = "ranger_teams_gw"
  }
}

resource "aws_eip" "ranger_teams_nat_eip" {
  domain = "vpc"

  tags = {
    Name = "ranger_teams_nat_eip"
  }
}

resource "aws_nat_gateway" "ranger_teams_nat" {
  subnet_id     = aws_subnet.ranger_teams_gateway.id
  allocation_id = aws_eip.ranger_teams_nat_eip.id

  tags = {
    Name = "ranger_teams_nat"
  }

  depends_on = [aws_internet_gateway.ranger_teams_gw]
}

resource "aws_route_table" "ranger_teams_public_rt" {
  vpc_id = aws_vpc.ranger_teams.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ranger_teams_gw.id
  }

  route {
    cidr_block                = aws_vpc.ranger_main.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.ranger_link.id
  }

  tags = {
    Name = "ranger_teams_public_rt"
  }
}

resource "aws_route_table_association" "ranger_teams_gateway_rta" {
  subnet_id      = aws_subnet.ranger_teams_gateway.id
  route_table_id = aws_route_table.ranger_teams_public_rt.id
}
