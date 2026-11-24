#!/usr/bin/env python3
# meta-muse-ultra route cache: per-domain lane outcome hints (JSON file next to this script).
# Usage:
#   routecache.py get <domain>          -> prints "l0=<v> l1=<v>" (ok | F-* | -), entries older than 7d ignored
#   routecache.py set <domain> <lane> <value>
import sys, os, json, time
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "route-cache.json")
MAXAGE = 7 * 24 * 3600

def load():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except Exception:
        return {}

def save(data):
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, CACHE)

def domain_of(s):
    if "://" in s:
        return (urlparse(s).hostname or s).lower()
    return s.lower()

def main():
    if len(sys.argv) < 3:
        print("l0=- l1=-")
        return
    cmd, dom = sys.argv[1], domain_of(sys.argv[2])
    data = load()
    now = time.time()
    if cmd == "get":
        ent = data.get(dom) or {}
        if now - ent.get("ts", 0) > MAXAGE:
            ent = {}
        print("l0=%s l1=%s" % (ent.get("l0", "-"), ent.get("l1", "-")))
    elif cmd == "set" and len(sys.argv) >= 5:
        lane, value = sys.argv[3], sys.argv[4]
        ent = data.get(dom) or {}
        ent[lane] = value
        ent["ts"] = now
        data[dom] = ent
        save(data)

if __name__ == "__main__":
    main()
