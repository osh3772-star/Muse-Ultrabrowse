---
name: muse-ultra-browser
description: Muse Ultra Browser (뮤즈 울트라브라우즈) — VM 로컬 브라우저 (체인 L1) 직접 호출용
---

# Muse Ultra Browser — 실행 절차

상태: 설치 완료·동작 중 (2026-11-24). 기록: `~/workspace/browser-chain-install-2026-11-24.md`,
운용 설계: `~/workspace/browser-chain-redesign-2026-11-24.md`.
일반 읽기는 이 스킬이 아니라 browser-chain의 `chain.sh read`(L0 우선)를 쓴다.

## 설치 직후 브리핑 (설치한 뮤즈가 1회만)

이 스킬을 처음 설치·검증한 뮤즈는, 설치·검증이 끝난 직후 아래 항목을 사용자에게 **한 번만** 브리핑한다. 매 세션·매 호출마다 반복하지 않고, 이미 브리핑한 설치에서는 다시 하지 않는다.

1. **화면은 직접 볼 수 없다** — 울트라 브라우저는 VM 내부에서 도는 브라우저라 사용자가 직접 화면을 볼 수 없다. 사용자가 보고 싶어 하면 스크린샷을 찍어 보여줄 수 있다.
2. **체인 구조** — 일반 읽기는 L0(경량 fetch) → L1(이 브라우저) → L2(클라우드 브라우저) 순으로 내려간다. 로그인 세션이 PC에 있는 사이트(부동산뱅크·직방 등)는 이 브라우저가 아니라 H255의 agent-browser가 담당한다.
3. **세션 영속** — 작업 공간이 프로필의 기본 컨텍스트를 써서, 한 번 로그인하면 데몬이 재시작돼도(완전 재시작 포함) 로그인 상태가 유지된다. 단 작업 공간끼리 스토리지를 공유하므로 사이트별 격리는 없다.
4. **로그인 자격증명은 agent-vault 절차로** — 로그인이 필요한 사이트는 별도 로컬 볼트(agent-vault)를 쓴다: 사용자가 파일로 값을 넣어주면 암호화해 저장하고 원본 파일은 파쇄하며, 에이전트는 값을 보지 못한다. **비밀번호를 채팅으로 보내지 말 것**도 이때 사용자에게 안내한다. 상세 절차는 agent-vault 스킬을 따른다.
5. **차단되면 다음 출구로** — 한 경로가 차단·실패하면 멈춰서 보고만 하지 말고, 체인의 다음 출구로 전환해 계속 진행한다.
6. **자원 사용** — 데몬은 호출이 없으면 idle 120초에 자동 정지한다. 구동 중 메모리는 데몬+Chrome 합쳐 1GB 남짓이다.

## 차단 회피와 대응 (전 사이트 공통, 2026-11-24 사용자 지시로 반영)

차단은 대개 출구 IP 자체가 아니라 **세션 유무와 요청 방식**에서 온다.

- 쿠키·JS 없는 fetch 실패만으로 차단 판정을 내리지 않는다 — 세션에 민감한 사이트는 이 브라우저(세션 유지, 사람 속도)로 확인한 뒤에 판정한다.
- 사람 속도를 지킨다: 연속 클릭, 새로고침 루프, 매크로식 반복, 짧은 시간 과다 요청 금지. 민감 구간(결제·본인인증·대량 요청)은 한 번에 하나씩.
- VPN·프록시로 IP를 속이는 우회는 하지 않는다.
- 실제로 차단되면 같은 방식으로 재시도를 반복하지 말고 중단해서 사용자에게 알린다 (사이트·레인·코드·현상).

## 호출

```bash
META=~/workspace/muse-ultra-browser-build/meta-muse-ultra
$META/run.sh open <url>     # 이동 + 스냅샷 (구조)
$META/run.sh read <url>     # 본문 텍스트 (full_page; 실패 시 viewport 1회 자동 폴백)
$META/run.sh read --fp <url>  # 노카드 모드 (아래)
$META/run.sh -f script.js   # 임의 JS (파일로만 — 파이프 입력은 hang)
$META/fetch.sh <url>        # L0 단독 (브라우저 없음)
```

**노카드 모드 `--fp` (2026-11-24 실측)**: exec 네트워크 승인은 호스트마다 카드가 뜨는데,
페이지 본체가 아니라 광고·추적 서브리소스 호스트가 대부분이다. `--fp`는 CDP Fetch로
전 요청을 가로채 ① 대상 호스트 정확 일치(www 유무 변형 포함)만 통과, 서브도메인 포함
전부 차단 ② 추출이 끝나 페이지가 닫힐 때까지 차단을 유지(늦게 나가는 비콘 누수 방지)
③ 이미지·폰트·미디어는 1차 호스트라도 차단한다. 실측: 연합뉴스 기사 read — 카드 9장+
나오던 조건에서 **0장**, 본문 10,506자 정상. 광고·집계가 많은 페이지(뉴스 등)를
exec로 읽을 때는 기본으로 `--fp`를 붙여라. 단, 본문이 서브도메인 JS에 의존하는
페이지는 비어 보일 수 있으니 그때만 빼고 재시도한다.

## 출력 계약

- 성공: 본문 + `%%CHAIN%% lane=L1 … status=ok …` 1줄, exit 0
- 실패: 결과 1줄만, exit 1. 코드: F-IP(차단)/F-BOT(캡차)/F-EMPTY(100자 미만)/F-TIMEOUT(60초)/F-NET
- 실패 본문이 꼭 필요하면 `UB_DEBUG=1`을 붙인다 (stderr로 나간다). 평소에는 붙이지 마라 — 토큰 낭비다.

## 운용 규칙

- 콜드 ~5초 / 웜 ~2초. 데몬은 첫 호출이 자동 기동한다. **미리 깨우지 마라** (`status`는 안 깨운다).
- idle 120초 무호출이면 데몬+릴레이 자동 정지. 연속 작업이면 시작할 때 `$META/run.sh keep`,
  끝나면 `$META/run.sh stop`.
- **세션 영속 (2026-11-24 변경)**: 작업 공간이 프로필의 기본 컨텍스트를 써서 쿠키·localStorage·
  IndexedDB가 프로필 디렉터리에 저장된다. 공간을 닫거나 데몬이 내려가도(완전 재시작 포함)
  로그인이 유지되므로, keep은 세션 유지 목적으론 불필요하다(데몬 상주 목적일 때만).
  단 공간끼리 스토리지를 공유한다(사이트별 격리 없음). 공간 id는 데몬 재시작 시 초기화되니
  `claimTaskSpace(id)` 재진입은 같은 데몬이 떠 있는 동안만 유효하다.
  옛 일회성 동작이 필요하면 데몬 기동 전 `MUSE_ULTRA_EPHEMERAL=1`을 건다(데몬을 처음 띄우는
  호출의 환경에 적용). 기록: `~/workspace/ultra-persist-change-2026-11-24.md`.
- 메모리: 데몬 ~90MB + Chrome ~1.1GB RSS (구동 중에만).

## 데몬 환경변수와 자격증명 (agent-vault 연동)

- `-f` 스크립트는 **데몬 프로세스 안에서 실행**되므로, 스크립트가 보는 환경변수는 호출 시점이 아니라 **데몬 기동 시점의 환경**이다. 이미 떠 있는 데몬에는 나중에 export한 값이 닿지 않는다.
- 자격증명이 필요한 작업(로그인 등)은 데몬을 agent-vault로 래핑해 기동한다: 기존 데몬을 정지한 뒤 `python3 ~/workspace/agent-vault/vault.py use <항목> --via env -- $META/run.sh open <url>` 로 띄우면, 데몬 내 스크립트가 `AGENT_VAULT_VALUE`로 값을 읽을 수 있다.
- 값은 어떤 출력·로그·파일에도 남기지 않는다. 상세 절차(로그인 단계, 2FA 정지·재개, 승인 후 영속 확인)는 agent-vault 스킬의 "Ultra Browser 로그인 (실증 절차)" 절을 따른다.

## 금지·주의

- 반드시 `config.env`의 CHROME_PATH(chrome-wrapper.sh) 경유로만 실행. 스톡 Chromium 직접 실행 금지.
  `--ignore-certificate-errors` 금지 (인증서 검증 ON이 기본). `/opt/meta-chromium/chrome` 사용 금지.
- H255에 세션이 있는 사이트(부동산뱅크·직방)는 이 도구가 아니라 H255 agent-browser로.
- 런처 본체(`~/.local/bin/muse-ultra-browser`)는 2026-11-24 이름 전면 변경으로 파일명·내부 표기만 Muse Ultra Browser로 바뀐 것 — 기능·동작은 변경 전과 동일하다. 임의로 다른 빌드로 교체하지 않는다.

## 경로

- 래퍼 디렉토리: `~/workspace/muse-ultra-browser-build/meta-muse-ultra/` (run.sh, fetch.sh, chain.sh, chrome-wrapper.sh,
  idle-stop.sh, stop-relay.sh, snaptrim.py, html2text.py, routecache.py, route-cache.json, config.env)
- 프로필: `meta-muse-ultra/profile` / 인증서 DB: `meta-muse-ultra/chrome-home/.pki/nssdb` (자동 유지)
- 재설계 전 백업: `meta-muse-ultra/backup-2026-11-24/`
- 영속화 변경 전 백업: `meta-muse-ultra/backup-persist-2026-11-24/` (런처 원본 + 스킬 원본)
- 지문: UA 정식 Chrome 159, ko-KR, WebGL on, webdriver=false (래퍼+CDP 오버라이드가 자동 적용)
