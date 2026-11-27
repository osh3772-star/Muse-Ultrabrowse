# Muse Ultra Browser — Fallback Browser Chain

Muse Ultra Browser is a local browser harness for Linux that lets an AI agent
open and read web pages through a real Chromium engine, wrapped in a
**fallback chain**: cheap methods are tried first, heavier ones only when
needed, and every step reports a machine-readable result so the caller can
decide what to do next without guessing.

## Where does this get installed?

**Not on your PC.** Muse Ultra Browser is a tool for a Muse *agent*, and it
is installed inside the Linux VM where the agent itself lives — the same
environment the agent uses for its shell, its files and its skills. There is
nothing to install on your own computer, and you never need to open a
terminal or run a command yourself.

The intended way to set it up is to hand your Muse the GitHub address and
let the agent do the whole job inside its VM: clone the repository, check
the environment (`doctor`), register the bundled skills, and run a working
test — then report the result back to you. The next section gives you a
prompt to copy-paste for exactly that.

## Let your agent install it

Copy one of the prompts below into a chat with your Muse, as-is. The agent
will follow the agent-only install procedure at the top of
[INSTALL.md](INSTALL.md) and report back when the working test passes.

English:

```text
Please install Muse Ultra Browser inside your own VM from this repository:
https://github.com/osh3772-star/Muse-Ultrabrowse

Follow the agent-only install procedure at the top of INSTALL.md, exactly:
1. Clone the repository to ~/workspace/muse-ultra-browser-build (the bundled skills expect the harness at ~/workspace/muse-ultra-browser-build/meta-muse-ultra).
2. Check the prerequisites and install what is missing (Node.js 22 or newer, Chromium via `npx playwright install chromium`, python3, curl; socat and certutil only if the doctor says my environment needs them).
3. Create config.env from config.env.example, keeping the defaults.
4. Run ./doctor.sh --smoke in meta-muse-ultra/ and fix every FAIL item.
5. Register the skills: copy every directory under the repository's skills/ into my custom skills directory (~/workspace/custom-skills/).
6. Run ./run.sh warm, then ./run.sh read https://example.com as the working test.
7. Report back to me: the doctor result, the %%CHAIN%% result line from the read test, and the paths where everything was installed.

Everything happens inside your VM — do not ask me to install anything on my PC.
```

한국어:

```text
이 저장소로 뮤즈 울트라브라우즈를 너의 VM 안에 설치해 줘:
https://github.com/osh3772-star/Muse-Ultrabrowse

INSTALL.md 맨 위의 "에이전트 전용 설치 절차"를 정확히 따라 줘:
1. 저장소를 ~/workspace/muse-ultra-browser-build 에 클론해 줘 (스킬들이 ~/workspace/muse-ultra-browser-build/meta-muse-ultra 경로를 기대해).
2. 전제 조건을 확인하고 없는 것만 설치해 줘 (Node.js 22 이상, `npx playwright install chromium`으로 Chromium, python3, curl. socat·certutil은 doctor가 필요하다고 할 때만).
3. config.env.example을 config.env로 복사해 줘 (기본값 유지).
4. meta-muse-ultra/에서 ./doctor.sh --smoke 를 실행하고 FAIL 항목을 전부 고쳐 줘.
5. 스킬을 등록해 줘: 저장소의 skills/ 아래 디렉터리 전부를 내 커스텀 스킬 위치(~/workspace/custom-skills/)로 복사해 줘.
6. ./run.sh warm 후 ./run.sh read https://example.com 으로 작동 테스트를 해 줘.
7. 결과를 보고해 줘: doctor 결과, read 테스트의 %%CHAIN%% 결과 줄, 설치된 경로.

전부 너의 VM 안에서 진행하고, 내 PC에는 아무것도 설치하지 마.
```

## Why a chain?

A single browsing method is a bad fit for every page:

- Fetching raw HTML is nearly free, but useless on JavaScript-rendered pages.
- A full browser handles almost everything, but costs seconds of startup and
  over a gigabyte of memory while it runs.
- Some sites block datacenter IPs or fingerprint headless browsers, and no
  amount of retrying on the same lane fixes that.

The chain routes each job to the cheapest lane that can do it, and moves down
exactly one lane per failure, with explicit failure codes.

## Architecture

```
Job classification (once, at entry)
├─ R: public, read-only (body text is enough)
│     L0 lightweight fetch → L1 Muse Ultra Browser → L2 cloud browser
├─ V: public, rendering / JS / interaction needed
│     L1 Muse Ultra Browser → L2 cloud browser
└─ login / payment / user-attended flows
      out of chain — handled by a session-holding browser instead
```

| Lane | What it is | Typical cost |
|---|---|---|
| L0 | HTTP fetch + HTML-to-text extraction. No browser process at all. | ~1 s, ~0 MB resident |
| L1 | Muse Ultra Browser: a daemon drives stock Chromium (Chrome for Testing) over CDP, with a normalized fingerprint (regular Chrome UA, locale, WebGL enabled, `navigator.webdriver = false`). Certificate verification stays on. | cold start ~5 s, warm ~2 s per call |
| L2 | A hosted cloud browser, used only when local lanes fail. | varies |

### Failure codes

Every lane ends its output with one structured line:

```
%%CHAIN%% lane=L1 mode=read status=fail code=F-IP elapsed_s=2.0 chars=737
```

| Code | Trigger | Next step |
|---|---|---|
| F-IP | HTTP 403/429, or a block page ("Attention Required", "you have been blocked", …) | never retry the same lane; move down |
| F-BOT | captcha / bot-check markers | move down; stop if the last lane also fails |
| F-EMPTY | extracted text below a minimum length | one in-lane retry with a different extraction strategy, then move down |
| F-TIMEOUT | lane time budget exceeded (L0: 20 s, L1: 60 s) | move down |
| F-NET | connection or proxy errors | move down |
| F-AUTH | a login wall was detected | leave the chain; use a browser that holds the session |

Rules: at most one retry per lane, and only with a different strategy; the
same failure code on two consecutive lanes stops the chain; total budget
5 minutes.

### Route cache

The chain remembers, per domain, which lanes recently succeeded or failed
(a small JSON file, entries expire after 7 days). A domain that blocked L0
yesterday skips L0 today; a domain that blocked L1 goes straight to L2.
The cache is a hint only — outcomes are still measured on every run.

### Resource behavior

Nothing runs at idle. The L1 daemon starts on demand with the first call
and **stops automatically after an idle period** (default 600 s,
configurable), together with its local proxy relay. While running, expect
roughly 0.1 GB for the daemon and ~1.1 GB RSS for the Chromium process
group. A `keep` command pins the daemon up for long interactive sessions,
and `stop` shuts everything down immediately.

## Requirements

- Linux with Node.js ≥ 22 (the L1 harness is a dependency-free Node
  daemon + client — `cdp-daemon.mjs` / `cdp-client.mjs` — speaking raw CDP)
- Chrome for Testing (or another stock Chromium build) — downloaded
  separately; `CHROME_PATH` in `config.env` points at the wrapper script
  that launches it
- `curl` and `python3` (standard library only) for the L0 lane
- Network egress. If your environment forces traffic through an HTTP
  proxy that rejects direct CONNECTs from Chromium, the wrapper starts a
  small local relay (via `socat`) and points Chromium at it; if the proxy
  TLS-intercepts, import its CA into a dedicated NSS database for the
  browser profile instead of disabling certificate verification.

## Install

Full procedure: [INSTALL.md](INSTALL.md). If you are a Muse agent installing
this into your own VM, follow the agent-only procedure at the top of
INSTALL.md instead of this outline. Outline:

1. Clone this repository — there is no separate launcher binary; the
   daemon, client and wrapper scripts live in `meta-muse-ultra/`.
2. Install a Chrome for Testing build and set `CHROME_PATH` in
   `config.env` to the wrapper script (`meta-muse-ultra/chrome-wrapper.sh`;
   or directly to the binary if your network needs no relay).
3. Copy `config.env.example` to `config.env` and adjust the profile path
   and headless setting.
4. Run the verification below.

## Usage

```bash
chain.sh read https://example.com   # read-only: L0 first, L1 on failure
chain.sh open https://example.com   # rendered snapshot via L1
run.sh read https://example.com     # L1 directly
run.sh -f script.js                 # arbitrary JS against L1
run.sh keep                         # pin the daemon up (disable idle stop)
run.sh stop                         # stop daemon + relay now
fetch.sh https://example.com        # L0 directly
```

## Verification

Use `https://example.com` as the smoke-test target — it is small, stable,
and needs no permissions from anyone.

```bash
fetch.sh https://example.com
# → page text, then: %%CHAIN%% lane=L0 ... status=ok ... http=200

run.sh read https://example.com     # first call is the cold start
run.sh read https://example.com     # second call should be warm (~2 s)
```

A blocked-site check: pick any page your egress IP cannot fetch and confirm
the chain reports `code=F-IP` on L0 and L1 and hands off to L2, instead of
returning the block page as if it were content.

## Design notes

- **Why not always use the browser?** Most agent page reads are static.
  L0 answers them in about a second with no resident memory, which matters
  on small machines.
- **Why not always fetch?** Client-rendered pages return empty shells to a
  fetcher. The F-EMPTY code detects that and escalates automatically.
- **Why is the daemon not per-request?** A cold browser start costs several
  seconds; a warm call costs about two. Keeping the daemon briefly and
  stopping it on idle gets both: fast repeats, zero idle footprint.
- **Fingerprint normalization is not a bypass.** It makes the browser look
  like a regular browser; sites that block by IP still block, and the chain
  treats that as a routing signal (F-IP), not an error to retry through.

## License

See the repository license file. The embedded harness derives from an
MIT-licensed upstream project; see the notices in the source tree.
