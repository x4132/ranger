/**
 * Auto-seed services after every terraform apply.
 *
 * Runs scripts/wait-and-seed.sh, which polls each instance for its
 * bootstrap marker file (/var/lib/ranger-{gameserver,checker,vulnbox}-bootstrapped)
 * and then invokes seed_services/seed.py --all. Triggers on instance IDs,
 * so any host replacement reseeds. Service-content edits are not tracked
 * automatically — re-run with:
 *
 *   terraform apply -replace=null_resource.seed_services[0]
 *
 * or just `python3 seed_services/seed.py --all` directly. seed.py is idempotent.
 *
 * Disable with: terraform apply -var=auto_seed_services=false
 */

variable "auto_seed_services" {
  description = "Run seed_services/seed.py --all after apply."
  type        = bool
  default     = true
}

resource "null_resource" "seed_services" {
  count = var.auto_seed_services ? 1 : 0

  triggers = {
    gameserver_id = aws_instance.gameserver.id
    checker_id    = aws_instance.checker.id
    vulnbox_ids   = join(",", [for m in module.team : m.vulnbox_id])
  }

  depends_on = [
    aws_instance.gameserver,
    aws_instance.checker,
    aws_instance.admin,
    module.team,
    local_file.admin_private_key,
  ]

  provisioner "local-exec" {
    working_dir = path.module
    command     = "${path.module}/scripts/wait-and-seed.sh"
    interpreter = ["/bin/bash", "-c"]
    # Pass infra IPs explicitly: `terraform output` from a subprocess during an
    # in-progress apply has been observed to return stale (pre-apply) values
    # for some outputs even after the underlying resource is recreated, which
    # made the script poll the previous instance's IP and time out.
    # Resource attributes referenced here are evaluated by Terraform against
    # the live in-memory state, so they're always current.
    environment = {
      ADMIN_IP            = aws_instance.admin.public_ip
      GAMESERVER_IP       = aws_instance.gameserver.private_ip
      CHECKER_IP          = aws_instance.checker.private_ip
      NUM_TEAMS           = tostring(var.num_teams)
      VPN_CONFIGS_BUCKET  = aws_s3_bucket.vpn_configs.bucket
      AWS_REGION_OUT      = var.aws_region
    }
  }
}
