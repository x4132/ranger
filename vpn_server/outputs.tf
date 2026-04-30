output "public_ip" {
  description = "Public EIP of the VPN server"
  value       = aws_eip.vpn_eip.public_ip
}

output "private_ip" {
  description = "Private IP of the VPN server"
  value       = aws_network_interface.vpn_iface.private_ip
}

output "network_interface_id" {
  description = "ENI of the VPN server. Used as a route target so the VPC route tables can deliver replies to VPN client tunnel IPs without MASQUERADE."
  value       = aws_network_interface.vpn_iface.id
}

output "vpn_cidr" {
  description = "Team-VPN client CIDR (the tunnel pool, not a VPC subnet)."
  value       = var.vpn_cidr
}

output "vulnbox_vpn_cidr" {
  description = "Vulnbox-admin VPN client CIDR (the tunnel pool)."
  value       = var.vulnbox_vpn_cidr
}
