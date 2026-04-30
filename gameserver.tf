/**
 * Gameserver: hosts the ctf-gameserver controller, submission daemon, web
 * scoreboard, and (colocated) PostgreSQL. Lives in the private ranger_routers
 * subnet; teams reach it over the team VPN via masquerade from ranger_main.
 *
 * Actual ctf-gameserver install is done out-of-band via the upstream Ansible
 * roles from the admin host once the box is up; this module just lays down
 * the base OS, database, and web server.
 */

resource "aws_security_group" "gameserver_sg" {
  name        = "ranger_gameserver_sg"
  description = "Security group for the gameserver"
  vpc_id      = aws_vpc.ranger_main.id

  egress {
    description      = "Allow all egress"
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

  # Scoreboard / submission ingress: VPN clients now arrive with their tunnel
  # IPs (no more MASQUERADE to ranger_main), and vulnboxes hit us via peering
  # from the teams VPC.
  ingress {
    description = "Scoreboard HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [
      aws_vpc.ranger_main.cidr_block,
      aws_vpc.ranger_teams.cidr_block,
      module.vpn.vpn_cidr,
      module.vpn.vulnbox_vpn_cidr,
    ]
  }

  ingress {
    description = "Flag submission"
    from_port   = 31337
    to_port     = 31337
    protocol    = "tcp"
    cidr_blocks = [
      aws_vpc.ranger_main.cidr_block,
      aws_vpc.ranger_teams.cidr_block,
      module.vpn.vpn_cidr,
      module.vpn.vulnbox_vpn_cidr,
    ]
  }

  ingress {
    description     = "Postgres from checker SG"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.checker_sg.id]
  }

  tags = {
    Name = "ranger_gameserver_sg"
  }
}

# Secrets are generated once and survive instance replacement (kept in state).
# Wiping them via `terraform taint` will force a full gameserver reinit.
resource "random_password" "django_secret_key" {
  length  = 50
  special = true
}

resource "random_password" "flag_secret" {
  length  = 32
  special = false
}

resource "random_password" "django_admin_password" {
  length  = 24
  special = false
}

resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

# One scoreboard login per team; teams use these to download their VPN config.
resource "random_password" "team_password" {
  count   = var.num_teams
  length  = 16
  special = false
}

resource "aws_instance" "gameserver" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.gameserver_instance_type
  subnet_id                   = aws_subnet.ranger_routers.id
  key_name                    = aws_key_pair.admin_key.key_name
  iam_instance_profile        = aws_iam_instance_profile.gameserver.name
  associate_public_ip_address = false

  vpc_security_group_ids = [aws_security_group.gameserver_sg.id]

  # Cloud-init payload exceeds the 16KB raw user_data limit, so it ships gzipped.
  user_data_base64 = base64gzip(templatefile("${path.module}/gameserver_cloud_init.yaml.tftpl", {
    admin_pubkey          = trimspace(tls_private_key.admin_key.public_key_openssh)
    num_teams             = var.num_teams
    team_ip_pattern       = "10.32.%s.4"
    scoreboard_hostname   = "scoreboard.ctf.internal"
    django_secret_key     = random_password.django_secret_key.result
    flag_secret           = base64encode(random_password.flag_secret.result)
    django_admin_email    = var.gameserver_admin_email
    django_admin_password = random_password.django_admin_password.result
    postgres_password     = random_password.postgres_password.result
    aws_region            = var.aws_region
    vulnbox_config_bucket = aws_s3_bucket.vpn_configs.bucket
    tick_duration         = 120
    team_passwords_json   = jsonencode([for p in random_password.team_password : p.result])
  }))
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "ranger_gameserver"
  }
}

output "gameserver_private_ip" {
  description = "Private IP of the gameserver"
  value       = aws_instance.gameserver.private_ip
}

output "gameserver_scoreboard_url" {
  description = "Internal scoreboard URL (reachable via team or admin VPN)"
  value       = "http://scoreboard.ctf.internal/"
}

output "gameserver_admin_password" {
  description = "Initial Django superuser password for the scoreboard. Username: admin"
  value       = random_password.django_admin_password.result
  sensitive   = true
}

output "team_passwords" {
  description = "Per-team scoreboard passwords (username team_<i>). Use to fetch the team's VPN config from the scoreboard team-downloads page."
  value       = { for i, p in random_password.team_password : "team_${i + 1}" => p.result }
  sensitive   = true
}
