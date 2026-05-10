"""Install a service onto every team's vulnbox.

For docker-compose services we extract under /opt/<slug>/ and run
`docker compose up -d --build`. For native (FAUST-style) services without a
top-level `docker-compose.yml`, we run `make install DESTDIR=...`, rsync the
staging tree onto /, and start any `.socket` / `.service` units the install
shipped under /etc/systemd/system/.
"""
from __future__ import annotations

import concurrent.futures
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
    """Install `service` on every vulnbox in parallel. Returns {team_id: status}."""
    if service.has_docker_compose:
        compose_rel = _compose_relative(service)
        script = _vulnbox_compose_install_script(
            slug=service.slug,
            bucket=bucket,
            region=region,
            compose_rel=compose_rel,
        )
    else:
        script = _vulnbox_native_install_script(
            slug=service.slug,
            bucket=bucket,
            region=region,
            debian_packages=service.vulnbox_debian_packages,
            postinst_commands=service.vulnbox_postinst_commands,
        )

    def _one(team_id: int) -> tuple[int, str]:
        host = f"10.32.{team_id}.4"
        prefix = f"team{team_id}/{service.slug}"
        try:
            ssh.host_run(admin_ip, key, host, script, prefix=prefix)
            return team_id, "ok"
        except Exception as exc:  # pragma: no cover — surface failure per host
            return team_id, f"failed: {exc}"

    results: dict[int, str] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=num_teams) as pool:
        for team_id, status in pool.map(_one, range(1, num_teams + 1)):
            results[team_id] = status
    return results


def _compose_relative(service: Service) -> str:
    p = service.docker_compose_path
    assert p is not None
    return str(p.relative_to(service.path))


def _vulnbox_compose_install_script(*, slug: str, bucket: str, region: str, compose_rel: str) -> str:
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


def _vulnbox_native_install_script(
    *,
    slug: str,
    bucket: str,
    region: str,
    debian_packages: list[str],
    postinst_commands: list[str],
) -> str:
    deb = " ".join(p for p in debian_packages)
    # Bash-format the postinst commands as a here-doc; the FAUST metadata
    # convention is shell-line-per-entry. Best-effort wrap each in `|| true`
    # so a postinst that's already been applied (idempotent re-runs) doesn't
    # abort the whole install.
    postinst_block = "\n".join(f"    {c} || true" for c in postinst_commands) or "    :"
    return f"""\
set -euo pipefail

SLUG={slug}
BUCKET={bucket}
REGION={region}
DEST=/opt/$SLUG
DIST="$DEST/dist_root"
SVC_DIR="/srv/$SLUG"

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

# Build deps + service-declared deps. Most native FAUST services need a C
# toolchain to `make install`, so always pull build-essential.
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \\
    build-essential rsync python3 {deb}

sudo install -d -m 0755 "$DEST"
sudo aws --region "$REGION" s3 cp "s3://$BUCKET/services/$SLUG.tar.gz" "/tmp/$SLUG.tar.gz"
sudo tar xzf "/tmp/$SLUG.tar.gz" -C "$DEST"
sudo rm -f "/tmp/$SLUG.tar.gz"

# Service user (FAUST convention) + service data dir referenced by postinst.
if ! id "$SLUG" >/dev/null 2>&1; then
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin "$SLUG"
fi
sudo install -d -m 0755 -o "$SLUG" -g "$SLUG" "$SVC_DIR" "$SVC_DIR/data" || true

# Stage the install tree under DIST then rsync onto /. `make install` doesn't
# accept being told the staging root for non-FAUST Makefiles, but the FAUST
# convention is `DESTDIR=...` and `SERVICEDIR=/srv/<slug>`.
cd "$DEST"
sudo make install DESTDIR="$DIST" SERVICEDIR="$SVC_DIR"
# Set service-user ownership on the staged tree *before* rsync so rsync -a
# carries it through. If we chown'd /srv/$SLUG after the fact, on a re-run
# we'd hit the live bindfs mountpoint at /srv/$SLUG/data — chown returns
# EPERM on a FUSE root and aborts under set -e. Guarded with -d because
# not every FAUST Makefile populates $SERVICEDIR (e.g., ghost installs
# directly under /srv/setup with no /srv/ghost/ subtree).
[ -d "$DIST$SVC_DIR" ] && sudo chown -R "$SLUG:$SLUG" "$DIST$SVC_DIR"
sudo rsync -a "$DIST/" /

# Run postinst commands literally. They may reference paths under /srv/<slug>
# or systemctl. Wrapped in || true so re-runs survive already-applied state.
sudo bash -euxc '
{postinst_block}
'

# FAUST services use `[Install] WantedBy=faustctf.target` to pull every
# service-side unit up at boot. The .target itself isn't part of any one
# service tarball — drop a stub if absent, then enable+start it so all
# .target.wants symlinks (set up by the postinst commands) take effect.
if [ ! -f /etc/systemd/system/faustctf.target ]; then
    sudo tee /etc/systemd/system/faustctf.target >/dev/null <<'TARGET'
[Unit]
Description=FAUST CTF service target
Requires=multi-user.target
After=multi-user.target
AllowIsolate=no

[Install]
WantedBy=multi-user.target
TARGET
fi

sudo systemctl daemon-reload
sudo systemctl enable --now faustctf.target

# Service-named units that *aren't* covered by faustctf.target (e.g. socket
# activation units like veighty-machinery.socket) — enable/start by name.
for unit in $(find /etc/systemd/system -maxdepth 1 -type f \( -name "$SLUG*.socket" -o -name "$SLUG.service" \)); do
    name=$(basename "$unit")
    sudo systemctl enable --now "$name" || true
done
"""
