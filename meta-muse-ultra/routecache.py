#!/usr/bin/env python3
# meta-muse-ultra route cache: per-domain lane outcome hints (JSON file next to this script).
# Usage:
#   routecache.py get <domain>          -> prints "l0=<v> l1=<v>" (ok | F-* | -)
#   routecache.py set <domain> <lane> <value>
#
# Schema (2026-11-27 audit fix, MUSE-005/006/007/008): each lane carries its
# OWN timestamp; expiry is per lane AND per result value, so a transient L0
# failure no longer sticks for 7 days and refreshing L1 never extends L0.
#   {"example.com": {"l0": {"v": "F-NET", "ts": 1000.0}, "l1": {"v": "ok", "ts": 1100.0}}}
# The pre-2026-11-27 flat schema ({"l0": .., "l1": .., "ts": ..}) is migrated
# on load, keeping the old shared ts as each lane's starting ts.
#
# TTL policy (seconds): ok / F-IP / F-BOT are treated as durable route facts
# (7d). F-AUTH gets 24h (a session may appear later). Transient codes expire
# fast: F-NET 60s, F-TIMEOUT 120s, anything else 300s. F-EMPTY is a property
# of one page (an SPA shell), not of the domain, so it is never stored.
# UB_ROUTECACHE=0 disables the cache entirely (get -> "-", set -> no-op).
# Writes hold an flock around the whole read-modify-write and use a
# per-process tmp file, so concurrent writers cannot lose each other's
# updates or crash on a shared tmp path (measured pre-fix: 20 concurrent
# sets -> 2 domains survived, plus FileNotFoundError tracebacks).
# Cache failures must never break the caller: every error path degrades to
# "no hint".
import sys, os, json, time, fcntl
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "route-cache.json")
LOCK = CACHE + ".lock"

TTL = {"ok": 7 * 24 * 3600, "F-IP": 7 * 24 * 3600, "F-BOT": 7 * 24 * 3600,
       "F-AUTH": 24 * 3600, "F-NET": 60, "F-TIMEOUT": 120}
TTL_DEFAULT = 300
NO_STORE = {"F-EMPTY"}
DISABLED = os.environ.get("UB_ROUTECACHE") == "0"

def ttl_of(value):
    return TTL.get(value, TTL_DEFAULT)

def load():
    try:
        with open(CACHE) as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return {}
    except Exception:
        return {}
    # migrate flat entries in place (idempotent)
    for dom, ent in data.items():
        if isinstance(ent, dict) and ("l0" in ent or "l1" in ent) and "ts" in ent \
                and not any(isinstance(ent.get(k), dict) for k in ("l0", "l1")):
            ts = ent.get("ts", 0)
            data[dom] = {k: {"v": ent[k], "ts": ts} for k in ("l0", "l1") if k in ent}
    return data

def save(data):
    tmp = "%s.tmp.%d" % (CACHE, os.getpid())
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, CACHE)

def lane_value(ent, lane, now):
    item = ent.get(lane)
    if not isinstance(item, dict):
        return "-"
    if now - item.get("ts", 0) > ttl_of(item.get("v", "")):
        return "-"
    return item.get("v", "-")

def main():
    if len(sys.argv) < 3:
        print("l0=- l1=-")
        return
    cmd, dom = sys.argv[1], domain_of(sys.argv[2])
    now = time.time()
    if cmd == "get":
        if DISABLED:
            print("l0=- l1=-")
            return
        ent = load().get(dom) or {}
        print("l0=%s l1=%s" % (lane_value(ent, "l0", now), lane_value(ent, "l1", now)))
    elif cmd == "set" and len(sys.argv) >= 5:
        if DISABLED:
            return
        lane, value = sys.argv[3], sys.argv[4]
        if value in NO_STORE:
            return
        with open(LOCK, "a") as lf:
            fcntl.flock(lf, fcntl.LOCK_EX)
            data = load()
            ent = data.get(dom) or {}
            ent[lane] = {"v": value, "ts": now}
            data[dom] = ent
            save(data)
            fcntl.flock(lf, fcntl.LOCK_UN)

def domain_of(s):
    if "://" in s:
        return (urlparse(s).hostname or s).lower()
    return s.lower()

if __name__ == "__main__":
    try:
        main()
    except Exception:
        # a broken cache must never break a browser request
        if len(sys.argv) >= 2 and sys.argv[1] == "get":
            print("l0=- l1=-")
