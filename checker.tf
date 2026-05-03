/**
 * Checker: runs ctf-gameserver checker scripts. Sits in ranger_routers and
 * needs L3 reach to every team's vulnbox service ports — the egress rule
 * below is wide-open so individual checker scripts decide which ports to
 * hit. DB coordination happens back to the gameserver's Postgres.
 */

resource "aws_security_group" "checker_sg" {
  name        = "ranger_checker_sg"
  description = "Security group for the checker"
  vpc_id      = aws_vpc.ranger_main.id

  egress {
    description      = "Allow all egress (checker needs reach to all team vulnboxes)"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description     = "SSH from admin bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.admin_sg.id]
  }

  tags = {
    Name = "ranger_checker_sg"
  }
}

resource "aws_instance" "checker" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.checker_instance_type
  subnet_id                   = aws_subnet.ranger_routers.id
  key_name                    = aws_key_pair.admin_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.checker.name
  associate_public_ip_address = false

  vpc_security_group_ids = [aws_security_group.checker_sg.id]

  user_data = templatefile("${path.module}/checker_cloud_init.yaml.tftpl", {
    admin_pubkey          = trimspace(tls_private_key.admin_key.public_key_openssh)
    postgres_password     = random_password.postgres_password.result
    flag_secret           = base64encode(random_password.flag_secret.result)
    gameserver_private_ip = aws_instance.gameserver.private_ip
    team_ip_pattern       = "10.32.%s.4"
  })
  user_data_replace_on_change = true

  tags = {
    Name = "ranger_checker"
  }
}

output "checker_private_ip" {
  description = "Private IP of the checker"
  value       = aws_instance.checker.private_ip
}
