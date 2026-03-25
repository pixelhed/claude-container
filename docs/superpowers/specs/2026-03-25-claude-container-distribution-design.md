# Claude Container Distribution Design

**Date:** 2026-03-25
**Status:** Approved
**Scope:** Unify claude-container into a distributable git repo consumed by projects as a submodule

---

## Problem

claude-container exists as multiple divergent copies across projects (business-agents, akeneo-logo-remover) with no version control or sync mechanism. Project-specific customizations are mixed into template files. The system cannot be used on other computers or by other people.

## Goals

1. Single canonical git repo for claude-container
2. Projects consume it as a git submodule (pinned, updatable)
3. Clean separation: template owns its files, projects extend through defined interfaces
4. Works across machines (`git clone --recurse-submodules`)
5. Distributable to others (private now, open-source later)
6. Documentation stays in sync with code automatically

## Non-Goals

- claude-ecosystem portability (deferred — tracked in project memory)
- Open-sourcing (deferred until stable)
- CI/CD for the template repo

---

## 1. Repository Structure

```
my-project/                          # the project repo
├── .gitmodules                      # pins claude-container to a commit
├── claude-container/                # submodule
│   ├── bin/                         # host-side scripts
│   │   ├── claude                   # exec Claude in YOLO mode
│   │   ├── compose-args             # shared library (merges config + compose files)
│   │   ├── destroy                  # remove container, volumes, images
│   │   ├── entrypoint               # container startup (ecosystem, settings merge, plugins)
│   │   ├── exec                     # run workspace/bin/ scripts inside container
│   │   ├── firewall                 # optional outbound network restriction (container-only)
│   │   ├── rebuild                  # rebuild with --no-cache
│   │   ├── setup                    # post-submodule-add project setup
│   │   ├── shell                    # interactive bash in container
│   │   ├── start                    # build + start container
│   │   ├── status                   # show versions, mounts, health
│   │   ├── stop                     # stop container, preserve volumes
│   │   └── update                   # git submodule update --remote wrapper
│   ├── Dockerfile                   # base image with build-arg toggles
│   ├── docker-compose.yml           # base service definition
│   ├── build.conf                   # default build config (tracked)
│   ├── settings.container.json      # default Claude Code settings (tracked)
│   ├── .env.example                 # credential template
│   ├── QUICKSTART.md                # short getting-started guide
│   ├── CLAUDE.md                    # rules for Claude (auto-update docs, etc.)
│   ├── docs/
│   │   └── guide.md                 # comprehensive reference
│   │
│   │  # --- project-local overrides (gitignored by submodule) ---
│   ├── build.local.conf             # project build overrides
│   ├── settings.container.local.json # project settings overlay
│   └── .env                         # credentials
│
└── workspace/                       # project code
    ├── bin/                         # project-specific container scripts
    ├── Dockerfile                   # optional image extension (FROM base)
    └── docker-compose.yml           # optional extra services
```

### File placement rationale

Project-local override files (`build.local.conf`, `settings.container.local.json`, `.env`) live **inside** the `claude-container/` directory. This keeps script paths simple — all scripts resolve files relative to their own directory without path gymnastics. These files are gitignored by the submodule's own `.gitignore`, so they never dirty the submodule or get committed upstream.

### `.gitignore` (submodule)

```
.env
build.local.conf
settings.container.local.json
.DS_Store
.archived/
```

Note: `settings.container.json` and `build.conf` are **tracked** (template defaults).

### Key Rules

- Template-owned files inside `claude-container/` are **never modified per-project** — the submodule stays clean
- Project customization uses the gitignored local override files inside the submodule, plus `workspace/` extension points
- Template is authoritative for its tracked files; projects extend through designated interfaces only
- `COMPOSE_PROJECT_NAME` **must** be set in `.env` per project — `bin/start` will error if unset to prevent container name collisions

---

## 2. Build Configuration

### Default config (`claude-container/build.conf`)

```ini
NODE_VERSION=20
INSTALL_PHP=false
INSTALL_PYTHON=true
INSTALL_COMPOSER=false
```

### Project overrides (`build.local.conf`, inside submodule, gitignored by submodule)

```ini
INSTALL_PHP=true
INSTALL_COMPOSER=true
```

### Resolution

`bin/compose-args` reads `build.conf` then overlays `build.local.conf` (local wins) using shell `source` — both files are simple `KEY=value` shell variable assignments. Merged values are passed as `--build-arg` flags to `docker compose build`. The same args are passed to the standalone `docker build` call for `workspace/Dockerfile` if it exists.

### Dockerfile

Uses `ARG` with defaults and conditional installation:

```dockerfile
ARG INSTALL_PHP=false
ARG INSTALL_PYTHON=true
ARG INSTALL_COMPOSER=false

RUN if [ "$INSTALL_PHP" = "true" ]; then apt-get install -y php8... ; fi
RUN if [ "$INSTALL_COMPOSER" = "true" ]; then ... ; fi
```

### Workspace Dockerfile (optional, project-specific)

```dockerfile
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
RUN apt-get install -y postgresql-client
```

Extends the base image with project-specific system packages. If no `workspace/Dockerfile` exists, the base image is used as-is.

### Adding new dependencies

- **Generic, useful to everyone** (e.g., `INSTALL_RUBY`): Add build arg to Dockerfile and `build.conf`, commit upstream to template repo
- **Project-specific** (e.g., `postgresql-client`): Add to `workspace/Dockerfile`, never touches the template

### Upstream contribution workflow

1. Working in `my-project/claude-container/` (submodule)
2. Make changes to Dockerfile/build.conf
3. `cd claude-container && git commit && git push` (pushes to template repo)
4. Back in project root: `git add claude-container` to pin new commit
5. Other projects get it via `git submodule update --remote`

---

## 3. Settings Configuration

### Purpose

Settings control **hooks**, **MCP servers**, and **Claude Code preferences**. Permissions are irrelevant — the container runs in YOLO mode (`--dangerously-skip-permissions`).

### Default settings (`claude-container/settings.container.json`)

Template-level hooks, MCP servers, and preferences that apply to all projects.

### Project overrides (`settings.container.local.json`, inside submodule, gitignored by submodule)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "command": "php-cs-fixer fix $FILE_PATH --quiet"
      }
    ]
  },
  "mcpServers": {
    "n8n": { "enabled": true }
  }
}
```

### Merge strategy (handled by entrypoint at startup)

| Type | Collision behavior |
|------|-------------------|
| Hooks | **Append per event** — local hooks are appended to the template's hook array for each event (e.g., `PostToolUse`). Both fire. If this causes double-firing (e.g., two formatters on the same file type), it's the project's responsibility to not duplicate template hooks. |
| MCP servers | **Local wins per key** — if both template and local define server `n8n`, local's definition replaces template's for that key. New keys from local are added. |
| Scalar values | **Local wins** — local value replaces template value |

The entrypoint merges both files into `~/.claude/settings.json` inside the container. Source files stay untouched.

---

## 4. Plugin & Skill Management

### Principle: Install globally, enable per project

All plugins are installed into the container by the entrypoint. Projects enable specific plugins via `settings.container.local.json` MCP server configuration.

### Plugins installed at startup

| Plugin | Purpose |
|--------|---------|
| `superpowers` | Workflow skills (brainstorming, TDD, debugging) |
| `context7` | Library documentation lookup |
| `n8n-mcp-skills` | n8n workflow building skills |

### Marketplaces registered

| Marketplace | Source |
|-------------|--------|
| `obra/superpowers-marketplace` | Superpowers plugin ecosystem |
| `czlonkowski/n8n-skills` | n8n skill ecosystem |

### GSD

`get-shit-done-cc` installed globally via npm in the Dockerfile. Auto-setup at first boot via entrypoint.

### Adding new plugins

- Useful to everyone → add to entrypoint, commit upstream
- Project-specific → enable in `settings.container.local.json`

---

## 5. Host-side vs Container-side Scripts

### Host-side scripts (`claude-container/bin/`, template-owned)

Run on the host machine, manage the container lifecycle:

| Script | Purpose |
|--------|---------|
| `start` | Build images + start container |
| `stop` | Stop container, preserve volumes |
| `rebuild` | Rebuild with `--no-cache` |
| `destroy` | Remove container, volumes, images |
| `claude` | Exec Claude in YOLO mode |
| `shell` | Interactive bash in container |
| `status` | Show versions, mounts, health |
| `setup` | Post-submodule-add project setup (create workspace/, copy .env.example, etc.) |
| `exec` | Run a workspace/bin/ script inside the container |
| `compose-args` | Shared library (config merge, compose file detection, build-arg resolution) |
| `update` | `git submodule update --remote` wrapper |

### Container-side scripts (`workspace/bin/`, project-owned)

Project-specific scripts that run inside the container. Example: `n8n` for switching n8n environments.

### Dispatch mechanism

`bin/exec` is an explicit dispatcher: `bin/exec n8n dev` translates to `docker compose exec <service> /workspace/bin/n8n dev` inside the container. No symlink magic, no catch-all — the user knows they're running a workspace script.

Additionally, the entrypoint adds `/workspace/bin/` to `PATH` inside the container, so workspace scripts are also available during interactive `bin/shell` sessions without the `bin/exec` prefix.

### `bin/setup` in the submodule model

`bin/setup` runs **after** `git submodule add`. It does not add the submodule itself (that's a manual step documented in QUICKSTART). What it does:

1. Creates `../workspace/` directory if missing
2. Copies `.env.example` to `.env` if `.env` doesn't exist
3. Prompts for `COMPOSE_PROJECT_NAME` and writes it to `.env`
4. Creates `../workspace/bin/` directory
5. Optionally adopts an existing project (moves files into `../workspace/`)

---

## 6. Documentation

### QUICKSTART.md (root of template repo, ~1 page)

- Prerequisites (Docker, git)
- Add to project: `git submodule add <repo-url> claude-container`
- First run: `cd claude-container && bin/setup --adopt && bin/start`
- Daily use: `bin/claude`, `bin/shell`, `bin/stop`
- Link to full guide

### docs/guide.md (comprehensive reference)

- Full project structure explanation
- Build configuration (`build.conf` / `build.local.conf`)
- Settings overlay (`settings.container.json` / `settings.container.local.json`)
- Plugin management
- Project-specific scripts (`workspace/bin/`)
- Project-specific dependencies (workspace Dockerfile vs upstream)
- Contributing changes upstream (submodule workflow)
- Updating the template (`bin/update`)
- Multi-computer setup (`git clone --recurse-submodules`)
- Firewall configuration
- Ecosystem mount (optional)
- Troubleshooting / FAQ

### Auto-update rule (CLAUDE.md)

```
When modifying bin scripts, Dockerfile, docker-compose.yml, build.conf,
or entrypoint: update QUICKSTART.md and docs/guide.md to reflect the changes.
```

---

## 7. Migration Path

### Step 1: Consolidate the template repo

- Use business-agents copy as baseline (most advanced)
- Strip project-specific content (n8n script, PHP hooks, postgres config, n8n env vars from quick-setup)
- Apply build-arg toggles to Dockerfile (default `INSTALL_PHP=false`, `INSTALL_COMPOSER=false`)
- Replace `bin/pull` (rsync) with `bin/update` (submodule)
- Replace `bin/quick-setup` with simplified `bin/setup` (post-submodule-add helper)
- Add `bin/exec` dispatcher
- Update `.gitignore`: track `settings.container.json`, ignore `build.local.conf` and `settings.container.local.json`
- Implement settings merge in entrypoint (template + local overlay → `~/.claude/settings.json`)
- Add `/workspace/bin/` to PATH in entrypoint
- Add docs (QUICKSTART.md, docs/guide.md, CLAUDE.md)
- Enforce `COMPOSE_PROJECT_NAME` in `bin/start`
- Commit and push to private GitHub repo

### Step 2: Migrate business-agents

- Delete embedded `claude-container/` directory
- `git submodule add <repo-url> claude-container`
- Move project config to correct locations:
  - PHP hooks → `settings.container.local.json`
  - `INSTALL_PHP=true`, `INSTALL_COMPOSER=true` → `build.local.conf`
  - `bin/n8n` → `workspace/bin/n8n`
  - postgres/api/webui services stay in `workspace/docker-compose.yml`
  - Workspace Dockerfile stays at `workspace/Dockerfile`

### Step 3: Migrate akeneo-logo-remover

- Same pattern: delete embedded copy, add submodule, extract local config

### Step 4: Verify on second machine

- Clone a project with `--recurse-submodules`
- Create `.env`, optionally `build.local.conf` and `settings.container.local.json`
- `cd claude-container && bin/start && bin/claude` — should just work

**Dependencies:** Step 1 must complete before 2–4. Steps 2 and 3 are independent. Step 4 validates everything.

---

## 8. Future Work (Tracked, Deferred)

1. **claude-ecosystem as git repo** — `~/claude-ecosystem/` (commands, skills, rules, agents) must become version-controlled for multi-computer use. Possibly another submodule. Tracked in project memory.

2. **Open-sourcing** — Private repo first. Open-source when stable across multiple projects and machines.

3. **CI/CD** — Automated Dockerfile build/test on push via GitHub Actions.
