output "public_ip" {
  description = "Public EIP of the VPN server"
  value       = aws_eip.vpn_eip.public_ip
}

output "private_ip" {
  description = "Private IP of the VPN server"
  value       = aws_network_interface.vpn_iface.private_ip
}
