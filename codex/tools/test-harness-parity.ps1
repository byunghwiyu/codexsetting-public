param([string]$CodexHome = "$HOME\.codex")

$ErrorActionPreference = "Stop"
$powerShellExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$validator = Join-Path $CodexHome "tools\validate-harness-parity.ps1"
$policy = Join-Path $CodexHome "harness-policy.json"

& $validator -PolicyPath $policy
if ($LASTEXITCODE -ne 0) { throw "현재 글로벌 하네스의 필수 capability 검증 실패" }

# OS 공통 임시 경로와 고유 이름으로 기존 파일 및 동시 검사와의 충돌을 피한다.
$fixtureId = [guid]::NewGuid().ToString('N')
$fixtureFile = Join-Path ([System.IO.Path]::GetTempPath()) "harness-parity-$fixtureId.md"
$fixturePolicy = Join-Path ([System.IO.Path]::GetTempPath()) "harness-parity-$fixtureId.json"
try {
    [System.IO.File]::WriteAllText($fixtureFile, "marker 없음")
    $fixture = @{
        schemaVersion = 2
        capabilities = @(@{
            id = "required-marker"
            status = "required"
            implementations = @{
                Codex = @(@{ path = $fixtureFile; allOf = @("필수 표식") })
                Claude = @(@{ path = $fixtureFile; allOf = @("필수 표식") })
            }
        })
        conflictRules = @()
    } | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($fixturePolicy, $fixture, [System.Text.UTF8Encoding]::new($false))
    & $powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $validator -PolicyPath $fixturePolicy *> $null
    if ($LASTEXITCODE -ne 1) { throw "필수 기능 누락 fixture가 실패하지 않았습니다." }
}
finally {
    Remove-Item -LiteralPath $fixtureFile, $fixturePolicy -Force -ErrorAction SilentlyContinue
}

Write-Output "PASS: 현재 필수 capability 및 누락 감지 fixture"
