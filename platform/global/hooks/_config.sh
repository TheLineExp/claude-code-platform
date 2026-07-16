#!/bin/bash
# Shared configuration for all guard hooks — HARDCODED, no config file.
#
# Decision (2026-07-04 audit, batch 2): these values used to come from a per-repo
# platform.config.json that had been deleted, so every hook silently ran on
# fallback defaults — policy by accident. A config-file override is itself a
# silent policy-downgrade vector (any repo could ship mergePolicy:"allow-staging"
# and weaken the guard), so the values are now explicit constants. If policy ever
# needs to change, change it HERE, in the canonical repo, via PR.
#
# Usage: source "$(dirname "$0")/_config.sh"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

PROTECTED_BRANCHES="staging master main"

# Config/data TRUNK repos — NOT product deploy targets. Their `main` is the
# intended direct-push workflow (e.g. the /feature + /todo backlog skills do
# `git commit && push` to main, and the dev-system config lives here), so
# block-protected-branch does NOT gate their deploy branches. Matched by
# origin-remote repo name OR worktree-toplevel basename (see _is_trunk_repo).
# This is the ONE exemption to deploy-branch protection — product repos
# (reservations / Fleetmanager_V3 / vouchers) are never listed here and stay
# fully protected. Space-separated repo names.
TRUNK_REPOS="claude-code-platform"

FEATURE_PREFIX="feature/"
OWNER_PREFIXES="mk"
MERGE_POLICY="block-all"   # agents never merge PRs — doctrine
MAX_WINDOWS=3
