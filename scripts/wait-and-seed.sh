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

wait_for_cloud_init() {
  local ip="$1" timeout="${2:-1500}"
  local start
  start=$(date +%s)
  echo "  waiting for cloud-init on $ip..."
  while :; do
    # `cloud-init status --wait` blocks server-side until cloud-init reaches a
    # terminal state. Exit 0 = done, 2 = "degraded done" (recoverable warnings,
    # e.g. AWS IPv6 IMDS attempts on a v4-only VPC), 1 = error. Treat 0 and 2
    # as ready.
    rc=0
    ssh "${SSH_OPTS[@]}" -o "ProxyCommand=$PROXY" "ubuntu@$ip" \
        "sudo cloud-init status --wait" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = 0 ] || [ "$rc" = 2 ]; then
      echo "  ready: $ip"
      return 0
    fi
    if (( $(date +%s) - start > timeout )); then
      echo "  timeout waiting for cloud-init on $ip" >&2
      return 1
    fi
    sleep 10
  done
}

echo "== waiting for instance bootstrap =="
# Gameserver builds ctf-gameserver from source on first boot — give it room.
wait_for_cloud_init "$GAMESERVER_IP" 1500
wait_for_cloud_init "$CHECKER_IP"    600
for i in $(seq 1 "$NUM_TEAMS"); do
  wait_for_cloud_init "10.32.$i.4"   600
done

echo "== seeding services =="
python3 seed_services/seed.py --all
