#!/usr/bin/env python3
"""Generate the contents of docker-bake.versions.json from poetry.lock"""
import json
import tomllib


def main():
    with open("poetry.lock", "rb") as f:
        lockfile = tomllib.load(f)

    packages = {p["name"]: p for p in lockfile["package"]}

    version_vars = json.dumps(
        {
            "MYTHRIL_VERSION": packages["mythril"]["version"],
            "BLAKE2B_VERSION": packages["blake2b-py"]["version"],
        },
        indent=2,
    )
    print(version_vars)


if __name__ == "__main__":
    main()
