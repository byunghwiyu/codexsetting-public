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

Write-Output "PASS: 안전 정책 동기화, 필수 규칙, 책임 분리, 멱등성, 생성기 사전 거부 $($safetyCases.Count)건 확인"
