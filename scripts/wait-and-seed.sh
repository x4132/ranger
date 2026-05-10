#!/usr/bin/env bash
# Wait for cloud-init bootstrap on every instance, then run
# seed_services/seed.py --all. Invoked by null_resource.seed_services
# in seed.tf during `terraform apply`.
set -euo pipefail

cd "$(dirname "$0")/.."

ADMIN_IP=$(terraform output -raw admin_public_ip)
GAMESERVER_IP=$(terraform output -raw gameserver_private_ip)
CHECKER_IP=$(terraform output -raw checker_private_ip)
NUM_TEAMS=$(terraform output -raw num_teams)
KEY=./admin_key.pem

SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=5)
PROXY="ssh ${SSH_OPTS[*]} -W %h:%p ubuntu@${ADMIN_IP}"

ssh_to() {
  ssh "${SSH_OPTS[@]}" -o "ProxyCommand=$PROXY" "ubuntu@$1" "$2"
}

# `cloud-init status --wait` returns:
#   0 — done
#   2 — degraded done (recoverable warnings, e.g. AWS IPv6 IMDS attempts on
#       a v4-only VPC). Treat as ready.
#   1 — error (a module failed). Once cloud-init reaches this state it does
#       not recover, so polling further is pointless. Surface diagnostics
#       and abort.
# In addition, "done" only means cloud-init's modules finished — it does not
# guarantee the marker file exists (the runcmd that writes it could itself
# fail). When a marker is provided, verify it before declaring success.
wait_for_cloud_init() {
  local ip="$1" timeout="${2:-1500}" marker="${3:-}"
  local start rc
  start=$(date +%s)
  echo "  waiting for cloud-init on $ip..."
  while :; do
    rc=0
    ssh_to "$ip" "sudo cloud-init status --wait" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0|2)
        if [ -n "$marker" ]; then
          if ssh_to "$ip" "test -f $marker" >/dev/null 2>&1; then
            echo "  ready: $ip"
            return 0
          fi
          echo "  cloud-init done on $ip but marker $marker missing — bootstrap script failed" >&2
          ssh_to "$ip" "sudo cloud-init status --long; echo '----- runcmd output (tail) -----'; sudo tail -80 /var/log/cloud-init-output.log" >&2 || true
          return 1
        fi
        echo "  ready: $ip"
        return 0
        ;;
      1)
        echo "  cloud-init reported error on $ip — aborting (state is terminal, polling won't help)" >&2
        ssh_to "$ip" "sudo cloud-init status --long" >&2 || true
        return 1
        ;;
    esac
    if (( $(date +%s) - start > timeout )); then
      echo "  timeout waiting for cloud-init on $ip (rc=$rc, possibly unreachable via SSH)" >&2
      return 1
    fi
    sleep 10
  done
}

echo "== waiting for instance bootstrap =="
# Gameserver builds ctf-gameserver from source on first boot — give it room.
wait_for_cloud_init "$GAMESERVER_IP" 1500 /var/lib/ranger-gameserver-bootstrapped
wait_for_cloud_init "$CHECKER_IP"     600 /var/lib/ranger-checker-bootstrapped
for i in $(seq 1 "$NUM_TEAMS"); do
  wait_for_cloud_init "10.32.$i.4"    600 /var/lib/ranger-vulnbox-bootstrapped
done

echo "== seeding services =="
python3 seed_services/seed.py --all
