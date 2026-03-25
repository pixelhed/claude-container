# Claude Container — Comprehensive Guide

For a quick start, see [QUICKSTART.md](../QUICKSTART.md).

---

## Overview

Claude Container runs Claude Code in YOLO mode (`--dangerously-skip-permissions`) inside a Docker container. Projects consume it as a **git submodule** — the template owns the container definition, and projects extend it through well-defined override files. This keeps every project on the same base while allowing per-project customization of languages, tools, hooks, and MCP servers.

The container is based on `node:20-bookworm-slim` and ships with Claude Code (native installer), GSD (`get-shit-done-cc`), and a curated set of plugins (superpowers, context7, n8n-mcp-skills). Build-arg toggles control optional language runtimes (Python, PHP, Composer). Your project code lives in a `workspace/` directory outside the submodule and is bind-mounted into the container at `/workspace`.

Auth tokens, bash history, and plugin state persist across restarts in Docker volumes. An optional firewall script can restrict outbound network access. An optional `claude-ecosystem` mount brings in global commands, skills, rules, and agents.

---

## Project Structure

```
my-project/                              # your project repo
├── .gitmodules                          # pins claude-container to a commit
├── claude-container/                    # git submodule (template-owned)
│   ├── bin/
│   │   ├── claude                      # run Claude Code in YOLO mode
│   │   ├── compose-args                # shared library sourced by other scripts
│   │   ├── destroy                     # remove container, volumes, images
│   │   ├── entrypoint                  # container startup (ecosystem, settings, plugins)
│   │   ├── exec                        # run workspace/bin/ scripts in container
│   │   ├── firewall                    # optional outbound network restriction
│   │   ├── rebuild                     # rebuild image with --no-cache
│   │   ├── setup                       # post-submodule-add project setup
│   │   ├── shell                       # interactive bash inside container
│   │   ├── start                       # build + start container
│   │   ├── status                      # show versions and health
│   │   ├── stop                        # stop container, preserve volumes
│   │   ├── update                      # pull latest template via submodule
│   │   └── update-packages             # background npm update checker
│   ├── Dockerfile                      # base image with build-arg toggles
│   ├── docker-compose.yml              # base service definition
│   ├── build.conf                      # default build config (tracked)
│   ├── settings.container.json         # default Claude settings (tracked)
│   ├── .env.example                    # credential template
│   ├── CLAUDE.md / QUICKSTART.md       # documentation
│   ├── docs/guide.md                   # this file
│   │
│   │  # ── project-local overrides (gitignored) ──
│   ├── .env                            # credentials + COMPOSE_PROJECT_NAME
│   ├── build.local.conf                # build-arg overrides
│   └── settings.container.local.json   # settings overlay
│
└── workspace/                           # project code (bind-mounted to /workspace)
    ├── bin/                             # project-specific container scripts
    ├── Dockerfile                       # optional image extension (FROM base)
    └── docker-compose.yml              # optional extra services
```

Template files inside `claude-container/` are **never modified per-project**. All customization uses the gitignored override files or the `workspace/` extension points.

---

## Setup

### Adding to a new project

```bash
cd your-project
git submodule add <repo-url> claude-container
cd claude-container
bin/setup            # creates workspace/, .env, settings.container.local.json
```

`bin/setup` creates the directory structure and prompts for `COMPOSE_PROJECT_NAME`.

### Adopting an existing project

If your repo already has files at the root, `--adopt` moves them into `workspace/` (skipping `.git`, `.gitmodules`, and the submodule itself):

```bash
cd claude-container
bin/setup --adopt
```

### First run

```bash
bin/start            # build image + start container
bin/shell            # open bash inside container
claude auth login    # browser-based OAuth — token persists in Docker volume
exit
bin/claude           # Claude Code in YOLO mode
```

---

## Build Configuration

### Layering

| File | Purpose | Tracked |
|------|---------|---------|
| `build.conf` | Template defaults | Yes |
| `build.local.conf` | Project overrides | No (gitignored) |

Both files use `KEY=value` shell syntax. `bin/compose-args` sources `build.conf` first, then `build.local.conf` — local values win on collision.

### Default build args

```ini
INSTALL_PHP=false
INSTALL_PYTHON=true
INSTALL_COMPOSER=false
```

### Enabling a feature per project

Create `build.local.conf`:

```ini
INSTALL_PHP=true
INSTALL_COMPOSER=true
```

Then rebuild: `bin/rebuild`

### Adding a new build arg upstream

1. Add `ARG MY_FEATURE=false` and a conditional `RUN` block to `Dockerfile`
2. Add `MY_FEATURE=false` to `build.conf`
3. Add `MY_FEATURE` to the variable list in `bin/compose-args` (`load_build_config`)
4. Commit and push to the template repo

---

## Settings

### Files

| File | Purpose | Tracked |
|------|---------|---------|
| `settings.container.json` | Template defaults (hooks, MCP, prefs) | Yes |
| `settings.container.local.json` | Project overlay | No (gitignored) |

Both are mounted read-only into the container. The entrypoint merges them into `~/.claude/settings.json` at startup.

### Merge strategy

| Type | Behavior |
|------|----------|
| **Hooks** | Append per event — local hooks are added after template hooks for each event key (e.g., `PostToolUse`). Both fire. |
| **MCP servers** | Local wins per key — if both define server `n8n`, local's definition replaces template's. New keys are added. |
| **Scalars** | Local wins — local value replaces template value. |

### Example local overlay

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{ "type": "command", "command": "php-cs-fixer fix $FILE_PATH --quiet" }]
      }
    ]
  },
  "mcpServers": {
    "n8n": { "enabled": true }
  }
}
```

---

## Plugin Management

### Installed automatically

The entrypoint installs these on first boot (persisted in the `claude-config` volume):

| Plugin | Purpose |
|--------|---------|
| `superpowers` | Workflow skills — brainstorming, TDD, debugging |
| `context7` | Library documentation lookup |
| `n8n-mcp-skills` | n8n workflow building skills |

### GSD

`get-shit-done-cc` is installed globally via npm in the Dockerfile and auto-configured by the entrypoint. Use `/gsd` inside Claude sessions.

### Enabling plugins per project

Plugins are installed globally but enabled per project via `settings.container.local.json` MCP server entries. For example, to enable the n8n MCP server:

```json
{ "mcpServers": { "n8n": { "enabled": true } } }
```

---

## Scripts Reference

All scripts live in `bin/` and run on the **host** machine.

| Script | Purpose | Example |
|--------|---------|---------|
| `start` | Build image + start container | `bin/start` |
| `stop` | Stop container, preserve volumes | `bin/stop` |
| `rebuild` | Rebuild with `--no-cache` + restart | `bin/rebuild` |
| `destroy` | Remove container, volumes, and image | `bin/destroy` |
| `claude` | Claude Code in YOLO mode | `bin/claude -p "fix lint errors"` |
| `shell` | Interactive bash in container | `bin/shell` |
| `status` | Show container state and versions | `bin/status` |
| `setup` | Post-submodule-add setup | `bin/setup --adopt` |
| `exec` | Run a workspace/bin/ script | `bin/exec migrate --fresh` |
| `update` | Pull latest template | `bin/update --rebuild` |

### Details for key scripts

**`bin/claude`** — Auto-starts the container if not running. Passes all arguments through to Claude Code with `--dangerously-skip-permissions`. Supports `-p` for headless prompts and `--print` for print mode.

**`bin/start`** — Refuses to start if `COMPOSE_PROJECT_NAME` is not set in `.env` (prevents container name collisions). Creates `settings.container.local.json` if missing (Docker requires mount targets to exist). Calls `build_images` from `compose-args`, which also builds the workspace Dockerfile extension if present.

**`bin/compose-args`** — Not run directly. Sourced by other scripts. Loads `build.conf` + `build.local.conf`, sets `BUILD_ARGS`, detects `workspace/docker-compose.yml` for multi-file compose, and provides `build_images()`.

**`bin/destroy`** — Prompts for confirmation before removing the container, all volumes (including auth/history), and the built image.

---

## Project-Specific Scripts

### Creating scripts

Put executable scripts in `workspace/bin/`:

```bash
# workspace/bin/migrate
#!/bin/bash
cd /workspace
php artisan migrate "$@"
```

### Running from the host

```bash
bin/exec migrate --fresh --seed
bin/exec test --filter=UserTest
```

`bin/exec` lists available scripts if called without arguments or if the named script is not found.

### Inside the container

The entrypoint adds `/workspace/bin` to `PATH`, so during `bin/shell` sessions you can call workspace scripts directly:

```bash
migrate --fresh --seed
```

---

## Project-Specific Dependencies

### Option 1: Workspace Dockerfile (project-specific)

Create `workspace/Dockerfile` to extend the base image:

```dockerfile
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN apt-get update && apt-get install -y postgresql-client && rm -rf /var/lib/apt/lists/*
```

`bin/compose-args` builds the base image first, then runs `docker build` on the workspace Dockerfile with `--build-arg BASE_IMAGE=<base>` and tags the result with the same image name, replacing the base.

### Option 2: Upstream contribution (generic, reusable)

If the dependency is useful across projects (e.g., Ruby runtime), add a build-arg toggle to the template Dockerfile and `build.conf`, then commit upstream. See [Adding a new build arg upstream](#adding-a-new-build-arg-upstream).

### Extra services

Create `workspace/docker-compose.yml` for project-specific services (databases, APIs, etc.). It is automatically detected and merged via `bin/compose-args`.

---

## Contributing Changes Upstream

When working inside a consumer project and you want to improve the template:

```bash
cd claude-container               # enter the submodule

# Make your changes to Dockerfile, build.conf, entrypoint, etc.
git add -A
git commit -m "feat: add Ruby build-arg toggle"
git push                           # pushes to the template repo

cd ..                              # back to project root
git add claude-container           # update the submodule pin
git commit -m "chore: update claude-container"
```

Other projects pick up the change via `bin/update`.

---

## Updating

```bash
bin/update                # pull latest template commit
bin/update --rebuild      # pull + rebuild image with new Dockerfile
```

`bin/update` runs `git submodule update --remote claude-container` from the project root, then optionally stops, rebuilds, and restarts the container.

---

## Multi-Computer Setup

### Cloning a project that uses claude-container

```bash
git clone --recurse-submodules <project-url>
cd my-project/claude-container
```

### Creating local config

The gitignored override files do not travel with the repo. Create them on each machine:

```bash
cp .env.example .env
# Edit .env — set COMPOSE_PROJECT_NAME at minimum
```

Optionally create `build.local.conf` and `settings.container.local.json` as needed.

### Verify

```bash
bin/start
bin/shell
claude auth login        # authenticate on this machine
exit
bin/claude               # ready
```

---

## Firewall

An optional iptables-based firewall restricts outbound network access from inside the container. It is **not enabled by default**.

### Enabling

From inside the container (`bin/shell`):

```bash
sudo init-firewall
```

### What is allowed

- DNS (UDP/TCP port 53)
- Anthropic API (`api.anthropic.com`, `statsig.anthropic.com`)
- Sentry (`sentry.io`)
- Package registries (`registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`)
- GitHub (`github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`)
- SSH (port 22)
- Docker internal DNS (`127.0.0.11`)

Everything else is dropped. The container has `NET_ADMIN` and `NET_RAW` capabilities to support this.

---

## Ecosystem Mount

The container can optionally mount a `claude-ecosystem` directory (read-only) that provides global commands, skills, rules, and agents shared across all projects.

### Configuration

Set the path in `.env`:

```
CLAUDE_ECOSYSTEM_PATH=~/claude-ecosystem
```

The entrypoint symlinks ecosystem content into `~/.claude/` at startup:
- `global/CLAUDE.md` -- global rules
- `global/commands/` -- slash commands
- `global/skills/` -- skills
- `global/rules/` -- rule files
- `global/agents/` -- agent definitions

### Current limitations

- `claude-ecosystem` is not yet version-controlled — it must be manually copied between machines.
- Future plans include making it a git repo (possibly another submodule) for automatic sync.

---

## Troubleshooting / FAQ

### Docker mount error on `settings.container.local.json`

Docker requires bind-mount source files to exist. `bin/start` auto-creates an empty `settings.container.local.json` if missing, but if you see mount errors, create it manually:

```bash
echo '{}' > settings.container.local.json
```

### Container name collision

If `docker compose up` fails with a name conflict, ensure `COMPOSE_PROJECT_NAME` in `.env` is unique across all your claude-container projects. The container name is `${COMPOSE_PROJECT_NAME}-code`.

### Submodule shows as dirty / modified

The gitignored override files (`.env`, `build.local.conf`, `settings.container.local.json`) live inside the submodule directory but are excluded by the submodule's `.gitignore`. If git still reports the submodule as dirty, check that these filenames exactly match the `.gitignore` entries.

### `claude-ecosystem` not found

If the ecosystem path does not exist on the host, Docker may create it as an empty directory owned by root. The entrypoint handles this gracefully — it skips ecosystem wiring and logs a message. Set `CLAUDE_ECOSYSTEM_PATH` to a valid path or remove/comment the line in `.env`.

### Plugins fail to install

Plugin installs require `TMPDIR` to be on the same filesystem as `~/.claude`. The Dockerfile and entrypoint set `TMPDIR=/home/node/.claude/tmp` to handle this. If plugins still fail, check that the `claude-config` volume is healthy: `bin/destroy` and `bin/start` to recreate it.

### Claude Code not found in PATH

The Dockerfile installs Claude Code to `~/.local/bin/` and adds it to `PATH` via `ENV`. If `claude` is not found inside the container, the install may have failed during build. Run `bin/rebuild` to reinstall from scratch.

### How do I reset everything?

`bin/destroy` removes the container, all volumes (auth, history, plugins), and the built image. The next `bin/start` rebuilds from scratch.
