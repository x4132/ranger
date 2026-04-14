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

  vpc_security_group_ids = [aws_security_group.admin_sg.id]

  user_data = templatefile("${path.module}/admin_cloud_init.yaml.tftpl", {
    admin_pubkey = trimspace(tls_private_key.admin_key.public_key_openssh)
  })
  user_data_replace_on_change = true

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
