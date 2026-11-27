#!/usr/bin/env bash
# meta-muse-ultra: Muse Ultra Browser (muse-ultra-browser) wrapper — redesigned 2026-11-24.
# Usage:
#   run.sh open <url>    — navigate + snapshot (structure, trimmed)
#   run.sh read <url>    — navigate + body text (full_page; viewport fallback x1)
#   run.sh open|read --lean <url> — lean mode: block Image/Font/Media requests
#                         via CDP Fetch (opt-in, default OFF; UB_LEAN=1 also works).
#                         Read-only text/structure tasks only — never for login,
#                         captcha or interactive work (pages can break).
#   run.sh '<JS>'        — arbitrary JS
#   run.sh -f script.js  — JS file
#   run.sh keep          — disable idle auto-stop (daemon stays up)
#   run.sh resume        — re-enable idle auto-stop
#   run.sh stop          — stop daemon now (shared relay stays up;
#                          stop-relay.sh stops it, explicitly only)
#   run.sh status        — daemon status
#   run.sh warm          — pre-start the daemon (skip cold start on next call)
#   run.sh batch <file>  — run several steps from a file in this one process
#                          (see batch.sh; one exec, daemon started once)
#   run.sh doctor [--smoke] — environment checks (see doctor.sh; --smoke boots
#                          a throwaway daemon on temp dirs for an eval round-trip)
# open/read/js print a final structured line:
#   %%CHAIN%% lane=L1 mode=<m> status=ok|fail code=<F-*|-> elapsed_s=<n> chars=<n> via=<full|viewport|->
# The launcher auto-starts its daemon on the first real call; do NOT pre-wait
# for the socket (the old ensure_daemon loop burned ~10s waiting for a socket
# that `muse-ultra-browser status` never creates — measured: direct cold 6.4s vs 19.9s).
# HARNESS (2026-11-26): the client is now cdp-client.mjs + cdp-daemon.mjs, a
# raw-CDP daemon in this directory — the ego-generation harness delivered the
# first Fetch.requestPaused event ~15s after navigation (measured on both the
# stock launcher and the ego-linux fork); raw CDP delivers it in ~80ms.
# See ~/workspace/ultra-harness-2026-11-26.md. Rollback: backup-harness-2026-11-26/.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/config.env" ] && set -a && . "$HERE/config.env" && set +a
export PATH="$HOME/.local/bin:$PATH"
# Environment resolution (Chromium, proxy, CA/NSS, dirs) lives in
# ub-config.sh — no machine-specific paths are hardcoded here.
. "$HERE/ub-config.sh"
# CHROME_PATH is what the daemon spawns as "Chrome". Default: this tree's
# chrome-wrapper.sh, which resolves the real binary/proxy/NSS from config.
# An explicit CHROME_PATH in config.env wins (wrapper or raw binary).
export CHROME_PATH="${CHROME_PATH:-$HERE/chrome-wrapper.sh}"
if [ ! -x "$CHROME_PATH" ]; then
  echo "run.sh: CHROME_PATH is not executable: $CHROME_PATH" >&2
  echo "run.sh: set CHROME_PATH in config.env (default: this tree's chrome-wrapper.sh)" >&2
  exit 1
fi
export MUSE_ULTRA_HEADLESS="${MUSE_ULTRA_HEADLESS:-1}"
# Chromium version for the UA / client-hints override in generated scripts,
# derived from the resolved binary so the fingerprint matches the install
# (falls back to the last verified version when resolution is impossible).
UB_CHROME_BIN=$(ub_resolve_chrome 2>/dev/null || true)
UB_CHROME_FULL=$(ub_chrome_full_version "$UB_CHROME_BIN" 2>/dev/null || true)
UB_CHROME_MAJOR="${UB_CHROME_FULL%%.*}"
[ -n "$UB_CHROME_MAJOR" ] || UB_CHROME_MAJOR=159
[ -n "$UB_CHROME_FULL" ] || UB_CHROME_FULL=159.0.8154.6
MUSE_ULTRA_TIMEOUT=60
STATE="$HERE/.chain-state"
mkdir -p "$STATE"

arm_idle() {
  date +%s > "$STATE/last-used"
  if [ -f "$STATE/watchdog.pid" ]; then
    kill "$(cat "$STATE/watchdog.pid" 2>/dev/null)" 2>/dev/null || true
  fi
  IDLE_STOP_SEC="${IDLE_STOP_SEC:-600}" nohup "$HERE/idle-stop.sh" >/dev/null 2>&1 &
  echo $! > "$STATE/watchdog.pid"
  disown 2>/dev/null || true
}

case "${1:-}" in
  keep)  touch "$STATE/keep"; echo "idle auto-stop OFF (daemon will stay up)"; exit 0 ;;
  resume) rm -f "$STATE/keep"; arm_idle; echo "idle auto-stop ON (${IDLE_STOP_SEC:-600}s)"; exit 0 ;;
  stop)  # Daemon only. The socat relay (:$UB_RELAY_PORT) is shared with other
         # instances/tools — stopping it here took their egress down too
         # (found 2026-11-26, doctor clean-install test). The relay stops
         # only via an explicit stop-relay.sh run.
         node "$HERE/cdp-client.mjs" --stop 2>/dev/null || true
         rm -f "$STATE/watchdog.pid"; exit 0 ;;
  status) exec node "$HERE/cdp-client.mjs" --status ;;
  warm)
    # Pre-start the daemon so the next real call skips the cold start.
    # Self-contained retry: the first client call can hit ECONNREFUSED on the
    # daemon socket while the daemon is still coming up (error text is on
    # stderr, not stdout — measured 2026-11-26).
    arm_idle
    WARMJS=$(mktemp /tmp/meta-muse-ultra-warm-XXXXXX.js)
    WARMERR=$(mktemp /tmp/meta-muse-ultra-warmerr-XXXXXX.txt)
    printf 'const t = await taskSpace("ub-warm");\nconst p = await t.newPage();\nawait t.finish({keep: []});\nconsole.log("ub-warm");\n' > "$WARMJS"
    WRC=0
    timeout 30 node "$HERE/cdp-client.mjs" < "$WARMJS" 2> "$WARMERR" || WRC=$?
    if [ $WRC -ne 0 ] && grep -qiE 'daemon\.sock|ECONNREFUSED' "$WARMERR" 2>/dev/null; then
      sleep 1; WRC=0
      timeout 30 node "$HERE/cdp-client.mjs" < "$WARMJS" 2> "$WARMERR" || WRC=$?
    fi
    [ -s "$WARMERR" ] && cat "$WARMERR" >&2
    rm -f "$WARMJS" "$WARMERR"
    if [ $WRC -eq 0 ]; then echo "daemon warm"; else echo "warm failed rc=$WRC" >&2; exit 1; fi
    exit 0 ;;
  doctor) shift; exec "$HERE/doctor.sh" "$@" ;;
  batch) shift; exec "$HERE/batch.sh" "$@" ;;
esac

START=$(date +%s.%N)
elapsed() { awk -v s="$START" -v e="$(date +%s.%N)" 'BEGIN{printf "%.1f", e-s}'; }
result_line() { # mode status code chars via
  echo "%%CHAIN%% lane=L1 mode=$1 status=$2 code=$3 elapsed_s=$(elapsed) chars=$4 via=$5"
}
detect_code() { # file chars -> prints F-IP|F-BOT|- based on block markers
  # Corroboration (2026-11-27 audit fix, MUSE-001): a keyword alone does not
  # convict a long document — technical articles about blocking legitimately
  # contain these phrases (L0 measured false positive: 4,199-char HTTP-200
  # error guide -> F-IP). Real interstitials are short (measured Musinsa
  # challenge: 1,709 chars), so keyword verdicts require chars < 2500.
  # Same rule and phrase list as fetch.sh.
  if [ "${2:-0}" -ge 2500 ]; then echo -; return; fi
  if grep -qiE 'attention required|sorry, you have been blocked|access denied|접속이 일시적으로 제한|접속이 제한되었습니다|비정상적인 접근이 감지' "$1"; then echo F-IP;
  elif grep -qiE 'verify you are human|are you a robot|unusual traffic from your computer|just a moment|performing security verification|checking if the site connection is secure|verifying you are human|사람인지 확인하는 중|보안 확인 수행 중' "$1"; then echo F-BOT;
  else echo -; fi
}

run_client() { # script-file -> runs the muse-ultra-browser client once, retrying
  # exactly once when the daemon socket race hits (ECONNREFUSED while the daemon
  # is still starting). The client prints that error on STDERR — the pre-2026-11-26
  # retry grepped stdout only and never fired (measured: cold call F-NET in 5.6s).
  # Client stderr is captured to a temp file and replayed to our stderr.
  local infile="$1" errf rc=0
  errf=$(mktemp /tmp/meta-muse-ultra-err-XXXXXX.txt)
  timeout $MUSE_ULTRA_TIMEOUT node "$HERE/cdp-client.mjs" < "$infile" 2> "$errf" || rc=$?
  if [ $rc -ne 0 ] && grep -qiE 'daemon\.sock|ECONNREFUSED' "$errf" 2>/dev/null; then
    sleep 1
    rc=0
    timeout $MUSE_ULTRA_TIMEOUT node "$HERE/cdp-client.mjs" < "$infile" 2> "$errf" || rc=$?
  fi
  [ -s "$errf" ] && cat "$errf" >&2
  rm -f "$errf"
  return $rc
}

if [ "${1:-}" = "open" ] || [ "${1:-}" = "read" ]; then
  MODE=$1; shift
  LEAN=0; FP=0
  while [ "${1:-}" = "--lean" ] || [ "${1:-}" = "--fp" ]; do
    [ "$1" = "--lean" ] && LEAN=1
    [ "$1" = "--fp" ] && { FP=1; LEAN=1; }
    shift
  done
  [ "${UB_LEAN:-}" = "1" ] && LEAN=1
  [ "${UB_FP:-}" = "1" ] && { FP=1; LEAN=1; }
  URL=${1:?usage: run.sh open|read [--lean] [--fp] <url>}
  [ "$LEAN" = "1" ] && echo "run.sh: lean mode (Image/Font/Media requests blocked via CDP Fetch)" >&2
  arm_idle
  URLJSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$URL")
  BASEJSON=$(python3 -c 'import json,sys; from urllib.parse import urlparse; h=(urlparse(sys.argv[1]).hostname or "").lower(); p=h.split("."); sl={"co","or","go","ac","ne","pe","re","hs","ms","es","sc","kg"}; n=3 if len(p)>=3 and p[-1]=="kr" and p[-2] in sl else 2; print(json.dumps(".".join(p[-n:]) if len(p)>=n else h))' "$URL")
  HOSTSJSON=$(python3 -c 'import json,sys; from urllib.parse import urlparse; h=(urlparse(sys.argv[1]).hostname or "").lower(); bare=h[4:] if h.startswith("www.") else h; print(json.dumps(sorted({h, bare, "www."+bare})))' "$URL")
  [ "$FP" = "1" ] && echo "run.sh: first-party strict mode (only exact hosts $HOSTSJSON continue; subdomains and all third-party hosts blocked via CDP Fetch)" >&2
  # Navigation block injected into the generated script. Normal mode: the
  # existing p.goto line, unchanged. Lean/FP mode: Fetch.enable (bare
  # pattern) + a daemon-side armed Fetch policy + fire-and-forget
  # Page.navigate + a readyState settle poll. History: the pre-harness-swap
  # pump answered paused requests from the script via p.events(), which
  # only worked because the old harness delivered events ~15s late; over
  # raw CDP that pattern deadlocks (see cdp-daemon.mjs armFetch note).
  if [ "$LEAN" = "1" ]; then
    NAVBLOCK=$(cat <<'LEANEOF'
  // Bare Fetch pattern (no resourceType): Chrome 159's Fetch domain rejects
  // several resourceType values in the filter list (TextTrack first) with
  // "Unknown resource type in fetch filter" — a typed list either throws
  // (17 types) or silently narrows coverage. The bare pattern pauses every
  // request the Fetch domain can pause, incl. CORS preflights (which surface
  // as XHR/OPTIONS). WebSocket handshakes are NOT paused by the Fetch domain
  // at all (measured 2026-11-26) — a Chrome-level limit, same for any driver.
  try { await p.cdp('Fetch.enable', { patterns: [{ urlPattern: '*', requestStage: 'Request' }] }); } catch (e) {}
  // Paused requests are answered daemon-side by the armed policy the instant
  // they arrive. Answering from this script via events()+cdp() deadlocks:
  // the pump's Runtime.evaluate is queued until the navigation commits, and
  // the commit waits for the Fetch answer (measured 2026-11-26).
  let leanLastPausedAt = Date.now();
  let leanPausedTotal = 0;
  p.armFetch(({ resourceType }) => {
    leanPausedTotal++; leanLastPausedAt = Date.now();
    return (resourceType === 'Image' || resourceType === 'Font' || resourceType === 'Media') ? 'fail' : 'continue';
  }, 'continue');
  // Fire-and-forget navigate; the settle poll below watches readyState/href.
  p.cdp('Page.navigate', { url: __URLJSON__ }).catch(() => {});
  {
    const pumpStart = Date.now();
    const pumpDeadline = pumpStart + 45000;
    let sawNav = false;
    while (Date.now() < pumpDeadline) {
      let st = null;
      try { st = await p.evaluate(() => ({ rs: document.readyState, href: location.href })); } catch (e) {}
      if (st && st.href && st.href !== 'about:blank') sawNav = true;
      if (sawNav && st && st.rs === 'complete' && Date.now() - leanLastPausedAt > 400 && Date.now() - pumpStart > 1000) break;
      if (!sawNav && leanPausedTotal === 0 && Date.now() - pumpStart > 8000) break; // navigation never started
      await new Promise(r => setTimeout(r, 100));
    }
  }
  p.disarmFetch();
  try { await p.cdp('Fetch.disable'); } catch (e) {}
LEANEOF
)
    NAVBLOCK=${NAVBLOCK/__URLJSON__/$URLJSON}
    if [ "$FP" = "1" ]; then
      # First-party variant: intercept every resource type the harness
      # accepts. Continue only requests whose host EXACTLY matches the
      # target host (or its www/bare variant, see HOSTSJSON) — subdomains
      # are blocked too, they carded in the 2026-11-24 leak. Fail all other
      # hosts before they leave the browser, so no connection to them is
      # ever attempted. Image/Font/Media still fail even when first-party
      # (lean behaviour).
      NAVBLOCK=$(cat <<'FPEOF'
  const FP_HOSTS = __HOSTSJSON__;
  const fpAllow = (u) => { try { const h = new URL(u).hostname.toLowerCase(); return FP_HOSTS.includes(h); } catch (e) { return true; } };
  // Bare pattern (see the lean block for why typed lists are wrong on
  // Chrome 159). Host policy unchanged: only the exact target host (or its
  // www/bare variant) continues — subdomains fail too, they carded in the
  // 2026-11-24 leak. Image/Font/Media fail even when first-party.
  try { await p.cdp('Fetch.enable', { patterns: [{ urlPattern: '*', requestStage: 'Request' }] }); } catch (e) {}
  // Daemon-side armed policy answers each paused request the instant it
  // arrives (script-side answering via events() deadlocks against the
  // pump's Runtime.evaluate — measured 2026-11-26). The closure updates
  // the settle-poll counters directly.
  let fpLastPausedAt = Date.now();
  let fpPausedTotal = 0;
  p.armFetch(({ resourceType, url }) => {
    fpPausedTotal++; fpLastPausedAt = Date.now();
    return (resourceType === 'Image' || resourceType === 'Font' || resourceType === 'Media' || !fpAllow(url)) ? 'fail' : 'continue';
  }, 'fail');
  p.cdp('Page.navigate', { url: __URLJSON__ }).catch(() => {});
  {
    const pumpStart = Date.now();
    const pumpDeadline = pumpStart + 45000;
    let sawNav = false;
    while (Date.now() < pumpDeadline) {
      let st = null;
      try { st = await p.evaluate(() => ({ rs: document.readyState, href: location.href })); } catch (e) {}
      if (st && st.href && st.href !== 'about:blank') sawNav = true;
      if (sawNav && st && st.rs === 'complete' && Date.now() - fpLastPausedAt > 400 && Date.now() - pumpStart > 1000) break;
      if (!sawNav && fpPausedTotal === 0 && Date.now() - pumpStart > 8000) break; // navigation never started
      await new Promise(r => setTimeout(r, 100));
    }
  }
  // NOTE: Fetch interception + the armed policy intentionally STAY ACTIVE
  // after the settle poll. Extraction runs next, then the page is closed by
  // taskSpace finish. Any late request the page fires in between is failed
  // by the policy and never leaves the browser — disabling Fetch here
  // leaked delayed third-party beacons out (measured 2026-11-24: taboola/
  // dable/criteo hosts carded seconds after the read finished).
FPEOF
)
      NAVBLOCK=${NAVBLOCK/__URLJSON__/$URLJSON}
      NAVBLOCK=${NAVBLOCK/__HOSTSJSON__/$HOSTSJSON}
    fi
    # Lean extraction replaces the bridge snapshot: p.snapshot hangs after a
    # Fetch-paused navigation (the bridge's navigation bookkeeping never
    # settles — measured across goto load/domcontentloaded/commit and raw
    # Page.navigate variants). Raw evaluate/CDP extraction works fine.
    if [ "$MODE" = "read" ]; then
      LOGCALL="console.log(await p.evaluate(() => { const b = document.body; if (!b) return ''; return b.innerText || b.textContent || ''; }));"
    else
      LOGCALL=$(cat <<'OUTEOF'
console.log(await p.evaluate(() => {
  const out = [];
  out.push('title: ' + document.title);
  out.push('url: ' + location.href);
  const els = document.querySelectorAll('h1,h2,h3,h4,a[href],button,input,select,textarea,[role="button"]');
  let n = 0;
  for (const el of els) {
    if (n >= 400) { out.push('... (outline truncated at 400 entries)'); break; }
    const tag = el.tagName.toLowerCase();
    const label = (el.innerText || el.value || el.getAttribute('aria-label') || el.getAttribute('placeholder') || '').trim().replace(/\s+/g, ' ').slice(0, 80);
    if (tag === 'a') { out.push('link "' + label + '" -> ' + el.getAttribute('href')); n++; }
    else if (tag === 'input' || tag === 'select' || tag === 'textarea') { out.push(tag + ' [name=' + (el.getAttribute('name') || '') + '] "' + label + '"'); n++; }
    else if (tag === 'button' || el.getAttribute('role') === 'button') { out.push('button "' + label + '"'); n++; }
    else { out.push(tag + ' "' + label + '"'); n++; }
  }
  return out.join('\n');
}));
OUTEOF
)
    fi
  else
    NAVBLOCK="  try { await p.goto($URLJSON); } catch (e) { /* navigation committed — snapshot anyway */ }"
  fi
  # Body settle poll (2026-11-27): the readyState settle above (or goto's
  # load event in normal mode) can return before an SPA hydrates —
  # measured on a Musinsa campaign page: innerText 1 char at load,
  # ~2,900 chars 2s later, which surfaced as F-EMPTY. Before extraction,
  # poll the body text length: stop when it reaches 1500 chars or stops
  # growing (3 consecutive equal polls, with a 750ms minimum dwell so a
  # not-yet-started hydration is not mistaken for stable), capped at
  # UB_SETTLE_MS (default 4000). UB_SETTLE=0 disables. Pages that are
  # already complete exit on the stable polls, so fast pages do not pay
  # the cap.
  SETTLE_MS=4000
  [ "${UB_SETTLE:-}" = "0" ] && SETTLE_MS=0
  [ -n "${UB_SETTLE_MS:-}" ] && SETTLE_MS=$UB_SETTLE_MS
  SETTLEBLOCK=$(cat <<'SETLEOF'
  {
    const settleMaxMs = __SETTLE_MS__;
    if (settleMaxMs > 0) {
      const settleStart = Date.now();
      let settleLastLen = -1, settleStable = 0;
      while (Date.now() - settleStart < settleMaxMs) {
        let settleLen = -1;
        try { settleLen = await p.evaluate(() => (document.body ? (document.body.innerText || '').length : 0)); } catch (e) {}
        if (settleLen >= 1500) break;
        if (settleLen >= 0 && settleLen === settleLastLen) {
          settleStable++;
          if (settleStable >= 3 && Date.now() - settleStart >= 750) break;
        } else { settleStable = 0; if (settleLen >= 0) settleLastLen = settleLen; }
        await new Promise(r => setTimeout(r, 250));
      }
    }
  }
SETLEOF
)
  SETTLEBLOCK=${SETTLEBLOCK/__SETTLE_MS__/$SETTLE_MS}
  TMPJS=$(mktemp /tmp/meta-muse-ultra-XXXXXX.js)
  RAW=$(mktemp /tmp/meta-muse-ultra-raw-XXXXXX.txt)
  OUT=$(mktemp /tmp/meta-muse-ultra-out-XXXXXX.txt)
  trap 'rm -f "$TMPJS" "$RAW" "$OUT"' EXIT

  run_attempt() { # snapcall trimmode -> fills $OUT, returns museUltra rc
    local snapcall="$1" trim="$2"
    local logline="console.log($snapcall);"
    [ "$LEAN" = "1" ] && logline="$LOGCALL"
    cat > "$TMPJS" <<EOF
let t;
try {
  t = await taskSpace("ub" + Date.now());
  const p = await t.newPage();
  try { await p.cdp('Emulation.setUserAgentOverride', {
    userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${UB_CHROME_MAJOR}.0.0.0 Safari/537.36',
    acceptLanguage: 'ko-KR,ko,en-US,en',
    platform: 'Linux',
    userAgentMetadata: {
      brands: [{brand: 'Google Chrome', version: '${UB_CHROME_MAJOR}'}, {brand: 'Chromium', version: '${UB_CHROME_MAJOR}'}, {brand: 'Not A(Brand', version: '8'}],
      fullVersionList: [{brand: 'Google Chrome', version: '${UB_CHROME_FULL}'}, {brand: 'Chromium', version: '${UB_CHROME_FULL}'}, {brand: 'Not A(Brand', version: '8.0.0.0'}],
      fullVersion: '${UB_CHROME_FULL}',
      platform: 'Linux', platformVersion: '', architecture: 'x86', model: '', mobile: false, bitness: '64', wow64: false
    }
  }); } catch (e) { /* wrapper flags + profile prefs still guarantee defaults */ }
$NAVBLOCK
$SETTLEBLOCK
  try { const __auth = await p.evaluate(() => { const pw = !!document.querySelector('input[type="password"]'); if (!pw) return ''; const lp = /(log[-_]?in|sign[-_]?in)/i.test(location.pathname); const bl = document.body ? (document.body.innerText || '').length : 0; return (lp || bl < 2000) ? 'UBAUTHSENTINEL' : ''; }); if (__auth) console.log(__auth); } catch (e) {}
  $logline
} finally {
  if (t) { try { await t.finish({keep: []}); } catch (e) {} }
}
EOF
    local rc=0
    run_client "$TMPJS" > "$RAW" || rc=$?
    if [ $rc -eq 0 ]; then
      if [ "$LEAN" = "1" ]; then cp "$RAW" "$OUT";
      else python3 "$HERE/snaptrim.py" "$trim" < "$RAW" > "$OUT" || cp "$RAW" "$OUT"; fi
    fi
    return $rc
  }

  VIA=-
  if [ "$MODE" = "read" ]; then
    RC=0; run_attempt 'await p.snapshot({scope: "full_page"})' text || RC=$?
    VIA=full
    [ "$LEAN" = "1" ] && VIA=lean
    CHARS=0; [ $RC -eq 0 ] && CHARS=$(wc -m < "$OUT")
    if [ "$LEAN" != "1" ] && { [ $RC -ne 0 ] || [ "$CHARS" -lt 100 ]; }; then
      # same-lane different attempt: viewport snapshot (giant pages time out on full_page)
      RC2=0; run_attempt 'await p.snapshot()' text || RC2=$?
      CHARS2=0; [ $RC2 -eq 0 ] && CHARS2=$(wc -m < "$OUT")
      if [ $RC2 -eq 0 ] && [ "$CHARS2" -ge "$CHARS" ]; then RC=$RC2; CHARS=$CHARS2; VIA=viewport; fi
    fi
  else
    RC=0; run_attempt 'await p.snapshot()' trim || RC=$?
    [ "$LEAN" = "1" ] && VIA=lean
    CHARS=0; [ $RC -eq 0 ] && CHARS=$(wc -m < "$OUT")
  fi

  # Agent-first output contract: success -> body + result line, exit 0.
  # Failure -> result line ONLY (no body: block pages/empty shells are wasted
  # tokens), exit 1. UB_DEBUG=1 sends the failed body to stderr for diagnosis.
  if [ $RC -ne 0 ]; then
    if [ $RC -eq 124 ]; then CODE=F-TIMEOUT; else CODE=F-NET; fi
    head -30 "$RAW" >&2
    result_line "$MODE" fail "$CODE" 0 "$VIA"
    exit 1
  fi
  # Login wall (2026-11-27 audit fix, MUSE-002): the generated script probes
  # the live DOM for a password field (dynamic forms included) and prints a
  # sentinel when the page is a login wall — password field AND (login-ish
  # path OR short body). A public page embedding a login form in a long
  # article does not trip it. The sentinel line is stripped from the body.
  # (the sentinel is checked in $RAW too: snaptrim drops unrecognized lines
  # from the non-lean snapshot stream, measured 2026-11-27)
  if grep -qx 'UBAUTHSENTINEL' "$OUT" 2>/dev/null || grep -qx 'UBAUTHSENTINEL' "$RAW" 2>/dev/null; then
    sed -i '/^UBAUTHSENTINEL$/d' "$OUT"
    CHARS=$(wc -m < "$OUT")
    [ "${UB_DEBUG:-}" = "1" ] && cat "$OUT" >&2
    result_line "$MODE" fail F-AUTH "$CHARS" "$VIA"; exit 1
  fi
  CODE=$(detect_code "$OUT" "$CHARS")
  if [ "$CODE" != "-" ]; then
    [ "${UB_DEBUG:-}" = "1" ] && cat "$OUT" >&2
    result_line "$MODE" fail "$CODE" "$CHARS" "$VIA"; exit 1
  fi
  if [ "$MODE" = "read" ] && [ "$CHARS" -lt 100 ]; then
    [ "${UB_DEBUG:-}" = "1" ] && cat "$OUT" >&2
    result_line "$MODE" fail F-EMPTY "$CHARS" "$VIA"; exit 1
  fi
  cat "$OUT"
  printf '\n'  # keep the result line at a line start for parsers
  result_line "$MODE" ok - "$CHARS" "$VIA"
  exit 0
fi

arm_idle
if [ "${1:-}" = "-f" ]; then
  RC=0; run_client "$2" || RC=$?
  result_line js "$([ $RC -eq 0 ] && echo ok || echo fail)" "$([ $RC -eq 124 ] && echo F-TIMEOUT || echo -)" 0 -
  [ $RC -eq 0 ] && exit 0 || exit 1
fi
if [ -n "${1:-}" ]; then
  # file redirect input (piped stdin makes the muse-ultra-browser client hang)
  TMPJS=$(mktemp /tmp/meta-muse-ultra-XXXXXX.js)
  printf '%s\n' "$1" > "$TMPJS"
  RC=0; run_client "$TMPJS" || RC=$?
  rm -f "$TMPJS"
  result_line js "$([ $RC -eq 0 ] && echo ok || echo fail)" "$([ $RC -eq 124 ] && echo F-TIMEOUT || echo -)" 0 -
  [ $RC -eq 0 ] && exit 0 || exit 1
fi
exec timeout $MUSE_ULTRA_TIMEOUT node "$HERE/cdp-client.mjs"
