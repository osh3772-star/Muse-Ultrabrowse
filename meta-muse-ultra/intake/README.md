# 자격증명 인입 (intake)

비밀번호를 채팅으로 받지 않기 위한 인입 도구 묶음. 사용자는 채팅이 아닌
**비공개 구글 시트(A)** 또는 **파일 왕복(B)** 으로 비밀번호만 넣어주고,
에이전트는 그 값을 agent-vault에 저장한 뒤 원본을 그 자리에서 지운다.

## 경로 판정 (설치 때 1회)

```bash
./intake.sh setup [--spec spec.tsv]
```

- 시트 커넥터(`hatch_gws_cli sheets status`)가 `connected`면 **A(시트)**,
  아니면 **B(파일)** 로 기록된다. 판정은 시트 우선 → 파일 폴백 순서를
  바꾸지 않는다. 기록 위치: `$MUSE_ULTRA_STATE_DIR/intake.json`
  (기본 `~/.local/share/muse-ultra-browser/intake.json`, 비밀값 없음).
- `./intake.sh path`로 기록된 경로를 확인한다.

## A. 시트 경로 (가드형)

`sheet-intake.py`가 커넥터 CLI로만 동작한다:

- `setup` — 스프레드시트를 만들고(탭 이름 `in`) 헤더와 spec 행을 채운다.
  열은 `site | username | password | entry | purpose`, 비밀번호 열만 비어 있다.
- `apply` — 채워진 행만 읽어 볼트에 저장하고, 저장된 행의 비밀번호 셀만
  지운 뒤 행마다 `ok site=… cleared=yes`로 보고한다.
- 모든 하위 명령은 실행 전에 커넥터 상태를 확인한다. 미연결이면 아무것도
  바꾸지 않고 `fallback=file reason=sheets-not-connected`를 출력하고
  종료 코드 2로 끝나니, 호출자는 파일 경로로 내려가면 된다.

## B. 파일 경로

```bash
./intake.sh form  --spec spec.tsv [--out inbox.tsv] [--format tsv|csv|xlsx]
# 사용자가 비밀번호 열만 채워 파일을 돌려준다
./intake.sh apply inbox.tsv [--copy <사본 경로>]
```

- spec은 에이전트가 쓰는 비밀 없는 표다: `site | username | entry | purpose`.
  폼은 여기에 빈 비밀번호 열이 끼워진 형태이며 권한 0600으로 만들어진다.
- 형식을 못 여는 사용자가 있으면 tsv → csv → xlsx 순으로 한 번씩 다시 만든다
  (xlsx는 openpyxl 필요).
- `apply`는 채워진 행만 저장한다. 값은 `vault.py store`의 표준입력으로만
  흐르고, 어떤 출력·로그·명령행 인자에도 남지 않는다. 저장에 성공한 행은
  폼에서 즉시 값을 비우고, 전부 성공하면 반환된 폼과 `--copy`로 지정한
  사본까지 파쇄·삭제한다. 실패한 행이 있으면 폼을 남겨 재시도할 수 있게 한다.

## 보고 형식

```
ok site=<사이트> cleared=yes
fail site=<사이트> cleared=no reason=<짧은 코드>
intake stored=N pending=M failed=K cleared=yes|partial|na
```

## 값 규율

- 비밀번호는 채팅 본문으로 받지 않는다. 시트/파일/표준입력만 통로다.
- 에이전트는 값을 읽어 보여줄 수 없다 — 볼트 목록은 이름·용도·날짜만 나온다.
- 삭제는 `vault.py delete <이름>`, 교체는 `vault.py store <이름> --force`.
