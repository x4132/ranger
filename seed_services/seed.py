#!/usr/bin/env python3
"""seed_services — push A/D services onto a live Ranger range.

Workflow (each step is independently invokable via flags):
  1. Discover service repos under ../services/ (each with a metadata.yml).
  2. Build per-service tarballs and upload them to the VPN-configs S3 bucket.
  3. SSH (via the admin bastion) to each vulnbox; pull tarball; docker compose up.
  4. SSH to the checker host; pull tarball; install per-service deps.
  5. SSH to the gameserver; insert/update a Service row in the Django DB.

Reads `terraform output -json` to discover infra; expects `admin_key.pem` at
the repo root (same one Terraform writes during `apply`).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

# Pick up AWS_* (and anything else terraform needs) from .env so callers don't
# have to remember `source init.sh` before running this script.
import os  # noqa: E402

_env_file = REPO_ROOT / ".env"
if _env_file.is_file():
    for line in _env_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip("'").strip('"'))

from lib import build, checker, db, service, ssh, tf  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Deploy A/D services to a Ranger range.")
    parser.add_argument("--list", action="store_true", help="List discovered services and exit.")
    parser.add_argument("--upload", action="store_true", help="Build + upload service tarballs to S3.")
    parser.add_argument("--vulnboxes", action="store_true", help="Install services on every vulnbox.")
    parser.add_argument("--checker", action="store_true", help="Install checker scripts on the checker host.")
    parser.add_argument("--db", action="store_true", help="Register services in the gameserver Django DB.")
    parser.add_argument("--all", action="store_true", help="Run upload + vulnboxes + checker + db.")
    parser.add_argument("--service", help="Limit to a single service (by slug).")
    args = parser.parse_args()

    services_dir = REPO_ROOT / "services"
    if not services_dir.is_dir():
        print(f"no services/ directory at {services_dir}", file=sys.stderr)
        return 2

    services = service.discover(services_dir)
    if args.service:
        services = [s for s in services if s.slug == args.service]
        if not services:
            print(f"no service with slug={args.service!r}", file=sys.stderr)
            return 2

    if args.list or not (args.all or args.upload or args.vulnboxes or args.checker or args.db):
        for s in services:
            kind = "docker-compose" if s.has_docker_compose else "native"
            print(f"  {s.slug:20s} {kind:14s} {s.name}")
        return 0

    outputs = tf.outputs(REPO_ROOT)
    admin_ip = outputs["admin_public_ip"]
    bucket = outputs["vpn_configs_bucket"]
    region = outputs["aws_region"]
    num_teams = int(outputs["num_teams"])
    gameserver_ip = outputs["gameserver_private_ip"]
    checker_ip = outputs["checker_private_ip"]
    key = REPO_ROOT / "admin_key.pem"
    if not key.is_file():
        print(f"missing admin key at {key}", file=sys.stderr)
        return 2

    failures: list[str] = []

    if args.all or args.upload:
        for s in services:
            tar = build.tarball(s)
            url = build.upload(tar, s.slug, bucket, region)
            print(f"  uploaded {s.slug:20s} -> {url}")

    if args.all or args.vulnboxes:
        for s in services:
            print(f"== vulnbox install: {s.slug} ==")
            results = vulnbox_install(
                admin_ip=admin_ip, key=key, bucket=bucket, region=region,
                num_teams=num_teams, service=s,
            )
            for team_id, status in sorted(results.items()):
                print(f"  team {team_id}: {status}")
                if status != "ok":
                    failures.append(f"vulnbox/{s.slug}/team{team_id}: {status}")

    if args.all or args.checker:
        for s in services:
            print(f"== checker install: {s.slug} ==")
            status = checker.install(
                admin_ip=admin_ip, key=key, checker_ip=checker_ip,
                bucket=bucket, region=region, service=s,
            )
            print(f"  {status}")
            if status.startswith("failed:"):
                failures.append(f"checker/{s.slug}: {status}")

    if args.all or args.db:
        print("== seeding Service rows in gameserver DB ==")
        out = db.seed(
            admin_ip=admin_ip, key=key, gameserver_ip=gameserver_ip,
            services=services,
        )
        print(out.rstrip())

    if failures:
        print(f"\n== {len(failures)} failure(s) — exiting non-zero ==", file=sys.stderr)
        for f in failures:
            print(f"  {f}", file=sys.stderr)
        return 1

    return 0


def vulnbox_install(**kwargs) -> dict[int, str]:
    # Late import to keep the CLI help fast when --list is the only path used.
    from lib.vulnbox import install
    return install(**kwargs)


if __name__ == "__main__":
    raise SystemExit(main())
