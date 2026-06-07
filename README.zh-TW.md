# codex-profile

[![English](https://img.shields.io/badge/lang-English-lightgrey)](README.md)
[![繁體中文](https://img.shields.io/badge/lang-繁體中文-blue)](README.zh-TW.md)

安全切換多個 Codex CLI 帳號。

`codex-profile` 現在支援兩種模式：

- **Auth-only switching**：只在命名 profile 和原生 `~/.codex/auth.json` 之間複製 `auth.json`。這是預設帳號切換方式，因為 sessions、logs、hooks、skills、agents、generated files，以及其他 runtime state 都會留在 Codex 原生管理的 `~/.codex`。
- **完整 `CODEX_HOME` 相容模式**：保留在 `codex-profile home <subcommand>` 底下，讓 Codex 從 `~/.codex-profiles/<profile>` 讀取全部 state。這仍可用於空 profile 的一次性 OAuth 或既有工作流。

每個 profile 都有自己的 `auth.json`。`config.toml` 預設透過 `~/.codex-profiles/_shared/config.toml` 在所有 profile 間共用。

## 安裝

```bash
mkdir -p ~/.local/bin
mv codex-profile ~/.local/bin/
chmod +x ~/.local/bin/codex-profile

# 可選的 legacy full-mode hook：
# echo 'eval "$(codex-profile home shell-init)"' >> ~/.zshrc
```

## 指令列表

### Profile 管理

| 指令 | 作用 |
|---|---|
| `list` (alias: `ls`) | 列出所有 profile，以 `*` 標示 active full-mode profile，並顯示登入狀態 |
| `current` (alias: `active`) | 已移到 `home current`，用於 full-mode profile |
| `add <name>` | 建立空 profile。第一次以 full mode 跑 `codex` 時可觸發 OAuth |
| `import-current [name]` | 把現有 `~/.codex` 複製成新 profile（預設名稱 `default`）。首次 import 時會把它的 `config.toml` 升格為 shared file |
| `switch <name>` (alias: `use`) | Auth-only switch：先備份原生 `~/.codex/auth.json`，再用 profile auth 取代 |
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
| `home switch <profile>` (alias: `home use`) | 把 `<profile>` 設成 active full `CODEX_HOME` 相容 profile |
| `home current` (alias: `home active`) | 印出目前 active full-mode profile 名稱 |
| `home env` | 印出 active full-mode profile 的 `export CODEX_HOME=...`，可搭配 `eval "$(codex-profile home env)"` |
| `home run -- <cmd> [args]` (alias: `home exec`) | 用 active full-mode profile 的 `CODEX_HOME` 跑 `<cmd>` |
| `home shell-init` (alias: `home init`) | 印出 legacy full-mode shell integration snippet |

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

## Minimal Workflow

`codex-profile` 的日常用法是 auth-only：profile 只提供 `auth.json`，Codex 的 sessions、AGENTS、skills、logs 和其他 runtime state 仍留在原生 `~/.codex`。

```text
codex-profile add <name>          # 建立 profile
codex-profile home run -- codex   # 只用於登入空 profile
codex-profile switch <name>       # 切換 native ~/.codex/auth.json
codex-profile list                # 檢查 profile 狀態
codex-profile remove <name>       # 封存 profile，不直接刪資料
```

### 1. 建立 profile

```bash
codex-profile add personal
codex-profile list
```

這會建立 `~/.codex-profiles/personal/`。新 profile 一開始通常沒有 `auth.json`。

### 2. 登入 profile

只在登入空 profile 時使用 full `CODEX_HOME` 相容模式：

```bash
codex-profile home switch personal
codex-profile home run -- codex
```

OAuth 完成後，確認 profile 已有 auth：

```bash
codex-profile list
codex-profile auth paths personal
```

### 3. 切換 profile

回到 auth-only 模式，讓 Codex 繼續使用原生 `~/.codex` runtime state：

```bash
unset CODEX_HOME
codex-profile switch personal
```

`switch` 會先備份目前的 native `~/.codex/auth.json`，再用 profile 的 `auth.json` 取代它。

### 4. 驗證 profile 能不能動

```bash
codex-profile auth paths personal
codex-profile auth backups
codex
```

如果你只想確認 full-mode profile 本身能啟動，不改目前 shell：

```bash
codex-profile home run -- codex
```

### 5. 刪除 profile

```bash
codex-profile remove personal
```

`remove` 會要求輸入 profile 名稱確認，然後把資料移到 `~/.codex-profiles/_removed/`，不會直接刪掉 `auth.json` 或 runtime artifacts。

### 6. 回復上一份 native auth

```bash
codex-profile auth revert
```

或列出並還原指定 backup：

```bash
codex-profile auth backups
codex-profile auth restore auth-20260601T120000Z-12345.json
```

## Shared Config 範例

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

## Auth Backup 維護

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
| `CODEX_HOME` | Codex CLI 讀取 state 的位置。只有明確的完整相容模式指令（`home env`、`home run`、`home shell-init`）會設定它 | `~/.codex` |
| `CODEX_PROFILES_DIR` | `codex-profile` 存放 profile 目錄的位置 | `~/.codex-profiles` |
| `EDITOR` / `VISUAL` | `config edit` 使用的編輯器 | `vi` |

## Troubleshooting

| 情況 | 檢查 / 處理 |
|---|---|
| `codex-profile switch <name>` 失敗 | 跑 `codex-profile auth paths <name>`；確認 `~/.codex-profiles/<name>/auth.json` 存在 |
| Codex 還在使用舊 profile state | 跑 `echo "$CODEX_HOME"`；auth-only 模式應該是空值。需要時 `unset CODEX_HOME` |
| 誤切 auth | 跑 `codex-profile auth revert` 還原最新 managed backup |
| 想看 full-mode profile | 使用 `codex-profile home run -- codex`，不要 `eval "$(codex-profile home env)"`，除非你真的要整個 shell 改用該 profile |
| 想刪 profile 但怕資料遺失 | `remove` 會封存到 `_removed/`；確認後再手動清理 archive |
| `current/env/run/shell-init` 報錯 | 這些 top-level full-mode 指令已移到 `home current/home env/home run/home shell-init`，避免和 auth-only `switch` 混用 |

重要檔案：

| 路徑 | 重要性 | 備註 |
|---|---|---|
| `~/.codex/auth.json` | 高 | Native Codex 目前使用的登入身份；`switch` 會替換它 |
| `~/.codex-profiles/<name>/auth.json` | 高 | 該 profile 的 auth source；沒有它就不能 auth-only switch |
| `~/.codex-profiles/_shared/auth-backups/` | 高 | `switch` 前建立的 native auth backups |
| `~/.codex/config.toml` / `_shared/config.toml` | 中 | MCP、model、approval 等設定；不是 auth-only 切換目標 |
| `sessions/`、`history.jsonl`、`logs_*.sqlite*` | 中 | 對話與診斷 state；不建議自動合併不同 profile |
| `skills/`、`agents/`、`hooks/` | 中 | Codex tooling；native `~/.codex` 通常應該是主來源 |
| `cache/`、`.tmp/`、`log/` | 低 | 通常可重建或只供診斷，清理前仍先確認 |

## 移除

```bash
# 從 ~/.zshrc / ~/.bashrc 移除任何 legacy `codex-profile home shell-init` 那行，然後：
unset CODEX_HOME
exec zsh

rm -rf ~/.codex-profiles   # 可選，會清掉 profiles、backups 和 archived removals
rm ~/.local/bin/codex-profile
```

`CODEX_HOME` unset 之後，Codex 會回到預設的 `~/.codex`。
