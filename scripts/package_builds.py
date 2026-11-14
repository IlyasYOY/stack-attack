#!/usr/bin/env python3
"""Package locally verified builds and identify their source commit."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]


def git(*arguments):
    return subprocess.check_output(["git", "-C", str(root), *arguments], text=True).strip()


if git("status", "--porcelain"):
    raise SystemExit("Commit source changes before packaging the tested build.")
commit = git("rev-parse", "HEAD")
build = root / "build"
apk = build / "android/stack-attack-prototype-debug.apk"
web = build / "web"
for required in [apk, web / "index.html", web / "index.pck", web / "index.wasm", build / "web-check.json"]:
    if not required.is_file():
        raise SystemExit(f"Missing {required}; export and check Web first.")
for target in ["web", "android"]:
    directory = build / target
    record = json.loads((directory / "build-source.json").read_text())
    if record["commit"] != commit or not record["source_clean"]:
        raise SystemExit(f"Re-export {target} from the current clean commit first.")
    for filename, expected in record["files"].items():
        if hashlib.sha256((directory / filename).read_bytes()).hexdigest() != expected:
            raise SystemExit(f"Exported bytes changed: {target}/{filename}")
web_check = json.loads((build / "web-check.json").read_text())
if (web_check["status"] != "PASS" or web_check["pck_sha256"] !=
        hashlib.sha256((web / "index.pck").read_bytes()).hexdigest()):
    raise SystemExit("Check the current Web export before packaging.")
destination = build / "deliverables"
destination.mkdir(exist_ok=True)
prefix = f"stack-attack-prototype-{commit[:12]}"
copied_apk = destination / f"{prefix}-debug.apk"
shutil.copy2(apk, copied_apk)
archive = destination / f"{prefix}-web.zip"
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as output:
    for file in sorted(web.iterdir()):
        if file.is_file():
            output.write(file, "web/" + file.name)
    output.writestr("README.txt", (
        "Stack Attack: first playable prototype.\n"
        f"Source commit: {commit}\n"
        "Extract, then: python3 -m http.server 8765 --directory web\n"
        "Open http://127.0.0.1:8765 (not file://). Requires WebGL 2.\n"
        "No public hosting or release has been published.\n"
    ))
manifest = {
    "commit": commit,
    "godot": (root / ".godot-version").read_text().strip(),
    "android": {"package": "org.ilyasyoy.stackattack.techtest", "version_code": 11,
                "min_sdk": 24, "target_sdk": 36, "abi": "arm64-v8a", "signing": "test debug"},
    "phone_run": "prototype not tested; earlier technical APK accepted by owner",
    "web_check": web_check,
    "files": [{"name": file.name, "bytes": file.stat().st_size,
               "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
              for file in [copied_apk, archive]],
}
manifest_path = destination / f"{prefix}-manifest.json"
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"commit": commit, "files": [str(copied_apk), str(archive), str(manifest_path)]}, indent=2))
