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
4. **자격증명은 볼트에 암호화로만** — 로그인이 필요한 사이트의 값은 로컬 볼트(agent-vault)에 암호문으로만 저장된다. 어떤 명령의 출력·로그·대화에도 값이 남지 않고, 에이전트도 값을 읽어서 보여줄 수 없다. 볼트 목록에서 보이는 것은 이름·용도·저장 날짜뿐이다.
5. **인입 경로는 설치 때 정한 한 가지** — 비밀번호를 받는 통로는 설치 때 세팅한 한 가지뿐이다: 비공개 구글 시트, 또는 파일 왕복 중 실제로 구성된 쪽을 한 줄로 알린다. 아이디는 에이전트가 미리 채워두므로 사용자는 비밀번호 칸만 채우면 된다. **비밀번호를 채팅 본문에 적지 말 것** — 이미 적었다면 그 비밀번호는 바꾸는 편이 안전하다고 알린다.
6. **반영이 끝나면 원본은 지워진다** — 값이 볼트로 옮겨지면 시트의 해당 칸은 비워지고, 파일 왕복이면 폼 파일과 그 사본까지 파쇄된다. 결과는 `ok site=… cleared=yes` 한 줄로 보고한다.
7. **삭제·교체는 이름으로** — 빼고 싶은 값이 있으면 사이트 이름만 말하면 `vault.py delete`로 지우고, 값을 바꾸는 것은 `store --force` 교체다. 절차 상세는 agent-vault 스킬과 `meta-muse-ultra/intake/README.md`를 따른다.
8. **하는 일과 안 하는 일** — 이 하네스는 페이지 읽기·목록 수집·클릭/입력 같은 가벼운 조작을 한다. 로그인은 볼트 값을 메모리로만 건네는 절차로 처리하고, 결제·2단계 인증 승인·캡차처럼 사람만 할 수 있는 단계에서는 멈추고 사용자에게 알린다.
9. **출구 IP의 한계** — 이 VM의 출구는 데이터센터 IP라, 사이트가 브라우저가 아니라 IP를 보고 막는 경우가 있다. 고장이 아니라 한계이며, 그럴 때는 체인의 다음 출구로 전환한다.
10. **차단되면 다음 출구로** — 한 경로가 차단·실패하면 멈춰서 보고만 하지 말고, 체인의 다음 출구로 전환해 계속 진행한다.
11. **자원 사용** — 데몬은 호출이 없으면 idle 600초에 자동 정지한다 (2026-11-26에 120→600으로 변경: 에이전트가 단계 사이 생각하는 시간보다 짧으면 데몬이 죽어 콜드 스타트+카드가 반복됐다). 구동 중 메모리는 데몬+Chrome 합쳐 1GB 남짓이다.

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
$META/run.sh warm           # 데몬 선기동 (다단계 작업 시작 시 — 콜드 스타트·소켓 경합 회피)
$META/run.sh batch steps.txt  # 여러 단계를 exec 1회로 실행 (아래 "배치" 절)
```

**배치 (2026-11-26 신설)**: 다단계 작업(로그인 플로, 여러 페이지 연속 읽기 등)을
단계마다 exec로 쪼개면 호출마다 데몬 재기동·신규 호스트 접속이 생겨 카드가 다시
뜬다 (2026-11-26 직방 로그인에서 재발). steps 파일에 한 줄에 한 단계씩 적어
`run.sh batch`로 한 번에 실행한다:
```
read --fp <url>
read --lean <url>
js <script.js>
warm / keep / stop
```
단계별 출력 + `%%BATCH-STEP%%` 헤더, 마지막에 `%%BATCH%% steps=.. ok=.. fail=..`
요약 줄이 나온다. 한 단계가 실패해도 나머지는 계속 실행된다.

**환경 점검 `doctor` (2026-11-26 신설)**: `$META/run.sh doctor [--smoke]` (또는
`$META/doctor.sh` 직접). ub-config.sh의 해석 규칙 그대로 Node ≥22·python3·curl·
socat/certutil(조건부), Chromium 자동 탐지 경로와 버전, CHROME_PATH 실행 가능
여부, config.env 유효성, 상태/프로필/chrome-home 디렉터리 생성·쓰기 가능 여부
(없는 디렉터리는 실제로 만들어 확인 — 신규 설치 ENOENT 부류 방지; 기존 프로필
디렉터리에는 쓰지 않음), 프록시 도달 가능성(호스트:포트만 출력), NSS DB 준비
상태를 항목별 PASS/FAIL/SKIP + 한 줄 사유로 출력하고 치명 항목 실패 시 종료
코드가 비0이다. 기본 실행은 검사만이라 실제 데몬·프로필을 건드리지 않는다.
`--smoke`는 임시 상태/프로필/chrome-home으로 데몬을 띄워 eval 왕복 후 정지까지
확인한다 (실제 프로필 무접촉). 새 인스턴스 설치 직후와 "우리 VM에선 되는데
신규 설치에서 깨지는" 부류의 진단에 먼저 돌릴 것. 설치 절차는 repo INSTALL.md
3단계에도 들어 있다.

**노카드 모드 `--fp` (2026-11-24 실측, 2026-11-26 복구·재검증)**: exec 네트워크 승인은 호스트마다 카드가 뜨는데,
페이지 본체가 아니라 광고·추적 서브리소스 호스트가 대부분이다. `--fp`는 CDP Fetch로
전 요청을 가로채 ① 대상 호스트 정확 일치(www 유무 변형 포함)만 통과, 서브도메인 포함
전부 차단 ② 추출이 끝나 페이지가 닫힐 때까지 차단을 유지(늦게 나가는 비콘 누수 방지)
③ 이미지·폰트·미디어는 1차 호스트라도 차단한다. 실측: 연합뉴스 기사 read — 카드 9장+
나오던 조건에서 **0장**, 본문 10,506자 정상. 광고·집계가 많은 페이지(뉴스 등)를
exec로 읽을 때는 기본으로 `--fp`를 붙여라. 단, 본문이 서브도메인 JS에 의존하는
페이지는 비어 보일 수 있으니 그때만 빼고 재시도한다. 검증·회귀·세션 체크처럼
상태 확인이 목적인 로드는 이 재시도 예외가 적용되지 않는다 — 아래 "작업 절차
규칙" 절의 --fp 강제 규칙을 따른다.

**⚠️ Fetch 패턴 규칙 (2026-11-26 하네스 교체로 갱신)**: 유형 거부
(TextTrack 등 5종)의 출처는 하네스가 아니라 **Chrome 159의 Fetch 도메인 자체
검증**이었다 — 유형을 열거한 패턴은 예외를 던지거나 커버리지가 좁아진다.
정석은 **resourceType 없는 bare 패턴** `{urlPattern:'*', requestStage:'Request'}`
하나로, Fetch가 일시정지할 수 있는 전 요청 + CORS 프리플라이트(XHR/OPTIONS로
표면화)까지 잡는다. 단 **WebSocket 핸드셰이크는 Fetch로 못 막는다** (bare
패턴에서도 실접속 실측) — WS로 제3자 호스트에 붙는 페이지는 카드 가능성이
남는다. 그리고 일시정지 응답은 스크립트의 events() 펌프가 아니라 데몬측
**`p.armFetch(policy, fallback)`** 으로 해야 한다 — events() 방식은
Runtime.evaluate와 교착한다 (상세: `~/workspace/ultra-harness-2026-11-26.md`).
재검증 (2026-11-26, 교체 후): YNA 기사 --fp read 4.7초·18,650자, 검증 구간
전체 카드 **0장**.

**입력 프리미티브 (2026-11-26 이식)**: 데몬 page 객체에 muse-desktop `chromeControl.js`(MIT)에서 이식한 입력 메서드가 있다 — 지금까지는 상호작용을 전부 임의 JS로 짜야 했는데, 이제 ref 기반으로 된다. `-f` 스크립트 안에서:
- `await p.elements()` — 보이는 상호작용 요소 목록: `{id:'e1', kind, x, y, type?, text?, label?, placeholder?, href?, value?, checked?, disabled?}` + `{url, title, truncated}`. 상한 300개. 비밀번호 입력은 값이 아니라 type만 나온다. 요소마다 `data-muse-id` 속성이 박혀 이후 호출이 그걸로 찾는다.
- `await p.click(ref)` — ref는 `'e3'`(elements의 id), CSS 셀렉터 문자열, `{id}`/`{selector}` 중 하나. scrollIntoView 후 중심점에 CDP `Input.dispatchMouseEvent`로 실제 클릭.
- `await p.type(ref, text, {clear:true})` — ref에 포커스 → (clear 시 Ctrl+A+Backspace) → `Input.insertText`. `await p.typeText(text)`는 현재 포커스된 곳에 바로 입력.
- `await p.press(key)` — `'Enter' 'Tab' 'Escape' 'Backspace' 'Delete' 방향키 'Home' 'End' 'PageUp/Down' 'Space' 'F1'~'F12'` 또는 한 글자. CDP `Input.dispatchKeyEvent` (특수키 표도 chromeControl에서 이식).
- 요소가 사라졌으면 `element_not_found` 에러 — `elements()`를 다시 불러 새 id를 쓸 것.
- 기존 AX `p.snapshot()`은 그대로 있다 (구조 파악용). 좌표 클릭이 필요하면 `elements()` 쪽.
- 이식 상세·백업: 데몬 주석(Transplanted 2026-11-26), 백업 `meta-muse-ultra/backup-input-2026-11-26/`. 검증: data: 테스트 페이지에서 elements→click(버튼 핸들러 발동)·type·press('Enter' keydown 발동)·clear 교체·셀렉터 클릭 전부 통과, 기존 `--fp` read 회귀 없음(위키 5.8초), 검증 구간 카드 0장(종료 후 65초 대기해 history로 셈).

**스냅샷 diff (2026-11-27 신설, Aside 이식 ①)**: `-f` 스크립트에서 `await p.snapshot({diff:true})` — 직전 스냅샷 대비 변경분만 반환한다 (cskwork 패턴). 액션 후 전체 트리를 다시 받는 토큰 낭비를 줄이는 용도.
- 반환 형식: 헤더(title/url) + `snapshot-diff: +A -R ~C` 줄 + `+ `(추가)/`- `(삭제)/`~ `(변경) 접두 줄들. 변경이 없으면 `(no changes)`.
- 기준선(baseline)은 **모든** snapshot 호출이 갱신한다 — 일반 `p.snapshot()`을 부른 직후의 diff는 `(no changes)`가 정상. 첫 diff 호출(기준선 없음)은 전체 트리 + `no baseline yet` 주석을 반환한다.
- 비교 키는 backendDOMNodeId(없으면 트리 경로)라, 같은 페이지의 연속 스냅샷에서만 의미가 있다. 페이지가 통째로 바뀌면 diff가 아니라 전체 스냅샷을 새로 받아라.
- 옵션이 없는 `p.snapshot()`과 run.sh의 호출(`{scope:"full_page"}` 포함)은 종전과 동일하게 동작한다.

**스냅샷 스코핑 (2026-11-27 신설, Aside 이식 ③)**: `-f` 스크립트에서 `await p.snapshot({ref})` / `p.snapshot({selector})` / `p.snapshot({interactiveOnly:true})` — 큰 페이지에서 필요한 부분만 받는 용도.
- `ref`는 스냅샷 줄에 찍히는 backendDOMNodeId(숫자), elements()의 `'e3'` id, CSS 셀렉터 문자열 중 하나. `selector`는 항상 CSS 셀렉터. 대상 요소의 서브트리만 반환하고 스코프 루트는 depth 0으로 다시 맞춰진다. 출력 헤더에 `scope: subtree of [ref=N] (K entries, depths rebased)` 줄이 붙고, 대상을 못 찾으면 `scope target not found` 에러를 던진다.
- `interactiveOnly:true`는 상호작용 역할(button·link·checkbox·radio·tab·menuitem·option·switch·textbox·searchbox·combobox·listbox·slider·spinbutton·treeitem·gridcell) 줄만 남긴다 (들여쓰기 유지). ref/selector와 조합 가능하고, 헤더에 `scope: interactive-only` 줄이 붙는다.
- **diff 기준선은 스코프별로 분리된다** — 무스코프 기준선 1개 + 스코프 대상별(+interactiveOnly 조합별) 기준선. 모든 snapshot 호출은 자기가 실행된 스코프의 기준선만 읽고 갱신하므로, 스코프 스냅샷이 전체 페이지 diff 기준선을 오염시키지 않는다 (역도 마찬가지). 스코프 diff의 첫 호출은 그 스코프의 전체 트리 + no-baseline 주석을 반환한다.
- 옵션이 없는 `p.snapshot()`과 run.sh의 호출(`{scope:"full_page"}` 포함)은 종전과 동일하게 동작한다.
- 검증 (2026-11-27): 중첩 테스트 페이지에서 selector/숫자 ref/e-ref 스코핑, interactive-only의 정적 텍스트 제외, 스코프 사용 후 전체 diff 무오염, 스코프별 diff 기준선 독립까지 31개 단언 전부 통과 — 백업 `meta-muse-ultra/backup-aside-step3-2026-11-27/`.

**이벤트 신호 + 다운로드 (2026-11-27 신설, Aside 이식 ②)**: `-f` 스크립트에서 쓰는 비동기 신호·다운로드 프리미티브. 지금까지는 팝업·다운로드·탭 닫힘을 스크립트가 폴링으로 발견해야 했는데, 데몬이 선별해 신호로 준다.
- `await p.drainEvents()` — 지난 drain 이후의 신호를 시간순 배열로: `{kind:'popup', targetId, url}`(페이지가 window.open/target=_blank로 연 팝업 탭), `{kind:'tab_closed', targetId}`(팝업 또는 우리 페이지 소멸), `{kind:'dialog', dialogType, message}`(이 페이지의 JS 다이얼로그 — `Page.handleJavaScriptDialog`로 처리하기 전까지 페이지가 멈춰 있다), `{kind:'download_started'|'download_completed'|'download_canceled', guid, url, filename, state, received, total}`. 원시 CDP 스트림은 기존 `p.events()`가 그대로 담당한다.
- `await p.waitForEvent(kind, {timeoutMs=15000})` — 해당 kind의 첫 신호, 시간 초과면 null. 단 기다리는 동안 지나간 다른 신호도 함께 소비(drain)되니, 스트림 전체가 필요하면 `drainEvents()`를 써라.
- `p.downloads()` — 데몬이 본 다운로드 전체 목록 `{guid, url, filename, state, received, total, startedAt}`.
- `await p.waitForDownload({timeoutMs=30000, filename?, url?})` — 완료: `{completed:true, path, bytes, filename, url, guid}` (path는 상태 디렉터리 `~/.local/share/muse-ultra-browser/downloads/` 아래 파일, bytes는 디스크 실측 크기). 취소: `{completed:false, state:'canceled', …}`, 시간 초과: `{completed:false, state:'timeout', pending:[…]}` — 예외가 아니라 보고 객체를 돌려주니 호출자가 다음 행동을 정한다. 다운로드 동작(allow+저장 경로)은 첫 페이지가 생길 때 데몬 전역으로 무장되므로, 클릭으로 시작된 다운로드도 나중에 `waitForDownload`로 회수할 수 있고, 호출 5초 전까지 시작된 것도 매칭된다.
- 검증 (2026-11-27): data: 테스트 페이지에서 window.open 팝업 신호 포착, data: 다운로드 completed·26바이트·디스크 내용 일치, drain에 started/completed 수신 — 백업 `meta-muse-ultra/backup-aside-step2-2026-11-27/`.

**a11y 상태 토큰 + 세션 fetch + PDF·annotated 스크린샷 (2026-11-27 신설, Aside 이식 ⑤)**: 스냅샷 줄의 상태 표기와, 페이지 세션을 쓰는 회수 프리미티브 묶음.
- **스냅샷 상태 토큰**: 모든 스냅샷 줄의 `[…]` bracket 안에 `ref=` 뒤로 상태 토큰이 붙는다 — `iframe`(Iframe 역할), `focused`(현재 포커스), `disabled`, `checked`(체크됨; tristate 'mixed'는 `checked=mixed`), `selected`, `expanded`/`collapsed`, `clickable`(클릭 가능 역할이거나 AX focusable). 없는 상태는 표기되지 않는다. snaptrim 문법(단일 bracket 그룹)은 그대로 유지된다. diff 비교에도 상태 변화가 `~` 변경으로 잡힌다.
- `await p.fetchInPage(pathOrUrl, opts)` — 페이지 안에서 fetch를 실행해 **페이지 세션(쿠키)을 동반**하는 same-origin 전용 헬퍼. L0 `fetch.sh`는 브라우저 쿠키가 없어 못 받는 로그인 세션 파일·데이터 회수용. 교차 출처는 요청을 보내기 전에 거부한다. opts: `{method, headers, save, name, json}`. 텍스트/JSON은 인라인 반환(100k 상한, `truncated` 표기), 바이너리거나 `save:true`면 상태 디렉터리 `downloads/`에 저장하고 `{savedTo, bytes}`를 반환한다.
- `await p.apiFallback(pathOrUrl, opts)` — DOM 추출이 막힐 때 페이지가 실제로 호출하는 same-origin 엔드포인트에서 데이터를 읽는 **범위가 잘린** 폴백 (fetchInPage + 기본 json). **접근 거부의 우회가 아니다**: 401/403이면 `api_fallback_access_denied` 에러를 던지니, 호출자는 그 자리에서 중단하고 체인 규칙(보고·다음 출구 전환)을 따라라. 거부 앞에서 재시도·우회를 시도하지 않는다.
- `await p.pdf(opts)` — `Page.printToPDF`로 현재 페이지를 PDF로 저장하고 `{path, bytes}` 반환 (상태 디렉터리 `downloads/`, opts: `{name, landscape, printBackground, paperWidth, paperHeight}`).
- `await p.annotatedScreenshot(opts)` — `elements()`의 e-id를 페이지 위에 박스+라벨로 그려 스크린샷을 저장하고 `{path, count, elements, bytes}` 반환 (PNG, 상태 디렉터리 `downloads/`). 오버레이는 촬영 직후 제거된다. 시각 확인·좌표 대조용.
- 검증 (2026-11-27): 로컬 테스트 페이지에서 상태 토큰 10종 실측(checked는 AX tristate 문자열 'true'로 오는 것을 확인해 반영), annotated 라벨 11개 육안 확인, fetch json/save·교차출처 거부·403 구조화 에러, PDF 매직까지 18개 단언 전부 통과 — 백업 `meta-muse-ultra/backup-aside-step5-2026-11-27/`.

**챌린지 감지+대기 (2026-11-27 신설)**: `-f` 스크립트에서 `await p.challenge(opts)` — ego lite의 `task.handleChallenge()`를 본뜬 **감지+대기 전용** 프리미티브. 챌린지를 클릭·풀이하지 않는다.
- 반환: `{detected, type, passed, waitedMs, url}`. `type`은 `turnstile`/`hcaptcha`/`recaptcha-v2`/`recaptcha-v3`/`cloudflare-challenge`/`generic`/null. `passed`는 토큰 생성·위젯 소멸·(인터스티셜) 통과 이동이면 true, 미해결이면 false, recaptcha-v3(점수 기반, 관찰 불가)는 null.
- 옵션: `timeoutMs`(기본 30000, 전체 상한), `pollMs`(기본 500), `appearMs`(기본 3000, 위젯 등장 유예), `wait:false`면 1회 탐지만.
- **주의 — `--fp`에서는 위젯이 안 뜬다**: 챌린지 호스트(challenges.cloudflare.com·hcaptcha.com·www.google.com/recaptcha)가 Fetch 가로채기에 막혀 렌더링 자체가 안 되므로, `detected:false`가 "챌린지 없음"을 뜻하지 않는다. 감지·대기는 lean/일반 모드 전용.
- 풀리지 않을 때의 절차(중단·보고·다른 출구로 전환, 자동 풀이 금지)는 **ultra-captcha-handling 스킬**을 따른다.
- 검증 (2026-11-27): reCAPTCHA 공식 데모(google.com/recaptcha/api2/demo)에서 `recaptcha-v2` 즉시 감지, 20초 대기 후 미해결 반환(사람 클릭이 필요한 챌린지라 자동 통과 없음이 정상) — 백업 `meta-muse-ultra/backup-captcha-2026-11-27/`.

## 출력 계약

- 성공: 본문 + `%%CHAIN%% lane=L1 … status=ok …` 1줄, exit 0
- 실패: 결과 1줄만, exit 1. 코드: F-IP(차단)/F-BOT(캡차)/F-EMPTY(100자 미만)/F-TIMEOUT(60초)/F-NET
- 실패 본문이 꼭 필요하면 `UB_DEBUG=1`을 붙인다 (stderr로 나간다). 평소에는 붙이지 마라 — 토큰 낭비다.
- **차단 탐지 문구 확장 (2026-11-27)**: `detect_code()`가 Cloudflare 인터스티셜의 영·한 실측 문구("Just a moment", "Performing security verification", "Checking if the site connection is secure", "Verifying you are human", "사람인지 확인하는 중", "보안 확인 수행 중")를 F-BOT로 잡는다. 종전 목록에는 이 문구들이 없어 챌린지 페이지 본문이 그대로 `status=ok`로 통과하고 routecache에 l1=ok가 7일 남는 오탐이 있었다 (무신사 실측: 수정 전 ok/1709자 → 수정 후 fail/F-BOT, 동일 1709자).
- **본문 settle 폴링 (2026-11-27 신설)**: read/open은 네비게이션 뒤 추출 전에 본문 텍스트 길이를 폴링한다 — 1,500자 도달 또는 3회 연속 정체(최소 체류 750ms) 시 종료, 상한 기본 4초. readyState 완료만으로는 SPA 하이드레이션 전에 읽어 F-EMPTY로 떨어지던 문제(무신사 캠페인 페이지: load 시 1자 → 2초 뒤 ~2,900자)의 수정이다. `UB_SETTLE=0`으로 끄고, `UB_SETTLE_MS`로 상한을 조정한다. 1,500자 미만인 작은 페이지는 정체 판정까지 최대 ~0.75초가 더 걸린다.
- **acceptLanguage 정렬 (2026-11-27)**: 데몬이 페이지를 생성할 때 ko-KR acceptLanguage를 전 경로 공통으로 건다. 종전에는 run.sh open/read만 걸어서 `-f` 스크립트는 같은 차단 페이지를 영문으로 받아 탐지 문구가 경로마다 갈렸다.

## 작업 절차 규칙 (2026-11-27 신설, Aside 이식 ④)

cskwork 스킬의 운용 규칙과 2026-11-27 카드 사고의 교훈을 절차로 박은 절이다. 코드가 아니라 읽고 따르는 규칙이다.

**읽기 에스컬레이션 사다리** — 상태를 읽을 때는 싼 단계부터 시작하고, 부족할 때만 한 칸씩 올린다:
1. 상호작용이 목적이면 `p.elements()` 또는 `p.snapshot({interactiveOnly:true})`로 싸게 시작한다.
2. 구조 전체가 필요하면 `p.snapshot()` 전체를 받는다.
3. 페이지가 크면 `p.snapshot({ref})` / `p.snapshot({selector})` 스코핑으로 필요한 서브트리만 좁혀 읽는다.
4. 액션을 한 뒤의 확인은 전체를 다시 받지 말고 `p.snapshot({diff:true})`로 변경분만 본다.
5. 그래도 상태를 확정할 수 없으면 잠시 기다렸다가 다시 찍고, 마지막 수단으로 스크린샷을 쓴다.

**액션은 확인 전엔 미확정** — 클릭·입력·이동 같은 액션은 실행했다고 끝이 아니다. 새 스냅샷(또는 diff)으로 결과가 실제로 반영된 것을 보기 전에는 "미확정"으로 취급하고, 확인 없이 다음 단계를 쌓지 않는다. 서로 의존성이 없는 액션과 그 확인 스냅샷은 한 호출(`run.sh batch`의 steps 또는 js 한 파일)로 묶어 왕복을 줄인다.

**이상하면 낡은 액션부터 의심** — 상태가 예상과 다르면 사이트 탓을 하기 전에 내 쪽부터 본다: ① 빠뜨린 액션이 있는지 ② 이전 페이지·이전 상태 기준으로 남은 낡은 ref·셀렉터로 실행한 액션이 있는지 ③ 엉뚱한 대상에 들어간 액션이 있는지. 이 셋을 확인한 뒤에야 사이트·세션 문제로 판정한다.

**확인 목적 로드는 --fp 강제 (2026-11-27 카드 사고 교훈)** — 검증·회귀·세션 체크를 포함해, 상태를 확인하려고 여는 모든 외부 페이지 로드는 `--fp` 모드로만 한다. `--fp`를 걸 수 없으면 로드 자체를 하지 말고, 못 한 사실을 보고한다. **세션 체크용 JS 세션 로드도 예외는 없다** — ③ 검증에서 --fp 없는 세션 체크 로드가 광고 서브도메인 승인 카드를 한 번에 ~34장 발생시켰다 (2026-11-27 16:31). 기능 수행 자체가 목적인 로드(로그인 플로 — agent-vault 스킬, 챌린지 감지 — ultra-captcha-handling 스킬)는 --fp가 그 기능 자체를 원천 차단하므로 각 전용 스킬의 절차를 따르되, 이 경우에도 단계를 exec로 쪼개지 말고 `run.sh batch`로 한 번에 실행해 카드가 뜨는 표면을 최소화한다.

**종료 절차 — 페이지를 열어둔 채 끝내지 않기 (2026-11-27 추가)** — 데몬에 로드된 페이지를 남겨두면 광고 비콘이 계속 나가면서, 작업이 끝난 뒤에도 승인 카드가 수 분간 지연 발생한다 (2026-11-27 16:38, contentsfeed·mobon 등 4장이 이 패턴으로 발생). 작업을 마칠 때는 ① 연 페이지를 닫고 ② 세션을 상주시킬 필요가 없는 작업이면 `run.sh stop`으로 데몬 정지까지를 종료 절차로 한다. 프로필에 저장된 로그인은 데몬을 내려도 유지되므로, 정지가 세션을 지우지는 않는다.

**불가피한 승인은 맨 앞에서 한 번에 (2026-11-27 추가)** — GitHub push-files 같은 커넥터 쓰기는 호출마다 승인 카드가 뜨는 구조라 피할 수 없다. 그런 호출이 필요한 작업은 중간에 끼워 넣지 말고 **작업 시작 직후에 몰아서 실행**하고, 본 작업은 그 뒤에 승인 없이 흐르도록 설계한다. 승인 카드가 작업 흐름을 끊는 위치에 오지 않게 하는 것이 목적이다.

## 운용 규칙

- 콜드: warm(데몬+Chrome 선기동) 3.4초, YNA --fp 콜드 read 8.0초. 웜: YNA --fp
  read 4.7초, 위키 lean 6.8초·--fp 5.1초, 배치 3단계 12.0초 (전부 2026-11-26
  하네스 교체 후 실측 — 교체 전 YNA --fp 19.4초의 대부분이던 첫 requestPaused
  ~15초 지연이 raw CDP에서 ~80ms로 사라진 결과). 데몬은 첫 호출이 자동
  기동한다 (`status`는 안 깨운다). 단일 호출이면 미리 깨울 필요 없지만,
  **다단계 작업이면 시작 시 `$META/run.sh warm`으로 선기동**하거나 아예
  `run.sh batch`로 묶어라 — 콜드 첫 호출의 소켓 경합(ECONNREFUSED)은 run_client가
  1회 재시도로 흡수한다 (2026-11-26 수정: 기존 재시도는 stdout만 grep해 발동 불가였음).
- idle 600초 무호출이면 데몬 자동 정지. **공유 릴레이(:18080)는 건드리지 않는다** —
  `run.sh stop`·idle-stop은 자기 데몬만 내리고, 릴레이 종료는 `stop-relay.sh` 명시
  실행으로만 한다 (2026-11-26 수정: stop이 릴레이까지 내려 다른 인스턴스의 출구를
  같이 끊던 문제). 긴 연속 작업이면 시작할 때 `$META/run.sh keep`,
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

- 반드시 CHROME_PATH(chrome-wrapper.sh) 경유로만 실행. 스톡 Chromium 직접 실행 금지.
  환경값(Chromium 바이너리·프록시·프록시 CA/NSS·상태/프로필 경로)은 코드에 고정돼 있지
  않고 `ub-config.sh`가 config.env·표준 환경변수에서 해석한다 (2026-11-26 이식성 패스:
  Chromium은 명시 경로 > Playwright 캐시 최신 리비전 > PATH 순 자동 탐지, 프록시
  미설정이면 직접 연결, CA 미설정이면 NSS 단계 생략). 다른 인스턴스에서는
  `config.env.example`의 선택 변수만 채우면 된다.
  `--ignore-certificate-errors` 금지 (인증서 검증 ON이 기본). `/opt/meta-chromium/chrome` 사용 금지.
- H255에 세션이 있는 사이트(부동산뱅크·직방)는 이 도구가 아니라 H255 agent-browser로.
- 런처 본체(`~/.local/bin/muse-ultra-browser`)는 2026-11-24 이름 전면 변경으로 파일명·내부 표기만 Muse Ultra Browser로 바뀐 것 — 기능·동작은 변경 전과 동일하다. 임의로 다른 빌드로 교체하지 않는다. **단 2026-11-26 사용자 전권 지시로 호출 경로의 하네스는 교체됐다**: run.sh는 이제 런처 대신 자체 raw-CDP 데몬(`cdp-daemon.mjs`/`cdp-client.mjs`)을 쓴다 (런처 바이너리 자체는 무변경, 롤백은 `backup-harness-2026-11-26/` 복원). 상세: `~/workspace/ultra-harness-2026-11-26.md`.

## 경로

- 래퍼 디렉토리: `~/workspace/muse-ultra-browser-build/meta-muse-ultra/` (run.sh, batch.sh, fetch.sh, chain.sh, chrome-wrapper.sh, ub-config.sh,
  cdp-daemon.mjs, cdp-client.mjs, idle-stop.sh, stop-relay.sh, snaptrim.py, html2text.py, routecache.py, route-cache.json, config.env, config.env.example)
- CDP 데몬 상태: `~/.local/share/muse-ultra-browser/` (cdp-daemon.sock/pid, cdp-daemon.log, cdp-chrome.log)
- 프로필: `meta-muse-ultra/profile` / 인증서 DB: `meta-muse-ultra/chrome-home/.pki/nssdb` (자동 유지)
- 재설계 전 백업: `meta-muse-ultra/backup-2026-11-24/`
- 영속화 변경 전 백업: `meta-muse-ultra/backup-persist-2026-11-24/` (런처 원본 + 스킬 원본)
- 성능·카드 재설계 전 백업: `meta-muse-ultra/backup-perf-2026-11-26/` (run.sh + idle-stop.sh + 스킬 원본), 상세 기록: `~/workspace/ultra-perf-2026-11-26.md`
- 하네스 교체 전 백업: `meta-muse-ultra/backup-harness-2026-11-26/` (run.sh + idle-stop.sh), 상세 기록: `~/workspace/ultra-harness-2026-11-26.md`
- 지문: UA 정식 Chrome 159, ko-KR, WebGL on, webdriver=false (래퍼+CDP 오버라이드가 자동 적용)
