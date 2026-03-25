# Claude Container Distribution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate claude-container into a distributable git repo with layered config, build-arg toggles, settings overlay, and submodule-ready structure (Migration Step 1 from the design spec).

**Architecture:** Business-agents copy is the baseline. Strip project-specific content, add build-arg toggles to Dockerfile, implement config layering (build.conf + build.local.conf, settings + settings.local), rewrite bin scripts for submodule model, add documentation.

**Tech Stack:** Bash, Docker, docker-compose, jq (for settings merge), git submodules

**Spec:** `docs/superpowers/specs/2026-03-25-claude-container-distribution-design.md`

**Important:** This is a shell/Docker/config project. "Tests" are verification steps (build image, start container, check behavior). Not a traditional TDD codebase.

---

### Task 1: Foundation — .gitignore, build.conf, .env.example

**Files:**
- Modify: `.gitignore`
- Create: `build.conf`
- Modify: `.env.example`

- [ ] **Step 1: Update .gitignore**

Replace current `.gitignore` with:

```
.env
build.local.conf
settings.container.local.json
.DS_Store
.archived/
```

Note: `settings.container.json` and `build.conf` are now **tracked**.

- [ ] **Step 2: Create build.conf with defaults**

```ini
# Build configuration — template defaults
# Override per-project in build.local.conf (gitignored)
INSTALL_PHP=false
INSTALL_PYTHON=true
INSTALL_COMPOSER=false
```

- [ ] **Step 3: Update .env.example**

```
# ── Authentication (choose ONE) ──
# Auth is managed inside the container via: claude auth login
# The token persists in the claude-config Docker volume.
# Only set these if you want to override container auth:
# ANTHROPIC_API_KEY=sk-ant-...
# CLAUDE_CODE_OAUTH_TOKEN=sk-...

# ── Ecosystem (optional) ──
CLAUDE_ECOSYSTEM_PATH=~/claude-ecosystem

# ── Project (REQUIRED) ──
COMPOSE_PROJECT_NAME=myproject

# ── Options ──
# SKIP_UPDATE_CHECK=1
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore build.conf .env.example
git commit -m "feat: add build.conf, update .gitignore for submodule model"
```

---

### Task 2: Dockerfile — Build-arg toggles

**Files:**
- Modify: `Dockerfile`

Baseline: `/Users/andre/Git-repo/python/business-agents/claude-container/Dockerfile`

- [ ] **Step 1: Copy baseline Dockerfile from business-agents**

```bash
cp /Users/andre/Git-repo/python/business-agents/claude-container/Dockerfile /Users/andre/claude-container/Dockerfile
```

- [ ] **Step 2: Add build args and make PHP/Composer/Python conditional**

Replace the unconditional `apt-get install` block and composer/tool installs with build-arg-toggled versions. The Dockerfile should:

1. Declare args after `FROM`:
```dockerfile
FROM node:20-bookworm-slim

ARG INSTALL_PHP=false
ARG INSTALL_PYTHON=true
ARG INSTALL_COMPOSER=false
```

2. Split package installation into always-installed base packages and conditional groups:
```dockerfile
# Always-installed base packages
RUN apt-get update && apt-get install -y \
    git curl sudo ca-certificates \
    ripgrep fd-find jq tree htop unzip zsh \
    iptables ipset dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Conditional: Python
RUN if [ "$INSTALL_PYTHON" = "true" ]; then \
    apt-get update && apt-get install -y \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*; \
    fi

# Conditional: PHP
RUN if [ "$INSTALL_PHP" = "true" ]; then \
    apt-get update && apt-get install -y \
    php-cli php-mbstring php-xml php-curl php-zip php-intl \
    && rm -rf /var/lib/apt/lists/*; \
    fi

# Conditional: Composer (requires PHP)
RUN if [ "$INSTALL_COMPOSER" = "true" ]; then \
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer; \
    fi

# UV (Python package manager) — only if Python installed
RUN if [ "$INSTALL_PYTHON" = "true" ]; then \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh || true; \
    fi
```

3. Update the COPY line for the npm updater script:
```dockerfile
COPY bin/firewall /usr/local/bin/init-firewall
COPY bin/entrypoint /usr/local/bin/entrypoint
COPY bin/update-packages /usr/local/bin/update-packages
```

4. Keep everything else unchanged (user setup, Claude install, GSD install, entrypoint, etc.)

Note: build args (`INSTALL_*`) go at the top after `FROM`. The existing `USERNAME`/`USER_UID`/`USER_GID` args stay where they are.

- [ ] **Step 3: Verify Dockerfile builds**

```bash
cd /Users/andre/claude-container
docker build --build-arg INSTALL_PHP=false --build-arg INSTALL_PYTHON=true --build-arg INSTALL_COMPOSER=false -t claude-container-test .
```

Expected: successful build, no PHP/Composer installed.

- [ ] **Step 4: Verify with PHP enabled**

```bash
docker build --build-arg INSTALL_PHP=true --build-arg INSTALL_PYTHON=true --build-arg INSTALL_COMPOSER=true -t claude-container-test-php .
docker run --rm claude-container-test-php php -v
docker run --rm claude-container-test-php composer --version
```

Expected: PHP and Composer versions printed.

- [ ] **Step 5: Clean up test images and commit**

```bash
docker rmi claude-container-test claude-container-test-php 2>/dev/null || true
git add Dockerfile
git commit -m "feat: add build-arg toggles for PHP, Python, Composer"
```

---

### Task 3: compose-args — Build config reading and build-arg passing

**Files:**
- Modify: `bin/compose-args`

Baseline: `/Users/andre/Git-repo/python/business-agents/claude-container/bin/compose-args`

- [ ] **Step 1: Copy baseline from business-agents**

```bash
cp /Users/andre/Git-repo/python/business-agents/claude-container/bin/compose-args /Users/andre/claude-container/bin/compose-args
chmod +x /Users/andre/claude-container/bin/compose-args
```

- [ ] **Step 2: Add build.conf reading and build-arg generation**

Add after the `COMPOSE_FILES` setup, before `build_images()`:

```bash
# ── Load build config (base + local overlay) ──
BUILD_ARGS=""
load_build_config() {
    # Source defaults
    [ -f "build.conf" ] && source "build.conf"
    # Overlay local overrides (wins on collision)
    [ -f "build.local.conf" ] && source "build.local.conf"

    # Collect all INSTALL_* vars as build args
    BUILD_ARGS=""
    for var in INSTALL_PHP INSTALL_PYTHON INSTALL_COMPOSER; do
        val="${!var}"
        [ -n "$val" ] && BUILD_ARGS="$BUILD_ARGS --build-arg $var=$val"
    done
}

load_build_config
```

- [ ] **Step 3: Update build_images() to pass BUILD_ARGS**

Modify the `docker compose build` and `docker build` calls to include `$BUILD_ARGS`:

```bash
build_images() {
    local cache_flag=""
    [ "${1:-}" = "--no-cache" ] && cache_flag="--no-cache"

    docker compose -f docker-compose.yml build $cache_flag $BUILD_ARGS

    if [ -f "../workspace/Dockerfile" ]; then
        local base_image
        base_image=$(docker compose -f docker-compose.yml config --images 2>/dev/null | head -1)

        echo "Extending with workspace Dockerfile..."
        docker build $cache_flag $BUILD_ARGS \
            --build-arg BASE_IMAGE="$base_image" \
            -t "$base_image" \
            -f "../workspace/Dockerfile" \
            "../workspace"
        echo "   Image extended: $base_image"
    fi
}
```

- [ ] **Step 4: Commit**

```bash
git add bin/compose-args
git commit -m "feat: compose-args reads build.conf + build.local.conf, passes build-args"
```

---

### Task 4: settings.container.json — Strip to template defaults

**Files:**
- Modify: `settings.container.json`
- Delete: `settings.container.json.example`

- [ ] **Step 1: Write clean template settings.container.json**

Strip PHP-specific hooks and project-specific MCP servers. Keep only universal template defaults:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"/home/node/.claude/hooks/gsd-check-update.js\""
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "node \"/home/node/.claude/hooks/gsd-statusline.js\""
  }
}
```

No permissions (YOLO mode). No PHP hooks (project-specific). No MCP servers disabled by default (projects enable via local overlay).

- [ ] **Step 2: Delete settings.container.json.example**

No longer needed — the tracked `settings.container.json` IS the example/default.

```bash
rm -f settings.container.json.example
```

- [ ] **Step 3: Commit**

```bash
git add settings.container.json
git rm settings.container.json.example 2>/dev/null || true
git commit -m "feat: strip settings.container.json to universal template defaults"
```

---

### Task 5: docker-compose.yml — Mount local settings overlay

**Files:**
- Modify: `docker-compose.yml`

Baseline: `/Users/andre/Git-repo/python/business-agents/claude-container/docker-compose.yml`

- [ ] **Step 1: Copy baseline from business-agents**

```bash
cp /Users/andre/Git-repo/python/business-agents/claude-container/docker-compose.yml /Users/andre/claude-container/docker-compose.yml
```

- [ ] **Step 2: Add settings.container.local.json mount**

The file must exist on the host before Docker tries to mount it, otherwise Docker creates an empty directory (which breaks things). `bin/start` (Task 9) creates an empty `{}` file if missing.

Update the volumes section:

```yaml
      # ── Settings (merged by entrypoint) ──
      - ./settings.container.json:/home/node/.claude/settings.container.json:ro
      - ./settings.container.local.json:/home/node/.claude/settings.container.local.json:ro
```

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: mount settings.container.local.json for project overlay"
```

---

### Task 6: Entrypoint — Settings merge + workspace/bin PATH

**Files:**
- Modify: `bin/entrypoint`

Baseline: `/Users/andre/Git-repo/python/business-agents/claude-container/bin/entrypoint`

- [ ] **Step 1: Copy baseline from business-agents**

```bash
cp /Users/andre/Git-repo/python/business-agents/claude-container/bin/entrypoint /Users/andre/claude-container/bin/entrypoint
chmod +x /Users/andre/claude-container/bin/entrypoint
```

- [ ] **Step 2: Add settings merge logic**

Replace the simple `cp` of `settings.container.json` with a merge. Add this after the ecosystem wiring section (section 1) and before GSD install (section 2):

```bash
# ---------------------------------------------------------------
# 1b. Merge settings (template + local overlay)
# ---------------------------------------------------------------
SETTINGS_BASE="$CLAUDE_HOME/settings.container.json"
SETTINGS_LOCAL="$CLAUDE_HOME/settings.container.local.json"
SETTINGS_OUT="$CLAUDE_HOME/settings.json"

if [ -f "$SETTINGS_BASE" ]; then
    if [ -f "$SETTINGS_LOCAL" ] && [ -s "$SETTINGS_LOCAL" ]; then
        echo "   Merging settings (base + local overlay)..."
        # jq merge: hooks arrays are concatenated, MCP servers local-wins-per-key, scalars local-wins
        jq -s '
          def merge_hooks:
            if (.[0].hooks // {}) == {} and (.[1].hooks // {}) == {} then {}
            elif (.[1].hooks // {}) == {} then {hooks: .[0].hooks}
            elif (.[0].hooks // {}) == {} then {hooks: .[1].hooks}
            else {hooks: (.[0].hooks // {} | to_entries | map({key: .key, value: .value}) |
              reduce .[] as $e ({}; .[$e.key] = $e.value)) as $base |
              (.[1].hooks // {} | to_entries |
              reduce .[] as $e ($base; .[$e.key] = (.[$e.key] // []) + $e.value)) |
              {hooks: .}}
            end;
          def merge_mcp:
            {mcpServers: ((.[0].mcpServers // {}) * (.[1].mcpServers // {}))};
          .[0] * .[1] * (. | merge_hooks) * (. | merge_mcp)
        ' "$SETTINGS_BASE" "$SETTINGS_LOCAL" > "$SETTINGS_OUT"
        echo "   Settings merged into settings.json"
    else
        cp -f "$SETTINGS_BASE" "$SETTINGS_OUT"
        echo "   Using base settings.json (no local overlay)"
    fi
fi
```

Note: This requires `jq` which is already installed in the Dockerfile.

- [ ] **Step 3: Remove the old simple cp logic**

Remove this block from the ecosystem wiring section:

```bash
    if [ -f "$CLAUDE_HOME/settings.container.json" ]; then
        cp -f "$CLAUDE_HOME/settings.container.json" "$CLAUDE_HOME/settings.json"
        echo "   Using container-specific settings.json (writable copy)"
    elif [ -f "$ECOSYSTEM_DIR/global/settings.json" ]; then
        cp -f "$ECOSYSTEM_DIR/global/settings.json" "$CLAUDE_HOME/settings.json"
        echo "   Using ecosystem settings.json (writable copy)"
    fi
```

The new merge logic (step 2) replaces this entirely.

Note: this intentionally drops the ecosystem `settings.json` fallback. Settings now always come from the template's `settings.container.json` (+ optional local overlay). Ecosystem-level settings are a future concern tracked in the deferred claude-ecosystem work.

- [ ] **Step 4: Add workspace/bin to PATH**

Add before the "Ready" section at the end of the entrypoint:

```bash
# ---------------------------------------------------------------
# 4b. Add workspace/bin to PATH
# ---------------------------------------------------------------
if [ -d "/workspace/bin" ]; then
    export PATH="/workspace/bin:$PATH"
    echo "   workspace/bin added to PATH"
fi
```

Also add it to `.bashrc` for interactive sessions:

```bash
echo 'export PATH="/workspace/bin:$PATH"' >> /home/node/.bashrc
```

- [ ] **Step 5: Commit**

```bash
git add bin/entrypoint
git commit -m "feat: entrypoint merges settings overlay, adds workspace/bin to PATH"
```

---

### Task 7: bin/exec — Workspace script dispatcher

**Files:**
- Create: `bin/exec`

- [ ] **Step 1: Write bin/exec**

```bash
#!/bin/bash
## Host: Run a workspace/bin/ script inside the container
##
## Usage:
##   bin/exec <script> [args...]
##
## Examples:
##   bin/exec n8n dev          Run workspace/bin/n8n with arg "dev"
##   bin/exec migrate          Run workspace/bin/migrate

set -e
source "$(dirname "$0")/compose-args"

SCRIPT="$1"
if [ -z "$SCRIPT" ]; then
    echo "Usage: bin/exec <script> [args...]"
    echo ""
    echo "Runs workspace/bin/<script> inside the container."
    if [ -d "../workspace/bin" ]; then
        echo ""
        echo "Available scripts:"
        ls -1 "../workspace/bin/" 2>/dev/null | sed 's/^/  /'
    fi
    exit 1
fi
shift

if [ ! -f "../workspace/bin/$SCRIPT" ]; then
    echo "Not found: workspace/bin/$SCRIPT"
    if [ -d "../workspace/bin" ]; then
        echo ""
        echo "Available scripts:"
        ls -1 "../workspace/bin/" 2>/dev/null | sed 's/^/  /'
    fi
    exit 1
fi

docker compose $COMPOSE_FILES exec claude /workspace/bin/"$SCRIPT" "$@"
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x bin/exec
git add bin/exec
git commit -m "feat: add bin/exec dispatcher for workspace/bin scripts"
```

---

### Task 8: bin/setup — Rewrite for submodule model

**Files:**
- Modify: `bin/setup`

- [ ] **Step 1: Rewrite bin/setup as post-submodule-add helper**

Replace the entire contents. The new setup runs AFTER `git submodule add`:

```bash
#!/bin/bash
## Host: Post-submodule-add project setup
##
## Run this after: git submodule add <repo-url> claude-container
##
## Usage:
##   cd claude-container && bin/setup
##   cd claude-container && bin/setup --adopt    # move existing files into workspace/
##
## What it does:
##   1. Creates ../workspace/ directory (or moves existing files into it with --adopt)
##   2. Creates ../workspace/bin/ directory
##   3. Copies .env.example to .env if needed
##   4. Prompts for COMPOSE_PROJECT_NAME
##   5. Creates empty settings.container.local.json if needed

set -e
cd "$(dirname "$0")/.."

MODE="default"
[ "${1:-}" = "--adopt" ] && MODE="adopt"

PROJECT_ROOT="$(cd .. && pwd)"

# ── Adopt mode: move existing project files into workspace/ ──
if [ "$MODE" = "adopt" ]; then
    if [ -d "../workspace" ]; then
        echo "workspace/ already exists — skipping adopt"
    else
        echo "Moving project contents into workspace/..."
        TMPWORK="$PROJECT_ROOT/.workspace-tmp-$$"
        mkdir -p "$TMPWORK"

        for item in "$PROJECT_ROOT"/*; do
            name=$(basename "$item")
            [ "$name" = "claude-container" ] && continue
            [ "$name" = ".workspace-tmp-$$" ] && continue
            mv "$item" "$TMPWORK/"
        done

        for item in "$PROJECT_ROOT"/.[!.]*; do
            [ ! -e "$item" ] && continue
            name=$(basename "$item")
            [ "$name" = ".DS_Store" ] && continue
            [ "$name" = ".gitmodules" ] && continue
            [ "$name" = ".git" ] && continue
            [ "$name" = ".workspace-tmp-$$" ] && continue
            mv "$item" "$TMPWORK/"
        done

        mv "$TMPWORK" "$PROJECT_ROOT/workspace"
        echo "   Moved all contents to workspace/"
    fi
fi

# ── Create workspace/ if not exists ──
if [ ! -d "../workspace" ]; then
    mkdir -p "../workspace"
    echo "Created workspace/"
fi

# ── Create workspace/bin/ ──
mkdir -p "../workspace/bin"

# ── .env ──
if [ ! -f ".env" ]; then
    cp ".env.example" ".env"
    echo "Created .env from .env.example"

    # Prompt for COMPOSE_PROJECT_NAME
    read -p "Project name for COMPOSE_PROJECT_NAME: " project_name
    if [ -n "$project_name" ]; then
        sed -i.bak "s/COMPOSE_PROJECT_NAME=myproject/COMPOSE_PROJECT_NAME=$project_name/" .env
        rm -f .env.bak
        echo "   Set COMPOSE_PROJECT_NAME=$project_name"
    fi
else
    echo ".env already exists — keeping it"
fi

# ── settings.container.local.json ──
if [ ! -f "settings.container.local.json" ]; then
    echo '{}' > settings.container.local.json
    echo "Created empty settings.container.local.json"
fi

echo ""
echo "Ready:"
echo ""
echo "   $(pwd)/"
echo "   .env                             edit credentials"
echo "   settings.container.local.json    project-specific hooks/MCP"
echo "   build.local.conf                 project-specific build args"
echo ""
echo "   bin/start                        build + start"
echo "   bin/claude                       YOLO mode"
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x bin/setup
git add bin/setup
git commit -m "feat: rewrite bin/setup as post-submodule-add helper"
```

---

### Task 9: bin/start — COMPOSE_PROJECT_NAME enforcement + settings.local init

**Files:**
- Modify: `bin/start`

Baseline: `/Users/andre/Git-repo/python/business-agents/claude-container/bin/start`

- [ ] **Step 1: Copy baseline and add enforcement**

```bash
#!/bin/bash
## Host: Build and start the Claude Code container

set -e
source "$(dirname "$0")/compose-args"

# Ensure COMPOSE_PROJECT_NAME is set
if [ -z "${COMPOSE_PROJECT_NAME:-}" ]; then
    # Try loading from .env
    [ -f ".env" ] && source .env
    if [ -z "${COMPOSE_PROJECT_NAME:-}" ]; then
        echo "COMPOSE_PROJECT_NAME is not set in .env"
        echo "This is required to prevent container name collisions."
        echo ""
        echo "Add to .env:  COMPOSE_PROJECT_NAME=myproject"
        exit 1
    fi
fi

# Ensure settings.container.local.json exists (needed for Docker mount)
[ ! -f "settings.container.local.json" ] && echo '{}' > settings.container.local.json

build_images
docker compose $COMPOSE_FILES up -d

echo ""
echo "Container running. Project mounted at /workspace"
echo ""
echo "  bin/shell              Open a shell inside the container"
echo "  bin/claude             Run Claude Code in YOLO mode"
echo "  bin/stop               Stop the container"
```

- [ ] **Step 2: Commit**

```bash
chmod +x bin/start
git add bin/start
git commit -m "feat: bin/start enforces COMPOSE_PROJECT_NAME, ensures settings.local exists"
```

---

### Task 10: Remaining bin scripts — Copy, clean, update

**Files:**
- Modify: `bin/claude`, `bin/shell`, `bin/stop`, `bin/destroy`, `bin/rebuild`, `bin/status`
- Create: `bin/update`
- Delete: `bin/pull`, `bin/quick-setup`, `bin/n8n`

- [ ] **Step 1: Copy baseline bin scripts from business-agents**

Copy: `claude`, `shell`, `stop`, `destroy`, `rebuild`, `status`, `firewall`.

The npm package updater (`bin/update` in business-agents) must be renamed to `bin/update-packages` to avoid colliding with the new `bin/update` submodule wrapper. The Dockerfile COPY line must also be updated.

```bash
for script in claude shell stop destroy rebuild status firewall; do
    cp /Users/andre/Git-repo/python/business-agents/claude-container/bin/$script /Users/andre/claude-container/bin/$script
done
# Rename npm updater to avoid collision with new bin/update (submodule wrapper)
cp /Users/andre/Git-repo/python/business-agents/claude-container/bin/update /Users/andre/claude-container/bin/update-packages
chmod +x /Users/andre/claude-container/bin/*
```

- [ ] **Step 2: Update bin/status to handle conditional versions**

The status script currently always shows PHP/Composer. Modify to only show installed tools:

Replace the version-checking block with:

```bash
    echo ""
    echo "── Versions ──"
    docker compose $COMPOSE_FILES exec claude bash -c '
        echo "   claude:      $(claude --version 2>/dev/null || echo "not found")"
        echo "   node:        $(node -v 2>/dev/null)"
        command -v php &>/dev/null && echo "   php:         $(php -v 2>/dev/null | head -1 | awk "{print \$2}")"
        command -v composer &>/dev/null && echo "   composer:    $(composer -V 2>/dev/null | awk "{print \$3}")"
        command -v python3 &>/dev/null && echo "   python:      $(python3 --version 2>/dev/null | awk "{print \$2}")"
    '
```

- [ ] **Step 3: Create bin/update (submodule wrapper)**

This replaces `bin/pull`. It updates the claude-container submodule to the latest remote commit:

```bash
#!/bin/bash
## Host: Update claude-container to latest version
##
## Usage:
##   bin/update              Pull latest template
##   bin/update --rebuild    Pull and rebuild image

set -e
cd "$(dirname "$0")/.."

echo "Updating claude-container..."

# We're inside the submodule — go to the project root
PROJECT_ROOT="$(cd .. && pwd)"

cd "$PROJECT_ROOT"
git submodule update --remote claude-container

echo "Updated to: $(cd claude-container && git log --oneline -1)"

if [ "${1:-}" = "--rebuild" ]; then
    echo ""
    echo "Rebuilding..."
    cd claude-container
    bin/stop 2>/dev/null || true
    bin/rebuild
else
    echo ""
    echo "Run 'bin/update --rebuild' to also rebuild the image."
fi
```

- [ ] **Step 4: Remove project-specific scripts**

```bash
rm -f /Users/andre/claude-container/bin/pull
rm -f /Users/andre/claude-container/bin/quick-setup
rm -f /Users/andre/claude-container/bin/n8n
```

- [ ] **Step 5: Commit**

```bash
git add bin/
git rm bin/pull bin/quick-setup bin/n8n 2>/dev/null || true
git commit -m "feat: update bin scripts for submodule model, remove project-specific scripts"
```

---

### Task 11: Remove archived files and clean up

**Files:**
- Delete: `.archived/` contents
- Delete: `README.md` (replaced by QUICKSTART.md)

- [ ] **Step 1: Remove archived files**

```bash
rm -rf /Users/andre/claude-container/.archived/*
```

- [ ] **Step 2: Remove old README.md**

Will be replaced by QUICKSTART.md in Task 13.

```bash
rm -f /Users/andre/claude-container/README.md
```

- [ ] **Step 3: Commit**

```bash
git rm -r .archived/ README.md 2>/dev/null || true
git commit -m "chore: remove archived files and old README"
```

---

### Task 12: CLAUDE.md — Rules for Claude

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write CLAUDE.md**

```markdown
# Claude Container

Docker-based Claude Code container for running in YOLO mode (`--dangerously-skip-permissions`).
Projects consume this as a git submodule.

## Architecture

- `build.conf` — default build config (tracked). Project overrides in `build.local.conf` (gitignored).
- `settings.container.json` — default settings (tracked). Project overrides in `settings.container.local.json` (gitignored).
- `bin/` — host-side scripts for container lifecycle.
- `workspace/` — project code, lives as sibling directory outside this submodule.
- `workspace/bin/` — project-specific scripts, run via `bin/exec`.

## Rules

- When modifying bin scripts, Dockerfile, docker-compose.yml, build.conf, or entrypoint: update QUICKSTART.md and docs/guide.md to reflect the changes.
- Template files are never modified per-project. All project customization uses gitignored local override files (build.local.conf, settings.container.local.json, .env).
- Permissions config is irrelevant — the container runs in YOLO mode.

## Submodule Upstream Workflow

When working on the template itself (not a consumer project):
1. Make changes in this directory
2. `git commit && git push` to push to the template repo
3. In consumer projects: `cd claude-container && bin/update` to pull latest

## Key Files

- `bin/compose-args` — shared library sourced by all bin scripts. Reads build.conf + build.local.conf, provides build_images().
- `bin/entrypoint` — container startup. Wires ecosystem, merges settings, installs plugins.
- `Dockerfile` — uses build-args (INSTALL_PHP, INSTALL_PYTHON, INSTALL_COMPOSER) for conditional installs.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: add CLAUDE.md with rules for Claude"
```

---

### Task 13: QUICKSTART.md — Short getting-started guide

**Files:**
- Create: `QUICKSTART.md`

- [ ] **Step 1: Write QUICKSTART.md**

```markdown
# Claude Container — Quick Start

Run Claude Code in YOLO mode inside Docker. [Full guide →](docs/guide.md)

## Prerequisites

- Docker Desktop (or Docker Engine + Compose plugin)
- Git

## Add to Your Project

```bash
cd your-project
git submodule add <repo-url> claude-container
cd claude-container
bin/setup            # creates workspace/, .env, settings.container.local.json
```

To adopt an existing project (moves files into `workspace/`):

```bash
bin/setup --adopt
```

## Configure

Edit `.env` inside `claude-container/`:

```
COMPOSE_PROJECT_NAME=your-project-name   # REQUIRED — unique per project
# ANTHROPIC_API_KEY=sk-ant-...           # or use OAuth below
```

Optionally create `build.local.conf` to toggle build features:

```ini
INSTALL_PHP=true
INSTALL_COMPOSER=true
```

## Run

```bash
bin/start              # build + start container
bin/claude             # Claude Code in YOLO mode
bin/shell              # bash inside container
bin/stop               # stop (preserves auth + history)
```

## First Time Auth

```bash
bin/shell
claude auth login      # opens browser OAuth flow — token persists in Docker volume
```

## Update Template

```bash
bin/update             # pull latest submodule
bin/update --rebuild   # pull + rebuild image
```

## Project Scripts

Put project-specific scripts in `workspace/bin/` and run them with:

```bash
bin/exec your-script   # runs workspace/bin/your-script inside the container
```

[Full guide →](docs/guide.md)
```

- [ ] **Step 2: Commit**

```bash
git add QUICKSTART.md
git commit -m "docs: add QUICKSTART.md"
```

---

### Task 14: docs/guide.md — Comprehensive reference

**Files:**
- Create: `docs/guide.md`

- [ ] **Step 1: Write docs/guide.md**

This is the comprehensive reference document covering all topics listed in the spec's Section 6. It should cover:

1. **Overview** — what claude-container is and how it works
2. **Project Structure** — full directory tree with explanations
3. **Setup** — adding to a new project, adopting existing project, cloning
4. **Build Configuration** — build.conf, build.local.conf, adding new build args
5. **Settings** — settings.container.json, settings.container.local.json, merge strategy
6. **Plugin Management** — what's installed, how to enable per project
7. **Scripts Reference** — all bin/ scripts with usage examples
8. **Project-Specific Scripts** — workspace/bin/ and bin/exec
9. **Project-Specific Dependencies** — workspace/Dockerfile vs upstream
10. **Contributing Upstream** — submodule commit/push workflow for template changes
11. **Updating** — bin/update usage
12. **Multi-Computer Setup** — clone with --recurse-submodules, setting up .env
13. **Firewall** — optional network restriction
14. **Ecosystem Mount** — optional claude-ecosystem integration
15. **Troubleshooting / FAQ**

Each section should be concise but complete with examples. Target ~300-400 lines total.

Write the full content. Cross-link to QUICKSTART.md at the top.

- [ ] **Step 2: Commit**

```bash
git add docs/guide.md
git commit -m "docs: add comprehensive guide"
```

---

### Task 15: Integration verification

**Files:** None (verification only)

- [ ] **Step 1: Build the image with default config**

```bash
cd /Users/andre/claude-container
# Create minimal .env for testing
echo "COMPOSE_PROJECT_NAME=test-container" > .env
echo '{}' > settings.container.local.json
bin/start
```

Expected: image builds with Python but without PHP/Composer. Container starts.

- [ ] **Step 2: Verify status**

```bash
bin/status
```

Expected: shows Claude version, Node version, Python version. Does NOT show PHP or Composer.

- [ ] **Step 3: Verify settings merge (no local overlay)**

```bash
bin/shell
cat ~/.claude/settings.json
exit
```

Expected: settings.json matches settings.container.json (base settings only).

- [ ] **Step 4: Test with build.local.conf**

```bash
echo "INSTALL_PHP=true" > build.local.conf
echo "INSTALL_COMPOSER=true" >> build.local.conf
bin/rebuild
bin/status
```

Expected: PHP and Composer now appear in status output.

- [ ] **Step 5: Test settings merge with local overlay**

Write a test local settings file:

```bash
cat > settings.container.local.json << 'EOF'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "^(Write|Edit)",
        "hooks": [
          {
            "type": "command",
            "command": "echo 'test hook fired'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
EOF
```

Restart container and verify merge:

```bash
bin/stop && bin/start
bin/shell
cat ~/.claude/settings.json
exit
```

Expected: settings.json contains both SessionStart hook (from base) and PostToolUse hook (from local).

- [ ] **Step 6: Verify workspace/bin is on PATH inside container**

```bash
bin/shell
echo $PATH | tr ':' '\n' | grep workspace
exit
```

Expected: `/workspace/bin` appears in PATH.

- [ ] **Step 7: Verify update-packages is the npm updater (not the submodule wrapper)**

```bash
docker compose exec claude head -3 /usr/local/bin/update-packages
```

Expected: shows the npm update script content (with `_check_update` function), NOT the submodule wrapper.

- [ ] **Step 8: Test bin/exec with no workspace scripts**

```bash
bin/exec nonexistent
```

Expected: "Not found: workspace/bin/nonexistent" error message.

- [ ] **Step 9: Clean up test artifacts**

```bash
rm -f build.local.conf
echo '{}' > settings.container.local.json
bin/stop
```

- [ ] **Step 10: Final commit of any remaining changes**

```bash
git status
# Commit anything missed
```

---

### Task 16: Push to GitHub

**Files:** None

- [ ] **Step 1: Create private GitHub repo**

```bash
gh repo create claude-container --private --source=. --push
```

Or if the repo already exists:

```bash
git remote add origin git@github.com:<user>/claude-container.git
git push -u origin main
```

- [ ] **Step 2: Verify clone works**

```bash
cd /tmp
git clone --recurse-submodules git@github.com:<user>/claude-container.git test-clone
ls test-clone/
rm -rf test-clone
```

Expected: all files present, including build.conf and settings.container.json.
