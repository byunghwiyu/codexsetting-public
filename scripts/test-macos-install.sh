#!/usr/bin/env bash
# 실제 홈 대신 임시 복사본을 사용한다. 검사 산출물은 진단용으로 보존한다.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_REPO="${1:-$REPO/../claude}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/public-shell-install.XXXXXXXX")"
CODEX_FIXTURE="$TEST_ROOT/codex"
CLAUDE_FIXTURE="$TEST_ROOT/claude"
cp -R "$REPO" "$CODEX_FIXTURE"
cp -R "$CLAUDE_REPO" "$CLAUDE_FIXTURE"
TEST_HOME="$TEST_ROOT/home 한글 & \$literal"
mkdir -p "$TEST_HOME"
fail() { echo "FAIL: $*" >&2; exit 1; }
native_home() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$TEST_HOME"; else printf '%s' "$TEST_HOME"; fi; }
run_codex() { env -u CODEX_HOME -u CLAUDE_CONFIG_DIR HOME="$TEST_HOME" USERPROFILE="$(native_home)" bash "$CODEX_FIXTURE/scripts/install-macos.sh" "$@"; }
run_claude() { env -u CODEX_HOME -u CLAUDE_CONFIG_DIR HOME="$TEST_HOME" USERPROFILE="$(native_home)" bash "$CLAUDE_FIXTURE/install-macos.sh" "$@"; }
snapshot() { (cd "$TEST_HOME"; find . -print | LC_ALL=C sort; find . -type f -exec cksum {} \; | LC_ALL=C sort); }
assert_text() { [[ "$(cat "$1")" == "$2" ]] || fail "$1 내용"; }
before="$(snapshot)"
run_claude --print-settings > "$TEST_ROOT/settings.json"
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$TEST_ROOT/settings.json"
run_claude --dry-run > "$TEST_ROOT/claude-dry.log"
run_codex --dry-run > "$TEST_ROOT/codex-dry.log"
[[ "$before" == "$(snapshot)" ]] || fail "dry-run 또는 설정안 출력이 홈 변경"
run_claude > "$TEST_ROOT/claude-install.log"
run_codex > "$TEST_ROOT/codex-install.log"
[[ -f "$TEST_HOME/.claude/settings.json" && -f "$TEST_HOME/.codex/config.toml" ]] || fail "신규 설정 누락"
[[ ! -e "$TEST_HOME/.claude/skills" && ! -e "$TEST_HOME/.codex/skills" && ! -e "$TEST_HOME/.agents" ]] || fail "핵심 범위 외 설치"
[[ ! -e "$TEST_HOME/.claude/mcp.json" && ! -e "$TEST_HOME/.claude/work-history" ]] || fail "MCP·개인 기록 자동 설치"
before="$(snapshot)"
run_claude > "$TEST_ROOT/claude-repeat.log"
run_codex > "$TEST_ROOT/codex-repeat.log"
[[ "$before" == "$(snapshot)" ]] || fail "재실행 비멱등"
echo "PASS: 신규 설치·미리보기·핵심 범위·멱등성"

printf 'personal-config\n' > "$TEST_HOME/.codex/config.toml"
printf 'personal-hooks\n' > "$TEST_HOME/.codex/hooks.json"
printf '{"personal":true}\n' > "$TEST_HOME/.claude/settings.json"
printf 'private-fixture\n' > "$TEST_HOME/.claude/.credentials.json"
printf 'old-codex\n' > "$TEST_HOME/.codex/AGENTS.md"
printf 'old-claude\n' > "$TEST_HOME/.claude/CLAUDE.md"
run_claude > "$TEST_ROOT/claude-update.log"
run_codex > "$TEST_ROOT/codex-update.log"
assert_text "$TEST_HOME/.codex/config.toml" personal-config
assert_text "$TEST_HOME/.codex/hooks.json" personal-hooks
assert_text "$TEST_HOME/.claude/settings.json" '{"personal":true}'
assert_text "$TEST_HOME/.claude/.credentials.json" private-fixture
codex_backups=("$TEST_HOME"/codex-dotfiles-backup.*)
claude_backups=("$TEST_HOME"/claude-dotfiles-backup.*)
[[ ${#codex_backups[@]} -eq 1 && ${#claude_backups[@]} -eq 1 ]] || fail "백업 개수"
assert_text "${codex_backups[0]}/.codex/AGENTS.md" old-codex
assert_text "${claude_backups[0]}/.claude/CLAUDE.md" old-claude
[[ ! -e "${claude_backups[0]}/.claude/.credentials.json" ]] || fail "인증 백업 포함"
before="$(snapshot)"
run_claude > "$TEST_ROOT/claude-stable.log"
run_codex > "$TEST_ROOT/codex-stable.log"
[[ "$before" == "$(snapshot)" ]] || fail "기존 설정 재설치 비멱등"
cp "${codex_backups[0]}/.codex/AGENTS.md" "$TEST_HOME/.codex/AGENTS.md"
cp "${claude_backups[0]}/.claude/CLAUDE.md" "$TEST_HOME/.claude/CLAUDE.md"
assert_text "$TEST_HOME/.codex/AGENTS.md" old-codex
assert_text "$TEST_HOME/.claude/CLAUDE.md" old-claude
echo "PASS: 기존 설정·인증 보존, 백업 분리·복구"

mkdir -p "$TEST_HOME/.codex/tools/new.txt"
printf 'new\n' > "$CODEX_FIXTURE/codex/tools/new.txt"
before="$(snapshot)"
if run_codex > "$TEST_ROOT/conflict.log" 2>&1; then fail "유형 충돌 허용"; fi
[[ "$before" == "$(snapshot)" ]] || fail "충돌 전 부분 설치"
if run_claude --symlink > "$TEST_ROOT/option.log" 2>&1; then fail "잘못된 옵션 허용"; fi
if env CODEX_HOME="$TEST_ROOT/custom" HOME="$TEST_HOME" bash "$CODEX_FIXTURE/scripts/install-macos.sh" > "$TEST_ROOT/custom.log" 2>&1; then fail "사용자 지정 홈 무시"; fi
[[ "$before" == "$(snapshot)" ]] || fail "오류 시 홈 변경"
echo "PASS: 유형 충돌·지원하지 않는 옵션·사용자 지정 홈 사전 차단"

# 복사된 실제 설정의 명령을 더미 훅으로 실행해 특수문자 경로만 검증한다.
TEST_HOME="$TEST_ROOT/hook 한글 & \$literal"
mkdir -p "$TEST_HOME/.claude/hooks"
printf 'process.stdout.write("HOOK_OK");\n' > "$TEST_HOME/.claude/hooks/validate-deny.js"
printf 'process.stdout.write("HOOK_OK");\n' > "$TEST_HOME/.claude/hooks/post_edit_build.js"
for event in PreToolUse PostToolUse; do
  command_text="$(node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(v.hooks[process.argv[2]][0].hooks[0].command)' "$CLAUDE_REPO/settings.macos.json" "$event")"
  [[ "$(env HOME="$TEST_HOME" USERPROFILE="$(native_home)" bash -c "$command_text")" == HOOK_OK ]] || fail "$event 특수문자 홈"
done
echo "PASS: 실제 설정의 훅 명령과 공백·한글·달러 기호 홈"

TEST_HOME="$TEST_ROOT/link-home"
mkdir -p "$TEST_HOME" "$TEST_ROOT/external"
ln -s "$TEST_ROOT/external" "$TEST_HOME/.claude" 2>/dev/null || true
if [[ -L "$TEST_HOME/.claude" ]]; then
  if run_claude > "$TEST_ROOT/link.log" 2>&1; then fail "심볼릭 링크 허용"; fi
  [[ -z "$(find "$TEST_ROOT/external" -type f -print)" ]] || fail "링크 외부 파일 변경"
  echo "PASS: 실제 심볼릭 링크 대상 거부"
else
  echo "SKIP: 이 환경은 실제 심볼릭 링크를 생성하지 못함"
fi
echo "검사 산출물: $TEST_ROOT"
