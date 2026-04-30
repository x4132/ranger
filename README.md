# Ranger

Terraform-based Attack/Defense (A/D) CTF range on AWS. Provisions VPCs,
networking, two OpenVPN endpoints (team + out-of-band admin), per-team
vulnboxes, a gameserver running upstream `ctf-gameserver` (controller +
submission + Django scoreboard + Postgres on a single host), and a checker
host. The DB is auto-seeded with N teams; per-team OpenVPN configs land in
S3 and are surfaced to teams through the scoreboard's per-team downloads.

## Requirements

- Terraform >= 1.13
- AWS credentials (in `.env`, loaded with `source init.sh` or `source init.fish`)

## Deploy

```bash
source init.sh                     # exports AWS_* env vars from .env
terraform init
terraform apply
```

Outputs include the admin EIP, gameserver and VPN private IPs, and (sensitive)
the Django admin password and per-team scoreboard passwords:

```bash
terraform output -json team_passwords
terraform output gameserver_admin_password
```

## Access

The admin host is the only path with a public IP. Everything else is reached
through it (or through a VPN connection).

```bash
# Operator SSH
ssh -i admin_key.pem ubuntu@$(terraform output -raw admin_public_ip)

# Operator scripts available on admin (see admin_cloud_init.yaml.tftpl):
team-ssh N [cmd...]              # SSH into team N's vulnbox
team-restart-service N SERVICE   # restart a unit on team N's vulnbox
fetch-team-logs N [DEST]         # rsync /var/log from team N's vulnbox
presign-vpn N [SECONDS]          # signed S3 URL for team N's openvpn config
```

`presign-vpn` is the OOB path for handing teams their initial VPN config —
once they're on the VPN, subsequent configs are served from the scoreboard's
team-downloads page.

## Architecture

### Networks

Two peered VPCs:

- **ranger_main** (10.50.0.0/16) — public-facing infrastructure
  - `ranger_public` (10.50.0.0/25): VPN host, IGW
  - `ranger_routers` (10.50.1.0/24): admin, gameserver, checker
- **ranger_teams** (10.32.0.0/16) — team infrastructure
  - per team: `10.32.<N>.0/24`, vulnbox at `.4`

### VPNs

Two OpenVPN daemons on the same host:

- **Team VPN** (UDP 1201, tunnel pool 10.8.0.0/16) — for team members. Each
  `team_<N>` cert is pinned to `10.8.<N>.10` via OpenVPN CCD so the
  submission daemon can derive the team id from the source IP.
- **Vulnbox-admin VPN** (UDP 1200, tunnel pool 10.9.0.0/24) — out-of-band
  channel for organizers; vulnboxes auto-connect at boot via S3-distributed
  client configs.

VPN→VPC traffic is **not** MASQUERADEd — VPC route tables route the tunnel
CIDRs back to the VPN host's ENI, so vulnboxes/gameserver/admin see real
client source IPs. Only internet-bound VPN traffic is NATed.

### Gameserver

Upstream `ctf-gameserver` (FAUST), pinned to commit
`cbc85804ded8827bd46c464088b4b0158eace26b` — the last commit before the
pyproject migration that requires Python 3.13. Built from source at first
boot. Runs:

- PostgreSQL (local cluster)
- Django scoreboard via uWSGI behind nginx
- `ctf-controller.service` (round/tick driver, flag generation)
- `ctf-submission@31337.service` (TCP flag intake; matches source IP against
  `^(?:10\.32|10\.8)\.([0-9]+)\.[0-9]+$` to derive team id — both vulnbox and
  team-VPN clients work)

The bootstrap script seeds N team Django users (`team_<i>` / random
password), `Team` rows with `net_number = i`, and a `GameControl` row with
`tick_duration = 120s` and a null `start`/`end` (no contest until you set
them in `/admin/`).

### Checker

A second host in `ranger_routers` with full L3 reach to every team's
vulnbox. Currently only Python deps installed; per-service checker scripts
and `ctf-checker@<svc>` units come with services (deferred).

## Key variables

| Variable | Default | Description |
|----------|---------|-------------|
| `num_teams` | `4` | Number of teams to provision |
| `aws_region` | `us-east-1` | AWS region |
| `*_instance_type` | `t3.micro` (gameserver: `t3.small`) | Instance sizing |
| `admin_ssh_cidr` | `10.50.0.0/16` | Operator SSH ingress on admin (in addition to VPN tunnel CIDRs and `admin_public_ssh_cidr`) |
| `admin_public_ssh_cidr` | `0.0.0.0/0` | Public SSH ingress on admin — tighten to your operator IP |
| `gameserver_admin_email` | `admin@ctf.internal` | Django superuser email |

## What's not (yet) provisioned

- Vulnerable services and their checker scripts. The vulnbox boots stock
  Ubuntu 24.04 with docker preinstalled — adding services means dropping a
  bundle in S3, having the vulnbox cloud-init pull and `docker compose up`,
  and dropping the corresponding checker script + `ctf-checker@<svc>` unit
  on the checker host.
- Postgres backup. The single-host DB has no scheduled snapshot; replacing
  the gameserver wipes the data (intentional for a testing range).
- Monitoring stack (Prometheus/Grafana).
