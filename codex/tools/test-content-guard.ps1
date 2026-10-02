param([string]$CodexHome = "$HOME\.codex")

$ErrorActionPreference = 'Stop'
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
    @{ Name = '잘못된 JSON'; Raw = '{broken'; Expected = 2 }
)

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
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($payload)
    $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $process.StandardInput.Close()
    $null = $process.StandardOutput.ReadToEnd()
    $null = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne $case.Expected) {
        $failures += "$($case.Name): expected=$($case.Expected) actual=$($process.ExitCode)"
    }
    $process.Dispose()
}
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "FAIL: $_" }
    exit 1
}
Write-Output "PASS: 콘텐츠 가드 $($cases.Count)건"
exit 0
