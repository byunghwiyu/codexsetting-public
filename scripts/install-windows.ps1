param(
    [string]$HomeDirectory = $env:USERPROFILE,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($HomeDirectory)) { throw '절대 홈 경로가 필요합니다.' }
$targetHome = [System.IO.Path]::GetFullPath($HomeDirectory).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $targetHome -PathType Container)) { throw '존재하는 홈 디렉터리가 필요합니다.' }
$codexDirectory = Join-Path $targetHome '.codex'
if ($env:CODEX_HOME -and [System.IO.Path]::GetFullPath($env:CODEX_HOME).TrimEnd('\', '/') -ne $codexDirectory) {
    throw '사용자 지정 CODEX_HOME은 지원하지 않습니다. 기본 홈 설치인지 확인하세요.'
}

function Assert-PlainPath([string]$Path) {
    $entry = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -ne $entry -and ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "링크 또는 정션은 먼저 별도 이관하세요: $Path"
    }
}

# 쓰기 전에 전체 파일의 유형·링크를 검사해 충돌로 인한 부분 설치를 막는다.
$plan = [System.Collections.Generic.List[object]]::new()
function Add-Tree([string]$Source, [string]$Destination, [string]$Relative, [bool]$Preserve = $false) {
    Assert-PlainPath $Source
    Assert-PlainPath $Destination
    $item = Get-Item -LiteralPath $Source -Force
    if ($item.PSIsContainer) {
        if ((Test-Path -LiteralPath $Destination) -and -not (Test-Path -LiteralPath $Destination -PathType Container)) {
            throw "디렉터리 대상에 파일이 있습니다: $Destination"
        }
        foreach ($child in Get-ChildItem -LiteralPath $Source -Force | Sort-Object Name) {
            Add-Tree $child.FullName (Join-Path $Destination $child.Name) (Join-Path $Relative $child.Name)
        }
    }
    else {
        if ((Test-Path -LiteralPath $Destination) -and -not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
            throw "파일 대상에 다른 유형이 있습니다: $Destination"
        }
        $plan.Add([pscustomobject]@{ Source = $Source; Destination = $Destination; Relative = $Relative; Preserve = $Preserve })
    }
}

Assert-PlainPath $targetHome
Assert-PlainPath $repo
Assert-PlainPath (Join-Path $repo 'codex')
Assert-PlainPath (Join-Path $repo 'settings')
Assert-PlainPath $codexDirectory
if ((Test-Path -LiteralPath $codexDirectory) -and -not (Test-Path -LiteralPath $codexDirectory -PathType Container)) {
    throw 'Codex 설치 경로가 디렉터리가 아닙니다.'
}
Add-Tree (Join-Path $repo 'AGENTS.md') (Join-Path $codexDirectory 'AGENTS.md') '.codex/AGENTS.md'
foreach ($name in @('deny-patterns.yaml', 'harness-policy.json', 'safety-policy.json', 'hooks', 'rules', 'tools')) {
    Add-Tree (Join-Path $repo "codex/$name") (Join-Path $codexDirectory $name) ".codex/$name"
}
Add-Tree (Join-Path $repo 'codex/hooks.json') (Join-Path $codexDirectory 'hooks.json') '.codex/hooks.json' $true
Add-Tree (Join-Path $repo 'settings/config.windows.toml') (Join-Path $codexDirectory 'config.toml') '.codex/config.toml' $true

$backupRoot = $null
$changed = 0
foreach ($entry in $plan) {
    $exists = Test-Path -LiteralPath $entry.Destination -PathType Leaf
    if ($exists -and $entry.Preserve) {
        Write-Output "보존: $($entry.Destination) (설정 예시와 별도 비교·병합 필요)"
        continue
    }
    if ($exists -and (Get-FileHash -LiteralPath $entry.Source).Hash -eq (Get-FileHash -LiteralPath $entry.Destination).Hash) { continue }
    $changed++
    Write-Output "갱신: $($entry.Destination)"
    if ($DryRun) { continue }
    if ($exists) {
        if ($null -eq $backupRoot) {
            $backupRoot = Join-Path $targetHome ('codex-dotfiles-backup.' + [guid]::NewGuid().ToString('N'))
            Write-Output "백업: $backupRoot"
        }
        $backupPath = Join-Path $backupRoot $entry.Relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
        Copy-Item -LiteralPath $entry.Destination -Destination $backupPath
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $entry.Destination) -Force | Out-Null
    Copy-Item -LiteralPath $entry.Source -Destination $entry.Destination -Force
}
Write-Output "완료: 변경 대상 $changed 파일, dry-run=$DryRun"
