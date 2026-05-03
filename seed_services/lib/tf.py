"""Read terraform outputs as a Python dict.

Kept as a thin wrapper so the rest of the module doesn't shell out directly.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path


def outputs(repo_root: Path) -> dict:
    """Return all root-module terraform outputs as {name: value}.

    Sensitive outputs are returned in cleartext — caller must not log them.
    """
    raw = subprocess.check_output(
        ["terraform", f"-chdir={repo_root}", "output", "-json"],
        cwd=repo_root,
    )
    data = json.loads(raw)
    return {k: v["value"] for k, v in data.items()}
