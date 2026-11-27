---
name: "ultra-captcha-handling"
description: "Ultra Browser (체인 L1) 작업 중 사람 인증 챌린지(Cloudflare Turnstile, hCaptcha, reCAPTCHA v2/v3, Cloudflare Managed Challenge)를 만났을 때 쓰는 절차. 데몬의 challenge() 프리미티브로 감지하고 자동 통과를 기다리되, 풀리지 않으면 자동 풀이를 시도하지 않고 중단·보고한 뒤 체인의 다른 출구로 전환한다."
---

# Ultra CAPTCHA handling — 감지 + 대기 + 인계

울트라 데몬의 `p.challenge()`는 ego lite의 `task.handleChallenge()`를 본뜬 **감지 + 대기 전용** 프리미티브다. 챌린지를 클릭·풀이하지 않으며, 외부 솔버 서비스도 쓰지 않는다.

## 프리미티브

`-f` 스크립트 안의 page 객체에서:

```js
const r = await p.challenge({ timeoutMs: 30000 });
// r = { detected, type, passed, waitedMs, url }
```

- `type`: `turnstile` | `hcaptcha` | `recaptcha-v2` | `recaptcha-v3` | `cloudflare-challenge` | `generic` | `null`
- `passed`: `true` = 응답 토큰 생성 / 위젯 소멸 / (인터스티셜) 통과 후 페이지 이동으로 해결됨. `false` = 대기 종료까지 미해결, 또는 챌린지 없음. `null` = recaptcha-v3 — 점수 기반이라 통과 여부를 DOM으로 알 수 없고 존재만 보고된다.
- 옵션: `timeoutMs` (기본 30000, 호출 전체의 상한), `pollMs` (기본 500), `appearMs` (기본 3000 — 위젯이 로드보다 늦게 주입되는 경우의 등장 유예), `wait: false`면 1회 탐지만 하고 즉시 반환.
- 감지 대상: Turnstile 위젯·iframe (`challenges.cloudflare.com`), hCaptcha (`hcaptcha.com` iframe·`.h-captcha`), reCAPTCHA v2/v3 (`google.com/recaptcha`·`.g-recaptcha`), Cloudflare Managed Challenge / "Just a moment" 인터스티셜, 그 외 captcha를 자칭하는 보이는 요소.

## 절차

1. 챌린지가 의심되는 페이지는 일반/lean 모드로 열고 `p.challenge()`를 호출한다. 탐지만 먼저 하려면 `{ wait: false }`.
2. `passed: true`면 작업을 그대로 계속한다 — Turnstile과 Managed Challenge는 정상 세션에서 대기 중 자동 통과되는 경우가 많다.
3. `passed: false`로 돌아오면 **그 자리에서 중단**한다. 체크박스 클릭, 이미지 풀이, 좌표 클릭 우회, 외부 솔버 사용 — 전부 금지. 같은 방식으로 재시도를 반복하지도 않는다.
4. 사용자에게 보고하고(사이트·챌린지 종류·대기 시간), 체인의 다음 출구로 전환한다: L2 클라우드 브라우저(사용자 인계 가능) 또는 H255 agent-browser(사용자 본인 Chrome 세션). 전환 판단은 browser-chain 스킬과 해당 사이트 전용 스킬을 따른다.
5. `passed: null`(recaptcha-v3)이면 챌린지가 작업을 막고 있는 게 아니다 — 원래 작업을 계속하되, 제출이 실제로 거부되면 그때 3–4로 간다.

## --fp 주의

`--fp` 엄격 모드에서는 대상 호스트만 통과하므로 챌린지 호스트(`challenges.cloudflare.com`, `hcaptcha.com`, `www.google.com/recaptcha`)가 Fetch 가로채기에 막혀 **위젯 자체가 렌더링되지 않는다**. --fp에서 챌린지 자리가 비어 보이거나 `challenge()`가 `detected: false`를 돌려줘도 "챌린지 없음"이라는 뜻이 아니다 — 감지·대기가 필요하면 lean/일반 모드로 다시 열어 확인한다.
