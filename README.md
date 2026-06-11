# codex-accounts

[![English](https://img.shields.io/badge/lang-English-blue)](README.md)
[![繁體中文](https://img.shields.io/badge/lang-繁體中文-lightgrey)](README.zh-TW.md)

Switch between Codex CLI accounts safely.

`codex-accounts` now supports two modes:

- **Auth-only switching**: copy only `auth.json` between a named profile and native `~/.codex/auth.json`. This is the default identity-switching path because sessions, logs, hooks, skills, agents, generated files, and other runtime state stay under native Codex management.
- **Full `CODEX_HOME` compatibility mode**: keep the older behavior under `codex-accounts home <subcommand>`, where Codex reads all state from `~/.codex-profiles/<profile>`. This remains available for one-time OAuth into empty profiles and legacy workflows.

Each profile stores its own `auth.json`. `config.toml` is shared across profiles by default through `~/.codex-profiles/_shared/config.toml`.

## Install

```bash
./install.sh

# Recommended: make auth-only switch clear CODEX_HOME in the current shell.
echo 'eval "$(codex-accounts auth-init)"' >> ~/.zshrc
exec zsh

# Optional legacy full-mode hook:
# echo 'eval "$(codex-accounts home shell-init)"' >> ~/.zshrc
```

## Commands

### Profile management

| Command | What it does |
|---|---|
| `list` (alias: `ls`) | Show all profiles, marking the profile matching native `~/.codex/auth.json` with `*` and indicating login status |
| `current` (alias: `active`) | Moved to `home current` for full-mode profiles |
| `add <name>` | Create an empty profile. First `codex` run in full mode can trigger OAuth |
| `import-current [name]` | Copy existing `~/.codex` into a new profile (default name: `default`). On first import, promotes its `config.toml` to the shared file |
| `switch <name>` (alias: `use`) | Auth-only switch: back up native `~/.codex/auth.json`, then replace it from the profile |
| `remove <name>` (alias: `rm`) | Deactivate a profile and preserve its data under `_removed/` (requires typing the name to confirm) |
| `auth-init` | Print the auth-only shell wrapper so `switch` automatically unsets `CODEX_HOME` in the current shell |

### Minimal auth replacement

These commands operate on `auth.json` only. They do not copy sessions, history, logs, cache, hooks, skills, agents, generated images, or GSD artifacts.

| Command | What it does |
|---|---|
| `auth paths <profile>` | Preview auth-required source, target, and backup paths without reading token contents |
| `auth switch <profile>` | Back up native `~/.codex/auth.json`, then replace it with `<profile>/auth.json` |
| `auth backups` | List managed native auth backups without reading auth contents |
| `auth restore [backup]` | Restore the latest or named native auth backup |
| `auth revert` | Restore the latest managed native auth backup |
| `auth prune-backups --keep <count>` | Delete older managed auth backups after typing `prune` to confirm |
| `auth help` | Show `auth` subcommand usage |

### Full `CODEX_HOME` compatibility mode

| Command | What it does |
|---|---|
| `home switch <profile>` (alias: `home use`) | Make `<profile>` the active full `CODEX_HOME` compatibility profile |
| `home current` (alias: `home active`) | Print the active full-mode profile name |
| `home env` | Print `export CODEX_HOME=...` for the active full-mode profile. Use with `eval "$(codex-accounts home env)"` |
| `home run -- <cmd> [args]` (alias: `home exec`) | Run `<cmd>` with `CODEX_HOME` set to the active full-mode profile |
| `home shell-init` (alias: `home init`) | Print a snippet for legacy full-mode shell integration |

### Shared config (`config.toml`)

`config.toml` (MCP servers, `[features]`, model defaults) is symlinked from each profile to `~/.codex-profiles/_shared/config.toml`. Edit once, applies everywhere.

| Command | What it does |
|---|---|
| `config status` | Show shared config path and per-profile link state (linked / local / missing / broken) |
| `config path` | Print the shared `config.toml` path |
| `config edit` | Open the shared `config.toml` in `$EDITOR` |
| `config link <profile> [--force]` | Re-link a profile's `config.toml` to shared. `--force` overwrites a local copy |
| `config unlink <profile>` | Detach a profile from shared (make a private copy) |
| `config relink-all [--force]` | Re-link every profile to shared |
| `config help` | Show `config` subcommand usage |

### Help

| Command | What it does |
|---|---|
| `help` (alias: `-h`, `--help`) | Show top-level usage |

## Minimal Workflow

Daily `codex-accounts` usage is auth-only: profiles provide `auth.json`, while Codex sessions, AGENTS, skills, logs, and other runtime state stay under native `~/.codex`.

```text
codex-accounts add <name>          # Create a profile
codex-accounts home run -- codex   # Use only to log in an empty profile
codex-accounts switch <name>       # Switch native ~/.codex/auth.json and clear CODEX_HOME via auth-init
codex-accounts list                # Check profile status
codex-accounts remove <name>       # Archive a profile without deleting data
```

### 1. Create a profile

```bash
codex-accounts add personal
codex-accounts list
```

This creates `~/.codex-profiles/personal/`. A new profile usually starts without `auth.json`.

### 2. Log in to a profile

Use full `CODEX_HOME` compatibility mode only to log in an empty profile:

```bash
codex-accounts home switch personal
codex-accounts home run -- codex
```

After OAuth completes, confirm the profile has auth:

```bash
codex-accounts list
codex-accounts auth paths personal
```

### 3. Switch profiles

Return to auth-only mode so Codex keeps using native `~/.codex` runtime state:

```bash
codex-accounts switch personal
```

If `eval "$(codex-accounts auth-init)"` is installed, `switch` first clears `CODEX_HOME` in the current shell, then backs up the current native `~/.codex/auth.json` and replaces it from the profile.

### 4. Verify a profile works

```bash
codex-accounts auth paths personal
codex-accounts auth backups
codex
```

To test the full-mode profile itself without changing the current shell:

```bash
codex-accounts home run -- codex
```

### 5. Remove a profile

```bash
codex-accounts remove personal
```

`remove` asks you to type the profile name, then moves the data under `~/.codex-profiles/_removed/`. It does not directly delete `auth.json` or runtime artifacts.

### 6. Restore the previous native auth

```bash
codex-accounts auth revert
```

Or inspect and restore a specific backup:

```bash
codex-accounts auth backups
codex-accounts auth restore auth-20260601T120000Z-12345.json
```

## Shared Config Examples

```bash
codex-accounts config edit
# Opens ~/.codex-profiles/_shared/config.toml in $EDITOR
# Save -> applies to ALL linked profiles immediately

codex-accounts config status
# Shared config: /home/you/.codex-profiles/_shared/config.toml
#   42 lines, 3 MCP server(s)
#
# Per-profile config.toml:
#   work        linked    -> shared
#   personal    linked    -> shared
```

If one profile needs different settings:

```bash
codex-accounts config unlink personal
$EDITOR ~/.codex-profiles/personal/config.toml

codex-accounts config link personal --force
```

## Auth Backup Maintenance

```bash
codex-accounts auth backups
codex-accounts auth prune-backups --keep 3
```

`prune-backups` only removes older managed backup files after explicit confirmation. It ignores malformed entries and symlinks.

## Auth-required vs incidental state

| Path | Scope | Used by minimal auth commands? |
|---|---|---|
| `auth.json` | Identity/authentication | Yes |
| `_shared/auth-backups/auth-*.json` | Native auth rollback | Yes |
| `config.toml` | MCP servers, settings, model defaults | No, shared/profile config only |
| `sessions/`, `history.jsonl`, `log/`, `cache/` | Runtime history and diagnostics | No |
| `hooks/`, `skills/`, `agents/`, `generated_images/` | Tooling/runtime artifacts | No |

Minimal auth commands print paths and status only. They do not print token values or auth file contents.

## What's shared vs private

| File or directory | Scope |
|---|---|
| `_shared/config.toml` | Shared via symlink |
| `_shared/auth-backups/` | Managed native auth backups |
| `<profile>/auth.json` | Private per profile |
| `<profile>/sessions/`, `<profile>/history.jsonl`, `<profile>/log/` | Private full-mode runtime state |
| `_removed/<profile>-removed-*` | Archived removed profiles |

## Layout on disk

```
~/.codex-profiles/
├── _shared/
│   ├── config.toml              # The real shared config
│   └── auth-backups/
│       └── auth-*.json          # Managed native auth backups
├── _removed/
│   └── work-removed-.../        # Preserved profile archives
├── .active                      # Plain text: active full-mode profile name
├── work/
│   ├── auth.json
│   ├── config.toml -> ../_shared/config.toml
│   ├── sessions/
│   └── ...
└── personal/
    ├── auth.json
    ├── config.toml -> ../_shared/config.toml
    └── ...
```

## Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `CODEX_HOME` | Where Codex CLI reads its state. Set only by explicit full compatibility commands (`home env`, `home run`, `home shell-init`) | `~/.codex` |
| `CODEX_PROFILES_DIR` | Where `codex-accounts` stores profile directories | `~/.codex-profiles` |
| `EDITOR` / `VISUAL` | Used by `config edit` | `vi` |

## Troubleshooting

| Situation | Check / fix |
|---|---|
| `codex-accounts switch <name>` fails | Run `codex-accounts auth paths <name>` and confirm `~/.codex-profiles/<name>/auth.json` exists |
| Codex still uses old profile state | Run `echo "$CODEX_HOME"`; auth-only mode should be empty. Install `eval "$(codex-accounts auth-init)"`, or use `unset CODEX_HOME` manually |
| Switched auth by mistake | Run `codex-accounts auth revert` to restore the latest managed backup |
| Need to inspect a full-mode profile | Use `codex-accounts home run -- codex`; avoid `eval "$(codex-accounts home env)"` unless you really want the whole shell to use that profile |
| Want to remove a profile safely | `remove` archives it under `_removed/`; manually clean archives only after checking them |
| `current/env/run/shell-init` fails | These top-level full-mode commands moved to `home current/home env/home run/home shell-init` to avoid mixing with auth-only `switch` |

Important files:

| Path | Importance | Notes |
|---|---|---|
| `~/.codex/auth.json` | High | Native Codex's current identity; `switch` replaces it |
| `~/.codex-profiles/<name>/auth.json` | High | The profile's auth source; required for auth-only switching |
| `~/.codex-profiles/_shared/auth-backups/` | High | Native auth backups created before `switch` |
| `~/.codex/config.toml` / `_shared/config.toml` | Medium | MCP, model, and approval settings; not the auth-only switch target |
| `sessions/`, `history.jsonl`, `logs_*.sqlite*` | Medium | Conversation and diagnostics state; avoid automatic cross-profile merges |
| `skills/`, `agents/`, `hooks/` | Medium | Codex tooling; native `~/.codex` should usually be the source of truth |
| `cache/`, `.tmp/`, `log/` | Low | Usually rebuildable or diagnostic-only; still inspect before cleaning |

## Uninstall

```bash
# Remove any legacy `codex-accounts home shell-init` line from ~/.zshrc / ~/.bashrc, then:
unset CODEX_HOME
exec zsh

rm -rf ~/.codex-profiles   # optional, wipes profiles, backups, and archived removals
rm ~/.local/bin/codex-accounts
```

Codex falls back to `~/.codex` once `CODEX_HOME` is unset.
