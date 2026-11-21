"""Publish only a complete, verified draft. A retry never overwrites an asset or tag."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from version import STABLE, parts, version_code

DEMO = "https://ilyasyoy.github.io/stack-attack/"


def api(endpoint, *args, payload=None):
    command = ["gh", "api", endpoint, *args]
    if payload is not None:
        command += ["--input", "-"]
    return subprocess.check_output(command, input=json.dumps(payload) if payload is not None else None,
                                   text=True)


def listing(endpoint):
    output = api(endpoint, "--paginate", "--jq", ".[] | @json")
    return [json.loads(line) for line in output.splitlines()]


def select_version(requested, sha, tags, releases):
    stable = {t["name"][1:]: t["commit"]["sha"] for t in tags
              if t["name"].startswith("v") and STABLE.fullmatch(t["name"][1:])}
    latest = max(stable, key=parts, default=None)
    assigned = {v for v, source in stable.items() if source == sha}
    assigned.update(r["tag_name"][1:] for r in releases if r["target_commitish"] == sha
                    and r["tag_name"].startswith("v") and STABLE.fullmatch(r["tag_name"][1:]))
    if len(assigned) > 1 or (requested and assigned and requested not in assigned):
        raise ValueError(f"Source already has a different stable version: {sorted(assigned)}")
    if requested or assigned:
        version = requested or next(iter(assigned))
    elif latest is not None:
        major, minor, patch = parts(latest)
        version = f"{major}.{minor}.{patch + 1}"
    else:
        raise ValueError("Choose the first stable version using the manual workflow")
    version_code(version)
    return version, stable.get(latest)


def state(version, sha, tags, releases):
    """Only our draft for this exact version and source may be resumed."""
    tag = "v" + version
    marker = f"<!-- stack-attack-release-v1 {tag} {sha} -->"
    matches = [r for r in releases if r["tag_name"] == tag]
    if len(matches) > 1:
        raise ValueError("Multiple releases or drafts for the same tag")
    current = next(iter(matches), None)
    target = next((t["commit"]["sha"] for t in tags if t["name"] == tag), None)
    if current and (current["target_commitish"] != sha or marker not in (current["body"] or "").splitlines()):
        raise ValueError("Conflicting release or draft")
    if target and (target != sha or not current):
        raise ValueError("Conflicting tag")
    if current and not current["draft"]:
        if target != sha:
            raise ValueError("Published tag/source mismatch")
        apk, web = f"stack-attack-{tag}.apk", f"stack-attack-{tag}-web.zip"
        sums = ""
        expected = {}
        for name in (apk, web):
            match = re.search(r"^([0-9a-f]{64})  " + re.escape(name) + "$", current["body"], re.M)
            if not match:
                raise ValueError("Published checksum missing")
            expected[name] = "sha256:" + match[1]
            sums += match[0] + "\n"
        expected["SHA256SUMS.txt"] = "sha256:" + hashlib.sha256(sums.encode()).hexdigest()
        if {a["name"]: a.get("digest") for a in current["assets"]} != expected:
            raise ValueError("Published release assets differ from its checksums")
        return "published", current
    for name in [t["name"] for t in tags] + [r["tag_name"] for r in releases]:
        if name.startswith("v") and STABLE.fullmatch(name[1:]) and parts(name[1:]) > parts(version):
            raise ValueError(f"A higher version already exists: {name}")
    return "draft" if current else "new", current


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def release(mode, version, sha, directory=None):
    if mode not in ("plan", "publish") or not re.fullmatch("[0-9a-f]{40}", sha):
        raise ValueError("Invalid operation or source SHA")
    repo = os.environ["GITHUB_REPOSITORY"]
    base = f"repos/{repo}"
    tags = listing(base + "/tags?per_page=100")
    releases = listing(base + "/releases?per_page=100")
    version, latest_source = select_version(version, sha, tags, releases)
    tag = "v" + version
    status, record = state(version, sha, tags, releases)
    if status != "published" and latest_source and latest_source != sha:
        relation = json.loads(api(f"{base}/compare/{latest_source}...{sha}", "--jq", "{status}"))
        if relation["status"] != "ahead":
            raise ValueError("The source must descend from the highest stable tag")
    if mode == "plan":
        with Path(os.environ["GITHUB_OUTPUT"]).open("a") as out:
            print(f"version={version}", file=out)
            print("needed=" + ("false" if status == "published" else "true"), file=out)
    if status == "published" or mode == "plan":
        print(f"{tag} @ {sha}: {status}")
        return

    folder = Path(directory)
    apk, web = [folder / f"stack-attack-{tag}{suffix}" for suffix in (".apk", "-web.zip")]
    sums = folder / "SHA256SUMS.txt"
    sums.write_text("".join(f"{digest(p)}  {p.name}\n" for p in (apk, web)))
    expected = {p.name: "sha256:" + digest(p) for p in (apk, web, sums)}
    body = (f"Stack Attack {version} · Android versionCode {version_code(version)}\n\n"
            f"Source commit: `{sha}`\n\nAPK certificate SHA-256: `{os.environ['APK_SIGNING_CERT_SHA256']}`\n\n"
            f"[Live demo (independently deployed)]({DEMO})\n\n"
            f"SHA-256\n\n```text\n{sums.read_text()}```\n\n"
            f"<!-- stack-attack-release-v1 {tag} {sha} -->")
    if status == "new":
        record = json.loads(api(base + "/releases", payload={
            "tag_name": tag, "name": f"Stack Attack {tag}", "target_commitish": sha,
            "draft": True, "body": body,
        }))
    if record["body"] != body:
        raise ValueError("Draft belongs to different build bytes. Retry the original publish job.")
    endpoint = base + f"/releases/{record['id']}"
    assets = {a["name"]: a for a in listing(endpoint + "/assets?per_page=100")}
    for name, asset in assets.items():
        if expected.get(name) != asset.get("digest") or name not in expected or asset["state"] != "uploaded":
            raise ValueError(f"Conflicting draft asset: {name}")
    for name in expected.keys() - assets.keys():
        api(f"https://uploads.github.com/{endpoint}/assets?name={name}", "--method", "POST",
            "-H", "Content-Type: application/octet-stream", "--input", str(folder / name))
    if {a["name"]: a["digest"] for a in listing(endpoint + "/assets?per_page=100")} != expected:
        raise ValueError("Remote asset checksums do not match")
    # Reserve the exact commit before publication. Never force or move a ref.
    if tag not in {t["name"] for t in tags}:
        api(base + "/git/refs", payload={"ref": "refs/tags/" + tag, "sha": sha})
    ref = json.loads(api(base + "/git/ref/tags/" + tag))["object"]
    if ref["type"] != "commit" or ref["sha"] != sha:
        raise ValueError("Tag does not point directly to source commit")
    final = json.loads(api(endpoint, "--method", "PATCH", payload={"draft": False}))
    if final["draft"] or final["tag_name"] != tag:
        raise RuntimeError("Publication not confirmed")
    print(final["html_url"])


if __name__ == "__main__":
    release(*sys.argv[1:])
