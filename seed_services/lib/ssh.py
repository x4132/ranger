"""ssh / scp wrappers that always go via the admin bastion.

Range hosts have rotating IPs and host keys (cloud-init re-runs replace them),
so we disable host-key tracking outright — same posture as the admin's own
~/.ssh/config that the bastion image ships with.
"""
from __future__ import annotations

import shlex
import subprocess
from pathlib import Path

_BASE_OPTS = [
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "LogLevel=ERROR",
]


def admin_run(admin_ip: str, key: Path, script: str, *, capture: bool = False) -> str:
    """Run a bash script on the admin bastion. Returns stdout if capture=True."""
    cmd = [
        "ssh", *_BASE_OPTS,
        "-i", str(key),
        f"ubuntu@{admin_ip}",
        "bash", "-s",
    ]
    result = subprocess.run(
        cmd,
        input=script.encode(),
        capture_output=True,
    )
    if result.returncode != 0:
        stderr = result.stderr.decode(errors="replace").strip()
        stdout = result.stdout.decode(errors="replace").strip()
        raise RuntimeError(
            f"ssh exit={result.returncode}\n"
            f"--- stderr ---\n{stderr}\n--- stdout tail ---\n{stdout[-1000:]}"
        )
    return result.stdout.decode() if capture else ""


def host_run(admin_ip: str, key: Path, host: str, script: str, *, capture: bool = False) -> str:
    """Run a bash script on `host` (a private IP) via the admin bastion."""
    inner = " ".join([
        "ssh", *_BASE_OPTS,
        f"ubuntu@{host}",
        "bash", "-s",
    ])
    return admin_run(admin_ip, key, f"{inner} <<'__INNER_EOF__'\n{script}\n__INNER_EOF__\n", capture=capture)


def host_put(admin_ip: str, key: Path, host: str, src: Path, dst: str) -> None:
    """Copy a local file onto the admin bastion, then onto `host`."""
    name = src.name
    # Stage on admin first.
    subprocess.run(
        ["scp", *_BASE_OPTS, "-i", str(key), str(src), f"ubuntu@{admin_ip}:/tmp/{name}"],
        check=True,
    )
    # Hop to the inner host.
    admin_run(admin_ip, key, f"scp {' '.join(_BASE_OPTS)} /tmp/{name} ubuntu@{host}:/tmp/{name}")
