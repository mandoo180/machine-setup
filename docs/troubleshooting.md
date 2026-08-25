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

**해결** — Windows PowerShell에서 `wsl --shutdown` 후 재진입.

기동 시점의 일회성 오류이고 weston은 재시도하지 않으므로, 그 프로세스가 살아 있는 한 copy mode가 유지된다.
weston은 사용자 배포판이 아니라 **WSLg 시스템 배포판**에서 돌기 때문에 `wsl -t <distro>`(배포판만 종료)로는
재기동되지 않는다 — VM 전체를 내려야 한다. 재진입 후 `use_gfxredir = 1`이면 복구된 것이다.
반복되면 `wsl --update`.

**오진 방지** — 특정 앱의 버그가 아니다. WSLg를 쓰는 모든 GUI 앱이 동시에 영향을 받으며 X11/Wayland,
GPU 가속 사용 여부와 무관하다(OpenGL을 전혀 쓰지 않는 `xeyes`도 똑같이 투명하게 나온다).
**한 앱만 안 뜨는 상황이면 원인이 다르다.** 같은 공유 메모리 경로를 쓰는 PulseAudio RDP sink도 함께 죽으므로,
`/mnt/wslg/pulseaudio.log`에 `[rdp-sink] module-rdp-sink.c: Connected failed`가 같이 찍혀 있으면 이 건이 맞다.

**부수 효과** — `wsl --shutdown`은 VM을 내리므로 docker 컨테이너가 함께 정지하고 WSL 안의 세션도 모두 끊긴다.
컨테이너에 `restart: unless-stopped`(또는 `always`)가 걸려 있고 `systemctl is-enabled docker`가 `enabled`면
재진입 시 자동 복구되므로, 사전에 두 가지만 확인하면 손실 없이 재시작할 수 있다.

```bash
docker inspect <name> --format '{{.HostConfig.RestartPolicy.Name}}'
systemctl is-enabled docker
```
