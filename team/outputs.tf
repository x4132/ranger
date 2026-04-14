output "subnet_id" {
  description = "Subnet ID for this team"
  value       = aws_subnet.ranger_team_subnets.id
}

output "vulnbox_id" {
  description = "EC2 instance ID for this team's vulnbox"
  value       = aws_instance.vulnbox.id
}

output "vulnbox_private_ip" {
  description = "Private IP of the team's vulnbox"
  value       = aws_instance.vulnbox.private_ip
}

output "vulnbox_key_file" {
  description = "Path to the vulnbox SSH private key"
  value       = local_file.vulnbox_private_key.filename
}
