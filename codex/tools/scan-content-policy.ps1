param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Content,
    [string]$FilePath = "",
    [string]$PolicyPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "deny-patterns.yaml")
)

$ErrorActionPreference = "Stop"
$entries = @()
$current = $null

foreach ($line in Get-Content -LiteralPath $PolicyPath -Encoding UTF8) {
    if ($line -match '^\s*- pattern:\s*"(.*)"\s*$') {
        if ($null -ne $current) { $entries += [pscustomobject]$current }
        $current = @{ Pattern = $Matches[1] }
        continue
    }
    if ($null -eq $current) { continue }
    if ($line -match '^\s+policy:\s*"(forbidden|prompt|scan)"\s*$') { $current.Policy = $Matches[1] }
    elseif ($line -match '^\s+scope:\s*"(.*)"\s*$') { $current.Scope = $Matches[1] }
    elseif ($line -match '^\s+reason:\s*"(.*)"\s*$') { $current.Reason = $Matches[1] }
}
if ($null -ne $current) { $entries += [pscustomobject]$current }

# 기존 정책 이름은 유지하고, 식별자와 실제 값 또는 SQL 구문을 구분한다.
$matchers = @{
    'DROP TABLE' = '\bDROP\s+TABLE\b'
    'api_key' = '(?i)\bapi_key\b["'']?\s*[:=]\s*["''][^"''\r\n]{8,}["'']'
    'sk-' = '\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[A-Za-z0-9-]{10,})\b'
    'GITHUB_TOKEN=' = '\bGITHUB_TOKEN\s*=\s*(?:["''][A-Za-z0-9_-]+["'']|[A-Za-z0-9_-]+(?=\s*(?:$|[;\r\n])))'
}

foreach ($entry in $entries) {
    if ($entry.Policy -ne "scan") { continue }
    if ($entry.Scope -ne "**/*" -and -not [string]::IsNullOrWhiteSpace($FilePath)) {
        $normalizedPath = '/' + $FilePath.Replace('\', '/').TrimStart('/')
        if (-not ($normalizedPath -like $entry.Scope.Replace('**/', '*'))) { continue }
    }
    $matched = if ($matchers.ContainsKey($entry.Pattern)) {
        [regex]::IsMatch($Content, $matchers[$entry.Pattern], [System.Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromSeconds(1))
    }
    else { $Content.IndexOf($entry.Pattern, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }
    if ($matched) {
        [Console]::Error.WriteLine("[Scan:$($entry.Pattern)] $($entry.Reason)")
        exit 2
    }
}

Write-Output "PASS: 콘텐츠 정책 위반 없음"
exit 0
