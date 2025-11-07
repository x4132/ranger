resource "aws_network_interface" "vpn_iface" {
  subnet_id         = var.vpn_subnet_id
  ipv6_address_count = 1
  security_groups   = [var.security_group_id]

  tags = {
    Name = "vpn_network_iface"
  }
}

resource "aws_instance" "vpn_server" {
  ami           = var.ami
  instance_type = var.instance_type

  primary_network_interface {
    network_interface_id = aws_network_interface.vpn_iface.id
  }

  tags = {
    Name = "ranger_vpn_server"
  }
}
