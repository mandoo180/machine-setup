# 기존 nix-darwin Mac 을 이 구성으로 옮기기

`bootstrap/macos.sh` 는 깨끗한 macOS 를 전제로 한다. nix-darwin + home-manager 로 쓰던 Mac 은 OS 를 다시 깔지 않고
아래 순서로 옮길 수 있다. 핵심은 **nix 를 지우기 전에** 모든 것을 nix 밖으로 옮기는 것이다 — nix-darwin 제거기는
`/etc` 링크, `/Library/Fonts/Nix Fonts`, nix 스토어를 가리키던 dotfile 링크를 함께 없앤다.

## 0. 먼저 볼 것

- 설정 저장소(flake)의 `environment.systemPackages`, `home.packages`, `programs.*`, `fonts.packages`,
  `launchd.*`, `system.defaults`, `environment.variables`, `system.activationScripts` 를 읽고 목록을 만든다.
- nix 스토어를 가리키는 것을 찾는다.

  ```bash
  find ~ -maxdepth 3 -type l -lname '/nix/store*' 2>/dev/null        # home-manager 링크(dotfile)
  ls -la /etc/static /etc/zshrc /etc/zshenv /etc/zprofile               # nix-darwin /etc 링크
  grep -l -E '/nix/store|/run/current-system|/etc/profiles/per-user' ~/Library/LaunchAgents/*.plist
  otool -L ~/.local/bin/* 2>/dev/null | grep -B1 /nix/store             # nix 라이브러리에 링크된 바이너리
  ```

  놓치기 쉬운 것: LaunchAgent 의 `ProgramArguments`·`PATH` 에 박힌 `/nix/store/...` 경로, nix 의 bun·go 등으로
  빌드한 바이너리(nix 의 ICU 같은 dylib 에 링크됨 — Homebrew 판으로 다시 빌드), git 설정의 delta·gpg 절대 경로,
  tmux 플러그인 경로, Emacs 같은 앱이 빌드 때 구워 넣은 PATH, venv 의 `home =`(nix python 기반이면 다시 만든다).
- 지울 것을 백업해 둔다: `cp -L` 로 dotfile 실내용, `/etc` 의 `zshrc`·`zprofile`·`zshenv`·`bashrc`·`*.before-nix-darwin`·`*.backup-before-nix`, `~/Library/LaunchAgents/*.plist`.

## 1. 이 구성 적용(전환) — nix 가 살아 있는 동안

```bash
brew install chezmoi
git clone https://github.com/mandoo180/machine-setup.git ~/Projects/machine-setup   # 이미 있으면 생략
ln -s ~/Projects/machine-setup ~/.local/share/chezmoi                               # rebuild 가 이 클론을 pull
chezmoi init --promptString email=<git 메일>
chezmoi diff                                    # 백업과 비교 — 잃는 줄이 없는지
HOMEBREW_BUNDLE_NO_UPGRADE=1 chezmoi apply      # 이미 깔린 formula 를 이 김에 올리지 않는다
```

- `~/.zshenv`·`~/.zshrc` 등 home-manager 링크는 `chezmoi apply` 가 실파일로 바꾼다. 이 저장소가 다루지 않는 링크
  (예: tmux 설정 — 이관 대상 아님)는 `cp -L` 로 같은 내용의 실파일을 만든다.
- 공개 저장소에 둘 수 없는 값(회사 주소, 업무용 별칭, 머신 전용 PATH)은 `~/.zshenv.local`(모든 zsh)과
  `~/.zshrc.local`(대화형)에 둔다. 둘 다 저장소 밖이고 있을 때만 읽힌다.
- PATH 는 `~/.config/zsh/path.zsh` 한 곳이다. `~/.zshenv` 와 `~/.zprofile` 이 함께 읽는다 — nix-darwin 을 지우면
  macOS 기본 `/etc/zprofile` 의 `path_helper` 가 로그인 셸에서 `/usr/bin` 을 Homebrew 앞으로 당기기 때문이다.
- 손으로 깐 글꼴 파일이 cask 와 같은 이름이면 20-fonts 의 `brew install --cask` 가 실패한다. 그 파일을 옮긴 뒤 다시 적용한다.
- Docker Desktop 이 있으면 40-services 는 colima 를 띄우지 않는다(띄우면 docker context 가 바뀐다). `docker` formula(CLI)는
  Docker Desktop cask 의 셸 자동완성 링크만 덮어쓴다 — 되돌리려면 `brew unlink --formula docker && brew link --cask docker-desktop`.
- 큰 bottle(llvm·openjdk 등) 다운로드가 끊기면 10-packages 가 실패하고 dotfile 은 쓰이지 않는다. `HOMEBREW_CURL_RETRIES=10` 으로 다시 적용한다.
- LaunchAgent 는 실행 파일·PATH 를 Homebrew 의 `opt` 경로(`/opt/homebrew/opt/<formula>/bin/...`)로 고친다.
  Cellar 경로(`/opt/homebrew/Cellar/<formula>/<판>/...`)는 `brew upgrade` 뒤 사라진다. 고친 뒤
  `launchctl bootout gui/$UID <plist>; launchctl bootstrap gui/$UID <plist>; launchctl kickstart -k gui/$UID/<label>`.
- 새 로그인 셸(`zsh -l`)·비대화형 셸(`zsh -c 'command -v node python3 git'`)·각 LaunchAgent 에서 nix 경로가
  안 나오는지 본다. 이미 떠 있는 프로세스는 옛 환경을 물려받고 있으니 재부팅 전까지는 새로 띄운 것만 믿는다.

## 2. nix 제거 — 1 이 끝나고 확인한 뒤(sudo)

```bash
sudo /run/current-system/sw/bin/darwin-uninstaller   # nix-darwin. 시스템 프로필에 들어 있어 네트워크가 필요 없다
```

nix-darwin 제거기는 `org.nixos.*` 서비스, `/etc/static` 링크, `/Library/Fonts/Nix Fonts` 를 지우고
`/etc/*.before-nix-darwin` 을 원래 이름으로 되돌린다. `/etc/pam.d/sudo_local` 링크도 사라지므로 Touch ID sudo 를 다시 켠다.

```bash
sed 's/^#auth/auth/' /etc/pam.d/sudo_local.template | sudo tee /etc/pam.d/sudo_local >/dev/null
```

그다음 nix 본체(공식 멀티유저 설치기로 깐 경우 — Determinate Systems 설치기면 `/nix/nix-installer uninstall`).
절차는 [Nix 매뉴얼의 macOS 제거](https://nix.dev/manual/nix/latest/installation/uninstall#macos)를 따른다.

```bash
grep -n -i nix /etc/zshrc /etc/bashrc /etc/zprofile    # 남은 nix 줄이 없어야
sudo rm -f /etc/zshrc.backup-before-nix /etc/bashrc.backup-before-nix   # 위에서 macOS 기본판이 이미 돌아왔으면 지우기만
sudo rm -f /etc/bash.bashrc                             # nix 설치기가 만든 파일이면(macOS 기본에는 없음)
sudo launchctl bootout system /Library/LaunchDaemons/org.nixos.nix-daemon.plist
sudo rm /Library/LaunchDaemons/org.nixos.nix-daemon.plist
sudo launchctl bootout system /Library/LaunchDaemons/org.nixos.darwin-store.plist
sudo rm /Library/LaunchDaemons/org.nixos.darwin-store.plist
sudo dscl . -delete /Groups/nixbld
for u in $(dscl . -list /Users | grep '^_nixbld'); do sudo dscl . -delete /Users/"$u"; done
sudo vifs                                               # /nix 줄 삭제
sudo sed -i '' -E '/^nix$/d; /^run[[:space:]]/d' /etc/synthetic.conf
sudo rm -rf /etc/nix /var/root/.nix-profile /var/root/.nix-defexpr /var/root/.nix-channels
sudo diskutil apfs deleteVolume /nix
rm -rf ~/.nix-profile ~/.nix-defexpr ~/.nix-channels ~/.local/state/nix ~/.local/state/home-manager
```

재부팅한다 — `/run` 링크와 `/nix` 마운트 지점이 사라지고, 옛 PATH 를 물려받은 프로세스가 정리된다.

## 3. 되돌리기

- 1 단계 도중: 백업한 dotfile·plist 를 되돌리고 `sudo darwin-rebuild switch --flake <flake>` 를 다시 돌리면 home-manager
  링크가 돌아온다(그 사이 실파일은 home-manager 의 `backupFileExtension` 으로 옮겨진다).
- 2 단계 뒤: nix 공식 설치기 → `sudo nix run nix-darwin -- switch --flake <flake>`. 설정 저장소는 지우지 않고 보관한다.
