"""Insert/update Service rows in the gameserver Django DB.

Uses django-admin shell on the gameserver host so we can speak to the ORM
directly without copying secrets to the seed_services machine.
"""
from __future__ import annotations

import json
from pathlib import Path

from . import ssh
from .service import Service


def seed(
    *,
    admin_ip: str,
    key: Path,
    gameserver_ip: str,
    services: list[Service],
) -> str:
    """Idempotently upsert a Service row per declared service."""
    payload = json.dumps([
        {"slug": s.slug, "name": s.name, "margin": 30}
        for s in services
    ])
    script = _gameserver_seed_script(payload)
    return ssh.host_run(admin_ip, key, gameserver_ip, script, capture=True)


def _gameserver_seed_script(payload_json: str) -> str:
    return f"""\
set -euo pipefail

cat > /tmp/seed_services_payload.json <<'PAYLOAD_EOF'
{payload_json}
PAYLOAD_EOF

sudo PYTHONPATH=/etc/ctf-gameserver/web DJANGO_SETTINGS_MODULE=prod_settings \\
    python3 - <<'PY'
import json
import django
django.setup()
from ctf_gameserver.web.scoring.models import Service

with open("/tmp/seed_services_payload.json") as f:
    payload = json.load(f)

for entry in payload:
    obj, created = Service.objects.update_or_create(
        slug=entry["slug"],
        defaults={{"name": entry["name"], "margin": entry["margin"]}},
    )
    print(f"{{'created' if created else 'updated'}} service {{obj.slug}} ({{obj.name}})")
PY

rm -f /tmp/seed_services_payload.json
"""
