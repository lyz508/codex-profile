# codex-profile

[![English](https://img.shields.io/badge/lang-English-blue)](README.md)
[![繁體中文](https://img.shields.io/badge/lang-繁體中文-lightgrey)](README.zh-TW.md)

Switch between Codex CLI accounts safely.

`codex-profile` now supports two modes:

- **Minimal auth replacement**: copy only `auth.json` between a named profile and native `~/.codex/auth.json`. This is the recommended identity-switching path because sessions, logs, hooks, skills, agents, generated files, and other runtime state stay under native Codex management.
- **Full `CODEX_HOME` compatibility mode**: keep the older behavior where `switch`, `env`, `run`, and `shell-init` point Codex at `~/.codex-profiles/<profile>`. This remains available for existing workflows.

Each profile stores its own `auth.json`. `config.toml` is shared across profiles by default through `~/.codex-profiles/_shared/config.toml`.

## Install

```bash
mkdir -p ~/.local/bin
mv codex-profile ~/.local/bin/
chmod +x ~/.local/bin/codex-profile

# Optional: auto-apply full CODEX_HOME compatibility mode in new shells.
echo 'eval "$(codex-profile shell-init)"' >> ~/.zshrc
exec zsh
```

## Commands

### Profile management

| Command | What it does |
|---|---|
| `list` (alias: `ls`) | Show all profiles, marking the active full-mode profile with `*` and indicating login status |
| `current` (alias: `active`) | Print the active full-mode profile name |
| `add <name>` | Create an empty profile. First `codex` run in full mode can trigger OAuth |
| `import-current [name]` | Copy existing `~/.codex` into a new profile (default name: `default`). On first import, promotes its `config.toml` to the shared file |
| `switch <name>` (alias: `use`) | Make `<name>` the active full `CODEX_HOME` compatibility profile. Does not modify native auth |
| `remove <name>` (alias: `rm`) | Deactivate a profile and preserve its data under `_removed/` (requires typing the name to confirm) |

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
| `env` | Print `export CODEX_HOME=...` for the active full-mode profile. Use with `eval "$(codex-profile env)"` |
| `run -- <cmd> [args]` (alias: `exec`) | Run `<cmd>` with `CODEX_HOME` set to the active full-mode profile |
| `shell-init` (alias: `init`) | Print a snippet to add to `~/.zshrc` / `~/.bashrc` so new shells auto-apply the active full-mode profile |

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

## Usage examples

### 1. Adopt an existing native Codex login

If you already have a logged-in `~/.codex`, import it as a named profile:

```bash
codex-profile import-current work
codex-profile list
# *  work    logged in
```

This gives you a profile-local copy of the current Codex state and a profile `auth.json` that can later be used by minimal auth replacement.

### 2. Add another account

Full compatibility mode can still create and log in an isolated profile:

```bash
codex-profile add personal
codex-profile switch personal
codex-profile run -- codex     # OAuth for the second ChatGPT account
```

After OAuth completes, `~/.codex-profiles/personal/auth.json` can be used as a minimal-auth source.

### 3. Switch identity with minimal auth replacement

Use this when you only want to change the Codex account and keep normal runtime state in native `~/.codex`:

```bash
codex-profile auth paths personal
codex-profile auth switch personal
codex
```

`auth switch` backs up the current native `~/.codex/auth.json` before replacing it. It does not touch `.active` and does not set `CODEX_HOME`.

To return to the previous native auth:

```bash
codex-profile auth revert
```

Or inspect and restore a specific backup:

```bash
codex-profile auth backups
codex-profile auth restore auth-20260601T120000Z-12345.json
```

### 4. Use full `CODEX_HOME` compatibility mode

Use this when you intentionally want Codex to read all state from a profile directory:

```bash
codex-profile switch work
eval "$(codex-profile env)"
codex
```

Or run a single command without changing the current shell:

```bash
codex-profile run -- codex
```

> Kill running Codex processes before switching full `CODEX_HOME` profiles. Otherwise concurrent OAuth refreshes can race:
>
> ```bash
> pkill -f codex; sleep 2
> codex-profile switch <name>
> ```

### 5. Migrate from full profiles to minimal auth

1. Keep your existing profiles.
2. For each account, make sure the profile has an `auth.json`. If not, run it once in full mode:

   ```bash
   codex-profile switch personal
   codex-profile run -- codex
   ```

3. Preview the auth-only paths:

   ```bash
   codex-profile auth paths personal
   ```

4. Switch identity without moving runtime state:

   ```bash
   codex-profile auth switch personal
   unset CODEX_HOME
   codex
   ```

5. If needed, return to the previous native auth:

   ```bash
   codex-profile auth revert
   ```

Full profiles can stay on disk as auth sources. If you no longer need one as an active full-mode profile, `remove <name>` archives it under `_removed/` instead of deleting its contents.

### 6. Editing shared config

```bash
codex-profile config edit
# Opens ~/.codex-profiles/_shared/config.toml in $EDITOR
# Save -> applies to ALL linked profiles immediately

codex-profile config status
# Shared config: /home/you/.codex-profiles/_shared/config.toml
#   42 lines, 3 MCP server(s)
#
# Per-profile config.toml:
#   work        linked    -> shared
#   personal    linked    -> shared
```

If one profile needs different settings:

```bash
codex-profile config unlink personal
$EDITOR ~/.codex-profiles/personal/config.toml

codex-profile config link personal --force
```

### 7. Auth backup maintenance

```bash
codex-profile auth backups
codex-profile auth prune-backups --keep 3
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
| `CODEX_HOME` | Where Codex CLI reads its state. Set only by full compatibility commands (`env`, `run`, `shell-init`) | `~/.codex` |
| `CODEX_PROFILES_DIR` | Where `codex-profile` stores profile directories | `~/.codex-profiles` |
| `EDITOR` / `VISUAL` | Used by `config edit` | `vi` |

## Uninstall

```bash
# Remove the shell-init line from ~/.zshrc / ~/.bashrc, then:
unset CODEX_HOME
exec zsh

rm -rf ~/.codex-profiles   # optional, wipes profiles, backups, and archived removals
rm ~/.local/bin/codex-profile
```

Codex falls back to `~/.codex` once `CODEX_HOME` is unset.
