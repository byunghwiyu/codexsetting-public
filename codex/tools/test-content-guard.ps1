param([string]$CodexHome = "$HOME\.codex")

$ErrorActionPreference = 'Stop'
# 자식 가드의 사유와 검사 요약을 같은 UTF-8 인코딩으로 전달한다.
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
# 현재 실행기를 재사용해 Windows PowerShell과 macOS pwsh를 모두 지원한다.
$powerShellExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$hook = Join-Path $CodexHome 'hooks\pre_tool_use_content_guard.ps1'
$cases = @(
    @{ Name = '일반 문자열'; Text = 'task-name'; Expected = 0 },
    @{ Name = '환경변수 API 키'; Text = 'api_key = os.getenv("EXAMPLE")'; Expected = 0 },
    @{ Name = '환경변수 토큰'; Text = 'GITHUB_TOKEN=$env:EXAMPLE'; Expected = 0 },
    @{ Name = '함수로 읽는 토큰'; Text = 'GITHUB_TOKEN=os.getenv("EXAMPLE")'; Expected = 0 },
    @{ Name = 'API 키 리터럴'; Text = 'api_key = "example-value-123"'; Expected = 2 },
    @{ Name = '토큰 리터럴'; Text = 'GITHUB_TOKEN=secret'; Expected = 2 },
    @{ Name = '키 형태'; Text = ('sk-' + ('a' * 24)); Expected = 2 },
    @{ Name = 'GitHub 키 형태'; Text = ('ghp_' + ('a' * 32)); Expected = 2 },
    @{ Name = 'SQL 기본'; Text = 'DROP TABLE example;'; Expected = 2 },
    @{ Name = 'SQL 공백'; Text = 'DROP  TABLE example;'; Expected = 2 },
    @{ Name = 'SQL 줄바꿈'; Text = "drop`nTABLE example;"; Expected = 2 },
    @{ Name = 'SQL 단어 경계'; Text = 'DROPTABLE example'; Expected = 0 },
    @{ Name = '개인키 표식'; Text = 'BEGIN PRIVATE KEY'; Expected = 2 },
    @{ Name = '정상 패치'; Text = "*** Begin Patch`n*** Add File: src/a.py`n+print(1)`n*** End Patch"; Expected = 0 },
    @{ Name = 'SQL 삭제 패치'; Text = "*** Begin Patch`n*** Update File: src/a.sql`n@@`n-DROP TABLE example;`n+SELECT 1;`n*** End Patch"; Expected = 0 },
    @{ Name = 'SQL 추가 패치'; Text = "*** Begin Patch`n*** Update File: src/a.sql`n@@`n+DROP`n+TABLE example;`n*** End Patch"; Expected = 2 },
    @{ Name = '키 삭제 패치'; Text = ("*** Begin Patch`n*** Update File: src/a.py`n@@`n-" + 'sk-' + ('a' * 24) + "`n+safe`n*** End Patch"); Expected = 0 },
    @{ Name = '파일 삭제 패치'; Text = "*** Begin Patch`n*** Delete File: src/a.sql`n*** End Patch"; Expected = 0 },
    @{ Name = '문맥 줄'; Text = "*** Begin Patch`n*** Update File: src/a.sql`n@@`n DROP TABLE example;`n+SELECT 1;`n*** End Patch"; Expected = 0 },
    @{ Name = '테스트 경로'; Text = "*** Begin Patch`n*** Add File: tests/a.cs`n+ASPNETCORE_ENVIRONMENT=Production`n*** End Patch"; Expected = 2 },
    @{ Name = '일반 경로'; Text = "*** Begin Patch`n*** Add File: src/a.cs`n+ASPNETCORE_ENVIRONMENT=Production`n*** End Patch"; Expected = 0 },
    @{ Name = '다중 파일 경로'; Text = "*** Begin Patch`n*** Add File: src/a.cs`n+safe`n*** Add File: tests/a.cs`n+ASPNETCORE_ENVIRONMENT=Production`n*** End Patch"; Expected = 2 },
    @{ Name = '이동 대상 경로'; Text = "*** Begin Patch`n*** Update File: src/a.cs`n*** Move to: tests/a.cs`n@@`n+ASPNETCORE_ENVIRONMENT=Production`n*** End Patch"; Expected = 2 },
    @{ Name = '셸 입력'; Tool = 'Bash'; Field = 'command'; Text = 'DROP  TABLE example;'; Expected = 2 },
    @{ Name = 'cmd 입력'; Tool = 'Bash'; Field = 'cmd'; Text = 'DROP TABLE example;'; Expected = 2 },
    @{ Name = '기존 patch 입력'; Field = 'patch'; Text = 'DROP TABLE example;'; Expected = 2 },
    @{ Name = '잘못된 JSON'; Raw = '{broken'; Expected = 2 },
    @{ Name = 'BOM 정상 입력'; Text = 'task-name'; Bom = $true; Expected = 0 },
    @{ Name = 'BOM 위험 입력'; Text = 'BEGIN PRIVATE KEY'; Bom = $true; Expected = 2 },
    @{ Name = '한글 정상 입력'; Text = '한글 설명 문자열'; Expected = 0 }
)

# 아래 위험 문자열은 훅에 전달하는 합성 입력이며 실제 SQL이나 패치를 실행하지 않는다.
$cases += @(
    @{ Name = 'DB 삭제 기본'; Text = 'DROP DATABASE example;'; Expected = 2; Rule = 'DROP DATABASE' },
    @{ Name = 'DB 삭제 공백'; Text = 'DROP  DATABASE example;'; Expected = 2; Rule = 'DROP DATABASE' },
    @{ Name = 'DB 삭제 줄바꿈'; Text = "drop`nDATABASE example;"; Expected = 2; Rule = 'DROP DATABASE' },
    @{ Name = 'DB 삭제 앞 단어 경계'; Text = 'DROPDATABASE example'; Expected = 0 },
    @{ Name = 'DB 삭제 뒤 단어 경계'; Text = 'DROP DATABASE_LOG example'; Expected = 0 },
    @{ Name = 'DB 삭제 추가 패치'; Text = "*** Begin Patch`n*** Update File: src/a.sql`n@@`n+DROP`n+DATABASE example;`n*** End Patch"; Expected = 2; Rule = 'DROP DATABASE' },
    @{ Name = 'DB 삭제 제거 패치'; Text = "*** Begin Patch`n*** Update File: src/a.sql`n@@`n-DROP DATABASE example;`n+SELECT 1;`n*** End Patch"; Expected = 0 },
    @{ Name = 'DB 삭제 문맥 줄'; Text = "*** Begin Patch`n*** Update File: src/a.sql`n@@`n DROP DATABASE example;`n+SELECT 1;`n*** End Patch"; Expected = 0 },
    @{ Name = 'DB 삭제 셸 cmd'; Tool = 'Bash'; Field = 'cmd'; Text = 'DROP DATABASE example;'; Expected = 2; Rule = 'DROP DATABASE' }
)
foreach ($keyFormat in @('RSA', 'EC', 'OPENSSH')) {
    $keyMarker = "BEGIN $keyFormat PRIVATE KEY"
    $keyHeader = "-----$keyMarker-----"
    $cases += @(
        @{ Name = "$keyFormat 개인키 헤더"; Text = $keyHeader; Expected = 2; Rule = $keyMarker },
        @{ Name = "$keyFormat 개인키 소문자"; Text = $keyHeader.ToLowerInvariant(); Expected = 2; Rule = $keyMarker },
        @{ Name = "$keyFormat 개인키 셸 입력"; Tool = 'Bash'; Field = 'command'; Text = $keyHeader; Expected = 2; Rule = $keyMarker },
        @{ Name = "$keyFormat 개인키 추가 패치"; Text = "*** Begin Patch`n*** Add File: docs/example.md`n+$keyHeader`n*** End Patch"; Expected = 2; Rule = $keyMarker },
        @{ Name = "$keyFormat 개인키 제거 패치"; Text = "*** Begin Patch`n*** Update File: docs/example.md`n@@`n-$keyHeader`n+safe`n*** End Patch"; Expected = 0 },
        @{ Name = "$keyFormat 공개키 허용"; Text = "-----BEGIN $keyFormat PUBLIC KEY-----"; Expected = 0 }
    )
}

$failures = @()
foreach ($case in $cases) {
    $tool = if ($case.Tool) { $case.Tool } else { 'apply_patch' }
    $field = if ($case.Field) { $case.Field } else { 'command' }
    $payload = if ($case.Raw) { $case.Raw } else {
        @{ tool_name = $tool; tool_input = @{ $field = $case.Text } } | ConvertTo-Json -Compress
    }
    # 가상 입력만 훅으로 보내며, 입력 안의 명령과 패치는 실행하지 않는다.
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $powerShellExecutable
    $start.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $hook + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($start)
    # Bom 사례는 UTF-8 BOM을 직접 붙여 호출자 인코딩 차이를 재현한다.
    $bytes = [System.Text.UTF8Encoding]::new([bool]$case.Bom).GetPreamble() + [System.Text.UTF8Encoding]::new($false).GetBytes($payload)
    $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $process.StandardInput.Close()
    $null = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne $case.Expected) {
        $failures += "$($case.Name): expected=$($case.Expected) actual=$($process.ExitCode)"
    }
    # 단순 오류 종료를 탐지 성공으로 오인하지 않도록 해당 차단 규칙도 확인한다.
    if ($case.Rule -and -not $stderr.Contains("[Scan:$($case.Rule)]")) {
        $failures += "$($case.Name): expected rule=$($case.Rule)"
    }
    $process.Dispose()
}

# Windows 앱이 등록 명령을 외부 PowerShell에서 실행하는 경로도 검증한다.
$launcherCases = @()
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    $registered = Get-Content -LiteralPath (Join-Path $CodexHome 'hooks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $windowsCommand = [string]$registered.hooks.PreToolUse[0].hooks[0].commandWindows
    # 홈을 바꾸지 않고 파일 경로만 자식 프로세스의 전용 환경변수로 주입한다.
    $launcherCommand = $windowsCommand.Replace('$env:USERPROFILE/.codex/hooks/pre_tool_use_content_guard.ps1', '$env:CODEX_CONTENT_GUARD_TEST_PATH')
    if ($launcherCommand -eq $windowsCommand) { throw '등록 명령의 가드 경로를 격리하지 못했습니다.' }
    $launcherCases = @(
        @{ Name = '등록 명령 정상'; Text = '한글 정상 내용'; Expected = 0; Feedback = 'PASS: 콘텐츠 정책 위반 없음' },
        @{ Name = '등록 명령 BOM'; Text = '한글 정상 내용'; Bom = $true; Expected = 0; Feedback = 'PASS: 콘텐츠 정책 위반 없음' },
        @{ Name = '등록 명령 위험 패치'; Text = "*** Begin Patch`n*** Add File: docs/example.md`n+BEGIN PRIVATE KEY`n*** End Patch"; Expected = 2; Feedback = '[Scan:BEGIN PRIVATE KEY] 개인키 검사 대상' },
        @{ Name = '등록 명령 JSON 오류'; Raw = '{broken'; Expected = 2; Feedback = '[Codex Guard] 훅 입력 파싱 실패' }
    )
    foreach ($case in $launcherCases) {
        $payload = if ($case.Raw) { $case.Raw } else {
            @{ tool_name = 'apply_patch'; tool_input = @{ command = $case.Text } } | ConvertTo-Json -Compress
        }
        $start = [System.Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $powerShellExecutable
        $start.Arguments = '-NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($launcherCommand))
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardInput = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
        $start.EnvironmentVariables['CODEX_CONTENT_GUARD_TEST_PATH'] = [IO.Path]::GetFullPath($hook)
        $process = [System.Diagnostics.Process]::Start($start)
        $bytes = [Text.UTF8Encoding]::new([bool]$case.Bom).GetPreamble() + [Text.UTF8Encoding]::new($false).GetBytes($payload)
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.Close()
        $feedback = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne $case.Expected -or -not $feedback.Contains($case.Feedback)) {
            $failures += "$($case.Name): expected=$($case.Expected) actual=$($process.ExitCode), 한글 피드백=$($feedback.Contains($case.Feedback))"
        }
        $process.Dispose()
    }
}


# 손상·빈 정책은 정상 내용도 통과시키지 않는다. 임시 정책 파일로 검사기를 직접 실행한다.
$scanner = Join-Path $CodexHome 'tools\scan-content-policy.ps1'
$policyRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-scan-policy-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $policyRoot | Out-Null
$policyCases = @(
    @{ Name = '빈 정책'; Body = 'patterns: []' },
    @{ Name = 'scope 누락 정책'; Body = "patterns:`n  - pattern: `"sk-`"`n    policy: `"scan`"`n    reason: `"example`"" },
    @{ Name = '정책 파일 없음'; Body = $null }
)
foreach ($policyCase in $policyCases) {
    $policyFile = Join-Path $policyRoot ([guid]::NewGuid().ToString('N') + '.yaml')
    if ($null -ne $policyCase.Body) { [System.IO.File]::WriteAllText($policyFile, $policyCase.Body) }
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $powerShellExecutable
    $start.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $scanner + '" -Content task-name -PolicyPath "' + $policyFile + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($start)
    $null = $process.StandardOutput.ReadToEnd()
    $null = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 2) {
        $failures += "$($policyCase.Name): expected=2 actual=$($process.ExitCode)"
    }
    $process.Dispose()
}
# 임시 정책 폴더는 진단을 위해 보존한다. 자동 삭제하지 않는다.

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "FAIL: $_" }
    exit 1
}
Write-Output "PASS: 콘텐츠 가드 $($cases.Count)건, 정책 오류 $($policyCases.Count)건, Windows 등록 명령 $($launcherCases.Count)건"
exit 0
