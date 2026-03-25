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
