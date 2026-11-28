#!/usr/bin/env python3
"""Apply a filled intake form: store values in agent-vault, then dispose.

For every row whose password cell is filled:
  1. the value is piped to `vault.py store` over stdin (never argv,
     never printed, never logged),
  2. on success the password cell in the form is blanked immediately and
     the form rewritten, and the row is reported as
         ok site=<site> cleared=yes
  3. on failure the password cell is blanked the same way (2026-11-28,
     adopted from pickle-ultra-browser's intake fix: a value that could
     not be stored must not sit in a file waiting for a retry) and the
     row is reported as
         fail site=<site> cleared=yes reason=<short code>
     Site and username stay in the form, so the user only refills the
     password cell on the next round.

When every filled row succeeded, the returned form and any extra copies
named with --copy are shredded and removed. If anything failed, the
(password-free) form is kept for a refill round.

Rows with an empty password cell are left alone and counted as pending.

Usage:
    apply-intake.py FORM [--vault-py PATH] [--copy PATH ...] [--force]

Exit codes: 0 = nothing failed, 1 = a row failed, 2 = cannot proceed.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import intake_common as ic


def main():
    ap = argparse.ArgumentParser(description="Store a filled intake form into agent-vault.")
    ap.add_argument("form", help="the filled form file (tsv/csv/xlsx)")
    ap.add_argument("--vault-py", help="path to agent-vault vault.py")
    ap.add_argument("--copy", action="append", default=[], help="extra copy of the form to shred on success")
    ap.add_argument("--force", action="store_true", help="replace existing vault entries")
    args = ap.parse_args()

    if not os.path.isfile(args.form):
        print("fail reason=form-missing", file=sys.stderr)
        return 2
    vault_py = ic.resolve_vault_py(args.vault_py)
    if not vault_py:
        print("fail reason=vault-not-found", file=sys.stderr)
        return 2

    fmt = ic.detect_format(args.form)
    try:
        header, rows = ic.read_table(args.form, fmt)
    except (OSError, ValueError) as e:
        print(f"fail reason=form-unreadable ({e})", file=sys.stderr)
        return 2
    if "password" not in header or "entry" not in header:
        print("fail reason=form-columns", file=sys.stderr)
        return 2

    pw_idx = header.index("password")
    dicts = ic.as_dicts(header, rows, ic.FORM_COLUMNS)

    def blank_password(i):
        """Remove row i's password from the form on disk, whatever the
        store outcome was. Returns True when the cell is confirmed gone."""
        rows[i][pw_idx] = ""
        try:
            ic.write_table(args.form, fmt, header, rows)
            return True
        except ValueError:
            return False

    stored = pending = failed = 0
    for i, row in enumerate(dicts):
        value = row["password"].strip("\r\n")
        if not value:
            pending += 1
            continue
        if not ic.valid_entry_name(row["entry"]):
            failed += 1
            cleared = blank_password(i)
            print(f"fail site={row['site']} cleared={'yes' if cleared else 'no'} reason=bad-entry")
            continue
        if ic.store_value(vault_py, row["entry"], row["purpose"], value, force=args.force):
            stored += 1
            blank_password(i)
            print(f"ok site={row['site']} cleared=yes")
        else:
            failed += 1
            cleared = blank_password(i)
            print(f"fail site={row['site']} cleared={'yes' if cleared else 'no'} reason=store-failed")

    if failed == 0 and stored > 0:
        ic.shred_file(args.form)
        for copy in args.copy:
            ic.shred_file(copy)
        print(f"intake stored={stored} pending={pending} failed=0 cleared=yes")
        return 0
    if failed == 0:
        print(f"intake stored=0 pending={pending} failed=0 cleared=na")
        return 0
    print(f"intake stored={stored} pending={pending} failed={failed} cleared=partial")
    return 1


if __name__ == "__main__":
    sys.exit(main())
