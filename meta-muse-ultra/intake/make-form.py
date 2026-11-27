#!/usr/bin/env python3
"""Create a credential intake form for the user to fill in away from chat.

Input is a spec table written by the agent (no secrets in it):

    site | username | entry | purpose

Output is the user-facing form with an empty password column inserted:

    site | username | password | entry | purpose

The user fills ONLY the password column and sends the file back; the
companion tool (apply-intake.py) stores the values and disposes of the
form. The form file is created mode 0600.

Usage:
    make-form.py --spec spec.tsv [--out PATH] [--format tsv|csv|xlsx] [--force]

Default out: $MUSE_ULTRA_STATE_DIR/intake/inbox.tsv
             (~/.local/share/muse-ultra-browser/intake/inbox.tsv)
Formats are tried in the order tsv -> csv -> xlsx when a user cannot
open one; xlsx needs openpyxl.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import intake_common as ic


def main():
    ap = argparse.ArgumentParser(description="Create an intake form (password column empty).")
    ap.add_argument("--spec", required=True, help="spec table: site/username/entry/purpose")
    ap.add_argument("--out", help="form path to create")
    ap.add_argument("--format", choices=["tsv", "csv", "xlsx"], help="default: from --out suffix, else tsv")
    ap.add_argument("--force", action="store_true", help="overwrite an existing form")
    args = ap.parse_args()

    spec_fmt = ic.detect_format(args.spec)
    try:
        header, rows = ic.read_table(args.spec, spec_fmt)
    except (OSError, ValueError) as e:
        return ic.fail(f"cannot read spec: {e}")
    spec = ic.as_dicts(header, rows, ic.SPEC_COLUMNS)
    if not spec:
        return ic.fail("spec has no rows")

    for row in spec:
        for col in ic.SPEC_COLUMNS:
            if "\t" in row[col] or "\n" in row[col]:
                return ic.fail(f"spec field {col!r} contains a tab/newline; refusing")
        if not ic.valid_entry_name(row["entry"]):
            return ic.fail(f"bad vault entry name in spec: {row['entry']!r}")

    out = args.out
    if not out:
        out = os.path.join(ic.state_dir(), "intake", "inbox.tsv")
    fmt = ic.detect_format(out, args.format)
    if os.path.exists(out) and not args.force:
        return ic.fail(f"form already exists: {out} (use --force to replace)")

    form_rows = [
        [r["site"], r["username"], "", r["entry"], r["purpose"]] for r in spec
    ]
    os.makedirs(os.path.dirname(os.path.abspath(out)), mode=0o700, exist_ok=True)
    try:
        ic.write_table(out, fmt, ic.FORM_COLUMNS, form_rows)
    except ValueError as e:
        return ic.fail(str(e))
    print(f"form created: {out} rows={len(form_rows)} format={fmt}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
