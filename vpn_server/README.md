# VPN Server

This module represents one VPN server.

## Client configs

Cloud-init generates all `.ovpn` files on the VPN host under
`/root/client-configs/` and inlines `<ca>/<cert>/<key>/<tls-crypt>` into each.

| Config | Port | Distribution |
|--------|------|--------------|
| `admin.ovpn` (operator on team VPN) | 1201 | **Stays on the VPN host only — not uploaded to S3.** |
| `team_<N>.ovpn` | 1201 | Uploaded to `s3://<vpn_configs_bucket>/team_<N>.ovpn`; also served to teams via the scoreboard's per-team downloads page. |
| `vulnbox_<N>.ovpn` (OOB admin VPN) | 1200 | Uploaded to `s3://<vpn_configs_bucket>/vulnbox_<N>.ovpn`; vulnboxes pull their own at first boot. |

### Retrieving `admin.ovpn`

The VPN host's security group only allows SSH from the admin bastion's SG, so
pull the file through the bastion:

```bash
ssh -i ./admin_key.pem \
    -J ubuntu@$(terraform output -raw admin_public_ip) \
    ubuntu@$(terraform output -raw vpn_private_ip) \
    sudo cat /root/client-configs/admin.ovpn > admin.ovpn
chmod 600 admin.ovpn
```
