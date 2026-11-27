"""Shared helpers for the credential intake tools (make-form / apply-intake).

The form is a small table the user fills in away from chat:

    site | username | password | entry | purpose

- site / username / entry / purpose are pre-filled by the agent.
- password starts empty; the user fills only that column.
- Values are secrets: nothing in this package prints a password, writes
  one to a log, or passes one as a command-line argument. Passwords move
  from the form file into `vault.py store` over stdin only.

Formats: tsv (default), csv, xlsx (xlsx needs openpyxl). Delivery order
when a user cannot open a format is tsv -> csv -> xlsx, one attempt each.
"""

import os
import sys

FORM_COLUMNS = ["site", "username", "password", "entry", "purpose"]
SPEC_COLUMNS = ["site", "username", "entry", "purpose"]


def shred_file(path):
    """Overwrite a file with random bytes, fsync, then unlink.

    Same disposal contract as agent-vault's own shredder. Missing files
    are not an error (a copy may already be gone).
    """
    try:
        size = os.path.getsize(path)
    except OSError:
        return False
    try:
        with open(path, "r+b", buffering=0) as f:
            remaining = size
            while remaining > 0:
                chunk = os.urandom(min(remaining, 65536))
                f.write(chunk)
                remaining -= len(chunk)
            f.flush()
            os.fsync(f.fileno())
    except OSError:
        pass
    try:
        os.unlink(path)
    except OSError:
        return False
    return True


def write_private(path, data: bytes):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, data)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.chmod(path, 0o600)


def detect_format(path, explicit=None):
    if explicit:
        return explicit.lower()
    ext = os.path.splitext(path)[1].lower().lstrip(".")
    if ext in ("tsv", "csv", "xlsx"):
        return ext
    return "tsv"


def _rows_from_delimited(text, delimiter):
    import csv
    import io

    reader = csv.reader(io.StringIO(text), delimiter=delimiter)
    rows = [r for r in reader if any(cell.strip() for cell in r)]
    if not rows:
        return [], []
    header = [c.strip() for c in rows[0]]
    return header, rows[1:]


def _rows_to_delimited(header, rows, delimiter):
    import csv
    import io

    buf = io.StringIO()
    writer = csv.writer(buf, delimiter=delimiter, lineterminator="\n")
    writer.writerow(header)
    for r in rows:
        writer.writerow(r)
    return buf.getvalue()


def read_table(path, fmt):
    """Return (header, rows) where rows are lists of strings."""
    if fmt == "xlsx":
        try:
            import openpyxl
        except ImportError:
            raise ValueError("xlsx requires openpyxl; use tsv or csv instead")
        wb = openpyxl.load_workbook(path)
        ws = wb.active
        values = [[("" if c is None else str(c)) for c in row] for row in ws.iter_rows(values_only=True)]
        values = [r for r in values if any(cell.strip() for cell in r)]
        if not values:
            return [], []
        return [c.strip() for c in values[0]], values[1:]
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    return _rows_from_delimited(text, "\t" if fmt == "tsv" else ",")


def write_table(path, fmt, header, rows):
    """Write the table with owner-only permissions."""
    if fmt == "xlsx":
        try:
            import openpyxl
        except ImportError:
            raise ValueError("xlsx requires openpyxl; use tsv or csv instead")
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.append(header)
        for r in rows:
            ws.append(r)
        import io

        buf = io.BytesIO()
        wb.save(buf)
        write_private(path, buf.getvalue())
        return
    text = _rows_to_delimited(header, rows, "\t" if fmt == "tsv" else ",")
    write_private(path, text.encode("utf-8"))


def as_dicts(header, rows, wanted):
    """Map rows to dicts keyed by `wanted` columns; missing columns -> ''."""
    idx = {}
    for col in wanted:
        idx[col] = header.index(col) if col in header else -1
    out = []
    for r in rows:
        d = {}
        for col in wanted:
            i = idx[col]
            d[col] = r[i] if 0 <= i < len(r) else ""
        out.append(d)
    return out


def fail(msg):
    print(msg, file=sys.stderr)
    return 1


# ---------------------------------------------------------------- vault ---

ENTRY_RE = None  # compiled lazily to keep module import light


def valid_entry_name(name):
    import re

    global ENTRY_RE
    if ENTRY_RE is None:
        ENTRY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
    return bool(ENTRY_RE.match(name or ""))


def resolve_vault_py(explicit=None):
    """Locate agent-vault's vault.py.

    Order: explicit argument / AGENT_VAULT_PY env, the repo layout
    (agent-vault/ sits next to meta-muse-ultra/ in the repo), then the
    long-standing local install at ~/workspace/agent-vault/.
    """
    candidates = []
    if explicit:
        candidates.append(explicit)
    env = os.environ.get("AGENT_VAULT_PY")
    if env:
        candidates.append(env)
    here = os.path.dirname(os.path.abspath(__file__))
    candidates.append(os.path.join(here, "..", "..", "agent-vault", "vault.py"))
    candidates.append(os.path.expanduser("~/workspace/agent-vault/vault.py"))
    for c in candidates:
        if c and os.path.isfile(c):
            return os.path.abspath(c)
    return None


def store_value(vault_py, entry, purpose, value, force=False):
    """Store one value via vault.py, feeding it on stdin only.

    The value never appears in argv, in this process's output, or in any
    file. Returns True on success. vault.py's own stdout is discarded
    (it only ever contains the entry name, but we do not forward it).
    """
    import subprocess

    cmd = [sys.executable, vault_py, "store", entry, "--purpose", purpose]
    if force:
        cmd.append("--force")
    try:
        proc = subprocess.run(
            cmd,
            input=value.encode("utf-8"),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return proc.returncode == 0


def state_dir():
    return os.environ.get(
        "MUSE_ULTRA_STATE_DIR",
        os.path.expanduser("~/.local/share/muse-ultra-browser"),
    )


def intake_config_path():
    return os.path.join(state_dir(), "intake.json")


def load_intake_config():
    import json

    try:
        with open(intake_config_path(), "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_intake_config(cfg):
    import json

    d = state_dir()
    os.makedirs(d, mode=0o700, exist_ok=True)
    write_private(intake_config_path(), (json.dumps(cfg, indent=2) + "\n").encode("utf-8"))
