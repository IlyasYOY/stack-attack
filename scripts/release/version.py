"""Allocate Android codes in the same order as stable vMAJOR.MINOR.PATCH tags."""
import re
import sys

STABLE = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")


def parts(version):
    match = STABLE.fullmatch(version)
    if not match:
        raise ValueError("Use stable MAJOR.MINOR.PATCH without a v prefix or leading zeros")
    return tuple(map(int, match.groups()))


def version_code(version):
    major, minor, patch = parts(version)
    if major > 2099 or minor > 999 or patch > 999:
        raise ValueError("Supported ranges: major 0..2099, minor and patch 0..999")
    return 1 + major * 1_000_000 + minor * 1_000 + patch


if __name__ == "__main__":
    print(version_code(sys.argv[1]))
