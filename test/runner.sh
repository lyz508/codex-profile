#!/usr/bin/env bash
set -euo pipefail

TEST_NAME=""
TEST_TMP=""
HOME_FIXTURE=""
PROFILES=""
STUB_BIN=""
STATUS_FILE=""
STDOUT_FILE=""
STDERR_FILE=""
TESTS_RUN=0
TESTS_FAILED=0
CURRENT_TEST_FAILED=0

REAL_HOME="${HOME:-}"
REAL_CODEX="$REAL_HOME/.codex"
REAL_PROFILES="$REAL_HOME/.codex-profiles"

fail() {
    echo "FAIL: $TEST_NAME: $*" >&2
    CURRENT_TEST_FAILED=1
    return 1
}

assert_safe_path() {
    local path="$1"
    [[ -n "$path" ]] || fail "empty path"
    case "$path" in
        "$REAL_CODEX"|"$REAL_CODEX"/*|"$REAL_PROFILES"|"$REAL_PROFILES"/*|/home/yzlin/.codex|/home/yzlin/.codex/*|/home/yzlin/.codex-profiles|/home/yzlin/.codex-profiles/*)
            fail "unsafe real state path: $path"
            ;;
    esac
}

assert_no_real_state_paths() {
    assert_safe_path "$HOME_FIXTURE"
    assert_safe_path "$PROFILES"
    [[ "$HOME_FIXTURE" == "$TEST_TMP"/home ]] || fail "HOME fixture outside test tmp"
    [[ "$PROFILES" == "$TEST_TMP"/profiles ]] || fail "profiles outside test tmp"
}

setup_test() {
    TEST_TMP="$(mktemp -d)"
    HOME_FIXTURE="$TEST_TMP/home"
    PROFILES="$TEST_TMP/profiles"
    STUB_BIN="$TEST_TMP/bin"
    STATUS_FILE="$TEST_TMP/status"
    STDOUT_FILE="$TEST_TMP/stdout"
    STDERR_FILE="$TEST_TMP/stderr"
    mkdir -p "$HOME_FIXTURE" "$PROFILES" "$STUB_BIN"
    cat > "$STUB_BIN/pgrep" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
    chmod +x "$STUB_BIN/pgrep"
    assert_no_real_state_paths
}

cleanup_test() {
    if [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]]; then
        rm -rf "$TEST_TMP"
    fi
}

run_cli() {
    assert_no_real_state_paths
    : > "$STDOUT_FILE"
    : > "$STDERR_FILE"
    set +e
    HOME="$HOME_FIXTURE" CODEX_PROFILES_DIR="$PROFILES" PATH="$STUB_BIN:$PATH" bash ./codex-accounts "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
    local status=$?
    set -e
    printf '%s' "$status" > "$STATUS_FILE"
    return 0
}

run_cli_with_stdin() {
    local input="$1"
    shift
    assert_no_real_state_paths
    : > "$STDOUT_FILE"
    : > "$STDERR_FILE"
    set +e
    HOME="$HOME_FIXTURE" CODEX_PROFILES_DIR="$PROFILES" PATH="$STUB_BIN:$PATH" bash ./codex-accounts "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE" <<<"$input"
    local status=$?
    set -e
    printf '%s' "$status" > "$STATUS_FILE"
    return 0
}

status_value() {
    cat "$STATUS_FILE"
}

assert_status() {
    local expected="$1"
    local actual
    actual="$(status_value)"
    [[ "$actual" == "$expected" ]] || fail "expected status $expected, got $actual; stdout=$(cat "$STDOUT_FILE"); stderr=$(cat "$STDERR_FILE")"
}

assert_status_nonzero() {
    local actual
    actual="$(status_value)"
    [[ "$actual" != "0" ]] || fail "expected non-zero status; stdout=$(cat "$STDOUT_FILE"); stderr=$(cat "$STDERR_FILE")"
}

assert_stdout_contains() {
    grep -Fq "$1" "$STDOUT_FILE" || fail "stdout missing: $1; stdout=$(cat "$STDOUT_FILE")"
}

assert_stderr_contains() {
    grep -Fq "$1" "$STDERR_FILE" || fail "stderr missing: $1; stderr=$(cat "$STDERR_FILE")"
}

assert_stdout_not_contains() {
    grep -Fq "$1" "$STDOUT_FILE" && fail "stdout unexpectedly contained forbidden text: $1"
    return 0
}

assert_stderr_not_contains() {
    grep -Fq "$1" "$STDERR_FILE" && fail "stderr unexpectedly contained forbidden text: $1"
    return 0
}

assert_output_not_contains_secret_markers() {
    local marker
    for marker in "$@"; do
        assert_stdout_not_contains "$marker"
        assert_stderr_not_contains "$marker"
    done
}

assert_file_exists() {
    [[ -e "$1" ]] || fail "missing file: $1"
}

assert_file_not_exists() {
    [[ ! -e "$1" ]] || fail "file exists unexpectedly: $1"
}

assert_symlink() {
    [[ -L "$1" ]] || fail "not a symlink: $1"
}

assert_file_content() {
    local file="$1" expected="$2" actual
    actual="$(cat "$file")"
    [[ "$actual" == "$expected" ]] || fail "expected $file content '$expected', got '$actual'"
}

removed_archives_for() {
    local name="$1"
    find "$PROFILES/_removed" -mindepth 1 -maxdepth 1 -type d -name "$name-removed-*" 2>/dev/null | sort || true
}

assert_single_removed_archive() {
    local name="$1" archives count
    archives="$(removed_archives_for "$name")"
    count="$(printf '%s\n' "$archives" | sed '/^$/d' | wc -l | tr -d ' ')"
    [[ "$count" == "1" ]] || fail "expected exactly one removed archive for $name, got $count"
    printf '%s\n' "$archives"
}

assert_files_same_without_printing() {
    local left="$1" right="$2"
    cmp -s "$left" "$right" || fail "files differ: $left $right"
}

write_auth_fixture() {
    local path="$1" marker="$2"
    mkdir -p "$(dirname "$path")"
    printf '{"auth_mode":"chatgpt","tokens":{"access_token":"%s-access","refresh_token":"%s-refresh","account_id":"%s-account"},"last_refresh":"fixture"}\n' "$marker" "$marker" "$marker" > "$path"
    chmod 600 "$path" 2>/dev/null || true
}

test_lifecycle_commands_are_isolated() {
    run_cli add work
    assert_status 0
    assert_file_exists "$PROFILES/work"
    assert_symlink "$PROFILES/work/config.toml"

    run_cli home switch work
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"

    run_cli home current
    assert_status 0
    assert_stdout_contains "work"

    run_cli home env
    assert_status 0
    assert_stdout_contains "CODEX_HOME=$PROFILES/work"

    run_cli home run -- sh -c 'printf "%s" "$CODEX_HOME"'
    assert_status 0
    assert_stdout_contains "$PROFILES/work"

    run_cli_with_stdin work remove work
    assert_status 0
    assert_file_not_exists "$PROFILES/work"
    assert_file_not_exists "$PROFILES/.active"
    local archive
    archive="$(assert_single_removed_archive work)"
    assert_file_exists "$archive"
}

test_shared_config_status_and_linking() {
    run_cli add work
    assert_status 0
    run_cli add personal
    assert_status 0
    rm -f "$PROFILES/personal/config.toml"
    printf 'local = true\n' > "$PROFILES/personal/config.toml"
    mkdir -p "$PROFILES/broken"
    ln -s "$TEST_TMP/missing.toml" "$PROFILES/broken/config.toml"
    mkdir -p "$PROFILES/missing"

    run_cli config status
    assert_status 0
    assert_stdout_contains "work"
    assert_stdout_contains "linked"
    assert_stdout_contains "personal"
    assert_stdout_contains "local"
    assert_stdout_contains "broken"
    assert_stdout_contains "missing"

    run_cli config link personal
    assert_status_nonzero
    assert_stderr_contains "personal/config.toml is a local file"
    assert_file_content "$PROFILES/personal/config.toml" "local = true"

    run_cli config link personal --force
    assert_status 0
    assert_symlink "$PROFILES/personal/config.toml"

    run_cli config unlink personal
    assert_status 0
    [[ ! -L "$PROFILES/personal/config.toml" ]] || fail "personal config should be private"

    run_cli config relink-all
    assert_status_nonzero
    assert_stderr_contains "personal"
    [[ ! -L "$PROFILES/personal/config.toml" ]] || fail "local config should remain unchanged after skipped relink-all"
    assert_symlink "$PROFILES/broken/config.toml"
    [[ ! -e "$PROFILES/_shared/config.toml/config.toml" ]] || fail "_shared treated as profile"
}

test_invalid_cli_names_are_rejected() {
    for name in "../evil" "bad/name" ".active" "_shared" "_removed" ""; do
        run_cli add "$name"
        assert_status_nonzero
    done
    assert_file_not_exists "$TEST_TMP/evil"
    run_cli add work
    assert_status 0
    run_cli add team-prod
    assert_status 0
    run_cli add personal_1
    assert_status 0
}

test_invalid_active_state_is_rejected() {
    run_cli add work
    assert_status 0
    printf '../evil\n' > "$PROFILES/.active"

    run_cli home current
    assert_status_nonzero
    assert_stderr_contains "active profile state is invalid"
    run_cli home env
    assert_status_nonzero
    assert_stderr_contains "active profile state is invalid"
    run_cli home run -- true
    assert_status_nonzero
    assert_stderr_contains "active profile state is invalid"

    run_cli home shell-init
    assert_status 0
    CODEX_HOME= HOME="$HOME_FIXTURE" CODEX_PROFILES_DIR="$PROFILES" bash -c "$(cat "$STDOUT_FILE"); [[ -z \"\${CODEX_HOME:-}\" ]]"
}

test_list_and_config_status_skip_invalid_dirs() {
    run_cli add work
    assert_status 0
    mkdir -p "$PROFILES/bad name" "$PROFILES/.hidden" "$PROFILES/_shared" "$PROFILES/_removed"

    run_cli list
    assert_status 0
    assert_stdout_contains "work"
    assert_stdout_not_contains "_removed"
    assert_stderr_contains "warning: skipping invalid profile directory: bad name"
    assert_stderr_contains "warning: skipping invalid profile directory: .hidden"

    run_cli config status
    assert_status 0
    assert_stdout_contains "work"
    assert_stdout_not_contains "_removed"
    assert_stderr_contains "warning: skipping invalid profile directory: bad name"
}

test_atomic_active_writes_for_switch_and_import() {
    run_cli add work
    assert_status 0
    run_cli home switch work
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"
    compgen -G "$PROFILES/.active.tmp.*" >/dev/null && fail "temporary active files remain after switch"

    mkdir -p "$HOME_FIXTURE/.codex"
    printf 'auth\n' > "$HOME_FIXTURE/.codex/auth.json"
    printf 'model = "x"\n' > "$HOME_FIXTURE/.codex/config.toml"
    run_cli import-current imported
    assert_status 0
    assert_file_exists "$PROFILES/imported/auth.json"
    assert_symlink "$PROFILES/imported/config.toml"
    assert_file_content "$PROFILES/.active" "imported"
    compgen -G "$PROFILES/.active.tmp.*" >/dev/null && fail "temporary active files remain after import-current"

    ! grep -v '^[[:space:]]*#' codex-accounts | grep -E 'echo "\$name" > "\$STATE_FILE"|> "\$STATE_FILE"' >/dev/null || fail "direct STATE_FILE write remains"
}

test_safe_remove_rejects_unmanaged_targets() {
    run_cli add work
    assert_status 0
    run_cli home switch work
    assert_status 0
    run_cli_with_stdin work remove work
    assert_status 0
    assert_file_not_exists "$PROFILES/work"
    assert_file_not_exists "$PROFILES/.active"
    local archive
    archive="$(assert_single_removed_archive work)"
    assert_file_exists "$archive"

    run_cli remove _shared
    assert_status_nonzero
    run_cli remove _removed
    assert_status_nonzero

    run_cli remove "../evil"
    assert_status_nonzero

    local outside="$TEST_TMP/outside"
    mkdir -p "$outside"
    printf 'keep\n' > "$outside/keep.txt"
    ln -s "$outside" "$PROFILES/symlinked"
    run_cli remove symlinked
    assert_status_nonzero
    assert_file_exists "$outside/keep.txt"

    local remove_body
    remove_body="$(sed -n '/cmd_remove()/,/^}/p' codex-accounts)"
    [[ "$remove_body" == *"assert_safe_profile_target"* ]] || fail "cmd_remove does not call assert_safe_profile_target"
    [[ "$remove_body" == *'mv "$path" "$archive_path"'* ]] || fail "cmd_remove does not archive profile with mv"
    [[ "$remove_body" != *'rm -rf "$path"'* ]] || fail "cmd_remove still deletes profile path"
}

test_remove_archives_profile_without_deleting_runtime_artifacts() {
    local marker="REMOVE_AUTH_SECRET"
    run_cli add work
    assert_status 0
    run_cli home switch work
    assert_status 0
    write_auth_fixture "$PROFILES/work/auth.json" "$marker"
    mkdir -p "$PROFILES/work/sessions" "$PROFILES/work/log" "$PROFILES/work/hooks" "$PROFILES/work/skills/example" "$PROFILES/work/agents" "$PROFILES/work/generated_images"
    printf 'session\n' > "$PROFILES/work/sessions/session.jsonl"
    printf 'log\n' > "$PROFILES/work/log/codex.log"
    printf 'history\n' > "$PROFILES/work/history.jsonl"
    printf 'hook\n' > "$PROFILES/work/hooks/hook.sh"
    printf 'skill\n' > "$PROFILES/work/skills/example/SKILL.md"
    printf 'agent\n' > "$PROFILES/work/agents/agent.md"
    printf 'image\n' > "$PROFILES/work/generated_images/image.png"

    run_cli_with_stdin work remove work
    assert_status 0
    assert_file_not_exists "$PROFILES/work"
    assert_file_not_exists "$PROFILES/.active"

    local archive
    archive="$(assert_single_removed_archive work)"
    assert_file_exists "$archive/auth.json"
    assert_file_content "$archive/sessions/session.jsonl" "session"
    assert_file_content "$archive/log/codex.log" "log"
    assert_file_content "$archive/history.jsonl" "history"
    assert_file_content "$archive/hooks/hook.sh" "hook"
    assert_file_content "$archive/skills/example/SKILL.md" "skill"
    assert_file_content "$archive/agents/agent.md" "agent"
    assert_file_content "$archive/generated_images/image.png" "image"
    assert_output_not_contains_secret_markers "$marker" "access_token" "refresh_token" "account_id"

    run_cli list
    assert_status 0
    assert_stdout_not_contains "work"
    assert_stdout_not_contains "_removed"
    assert_output_not_contains_secret_markers "$marker" "access_token" "refresh_token" "account_id"
}

write_process_stubs() {
    local mode="$1"
    case "$mode" in
        exact)
            cat > "$STUB_BIN/pgrep" <<'STUB'
#!/usr/bin/env bash
echo 4242
STUB
            cat > "$STUB_BIN/ps" <<'STUB'
#!/usr/bin/env bash
echo "codex codex"
STUB
            ;;
        unrelated)
            cat > "$STUB_BIN/pgrep" <<'STUB'
#!/usr/bin/env bash
echo 5151
STUB
            cat > "$STUB_BIN/ps" <<'STUB'
#!/usr/bin/env bash
echo "my-codex-not-cli my-codex-not-cli --serve"
STUB
            ;;
        missing)
            rm -f "$STUB_BIN/pgrep" "$STUB_BIN/ps"
            ;;
    esac
    [[ ! -e "$STUB_BIN/pgrep" ]] || chmod +x "$STUB_BIN/pgrep"
    [[ ! -e "$STUB_BIN/ps" ]] || chmod +x "$STUB_BIN/ps"
}

test_process_detection_is_narrow_and_best_effort() {
    run_cli add work
    assert_status 0
    run_cli add personal
    assert_status 0

    run_cli home switch work
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"

    write_process_stubs exact
    run_cli_with_stdin n home switch personal
    assert_status_nonzero
    assert_stderr_contains "warning:"
    assert_stderr_contains "codex process(es) still running"
    assert_file_content "$PROFILES/.active" "work"

    write_process_stubs unrelated
    run_cli home switch personal
    assert_status 0
    assert_file_content "$PROFILES/.active" "personal"

    write_process_stubs missing
    run_cli home switch work
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"

    ! grep -F "pgrep -f 'codex' 2>/dev/null | xargs" codex-accounts >/dev/null || fail "raw pgrep -f codex pipeline remains"
}

test_auth_paths_preview_is_sanitized_and_fixture_safe() {
    local native_marker="NATIVE_SECRET_MARKER"
    local profile_marker="PROFILE_SECRET_MARKER"
    run_cli add work
    assert_status 0
    write_auth_fixture "$HOME_FIXTURE/.codex/auth.json" "$native_marker"
    write_auth_fixture "$PROFILES/work/auth.json" "$profile_marker"

    run_cli auth paths work
    assert_status 0
    assert_stdout_contains "Auth-required files:"
    assert_stdout_contains "auth.json"
    assert_stdout_contains "$HOME_FIXTURE/.codex/auth.json"
    assert_stdout_contains "$PROFILES/work/auth.json"
    assert_stdout_contains "$PROFILES/_shared/auth-backups"
    assert_output_not_contains_secret_markers "$native_marker" "$profile_marker"
    assert_stdout_not_contains "$REAL_CODEX"
    assert_stdout_not_contains "$REAL_PROFILES"

    run_cli auth paths "../evil"
    assert_status_nonzero
    run_cli auth paths missing
    assert_status_nonzero
    assert_output_not_contains_secret_markers "$native_marker" "$profile_marker"

    grep -v '^[[:space:]]*#' codex-accounts | grep -F 'cmd_auth_paths' >/dev/null || fail "cmd_auth_paths missing from source"
}

test_auth_switch_replaces_only_native_auth_and_creates_backup() {
    local native_marker="NATIVE_SWITCH_SECRET"
    local profile_marker="PROFILE_SWITCH_SECRET"
    run_cli add work
    assert_status 0
    write_auth_fixture "$HOME_FIXTURE/.codex/auth.json" "$native_marker"
    write_auth_fixture "$PROFILES/work/auth.json" "$profile_marker"
    mkdir -p "$PROFILES/work/sessions" "$PROFILES/work/log"
    printf 'session\n' > "$PROFILES/work/sessions/session.jsonl"
    printf 'history\n' > "$PROFILES/work/history.jsonl"
    printf 'log\n' > "$PROFILES/work/log/codex.log"
    printf 'profile-config\n' > "$PROFILES/work/config.toml"

    run_cli auth switch work
    assert_status 0
    assert_stdout_contains "Auth-required files:"
    assert_stdout_contains "auth.json"
    assert_stdout_contains "$HOME_FIXTURE/.codex/auth.json"
    assert_stdout_contains "$PROFILES/work/auth.json"
    assert_stdout_contains "$PROFILES/_shared/auth-backups"
    assert_stdout_contains "Backed up native auth.json to:"
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$PROFILES/work/auth.json"

    local backup_count backup_file
    backup_count="$(find "$PROFILES/_shared/auth-backups" -type f -name 'auth-*.json' | wc -l | tr -d ' ')"
    [[ "$backup_count" == "1" ]] || fail "expected exactly one auth backup, got $backup_count"
    backup_file="$(find "$PROFILES/_shared/auth-backups" -type f -name 'auth-*.json' | head -1)"
    grep -Fq "$native_marker" "$backup_file" || fail "backup does not contain original native auth marker"
    [[ "$(basename "$backup_file")" != *"$native_marker"* ]] || fail "backup filename contains native marker"
    [[ "$(basename "$backup_file")" != *"$profile_marker"* ]] || fail "backup filename contains profile marker"

    assert_file_not_exists "$HOME_FIXTURE/.codex/sessions/session.jsonl"
    assert_file_not_exists "$HOME_FIXTURE/.codex/history.jsonl"
    assert_file_not_exists "$HOME_FIXTURE/.codex/log/codex.log"
    [[ ! -f "$HOME_FIXTURE/.codex/config.toml" ]] || fail "auth switch copied config.toml"
    assert_file_not_exists "$PROFILES/.active"
    assert_output_not_contains_secret_markers "$native_marker" "$profile_marker"

    local switch_body preview_line backup_line copy_line
    switch_body="$(sed -n '/cmd_auth_switch()/,/^}/p' codex-accounts)"
    preview_line="$(printf '%s\n' "$switch_body" | grep -n 'preview_auth_switch' | head -1 | cut -d: -f1)"
    backup_line="$(printf '%s\n' "$switch_body" | grep -n 'backup_auth_file' | head -1 | cut -d: -f1)"
    copy_line="$(printf '%s\n' "$switch_body" | grep -n 'copy_auth_without_leaking' | head -1 | cut -d: -f1)"
    [[ -n "$preview_line" && -n "$backup_line" && -n "$copy_line" ]] || fail "cmd_auth_switch missing preview/backup/copy calls"
    [[ "$preview_line" -lt "$backup_line" && "$backup_line" -lt "$copy_line" ]] || fail "cmd_auth_switch call order is not preview -> backup -> copy"
}

test_top_level_switch_is_auth_only() {
    local native_marker="TOP_SWITCH_NATIVE_SECRET"
    local profile_marker="TOP_SWITCH_PROFILE_SECRET"
    run_cli add work
    assert_status 0
    run_cli add personal
    assert_status 0
    run_cli home switch work
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"

    write_auth_fixture "$HOME_FIXTURE/.codex/auth.json" "$native_marker"
    write_auth_fixture "$PROFILES/personal/auth.json" "$profile_marker"

    run_cli switch personal
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$PROFILES/personal/auth.json"
    assert_stdout_contains "native auth.json replaced from profile 'personal'"
    assert_output_not_contains_secret_markers "$native_marker" "$profile_marker" "access_token" "refresh_token" "account_id"

    run_cli list
    assert_status 0
    grep -Eq '^\* personal[[:space:]]+logged in$' "$STDOUT_FILE" || fail "list did not mark personal as current native auth; stdout=$(cat "$STDOUT_FILE")"
}

test_auth_switch_missing_native_auth_is_fixture_safe() {
    local native_marker="NATIVE_MISSING_SOURCE_SECRET"
    local profile_marker="PROFILE_MISSING_NATIVE_SECRET"
    run_cli add work
    assert_status 0
    write_auth_fixture "$PROFILES/work/auth.json" "$profile_marker"

    run_cli auth switch work
    assert_status 0
    assert_stdout_contains "No existing native auth.json to back up."
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$PROFILES/work/auth.json"
    [[ ! -d "$PROFILES/_shared/auth-backups" ]] || [[ -z "$(find "$PROFILES/_shared/auth-backups" -type f -name 'auth-*.json' -print -quit)" ]] || fail "missing-native switch created a backup"
    assert_output_not_contains_secret_markers "$profile_marker"

    run_cli add empty
    assert_status 0
    write_auth_fixture "$HOME_FIXTURE/.codex/auth.json" "$native_marker"
    cp "$HOME_FIXTURE/.codex/auth.json" "$TEST_TMP/native-before.json"
    run_cli auth switch empty
    assert_status_nonzero
    assert_stderr_contains "profile 'empty' has no auth.json"
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$TEST_TMP/native-before.json"
    local backup_count
    backup_count="$(find "$PROFILES/_shared/auth-backups" -type f -name 'auth-*.json' 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$backup_count" == "0" ]] || fail "missing-source switch created a backup"
    assert_output_not_contains_secret_markers "$native_marker"
}

create_backup_fixture() {
    local name="$1" marker="$2"
    write_auth_fixture "$PROFILES/_shared/auth-backups/$name" "$marker"
}

test_auth_backups_list_is_sanitized() {
    local old_marker="BACKUP_OLD_SECRET"
    local new_marker="BACKUP_NEW_SECRET"
    mkdir -p "$PROFILES/_shared/auth-backups"
    create_backup_fixture "auth-20260101T000000Z-100.json" "$old_marker"
    create_backup_fixture "auth-20260102T000000Z-200.json" "$new_marker"
    printf 'ignore\n' > "$PROFILES/_shared/auth-backups/not-auth.json"
    mkdir -p "$PROFILES/_shared/auth-backups/auth-20260103T000000Z-300.json"
    ln -s "$PROFILES/_shared/auth-backups/auth-20260102T000000Z-200.json" "$PROFILES/_shared/auth-backups/auth-20260104T000000Z-400.json"

    run_cli auth backups
    assert_status 0
    assert_stdout_contains "Auth backups:"
    assert_stdout_contains "auth-20260101T000000Z-100.json"
    assert_stdout_contains "auth-20260102T000000Z-200.json"
    assert_stdout_contains "$PROFILES/_shared/auth-backups/auth-20260102T000000Z-200.json"
    assert_stdout_contains "* auth-20260102T000000Z-200.json"
    assert_stdout_not_contains "not-auth.json"
    assert_stdout_not_contains "auth-20260103T000000Z-300.json"
    assert_stdout_not_contains "auth-20260104T000000Z-400.json"
    assert_output_not_contains_secret_markers "$old_marker" "$new_marker" "access_token" "refresh_token" "account_id"

    rm -rf "$PROFILES/_shared/auth-backups"
    run_cli auth backups
    assert_status 0
    assert_stdout_contains "No auth backups found."
}

test_auth_restore_uses_latest_backup_without_leaking_tokens() {
    local old_marker="RESTORE_OLD_SECRET"
    local new_marker="RESTORE_NEW_SECRET"
    local native_marker="RESTORE_NATIVE_SECRET"
    mkdir -p "$PROFILES/_shared/auth-backups"
    create_backup_fixture "auth-20260101T000000Z-100.json" "$old_marker"
    create_backup_fixture "auth-20260102T000000Z-200.json" "$new_marker"
    write_auth_fixture "$HOME_FIXTURE/.codex/auth.json" "$native_marker"

    run_cli auth restore
    assert_status 0
    assert_stdout_contains "Restored native auth.json from:"
    assert_stdout_contains "$PROFILES/_shared/auth-backups/auth-20260102T000000Z-200.json"
    assert_stdout_contains "$HOME_FIXTURE/.codex/auth.json"
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$PROFILES/_shared/auth-backups/auth-20260102T000000Z-200.json"
    assert_output_not_contains_secret_markers "$old_marker" "$new_marker" "$native_marker" "access_token" "refresh_token" "account_id"

    run_cli auth restore auth-20260101T000000Z-100.json
    assert_status 0
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$PROFILES/_shared/auth-backups/auth-20260101T000000Z-100.json"
    assert_output_not_contains_secret_markers "$old_marker" "$new_marker" "$native_marker" "access_token" "refresh_token" "account_id"

    run_cli auth restore "../auth-20260101T000000Z-100.json"
    assert_status_nonzero
    run_cli auth restore "auth-20260101T000000Z-100.json/evil"
    assert_status_nonzero
    ln -s "$PROFILES/_shared/auth-backups/auth-20260101T000000Z-100.json" "$PROFILES/_shared/auth-backups/auth-20260103T000000Z-300.json"
    run_cli auth restore auth-20260103T000000Z-300.json
    assert_status_nonzero
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$PROFILES/_shared/auth-backups/auth-20260101T000000Z-100.json"
    assert_output_not_contains_secret_markers "$old_marker" "$new_marker" "$native_marker"
}

test_auth_revert_restores_latest_backup_without_leaking_tokens() {
    local native_marker="REVERT_NATIVE_SECRET"
    local profile_marker="REVERT_PROFILE_SECRET"
    run_cli add work
    assert_status 0
    write_auth_fixture "$HOME_FIXTURE/.codex/auth.json" "$native_marker"
    cp "$HOME_FIXTURE/.codex/auth.json" "$TEST_TMP/native-original.json"
    write_auth_fixture "$PROFILES/work/auth.json" "$profile_marker"

    run_cli auth switch work
    assert_status 0
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$PROFILES/work/auth.json"
    local backup_count backup_file
    backup_count="$(find "$PROFILES/_shared/auth-backups" -type f -name 'auth-*.json' | wc -l | tr -d ' ')"
    [[ "$backup_count" == "1" ]] || fail "expected exactly one auth backup, got $backup_count"
    backup_file="$(find "$PROFILES/_shared/auth-backups" -type f -name 'auth-*.json' | head -1)"
    assert_files_same_without_printing "$backup_file" "$TEST_TMP/native-original.json"
    assert_output_not_contains_secret_markers "$native_marker" "$profile_marker" "access_token" "refresh_token" "account_id"

    run_cli auth revert
    assert_status 0
    assert_stdout_contains "Reverted native auth.json from latest backup:"
    assert_stdout_contains "$backup_file"
    assert_stdout_contains "$HOME_FIXTURE/.codex/auth.json"
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$TEST_TMP/native-original.json"
    assert_output_not_contains_secret_markers "$native_marker" "$profile_marker" "access_token" "refresh_token" "account_id"

    run_cli auth revert extra
    assert_status_nonzero
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$TEST_TMP/native-original.json"
    assert_output_not_contains_secret_markers "$native_marker" "$profile_marker" "access_token" "refresh_token" "account_id"

    grep -v '^[[:space:]]*#' codex-accounts | grep -F 'cmd_auth_revert' >/dev/null || fail "cmd_auth_revert missing from source"
    grep -v '^[[:space:]]*#' codex-accounts | grep -F 'revert)' >/dev/null || fail "auth revert missing from dispatcher"
    sed -n '/cmd_auth_revert()/,/^}/p' codex-accounts | grep -F 'latest_auth_backup' >/dev/null || fail "cmd_auth_revert does not call latest_auth_backup"
    sed -n '/cmd_auth_revert()/,/^}/p' codex-accounts | grep -F 'copy_auth_without_leaking' >/dev/null || fail "cmd_auth_revert does not call copy_auth_without_leaking"
}

test_auth_revert_without_backup_is_failure_safe() {
    local native_marker="REVERT_NO_BACKUP_NATIVE_SECRET"
    write_auth_fixture "$HOME_FIXTURE/.codex/auth.json" "$native_marker"
    cp "$HOME_FIXTURE/.codex/auth.json" "$TEST_TMP/native-before-revert.json"

    run_cli auth revert
    assert_status_nonzero
    assert_stderr_contains "no auth backups found"
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$TEST_TMP/native-before-revert.json"
    assert_output_not_contains_secret_markers "$native_marker" "access_token" "refresh_token" "account_id"

    mkdir -p "$PROFILES/_shared/auth-backups"
    run_cli auth revert
    assert_status_nonzero
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$TEST_TMP/native-before-revert.json"
    assert_output_not_contains_secret_markers "$native_marker" "access_token" "refresh_token" "account_id"
}

test_auth_prune_backups_requires_explicit_confirmation() {
    local old_marker="PRUNE_OLD_SECRET"
    local mid_marker="PRUNE_MID_SECRET"
    local new_marker="PRUNE_NEW_SECRET"
    mkdir -p "$PROFILES/_shared/auth-backups"
    create_backup_fixture "auth-20260101T000000Z-100.json" "$old_marker"
    create_backup_fixture "auth-20260102T000000Z-200.json" "$mid_marker"
    create_backup_fixture "auth-20260103T000000Z-300.json" "$new_marker"
    printf 'not-a-backup\n' > "$PROFILES/_shared/auth-backups/not-auth.json"
    ln -s "$PROFILES/_shared/auth-backups/auth-20260101T000000Z-100.json" "$PROFILES/_shared/auth-backups/auth-20260104T000000Z-400.json"

    run_cli auth prune-backups
    assert_status_nonzero
    run_cli auth prune-backups --keep nope
    assert_status_nonzero
    run_cli auth prune-backups --keep -1
    assert_status_nonzero

    run_cli_with_stdin wrong auth prune-backups --keep 1
    assert_status_nonzero
    assert_file_exists "$PROFILES/_shared/auth-backups/auth-20260101T000000Z-100.json"
    assert_file_exists "$PROFILES/_shared/auth-backups/auth-20260102T000000Z-200.json"
    assert_file_exists "$PROFILES/_shared/auth-backups/auth-20260103T000000Z-300.json"
    assert_output_not_contains_secret_markers "$old_marker" "$mid_marker" "$new_marker" "access_token" "refresh_token" "account_id"

    run_cli_with_stdin prune auth prune-backups --keep 1
    assert_status 0
    assert_file_not_exists "$PROFILES/_shared/auth-backups/auth-20260101T000000Z-100.json"
    assert_file_not_exists "$PROFILES/_shared/auth-backups/auth-20260102T000000Z-200.json"
    assert_file_exists "$PROFILES/_shared/auth-backups/auth-20260103T000000Z-300.json"
    assert_file_exists "$PROFILES/_shared/auth-backups/not-auth.json"
    [[ -L "$PROFILES/_shared/auth-backups/auth-20260104T000000Z-400.json" ]] || fail "symlink backup was unexpectedly removed"
    assert_output_not_contains_secret_markers "$old_marker" "$mid_marker" "$new_marker" "access_token" "refresh_token" "account_id"

    grep -v '^[[:space:]]*#' codex-accounts | grep -F 'cmd_auth_prune_backups' >/dev/null || fail "cmd_auth_prune_backups missing from source"
    sed -n '/cmd_auth_prune_backups()/,/^}/p' codex-accounts | grep -F 'safe_auth_backup_path' >/dev/null || fail "cmd_auth_prune_backups does not call safe_auth_backup_path"
}

test_full_codex_home_mode_remains_compatible_after_auth_commands() {
    local native_marker="COMPAT_NATIVE_SECRET"
    local personal_marker="COMPAT_PERSONAL_SECRET"
    run_cli add work
    assert_status 0
    run_cli add personal
    assert_status 0
    run_cli home switch work
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"

    run_cli home env
    assert_status 0
    assert_stdout_contains "CODEX_HOME=$PROFILES/work"
    run_cli home run -- sh -c 'printf "%s" "$CODEX_HOME"'
    assert_status 0
    assert_stdout_contains "$PROFILES/work"

    write_auth_fixture "$HOME_FIXTURE/.codex/auth.json" "$native_marker"
    write_auth_fixture "$PROFILES/personal/auth.json" "$personal_marker"
    run_cli auth switch personal
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"

    run_cli home env
    assert_status 0
    assert_stdout_contains "CODEX_HOME=$PROFILES/work"
    assert_stdout_not_contains "$HOME_FIXTURE/.codex"
    run_cli home run -- sh -c 'printf "%s" "$CODEX_HOME"'
    assert_status 0
    assert_stdout_contains "$PROFILES/work"
    assert_stdout_not_contains "$HOME_FIXTURE/.codex"

    run_cli home shell-init
    assert_status 0
    local shell_output eval_file
    eval_file="$TEST_TMP/shell-init-eval.sh"
    cp "$STDOUT_FILE" "$eval_file"
    cat >> "$eval_file" <<'EVAL'
printf '%s' "${CODEX_HOME:-}"
EVAL
    shell_output="$(CODEX_HOME= HOME="$HOME_FIXTURE" CODEX_PROFILES_DIR="$PROFILES" bash "$eval_file")"
    [[ "$shell_output" == "$PROFILES/work" ]] || fail "shell-init exported '$shell_output' instead of full profile path"

    run_cli env
    assert_status_nonzero
    assert_stderr_contains "moved to 'codex-accounts home env'"
    run_cli current
    assert_status_nonzero
    assert_stderr_contains "moved to 'codex-accounts home current'"
    run_cli run -- true
    assert_status_nonzero
    assert_stderr_contains "moved to 'codex-accounts home run'"
    run_cli shell-init
    assert_status_nonzero
    assert_stderr_contains "moved to 'codex-accounts home shell-init'"

    run_cli help
    assert_status 0
    assert_stdout_contains "auth <subcommand>"
    run_cli auth help
    assert_status 0
    assert_stdout_contains "Minimal auth commands operate on auth.json only"
    assert_stdout_contains "Full CODEX_HOME compatibility mode"
    assert_output_not_contains_secret_markers "$native_marker" "$personal_marker" "access_token" "refresh_token" "account_id"
}

test_auth_init_wrapper_unsets_codex_home_for_switch() {
    local native_marker="INIT_NATIVE_SECRET"
    local profile_marker="INIT_PROFILE_SECRET"
    run_cli add work
    assert_status 0
    run_cli add personal
    assert_status 0
    run_cli home switch work
    assert_status 0
    write_auth_fixture "$HOME_FIXTURE/.codex/auth.json" "$native_marker"
    write_auth_fixture "$PROFILES/personal/auth.json" "$profile_marker"

    run_cli auth-init
    assert_status 0

    local shim="$STUB_BIN/codex-accounts"
    cat > "$shim" <<SHIM
#!/usr/bin/env bash
exec bash "$PWD/codex-accounts" "\$@"
SHIM
    chmod +x "$shim"

    local eval_file="$TEST_TMP/auth-init-eval.sh"
    cp "$STDOUT_FILE" "$eval_file"
    cat >> "$eval_file" <<'EVAL'
CODEX_HOME="$PROFILES/work"
codex-accounts switch personal >/tmp/codex-accounts-auth-init.out
printf 'CODEX_HOME=%s\n' "${CODEX_HOME:-}"
EVAL

    local shell_output
    shell_output="$(HOME="$HOME_FIXTURE" CODEX_PROFILES_DIR="$PROFILES" PATH="$STUB_BIN:$PATH" PROFILES="$PROFILES" bash "$eval_file")"
    [[ "$shell_output" == "CODEX_HOME=" ]] || fail "auth-init did not unset CODEX_HOME; output=$shell_output"
    assert_files_same_without_printing "$HOME_FIXTURE/.codex/auth.json" "$PROFILES/personal/auth.json"
}

run_test() {
    TEST_NAME="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TEST_FAILED=0
    setup_test
    "$@" || CURRENT_TEST_FAILED=1
    if [[ $CURRENT_TEST_FAILED -eq 0 ]]; then
        echo "ok - $TEST_NAME"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "not ok - $TEST_NAME" >&2
    fi
    cleanup_test
}

run_test "TEST-01 lifecycle commands are isolated" test_lifecycle_commands_are_isolated
run_test "TEST-03 shared config status and linking" test_shared_config_status_and_linking
run_test "SAFE-01 invalid CLI names are rejected" test_invalid_cli_names_are_rejected
run_test "SAFE-01 invalid active state is rejected" test_invalid_active_state_is_rejected
run_test "SAFE-01 list and config status skip invalid dirs" test_list_and_config_status_skip_invalid_dirs
run_test "SAFE-02 active writes are atomic" test_atomic_active_writes_for_switch_and_import
run_test "SAFE-03 remove rejects unmanaged targets" test_safe_remove_rejects_unmanaged_targets
run_test "PROF-02 remove archives profile without deleting runtime artifacts" test_remove_archives_profile_without_deleting_runtime_artifacts
run_test "SAFE-04 process detection is narrow and best-effort" test_process_detection_is_narrow_and_best_effort
run_test "AUTH-02 auth paths preview is sanitized and fixture-safe" test_auth_paths_preview_is_sanitized_and_fixture_safe
run_test "AUTH-01 auth switch replaces only native auth and creates backup" test_auth_switch_replaces_only_native_auth_and_creates_backup
run_test "AUTH-04 top-level switch is auth-only" test_top_level_switch_is_auth_only
run_test "AUTH-01 auth switch missing native/source edges are safe" test_auth_switch_missing_native_auth_is_fixture_safe
run_test "BACK-03 auth backups list is sanitized" test_auth_backups_list_is_sanitized
run_test "BACK-02 auth restore uses latest backup without leaking tokens" test_auth_restore_uses_latest_backup_without_leaking_tokens
run_test "PROF-03 auth revert restores latest backup without leaking tokens" test_auth_revert_restores_latest_backup_without_leaking_tokens
run_test "TEST-02 auth revert without backup is failure-safe" test_auth_revert_without_backup_is_failure_safe
run_test "BACK-04 auth prune backups requires explicit confirmation" test_auth_prune_backups_requires_explicit_confirmation
run_test "AUTH-03 full CODEX_HOME mode remains compatible after auth commands" test_full_codex_home_mode_remains_compatible_after_auth_commands
run_test "AUTH-05 auth-init wrapper unsets CODEX_HOME for switch" test_auth_init_wrapper_unsets_codex_home_for_switch

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "$TESTS_FAILED/$TESTS_RUN test(s) failed" >&2
    exit 1
fi

echo "$TESTS_RUN test(s) passed"
