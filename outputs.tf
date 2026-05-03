/**
 * Outputs consumed by the out-of-band tools (e.g. seed_services) so they can
 * discover the live infra without needing a copy of the TF state.
 */

output "vpn_configs_bucket" {
  description = "Name of the S3 bucket holding VPN configs and (now) service tarballs."
  value       = aws_s3_bucket.vpn_configs.bucket
}

output "num_teams" {
  description = "Number of teams provisioned. Tools iterate 1..N to reach each vulnbox at 10.32.<i>.4."
  value       = var.num_teams
}

output "aws_region" {
  description = "AWS region — for `aws --region` calls in deploy scripts."
  value       = var.aws_region
}
