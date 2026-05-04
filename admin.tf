/**
Admin Instance Configuration
*/

resource "tls_private_key" "admin_key" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "admin_key" {
  key_name   = "ranger_admin_key"
  public_key = tls_private_key.admin_key.public_key_openssh
}

resource "aws_security_group" "admin_sg" {
  name        = "admin_security_group"
  description = "Security group for admin instance"
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
    description = "Allow SSH from internal CIDR (VPN/VPC)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_cidr]
  }

  # Without VPN→VPC MASQUERADE, VPN clients arrive with their tunnel-side IPs
  # rather than the VPN host's IP, so VPC-CIDR-only rules no longer cover them.
  ingress {
    description = "Allow SSH from team VPN and vulnbox-admin VPN clients"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [module.vpn.vpn_cidr, module.vpn.vulnbox_vpn_cidr]
  }

  ingress {
    description = "Allow SSH from public internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_public_ssh_cidr]
  }

  tags = {
    Name = "admin_sg"
  }
}

resource "aws_instance" "admin" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.router_instance_type
  subnet_id                   = aws_subnet.ranger_public.id
  key_name                    = aws_key_pair.admin_key.key_name
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.admin.name

  vpc_security_group_ids = [aws_security_group.admin_sg.id]

  user_data = templatefile("${path.module}/admin_cloud_init.yaml.tftpl", {
    admin_pubkey          = trimspace(tls_private_key.admin_key.public_key_openssh)
    admin_private_key     = tls_private_key.admin_key.private_key_openssh
    vpn_configs_bucket    = aws_s3_bucket.vpn_configs.bucket
    aws_region            = var.aws_region
    extra_authorized_keys = var.extra_authorized_keys
  })
  user_data_replace_on_change = true

  # AWS flips associate_public_ip_address back to true once the EIP attaches,
  # which would otherwise force a needless replacement on every plan.
  lifecycle {
    ignore_changes = [associate_public_ip_address]
  }

  tags = {
    Name = "ranger_admin"
  }
}

resource "aws_eip" "admin_eip" {
  domain   = "vpc"
  instance = aws_instance.admin.id

  tags = {
    Name = "ranger_admin_eip"
  }
}

resource "local_file" "admin_private_key" {
  content  = tls_private_key.admin_key.private_key_openssh
  filename = "${path.module}/admin_key.pem"

  file_permission = "0600"
}

output "admin_private_ip" {
  description = "Private IP address of the admin instance"
  value       = aws_instance.admin.private_ip
}

output "admin_public_ip" {
  description = "Public EIP of the admin instance"
  value       = aws_eip.admin_eip.public_ip
}

output "admin_key_file" {
  description = "Path to the admin SSH private key"
  value       = local_file.admin_private_key.filename
}
