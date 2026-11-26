#!/usr/bin/env bash
# ensure-nssdb — UltraBrowse 전용 NSS DB(chrome-home/.pki/nssdb)에 프록시
# CA가 올바른 신뢰(CT,C,C)로 들어있는지 보장한다. 없거나 CA 지문이
# 바뀌었으면 DB를 재생성한다. 정상 상태에서는 조용히 빠르게 끝난다.
# 프록시 CA가 설정돼 있지 않으면(직접 연결 환경 등) 준비할 것이 없으므로
# 건너뛴다 — CA 경로는 코드가 아니라 ub-config.sh/config.env에서 온다.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/ub-config.sh"
DB="$UB_NSSDB_DIR"
CA_SRC="$UB_PROXY_CA"
NICK="$UB_NSSDB_NICK"

if [ -z "$CA_SRC" ] || [ ! -f "$CA_SRC" ]; then
  echo "ensure-nssdb: no proxy CA configured (UB_PROXY_CA) — skipping" >&2
  exit 0
fi
if ! command -v certutil >/dev/null 2>&1; then
  echo "ensure-nssdb: certutil not found — skipping NSS DB preparation" >&2
  exit 0
fi

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
