"""Build per-service tarballs and upload them to the VPN-configs bucket."""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from .service import Service


def tarball(service: Service) -> Path:
    """Tar up a service's source tree (sans .git) into /tmp."""
    out = Path(tempfile.gettempdir()) / f"ranger-svc-{service.slug}.tar.gz"
    subprocess.check_call([
        "tar",
        "--exclude=.git",
        "--exclude=__pycache__",
        "-czf", str(out),
        "-C", str(service.path),
        ".",
    ])
    return out


def upload(tarball: Path, slug: str, bucket: str, region: str) -> str:
    s3_url = f"s3://{bucket}/services/{slug}.tar.gz"
    subprocess.check_call([
        "aws", "s3", "cp",
        "--region", region,
        "--sse", "AES256",
        str(tarball), s3_url,
    ])
    return s3_url
