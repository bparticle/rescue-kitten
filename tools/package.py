"""Build a sideload ZIP and check Solana OS package limits."""

import json
import re
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "apps" / "dust-range"
OUTPUT = ROOT / "dist" / "dust-range.zip"
PATH_COMPONENT = re.compile(r"[a-z0-9_-](?:[a-z0-9_.-]*[a-z0-9_-])?")


def build():
    files = {p.relative_to(APP).as_posix(): p.read_bytes() for p in sorted(APP.rglob("*")) if p.is_file()}
    for name in ("main.lua", "app.json"):
        if name not in files:
            raise ValueError(f"Missing {name}")
    if len(files["main.lua"]) > 64 * 1024:
        raise ValueError("main.lua exceeds 64 KiB")

    bundled = {name: file for name, file in files.items() if name not in {"main.lua", "app.json"}}
    size = 0
    for name, content in bundled.items():
        parts = name.split("/")
        if len(name) > 64 or len(parts) > 4 or not all(PATH_COMPONENT.fullmatch(part) for part in parts):
            raise ValueError(f"Invalid bundled path {name}")
        length = len(content)
        if length > 256 * 1024:
            raise ValueError(f"{name} exceeds 256 KiB")
        size += length
    if len(bundled) > 64 or size > 1024 * 1024:
        raise ValueError(f"Package exceeds 64 bundled files or 1 MiB ({len(bundled)} files, {size} bytes)")

    manifest = json.loads(files["app.json"])
    OUTPUT.parent.mkdir(exist_ok=True)
    with TemporaryDirectory(dir=OUTPUT.parent) as staging:
        pending = Path(staging) / OUTPUT.name
        with ZipFile(pending, "w", ZIP_DEFLATED, compresslevel=9) as archive:
            for name, content in files.items():
                archive.writestr(name, content)
        with ZipFile(pending) as archive:
            if archive.testzip() is not None or set(archive.namelist()) != set(files):
                raise ValueError("ZIP integrity check failed")
        pending.replace(OUTPUT)

    permissions = ", ".join(manifest.get("permissions", [])) or "none"
    print(f"Dust Range {manifest['version']} | {len(bundled)}/64 bundled files | {size:,}/1,048,576 bytes")
    print(f"Permissions {permissions} | ZIP {OUTPUT.stat().st_size:,} bytes")


if __name__ == "__main__":
    build()
