resource "aws_network_interface" "vpn_iface" {
  subnet_id          = var.vpn_subnet_id
  ipv6_address_count = 1
  security_groups    = [var.security_group_id]
  source_dest_check  = false

  tags = {
    Name = "vpn_network_iface"
  }
}

resource "aws_eip" "vpn_eip" {
  domain            = "vpc"
  network_interface = aws_network_interface.vpn_iface.id

  tags = {
    Name = "ranger_vpn_eip"
  }
}

resource "aws_instance" "vpn_server" {
  ami                  = var.ami
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = var.iam_instance_profile

  primary_network_interface {
    network_interface_id = aws_network_interface.vpn_iface.id
  }

  lifecycle {
    ignore_changes = [source_dest_check]
  }

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    public_ip   = aws_eip.vpn_eip.public_ip
    aws_region  = var.aws_region
    vpn_port    = var.vpn_port
    vpn_cidr    = var.vpn_cidr
    vpn_network = cidrhost(var.vpn_cidr, 0)
    vpn_netmask = cidrnetmask(var.vpn_cidr)
    num_teams   = var.num_teams
    pushed_routes = [
      for c in var.pushed_routes : {
        network = cidrhost(c, 0)
        netmask = cidrnetmask(c)
      }
    ]
    vulnbox_vpn_port    = var.vulnbox_vpn_port
    vulnbox_vpn_cidr    = var.vulnbox_vpn_cidr
    vulnbox_vpn_network = cidrhost(var.vulnbox_vpn_cidr, 0)
    vulnbox_vpn_netmask = cidrnetmask(var.vulnbox_vpn_cidr)
    vulnbox_vpn_pushed_routes = [
      for c in var.vulnbox_vpn_pushed_routes : {
        network = cidrhost(c, 0)
        netmask = cidrnetmask(c)
      }
    ]
    vulnbox_config_bucket = var.vulnbox_config_bucket
    teams_vpc_cidr        = var.teams_vpc_cidr
    main_vpc_cidr         = var.main_vpc_cidr
  })
  user_data_replace_on_change = true

  tags = {
    Name = "ranger_vpn_server"
  }
}
