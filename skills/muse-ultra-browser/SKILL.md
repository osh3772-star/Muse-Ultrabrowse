# ultrabrowse — VM 로컬 브라우저 도구 (muse-ultra-browser)

이 VM(메타 테스트베드)에서 웹페이지를 열고 읽을 때 쓰는 로컬 브라우저 하네스.
운전은 외부 API가 아니라 Muse 본인이 exec로 JS를 넘겨 판단·조작하는 방식이다.
인증서 검증은 켜져 있고(정상 신뢰), 일반 사이트에 쓸 수 있다.

## 설치 직후 브리핑 (설치한 뮤즈가 1회만)

이 스킬을 처음 설치·검증한 뮤즈는, 설치·검증이 끝난 직후 아래 항목을 사용자에게 **한 번만** 브리핑한다. 매 세션·매 호출마다 반복하지 않고, 이미 브리핑한 설치에서는 다시 하지 않는다.

1. **화면은 직접 볼 수 없다** — 울트라 브라우저는 VM 내부에서 도는 브라우저라 사용자가 직접 화면을 볼 수 없다. 사용자가 보고 싶어 하면 스크린샷을 찍어 보여줄 수 있다.
2. **체인 구조** — 일반 읽기는 L0(경량 fetch) → L1(이 브라우저) → L2(클라우드 브라우저) 순으로 내려간다. 로그인 세션이 PC에 있는 사이트(부동산뱅크·직방 등)는 이 브라우저가 아니라 H255의 agent-browser가 담당한다.
3. **세션 영속** — 작업 공간이 프로필의 기본 컨텍스트를 써서, 한 번 로그인하면 데몬이 재시작돼도(완전 재시작 포함) 로그인 상태가 유지된다. 단 작업 공간끼리 스토리지를 공유하므로 사이트별 격리는 없다.
4. **로그인 자격증명** — 자격증명이 필요한 로그인은 별도의 로컬 볼트 절차로 다룬다 (이 레포에는 포함되지 않으며, 설치 환경의 로컬 스킬을 따른다). 비밀번호를 채팅으로 주고받지 않는다.
5. **차단되면 다음 출구로** — 한 경로가 차단·실패하면 멈춰서 보고만 하지 말고, 체인의 다음 출구로 전환해 계속 진행한다.
6. **자원 사용** — 데몬은 호출이 없으면 idle 120초에 자동 정지한다. 구동 중 메모리는 데몬+Chrome 합쳐 1GB 남짓이다.

## 호출법
```bash
# 데몬 예열 (작업 전 1회 권장 — 아래 '데몬 웜 유지' 참조)
~/workspace/muse-ultra-browser-build/meta-muse-ultra/run.sh warm
# 자주 쓰는 작업 (후처리 포함, 권장)
~/workspace/muse-ultra-browser-build/meta-muse-ultra/run.sh open https://example.com   # 이동 + 스냅샷(구조 유지)
~/workspace/muse-ultra-browser-build/meta-muse-ultra/run.sh read https://example.com   # 본문 텍스트만 추출
# 임의 JS
~/workspace/muse-ultra-browser-build/meta-muse-ultra/run.sh 'const t = await taskSpace("s"); const p = await t.newPage(); await p.goto("https://example.com"); console.log(await p.snapshot()); await t.finish({keep: []});'
# 파일로: run.sh -f script.js
# 데몬 상태/종료: muse-ultra-browser status / muse-ultra-browser stop  (PATH에 ~/.local/bin 필요)
```
- 모든 호출에 하드 타임아웃 60초가 걸려 있다 (run.sh 내장).
- 실측 지연: 가벼운 페이지 건당 웜 1.4~4.4초, 콜드(데몬 정지 후 첫 호출) ~15초.
  데몬 정지 상태에서 첫 호출이 실패하던 레이스는 수정됨 — 첫 호출이 알아서
  데몬을 깨우므로 재시도하지 말고 결과를 기다릴 것.
- 원샷 실측 (2026-11-21, HN 상위 3글 원샷 스크립트): 콜드 `-f` 1회 18.1초,
  웜 3.6~4.1초. `-f` 경로에도 콜드 소켓 레이스 시 래퍼 내부 1회 자동 재시도가
  들어갔다 (이전에는 open/read만 있었고, -f 콜드 실패를 실측으로 확인함).

## 데몬 웜 유지 (2026-11-21)
- 데몬(muse-ultra-browser serve) 소스에는 **유휴 종료 타이머가 없다**. 설계상 종료
  조건은 `muse-ultra-browser stop`, Chromium 크래시(데몬 동반 종료 → 다음 호출에서
  재생성), VM 재부팅뿐이다. 따라서 웜 유지는 "한 번 띄워 두기"로 충분하고
  별도 keepalive 루프는 두지 않는다.
  - 단, 2026-11-21 측정 직후 한 차례 데몬이 로그 없이 정지 상태로 발견된
    적이 있다 (원인 미확인, warm 재실행으로 즉시 복구). 장시간 상주가
    필요하면 작업 전 status 확인 + warm을 습관으로 할 것.
- `run.sh warm`: 데몬이 없으면 띄우고 about:blank 페이지로 예열한 뒤
  `muse-ultra-browser status`로 상주를 확인해 준다. 콜드에서 실측 14.2초.
- 작업 세션 시작 시 warm을 한 번 돌려 두면 이후 호출은 전부 웜 속도다.
  VM이 재부팅되면 데몬은 사라지므로 그때 다시 warm이 필요하다.
  단, 노드 수만 개급 거대 페이지의 read(full_page 스냅샷)는 ~50초가 걸릴 수
  있어 60초 타임아웃에 근접한다 — 그런 페이지는 open(뷰포트)부터 볼 것.
  (스크롤 분할은 실측상 역효과라 미적용. 근거는 meta-muse-ultra/README.md 패스 기록.)
- 스냅샷 후처리(snaptrim): 원본 대비 trim -18~21%, text -88% 수준 (Wikipedia Seoul 실측).

## 경로
- 래퍼: `~/workspace/muse-ultra-browser-build/meta-muse-ultra/run.sh`
- 설정: `~/workspace/muse-ultra-browser-build/meta-muse-ultra/config.env` (없으면 `config.env.example` 복사)
  - API 등록 슬롯 `MUSE_ULTRA_API_PROVIDER` / `MUSE_ULTRA_API_KEY` — 현재 미등록, 등록만 가능한 상태로 둘 것
- 본체: `~/.local/bin/muse-ultra-browser` (v4.0.0), 소스 `~/workspace/muse-ultra-browser-build/src/`
- 데몬 데이터: `~/.local/share/muse-ultra-browser/`
- 프로필: `~/workspace/muse-ultra-browser-build/meta-muse-ultra/profile` (durable, config.env의 MUSE_ULTRA_PROFILE)
- 인증서 신뢰 DB: `~/workspace/muse-ultra-browser-build/meta-muse-ultra/chrome-home/.pki/nssdb`
  (egress CA를 CT,C,C로 임포트, `ensure-nssdb.sh`가 자동 유지)

## 브라우저 지문 (2026-11-20 정상화)
- UA는 정식 Chrome 159 (`HeadlessChrome` 표기 없음), 언어는 ko-KR 우선
  (navigator.languages·Accept-Language 모두), WebGL 동작 (SwiftShader),
  `navigator.webdriver` false. 전/후 실측표는 meta-muse-ultra/README.md.
- open/read 경로는 CDP `Emulation.setUserAgentOverride`까지 자동 적용돼
  Sec-Ch-Ua 브랜드가 `Google Chrome`으로 나간다. 임의 JS로 직접 페이지를
  만들 때는 같은 일관성이 필요하면 페이지 생성 직후 동일 호출을 할 것:
  `await p.cdp('Emulation.setUserAgentOverride', {userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/159.0.0.0 Safari/537.36', acceptLanguage: 'ko-KR,ko,en-US,en', platform: 'Linux'})`
  (acceptLanguage에 q값을 넣으면 languages에 q값이 새니 태그만 넣을 것.)
- 주의: 이 정상화는 지문 층의 얘기다. 출구 IP 자체를 막는 사이트(예: 나무위키 —
  curl도 403)는 이걸로 안 풀린다.

## 세션 유지법
- Space는 격리 컨텍스트다. `t.finish({keep: []})`로 닫으면 쿠키가 폐기된다.
- 세션을 이어가려면 페이지를 keep하고, 다음 호출에서 `claimTaskSpace(id)`로 재진입할 것.
  (별도 호출 간 쿠키 유지 실측 확인됨. 데몬이 죽으면 런타임 컨텍스트는 소멸.)

## 제약 (중요)
- **2026-11-20 설치·검증 완료**: Playwright로 받은 Chrome for Testing 159.0.8154.6 사용.
  단, 스톡 Chromium 단독으로는 이 VM egress를 못 나간다 — 반드시 `config.env`의
  CHROME_PATH(= `meta-muse-ultra/chrome-wrapper.sh`) 경유로 실행할 것. 래퍼는 socat 릴레이
  (127.0.0.1:18080 → hatch-egress-proxy:3128)를 붙이고, Chrome의 HOME을 `chrome-home`으로
  지정해 전용 NSS DB의 egress CA를 정상 신뢰시킨다. `--ignore-certificate-errors`는
  쓰지 않는다 — 인증서 검증이 켜진 상태가 기본이다 (badssl 차단 + 로컬 분리 테스트로
  검증됨. 자세한 근거는 meta-muse-ultra/README.md).
- `/opt/meta-chromium/chrome`은 Hatch 전용 빌드라 단독 기동 불가 — 사용 금지.
- run.sh 인자/파일 입력은 파일 리다이렉트 방식이다. muse-ultra-browser에 파이프로 JS를 넘기면
  클라이언트가 종료되지 않는 행이 있으니 직접 호출 때도 heredoc/파일 입력을 쓸 것.
- 일반 사이트 사용 가능. 단, 로그인 세션이 필요한 사이트는 이 도구의 프로필에
  세션이 없으면 못 연다 — 그런 작업은 세션이 있는 브라우저 수단으로 보낼 것.
- upstream 하네스(citrolabs/muse-ultra-browser)는 MIT 표기, muse-ultra-browser 자체 라이선스 파일은 없음.
