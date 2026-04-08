# Setup Guide

## Prerequisites

- Git (2.20+)
- Claude Code CLI or VS Code extension
- Bash shell (macOS/Linux native, Windows via Git Bash or MSYS2)

## Installation

### Option 1: GitHub Template (Recommended)

1. Click "Use this template" on GitHub
2. Clone your new repo
3. Run `bash setup.sh`

### Option 2: Clone and Configure

```bash
git clone https://github.com/TheLineExp/claude-code-platform.git my-project
cd my-project
bash setup.sh
```

### Option 3: Add to Existing Repo

Copy these directories into your existing repo:
- `.claude/` (hooks, skills, agents, settings)
- `hooks/` (git hooks)
- `platform.config.json`
- `CLAUDE.md`

Then run `bash hooks/install.sh`.

## Platform-Specific Notes

### Windows (Git Bash / MSYS2)

The platform handles Windows path normalization automatically (`C:\` → `/c/`). Git Bash is required — PowerShell is not supported for hooks.

Verify Git Bash is working:
```bash
which bash  # Should return /usr/bin/bash or similar
```

### macOS

Works out of the box. If using Homebrew git, ensure hooks are executable:
```bash
chmod +x .claude/hooks/*.sh hooks/*
```

### Linux

Works out of the box. Same chmod step if needed.

## Post-Setup

1. **Review CLAUDE.md** — add your project-specific rules in the "Project Rules" section
2. **Create addon files** — see [CUSTOMIZATION.md](CUSTOMIZATION.md) for project-specific checks
3. **Copy settings.local.json.example** to `.claude/settings.local.json` for personal overrides
4. **Run `/letsbuild`** in Claude Code to verify everything works

## Verification

```bash
# Verify hooks are installed
bash hooks/verify.sh

# Verify platform config
cat platform.config.json

# Verify Claude settings
cat .claude/settings.json | head -20
```
