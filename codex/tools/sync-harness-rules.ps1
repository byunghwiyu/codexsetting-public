param(
    [string]$Source = "$HOME\.codex\harness-policy.json",
    [switch]$Write
)

$ErrorActionPreference = "Stop"
$startMarker = "<!-- HARNESS-COMMON:START -->"
$endMarker = "<!-- HARNESS-COMMON:END -->"

function Resolve-HomePath {
    param([string]$Path)

    if ($Path -eq "~") { return $HOME }
    if ($Path.StartsWith("~/") -or $Path.StartsWith("~\")) {
        return Join-Path $HOME $Path.Substring(2)
    }
    return $Path
}

function New-ManagedBlock {
    param([object]$Policy, [object]$Target)

    $common = $Policy.common
    $lines = @(
        $startMarker,
        "## 공통 하네스 계약 (자동 생성)",
        "",
        "> 원본: `~/.codex/harness-policy.json` — 이 블록을 직접 수정하지 않는다.",
        "",
        "- $($common.language)",
        "- $($common.planApproval)",
        "- $($common.destructiveApproval)",
        "- 1 Phase의 변경 파일은 최대 $($common.phaseMaxFiles)개다.",
        "- $($common.phaseApproval)",
        "- $($common.rubricRange)",
        "- 공통 판정 축: $($common.rubricAxes -join ', ')",
        "- $($common.completion)",
        "",
        "### $($Target.name) 플랫폼 예외"
    )
    foreach ($override in $Target.overrides) { $lines += "- $override" }
    $lines += $endMarker
    return ($lines -join "`n")
}

function Set-ManagedBlock {
    param([string]$Content, [string]$Block)

    $normalized = $Content.Replace("`r`n", "`n")
    $start = $normalized.IndexOf($startMarker)
    $end = $normalized.IndexOf($endMarker)
    if (($start -ge 0) -xor ($end -ge 0)) { throw "관리 블록 마커가 한쪽만 존재합니다." }
    if ($start -lt 0) { return $normalized.TrimEnd() + "`n`n" + $Block + "`n" }
    if ($end -lt $start) { throw "관리 블록 마커 순서가 잘못되었습니다." }
    $end += $endMarker.Length
    return $normalized.Substring(0, $start) + $Block + $normalized.Substring($end)
}

$policy = Get-Content -Raw -LiteralPath $Source -Encoding UTF8 | ConvertFrom-Json
if ($policy.schemaVersion -notin @(1, 2)) { throw "지원하지 않는 하네스 정책 버전: $($policy.schemaVersion)" }

foreach ($target in $policy.targets) {
    $targetPath = Resolve-HomePath $target.path
    if (-not (Test-Path -LiteralPath $targetPath)) { throw "동기화 대상이 없습니다: $targetPath" }
    $current = Get-Content -Raw -LiteralPath $targetPath -Encoding UTF8
    $expected = Set-ManagedBlock -Content $current -Block (New-ManagedBlock -Policy $policy -Target $target)
    $normalizedCurrent = $current.Replace("`r`n", "`n")

    if ($Write) {
        [System.IO.File]::WriteAllText($targetPath, $expected, [System.Text.UTF8Encoding]::new($true))
        Write-Output "SYNC $($target.name): $targetPath"
    }
    elseif ($normalizedCurrent -ne $expected) {
        throw "하네스 규칙 드리프트 감지: $($target.name) ($targetPath)"
    }
    else {
        Write-Output "PASS $($target.name): 관리 블록 일치"
    }
}
