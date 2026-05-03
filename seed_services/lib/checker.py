"""Install per-service checker scripts on the checker host.

Stages the source tree under /opt/checkers/<slug>/, installs Debian/pip deps
from metadata.yml, drops a per-service env file at
/etc/ctf-gameserver/checker/<slug>.env, and enables the
ctf-checkermaster@<slug>.service systemd instance shipped by the
ctf-gameserver Debian package the checker host built at boot.
"""
from __future__ import annotations

import shlex
from pathlib import Path

from . import ssh
from .service import Service


def install(
    *,
    admin_ip: str,
    key: Path,
    checker_ip: str,
    bucket: str,
    region: str,
    service: Service,
) -> str:
    if not service.checker_script:
        return "skipped: no checker.script_path declared"

    script = _checker_install_script(
        slug=service.slug,
        checker_script=service.checker_script,
        bucket=bucket,
        region=region,
        debian_packages=service.checker_debian_packages,
        pip_packages=service.checker_pip_packages,
    )
    try:
        ssh.host_run(admin_ip, key, checker_ip, script, capture=True)
        return "ok"
    except Exception as exc:  # pragma: no cover
        return f"failed: {exc}"


def _checker_install_script(
    *,
    slug: str,
    checker_script: str,
    bucket: str,
    region: str,
    debian_packages: list[str],
    pip_packages: list[str],
) -> str:
    deb = " ".join(shlex.quote(p) for p in debian_packages)
    pip = " ".join(shlex.quote(p) for p in pip_packages)
    return f"""\
set -euo pipefail

SLUG={slug}
BUCKET={bucket}
REGION={region}
DEST=/opt/checkers/$SLUG
CHECKER_SCRIPT_REL={shlex.quote(checker_script)}

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

if [ -n "{deb}" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y {deb}
fi
if [ -n "{pip}" ]; then
    sudo pip3 install --break-system-packages {pip}
fi

# Make the checker script executable for ctf-checkerrunner — checkermaster
# sudo's into that user to run each check.
sudo chmod +x "$DEST/$CHECKER_SCRIPT_REL"

# Per-slug env. checkermaster.env (DB creds, flag secret, IP pattern) is
# already on disk from the checker host's own cloud-init.
sudo install -d -m 0755 /etc/ctf-gameserver/checker
sudo tee /etc/ctf-gameserver/checker/$SLUG.env >/dev/null <<EOF
CTF_SERVICE=$SLUG
CTF_CHECKERSCRIPT=$DEST/$CHECKER_SCRIPT_REL
CTF_CHECKERCOUNT=1
CTF_INTERVAL=20
EOF

# Wait until the checker host's bootstrap finished installing the
# ctf-gameserver .deb (and its systemd template). Up to ~15 minutes since
# the build pulls a lot of apt deps on first boot.
for attempt in $(seq 1 90); do
    if dpkg -s ctf-gameserver >/dev/null 2>&1; then break; fi
    sleep 10
done

sudo systemctl daemon-reload
sudo systemctl enable --now "ctf-checkermaster@$SLUG.service"
"""
