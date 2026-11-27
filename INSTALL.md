# 설치 — Muse Ultra Browser (뮤즈 울트라브라우즈)

현행 빌드(2026-11-26 하네스 교체 이후) 기준의 설치 절차다.

하네스는 단일 파일 런처 번들이 아니라, 이 저장소의 `meta-muse-ultra/` 안에 있는
자체 raw CDP 데몬이 담당한다 — `cdp-daemon.mjs`(데몬) + `cdp-client.mjs`(클라이언트),
npm 의존성 0. 별도로 설치할 바이너리는 없고, 저장소를 클론하면 구성 파일이 전부
들어 있다. `run.sh`가 이 데몬을 통해 Chromium을 운전한다.

## 에이전트 전용 설치 절차 (뮤즈 VM에 직접 설치)

이 도구는 사용자의 PC가 아니라 **뮤즈 에이전트가 사는 Linux VM 안**에
설치한다. 사용자가 GitHub 주소만 전달하면, 에이전트는 아래 순서를 그대로
실행해 설치를 끝내고 결과를 보고한다. 모든 단계는 에이전트 VM 안에서
실행하며, 사용자 PC에는 아무것도 설치하지 않는다. 단계별 상세 설명은 아래
"사전 요건"·"설치 절차" 절에 있으니, 막히는 단계에서는 그쪽을 참조한다.

### 1. 저장소 클론 (경로 고정)

스킬(`skills/muse-ultra-browser` 등)이 하네스 경로를
`~/workspace/muse-ultra-browser-build/meta-muse-ultra`로 기대하므로 클론
위치를 이 경로로 고정한다.

```bash
git clone https://github.com/osh3772-star/Muse-Ultrabrowse ~/workspace/muse-ultra-browser-build
cd ~/workspace/muse-ultra-browser-build/meta-muse-ultra
chmod +x *.sh
```

같은 위치에 이전 설치가 있으면, 덮어쓰기 전에 기존 `profile/`·`config.env`
(로그인 세션·설정)의 보존부터 판단한다 — 세션이 살아 있는 설치를 새 클론으로
교체하지 않는다.

### 2. 전제 조건 확인·설치

아래 "사전 요건" 표의 항목을 확인하고, 없는 것만 설치한다.

```bash
node --version                    # ≥ 22 여야 한다
npx playwright install chromium   # Chromium 본체
python3 --version
curl --version
```

검증된 조합 (2026-11-27 실측, 기준 설치): Node v24.22.1, Chromium
159.0.8154.6 (Playwright chromium-1255), Python 3.12.3. 설치 후 doctor가
해석된 Chromium 경로와 버전을 출력하니 이 조합과 대조한다. 버전이 다르면
동작이 달라질 수 있으며, 그 경우 `meta-muse-ultra/tests/run_tests.sh`로
회귀부터 확인한다.

`socat`·`certutil`은 비로컬 프록시·프록시 CA가 있는 환경에서만 필요하다 —
다음 5단계의 doctor가 환경에 맞게 PASS/SKIP으로 알려준다.

### 3. 설정 파일

```bash
cp config.env.example config.env
```

기본값 그대로 둔다. 항목별 의미는 아래 "설치 절차 2. 설정 파일"을 참조한다.

### 4. NSS DB (조건부)

egress 프록시가 TLS를 중계하는 환경에서만 실행한다 (프록시 CA가 없는
환경에서는 건너뛴다). 상세는 아래 "설치 절차 4"를 참조한다.

```bash
./ensure-nssdb.sh
```

### 5. 환경 진단

```bash
./doctor.sh --smoke
```

FAIL 항목이 있으면 그 항목부터 고치고 다시 실행한다. 전부 PASS(조건부
항목은 SKIP 가능)가 될 때까지 다음 단계로 넘어가지 않는다. `--smoke`는 임시
상태/프로필로 데몬 기동 → eval 왕복 → 정지를 확인하므로 실제 프로필은
건드리지 않는다.

### 6. 스킬 등록

저장소의 `skills/` 아래 디렉터리 전부(`agent-vault`, `browser-chain`,
`muse-ultra-browser`, `ultra-captcha-handling`)를 뮤즈의 커스텀 스킬
위치로 복사한다.

```bash
cd ~/workspace/muse-ultra-browser-build
cp -r skills/. ~/workspace/custom-skills/
```

### 7. 작동 테스트

```bash
cd ~/workspace/muse-ultra-browser-build/meta-muse-ultra
./run.sh warm
./run.sh read https://example.com
```

`read` 출력 끝에 `%%CHAIN%% lane=L1 mode=read status=ok ...` 결과 줄이
붙고 종료 코드가 0이면 성공이다.

### 8. 자격증명 인입 세팅

로그인 값을 채팅으로 받지 않기 위한 인입 경로를 설치와 한 세트로 세팅한다.

```bash
cd ~/workspace/muse-ultra-browser-build/meta-muse-ultra/intake
./intake.sh setup
```

- 판정은 시트 우선 → 파일 폴백이다. 시트 커넥터(`hatch_gws_cli sheets status`)가 `connected`면 비공개 구글 시트 경로(A), 아니면 파일 왕복 경로(B)로 기록된다. 미연결이면 시트 경로는 가드로 막혀 동작하지 않는다.
- 판정 결과는 상태 디렉터리의 `intake.json`에 남는다 (비밀값 없음). `./intake.sh path`로 확인할 수 있다.
- 볼트 초기화(`vault.py init`)가 안 돼 있으면 이 단계에서 함께 한다. 실제 폼·시트 행은 로그인이 필요한 사이트가 정해질 때 spec으로 만든다 — 절차 상세는 agent-vault 스킬의 "폼 기반 인입" 절과 `intake/README.md`를 따른다.

### 9. 결과 보고

사용자에게 다음을 보고한다: doctor 결과(PASS/FAIL/SKIP 항목), 위 read
테스트의 `%%CHAIN%%` 결과 줄, 설치 경로
(`~/workspace/muse-ultra-browser-build`). 설치 직후 1회 브리핑 항목은
등록한 `muse-ultra-browser` 스킬의 "설치 직후 브리핑" 절을 따른다.

## 사전 요건

| 항목 | 요건 | 용도 |
|---|---|---|
| OS | Linux | |
| Node.js | ≥ 22 | CDP 데몬·클라이언트 실행 (Node 22 내장 전역 WebSocket 등 사용) |
| Chromium | Chrome for Testing 159 (Playwright 설치본) | 브라우저 본체 |
| python3 | 표준 라이브러리만 | 스냅샷 후처리(`snaptrim.py`), 본문 추출 |
| socat | | 로컬 프록시 릴레이(127.0.0.1:18080) — 비로컬 프록시가 설정된 환경에서만 |
| certutil, openssl | NSS 도구 | 브라우저 전용 NSS DB에 egress CA 임포트 — 프록시 CA가 있는 환경에서만 |
| curl | | L0 경량 fetch(`fetch.sh`) |

Chromium은 Playwright로 설치한다:

```bash
npx playwright install chromium
# → ~/.cache/ms-playwright/chromium-*/chrome-linux*/chrome
```

`CHROME_PATH`(데몬이 실행할 래퍼)의 기본값은 트리의 `chrome-wrapper.sh`이며,
래퍼가 실제 Chromium 바이너리를 자동 탐지한다 — 명시 지정
(`MUSE_ULTRA_CHROME`/`CHROME_BIN`) > Playwright 캐시의 최신 `chromium-*`
리비전 > PATH 순. 탐지 결과는 아래 `./doctor.sh`의 chromium 항목으로
확인할 수 있다.

## 설치 절차

### 1. 저장소 배치

이 저장소를 클론하고 `meta-muse-ultra/` 디렉터리로 이동한다. 스크립트에 실행
권한이 없으면 부여한다 (파일 모드가 보존되지 않는 경로로 받았을 때 필요).

```bash
cd meta-muse-ultra
chmod +x *.sh
```

### 2. 설정 파일

```bash
cp config.env.example config.env
```

`config.env` 항목:

- `CHROME_PATH` — 데몬이 실행할 래퍼. 기본값이 이 트리의
  `chrome-wrapper.sh`라 보통은 비워 둔다 (예시 파일에서도 주석 처리돼 있다).
  이 샌드박스 환경에서는 릴레이와 NSS DB를 붙이는 래퍼 경유가 필수이며,
  래퍼가 실제 Chromium 바이너리를 실행한다. 스톡 Chromium을 직접
  가리키지 않는다.
- `MUSE_ULTRA_PROFILE` — durable 브라우저 프로필 경로 (기본값은
  `meta-muse-ultra/profile`). 로그인 세션이 이 프로필에 유지된다.
- `MUSE_ULTRA_HEADLESS` — `1` (헤드리스 실행).
- `MUSE_ULTRA_API_PROVIDER` / `MUSE_ULTRA_API_KEY` — 등록만 가능한 슬롯.
  빈 값이 기본이고, 기본 운전은 외부 API 없이 에이전트가 판단해 호출하는
  방식이므로 비워 둔다.

### 3. 환경 점검 (doctor)

```bash
./doctor.sh          # 검사만 (실제 데몬·프로필 무변경)
./doctor.sh --smoke  # 임시 상태/프로필로 데몬 기동 → eval 왕복 → 정지까지
```

Node ≥ 22, python3, curl 같은 필수 도구, Chromium 자동 탐지 결과와 경로,
`config.env` 유효성, 상태/프로필 디렉터리의 생성 가능 여부, 프록시 도달
가능성, NSS DB 준비 상태를 항목별 PASS/FAIL/SKIP로 출력한다. 치명 항목이
실패하면 종료 코드가 0이 아니다. 아래 단계에서 막히면 먼저 이 출력의
FAIL 항목부터 확인할 것.

### 4. NSS DB 준비 (인증서)

egress 프록시가 TLS를 중계하는 환경에서는, 프록시 CA를 브라우저 전용 NSS DB에
넣어야 인증서 검증이 성립한다.

```bash
./ensure-nssdb.sh
```

- `chrome-home/.pki/nssdb`에 프록시 CA를 `CT,C,C` 신뢰로 임포트한다. CA 경로는
  `config.env`의 `UB_PROXY_CA`가 1순위이고 구 변수 `HATCH_EGRESS_CA`도
  인식하며, 둘 다 없으면 레거시 경로
  (`/usr/local/share/ca-certificates/hatch-egress-ca.crt`)를 자동 탐지한다.
  프록시 CA가 없는 환경에서는 이 단계 전체를 건너뛴다.
- `chrome-wrapper.sh`가 실행 때마다 이 스크립트를 자동 호출해 지문을 대조하고
  필요하면 재생성하므로, 수동 실행은 초기 확인용이다.
- `--ignore-certificate-errors`는 쓰지 않는다 — 인증서 검증 ON이 기본이다.

### 5. 릴레이 (자동)

egress 프록시가 Chromium 프로세스의 직접 CONNECT를 막는 환경에 대응해,
비로컬 프록시가 설정돼 있으면 `chrome-wrapper.sh`가 socat 릴레이
(기본 `127.0.0.1:18080`, `UB_RELAY_PORT`로 변경 가능)를 자동 기동하고
Chromium에 `--proxy-server`로 지정한다. 프록시가 없으면 릴레이도 없다.
릴레이만 따로 끄려면 `./stop-relay.sh`를 쓴다.

### 6. 데몬 선기동

```bash
./run.sh warm
```

첫 실제 호출이 데몬을 자동 기동하지만, 다단계 작업 전에는 `warm`으로 미리
띄워 두면 콜드 스타트와 소켓 경합을 피할 수 있다. 데몬 상태 파일은
`~/.local/share/muse-ultra-browser/` 아래에 생긴다
(`cdp-daemon.sock`, `cdp-daemon.pid`, `cdp-daemon.log`, `cdp-chrome.log`).

### 7. 동작 확인

```bash
./run.sh read https://example.com
```

성공하면 본문 뒤에 결과 줄이 붙고 종료 코드는 0이다:

```
%%CHAIN%% lane=L1 mode=read status=ok ... chars=...
```

상태 확인은 `./run.sh status`, 종료는 `./run.sh stop`이다. 호출이 없으면
데몬과 릴레이는 600초 뒤 자동 정지한다 (상주시키려면 `./run.sh keep`).

## 사용법 요약

```bash
./run.sh doctor [--smoke]   # 환경 점검 (도구·Chromium 탐지·디렉터리·프록시·NSS)
./run.sh open <url>          # 이동 + 구조 스냅샷
./run.sh read <url>          # 본문 텍스트
./run.sh read --lean <url>   # 이미지·폰트·미디어 요청 차단 (읽기 전용 작업용)
./run.sh read --fp <url>     # 대상 호스트만 통과시키는 엄격 모드 (광고·추적 많은 페이지용)
./run.sh batch steps.txt     # 여러 단계를 exec 1회로 실행
./run.sh -f script.js        # 임의 JS (파일로만)
./fetch.sh <url>             # L0: 브라우저 없는 경량 fetch
./chain.sh read <url>        # 체인 진입점 (L0 → L1 → L2 폴백)
```

## 주의

- 항상 `config.env`의 `CHROME_PATH`(래퍼)를 경유해 실행한다. 스톡 Chromium
  직접 실행과 `--ignore-certificate-errors`는 금지.
- JS는 `-f` 파일로 넘긴다. 표준입력 파이프로 넘기면 클라이언트가 종료되지
  않는 hang이 있다.
- `profile/`, `chrome-home/`, `config.env`는 런타임 상태라 저장소에 올리지
  않는다 (`.gitignore`로 차단됨).
- 스크립트 API와 운용 규칙의 상세는 `meta-muse-ultra/README.md`와
  `skills/muse-ultra-browser/SKILL.md`를 본다.
