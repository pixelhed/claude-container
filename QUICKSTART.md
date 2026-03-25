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
