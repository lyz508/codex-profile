#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
TARGET="${BIN_DIR}/codex-accounts"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${SOURCE_DIR}/codex-accounts"

die() {
    echo "error: $*" >&2
    exit 1
}

detect_shell_rc() {
    local shell_name
    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh)  echo "${HOME}/.zshrc" ;;
        bash) echo "${HOME}/.bashrc" ;;
        *)    echo "${HOME}/.profile" ;;
    esac
}

path_contains_bin_dir() {
    case ":${PATH}:" in
        *":${BIN_DIR}:"*) return 0 ;;
        *) return 1 ;;
    esac
}

append_path_export() {
    local rc_file="$1"
    local marker="# codex-accounts installer"
    local line='export PATH="$HOME/.local/bin:$PATH"'

    mkdir -p "$(dirname "$rc_file")"
    touch "$rc_file"
    if grep -Fq "$line" "$rc_file"; then
        echo "PATH export already exists in $rc_file"
        return 0
    fi

    {
        echo
        echo "$marker"
        echo "$line"
    } >> "$rc_file"
    echo "Added PATH export to $rc_file"
}

[[ -f "$SOURCE" ]] || die "codex-accounts executable not found next to install.sh"

mkdir -p "$BIN_DIR"
install -m 755 "$SOURCE" "$TARGET"
echo "Installed codex-accounts to $TARGET"

if ! path_contains_bin_dir; then
    rc_file="$(detect_shell_rc)"
    printf '%s is not in PATH. Add it to %s? (Y/n) ' "$BIN_DIR" "$rc_file"
    read -r answer
    case "$answer" in
        ""|[Yy]|[Yy][Ee][Ss])
            append_path_export "$rc_file"
            echo "Restart your shell or run: source $rc_file"
            ;;
        *)
            echo "Skipped PATH update. Add this manually if needed:"
            echo '  export PATH="$HOME/.local/bin:$PATH"'
            ;;
    esac
else
    echo "$BIN_DIR is already in PATH"
fi
