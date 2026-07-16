# Windows 11 부트스트랩 — PowerShell(관리자 아님)에서 실행:
#   Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap\windows.ps1
# WSL Ubuntu까지 설치하려면: .\bootstrap\windows.ps1 -InstallWSL
param([switch]$InstallWSL)
$ErrorActionPreference = 'Stop'

$repo = if ($env:MACHINE_SETUP_REPO) { $env:MACHINE_SETUP_REPO } else { 'https://github.com/mandoo180/machine-setup.git' }

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "winget이 없습니다. Microsoft Store에서 '앱 설치 관리자'를 업데이트하십시오."
}

Write-Host ">> [bootstrap] 최소 의존성 (git, chezmoi, PowerShell 7)"
foreach ($id in @('Git.Git', 'twpayne.chezmoi', 'Microsoft.PowerShell')) {
  winget list --id $id --exact --accept-source-agreements 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
  }
}

# PATH 갱신 (이 세션에서 chezmoi/git을 바로 쓰기 위함)
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

Write-Host ">> [bootstrap] chezmoi init --apply ($repo)"
chezmoi init --apply $repo

if ($InstallWSL) {
  Write-Host ">> [bootstrap] WSL Ubuntu 설치 (재부팅 필요할 수 있음)"
  wsl --install -d Ubuntu
  Write-Host ">> WSL 진입 후: bash <(curl -fsSL https://raw.githubusercontent.com/mandoo180/machine-setup/main/bootstrap/ubuntu.sh)"
}

Write-Host ">> [bootstrap] 완료. 새 터미널(pwsh 7)을 여십시오."
