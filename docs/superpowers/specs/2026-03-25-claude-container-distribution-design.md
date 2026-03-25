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
├── claude-container/                # submodule (READ-ONLY by convention)
│   ├── bin/                         # host-side scripts
│   │   ├── claude                   # exec Claude in YOLO mode
│   │   ├── compose-args             # shared library (merges config + compose files)
│   │   ├── destroy                  # remove container, volumes, images
│   │   ├── entrypoint               # container startup (ecosystem, settings merge, plugins)
│   │   ├── firewall                 # optional outbound network restriction
│   │   ├── quick-setup              # one-shot project onboarding
│   │   ├── rebuild                  # rebuild with --no-cache
│   │   ├── setup                    # initialize project structure
│   │   ├── shell                    # interactive bash in container
│   │   ├── start                    # build + start container
│   │   ├── status                   # show versions, mounts, health
│   │   ├── stop                     # stop container, preserve volumes
│   │   ├── update                   # git submodule update --remote wrapper
│   │   └── (catch-all dispatcher)   # delegates unknown commands to workspace/bin/
│   ├── Dockerfile                   # base image with build-arg toggles
│   ├── docker-compose.yml           # base service definition
│   ├── build.conf                   # default build config
│   ├── settings.container.json      # default Claude Code settings
│   ├── .env.example                 # credential template
│   ├── QUICKSTART.md                # short getting-started guide
│   ├── CLAUDE.md                    # rules for Claude (auto-update docs, etc.)
│   └── docs/
│       └── guide.md                 # comprehensive reference
│
├── build.local.conf                 # project build overrides (gitignored)
├── settings.container.local.json    # project settings overlay (gitignored)
├── .env                             # credentials (gitignored)
│
└── workspace/                       # project code
    ├── bin/                         # project-specific container scripts
    ├── Dockerfile                   # optional image extension (FROM base)
    └── docker-compose.yml           # optional extra services
```

### Key Rules

- Files inside `claude-container/` are **never modified per-project** — the submodule stays clean
- All project customization lives **outside** the submodule
- Template is authoritative for its files; projects can only add new files or use designated extension points

---

## 2. Build Configuration

### Default config (`claude-container/build.conf`)

```ini
NODE_VERSION=20
INSTALL_PHP=false
INSTALL_PYTHON=true
INSTALL_COMPOSER=false
```

### Project overrides (`build.local.conf`, outside submodule, gitignored)

```ini
INSTALL_PHP=true
INSTALL_COMPOSER=true
```

### Resolution

`bin/compose-args` reads `build.conf`, then overlays `build.local.conf` (local wins). Merged values are passed as `--build-arg` flags to `docker compose build`.

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

### Project overrides (`settings.container.local.json`, outside submodule, gitignored)

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

| Type | Strategy |
|------|----------|
| Hooks | **Additive** — local hooks appended to template hooks |
| MCP servers | **Additive** — local servers added to template servers |
| Scalar values | **Local wins** |

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
| `setup` | Initialize project structure (adopt/clone/link/empty) |
| `quick-setup` | One-shot project onboarding |
| `compose-args` | Shared library (config merge, compose file detection) |
| `update` | `git submodule update --remote` wrapper |

### Container-side scripts (`workspace/bin/`, project-owned)

Project-specific scripts that run inside the container. Example: `bin/n8n` for switching n8n environments.

### Dispatch mechanism

When `bin/<name>` doesn't exist in `claude-container/bin/`, a catch-all dispatcher looks in `../workspace/bin/<name>` and executes it inside the container via `docker compose exec`. From the user's perspective, it's always `bin/whatever` from the `claude-container/` directory.

Additionally, the entrypoint adds `workspace/bin/` to `PATH` inside the container so scripts are available during interactive `bin/shell` sessions.

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
- Strip project-specific content (n8n script, PHP hooks, postgres config)
- Apply build-arg toggles to Dockerfile
- Replace `bin/pull` (rsync) with `bin/update` (submodule)
- Add docs (QUICKSTART.md, docs/guide.md, CLAUDE.md)
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
