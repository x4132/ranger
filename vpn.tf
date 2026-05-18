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

  ingress {
    description      = "Allow vulnbox admin OpenVPN ingress"
    from_port        = 1200
    to_port          = 1200
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description     = "Allow SSH from admin bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.admin_sg.id]
  }

  # Forwarded return traffic from vulnboxes carries src=10.32.X.4 and
  # dst=<VPN tunnel IP>; the ENI's stateful SG doesn't have an outbound
  # conntrack entry for it (the original outbound src was the VPN client,
  # not this ENI), so without an explicit ingress rule the reply is dropped.
  ingress {
    description = "Allow forwarded return traffic from teams VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.ranger_teams.cidr_block]
  }

  tags = {
    Name = "vpn_sg"
  }
}

module "vpn" {
  source               = "./vpn_server"
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.vpn_instance_type
  vpn_subnet_id        = aws_subnet.ranger_public.id
  security_group_id    = aws_security_group.vpn_sg.id
  num_teams            = var.num_teams
  key_name             = aws_key_pair.admin_key.key_name
  aws_region           = var.aws_region
  iam_instance_profile = aws_iam_instance_profile.vpn_server.name
  pushed_routes = [
    aws_vpc.ranger_main.cidr_block,
    aws_vpc.ranger_teams.cidr_block,
  ]
  # Don't push ranger_main into the vulnbox tunnel — the vulnbox already
  # reaches ranger_main via VPC peering, and pushing the route caused
  # asymmetric returns: SYN arrived via peering, SYN-ACK left via tun0 (with
  # the vulnbox's tunnel-side source IP) and admin dropped the reply.
  # Operator access via the tunnel IP (10.9.0.X) still works thanks to the
  # tun-vbox MASQUERADE rule on the VPN host.
  vulnbox_vpn_pushed_routes = []
  vulnbox_config_bucket     = aws_s3_bucket.vpn_configs.bucket
  teams_vpc_cidr            = aws_vpc.ranger_teams.cidr_block
  main_vpc_cidr             = aws_vpc.ranger_main.cidr_block
}

output "vpn_public_ip" {
  description = "Public EIP of the VPN server"
  value       = module.vpn.public_ip
}

output "vpn_private_ip" {
  description = "Private IP of the VPN server (reach via admin bastion)"
  value       = module.vpn.private_ip
}
