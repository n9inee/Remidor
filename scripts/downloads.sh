#!/bin/sh
# Prints how often each release has been downloaded, from GitHub's public API.
# The zips are the app; the .sha256 files are the checksums, which the README badge counts too.
set -eu

repo="${1:-n9inee/Remidor}"

curl -fsS "https://api.github.com/repos/$repo/releases?per_page=100" | python3 -c "$(cat <<'PY'
import json, sys

def count(release, suffix):
    return sum(a["download_count"] for a in release["assets"] if a["name"].endswith(suffix))

apps = checks = 0
print(f"{'release':<10} {'date':<11} {'app':>4} {'checksum':>9}")
for release in json.load(sys.stdin):
    app, check = count(release, ".zip"), count(release, ".sha256")
    apps += app
    checks += check
    print(f"{release['tag_name']:<10} {release['published_at'][:10]:<11} {app:>4} {check:>9}")
print(f"{'total':<22} {apps:>4} {checks:>9}   (the badge shows {apps + checks})")
PY
)"
