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
        "- $($common.phaseFileRule)",
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

# 잘못된 정책이 빈 문장으로 생성되지 않도록 쓰기 전에 사용 필드를 검증한다.
foreach ($field in @("language", "planApproval", "destructiveApproval", "phaseFileRule", "phaseApproval", "rubricRange", "completion")) {
    $value = $policy.common.$field
    if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
        throw "정책 필드 오류: common.$field (비어 있지 않은 문자열 필요)"
    }
}
if ($policy.common.rubricAxes -isnot [array] -or $policy.common.rubricAxes.Count -eq 0) {
    throw "정책 필드 오류: common.rubricAxes (비어 있지 않은 배열 필요)"
}
foreach ($axis in $policy.common.rubricAxes) {
    if ($axis -isnot [string] -or [string]::IsNullOrWhiteSpace($axis)) {
        throw "정책 필드 오류: common.rubricAxes (비어 있지 않은 문자열 항목 필요)"
    }
}
if ($policy.targets -isnot [array] -or $policy.targets.Count -eq 0) {
    throw "정책 필드 오류: targets (비어 있지 않은 배열 필요)"
}
foreach ($target in $policy.targets) {
    foreach ($field in @("name", "path")) {
        if ($target.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($target.$field)) {
            throw "정책 필드 오류: targets.$field (비어 있지 않은 문자열 필요)"
        }
    }
    if ($target.overrides -isnot [array]) { throw "정책 필드 오류: targets.overrides (배열 필요)" }
    foreach ($override in $target.overrides) {
        if ($override -isnot [string] -or [string]::IsNullOrWhiteSpace($override)) {
            throw "정책 필드 오류: targets.overrides (비어 있지 않은 문자열 항목 필요)"
        }
    }
}

# 일부 대상만 갱신되지 않도록 모든 대상의 결과를 먼저 계산·검증한 뒤 쓴다.
$plans = @()
foreach ($target in $policy.targets) {
    $targetPath = Resolve-HomePath $target.path
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { throw "동기화 대상이 없습니다: $targetPath" }
    $current = Get-Content -Raw -LiteralPath $targetPath -Encoding UTF8
    $plans += [pscustomobject]@{
        Name = $target.name
        Path = $targetPath
        Current = $current.Replace("`r`n", "`n")
        Expected = Set-ManagedBlock -Content $current -Block (New-ManagedBlock -Policy $policy -Target $target)
    }
}

foreach ($plan in $plans) {
    if ($Write) {
        [System.IO.File]::WriteAllText($plan.Path, $plan.Expected, [System.Text.UTF8Encoding]::new($true))
        Write-Output "SYNC $($plan.Name): $($plan.Path)"
    }
    elseif ($plan.Current -ne $plan.Expected) {
        throw "하네스 규칙 드리프트 감지: $($plan.Name) ($($plan.Path))"
    }
    else {
        Write-Output "PASS $($plan.Name): 관리 블록 일치"
    }
}
