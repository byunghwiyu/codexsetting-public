param(
    [string]$CodexHome = "$HOME\.codex"
)

$ErrorActionPreference = "Stop"

$source = Join-Path $CodexHome "deny-patterns.yaml"
$target = Join-Path $CodexHome "rules\deny.rules"
$sync = Join-Path $CodexHome "tools\sync-deny-policy.ps1"

& $sync -Source $source -Target $target -Check

$rules = Get-Content -Raw -LiteralPath $target -Encoding UTF8
$requiredRules = @(
    'pattern=["git", "push", "--force-with-lease"], decision="forbidden"',
    'pattern=["Remove-Item", "-Recurse"], decision="forbidden"',
    'pattern=["rd", "/s", "/q"], decision="forbidden"',
    'pattern=["rmdir", "/s", "/q"], decision="forbidden"',
    'pattern=["del", "/s", "/q"], decision="forbidden"',
    'pattern=["psql"], decision="prompt"',
    'pattern=["mysql"], decision="prompt"'
)

foreach ($requiredRule in $requiredRules) {
    if (-not $rules.Contains($requiredRule)) {
        throw "필수 정책 누락: $requiredRule"
    }
}

foreach ($scanOnlyPattern in @("DROP TABLE", "api_key", "sk-", "BEGIN PRIVATE KEY", "GITHUB_TOKEN=")) {
    if ($rules.Contains($scanOnlyPattern)) {
        throw "콘텐츠 검사 패턴이 명령 정책에 잘못 포함됨: $scanOnlyPattern"
    }
}

# macOS에서도 유효한 임시 경로를 사용하며 기존 파일 및 동시 검사와 충돌하지 않는다.
$fixtureId = [guid]::NewGuid().ToString('N')
$temporaryRoot = [System.IO.Path]::GetTempPath()
$tempOne = Join-Path $temporaryRoot "codex-deny-policy-$fixtureId-one.rules"
$tempTwo = Join-Path $temporaryRoot "codex-deny-policy-$fixtureId-two.rules"
try {
    & $sync -Source $source -Target $tempOne
    & $sync -Source $source -Target $tempTwo
    $hashOne = (Get-FileHash -LiteralPath $tempOne -Algorithm SHA256).Hash
    $hashTwo = (Get-FileHash -LiteralPath $tempTwo -Algorithm SHA256).Hash
    if ($hashOne -ne $hashTwo) {
        throw "정책 생성 결과가 멱등적이지 않습니다."
    }
}
finally {
    Remove-Item -LiteralPath $tempOne, $tempTwo -Force -ErrorAction SilentlyContinue
}

# 공통 안전 정책 생성기: 상충 옵션과 일부 출력 경로 누락은 아무것도 쓰기 전에 거부해야 한다.
$safetySync = Join-Path $CodexHome "tools\sync-global-safety-policy.ps1"
$safetySource = Join-Path $CodexHome "safety-policy.json"
$safetyRoot = Join-Path $temporaryRoot "codex-safety-sync-$fixtureId"
$firstTarget = Join-Path $safetyRoot "codex.yaml"
$secondTarget = Join-Path $safetyRoot "claude.json"
$safetyCases = @(
    @{ Name = "Write와 Check 동시 지정"; ClaudeTarget = $secondTarget; Check = $true },
    @{ Name = "두 번째 출력 폴더 없음"; ClaudeTarget = (Join-Path $safetyRoot "missing\claude.json"); Check = $false }
)
New-Item -ItemType Directory -Path $safetyRoot | Out-Null
foreach ($safetyCase in $safetyCases) {
    [System.IO.File]::WriteAllText($firstTarget, "original")
    [System.IO.File]::WriteAllText($secondTarget, "original")
    $rejected = $false
    try { & $safetySync -Source $safetySource -CodexTarget $firstTarget -ClaudeTarget $safetyCase.ClaudeTarget -Write -Check:$safetyCase.Check | Out-Null }
    catch { $rejected = $true }
    if (-not $rejected) { throw "안전 정책 생성기가 거부하지 않음: $($safetyCase.Name)" }
    foreach ($target in @($firstTarget, $secondTarget)) {
        if ([System.IO.File]::ReadAllText($target) -ne "original") { throw "거부 전에 출력이 변경됨: $($safetyCase.Name) ($target)" }
    }
}
# 임시 산출물은 진단을 위해 보존한다. 자동 삭제하지 않는다.

# 실제 정책은 수정하지 않고, 합성 정책으로 JSON 비교의 허용·거부 경계를 확인한다.
$jsonSource = Join-Path $safetyRoot 'source.json'
$jsonPolicy = Get-Content -Raw -LiteralPath $safetySource -Encoding UTF8 | ConvertFrom-Json
$jsonPolicy.platformPolicies.claude.patterns = @([pscustomobject]@{
    id = 'alpha'; tools = @('Bash', 'Edit'); command_regex = 'a&b'; reason = '한글'; enabled = $true; note = $null
})
[System.IO.File]::WriteAllText($jsonSource, ($jsonPolicy | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
& $safetySync -Source $jsonSource -CodexTarget $firstTarget -ClaudeTarget $secondTarget -Write | Out-Null
$compact = '{"version":1,"patterns":[{"id":"alpha","tools":["Bash","Edit"],"command_regex":"a&b","reason":"한글","enabled":true,"note":null}]}'
$jsonCases = @(
    @{ Name = '압축 JSON'; Body = $compact; Valid = $true },
    @{ Name = '객체 속성 순서'; Body = '{"patterns":[{"note":null,"enabled":true,"reason":"한글","command_regex":"a&b","tools":["Bash","Edit"],"id":"alpha"}],"version":1}'; Valid = $true },
    @{ Name = '개행과 유니코드 이스케이프'; Body = ("`r`n  " + $compact.Replace('a&b', 'a\u0026b').Replace('한글', '\ud55c\uae00') + "`r`n"); Valid = $true },
    @{ Name = '문자열 대소문자 변경'; Body = $compact.Replace('alpha', 'ALPHA'); Valid = $false },
    @{ Name = '배열 순서 변경'; Body = $compact.Replace('["Bash","Edit"]', '["Edit","Bash"]'); Valid = $false },
    @{ Name = '숫자를 문자열로 변경'; Body = $compact.Replace('"version":1', '"version":"1"'); Valid = $false },
    @{ Name = '속성 이름 대소문자 변경'; Body = $compact.Replace('"id":', '"ID":'); Valid = $false },
    @{ Name = 'null 속성 누락'; Body = $compact.Replace(',"note":null', ''); Valid = $false },
    @{ Name = '추가 속성'; Body = $compact.Replace('"version":1', '"extra":0,"version":1'); Valid = $false },
    @{ Name = 'null을 빈 문자열로 변경'; Body = $compact.Replace('"note":null', '"note":""'); Valid = $false },
    @{ Name = '불리언 변경'; Body = $compact.Replace('true', 'false'); Valid = $false },
    @{ Name = '손상 JSON'; Body = '{broken'; Valid = $false },
    @{ Name = 'JSON 뒤 추가 입력'; Body = ($compact + ',"other":0'); Valid = $false },
    @{ Name = '빈 파일'; Body = ''; Valid = $false },
    @{ Name = '루트를 배열로 변경'; Body = ('[' + $compact + ']'); Valid = $false }
)
$jsonFailures = @()
foreach ($jsonCase in $jsonCases) {
    [System.IO.File]::WriteAllText($secondTarget, $jsonCase.Body, [System.Text.UTF8Encoding]::new($false))
    $beforeHashes = @($jsonSource, $firstTarget, $secondTarget | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash })
    $accepted = $true
    try { & $safetySync -Source $jsonSource -CodexTarget $firstTarget -ClaudeTarget $secondTarget -Check | Out-Null }
    catch { $accepted = $false }
    $afterHashes = @($jsonSource, $firstTarget, $secondTarget | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash })
    if (($beforeHashes -join ',') -ne ($afterHashes -join ',')) { throw "Check가 파일을 변경했습니다: $($jsonCase.Name)" }
    if ($accepted -ne $jsonCase.Valid) { $jsonFailures += $jsonCase.Name }
}
if ($jsonFailures.Count -gt 0) { throw "JSON 비교 결과 불일치: $($jsonFailures -join ', ')" }

Write-Output "PASS: 안전 정책 동기화, 필수 규칙, 책임 분리, 멱등성, 생성기 사전 거부 $($safetyCases.Count)건, JSON 비교·Check 무변경 $($jsonCases.Count)건 확인"
