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

Write-Output "PASS: 안전 정책 동기화, 필수 규칙, 책임 분리, 멱등성 확인"
