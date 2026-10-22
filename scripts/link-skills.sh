#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# link-skills.sh -- expose the tool-agnostic skills in skills/ to AI coding
# agents that look for them in their own directory.
#
# The single source of truth is skills/<name>/SKILL.md (Agent Skills format,
# https://agentskills.io). Each agent discovers project skills in a different
# folder, so this script creates <agent-dir>/skills -> ../skills symlinks
# (or copies, with --copy, for environments without symlinks such as some
# Windows setups).
#
# Usage:
#   scripts/link-skills.sh                 # default set: claude agents kiro
#   scripts/link-skills.sh all             # every known agent directory
#   scripts/link-skills.sh cursor copilot  # specific agents
#   scripts/link-skills.sh --copy all      # copy instead of symlink
#   scripts/link-skills.sh --list          # show agents and their directories
#
# Re-running is safe: existing links are replaced, existing real directories
# are left alone unless --force is given.
# ------------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# agent -> directory that should contain skills/
# Verify against each vendor's docs; these are the documented/common locations.
agent_dir() {
  case "$1" in
    claude)   echo ".claude" ;;        # Claude Code:        .claude/skills/
    agents)   echo ".agents" ;;        # Codex CLI, Gemini CLI, Cursor, Copilot (shared convention): .agents/skills/
    kiro)     echo ".kiro" ;;          # Kiro:               .kiro/skills/
    cursor)   echo ".cursor" ;;        # Cursor:             .cursor/skills/
    copilot)  echo ".github" ;;        # GitHub Copilot:     .github/skills/
    gemini)   echo ".gemini" ;;        # Gemini CLI:         .gemini/skills/
    codex)    echo ".codex" ;;         # Codex CLI (older builds): .codex/skills/
    *)        return 1 ;;
  esac
}
ALL_AGENTS="claude agents kiro cursor copilot gemini codex"
DEFAULT_AGENTS="claude agents kiro"

MODE=link
FORCE=0
AGENTS=()
for arg in "$@"; do
  case "$arg" in
    --copy)  MODE=copy ;;
    --force) FORCE=1 ;;
    --list)
      printf '%-8s %s\n' AGENT DIRECTORY
      for a in $ALL_AGENTS; do printf '%-8s %s/skills\n' "$a" "$(agent_dir "$a")"; done
      exit 0 ;;
    all)     for a in $ALL_AGENTS; do AGENTS+=("$a"); done ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *)       AGENTS+=("$arg") ;;
  esac
done
if [[ ${#AGENTS[@]} -eq 0 ]]; then for a in $DEFAULT_AGENTS; do AGENTS+=("$a"); done; fi

[[ -d skills ]] || { echo "error: skills/ directory not found at $REPO_ROOT" >&2; exit 1; }

for a in "${AGENTS[@]}"; do
  dir="$(agent_dir "$a")" || { echo "error: unknown agent '$a' (try --list)" >&2; exit 2; }
  target="$dir/skills"
  mkdir -p "$dir"
  if [[ -L "$target" ]]; then
    rm "$target"
  elif [[ -e "$target" ]]; then
    if [[ $FORCE -eq 1 ]]; then rm -rf "$target"; else
      echo "skip  $target exists and is not a symlink (use --force to replace)"; continue
    fi
  fi
  if [[ $MODE == link ]]; then
    ln -s ../skills "$target"
    echo "link  $target -> ../skills"
  else
    cp -R skills "$target"
    echo "copy  skills/ -> $target/"
  fi
done
