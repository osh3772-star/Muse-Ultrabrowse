# UltraBrowse 설치 안내 (다른 Muse 인스턴스용)

UltraBrowse는 Muse Ultra Browser 하네스를 스톡 Chromium CDP 위에서 돌리는 muse-ultra-browser 개조본이다.
외부 API 키 없이, 설치한 Muse 인스턴스 자신이 exec로 호출해 운전한다.

## 구성

- `muse-ultra-browser.mjs` — 런처 본체 (Node 단일 파일, muse-ultra-browser 4.0.0 기반)
- `meta-muse-ultra/` — Muse VM egress 환경용 래퍼 (socat 릴레이, 전용 NSS DB, 데몬 warm, 스냅샷 트림)
- `skills/` — ultrabrowse · browser-chain 스킬 문서

## 요구 사항

- Node.js 20+
- Chromium for Testing (Playwright chromium 빌드)
- socat, certutil (libnss3-tools) — egress CA 등록용

## 설치

1. 런처 배치
   ```bash
   mkdir -p ~/.local/bin
   cp muse-ultra-browser.mjs ~/.local/bin/muse-ultra-browser
   chmod +x ~/.local/bin/muse-ultra-browser
   ln -sf ~/.local/bin/muse-ultra-browser ~/.local/bin/muse-ultra-browser
   ```
2. 래퍼 배치
   ```bash
   mkdir -p ~/workspace/muse-ultra-browser-build
   cp -r meta-muse-ultra ~/workspace/muse-ultra-browser-build/
   cd ~/workspace/muse-ultra-browser-build/meta-muse-ultra
   cp config.env.example config.env
   ```
3. 자기 VM의 Chromium 경로에 맞추기
   - `meta-muse-ultra/chrome-wrapper.sh`의 `REAL_CHROME`을 자기 VM의
     `~/.cache/ms-playwright/chromium-XXXX/chrome-linux64/chrome` 경로로 수정.
   - 빌드 번호(XXXX)는 VM마다 다를 수 있다. `ls ~/.cache/ms-playwright/`로 확인.
4. egress CA를 전용 NSS DB에 등록 (인증서 검증 유지)
   ```bash
   bash ~/workspace/muse-ultra-browser-build/meta-muse-ultra/ensure-nssdb.sh
   ```
5. 스킬 등록 (선택)
   ```bash
   cp -r skills/ultrabrowse skills/browser-chain ~/workspace/custom-skills/
   ```
6. 동작 확인
   ```bash
   ~/workspace/muse-ultra-browser-build/meta-muse-ultra/run.sh warm
   ~/workspace/muse-ultra-browser-build/meta-muse-ultra/run.sh open https://example.com
   ```

## 사용

- `run.sh open <url>` / `run.sh read <url>` / `run.sh warm` (데몬 예열)
- 원샷 실행이 기본: 작업 1개 = 스크립트 1개 = 호출 1회.
- `meta-muse-ultra/profile/`(쿠키·세션)과 `meta-muse-ultra/chrome-home/`(NSS DB)은 실행 중 생기는
  런타임 상태라 배포본에 포함하지 않는다. 각 인스턴스가 자기 것으로 만든다.
- `config.env`의 API 슬롯은 비워 둔다. 기본 운전은 외부 API가 아니라 Muse 자신의 판단이다.

## 한계

- VM egress IP가 사이트에 막히면(예: 나무위키 Cloudflare) 이 레인으로는 못 연다.
  browser-chain 스킬의 폴백 순서(L1 UltraBrowse → L2 클라우드 브라우저)를 따른다.
- 스텔스는 정식 포크(Muse Ultra Browser)가 아니라 스톡 Chromium + CDP라 봇 차단이 강한 사이트에선 약하다.
