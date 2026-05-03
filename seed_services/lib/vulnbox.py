"""Install a service onto every team's vulnbox.

For docker-compose services we extract under /opt/<slug>/ and run
`docker compose up -d --build`. Native (systemd-only) services need their
Makefile's `make install DESTDIR=/` plus per-service postinst — those aren't
auto-installed yet (the FAUST install pipeline expects `faustctf.target` and a
`docker-compose@.service` template that we don't ship). They're flagged as
TODO and skipped so the docker majority can deploy unblocked.
"""
from __future__ import annotations

from pathlib import Path

from . import ssh
from .service import Service


def install(
    *,
    admin_ip: str,
    key: Path,
    bucket: str,
    region: str,
    num_teams: int,
    service: Service,
) -> dict[int, str]:
    """Install `service` on every vulnbox. Returns {team_id: status}."""
    if not service.has_docker_compose:
        return {i: "skipped: native service install not implemented" for i in range(1, num_teams + 1)}

    compose_rel = _compose_relative(service)
    script = _vulnbox_install_script(
        slug=service.slug,
        bucket=bucket,
        region=region,
        compose_rel=compose_rel,
    )

    results: dict[int, str] = {}
    for team_id in range(1, num_teams + 1):
        host = f"10.32.{team_id}.4"
        try:
            ssh.host_run(admin_ip, key, host, script, capture=True)
            results[team_id] = "ok"
        except Exception as exc:  # pragma: no cover — surface failure per host
            results[team_id] = f"failed: {exc}"
    return results


def _compose_relative(service: Service) -> str:
    p = service.docker_compose_path
    assert p is not None
    return str(p.relative_to(service.path))


def _vulnbox_install_script(*, slug: str, bucket: str, region: str, compose_rel: str) -> str:
    return f"""\
set -euo pipefail

SLUG={slug}
BUCKET={bucket}
REGION={region}
COMPOSE_REL={compose_rel}
DEST=/opt/$SLUG

if ! command -v aws >/dev/null; then
    for attempt in 1 2 3 4 5; do
        if curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip; then
            sudo apt-get install -y unzip >/dev/null
            unzip -qo /tmp/awscliv2.zip -d /tmp
            sudo /tmp/aws/install --update >/dev/null
            sudo rm -rf /tmp/aws /tmp/awscliv2.zip
            break
        fi
        sleep 5
    done
fi

sudo install -d -m 0755 "$DEST"
sudo aws --region "$REGION" s3 cp "s3://$BUCKET/services/$SLUG.tar.gz" "/tmp/$SLUG.tar.gz"
sudo tar xzf "/tmp/$SLUG.tar.gz" -C "$DEST"
sudo rm -f "/tmp/$SLUG.tar.gz"

cd "$DEST"
COMPOSE_DIR="$(dirname "$COMPOSE_REL")"
COMPOSE_FILE="$(basename "$COMPOSE_REL")"
cd "$COMPOSE_DIR"
sudo docker compose -f "$COMPOSE_FILE" pull --ignore-pull-failures || true
sudo docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans
"""
