#!/usr/bin/env bash
# 설정만 파일 단위로 설치합니다. --dry-run은 디스크를 변경하지 않습니다.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  --help) echo "사용법: bash $0 [--dry-run]"; exit 0 ;;
  *) echo "지원하지 않는 옵션: $1 (복사 설치만 지원)" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "옵션은 하나만 지정하세요." >&2; exit 2; }
fail() { echo "$*" >&2; exit 1; }
[[ -n "${HOME:-}" && "$HOME" == /* && -d "$HOME" ]] || fail "실제 홈 디렉터리가 필요합니다."
BACKUP_ROOT=""
CHANGED=0

# 쓰기 전에 전체 대상의 링크와 유형을 검사해 외부 원본 수정을 방지합니다.
check_tree() {
  local src="$1" dst="$2" child
  [[ ! -L "$src" ]] || fail "원본 심볼릭 링크는 지원하지 않습니다: $src"
  [[ ! -L "$dst" ]] || fail "기존 심볼릭 링크를 먼저 별도 이관하세요: $dst"
  if [[ -d "$src" ]]; then
    [[ ! -e "$dst" || -d "$dst" ]] || fail "디렉터리 대상에 파일이 있습니다: $dst"
    for child in "$src"/* "$src"/.[!.]* "$src"/..?*; do
      [[ -e "$child" || -L "$child" ]] || continue
      check_tree "$child" "$dst/${child##*/}"
    done
  else
    [[ -f "$src" ]] || fail "필수 원본 파일이 없습니다: $src"
    [[ ! -e "$dst" || -f "$dst" ]] || fail "파일 대상에 다른 유형이 있습니다: $dst"
  fi
}

# 홈 기준 상대 경로를 유지해 백업 원본을 구분합니다.
install_tree() {
  local src="$1" dst="$2" child relative
  if [[ -d "$src" ]]; then
    for child in "$src"/* "$src"/.[!.]* "$src"/..?*; do
      [[ -e "$child" || -L "$child" ]] || continue
      install_tree "$child" "$dst/${child##*/}"
    done
    return
  fi
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then return; fi
  echo "갱신: $dst"
  CHANGED=$((CHANGED + 1))
  [[ "$DRY_RUN" -eq 0 ]] || return 0
  if [[ -f "$dst" ]]; then
    if [[ -z "$BACKUP_ROOT" ]]; then
      BACKUP_ROOT="$(mktemp -d "$HOME/$BACKUP_PREFIX.XXXXXXXX")"
      echo "백업: $BACKUP_ROOT"
    fi
    relative="${dst#"$HOME"/}"
    mkdir -p "$BACKUP_ROOT/$(dirname "$relative")"
    cp -p "$dst" "$BACKUP_ROOT/$relative"
  fi
  mkdir -p "$(dirname "$dst")"
  cp -p "$src" "$dst"
}

check_root() {
  [[ ! -L "$1" ]] || fail "설치 루트가 심볼릭 링크입니다: $1"
  [[ ! -e "$1" || -d "$1" ]] || fail "설치 루트가 디렉터리가 아닙니다: $1"
}

CODEX_DIR="$HOME/.codex"
BACKUP_PREFIX="codex-dotfiles-backup"
[[ -z "${CODEX_HOME:-}" || "$CODEX_HOME" == "$CODEX_DIR" ]] ||
  fail "사용자 지정 CODEX_HOME은 지원하지 않습니다. 기본 홈 설치인지 확인하세요."
check_root "$CODEX_DIR"
check_tree "$REPO/AGENTS.md" "$CODEX_DIR/AGENTS.md"
for item in deny-patterns.yaml harness-policy.json safety-policy.json hooks rules tools; do
  check_tree "$REPO/codex/$item" "$CODEX_DIR/$item"
done
check_tree "$REPO/codex/hooks.json" "$CODEX_DIR/hooks.json"
check_tree "$REPO/settings/config.macos.toml" "$CODEX_DIR/config.toml"
if [[ "$DRY_RUN" -eq 0 ]]; then
  command -v pwsh >/dev/null 2>&1 ||
    fail "PowerShell 7이 필요합니다: brew install powershell (미지원 환경은 Microsoft 공식 macOS 설치 안내 참조)"
fi
install_tree "$REPO/AGENTS.md" "$CODEX_DIR/AGENTS.md"
for item in deny-patterns.yaml harness-policy.json safety-policy.json hooks rules tools; do
  install_tree "$REPO/codex/$item" "$CODEX_DIR/$item"
done
# 기존 훅 설정을 덮어쓰지 않고 병합 필요성을 안내한다.
if [[ -e "$CODEX_DIR/hooks.json" ]]; then
  echo "보존: $CODEX_DIR/hooks.json (새 훅 등록은 별도 비교·병합 필요)"
else
  install_tree "$REPO/codex/hooks.json" "$CODEX_DIR/hooks.json"
fi
if [[ -e "$CODEX_DIR/config.toml" ]]; then
  echo "보존: $CODEX_DIR/config.toml (템플릿과의 병합은 별도 검토)"
else
  install_tree "$REPO/settings/config.macos.toml" "$CODEX_DIR/config.toml"
fi
echo "완료: 변경 대상 $CHANGED 파일, dry-run=$DRY_RUN"
