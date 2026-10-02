# Codex 공개용 설정

Codex의 작업 지침·정책·훅·설치기를 공유하는 저장소입니다.
**초기 공개본이며 [MIT 라이선스](LICENSE)로 배포합니다.** 아래 로컬 검증 범위와 알려진 한계를 확인한 뒤 사용 환경에 맞게 검토하세요.

## 현재 포함된 파일

- [.gitattributes](.gitattributes)
- [.gitignore](.gitignore)
- [AGENTS.md](AGENTS.md)
- [codex/deny-patterns.yaml](codex/deny-patterns.yaml)
- [codex/harness-policy.json](codex/harness-policy.json)
- [codex/hooks/pre_tool_use_content_guard.ps1](codex/hooks/pre_tool_use_content_guard.ps1)
- [codex/hooks.json](codex/hooks.json)
- [codex/rules/deny.rules](codex/rules/deny.rules)
- [codex/safety-policy.json](codex/safety-policy.json)
- [codex/tools/scan-content-policy.ps1](codex/tools/scan-content-policy.ps1)
- [codex/tools/sync-deny-policy.ps1](codex/tools/sync-deny-policy.ps1)
- [codex/tools/sync-global-safety-policy.ps1](codex/tools/sync-global-safety-policy.ps1)
- [codex/tools/sync-harness-rules.ps1](codex/tools/sync-harness-rules.ps1)
- [codex/tools/test-content-guard.ps1](codex/tools/test-content-guard.ps1)
- [codex/tools/test-deny-policy.ps1](codex/tools/test-deny-policy.ps1)
- [codex/tools/test-global-guards.ps1](codex/tools/test-global-guards.ps1)
- [codex/tools/test-harness-parity.ps1](codex/tools/test-harness-parity.ps1)
- [codex/tools/validate-harness-parity.ps1](codex/tools/validate-harness-parity.ps1)
- [LICENSE](LICENSE)
- `README.md`: 이 안내
- [scripts/install-macos.sh](scripts/install-macos.sh)
- [scripts/install-windows.ps1](scripts/install-windows.ps1)
- [scripts/test-macos-install.sh](scripts/test-macos-install.sh)
- [scripts/test-windows-install.ps1](scripts/test-windows-install.ps1)
- [SECURITY.md](SECURITY.md)
- [settings/config.macos.toml](settings/config.macos.toml)
- [settings/config.windows.toml](settings/config.windows.toml)
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

## 설정 예시의 기본값

두 설정 예시는 일반 추론 강도 `medium`, 계획 모드 추론 강도 `high`와 터미널 상태 표시 항목을 담고 있습니다.
모델은 고정하지 않으며, 플러그인·실험 기능을 활성화하는 항목도 포함하지 않습니다.
추론 강도는 사용하는 모델이 지원하는지 확인하고 필요한 항목만 기존 개인 설정에 병합합니다.

Windows 예시에는 `windows.sandbox = "elevated"`가 있습니다. macOS 예시에는 Windows 설정을 넣지 않았습니다.
Unity MCP 블록은 주석으로만 제공하며 실제 개인 경로 대신 예시 경로를 사용합니다.
주석을 해제해도 `enabled = false` 상태이므로, 브리지를 설치하고 경로를 수정한 뒤 연결을 원할 때만 활성화합니다.

예시는 [공식 설정 문서](https://learn.chatgpt.com/docs/config-file/config-reference)와
[공식 설정 스키마](https://learn.chatgpt.com/docs/config-schema.json)를 기준으로 검토했습니다.
계정별 기능 사용 가능 여부나 실제 앱 동작을 보장하는 검증은 아닙니다.

## 설치와 기존 설정 보존

기본 `~/.codex` 또는 Windows 사용자 홈의 `.codex`에 핵심 파일만 복사합니다. 스킬·템플릿·`.agents`·Unity MCP는 설치하지 않습니다.
기존 `config.toml`과 `hooks.json`은 보존합니다. 새 설정·훅이 필요하면 배포 예시와 비교해 기존 파일에 필요한 항목만 병합합니다.

**기존 지침은 병합되지 않습니다.** `AGENTS.md`, 배포 대상 정책 파일, `hooks/`·`rules/`·`tools/` 안의 동일 상대 경로 파일은 내용이 다르면 백업 후 교체합니다. 배포본에 없는 개인 파일은 보존합니다. 먼저 dry-run으로 교체 대상을 확인하고 아래 복구 절차를 읽으세요.

Windows에서는 저장소 루트에서 실행합니다.

```powershell
powershell -NoProfile -File .\scripts\install-windows.ps1 -DryRun
powershell -NoProfile -File .\scripts\install-windows.ps1
```

macOS에서는 PowerShell 7(`pwsh`)과 Bash를 준비한 뒤 저장소 루트에서 실행합니다.

```bash
bash scripts/install-macos.sh --dry-run
bash scripts/install-macos.sh
```

설치 전에 Codex 설치·로그인을 완료합니다. 훅 실행에는 PowerShell이 필요하고, Claude C# 통합 검사에는 Node.js와 .NET SDK도 필요합니다.
기본 홈과 다른 `CODEX_HOME`, 링크·정션 대상, 파일·폴더 유형 충돌은 쓰기 전에 거부합니다.
Windows 설치기의 `-HomeDirectory`는 검사용 별도 홈을 지정할 수 있지만, 실행 중인 Codex의 홈을 바꾸는 옵션은 아닙니다.
자동 검사만으로 실제 앱의 훅 등록·호출을 보증하지 않으므로 설치 후 사용하는 버전에서 확인합니다.

## 포함하지 않는 자료

대화·세션 기록, 작업 계획, 사용자 메모리, 실제 프로젝트 자료, 인증 정보, 개인 PC 설정은 배포하지 않습니다.
기존 개인 백업 저장소의 Git 이력도 가져오지 않습니다.

스킬·프로젝트 템플릿은 핵심 설정과 분리해 검토합니다. 출처, 배포 조건, 필수 참조와 실행 의존성을 확인한 항목만 후속 공개 대상으로 삼습니다.

## 지원 환경과 검증 상태

2026-10-02 기준 확인한 범위입니다.

- Windows PowerShell 5.1·7: Codex 설치·dry-run·기존 설정과 인증 파일 보존·백업 복구·재설치 무변경·충돌 사전 차단·정션 거부
- Git Bash: 양쪽 설치기의 같은 핵심 시나리오와 특수문자 홈에서의 Claude 훅 명령
- 콘텐츠 가드 30건(BOM·한글 입력 포함), 안전 정책 생성·필수 규칙·반복 생성 일치
- Claude와 함께 격리된 홈에서 통합 훅 16건, 하네스 필수 항목 8개·충돌 규칙 3개·누락 감지
- OS별 TOML과 공식 스키마, 기본 설정 2건 및 비활성 MCP 예시 2건
- `.gitignore` 62개 경로와 Git 줄바꿈 속성 8건, 한글·로컬 참조 검사

저장소 루트에서 사용자 홈을 변경하지 않고 실행할 수 있는 검사는 다음과 같습니다.

```powershell
pwsh -NoProfile -File ./codex/tools/test-deny-policy.ps1 -CodexHome ./codex
pwsh -NoProfile -File ./codex/tools/test-content-guard.ps1 -CodexHome ./codex
powershell -NoProfile -File ./scripts/test-windows-install.ps1
```

마지막 명령은 Windows 전용입니다. 셸 설치 검사는 Claude 공개본 경로를 인수로 받습니다.

```bash
# ../claude를 실제 Claude 공개본 경로로 바꿉니다.
bash scripts/test-macos-install.sh ../claude
```

통합 빌드 검사도 경로를 지정해 실행합니다.

```powershell
pwsh -NoProfile -File ./codex/tools/test-global-guards.ps1 -CodexHome ./codex -ClaudeHome ../claude
```

검사 산출물은 진단용 임시 폴더에 남을 수 있습니다. 파괴적 명령과 키 형태는 가상 입력이며 실제 실행·인증에 쓰지 않습니다.
macOS 실기기와 실제 Codex 앱의 훅 호출은 미검증입니다. Git Bash의 실제 심볼릭 링크 검사는 환경 제약으로 건너뛰었습니다.
Windows 정션 검사는 통과했지만 이를 macOS 심볼릭 링크 검사로 대신하지 않습니다.

기존 검사는 제한된 입력 사례에 대한 결과입니다. 추가 검토에서 정책 오류 처리·명령 옵션 순서·일부 콘텐츠 형식의 탐지 누락과 문서 오탐이 확인되어 개선 중입니다. Windows PowerShell 5.1에서 콘솔 코드페이지에 따라 BOM이 붙거나 한글이 포함된 정상 입력까지 차단되던 문제는 훅이 입력을 UTF-8로 읽도록 수정했고, 코드페이지 949·65001에서 30건을 확인했습니다. PowerShell 7과 실제 앱 호출은 따로 확인하며, 설치 성공을 훅 작동 확인으로 간주하지 않습니다. 보호 범위는 [보안 안내](SECURITY.md)를 확인하세요.

## 업데이트와 복구

새 버전을 받은 뒤 dry-run을 확인하고 같은 설치기를 다시 실행합니다. 동일한 파일에는 쓰기·추가 백업이 발생하지 않습니다.
변경되는 기존 파일은 `codex-dotfiles-backup.<식별자>/.codex/` 아래 원래 상대 경로로 백업합니다.
기존 `config.toml`, `hooks.json`과 인증·개인 파일은 덮어쓰지 않습니다. 제거된 배포 파일도 설치기가 자동 삭제하지 않습니다.

복구할 때는 출력된 백업 폴더에서 필요한 파일만 되돌립니다. 복구 대상의 현재 내용도 필요하면 먼저 별도 보관합니다.

```powershell
# 실제 백업 식별자로 바꾼 뒤 실행합니다.
$backupPath = Join-Path $env:USERPROFILE 'codex-dotfiles-backup.실제식별자'
Copy-Item -LiteralPath (Join-Path $backupPath '.codex/AGENTS.md') -Destination (Join-Path $env:USERPROFILE '.codex/AGENTS.md')
```

macOS에서는 같은 백업 상대 경로의 파일을 `cp -p`로 복구합니다. 백업은 전체 홈 복제본이 아니며 신규 파일의 자동 제거 기능은 없습니다.

## 두 공개 저장소의 관계

각각의 설치기와 기본 검사는 단독으로 사용할 수 있습니다. 공통 안전 정책의 원본·생성 도구와 양쪽 정합성 검사는 Codex 공개본에서 관리합니다.
Claude만 설치하는 사용자는 생성된 정책을 사용하며, 패턴을 변경하려면 Codex 공개본의 원본과 생성 도구를 함께 준비합니다.
`test-harness-parity.ps1`은 양쪽 설치의 정합성을 검사하는 도구이므로 두 하네스가 모두 있는 환경에서 사용합니다.
관련 저장소: [Codex 공개본](https://github.com/byunghwiyu/codexsetting-public), [Claude 공개본](https://github.com/byunghwiyu/claudesetting-public).

## 개인 설정 관리

실제 인증 정보와 개인 경로는 이 저장소 밖의 사용자 설정에 보관합니다.
환경 파일 예시를 추가할 때는 `.env.example`, `.env.sample`, `.env.template` 중 하나를 사용하고 실제 값을 넣지 않습니다.

`.gitignore`는 Git에 아직 추가하지 않은 파일의 기본 제외 규칙입니다. 이미 추적한 파일이나 과거 커밋의 정보를 제거하지 않으며,
허용된 파일 안에 들어간 민감정보를 탐지하지도 않습니다. 배포 전에 파일 내용과 Git 이력을 별도로 확인합니다.

## 라이선스와 외부 구성요소

직접 작성한 코드·문서는 [MIT 라이선스](LICENSE)로 배포합니다. 별도 설치 도구와 외부 구성요소에는 각 배포처의 조건이 적용됩니다.
포함·제외한 외부 구성은 [외부 구성요소 안내](THIRD_PARTY_NOTICES.md), 보호 범위와 제보 채널 준비 상태는 [보안 안내](SECURITY.md)를 참고합니다.
