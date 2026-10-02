# 임시 저장소·홈만 사용하며 산출물은 진단용으로 보존한다.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('public-windows-install-' + [guid]::NewGuid().ToString('N'))
$fixtureRepo = Join-Path $fixture 'repo'
$testHome = Join-Path $fixture 'home 한글 & $literal'
New-Item -ItemType Directory -Path $fixtureRepo, $testHome -Force | Out-Null
foreach ($name in @('AGENTS.md', 'codex', 'settings', 'scripts')) {
    Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $fixtureRepo -Recurse
}
$installer = Join-Path $fixtureRepo 'scripts/install-windows.ps1'
$executable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
function Invoke-Installer([string]$Target, [bool]$Preview = $false, [int]$Expected = 0) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installer, '-HomeDirectory', $Target)
    if ($Preview) { $arguments += '-DryRun' }
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $result = & $executable @arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prior
    if ($code -ne $Expected) { throw "설치 종료 코드: expected=$Expected actual=$code $result" }
}
function Snapshot([string]$Root) {
    return ((Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length)
        if ($_.PSIsContainer) { "D:$relative" } else { "F:$relative=$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
    }) -join "`n")
}
function Assert-Text([string]$Path, [string]$Expected) {
    if ([System.IO.File]::ReadAllText($Path) -ne $Expected) { throw "파일 내용 불일치: $Path" }
}

$originalCodexHome = $env:CODEX_HOME
try {
    $env:CODEX_HOME = $null
    $before = Snapshot $testHome
    Invoke-Installer $testHome $true
    if ($before -ne (Snapshot $testHome)) { throw 'dry-run이 홈을 변경했습니다.' }
    Invoke-Installer $testHome
    if (-not (Test-Path -LiteralPath (Join-Path $testHome '.codex/config.toml'))) { throw '신규 설정 누락' }
    $before = Snapshot $testHome
    Invoke-Installer $testHome
    if ($before -ne (Snapshot $testHome)) { throw '재설치가 파일·백업을 변경했습니다.' }
    Write-Output 'PASS: 신규 설치·dry-run·멱등성'

    $config = Join-Path $testHome '.codex/config.toml'
    $hooks = Join-Path $testHome '.codex/hooks.json'
    $guide = Join-Path $testHome '.codex/AGENTS.md'
    [System.IO.File]::WriteAllText($config, 'personal-config')
    [System.IO.File]::WriteAllText($hooks, 'personal-hooks')
    [System.IO.File]::WriteAllText($guide, 'old-guide')
    $privatePath = Join-Path $testHome '.codex/auth.json'
    [System.IO.File]::WriteAllText($privatePath, 'private-fixture')
    $before = Snapshot $testHome
    Invoke-Installer $testHome $true
    if ($before -ne (Snapshot $testHome)) { throw '기존 홈 dry-run 변경' }
    Invoke-Installer $testHome
    Assert-Text $config 'personal-config'
    Assert-Text $hooks 'personal-hooks'
    Assert-Text $privatePath 'private-fixture'
    $backups = @(Get-ChildItem -LiteralPath $testHome -Directory -Filter 'codex-dotfiles-backup.*')
    if ($backups.Count -ne 1) { throw '백업 개수 불일치' }
    $saved = Join-Path $backups[0].FullName '.codex/AGENTS.md'
    Assert-Text $saved 'old-guide'
    if (Test-Path -LiteralPath (Join-Path $backups[0].FullName '.codex/auth.json')) { throw '인증 파일이 백업에 포함됐습니다.' }
    $before = Snapshot $testHome
    Invoke-Installer $testHome
    if ($before -ne (Snapshot $testHome)) { throw '기존 설정 재설치 비멱등' }
    Copy-Item -LiteralPath $saved -Destination $guide -Force
    Assert-Text $guide 'old-guide'
    Write-Output 'PASS: 개인 설정·인증 보존, 백업 분리·복구'

    # 뒤쪽 경로의 충돌도 설치 전 검사하므로 앞쪽 파일이 바뀌면 안 된다.
    $collisionHome = Join-Path $fixture 'collision'
    New-Item -ItemType Directory -Path (Join-Path $collisionHome '.codex/tools/scan-content-policy.ps1') -Force | Out-Null
    $before = Snapshot $collisionHome
    Invoke-Installer $collisionHome $false 1
    if ($before -ne (Snapshot $collisionHome)) { throw '충돌 이전에 부분 설치됐습니다.' }
    $env:CODEX_HOME = Join-Path $fixture 'custom-home'
    $before = Snapshot $testHome
    Invoke-Installer $testHome $false 1
    if ($before -ne (Snapshot $testHome)) { throw '사용자 지정 홈 오류 시 변경' }
    $env:CODEX_HOME = $null
    Write-Output 'PASS: 유형 충돌 사전 차단·사용자 지정 홈 오설치 방지'

    $linkHome = Join-Path $fixture 'link-home'
    $external = Join-Path $fixture 'external'
    New-Item -ItemType Directory -Path $linkHome, $external -Force | Out-Null
    New-Item -ItemType Junction -Path (Join-Path $linkHome '.codex') -Target $external | Out-Null
    Invoke-Installer $linkHome $false 1
    if (@(Get-ChildItem -LiteralPath $external -Force).Count -ne 0) { throw '정션 외부 경로 변경' }
    Write-Output 'PASS: 정션 대상 거부'
}
finally { $env:CODEX_HOME = $originalCodexHome }
Write-Output "검사 산출물: $fixture"
