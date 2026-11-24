#!/usr/bin/env bash
# meta-ego ensure-nssdb — UltraBrowse 전용 NSS DB(chrome-home/.pki/nssdb)에
# egress CA가 올바른 신뢰(CT,C,C)로 들어있는지 보장한다.
# 없거나 CA 지문이 바뀌었으면 DB를 재생성한다. 정상 상태에서는 조용히 빠르게 끝난다.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="$HERE/chrome-home/.pki/nssdb"
CA_SRC="${HATCH_EGRESS_CA:-/usr/local/share/ca-certificates/hatch-egress-ca.crt}"
NICK="hatch-egress"

fp_of_file() { openssl x509 -in "$1" -noout -sha256 -fingerprint 2>/dev/null | cut -d= -f2; }
fp_of_db() {
  certutil -L -d "sql:$DB" -n "$NICK" -a 2>/dev/null \
    | openssl x509 -noout -sha256 -fingerprint 2>/dev/null | cut -d= -f2
}

SRC_FP="$(fp_of_file "$CA_SRC" || true)"
if [ -n "$SRC_FP" ] && [ "$SRC_FP" = "$(fp_of_db || true)" ]; then
  exit 0  # 이미 올바른 CA가 들어 있음
fi

# (재)생성
rm -rf "$DB"
mkdir -p "$DB"
certutil -N -d "sql:$DB" --empty-password
certutil -A -d "sql:$DB" -n "$NICK" -t 'CT,C,C' -i "$CA_SRC"
echo "ensure-nssdb: NSS DB rebuilt with CA fp=$SRC_FP" >&2
