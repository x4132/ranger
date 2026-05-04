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
  }
}
