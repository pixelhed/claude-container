# Claude Code Container 🐳

Run Claude Code with `--dangerously-skip-permissions` safely in Docker.
Code lives in `workspace/`, Docker setup lives in `claude-container/`.

## Project Structure

```
my-project/
├── claude-container/         ← Docker setup (from ~/claude-container template)
└── workspace/                ← your code (git repo)
```

## Setup Modes

### Adopt an existing project (most common)

Restructures an existing project directory — moves all contents into `workspace/`:

```bash
~/claude-container/bin/setup ~/code/my-existing-project --adopt
```

Before:
```
my-existing-project/
├── .git/
├── src/
├── composer.json
└── ...
```

After:
```
my-existing-project/
├── claude-container/
└── workspace/
    ├── .git/
    ├── src/
    ├── composer.json
    └── ...
```

### Clone a repo

```bash
~/claude-container/bin/setup ~/projects/new-project --clone git@github.com:user/repo.git
```

### Symlink an existing repo (no copy, no move)

```bash
~/claude-container/bin/setup ~/projects/new-project --link ~/code/existing-repo
```

### Empty workspace

```bash
~/claude-container/bin/setup ~/projects/new-project
```

## Daily Use

```bash
cd my-project/claude-container
bin/start                        # build + start
bin/claude                       # YOLO mode
bin/claude -p "fix lint errors"  # headless
bin/shell                        # bash inside container
bin/status                       # versions + status
bin/stop                         # stop (keeps volumes)
```

## Update Template

Re-run setup — overwrites `claude-container/` but preserves `.env`:
```bash
~/claude-container/bin/setup ~/projects/my-project
```

## bin/ Commands

| Command | Where | Description |
|---------|-------|-------------|
| `bin/setup /path [mode]` | Host | Create/update project |
| `bin/start` | Host | Build + start container |
| `bin/stop` | Host | Stop (preserves volumes) |
| `bin/shell` | Host | Bash shell inside container |
| `bin/claude` | Host | YOLO mode |
| `bin/rebuild` | Host | Rebuild with latest packages |
| `bin/destroy` | Host | Remove everything |
| `bin/status` | Host | Versions + status |
| `cc` | Container | `claude --dangerously-skip-permissions` |
| `sudo init-firewall` | Container | Restrict outbound network |

## Mounts

| Host | Container | Mode |
|------|-----------|------|
| `../workspace/` | `/workspace/` | rw |
| `~/claude-ecosystem/` | `/home/node/claude-ecosystem/` | ro |
| `~/.gitconfig` | `~/.gitconfig` | ro |
