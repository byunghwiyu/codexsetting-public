param(
    [string]$PolicyPath = "$HOME\.codex\harness-policy.json"
)

$ErrorActionPreference = "Stop"
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Resolve-HomePath {
    param([string]$Path)

    if ($Path -eq "~") { return $HOME }
    if ($Path.StartsWith("~/") -or $Path.StartsWith("~\")) {
        return Join-Path $HOME $Path.Substring(2)
    }
    return $Path
}

function Add-Issue([string]$Status, [string]$Message) {
    if ($Status -eq "required") { $script:errors.Add($Message) }
    else { $script:warnings.Add($Message) }
}

function Test-Rule {
    param([string]$Id, [string]$Status, [object]$Rule)
    $resolvedPath = Resolve-HomePath $Rule.path
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        Add-Issue $Status "$Id 구현 파일 없음: $resolvedPath"
        return
    }
    $content = Get-Content -Raw -LiteralPath $resolvedPath -Encoding UTF8
    foreach ($requiredText in @($Rule.allOf)) {
        if ([string]::IsNullOrWhiteSpace($requiredText)) { continue }
        if (-not $content.Contains($requiredText)) { Add-Issue $Status "$Id 필수 문구 누락: '$requiredText' -> $resolvedPath" }
    }
    foreach ($forbiddenText in @($Rule.noneOf)) {
        if ([string]::IsNullOrWhiteSpace($forbiddenText)) { continue }
        if ($content.Contains($forbiddenText)) { Add-Issue $Status "$Id 상충 문구 발견: '$forbiddenText' -> $resolvedPath" }
    }
}

try { $policy = Get-Content -Raw -LiteralPath $PolicyPath -Encoding UTF8 | ConvertFrom-Json }
catch { Write-Output "FAIL 정책 JSON 파싱 실패: $($_.Exception.Message)"; exit 1 }
if ($policy.schemaVersion -ne 2) { Write-Output "FAIL capability manifest는 schemaVersion 2가 필요합니다."; exit 1 }

foreach ($capability in @($policy.capabilities)) {
    foreach ($platform in @("Codex", "Claude")) {
        $rules = @($capability.implementations.$platform)
        if ($rules.Count -eq 0) { Add-Issue $capability.status "$($capability.id) $platform 구현 매핑 없음"; continue }
        foreach ($rule in $rules) { Test-Rule -Id "$($capability.id)/$platform" -Status $capability.status -Rule $rule }
    }
}
foreach ($conflict in @($policy.conflictRules)) {
    foreach ($check in @($conflict.checks)) { Test-Rule -Id $conflict.id -Status $conflict.status -Rule $check }
}

foreach ($warning in $warnings) { Write-Output "WARN $warning" }
foreach ($errorItem in $errors) { Write-Output "FAIL $errorItem" }
Write-Output "SUMMARY capabilities=$(@($policy.capabilities).Count) conflicts=$(@($policy.conflictRules).Count) warnings=$($warnings.Count) errors=$($errors.Count)"
if ($errors.Count -gt 0) { exit 1 }
exit 0
