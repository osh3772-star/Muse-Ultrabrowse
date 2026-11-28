#!/usr/bin/env python3
"""vault-match.py — does agent-vault hold a credential for this host?

    python3 vault-match.py www.neonet.co.kr
    -> prints the entry name and exits 0
    -> prints nothing and exits 1 when no entry matches

Used by chain.sh to route a login wall (F-AUTH): with a stored credential
the caller continues inside this harness (vault-login.mjs,
next_action=vault-login, exit 5); without one the flow hands off to L2
(exit 3) as before.

Only metadata is read (meta.json: name / purpose / stored date — never a
value). Matching, in order:
  1. an explicit "site" field in the entry metadata: host equals it or is
     a subdomain of it;
  2. the entry name's first '-'-separated token (our naming convention is
     <site-slug>-<id>, e.g. neonet-80598881, zigbang-osh3629,
     google-osh3772) equals one of the host's DNS labels.

Free-text purpose is deliberately NOT mined for hosts: our purposes are
Korean prose that can mention unrelated domains (an email address in the
Google entry's purpose would false-match), which is why pickle's
prose-extraction matcher was not adopted as-is.
"""
import json
import os
import sys


def meta_path():
    env = os.environ.get("AGENT_VAULT_META")
    if env:
        return env
    return os.path.expanduser("~/workspace/agent-vault/meta.json")


def entries():
    try:
        with open(meta_path(), encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return []
        return [(k, v if isinstance(v, dict) else {}) for k, v in data.items()]
    except (OSError, ValueError):
        # No meta (vault not created yet) or a corrupt one: both answer
        # "no credential", the safe direction (caller hands off to L2).
        return []


def main(argv):
    if len(argv) < 2:
        print("usage: vault-match.py <host>", file=sys.stderr)
        return 2
    host = argv[1].lower().strip(".")
    if not host:
        return 1
    labels = [p for p in host.split(".") if p]
    for name, meta in entries():
        site = str(meta.get("site") or "").lower().strip(".")
        if site and (host == site or host.endswith("." + site)):
            print(name)
            return 0
        token = name.lower().split("-")[0].strip()
        if len(token) >= 3 and token in labels:
            print(name)
            return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
