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
    description = "Allow SSH from configured CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_cidr]
  }

  tags = {
    Name = "admin_sg"
  }
}

resource "aws_instance" "admin" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.router_instance_type
  subnet_id     = aws_subnet.ranger_routers.id
  key_name      = aws_key_pair.admin_key.key_name

  vpc_security_group_ids = [aws_security_group.admin_sg.id]

  tags = {
    Name = "ranger_admin"
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

output "admin_key_file" {
  description = "Path to the admin SSH private key"
  value       = local_file.admin_private_key.filename
}
