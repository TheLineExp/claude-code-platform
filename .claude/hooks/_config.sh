#!/bin/bash
# Shared configuration loader for all Claude Code hooks.
# Reads platform.config.json and exports shell variables.
# No jq dependency — uses grep/sed for parsing (works on all platforms).
#
# Usage: source "$(dirname "$0")/_config.sh"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG_FILE="$REPO_ROOT/platform.config.json"

# --- JSON parsing helpers (no jq required) ---

_get_json_string() {
  # Extract a string value: "key": "value" → value
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$CONFIG_FILE" 2>/dev/null \
    | head -1 \
    | sed 's/.*"[^"]*"[[:space:]]*:[[:space:]]*"//;s/"$//'
}

_get_json_array() {
  # Extract a JSON array of strings: "key": ["a","b"] → a b (space-separated)
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\[[^]]*\]" "$CONFIG_FILE" 2>/dev/null \
    | head -1 \
    | sed 's/.*\[//;s/\]//;s/"//g;s/,/ /g;s/^[[:space:]]*//;s/[[:space:]]*$//'
}

_get_json_number() {
  # Extract a number value: "key": 3 → 3
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9]*" "$CONFIG_FILE" 2>/dev/null \
    | head -1 \
    | sed 's/.*"[^"]*"[[:space:]]*:[[:space:]]*//'
}

# --- Load configuration ---

if [ ! -f "$CONFIG_FILE" ]; then
  # Sensible defaults if no config file exists
  PROTECTED_BRANCHES="staging master main"
  FEATURE_PREFIX="feature/"
  OWNER_PREFIXES="mk"
  MERGE_POLICY="block-all"
  MAX_WINDOWS=3
  PROJECT_NAME="my-project"
  REPO_DIR="my-project"
else
  PROTECTED_BRANCHES=$(_get_json_array "protected")
  FEATURE_PREFIX=$(_get_json_string "featurePrefix")
  OWNER_PREFIXES=$(_get_json_array "ownerPrefixes")
  MERGE_POLICY=$(_get_json_string "mergePolicy")
  MAX_WINDOWS=$(_get_json_number "maxWindows")
  PROJECT_NAME=$(_get_json_string "name")
  REPO_DIR=$(_get_json_string "repoDir")

  # Apply defaults for any missing values
  : "${PROTECTED_BRANCHES:=staging master main}"
  : "${FEATURE_PREFIX:=feature/}"
  : "${OWNER_PREFIXES:=mk}"
  : "${MERGE_POLICY:=block-all}"
  : "${MAX_WINDOWS:=3}"
  : "${PROJECT_NAME:=my-project}"
  : "${REPO_DIR:=my-project}"
fi
