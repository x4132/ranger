/**
VPN Configuration
*/

resource "aws_security_group" "vpn_sg" {
  name        = "vpn_security_group"
  description = "Security group for VPN server"
  vpc_id      = aws_vpc.ranger_main.id

  egress {
    description      = "Allow all egress traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow OpenVPN ingress"
    from_port        = 1201
    to_port          = 1201 + var.num_teams
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "vpn_sg"
  }
}

module "vpn" {
  source            = "./vpn_server"
  ami               = data.aws_ami.ubuntu.id
  instance_type     = var.vpn_instance_type
  vpn_subnet_id     = aws_subnet.ranger_public.id
  security_group_id = aws_security_group.vpn_sg.id
}
