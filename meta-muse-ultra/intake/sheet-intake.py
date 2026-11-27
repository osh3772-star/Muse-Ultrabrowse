#!/usr/bin/env python3
"""Sheet-based credential intake (path A), guarded by connector status.

The Google Sheets connector CLI (`hatch_gws_cli sheets ...`) is the only
sheet channel. Every subcommand here first asks the connector for its
status; unless it reports "connected", this tool changes nothing and
exits 2 with a fallback line so the caller drops to the file path:

    fallback=file reason=sheets-not-connected

When connected:
  setup  creates (or reuses) a private spreadsheet whose first tab is
         named "in", writes the header, and appends the spec rows with
         site/username/entry/purpose pre-filled and password blank.
  apply  reads the tab, stores each filled password in agent-vault over
         stdin, then clears exactly those password cells and reports
         `ok site=<site> cleared=yes` per row.

Sheet layout (tab "in", columns A..E):
    site | username | password | entry | purpose

Values never appear in this tool's output or in any argv: the connector
only ever sees the sheet itself, and vault.py is fed over stdin.
"""

import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import intake_common as ic

TAB = "in"
READ_RANGE = "in!A1:E200"
DEFAULT_TITLE = "울트라 자격증명 인입"


def gws_cli():
    env = os.environ.get("UB_GWS_CLI")
    if env and os.path.isfile(env):
        return env
    for cand in ("/opt/hatch/bin/hatch_gws_cli",):
        if os.path.isfile(cand):
            return cand
    import shutil

    return shutil.which("hatch_gws_cli") or shutil.which("gws")


def run_gws(args, timeout=60):
    cli = gws_cli()
    if not cli:
        return None
    try:
        proc = subprocess.run(
            [cli, "sheets"] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    try:
        return json.loads(proc.stdout.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return None


def unwrap(obj):
    """Connector output may wrap the API body under result/data keys."""
    if isinstance(obj, dict):
        for key in ("result", "data", "spreadsheet"):
            if isinstance(obj.get(key), dict):
                return obj[key]
    return obj if isinstance(obj, dict) else {}


def sheets_connected():
    out = run_gws(["status"])
    if not isinstance(out, dict):
        return False
    status = out.get("status") or unwrap(out).get("status")
    return status == "connected"


def guard():
    """Return True when sheet work may proceed; else print fallback."""
    if not gws_cli():
        print("fallback=file reason=no-sheet-cli")
        return False
    if not sheets_connected():
        print("fallback=file reason=sheets-not-connected")
        return False
    return True


def cmd_status(_args):
    if not gws_cli():
        print("sheets=unavailable reason=no-sheet-cli")
        return 2
    print("sheets=connected" if sheets_connected() else "sheets=not-connected")
    return 0


def cmd_setup(args):
    if not guard():
        return 2
    cfg = ic.load_intake_config()
    spec_rows = []
    if args.spec:
        fmt = ic.detect_format(args.spec)
        header, rows = ic.read_table(args.spec, fmt)
        spec_rows = ic.as_dicts(header, rows, ic.SPEC_COLUMNS)

    adopt = None
    if args.sheet_id:
        adopt = args.sheet_id
        if "spreadsheets/d/" in adopt:
            adopt = adopt.split("spreadsheets/d/")[1].split("/")[0]
    if adopt:
        sheet_id = adopt
        sheet_url = f"https://docs.google.com/spreadsheets/d/{sheet_id}"
        cfg.update({"path": "A", "sheet_id": sheet_id, "sheet_url": sheet_url, "tab": TAB})
        ic.save_intake_config(cfg)
        out = run_gws(["+read", "--spreadsheet", sheet_id, "--range", f"{TAB}!A1:E1"])
        body = unwrap(out or {})
        if not body.get("values"):
            run_gws(["+append", "--spreadsheet", sheet_id,
                     "--json-values", json.dumps([ic.FORM_COLUMNS])])
        print(f"sheet adopted id={sheet_id}")
        print(f"sheet_url={sheet_url}")
    elif cfg.get("sheet_id"):
        sheet_id, sheet_url = cfg["sheet_id"], cfg.get("sheet_url", "")
        print(f"sheet reused id={sheet_id}")
    else:
        body = {
            "properties": {"title": args.title or DEFAULT_TITLE},
            "sheets": [{"properties": {"title": TAB}}],
        }
        out = run_gws(["spreadsheets", "create", "--json", json.dumps(body)])
        created = unwrap(out or {})
        sheet_id = created.get("spreadsheetId")
        sheet_url = created.get("spreadsheetUrl", "")
        if not sheet_id:
            print("fallback=file reason=sheet-create-failed")
            return 2
        header = [ic.FORM_COLUMNS]
        out = run_gws(
            ["+append", "--spreadsheet", sheet_id, "--json-values", json.dumps(header)]
        )
        if out is None:
            print("fallback=file reason=sheet-write-failed")
            return 2
        cfg.update(
            {"path": "A", "sheet_id": sheet_id, "sheet_url": sheet_url, "tab": TAB}
        )
        ic.save_intake_config(cfg)
        print(f"sheet created id={sheet_id}")
        if sheet_url:
            print(f"sheet_url={sheet_url}")

    if spec_rows:
        values = [
            [r["site"], r["username"], "", r["entry"], r["purpose"]] for r in spec_rows
        ]
        out = run_gws(
            ["+append", "--spreadsheet", sheet_id, "--json-values", json.dumps(values)]
        )
        if out is None:
            print("fail reason=sheet-append-failed", file=sys.stderr)
            return 1
        print(f"rows added={len(values)}")
    print("intake_path=A")
    return 0


def cmd_apply(args):
    if not guard():
        return 2
    cfg = ic.load_intake_config()
    sheet_id = cfg.get("sheet_id")
    if not sheet_id:
        print("fallback=file reason=no-sheet-configured")
        return 2
    vault_py = ic.resolve_vault_py(args.vault_py)
    if not vault_py:
        print("fail reason=vault-not-found", file=sys.stderr)
        return 2

    out = run_gws(["+read", "--spreadsheet", sheet_id, "--range", READ_RANGE])
    body = unwrap(out or {})
    values = body.get("values") or []
    if not values:
        print("intake stored=0 pending=0 failed=0 cleared=na")
        return 0
    header = [c.strip() for c in values[0]]
    dicts = ic.as_dicts(header, values[1:], ic.FORM_COLUMNS)

    stored = pending = failed = 0
    clear_ranges = []
    for i, row in enumerate(dicts):
        value = row["password"].strip("\r\n")
        if not value:
            pending += 1
            continue
        sheet_row = i + 2  # header is row 1
        if not ic.valid_entry_name(row["entry"]):
            failed += 1
            print(f"fail site={row['site']} cleared=no reason=bad-entry")
            continue
        if ic.store_value(vault_py, row["entry"], row["purpose"], value, force=args.force):
            stored += 1
            clear_ranges.append(f"{TAB}!C{sheet_row}")
            print(f"ok site={row['site']} cleared=yes")
        else:
            failed += 1
            print(f"fail site={row['site']} cleared=no reason=store-failed")

    if clear_ranges:
        params = json.dumps({"spreadsheetId": sheet_id})
        body = json.dumps({"ranges": clear_ranges})
        out = run_gws(
            ["spreadsheets", "values", "batchClear", "--params", params, "--json", body]
        )
        if out is None:
            print("warn reason=password-cells-not-cleared", file=sys.stderr)
            return 1
    if failed:
        print(f"intake stored={stored} pending={pending} failed={failed} cleared=partial")
        return 1
    print(f"intake stored={stored} pending={pending} failed=0 cleared=yes")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Guarded Google Sheets intake (path A).")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    s = sub.add_parser("setup")
    s.add_argument("--spec", help="spec table with rows to pre-fill")
    s.add_argument("--title", help="spreadsheet title")
    s.add_argument("--sheet-id", help="adopt an existing spreadsheet (id or URL) instead of creating one")
    a = sub.add_parser("apply")
    a.add_argument("--vault-py")
    a.add_argument("--force", action="store_true")
    args = ap.parse_args()
    if args.cmd == "status":
        return cmd_status(args)
    if args.cmd == "setup":
        return cmd_setup(args)
    return cmd_apply(args)


if __name__ == "__main__":
    sys.exit(main())
