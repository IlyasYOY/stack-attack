"""Check the APK's real manifest, alignment, notices and (when signed) sole signer."""
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

from version import version_code


def verify(apk, version, certificate=None):
    tools = Path(os.environ["ANDROID_HOME"], "build-tools/36.1.0")
    subprocess.run([tools / "zipalign", "-c", "-P", "16", "4", apk], check=True)
    badging = subprocess.check_output([tools / "aapt", "dump", "badging", apk], text=True)
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']*)'", badging, re.M)
    expected = ("org.ilyasyoy.stackattack", str(version_code(version)), version)
    if not package or package.groups() != expected or "application-debuggable" in badging.splitlines():
        raise ValueError(f"Expected a release APK with package, code and name {expected}")
    with zipfile.ZipFile(apk) as archive:
        for name in ("GODOT_LICENSE.txt", "GODOT_COPYRIGHT.txt"):
            if archive.read("assets/notices/" + name) != Path("notices", name).read_bytes():
                raise ValueError(f"Incorrect APK notice: {name}")
    if certificate is not None:
        if not re.fullmatch("[0-9a-f]{64}", certificate):
            raise ValueError("Set APK_SIGNING_CERT_SHA256 to 64 lowercase hex digits")
        output = subprocess.check_output([tools / "apksigner", "verify", "--verbose", "--print-certs", apk], text=True)
        digests = re.findall(r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-f]+)$", output, re.M)
        if digests != [certificate]:
            raise ValueError(f"Unexpected signing certificate(s): {digests}")
        print("Verified APK signer SHA-256:", certificate)
    print("Verified package, versionCode, versionName:", *expected)


if __name__ == "__main__":
    verify(*sys.argv[1:])
