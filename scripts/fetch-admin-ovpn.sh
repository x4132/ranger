#!/usr/bin/env bash
# Fetches /root/client-configs/admin.ovpn from the VPN host by jumping
# through the public admin bastion. SCP can't sudo, so we ssh with
# ProxyJump and `sudo cat`, capturing stdout to a local file.
#
# Usage: fetch-admin-ovpn.sh [output_path]
#   default output_path: ./admin.ovpn

set -euo pipefail

OUT="${1:-admin.ovpn}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$REPO_ROOT/admin_key.pem"

if [ ! -f "$KEY" ]; then
  echo "missing key: $KEY (run terraform apply first)" >&2
  exit 1
fi

ADMIN_IP="$(terraform -chdir="$REPO_ROOT" output -raw admin_public_ip)"
VPN_IP="$(terraform -chdir="$REPO_ROOT" output -raw vpn_private_ip)"

SSH_OPTS=(
  -i "$KEY"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

ssh "${SSH_OPTS[@]}" \
  -o ProxyJump="ubuntu@${ADMIN_IP}" \
  "ubuntu@${VPN_IP}" \
  'sudo cat /root/client-configs/admin.ovpn' > "$OUT"

echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
