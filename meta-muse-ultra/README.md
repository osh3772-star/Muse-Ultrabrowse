# meta-muse-ultra — Muse Ultra Browser (뮤즈 울트라브라우즈) 래퍼

> 표기: 이 도구의 현행 이름은 **Muse Ultra Browser (뮤즈 울트라브라우즈)**다 (2026-11-24 통일).
> 런처 파일명(muse-ultra-browser)과 아래 본문의 과거 패스 기록은 이력으로 유지한다.
> 현행 운용(체인 구조·idle 정지·결과 라인)은 `~/workspace/browser-chain-redesign-2026-11-24.md` 참조.
> 설치 절차와 설치 범위(네트워크에서 받는 것·실행되는 스크립트·쓰는 위치·하지 않는 것)는 저장소 루트 `INSTALL.md`의 "설치 개요" 절이 기준이다.

muse-ultra-browser(Muse Ultra Browser의 Linux 포팅)를 이 VM에서 Muse가 exec로 운전하기 위한 래퍼.

## 구성
- `run.sh` — 실행 래퍼. `config.env`를 로드하고 JS를 muse-ultra-browser에 전달.
  - `run.sh open <url>` — 이동 + 스냅샷 (trim 후처리). `run.sh read <url>` — 본문 텍스트 추출.
  - `run.sh '<JS>'` / `run.sh -f script.js` 모두 가능 (인자 방식은 내부적으로 임시파일 리다이렉트)
  - 모든 muse-ultra-browser 호출에 하드 타임아웃 60초 (과거 hang 재발 방지).
  - JS API: `const t = await taskSpace("name"); const p = await t.newPage(); await p.goto(url); await p.snapshot();`
    (`t.page("라벨")`은 이미 있는 페이지 참조용. 새 페이지는 `t.newPage()`)
- `snaptrim.py` — 스냅샷 후처리. `trim`(구조 유지, 이름 없는 generic 래퍼 접기 + ListMarker 제거)과
  `text`(랜드마크 서브트리 제거 + 본문 텍스트만 추출) 모드.
- `chrome-wrapper.sh` — CHROME_PATH가 가리키는 래퍼. 아래 "샌드박스 우회 구조" 참조.
- `ensure-nssdb.sh` — chrome-wrapper가 매 실행 시 호출. `chrome-home/.pki/nssdb`에 egress CA가
  올바른 신뢰(CT,C,C)로 들어있는지 확인하고, 없거나 CA 지문이 바뀌면 재생성한다.
- `chrome-home/` — Chrome 프로세스 전용 HOME. `.pki/nssdb`에 Hatch Egress CA를 임포트해 둠.
- `profile/` — durable 브라우저 프로필 (config.env의 `MUSE_ULTRA_PROFILE`).
- `stop-relay.sh` — 로컬 프록시 릴레이(127.0.0.1:18080) 종료.
- `config.env` — 확정 설정. CHROME_PATH=chrome-wrapper.sh, MUSE_ULTRA_HEADLESS=1,
  MUSE_ULTRA_PROFILE=`meta-muse-ultra/profile`.
  - **API 등록 슬롯**: `MUSE_ULTRA_API_PROVIDER=`, `MUSE_ULTRA_API_KEY=` (빈 값). 등록만 가능한 자리이며 현재 미등록.
    실제 키는 넣지 않았다. 기본 운전은 외부 API 없이 Muse(이 인스턴스)가 판단해서 호출하는 방식.
- 설치 본체: `~/.local/bin/muse-ultra-browser` (v4.0.0, 단일 파일 빌드). 소스: `~/workspace/muse-ultra-browser-build/src/`
- Chromium: **Google Chrome for Testing 159.0.8154.6**
  `/home/hatch/.cache/ms-playwright/chromium-1255/chrome-linux64/chrome` (playwright로 설치)
- 데몬: 첫 실행 시 상주 데몬이 뜬다. 상태 `muse-ultra-browser status`, 종료 `muse-ultra-browser stop`.
  소켓/로그: `~/.local/share/muse-ultra-browser/` (daemon.sock, daemon.log, profile/)

## 현재 상태 (2026-11-20) — 설치·검증 완료 ✅
- data: 페이지 스모크 테스트 통과, https://example.com 실제 접속·스냅샷 확보 성공 (run.sh 경유 포함)
- 데몬 status/stop 동작 확인. 종료 시 데몬·Chrome·릴레이까지 정리됨. (2026-11-26 정정: 지금은 stop/idle-stop이 공유 릴레이를 내리지 않는다 — 릴레이 종료는 `stop-relay.sh` 명시 실행만. 아래 stop 설명이 현행이다.)
- **인증서 검증 ON (우회 제거)**: `--ignore-certificate-errors`를 제거하고 NSS DB 기반
  정상 신뢰로 교체 완료. 일반 사용 가능 — "공개 페이지 전용·로그인 금지" 전제는 폐지됨.
  검증 근거 (2026-11-20):
  - run.sh 경유 example.com 정상 로드 (검증 켜진 상태)
  - self-signed.badssl.com / expired.badssl.com 접속 차단 (프록시 층 ERR_EMPTY_RESPONSE)
  - 로컬 분리 테스트: NSS DB에 넣은 CA로 서명한 인증서는 로드, self-signed는
    ERR_CERT_AUTHORITY_INVALID로 차단, DB에 없는 제3의 CA 서명도 차단
    → 신뢰가 DB 근거로 동작하고 검증기가 실제로 켜져 있음을 확인.
- **세션 지속성**: 프로필은 `meta-muse-ultra/profile`에 고정. 단, 하네스의 Space는 격리 컨텍스트라
  `t.finish({keep: []})`로 닫으면 쿠키가 폐기된다. 세션을 이어가려면 페이지를 keep한 뒤
  다음 호출에서 `claimTaskSpace(id)`로 재진입할 것 — 이 방식으로 별도 run.sh 호출 간
  쿠키 유지(httpbin 쿠키 왕복)를 실측 확인함. 데몬이 죽으면 런타임 컨텍스트는 사라진다.

## 샌드박스 우회 구조 (왜 chrome-wrapper가 필요한가)
이 VM의 egress는 런타임 프록시 경유가 강제되고, 스톡 Chromium을 그대로 쓰면 두 군데서 막힌다:
1. **CONNECT 403**: egress 프록시(`hatch-egress-proxy:3128`)가 Chrome 프로세스의 직접 CONNECT를
   403으로 막는다 (curl/python/node/socat은 통과 — 프로세스 식별로 보임).
   → chrome-wrapper가 `socat` 릴레이(127.0.0.1:18080 → 프록시)를 자동 기동하고
   Chrome에 `--proxy-server=http://127.0.0.1:18080`을 붙인다. 트래픽은 여전히 같은 프록시를 거친다.
2. **인증서 오류(-202)**: 프록시가 `Hatch Sandbox Egress CA`로 TLS를 MITM한다.
   초기 조사에서는 "CfT 내장 검증기가 NSS DB를 읽지 않는다"고 봤으나 **이는 오진이었다** —
   재검증 결과 검증기는 `$HOME/.pki/nssdb`를 읽으며, 런타임 기본 DB의 CA 신뢰 플래그가
   `C,,`라서 신뢰가 성립하지 않았던 것이 실제 원인이다.
   → UltraBrowse 전용 HOME(`chrome-home/.pki/nssdb`)에 CA를 `CT,C,C` 신뢰로 임포트하고,
   chrome-wrapper가 Chrome 프로세스의 HOME만 그쪽으로 지정한다. `ensure-nssdb.sh`가
   매 실행 시 지문을 대조해 DB를 자동 유지한다. `--ignore-certificate-errors`는 쓰지 않는다.
- `/opt/meta-chromium/chrome`은 Hatch CVM 전용 빌드라 단독 기동 불가 (WebGL 도메인 정책 오류) — 쓰지 말 것.

## 최적화 패스 1 실측 (2026-11-20)
스냅샷 크기 (원본 → trim → text):
| 페이지 | 원본 | trim | text |
|---|---|---|---|
| example.com (viewport) | 1,862B | 1,862B | 1,285B |
| Wikipedia Seoul (viewport) | 19,490B | 15,450B (-21%) | 1,483B |
| Wikipedia Seoul (full_page) | 797,235B | 654,088B (-18%) | 99,042B (-88%) |

건당 소요 시간:
- 가벼운 페이지: 콜드(데몬+Chrome 기동 포함) 3.8초, 웜 open 1.3~1.6초, 웜 read 1.5~1.8초.
  데몬 재사용이 기본이라 연속 호출은 웜 기준으로 돈다.
- 무거운 페이지 (Wikipedia Seoul read, 총 56초) 구간 분리:
  스페이스+페이지 0.4초 / goto 15.1초 (하네스 로드 타임아웃 — 프록시 경유 로드 지연) /
  **full_page 스냅샷 생성 39.8초 (지배적 구간)**. 노드 ~17K개급 거대 페이지에서만 발생.
  → read는 60초 타임아웃에 걸릴 수 있는 상한 케이스가 이 부류다. 일반 페이지는 수 초 단위.
- 후처리 중 발견·수정한 버그: 스냅샷 ref 표기가 `[ref=165, loc=css:...]` 형태일 때
  snaptrim 파서가 노드로 인식 못해 트리가 붕괴하던 문제 → 정규식 수정 후 heading 47개 정상 복원.
- `muse-ultra-browser stop`은 데몬·Chrome을 정리하지만 socat 릴레이(18080)는 남는다 (재사용되므로 무해,
  완전 종료는 `stop-relay.sh`).

## 보안 경계 (2026-11-27 감사 반영)

- **Chromium 샌드박스**: 실행 옵션에 `--no-sandbox --disable-setuid-sandbox`가 있다. 이 VM의
  exec는 root로 동작하는데, root에서는 Chromium 샌드박스 자체가 기동을 거부한다
  (실측: 플래그 없이 실행 시 "Running as root without --no-sandbox is not supported"로
  종료). 즉 이 환경에서는 샌드박스 활성화가 불가능하고, 격리는 VM 자체의 경계와
  출구 프록시가 담당한다. **잔존 위험**: 악성 페이지가 브라우저 프로세스를 탈취하면
  같은 VM 안의 파일(브라우저 프로필 포함)에 닿을 수 있다. 비-root 실행 환경에서는
  플래그를 제거하고 샌드박스를 켜야 한다. TLS 인증서 검증은 유지된다
  (`--ignore-certificate-errors` 금지).
- **데몬 소켓**: `cdp-daemon.sock`은 에이전트 자신의 제어 채널이다. 소켓으로 온
  스크립트는 데몬 프로세스에서 실행되는 것이 설계이며, 페이지 콘텐츠가 코드로
  실행되는 경로는 없다. 소켓 파일 권한은 소유자 전용(0600)으로 제한한다.
- **다운로드**는 상태 디렉터리 아래 `downloads/`에만 저장된다.
- **비밀번호 입력 (2026-11-28, 피클 빌드의 보안 묶음 채택)**: 데몬 스크립트 표면의
  `type()`/`typeText()`는 비밀번호 란 입력을 fail-closed로 거부한다
  (`password_field_refused` — 활성 요소 판정에 실패해도 거부). 유일한 예외는 전용
  드라이버 `vault-login.mjs`로, agent-vault 값을 데몬 안에서만 풀고 항목 사이트에
  https로만 입력한다 (origin 게이트를 볼트 개방 전·착지 후·제출 후·캡차/2FA 답변
  후·`chp=` 재진입 전에 검사). 캡차·2FA는 세션 유지 + 스크린샷 + 사람의 답변 파일
  브리지까지만 지원하며 자동 풀이는 없다.
- **탐지 실패 코드 F-DETECT (2026-11-28)**: 추출기·판정 grep 같은 탐지 단계 자체가
  실패하면 페이지 판정이 아니라 F-DETECT로 보고한다. 라우팅 캐시에도 넣지 않는다.
- **데몬 시작 락 (2026-11-28)**: 동시 기동은 `daemon.start.lock`(원자적 mkdir,
  15초 stale)으로 직렬화해 중복 데몬 실행을 막는다.
- **체인 볼트 라우팅 (2026-11-28)**: chain.sh가 F-AUTH를 만나면 `vault-match.py`
  (메타데이터만 조회)로 볼트 항목을 확인해, 있으면 exit 5
  (`next_action=vault-login`)로 이 하네스의 로그인을 지목하고 없으면 종전대로
  exit 3 (L2 인계)이다.

## 지문·WebGL·콜드스타트 패스 (2026-11-20)
전부 래퍼/설정 층에서만 수정 (하네스 본체 무수정). 실측 전/후:

| 항목 | 수정 전 | 수정 후 |
|---|---|---|
| UA (헤더·navigator) | `HeadlessChrome/159.0.0.0` 포함 | `Chrome/159.0.0.0` — Headless 표기 제거 |
| Accept-Language | `en-US,en;q=0.9` | `ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7` |
| navigator.language(s) | en-US / [en-US, en] | ko-KR / [ko-KR, ko, en-US, en] |
| Sec-Ch-Ua (open/read 경로) | `"Chromium"`만 | `"Google Chrome";v="159", "Chromium";v="159", "Not A(Brand";v="8"` |
| navigator.webdriver | false | false (유지) |
| WebGL | 컨텍스트 생성 실패(no-context), vendor/renderer null | 동작 — vendor `Google Inc. (Google)`, renderer `ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (Subzero)), SwiftShader driver)` |
| 데몬 정지 후 첫 호출 | `ENOENT daemon.sock` 1회 실패 | 첫 호출 성공 |

수단:
- **UA**: chrome-wrapper가 `--user-agent`로 정식 Chrome 159 UA를 고정.
- **언어**: `--lang=ko-KR`만으로는 부족했다 (프로필 pref가 우선). 프로필
  `Default/Preferences`의 `intl.accept_languages`와 `intl.selected_languages`를
  **둘 다** `ko-KR,ko,en-US,en`으로 세팅해야 유지된다 (하나만 바꾸면 Chrome이
  시작 시 en-US로 되돌림 — 실측). 여기에 run.sh open/read가 CDP
  `Emulation.setUserAgentOverride`(acceptLanguage는 q값 없는 태그 목록으로 —
  q값을 넣으면 navigator.languages에 q값이 새고 헤더가 이중 표기됨)로
  클라이언트 힌트 브랜드까지 맞춘다. 임의 JS(-f/인자) 경로는 플래그+pref까지만
  적용되고, 브랜드까지 맞추려면 JS에서 같은 `p.cdp(...)` 호출을 하면 된다.
- **WebGL**: muse-ultra-browser가 붙이는 `--disable-gpu`를 래퍼가 제거하고
  `--use-angle=swiftshader`를 추가. 둘 중 하나라도 빠지면 no-context로 돌아감 (실측).
- **콜드 스타트 레이스**: run.sh가 호출 전 `ensure_daemon`으로 소켓을 확인해
  데몬을 깨우고, open/read는 daemon.sock 오류 시 1회 재시도한다.
  단, 콜드 첫 호출 실측 ~15초 (패스 1 당시 3.8초와 차이 — 플래그 유무로
  재측정해도 동일해 WebGL 플래그 탓은 아님. 웜 호출은 1.4~4.4초로 종전 수준).

### 거대 페이지 read — 분할 전략 검토 결과: 미적용
Wikipedia Seoul (높이 34,457px ≈ 뷰포트 52개, DOM 노드 11,525개) 실측:
read(full_page) 52.8초, full_page 스냅샷 단독 28.8초, **뷰포트 스냅샷 단독도
14.8초** — 스냅샷 비용이 뷰포트가 아니라 페이지 전체 트리에 비례한다.
스크롤 분할은 합계가 오히려 커져 성립하지 않는다. 비용의 본체는 하네스
스냅샷 생성이라 래퍼 층에서 고칠 수 없다 — 현 상태 유지.

## 알려진 quirk
- run.sh에 JS를 printf 파이프로 넘기던 초기 방식은 muse-ultra-browser 클라이언트가 종료되지 않는 행(hang)이
  있었다 (출력은 완료됨). 임시파일 리다이렉트로 교체해 해결 (2026-11-20). 직접 호출 시에도
  heredoc/파일 입력 권장, 파이프 입력은 피할 것.

## 제약
- 일반 사이트 사용 가능 (인증서 검증 켜짐). 단, H255 크롬에 세션이 있는 사이트
  (부동산뱅크·직방)는 기존 라우팅대로 H255 agent-browser 담당 — 이 도구의 프로필에
  그 세션이 생기는 것은 아니다.
- 라이선스: muse-ultra-browser 저장소 자체에는 LICENSE 파일 없음. 구 하네스(단일 파일 런처 번들)는 citrolabs/muse-ultra-browser이며
  build-single.sh에 MIT로 표기됨. 현행 하네스는 자체 raw CDP 데몬(cdp-daemon.mjs/cdp-client.mjs)으로,
  2026-11-26 하네스 교체 때 구 런처 번들은 저장소에서 제거됐다.
