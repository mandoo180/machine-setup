# machine-setup

새 머신 초기 세팅 (macOS / Ubuntu desktop / Ubuntu WSL / Windows 11).
`~/Projects/nix` (nix flake)를 대체하는 native 구성 — chezmoi + brew/apt/winget.

## 부트스트랩 (새 머신에서 1회)

```bash
# macOS
bash <(curl -fsSL https://raw.githubusercontent.com/mandoo180/machine-setup/main/bootstrap/macos.sh)

# Ubuntu (desktop / WSL 자동 감지)
bash <(curl -fsSL https://raw.githubusercontent.com/mandoo180/machine-setup/main/bootstrap/ubuntu.sh)
```

```powershell
# Windows 11 (PowerShell)
Set-ExecutionPolicy -Scope Process Bypass -Force
git clone https://github.com/mandoo180/machine-setup.git; .\machine-setup\bootstrap\windows.ps1
# WSL까지: .\machine-setup\bootstrap\windows.ps1 -InstallWSL
```

최초 실행 시 git email을 묻는다 (개인 mandoo180@gmail.com / 회사 kyeongsoo@douzone.com).

## 일상 워크플로우

```bash
rebuild   # 저장소 pull + 적용 (패키지 목록 변경분 설치 포함)
update    # 패키지 업그레이드(brew/apt/winget) + rebuild
```

패키지 추가·삭제: `home/.chezmoidata/packages.yaml` 수정 → commit/push → 각 머신에서 `rebuild`.

## 구조

- `bootstrap/` — OS별 진입점 (최소 의존성 + chezmoi init --apply)
- `home/` — chezmoi source (dotfiles + `.chezmoiscripts`)
- `home/.chezmoidata/packages.yaml` — 패키지 목록 단일 소스
- 실행 순서: 10-packages(before) → dotfiles → 20-fonts → 25-omz → 30-os → 40-services → 50-input-method

## 수동 검증 체크리스트 (부트스트랩 후)

- [ ] `exec zsh` → oh-my-zsh lambda 프롬프트
- [ ] 터미널에서 Nerd Font 아이콘 렌더링 (`echo " "`)
- [ ] `git log`에서 delta 페이저 동작, `git config user.email` 확인
- [ ] `docker run hello-world` (WSL: `wsl --shutdown` 후 재진입 + `rebuild` 필요할 수 있음)
- [ ] 한글 입력: desktop = Super+Space(ibus), WSL = fcitx5-configtool에서 Hangul 엔진 추가 후 GUI 앱 확인
- [ ] desktop: `sudo tailscale up --ssh` (최초 1회), **원격 SSH 쓸 거면 `~/.ssh/authorized_keys` 먼저 배치** (패스워드 인증 꺼져 있음)
- [ ] Windows: 새 pwsh 7 창에서 Ctrl+r(PSFzf), `z <dir>`(zoxide)

## 주의사항

- Nerd Fonts 버전 업그레이드: `packages.yaml`의 `nerd_version` 수정 후, 각 머신에서 `rm -rf ~/.local/share/fonts/<이름>` 후 `rebuild` (다운로드 마커가 디렉터리라서)
- deb 직배포 앱(obsidian/slack/discord)은 `update`로 업그레이드되지 않음 — 앱 내 업데이트 또는 재설치
- 기존 nix 머신에는 적용하지 않는다 (깨끗한 OS 전제 — 스펙 §2)

## 테스트

```bash
bash tests/lint.sh          # shellcheck (+--ps: PSScriptAnalyzer)
bash tests/smoke-ubuntu.sh  # Docker 컨테이너 e2e (desktop/WSL 양쪽 컨텍스트)
```
