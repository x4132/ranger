"""Service discovery + metadata parsing.

Each subdir under `services/` is treated as one A/D service. We read its
metadata.yml to pick up the slug, checker script path, and Debian/pip deps.
The parser handles the subset of YAML the FAUST metadata.yml files use —
just enough to avoid a hard dependency on PyYAML.
"""
from __future__ import annotations

import dataclasses
import re
from pathlib import Path


@dataclasses.dataclass
class Service:
    path: Path
    slug: str
    name: str
    checker_script: str | None
    checker_max_duration: int
    checker_pip_packages: list[str]
    checker_debian_packages: list[str]
    has_docker_compose: bool

    @property
    def docker_compose_path(self) -> Path | None:
        if not self.has_docker_compose:
            return None
        for candidate in (
            self.path / "docker-compose.yml",
            self.path / "src" / "docker-compose.yml",
        ):
            if candidate.is_file():
                return candidate
        return None


def discover(services_root: Path) -> list[Service]:
    out: list[Service] = []
    for sub in sorted(p for p in services_root.iterdir() if p.is_dir()):
        meta = sub / "metadata.yml"
        if not meta.is_file():
            continue
        out.append(_parse(sub, meta))
    return out


def _parse(path: Path, meta: Path) -> Service:
    text = meta.read_text()
    slug = _scalar(text, "slug") or path.name
    name = _scalar(text, "name") or slug
    checker_script = _nested_scalar(text, "checker", "script_path")
    checker_max_duration = int(_nested_scalar(text, "checker", "max_duration") or "60")
    checker_pip = _nested_list(text, "checker", "pip_packages")
    checker_deb = _nested_list(text, "checker", "debian_packages")

    has_compose = any(
        (path / p).is_file()
        for p in ("docker-compose.yml", "src/docker-compose.yml")
    )

    return Service(
        path=path,
        slug=slug,
        name=name,
        checker_script=checker_script,
        checker_max_duration=checker_max_duration,
        checker_pip_packages=checker_pip,
        checker_debian_packages=checker_deb,
        has_docker_compose=has_compose,
    )


# ---------- minimal YAML scanner ----------

def _scalar(text: str, key: str) -> str | None:
    """Return the value of a top-level scalar `key: value` line."""
    pattern = re.compile(rf"^{re.escape(key)}\s*:\s*(.*)$", re.MULTILINE)
    m = pattern.search(text)
    if not m:
        return None
    return _strip(m.group(1))


def _nested_scalar(text: str, parent: str, child: str) -> str | None:
    """Return the value of `child:` nested under top-level `parent:`."""
    block = _block_under(text, parent)
    if block is None:
        return None
    pattern = re.compile(rf"^\s+{re.escape(child)}\s*:\s*(.*)$", re.MULTILINE)
    m = pattern.search(block)
    if not m:
        return None
    return _strip(m.group(1))


def _nested_list(text: str, parent: str, child: str) -> list[str]:
    """Return the items of `child:` (a YAML list) nested under top-level `parent:`."""
    block = _block_under(text, parent)
    if block is None:
        return []
    # Find the child line, then read indented `- item` lines until indentation
    # drops back to (or below) the child's level.
    lines = block.splitlines()
    items: list[str] = []
    in_list = False
    list_indent = -1
    for line in lines:
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if not in_list:
            if stripped.startswith(f"{child}:"):
                in_list = True
                list_indent = indent
            continue
        if not stripped:
            continue
        if indent <= list_indent and not stripped.startswith("-"):
            break
        if stripped.startswith("- "):
            items.append(_strip(stripped[2:]))
    return items


def _block_under(text: str, parent: str) -> str | None:
    """Slice the YAML block belonging to a top-level key."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.startswith(f"{parent}:"):
            start = i + 1
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start, len(lines)):
        line = lines[j]
        if line and not line.startswith((" ", "\t", "#")):
            end = j
            break
    return "\n".join(lines[start:end])


def _strip(value: str) -> str:
    """Strip whitespace, comments, and YAML-style quotes."""
    value = value.split("#", 1)[0].strip()
    if (value.startswith("'") and value.endswith("'")) or (
        value.startswith('"') and value.endswith('"')
    ):
        value = value[1:-1]
    return value
