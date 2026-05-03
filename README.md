# Ranger

Terraform-based Attack/Defense (A/D) CTF range on AWS. Provisions VPCs,
networking, two OpenVPN endpoints (team + out-of-band admin), per-team
vulnboxes, a gameserver running upstream `ctf-gameserver` (controller +
submission + Django scoreboard + Postgres on a single host), and a checker
host that runs the upstream `ctf-checkermaster` per service.

The DB is auto-seeded with N team users and a `GameControl` row; per-team
OpenVPN configs land in S3 and are surfaced to teams through the
scoreboard's team-downloads page. Services are deployed out-of-band via the
`seed_services` module.

## Requirements

- Terraform >= 1.13
- AWS credentials in `.env`, loaded with `source init.sh` (or `source init.fish`)
- Local `aws`, `ssh`, `python3` on `$PATH` for the operator workflow
- A FAUST-style service repo per service (under `services/<dir>/`) — see
  [`seed_services/README.md`](seed_services/README.md)

## Bring the range up

```bash
source init.sh
terraform init
terraform apply
```

Apply takes ~10–15 min; the gameserver and checker each build the
ctf-gameserver Debian package from source on first boot.

After the apply finishes, get the credentials:

```bash
terraform output -json team_passwords     # per-team scoreboard logins
terraform output gameserver_admin_password # Django superuser ('admin')
terraform output admin_public_ip           # operator SSH target
terraform output vpn_public_ip             # OpenVPN endpoint
```

The admin SSH key is written to `./admin_key.pem` (chmod 0600); guard it.

## Distribute VPN configs to teams

The chicken-and-egg: the scoreboard's team-downloads page needs the team to
already be on the VPN. For first-time distribution, hand out a presigned
S3 URL via the admin bastion's `presign-vpn` script:

```bash
ssh -i admin_key.pem ubuntu@$(terraform output -raw admin_public_ip)
# on admin:
presign-vpn 1 3600     # signed URL valid for 1 hour, for team_1.ovpn
presign-vpn 2 3600
# … one per team
```

Email or otherwise share each URL with the corresponding team. They `curl
-o team.ovpn '<url>'` and `openvpn --config team.ovpn`. Once on the VPN,
they reach the scoreboard at `http://scoreboard.ctf.internal/`, log in as
`team_<N>` with the password from `terraform output team_passwords`, and
re-download VPN configs from the team-downloads page on their own.

Each team cert is pinned by OpenVPN CCD to a fixed tunnel IP
`10.8.<N>.10`, so the submission daemon (which derives the team id from
the source IP) accepts flag submissions from either the team's vulnbox
(`10.32.<N>.4`) or the team's laptop on the VPN.

## Start the contest

The seeded `GameControl` row has `tick_duration = 120s`, `flag_prefix =
RANGER_`, and **null** `start` / `end` — the controller idles until you
set them. Easiest is via the Django admin (`/admin/scoring/gamecontrol/`)
once you've logged in as `admin`. Alternatively, from inside the
gameserver:

```bash
ssh -A -i admin_key.pem ubuntu@$(terraform output -raw admin_public_ip)
# from admin:
ssh ubuntu@$(terraform output -raw gameserver_private_ip)
# on gameserver:
sudo PYTHONPATH=/etc/ctf-gameserver/web DJANGO_SETTINGS_MODULE=prod_settings python3 - <<'PY'
import django, datetime
import django.utils.timezone as tz
django.setup()
from ctf_gameserver.web.scoring.models import GameControl
gc = GameControl.get_instance()
gc.start = tz.now()
gc.end   = tz.now() + datetime.timedelta(hours=8)
gc.services_public = gc.start
gc.save()
PY
sudo systemctl restart ctf-controller.service
```

## Add services

Drop one service per directory under `services/` (FAUST CTF format —
`metadata.yml` + `checker/` + sources). Then:

```bash
python3 seed_services/seed.py --list              # confirm discovery
python3 seed_services/seed.py --all               # build, upload, deploy, register
# or step-by-step:
python3 seed_services/seed.py --upload
python3 seed_services/seed.py --vulnboxes
python3 seed_services/seed.py --checker
python3 seed_services/seed.py --db
# scope to one service:
python3 seed_services/seed.py --all --service asm_chat
```

Caveats live in [`seed_services/README.md`](seed_services/README.md):
docker-compose services with locally-buildable Dockerfiles deploy cleanly;
services that depend on FAUST's private container registry
(`faust.cs.fau.de:5000/...`) need their dep images built locally first;
native (systemd-only) services need the FAUST install pipeline that's not
yet recreated here.

## Operator scripts (on the admin bastion)

```bash
team-ssh N [cmd...]              # SSH into team N's vulnbox (10.32.N.4)
team-restart-service N SERVICE   # restart a unit; SERVICE=compose bounces
                                 # all docker compose stacks under /opt
fetch-team-logs N [DEST]         # rsync /var/log from team N's vulnbox
presign-vpn N [SECONDS]          # signed S3 URL for team_N.ovpn (default
                                 # 3600s); for OOB distribution
```

The admin bastion is the only host with a public IP. Everything else
(gameserver, checker, VPN host, vulnboxes) is reached through it. The
admin's `~/.ssh/config` disables host-key tracking, so onward `ssh` and
`scp` calls work without prompting even after instance replacements.

## Tear the range down

```bash
terraform destroy
```

Destroy wipes the gameserver Postgres, all S3 service tarballs, and every
EC2 instance. Bringing the range back up is `terraform apply`; you'll need
to redistribute VPN configs and rerun `seed_services` to reinstall services.

## Architecture

### Networks

Two peered VPCs:

- **ranger_main** (10.50.0.0/16) — public-facing
  - `ranger_public` (10.50.0.0/25): VPN host, IGW
  - `ranger_routers` (10.50.1.0/24): admin, gameserver, checker
- **ranger_teams** (10.32.0.0/16) — team infra
  - per team: `10.32.<N>.0/24`, vulnbox at `.4`

VPN→VPC traffic isn't MASQUERADEd — VPC route tables send the tunnel
CIDRs back through the VPN host's ENI, so internal hosts see real client
source IPs. Only internet-bound VPN traffic is NATed.

### VPNs

Two OpenVPN daemons share one host:

- **Team VPN** (UDP 1201, tunnel pool 10.8.0.0/16). One cert per team,
  pinned to `10.8.<N>.10` via CCD. Single concurrent connection per team
  (no `duplicate-cn`).
- **Vulnbox-admin VPN** (UDP 1200, tunnel pool 10.9.0.0/24). Out-of-band
  channel for organizers; vulnboxes auto-connect at boot via S3-distributed
  client configs. The VPN host hairpin-MASQUERADEs traffic into `tun-vbox`
  so admin can reach a vulnbox via either the peering path or the tunnel
  IP (10.9.0.<x>) symmetrically.

### Gameserver

Upstream [`ctf-gameserver`](https://github.com/fausecteam/ctf-gameserver)
pinned to commit `cbc85804ded8827bd46c464088b4b0158eace26b` (last commit
before the pyproject migration that requires Python 3.13). Built from
source on first boot via `dpkg-buildpackage`. Runs:

- PostgreSQL (local cluster, listening on the routers subnet for the
  checker; HBA-restricted to the checker host's CIDR)
- Django scoreboard via uWSGI behind nginx on port 80
- `ctf-controller.service` (tick driver, flag generation, scheduling)
- `ctf-submission@31337.service` (flag intake; `CTF_TEAMREGEX` matches
  both `10.32.<id>.4` (vulnbox) and `10.8.<id>.10` (team VPN client))

### Checker

Same `.deb`, same pinned commit, installed on a separate host with full
L3 reach to every vulnbox. The `ctf-checkermaster@<slug>.service` template
schedules per-tick checks; `seed_services --checker` drops a per-service
env file at `/etc/ctf-gameserver/checker/<slug>.env` and enables one
template instance per declared service. Checker scripts run as the
`ctf-checkerrunner` system user (sudo'd into via the upstream-shipped
sudoers config) with `WorkingDirectory=/var/lib/ctf-checkerrunner` so
checkerlib's per-team state JSON files are persistable.

### Bootstrap details

- All cloud-init templates use a `bootcmd` retry loop around `apt-get
  update` because a fresh NAT gateway sometimes drops the very first
  fetch.
- The AWS CLI is installed via the bundled installer
  (`awscli.amazonaws.com`) instead of snap — the snap store has been
  intermittently unreachable from the VPC's NAT path.
- The gameserver bootstrap auto-seeds N team users (`team_<i>` + random
  password), `Team` rows with `net_number = i`, a `GameControl`
  singleton (tick=120s, start/end null), and a `TeamDownload` row for
  `openvpn.ovpn`. seed_services adds `Service` rows on top of that.

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

- FAUST native install pipeline (`make install DESTDIR=/`,
  `faustctf.target`, `docker-compose@.service` template) — services that
  rely on it (e.g. `veighty-machinery`, `ghost`) are skipped by
  seed_services with a warning.
- Local image builds for services that depend on private FAUST registry
  images (`faust.cs.fau.de:5000/...`).
- Postgres backup. Single-host DB, no scheduled snapshots; replacing the
  gameserver wipes the data (intentional for a testing range).
- Monitoring stack (Prometheus/Grafana).
