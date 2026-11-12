#!/usr/bin/env python3
"""Create a project-specific TEST key outside the checkout; never a release key."""
import argparse
import os
from pathlib import Path
import secrets
import shlex
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path, help="Private directory OUTSIDE the repository")
args = parser.parse_args()
repository = Path(__file__).resolve().parents[1]
directory = args.directory.expanduser().resolve()
if directory.is_relative_to(repository):
    parser.error("Signing files must be outside the repository")
directory.mkdir(parents=True, exist_ok=True, mode=0o700)
key = directory / "stack-attack-tech-debug.keystore"
activation = directory / "debug-signing.env"
if key.exists() or activation.exists():
    if not (key.is_file() and activation.is_file()):
        parser.error("Incomplete signing directory; refusing to overwrite")
    print("Existing test signing files preserved.")
else:
    os.umask(0o077)
    password = secrets.token_urlsafe(32)
    alias = "stack-attack-tech-debug"
    env = os.environ.copy()
    env["STACK_ATTACK_KEY_PASSWORD"] = password
    subprocess.run([
        "keytool", "-genkeypair", "-keystore", str(key),
        "-storepass:env", "STACK_ATTACK_KEY_PASSWORD",
        "-keypass:env", "STACK_ATTACK_KEY_PASSWORD", "-alias", alias,
        "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
        "-dname", "CN=Stack Attack Technical Debug", "-noprompt",
    ], env=env, check=True, capture_output=True)
    values = {
        "GODOT_ANDROID_KEYSTORE_DEBUG_PATH": str(key),
        "GODOT_ANDROID_KEYSTORE_DEBUG_USER": alias,
        "GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD": password,
    }
    activation.write_text("\n".join(
        f"export {name}={shlex.quote(value)}" for name, value in values.items()
    ) + "\n")
    key.chmod(0o600)
    activation.chmod(0o600)
    print("Created a private TEST key. Keep both files for future test updates.")
print("Activate signing: source " + shlex.quote(str(activation)))
