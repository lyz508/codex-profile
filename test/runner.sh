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
    HOME="$HOME_FIXTURE" CODEX_PROFILES_DIR="$PROFILES" PATH="$STUB_BIN:$PATH" bash ./codex-profile "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
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
    HOME="$HOME_FIXTURE" CODEX_PROFILES_DIR="$PROFILES" PATH="$STUB_BIN:$PATH" bash ./codex-profile "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE" <<<"$input"
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

test_lifecycle_commands_are_isolated() {
    run_cli add work
    assert_status 0
    assert_file_exists "$PROFILES/work"
    assert_symlink "$PROFILES/work/config.toml"

    run_cli switch work
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"

    run_cli current
    assert_status 0
    assert_stdout_contains "work"

    run_cli env
    assert_status 0
    assert_stdout_contains "CODEX_HOME=$PROFILES/work"

    run_cli run -- sh -c 'printf "%s" "$CODEX_HOME"'
    assert_status 0
    assert_stdout_contains "$PROFILES/work"

    run_cli_with_stdin work remove work
    assert_status 0
    assert_file_not_exists "$PROFILES/work"
    assert_file_not_exists "$PROFILES/.active"
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
    for name in "../evil" "bad/name" ".active" "_shared" ""; do
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

    run_cli current
    assert_status_nonzero
    assert_stderr_contains "active profile state is invalid"
    run_cli env
    assert_status_nonzero
    assert_stderr_contains "active profile state is invalid"
    run_cli run -- true
    assert_status_nonzero
    assert_stderr_contains "active profile state is invalid"

    run_cli shell-init
    assert_status 0
    CODEX_HOME= HOME="$HOME_FIXTURE" CODEX_PROFILES_DIR="$PROFILES" bash -c "$(cat "$STDOUT_FILE"); [[ -z \"\${CODEX_HOME:-}\" ]]"
}

test_list_and_config_status_skip_invalid_dirs() {
    run_cli add work
    assert_status 0
    mkdir -p "$PROFILES/bad name" "$PROFILES/.hidden" "$PROFILES/_shared"

    run_cli list
    assert_status 0
    assert_stdout_contains "work"
    assert_stderr_contains "warning: skipping invalid profile directory: bad name"
    assert_stderr_contains "warning: skipping invalid profile directory: .hidden"

    run_cli config status
    assert_status 0
    assert_stdout_contains "work"
    assert_stderr_contains "warning: skipping invalid profile directory: bad name"
}

test_atomic_active_writes_for_switch_and_import() {
    run_cli add work
    assert_status 0
    run_cli switch work
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

    ! grep -v '^[[:space:]]*#' codex-profile | grep -E 'echo "\$name" > "\$STATE_FILE"|> "\$STATE_FILE"' >/dev/null || fail "direct STATE_FILE write remains"
}

test_safe_remove_rejects_unmanaged_targets() {
    run_cli add work
    assert_status 0
    run_cli switch work
    assert_status 0
    run_cli_with_stdin work remove work
    assert_status 0
    assert_file_not_exists "$PROFILES/work"
    assert_file_not_exists "$PROFILES/.active"

    run_cli remove _shared
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
    remove_body="$(sed -n '/cmd_remove()/,/^}/p' codex-profile)"
    [[ "$remove_body" == *"assert_safe_profile_target"* ]] || fail "cmd_remove does not call assert_safe_profile_target"
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

    run_cli switch work
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"

    write_process_stubs exact
    run_cli_with_stdin n switch personal
    assert_status_nonzero
    assert_stderr_contains "warning:"
    assert_stderr_contains "codex process(es) still running"
    assert_file_content "$PROFILES/.active" "work"

    write_process_stubs unrelated
    run_cli switch personal
    assert_status 0
    assert_file_content "$PROFILES/.active" "personal"

    write_process_stubs missing
    run_cli switch work
    assert_status 0
    assert_file_content "$PROFILES/.active" "work"

    ! grep -F "pgrep -f 'codex' 2>/dev/null | xargs" codex-profile >/dev/null || fail "raw pgrep -f codex pipeline remains"
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
run_test "SAFE-04 process detection is narrow and best-effort" test_process_detection_is_narrow_and_best_effort

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "$TESTS_FAILED/$TESTS_RUN test(s) failed" >&2
    exit 1
fi

echo "$TESTS_RUN test(s) passed"
