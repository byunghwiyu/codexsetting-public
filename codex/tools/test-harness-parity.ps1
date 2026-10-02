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

    # 검증 목록 자체의 유효성: 정상 최소 manifest는 통과하고, 비어 있거나 판정 기준이 빠진 manifest는 실패해야 한다.
    [System.IO.File]::WriteAllText($fixtureFile, "필수 표식")
    $markerRule = @{ path = $fixtureFile; allOf = @("필수 표식") }
    $manifestCases = @(
        @{ Name = "정상 최소 manifest"; Expected = 0; Capabilities = @(@{ id = "marker"; status = "required"; implementations = @{ Codex = @($markerRule); Claude = @($markerRule) } }); Conflicts = @() },
        @{ Name = "빈 capabilities"; Expected = 1; Capabilities = @(); Conflicts = @() },
        @{ Name = "status 없는 capability"; Expected = 1; Capabilities = @(@{ id = "marker"; implementations = @{ Codex = @($markerRule); Claude = @($markerRule) } }); Conflicts = @() },
        @{ Name = "checks 없는 충돌 규칙"; Expected = 1; Capabilities = @(@{ id = "marker"; status = "required"; implementations = @{ Codex = @($markerRule); Claude = @($markerRule) } }); Conflicts = @(@{ id = "empty"; status = "required"; checks = @() }) }
    )
    foreach ($manifestCase in $manifestCases) {
        $manifest = @{ schemaVersion = 2; capabilities = $manifestCase.Capabilities; conflictRules = $manifestCase.Conflicts } | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($fixturePolicy, $manifest, [System.Text.UTF8Encoding]::new($false))
        & $powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $validator -PolicyPath $fixturePolicy *> $null
        if ($LASTEXITCODE -ne $manifestCase.Expected) { throw "manifest 검증 결과 불일치: $($manifestCase.Name) expected=$($manifestCase.Expected) actual=$LASTEXITCODE" }
    }

    # 하네스 동기화: 두 번째 대상이 없으면 첫 대상도 변경하지 않고 실패해야 한다.
    $syncTool = Join-Path $CodexHome "tools\sync-harness-rules.ps1"
    $syncFirst = Join-Path ([System.IO.Path]::GetTempPath()) "harness-parity-$fixtureId-first.md"
    $syncPolicy = Join-Path ([System.IO.Path]::GetTempPath()) "harness-parity-$fixtureId-sync.json"
    [System.IO.File]::WriteAllText($syncFirst, "original")
    $syncManifest = @{
        schemaVersion = 2
        common = @{ phaseMaxFiles = 5; rubricAxes = @("검증") }
        targets = @(
            @{ name = "First"; path = $syncFirst; overrides = @() },
            @{ name = "Missing"; path = (Join-Path ([System.IO.Path]::GetTempPath()) "harness-parity-$fixtureId-missing\rules.md"); overrides = @() }
        )
    } | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($syncPolicy, $syncManifest, [System.Text.UTF8Encoding]::new($false))
    # 기대한 실패의 stderr가 Windows PowerShell에서 종료 오류로 바뀌지 않도록 이 호출만 Continue로 실행한다.
    $ErrorActionPreference = "Continue"
    & $powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $syncTool -Source $syncPolicy -Write *> $null
    $syncExitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($syncExitCode -eq 0) { throw "하네스 동기화가 누락 대상을 거부하지 않았습니다." }
    if ([System.IO.File]::ReadAllText($syncFirst) -ne "original") { throw "하네스 동기화가 실패 전에 첫 대상을 변경했습니다." }
}
finally {
    Remove-Item -LiteralPath $fixtureFile, $fixturePolicy -Force -ErrorAction SilentlyContinue
    if ($syncFirst) { Remove-Item -LiteralPath $syncFirst, $syncPolicy -Force -ErrorAction SilentlyContinue }
}

Write-Output "PASS: 현재 필수 capability, 누락 감지·manifest 유효성 $($manifestCases.Count)건, 동기화 사전 거부 fixture"
