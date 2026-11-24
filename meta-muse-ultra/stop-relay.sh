#!/usr/bin/env bash
# meta-muse-ultra 로컬 프록시 릴레이(127.0.0.1:18080) 종료
pkill -f 'socat TCP-LISTEN:18080' 2>/dev/null && echo "relay stopped" || echo "relay not running"
