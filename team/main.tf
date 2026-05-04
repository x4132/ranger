resource "aws_subnet" "ranger_team_subnets" {
  cidr_block = var.cidr_block
  vpc_id     = var.vpc_id

  tags = {
    Name = "ranger_team_${var.team_id}_subnet"
  }
}

resource "aws_route_table" "team_rt" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.nat_gateway_id
  }

  route {
    cidr_block                = var.main_vpc_cidr
    vpc_peering_connection_id = var.peering_connection_id
  }

  route {
    cidr_block                = var.vpn_cidr
    vpc_peering_connection_id = var.peering_connection_id
  }

  route {
    cidr_block                = var.vulnbox_vpn_cidr
    vpc_peering_connection_id = var.peering_connection_id
  }

  tags = {
    Name = "ranger_team_${var.team_id}_rt"
  }
}

resource "aws_route_table_association" "team_rta" {
  subnet_id      = aws_subnet.ranger_team_subnets.id
  route_table_id = aws_route_table.team_rt.id
}

resource "tls_private_key" "vulnbox_key" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "vulnbox_key" {
  key_name   = "ranger_team_${var.team_id}_key"
  public_key = tls_private_key.vulnbox_key.public_key_openssh
}

resource "local_file" "vulnbox_private_key" {
  content  = tls_private_key.vulnbox_key.private_key_openssh
  filename = "${path.root}/team_${var.team_id}_key.pem"

  file_permission = "0600"
}

resource "aws_security_group" "vulnbox_sg" {
  name        = "ranger_team_${var.team_id}_vulnbox_sg"
  description = "Security group for team ${var.team_id} vulnbox"
  vpc_id      = var.vpc_id

  egress {
    description      = "Allow all egress traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "Allow SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_cidr]
  }

  ingress {
    description = "Allow traffic from main VPC (admin, gameserver, checker)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.main_vpc_cidr]
  }

  # Without MASQUERADE for VPN→teams-VPC, traffic from VPN clients arrives
  # with their tunnel IP as source. Allow it directly.
  ingress {
    description = "Allow traffic from team VPN and vulnbox-admin VPN clients"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpn_cidr, var.vulnbox_vpn_cidr]
  }

  ingress {
    description = "Allow intra-subnet traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.cidr_block]
  }

  # Peer teams attacking through their own vulnbox arrive with a 10.32.X.4
  # source IP. Tighten to specific service ports once services exist.
  ingress {
    description = "Allow attacks from peer team subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.teams_vpc_cidr]
  }

  tags = {
    Name = "ranger_team_${var.team_id}_vulnbox_sg"
  }
}

resource "aws_instance" "vulnbox" {
  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = aws_subnet.ranger_team_subnets.id
  # .0–.3 and .255 are AWS-reserved in every subnet, so .4 is the lowest usable.
  private_ip                  = cidrhost(var.cidr_block, 4)
  associate_public_ip_address = false
  key_name                    = aws_key_pair.vulnbox_key.key_name
  iam_instance_profile        = var.iam_instance_profile

  vpc_security_group_ids = [aws_security_group.vulnbox_sg.id]

  user_data = templatefile("${path.module}/vulnbox_cloud_init.yaml.tftpl", {
    team_id               = var.team_id
    vulnbox_config_bucket = var.vulnbox_config_bucket
    aws_region            = var.aws_region
    admin_pubkey          = var.admin_pubkey
    extra_authorized_keys = var.extra_authorized_keys
  })
  user_data_replace_on_change = true

  tags = {
    Name = "ranger_team_${var.team_id}_vulnbox"
  }
}
