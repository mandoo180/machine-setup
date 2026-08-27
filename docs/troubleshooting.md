# 트러블슈팅

부트스트랩 자체와 무관하게 머신 운용 중 겪은 문제와 복구 절차를 기록한다.

## WSL: GUI 앱 창이 안 뜬다 (작업표시줄 아이콘만 보임)

**증상** — WSL에서 GUI 앱을 실행하면 Windows 작업표시줄에 아이콘은 뜨는데 창이 화면에 나타나지 않는다.
프로세스는 정상 실행 중이고 앱 로그에도 오류가 없다. 창이 있어야 할 자리에는 뒤에 있던 창이 그대로 비친다.

**원인** — WSLg의 weston이 기동 시 Windows 공유 메모리 섹션 확보에 실패하면 그래픽 리디렉션(gfxredir)을 끄고
copy mode로 폴백한다. 이 상태에서 RAIL 창은 Windows 쪽에 layered window로 생성되지만 픽셀이 전달되지 않아,
Win32 API 상으로는 `IsWindowVisible=True` + 정상 좌표이면서 화면에는 아무것도 그려지지 않는다.
작업표시줄 아이콘은 픽셀과 별개인 app list 채널로 등록되므로 정상적으로 뜬다.

**판별** — 로그 한 줄로 끝난다.

```bash
grep -E "use_gfxredir|rdp_allocate_shared_memory" /mnt/wslg/weston.log
```

```
# 고장
rdp_allocate_shared_memory: Failed to open "/mnt/shared_memory/{...}" with error: Input/output error
RDP backend: use_gfxredir = 0

# 정상 (실패 라인 없음)
RDP backend: use_gfxredir = 1
```

WSLg가 창 제목에 직접 경고를 붙이기도 한다 (`enable_copy_warning_title = 1`이 기본값):

```
[WARN:COPY MODE] <원래 제목> (Ubuntu-24.04)
```

**해결** — weston만 재시작한다. VM·docker·현재 세션 전부 유지된다.

```bash
wsl.exe --system -e pkill -x weston
```

weston은 사용자 배포판이 아니라 **WSLg 시스템 배포판**에서 돌기 때문에 `wsl --system`으로 들어가야 한다.
그 안의 감독 프로세스 WSLGd가 2초 안에 weston을 되살리고, 그 시점엔 공유 메모리 마운트가 이미 준비돼
있으므로 `use_gfxredir = 1`로 올라온다. 확인:

```bash
grep -oE 'use_gfxredir = [01]' /mnt/wslg/weston.log | tail -1
```

재시작 이력이 쌓이면 `use_gfxredir` 줄이 여러 개가 되므로 **반드시 마지막 줄**을 봐야 한다. 첫 줄만 보면
이미 복구된 뒤에도 계속 고장으로 읽는다.

RDP 세션이 끊기므로 **열려 있던 GUI 창은 함께 닫힌다.** GUI 앱을 띄우기 전에 실행한다.

`wsl --shutdown` 후 재진입도 듣지만 결국 "weston을 나중에 다시 띄운다"의 비싼 버전이다 — VM을 내리므로
docker 컨테이너와 WSL 안의 모든 세션이 함께 끊긴다. weston 재시작이 듣지 않을 때만 쓰고, 그래도 반복되면
`wsl --update`.

**재발한다** — 기동 시점의 경합이라 부팅마다 다시 걸릴 수 있다. 관측 3회:

| 커널 부팅(`uptime -s`) | weston 기동 | 간격 | 결과 |
|---|---|---|---|
| 2026-08-25 09:03:02 | 09:08:11 | +5m09s | `use_gfxredir = 0` |
| 2026-08-25 10:13:46 | 10:13:54 | **+8s** | `= 1` |
| 2026-08-27 08:44:46 | 08:53:31 | +8m45s | `= 0` |

VM 커널이 먼저 떠 있고 배포판(`/sbin/init`)이 몇 분 뒤 시작될 때 실패했다. 공유 메모리 마운트가 준비되기
전에 weston이 RDP 백엔드를 초기화해 버리는 경합으로 보이지만 n=3 상관이라 확정은 아니다. 근거는, 고장
상태에서 시스템 배포판에 들어가 보면 마운트가 이미 정상이라는 점이다 — 그래서 재시작만으로 복구된다.

```bash
wsl.exe --system -e ls -ld /mnt/shared_memory
```

**자동 감지** — WSL 컨텍스트의 `.zshrc`가 로그인 시 1회 상태를 확인해 `use_gfxredir = 0`이면 경고한다.
`wslg-status`(현재 상태), `wslg-fix`(위 재시작) 함수도 같이 들어 있다. 자동 복구는 하지 않는다 —
열려 있는 GUI 창을 말없이 닫아 버리기 때문이다.

**오진 방지** — 특정 앱의 버그가 아니다. WSLg를 쓰는 모든 GUI 앱이 동시에 영향을 받으며 X11/Wayland,
GPU 가속 사용 여부와 무관하다(OpenGL을 전혀 쓰지 않는 `xeyes`도 똑같이 투명하게 나온다).
**한 앱만 안 뜨는 상황이면 원인이 다르다.** 같은 공유 메모리 경로를 쓰는 PulseAudio RDP sink도 함께 죽으므로,
`/mnt/wslg/pulseaudio.log`에 `[rdp-sink] module-rdp-sink.c: Connected failed`가 같이 찍혀 있으면 이 건이 맞다.

**폴백으로 `wsl --shutdown`을 쓸 때** — VM을 내리므로 docker 컨테이너가 함께 정지하고 WSL 안의 세션도 모두 끊긴다.
컨테이너에 `restart: unless-stopped`(또는 `always`)가 걸려 있고 `systemctl is-enabled docker`가 `enabled`면
재진입 시 자동 복구되므로, 사전에 두 가지만 확인하면 손실 없이 재시작할 수 있다.

```bash
docker inspect <name> --format '{{.HostConfig.RestartPolicy.Name}}'
systemctl is-enabled docker
```

## WSL: GUI 앱이 Windows에 설치된 폰트를 못 찾는다

**증상** — WSLg로 띄운 GUI 앱에 지정한 폰트가 적용되지 않는다. Windows에는 분명히 설치돼 있고
Windows 네이티브 앱에서는 잘 보이는 폰트다. Emacs처럼 후보 목록에서 첫 설치본을 고르는 설정이라면
조용히 맨 끝 fallback(DejaVu Sans Mono 등)으로 떨어지므로 오류 한 줄 없이 "그냥 못생기게" 뜬다.
한글은 더 나빠서, 후보가 전멸하면 fontset 항목 자체가 등록되지 않아 Unifont-JP 비트맵으로 렌더된다.

**원인** — WSL은 Windows 폰트를 fontconfig에 공유하지 않는다. 검색 경로는 `~/.fonts`,
`~/.local/share/fonts`, `/usr/local/share/fonts`, `/usr/share/fonts`뿐이고 `/mnt/c/...`는 포함되지 않는다.
Windows에서 설치한 폰트는 대개 시스템이 아니라 **사용자 폰트 디렉터리**
(`/mnt/c/Users/<user>/AppData/Local/Microsoft/Windows/Fonts`)에 들어가므로 리눅스 쪽에서는 전혀 보이지 않는다.

이 저장소가 오랫동안 WSL에서 폰트 설치를 건너뛴 것도 같은 전제 때문이었다 — "WSL엔 GUI가 없으니
폰트도 불필요, 터미널은 Windows측이 렌더링". WSLg로 GUI 앱을 직접 띄우는 순간 그 전제가 깨진다.

**판별** — 리눅스 쪽 fontconfig에 폰트가 있는지만 보면 된다. `fc-list`가 없다면 그 자체가 증상이다
(`fontconfig` 패키지는 GUI 의존성으로 딸려오는데 WSL엔 GUI 패키지가 없다).

```bash
/usr/bin/fc-list : family | tr ',' '\n' | sort -u | grep -i '<폰트명>'
```

Emacs라면 GUI 프레임에서 직접 물어보는 편이 확실하다.

```elisp
(find-font (font-spec :family "D2CodingLigature Nerd Font"))  ; nil이면 없는 것
(face-attribute 'default :family)                             ; 실제로 적용된 것
(car (internal-char-font nil ?한))                             ; 한글이 어느 폰트로 그려지는지
```

`PATH`에 linuxbrew가 있으면 `fc-list`/`fc-match`가 brew 쪽(별도 설정·캐시)으로 잡히므로
**반드시 `/usr/bin/fc-list`를 절대경로로** 부른다. GUI 앱이 링크하는 것은 시스템 `libfontconfig`이다.

```bash
ldd $(command -v emacs) | grep fontconfig   # /lib/x86_64-linux-gnu/libfontconfig.so.1
```

**해결** — `rebuild`. 이제 WSL에도 시스템 폰트(`apt.fonts`)와 Nerd Font(`20-fonts-ubuntu`)가
설치된다. `packages.yaml`의 `nerd_zips`에 이미 D2Coding·Iosevka·IosevkaTerm·IosevkaTermSlab·
Terminus가 들어 있으므로 별도 추가 없이 채워진다.

`/mnt/c`의 Windows 폰트 디렉터리를 `~/.config/fontconfig/fonts.conf`에 `<dir>`로 얹는 방법도
동작하기는 한다. 쓰지 않는다 — drvfs I/O라 수백 개 스캔이 느리고 앱 시작·폰트 조회가 눈에 띄게 밀린다.
같은 이유로 Windows 사용자 폰트 디렉터리 전체 복사도 피한다(Iosevka Nerd Font 전 웨이트만 2.6G).

**오진 방지** — 빌드나 앱 설정 문제로 보기 쉽지만 fontconfig 계층의 문제다. 같은 설정이 Windows
네이티브 앱에서 잘 되는 것은 반증이 아니라 오히려 증상 그대로다(그쪽은 Windows 폰트 목록을 본다).
GUI 앱 여러 개가 동시에 같은 폰트를 놓치는지 확인하면 앱 버그와 구분된다.

**남는 것** — 한자(漢)는 D2Coding 계열이 상용한자를 다 덮지 않아 여전히 폴백이 걸릴 수 있다.
`apt.fonts`의 `fonts-noto-cjk`가 설치되면 fontconfig 폴백으로 메워진다.
