# CLAUDE.md

Guidance for Claude Code working in this repository.

## Project overview

Ranger is a Terraform-based Attack/Defense (A/D) CTF range on AWS. It
provisions VPCs, networking, two OpenVPN endpoints (team + out-of-band
admin), per-team vulnboxes, a gameserver running upstream `ctf-gameserver`
(controller + submission + Django scoreboard + Postgres on a single host),
and a checker host. The DB is auto-seeded with N teams; per-team OpenVPN
configs land in S3 and are served to teams via the scoreboard's per-team
downloads page.

## Requirements

- Terraform >= 1.13
- AWS credentials in `.env`, loaded with `source init.sh` (or `init.fish`)

## Common commands

```bash
source init.sh
terraform init
terraform plan
terraform apply
terraform destroy
terraform output -json team_passwords        # per-team scoreboard logins
terraform output gameserver_admin_password   # Django superuser password
```

## Architecture

### Networks

Two peered VPCs:

- **ranger_main** (10.50.0.0/16) — public-facing
  - `ranger_public` (10.50.0.0/25): VPN host, IGW
  - `ranger_routers` (10.50.1.0/24): admin, gameserver, checker
- **ranger_teams** (10.32.0.0/16) — team infrastructure
  - per team: `10.32.<N>.0/24`, vulnbox at `.4`

### VPNs

Two OpenVPN daemons share a single host:

- **Team VPN** (UDP 1201, tunnel pool 10.8.0.0/16). Each `team_<N>` cert is
  pinned to `10.8.<N>.10` via OpenVPN CCD so the submission daemon can
  derive the team id from the source IP. One concurrent connection per
  team — duplicate-cn is not enabled.
- **Vulnbox-admin VPN** (UDP 1200, tunnel pool 10.9.0.0/24). Out-of-band
  channel for organizers; vulnboxes auto-connect at boot via S3-distributed
  client configs.

VPN→VPC traffic is **not** MASQUERADEd. VPC route tables route the tunnel
CIDRs back to the VPN host's ENI; vulnboxes/gameserver/admin see real
client source IPs. Only internet-bound VPN traffic is NATed.

### Terraform layout

- `main.tf` — provider, team module instantiation
- `network_config.tf` — VPCs, subnets, gateways, route tables (including the
  VPN-tunnel-CIDR routes that replace MASQUERADE)
- `vpn.tf`, `vpn_server/` — OpenVPN host + module
- `admin.tf`, `admin_cloud_init.yaml.tftpl` — bastion host with operator
  scripts (`team-ssh`, `team-restart-service`, `fetch-team-logs`,
  `presign-vpn`)
- `gameserver.tf`, `gameserver_cloud_init.yaml.tftpl` — ctf-gameserver host
  (built from source on first boot; user_data is gzipped because it exceeds
  the 16KB raw limit)
- `checker.tf`, `checker_cloud_init.yaml.tftpl` — checker host (deps only;
  scripts come with services)
- `team/` — per-team subnet, route table, vulnbox
- `dns.tf` — internal `ctf.internal` zone + optional public scoreboard A
  record (only when `public_zone_name` is set)
- `iam.tf` — per-role IAM (admin, gameserver, vpn_server, vulnbox, ec2_ssm)
- `s3.tf` — `ranger-vpn-configs-*` bucket for VPN config distribution
- `flow_logs.tf` — VPC flow logs to CloudWatch

### Gameserver bootstrap

Cloud-init builds the upstream `ctf-gameserver` Debian package from source,
pinned to `cbc85804ded8827bd46c464088b4b0158eace26b` (last commit before the
pyproject migration that requires Python 3.13). Then:

- Postgres role/db, Django migrate, superuser
- `/usr/local/sbin/ranger-seed-db.py` seeds N team users + `Team` rows
  (with `net_number = i`), the `GameControl` singleton (tick_duration 120s,
  null start/end), and the `TeamDownload(filename="openvpn.ovpn")` row
- Pulls `team_<i>.ovpn` from S3 to `/var/lib/ctf-gameserver/team-downloads/<i>/openvpn.ovpn`

The submission daemon's `CTF_TEAMREGEX` is
`^(?:10\.32|10\.8)\.([0-9]+)\.[0-9]+$` — matches both vulnbox source
(10.32.X.4) and team-VPN client source (10.8.X.10) and captures the team
id.

### Operator scripts on admin

The admin instance gets the operator SSH private key (in user_data) and
these wrappers in `/usr/local/bin/`:

- `team-ssh N [cmd...]` — SSH to team N's vulnbox
- `team-restart-service N SERVICE` — restart a unit (or `compose` for all
  docker compose stacks under `/opt`)
- `fetch-team-logs N [DEST]` — rsync `/var/log` from team N's vulnbox
- `presign-vpn N [SECONDS]` — presigned S3 URL for `team_N.ovpn`,
  for OOB distribution before teams are on the VPN

## Key variables

| Variable | Default | Description |
|----------|---------|-------------|
| `num_teams` | `4` | Number of teams |
| `aws_region` | `us-east-1` | AWS region |
| `*_instance_type` | `t3.micro` (gameserver: `t3.small`) | Instance sizing |
| `admin_ssh_cidr` | `10.50.0.0/16` | Operator SSH ingress on admin (on top of VPN tunnel CIDRs and `admin_public_ssh_cidr`) |
| `admin_public_ssh_cidr` | `0.0.0.0/0` | Public SSH ingress on admin — tighten to your operator IP |
| `gameserver_admin_email` | `admin@ctf.internal` | Django superuser email |

## What's not yet provisioned

- Vulnerable services + their checker scripts (the vulnbox boots stock
  Ubuntu with docker; service bundles + checker units are deferred)
- Postgres backup
- Monitoring (Prometheus/Grafana)
