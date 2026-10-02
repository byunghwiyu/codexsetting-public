$ErrorActionPreference = "Stop"

try {
    $raw = [Console]::In.ReadToEnd()
    $event = $raw | ConvertFrom-Json
}
catch {
    [Console]::Error.WriteLine("[Codex Guard] 훅 입력 파싱 실패 — 안전을 위해 차단합니다: $($_.Exception.Message)")
    exit 2
}

$toolName = if ($event.tool_name) { $event.tool_name } elseif ($event.toolName) { $event.toolName } else { "" }
$toolInput = if ($event.tool_input) { $event.tool_input } elseif ($event.toolInput) { $event.toolInput } else { $event.input }
$chunks = [System.Collections.Generic.List[string]]::new()
$filePath = ""

if ($null -ne $toolInput) {
    foreach ($propertyName in @("command", "cmd", "patch", "content", "new_string", "newString")) {
        $property = $toolInput.PSObject.Properties[$propertyName]
        if ($null -ne $property -and $null -ne $property.Value) { $chunks.Add([string]$property.Value) }
    }
    foreach ($pathName in @("file_path", "filePath", "path")) {
        $property = $toolInput.PSObject.Properties[$pathName]
        if ($null -ne $property -and $null -ne $property.Value) { $filePath = [string]$property.Value; break }
    }
}

if ($chunks.Count -eq 0) { exit 0 }

$scanner = Join-Path (Split-Path -Parent $PSScriptRoot) "tools\scan-content-policy.ps1"
if (-not (Test-Path -LiteralPath $scanner)) {
    [Console]::Error.WriteLine("[Codex Guard] 콘텐츠 검사기를 찾을 수 없어 차단합니다: $scanner")
    exit 2
}

try {
    # 정상 apply_patch 형식은 파일별 추가 줄만 검사해 삭제·문맥 줄의 오탐을 피한다.
    if ($toolName -eq 'apply_patch' -and ($chunks -join "`n").StartsWith('*** Begin Patch')) {
        $added = [System.Collections.Generic.List[string]]::new()
        foreach ($line in (($chunks -join "`n") -split '\r?\n')) {
            if ($line -match '^\*\*\* (?:Add|Update|Delete) File: (.+)$' -or $line -eq '*** End Patch') {
                if ($added.Count -gt 0) {
                    & $scanner -Content ($added -join "`n") -FilePath $filePath
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                    $added.Clear()
                }
                if ($line -ne '*** End Patch') { $filePath = $Matches[1] }
            }
            elseif ($line -match '^\*\*\* Move to: (.+)$') { $filePath = $Matches[1] }
            elseif ($line.StartsWith('+')) { $added.Add($line.Substring(1)) }
            elseif ($line.StartsWith('@@') -and $added.Count -gt 0) {
                & $scanner -Content ($added -join "`n") -FilePath $filePath
                if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                $added.Clear()
            }
        }
        if ($added.Count -gt 0) {
            & $scanner -Content ($added -join "`n") -FilePath $filePath
            exit $LASTEXITCODE
        }
        exit 0
    }
    & $scanner -Content ($chunks -join "`n") -FilePath $filePath
    exit $LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine("[Codex Guard] 콘텐츠 검사 실패 — 안전을 위해 차단합니다: $($_.Exception.Message)")
    exit 2
}
