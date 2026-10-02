param(
    [string]$CodexHome = "$HOME\.codex",
    [string]$ClaudeHome = "$HOME\.claude"
)

$ErrorActionPreference = "Stop"
$failures = [System.Collections.Generic.List[string]]::new()
$powerShellExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
# TEMP가 없는 macOS에서도 동작하며 검사마다 고유한 경로만 사용한다.
$temporaryRoot = [System.IO.Path]::GetTempPath()
$fixtureId = [guid]::NewGuid().ToString('N')
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "빌드 훅 검증에는 .NET SDK가 필요합니다."
}

# 이 검사 전용 홈에 정책만 복사해 실제 사용자 정책을 읽지 않는다.
$guardHome = Join-Path $temporaryRoot "codex-guard-home-$fixtureId"
$guardPolicyDirectory = Join-Path $guardHome '.claude'
New-Item -ItemType Directory -Path $guardPolicyDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $ClaudeHome 'deny-patterns.json') -Destination $guardPolicyDirectory
$sdkMajor = ((& dotnet --version) -split '\.')[0]
if ($sdkMajor -notmatch '^\d+$') { throw '설치된 .NET SDK 버전을 확인할 수 없습니다.' }
$targetFramework = "net$sdkMajor.0"

function Invoke-NodeHook {
    param([string]$Script, [string]$InputText)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = "node"
    $startInfo.Arguments = '"' + $Script.Replace('"', '\"') + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.EnvironmentVariables['HOME'] = $guardHome
    $startInfo.EnvironmentVariables['USERPROFILE'] = $guardHome
    $startInfo.EnvironmentVariables['DOTNET_CLI_HOME'] = $guardHome
    $startInfo.EnvironmentVariables['APPDATA'] = Join-Path $guardHome 'AppData/Roaming'
    $startInfo.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $guardHome 'AppData/Local'
    $startInfo.EnvironmentVariables['NUGET_PACKAGES'] = Join-Path $guardHome '.nuget/packages'
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $normalizedInput = $InputText.TrimStart([char]0xFEFF)
    $inputBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalizedInput)
    $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
    $process.StandardInput.BaseStream.Close()
    $output = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
}

function Assert-Exit {
    param([string]$Name, [object]$Result, [int]$Expected)
    if ($Result.ExitCode -ne $Expected) {
        $script:failures.Add("$Name expected=$Expected actual=$($Result.ExitCode) output=$($Result.Output.Trim())")
    }
}

function Invoke-PowerShellHook {
    param([string]$Script, [string]$InputText)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = $InputText | & $powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $Script 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

$denyHook = Join-Path $ClaudeHome "hooks\validate-deny.js"
$buildHook = Join-Path $ClaudeHome "hooks\post_edit_build.js"
$scanTool = Join-Path $CodexHome "tools\scan-content-policy.ps1"
$codexHook = Join-Path $CodexHome "hooks\pre_tool_use_content_guard.ps1"

Assert-Exit "Claude force-push 차단" (Invoke-NodeHook $denyHook '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}') 2
Assert-Exit "Claude 안전 명령 허용" (Invoke-NodeHook $denyHook '{"tool_name":"Bash","tool_input":{"command":"git status"}}') 0
Assert-Exit "Claude deny 입력 오류 fail-closed" (Invoke-NodeHook $denyHook '{broken') 2
$missingDirectory = Join-Path $temporaryRoot "codex-harness-missing-$fixtureId"
$markdownInput = @{ tool_name = 'Edit'; tool_input = @{ file_path = (Join-Path $missingDirectory 'probe.md') } } | ConvertTo-Json -Compress
$missingInput = @{ tool_name = 'Edit'; tool_input = @{ file_path = (Join-Path $missingDirectory 'probe.cs') } } | ConvertTo-Json -Compress
Assert-Exit "Claude 비-C# 건너뜀" (Invoke-NodeHook $buildHook $markdownInput) 0
$missingProject = Invoke-NodeHook $buildHook $missingInput
Assert-Exit "Claude C# 프로젝트 미발견 처리" $missingProject 0
if (-not $missingProject.Output.Contains("건너뜀")) { $failures.Add("Claude C# 훅이 프로젝트 탐색 결과를 보고하지 않음") }
Assert-Exit "Claude build 입력 오류 차단" (Invoke-NodeHook $buildHook '{broken') 1
$fixtureDirectory = Join-Path $temporaryRoot "codex-harness-hook-broken-$fixtureId"
$fixtureProject = Join-Path $fixtureDirectory "Broken.csproj"
$fixtureSource = Join-Path $fixtureDirectory "Probe.cs"
try {
    New-Item -ItemType Directory -Path $fixtureDirectory -Force | Out-Null
    [System.IO.File]::WriteAllText($fixtureProject, "<Project><Broken></Project>")
    [System.IO.File]::WriteAllText($fixtureSource, "public class Probe {}")
    $escapedSource = $fixtureSource.Replace('\', '\\')
    Assert-Exit "Claude 실제 빌드 실패 피드백" (Invoke-NodeHook $buildHook "{`"tool_name`":`"Edit`",`"tool_input`":{`"file_path`":`"$escapedSource`"}}") 2
}
finally {
    # 임시 산출물은 진단을 위해 보존한다. 자동 삭제하지 않는다.
}

$successDirectory = Join-Path $temporaryRoot "codex-harness-hook-success-$fixtureId"
$successProject = Join-Path $successDirectory "Assembly-CSharp.csproj"
$successDecoyProject = Join-Path $successDirectory "Other.csproj"
$successSource = Join-Path $successDirectory "Probe.cs"
try {
    New-Item -ItemType Directory -Path $successDirectory -Force | Out-Null
    [System.IO.File]::WriteAllText($successProject, ('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>{0}</TargetFramework></PropertyGroup></Project>' -f $targetFramework))
    [System.IO.File]::WriteAllText($successDecoyProject, '<Project><Broken></Project>')
    [System.IO.File]::WriteAllText($successSource, "public class Probe { }")
    $escapedSource = $successSource.Replace('\', '\\')
    Assert-Exit "Claude 실제 빌드·포맷 성공" (Invoke-NodeHook $buildHook "{`"tool_name`":`"Edit`",`"tool_input`":{`"file_path`":`"$escapedSource`"}}") 0
}
finally {
    # 임시 산출물은 진단을 위해 보존한다. 자동 삭제하지 않는다.
}

$formatDirectory = Join-Path $temporaryRoot "codex-harness-hook-format-$fixtureId"
$formatProject = Join-Path $formatDirectory "Format.csproj"
$formatSource = Join-Path $formatDirectory "Probe.cs"
try {
    New-Item -ItemType Directory -Path $formatDirectory -Force | Out-Null
    [System.IO.File]::WriteAllText($formatProject, ('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>{0}</TargetFramework></PropertyGroup></Project>' -f $targetFramework))
    # 빌드는 통과하지만 공백 규칙을 위반하는 소스로 포맷 실패 경로를 검사한다.
    [System.IO.File]::WriteAllText($formatSource, "public   class Probe{ }")
    $escapedSource = $formatSource.Replace('\', '\\')
    Assert-Exit "Claude 포맷 실패 피드백" (Invoke-NodeHook $buildHook "{`"tool_name`":`"Edit`",`"tool_input`":{`"file_path`":`"$escapedSource`"}}") 2
}
finally {
    # 임시 산출물은 진단을 위해 보존한다. 자동 삭제하지 않는다.
}

$ambiguousDirectory = Join-Path $temporaryRoot "codex-harness-hook-ambiguous-$fixtureId"
$ambiguousProjects = @(
    (Join-Path $ambiguousDirectory "Alpha.csproj"),
    (Join-Path $ambiguousDirectory "Beta.csproj")
)
$ambiguousSource = Join-Path $ambiguousDirectory "Probe.cs"
try {
    New-Item -ItemType Directory -Path $ambiguousDirectory -Force | Out-Null
    foreach ($project in $ambiguousProjects) {
        [System.IO.File]::WriteAllText($project, ('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>{0}</TargetFramework></PropertyGroup></Project>' -f $targetFramework))
    }
    [System.IO.File]::WriteAllText($ambiguousSource, "public class Probe { }")
    $escapedSource = $ambiguousSource.Replace('\', '\\')
    $ambiguousResult = Invoke-NodeHook $buildHook "{`"tool_name`":`"Edit`",`"tool_input`":{`"file_path`":`"$escapedSource`"}}"
    Assert-Exit "Claude 다중 프로젝트 모호성 피드백" $ambiguousResult 2
    if (-not $ambiguousResult.Output.Contains("대상을 결정할 수 없음")) { $failures.Add("Claude 다중 프로젝트 모호성 사유 미보고") }
}
finally {
    # 임시 산출물은 진단을 위해 보존한다. 자동 삭제하지 않는다.
}

# 프로젝트 탐색 경계: Editor 전용 프로젝트, 작업 폴더 밖 상위 프로젝트, Editor 폴더 파일의 대상 선택을 확인한다.
$validProject = ('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>{0}</TargetFramework></PropertyGroup></Project>' -f $targetFramework)
$boundaryRoot = Join-Path $temporaryRoot "codex-harness-hook-boundary-$fixtureId"
$editorOnlyDirectory = Join-Path $boundaryRoot "editor-only"
$outsideDirectory = Join-Path $boundaryRoot "outside"
$outsideWorkspace = Join-Path $outsideDirectory "workspace"
$unityDirectory = Join-Path $boundaryRoot "unity"
try {
    New-Item -ItemType Directory -Path $editorOnlyDirectory, $outsideWorkspace, (Join-Path $unityDirectory "Editor") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $editorOnlyDirectory "Tools.Editor.csproj"), $validProject)
    [System.IO.File]::WriteAllText((Join-Path $editorOnlyDirectory "Probe.cs"), "public class Probe { }")
    [System.IO.File]::WriteAllText((Join-Path $outsideDirectory "Broken.csproj"), "<Project><Broken></Project>")
    [System.IO.File]::WriteAllText((Join-Path $outsideWorkspace "Probe.cs"), "public class Probe { }")
    # 런타임 프로젝트는 깨진 미끼로 두어, 잘못 선택하면 빌드 실패로 드러나게 한다.
    [System.IO.File]::WriteAllText((Join-Path $unityDirectory "Assembly-CSharp.csproj"), "<Project><Broken></Project>")
    [System.IO.File]::WriteAllText((Join-Path $unityDirectory "Assembly-CSharp-Editor.csproj"), $validProject)
    [System.IO.File]::WriteAllText((Join-Path $unityDirectory "Editor\Probe.cs"), "public class Probe { }")

    $editorOnlyInput = @{ tool_name = 'Edit'; tool_input = @{ file_path = (Join-Path $editorOnlyDirectory "Probe.cs") }; cwd = $editorOnlyDirectory } | ConvertTo-Json -Compress
    $editorOnlyResult = Invoke-NodeHook $buildHook $editorOnlyInput
    Assert-Exit "Claude Editor 전용 프로젝트 빌드" $editorOnlyResult 0
    if (-not $editorOnlyResult.Output.Contains("Tools.Editor.csproj")) { $failures.Add("Claude Editor 전용 프로젝트를 대상으로 선택하지 않음") }

    $outsideInput = @{ tool_name = 'Edit'; tool_input = @{ file_path = (Join-Path $outsideWorkspace "Probe.cs") }; cwd = $outsideWorkspace } | ConvertTo-Json -Compress
    $outsideResult = Invoke-NodeHook $buildHook $outsideInput
    Assert-Exit "Claude 작업 폴더 밖 상위 프로젝트 제외" $outsideResult 0
    if (-not $outsideResult.Output.Contains("건너뜀")) { $failures.Add("Claude 작업 폴더 밖 상위 프로젝트를 선택함") }

    $unityInput = @{ tool_name = 'Edit'; tool_input = @{ file_path = (Join-Path $unityDirectory "Editor\Probe.cs") }; cwd = $unityDirectory } | ConvertTo-Json -Compress
    $unityResult = Invoke-NodeHook $buildHook $unityInput
    Assert-Exit "Claude Editor 폴더 파일의 Editor 프로젝트 선택" $unityResult 0
    if (-not $unityResult.Output.Contains("Assembly-CSharp-Editor.csproj")) { $failures.Add("Claude Editor 폴더 파일에 Editor 프로젝트를 선택하지 않음") }
}
finally {
    # 임시 산출물은 진단을 위해 보존한다. 자동 삭제하지 않는다.
}

& $scanTool -Content "public const string Name = 'safe';" *> $null
if ($LASTEXITCODE -ne 0) { $failures.Add("Codex 안전 콘텐츠 오탐") }
& $scanTool -Content "DROP TABLE users;" *> $null
if ($LASTEXITCODE -ne 2) { $failures.Add("Codex 파괴적 SQL 미탐") }
& $scanTool -Content "GITHUB_TOKEN=secret" *> $null
if ($LASTEXITCODE -ne 2) { $failures.Add("Codex 토큰 패턴 미탐") }
Assert-Exit "Codex 안전 patch 허용" (Invoke-PowerShellHook $codexHook '{"tool_name":"apply_patch","tool_input":{"patch":"safe content"}}') 0
Assert-Exit "Codex 파괴적 SQL patch 차단" (Invoke-PowerShellHook $codexHook '{"tool_name":"apply_patch","tool_input":{"patch":"DROP TABLE users;"}}') 2
Assert-Exit "Codex 훅 입력 오류 fail-closed" (Invoke-PowerShellHook $codexHook '{broken') 2

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Output "FAIL: $failure" }
    exit 1
}
Write-Output "PASS: Claude 훅 13건, Codex 콘텐츠 정책·PreToolUse 6건"
