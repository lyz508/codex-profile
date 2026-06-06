# codex-profile

[![English](https://img.shields.io/badge/lang-English-lightgrey)](README.md)
[![繁體中文](https://img.shields.io/badge/lang-繁體中文-blue)](README.zh-TW.md)

安全切換多個 Codex CLI 帳號。

`codex-profile` 現在支援兩種模式：

- **Minimal auth replacement**：只在命名 profile 和原生 `~/.codex/auth.json` 之間複製 `auth.json`。這是建議的帳號切換方式，因為 sessions、logs、hooks、skills、agents、generated files，以及其他 runtime state 都會留在 Codex 原生管理的 `~/.codex`。
- **完整 `CODEX_HOME` 相容模式**：保留舊行為，讓 `switch`、`env`、`run`、`shell-init` 把 Codex 指到 `~/.codex-profiles/<profile>`。既有工作流仍可繼續使用。

每個 profile 都有自己的 `auth.json`。`config.toml` 預設透過 `~/.codex-profiles/_shared/config.toml` 在所有 profile 間共用。

## 安裝

```bash
mkdir -p ~/.local/bin
mv codex-profile ~/.local/bin/
chmod +x ~/.local/bin/codex-profile

# 可選：讓新 shell 自動套用完整 CODEX_HOME 相容模式。
echo 'eval "$(codex-profile shell-init)"' >> ~/.zshrc
exec zsh
```

## 指令列表

### Profile 管理

| 指令 | 作用 |
|---|---|
| `list` (alias: `ls`) | 列出所有 profile，以 `*` 標示 active full-mode profile，並顯示登入狀態 |
| `current` (alias: `active`) | 印出目前 active full-mode profile 名稱 |
| `add <name>` | 建立空 profile。第一次以 full mode 跑 `codex` 時可觸發 OAuth |
| `import-current [name]` | 把現有 `~/.codex` 複製成新 profile（預設名稱 `default`）。首次 import 時會把它的 `config.toml` 升格為 shared file |
| `switch <name>` (alias: `use`) | 把 `<name>` 設成 active 的完整 `CODEX_HOME` 相容 profile。不會修改原生 auth |
| `remove <name>` (alias: `rm`) | 停用 profile，並把資料保存在 `_removed/` 底下（需要輸入 profile 名稱確認） |

### Minimal auth replacement

這些指令只操作 `auth.json`。它們不會複製 sessions、history、logs、cache、hooks、skills、agents、generated images 或 GSD artifacts。

| 指令 | 作用 |
|---|---|
| `auth paths <profile>` | 預覽 auth-required source、target、backup 路徑，不讀取 token 內容 |
| `auth switch <profile>` | 先備份原生 `~/.codex/auth.json`，再用 `<profile>/auth.json` 取代它 |
| `auth backups` | 列出 managed native auth backups，不讀取 auth 內容 |
| `auth restore [backup]` | 還原最新或指定名稱的 native auth backup |
| `auth revert` | 還原最新的 managed native auth backup |
| `auth prune-backups --keep <count>` | 輸入 `prune` 確認後，刪除較舊的 managed auth backups |
| `auth help` | 顯示 `auth` 子指令說明 |

### 完整 `CODEX_HOME` 相容模式

| 指令 | 作用 |
|---|---|
| `env` | 印出 active full-mode profile 的 `export CODEX_HOME=...`，可搭配 `eval "$(codex-profile env)"` |
| `run -- <cmd> [args]` (alias: `exec`) | 用 active full-mode profile 的 `CODEX_HOME` 跑 `<cmd>` |
| `shell-init` (alias: `init`) | 印出可加入 `~/.zshrc` / `~/.bashrc` 的 snippet，讓新 shell 自動套用 active full-mode profile |

### Shared config (`config.toml`)

`config.toml`（MCP servers、`[features]`、model defaults）會從每個 profile symlink 到 `~/.codex-profiles/_shared/config.toml`。改一次，所有 linked profiles 立刻生效。

| 指令 | 作用 |
|---|---|
| `config status` | 顯示 shared config 路徑，以及每個 profile 的 link 狀態（linked / local / missing / broken） |
| `config path` | 印出 shared `config.toml` 的路徑 |
| `config edit` | 用 `$EDITOR` 開 shared `config.toml` |
| `config link <profile> [--force]` | 把指定 profile 的 `config.toml` 重新 link 到 shared。`--force` 會覆蓋 local copy |
| `config unlink <profile>` | 把指定 profile 從 shared 拆開（變成 private copy） |
| `config relink-all [--force]` | 把所有 profile 重新 link 到 shared |
| `config help` | 顯示 `config` 子指令說明 |

### 其他

| 指令 | 作用 |
|---|---|
| `help` (alias: `-h`, `--help`) | 顯示總體用法 |

## 使用範例

### 1. 收編既有的原生 Codex 登入

如果你已經有登入過的 `~/.codex`，可以把它 import 成命名 profile：

```bash
codex-profile import-current work
codex-profile list
# *  work    logged in
```

這會得到一份 profile-local 的目前 Codex state，也會產生之後可給 minimal auth replacement 使用的 profile `auth.json`。

### 2. 新增另一個帳號

完整相容模式仍可建立並登入獨立 profile：

```bash
codex-profile add personal
codex-profile switch personal
codex-profile run -- codex     # 第二個 ChatGPT 帳號的 OAuth
```

OAuth 完成後，`~/.codex-profiles/personal/auth.json` 就可以當作 minimal-auth source。

### 3. 用 minimal auth replacement 切換身份

當你只想切換 Codex 帳號、並讓一般 runtime state 留在原生 `~/.codex` 時，使用這個方式：

```bash
codex-profile auth paths personal
codex-profile auth switch personal
codex
```

`auth switch` 會先備份目前的原生 `~/.codex/auth.json`，再取代它。它不會碰 `.active`，也不會設定 `CODEX_HOME`。

回到前一份 native auth：

```bash
codex-profile auth revert
```

或列出並還原指定 backup：

```bash
codex-profile auth backups
codex-profile auth restore auth-20260601T120000Z-12345.json
```

### 4. 使用完整 `CODEX_HOME` 相容模式

當你明確想讓 Codex 從某個 profile 目錄讀取所有 state 時，使用這個模式：

```bash
codex-profile switch work
eval "$(codex-profile env)"
codex
```

或只針對單次指令套用，不改目前 shell：

```bash
codex-profile run -- codex
```

> 切換完整 `CODEX_HOME` profile 前，請先關閉正在跑的 Codex processes，避免 OAuth refresh race：
>
> ```bash
> pkill -f codex; sleep 2
> codex-profile switch <name>
> ```

### 5. 從 full profiles 遷移到 minimal auth

1. 保留既有 profiles。
2. 確認每個帳號的 profile 都有 `auth.json`。如果沒有，先用 full mode 跑一次：

   ```bash
   codex-profile switch personal
   codex-profile run -- codex
   ```

3. 預覽 auth-only paths：

   ```bash
   codex-profile auth paths personal
   ```

4. 不移動 runtime state，只切換身份：

   ```bash
   codex-profile auth switch personal
   unset CODEX_HOME
   codex
   ```

5. 必要時回到前一份 native auth：

   ```bash
   codex-profile auth revert
   ```

Full profiles 可以繼續留在磁碟上當 auth sources。如果不再需要某個 profile 作為 active full-mode profile，`remove <name>` 會把它封存在 `_removed/`，不會刪掉內容。

### 6. 編輯 shared config

```bash
codex-profile config edit
# 在 $EDITOR 開 ~/.codex-profiles/_shared/config.toml
# 存檔後 -> 立刻套用到所有 linked profiles

codex-profile config status
# Shared config: /home/you/.codex-profiles/_shared/config.toml
#   42 lines, 3 MCP server(s)
#
# Per-profile config.toml:
#   work        linked    -> shared
#   personal    linked    -> shared
```

如果某個 profile 需要不同設定：

```bash
codex-profile config unlink personal
$EDITOR ~/.codex-profiles/personal/config.toml

codex-profile config link personal --force
```

### 7. Auth backup 維護

```bash
codex-profile auth backups
codex-profile auth prune-backups --keep 3
```

`prune-backups` 只會在明確確認後刪除較舊的 managed backup files。Malformed entries 和 symlinks 會被忽略。

## Auth-required vs incidental state

| 路徑 | 範圍 | Minimal auth 指令會使用？ |
|---|---|---|
| `auth.json` | 身份 / authentication | 會 |
| `_shared/auth-backups/auth-*.json` | Native auth rollback | 會 |
| `config.toml` | MCP servers、settings、model defaults | 不會，只屬於 shared/profile config |
| `sessions/`、`history.jsonl`、`log/`、`cache/` | Runtime history 和 diagnostics | 不會 |
| `hooks/`、`skills/`、`agents/`、`generated_images/` | Tooling/runtime artifacts | 不會 |

Minimal auth 指令只印 paths 和 status。它們不會印 token values 或 auth file contents。

## Shared vs Private

| 檔案或目錄 | 範圍 |
|---|---|
| `_shared/config.toml` | 透過 symlink 共用 |
| `_shared/auth-backups/` | Managed native auth backups |
| `<profile>/auth.json` | 每個 profile 獨立 |
| `<profile>/sessions/`、`<profile>/history.jsonl`、`<profile>/log/` | Private full-mode runtime state |
| `_removed/<profile>-removed-*` | 已移除 profile 的封存 |

## 目錄結構

```
~/.codex-profiles/
├── _shared/
│   ├── config.toml              # 真正的 shared config
│   └── auth-backups/
│       └── auth-*.json          # Managed native auth backups
├── _removed/
│   └── work-removed-.../        # 保留下來的 profile archives
├── .active                      # 純文字：active full-mode profile 名稱
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

## 環境變數

| 變數 | 用途 | 預設值 |
|---|---|---|
| `CODEX_HOME` | Codex CLI 讀取 state 的位置。只有完整相容模式指令（`env`、`run`、`shell-init`）會設定它 | `~/.codex` |
| `CODEX_PROFILES_DIR` | `codex-profile` 存放 profile 目錄的位置 | `~/.codex-profiles` |
| `EDITOR` / `VISUAL` | `config edit` 使用的編輯器 | `vi` |

## 移除

```bash
# 從 ~/.zshrc / ~/.bashrc 移除 shell-init 那行，然後：
unset CODEX_HOME
exec zsh

rm -rf ~/.codex-profiles   # 可選，會清掉 profiles、backups 和 archived removals
rm ~/.local/bin/codex-profile
```

`CODEX_HOME` unset 之後，Codex 會回到預設的 `~/.codex`。
