# Ranger — Plan to Complete the A/D CTF Range

## 1. Reference architecture (what an A/D range actually needs)

Synthesized from FAUST `ctf-gameserver`, saarCTF, and the standard A/D pattern:

| Role | Purpose | Typical impl |
|---|---|---|
| **Vulnbox** (per team) | Runs the vulnerable services teams attack/defend. Teams get root on their own. | Identical VM image per team; services as systemd units or docker-compose. |
| **Gameserver / Controller** | Drives ticks (rounds), generates flags, updates scores, stores state. | Python daemon + PostgreSQL. |
| **Checker** | Every tick, places flags into each team's services and verifies previous flags. Measures SLA (up / down / compromised). | Per-service checker scripts, run by a master on a dedicated box or fleet. Needs L3 reach to every vulnbox service port. |
| **Submission server** | Accepts captured flags from teams over TCP (saarCTF: 31337). | Small daemon talking to the same Postgres. |
| **Scoreboard / Web** | Team registration, scoreboard, downloads (vpn configs, patches), admin. | Django (ctf-gameserver ships one). |
| **Team VPN** | Network isolation; teams reach each other, submission, scoreboard. | OpenVPN — already in place. |
| **Vulnbox-admin VPN** | Always-up out-of-band channel so organizers can reach the vulnbox even if the team breaks networking. | Second OpenVPN profile installed on each vulnbox, auto-connecting. |
| **Monitoring** | SLA dashboards, service uptime, Grafana, logs. | Optional but standard. |

Flag flow: Controller mints flag → Checker plants it in service N on team T → team T's opponents exploit service N on T, extract the flag, POST it to submission → Controller awards points → next tick Checker verifies previous flags still retrievable (SLA).

## 2. What Ranger has today

- Two peered VPCs (main 10.50/16, teams 10.32/16).
- Per-team /24 subnet + empty Ubuntu 24.04 vulnbox (no services, no user_data).
- OpenVPN server with per-team + admin client configs auto-generated.
- Admin EC2 instance (bare).
- Security groups, NAT, IGW, routing.

## 3. What is missing

**Infrastructure (Terraform):**
- Gameserver EC2 (controller + submission + web, or split).
- Checker EC2 (needs full L3 reach to every team's vulnbox service ports).
- Postgres (RDS or on gameserver for a small range).
- Vulnbox-admin VPN (second OpenVPN on 1200 or similar, per-team client certs, auto-connect on vulnbox boot).
- Security groups allowing: checker → vulnbox service ports; team-VPN → submission:31337 & scoreboard:443; teams → each other on service ports.
- Route53 / internal DNS for `scoreboard.ctf`, `submission.ctf`.
- S3 bucket for vulnbox image distribution + checker script storage.
- IAM roles for EC2 (SSM, CloudWatch), not default creds.
- CloudWatch log groups, VPC Flow Logs.

**Software / provisioning (not in repo at all):**
- Vulnbox provisioning: cloud-init on the stock Ubuntu 24.04 AMI (no Packer). Installs services, systemd units, admin-VPN client, unprivileged `ctf` user, SSH hardening, baseline tools for teams (tcpdump, strace, docker). Service bundle pulled from S3 at first boot.
- Service implementations — the actual vulnerable apps (usually 3–5 per event). Source + Dockerfiles + intended exploits, tarballed to S3.
- Checker scripts per service, using `ctf-gameserver/checkerlib`.
- `ctf-gameserver` deployment: Ansible role (upstream provides one) targeting the gameserver + checker hosts.
- Scoreboard theming + team registration flow.
- Team-downloads: VPN configs, rulebook, service source (teams run the same Ubuntu + cloud-init locally if they want a disposable copy).

**Ops / tooling (not in repo):**
- Runbook: how to start/stop a round, rotate VPN creds, re-deploy a vulnbox, revoke a team.
- Admin scripts on the admin instance: SSH-to-team-N, restart-service, pull-logs.
- Backup/restore for Postgres.
- Incident playbook (team DoS, VPN flood, service wedge).

## 4. Proposed phased plan

### Phase 1 — Terraform gaps (1–2 days)
1. Add `gameserver/` module: EC2 in `ranger_main`, security group allowing submission (31337) + web (443) from team VPN CIDR only, outbound to checker + Postgres.
2. Add `checker/` module: EC2 in `ranger_main`, security group allowing egress to **all** team /24 service ports.
3. Add Postgres: start with `db.t4g.small` RDS in a private subnet, or (cheaper) colocate on gameserver with daily snapshot to S3.
4. Add second OpenVPN instance (or second daemon on same host) on a distinct port + CIDR for the "vulnbox-admin" channel. Generate one client cert per team, ship it inside the vulnbox image.
5. Wire vulnbox `user_data` in `team/` as a cloud-init template that: installs base packages (openvpn, docker, docker-compose, tcpdump, strace), drops the team-specific admin-VPN client cert (rendered from the OpenVPN module's easy-rsa state), enables the admin-VPN systemd unit, pulls the service bundle tarball from S3, and starts it via docker-compose. No Packer, no custom AMI — stock Ubuntu 24.04 from `ami.tf`.
6. IAM instance profiles with SSM + CloudWatch agent; enable VPC Flow Logs.
7. Add Route53 private zone `ctf.internal` with A records for gameserver/submission/scoreboard.

### Phase 2 — Vulnbox cloud-init (1–2 days)
1. `team/vulnbox_cloud_init.yaml.tftpl` — stock Ubuntu 24.04 + cloud-init that installs packages, hardens SSH, adds `ctf` user (teams' login), drops admin-VPN client cert, enables admin-VPN systemd unit, pulls service bundle from S3, starts docker-compose.
2. Package a placeholder service bundle (one dummy service) as a tarball in S3 to prove end-to-end flag plant/capture before real services exist.
3. `team/` module renders the template with per-team values (team id, admin-VPN cert, S3 bundle URL) and passes it via `user_data`. Boot time: ~2–3 min vs instant for a baked AMI — acceptable for a range you re-apply rarely.

### Phase 3 — Gameserver deployment (2–3 days)
1. Ansible playbook invoking upstream `ctf-gameserver-ansible` roles against gameserver + checker hosts. Triggered by `null_resource` in Terraform or a separate bootstrap script on the admin box.
2. Configure `CTF_SERVICE`, `CTF_CHECKERSCRIPT`, `CTF_INTERVAL` per service.
3. Seed Django with teams, services, tick length, flag prefix.
4. Smoke test: controller ticks, checker plants flag in dummy service, manual flag submission awards points.

### Phase 4 — Services + checkers (event-specific, iterative)
1. Choose/author 3–5 services. Each lives in its own repo with `service/`, `checker/`, `exploit/` (for organizers), `writeup.md`.
2. Bundle into the vulnbox image via Phase 2.
3. Checker scripts deployed to checker host; each service gets a systemd `ctf-checker@service.service` instance.

### Phase 5 — Ops hardening (1–2 days)
1. Admin-box scripts: `team-ssh N`, `team-restart-service N svc`, `fetch-team-logs N`.
2. Grafana + Prometheus on the admin box; node_exporter on vulnboxes scraped over the admin-VPN.
3. Postgres backups to S3, lifecycle 30d.
4. Runbook in `docs/ops.md` (start-of-event, during-event, end-of-event checklists).
5. Fire drill: kill a vulnbox mid-round, confirm checker reports `DOWN` and restore works.

### Phase 6 — Pre-event dress rehearsal (0.5 day)
Full end-to-end with 2 dummy teams, 1 real service, 2-hour mock game. Fix whatever breaks.

## 5. Open decisions to make before Phase 1

- **Gameserver: ctf-gameserver vs saarCTF vs CTForge?** Recommend `ctf-gameserver` — actively maintained, Ansible roles exist, clean DB-only inter-component model fits AWS fine.
- **RDS vs Postgres-on-EC2?** For ≤ ~30 teams, on-EC2 with EBS snapshots is simpler and ~10× cheaper.
- **Vulnbox distribution to teams**: teams can't snapshot an AMI they don't own. Options: (a) publish the cloud-init template + service tarball to teams so they can reproduce locally with any Ubuntu 24.04 VM, (b) share the AMI cross-account if teams are in AWS, (c) skip — teams operate only on the provisioned vulnbox. (a) is cheapest and fits the "stock Ubuntu + cloud-init" decision.
- **Tick length**: 60s (FAUST) vs 120–180s (saarCTF). Longer = kinder to checker fleet.
- **Flag format**: adopt ctf-gameserver default `RANGER_<base64>` with MAC; no custom work.

## 6. Rough effort estimate

| Phase | Days |
|---|---|
| 1 — Terraform gaps | 1.5 |
| 2 — Vulnbox cloud-init | 1.5 |
| 3 — Gameserver deploy | 2.5 |
| 4 — One real service + checker | 3 per service |
| 5 — Ops hardening | 1.5 |
| 6 — Dress rehearsal | 0.5 |

≈ 7.5 engineer-days of platform work + N×3 days for N services.

## References

- ctf-gameserver docs: <https://ctf-gameserver.org/> (architecture, installation, setup)
- ctf-gameserver source: <https://github.com/fausecteam/ctf-gameserver>
- saarCTF infrastructure: <https://github.com/MarkusBauer/saarctf-servers>
- FAUST CTF info pages (per-year rules/topology)
- CTForge: <https://github.com/secgroup/ctforge>
