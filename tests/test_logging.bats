#!/usr/bin/env bats
# Unit tests for lib/logging.sh
#
# logging.sh is a cross-cutting utility (every other lib/**/*.sh file calls
# into it), not one of the dir_stem::-namespaced modules - see
# docs/CONVENTIONS.md for why it keeps its plain log_* names.
#
# Contract under test: every log_* function writes to STDERR (stdout is
# reserved for a command's machine-readable payload); NO_COLOR / a
# non-TTY strips ANSI; QUIET silences the informational levels only.

load 'test_helper'

@test "log_info / log_step / log_success / log_warning write to stderr, not stdout" {
    for fn in log_info log_step log_success log_warning; do
        on_stdout="$($fn "msg" 2>/dev/null)"
        on_stderr="$($fn "msg" 2>&1 1>/dev/null)"
        [ -z "$on_stdout" ]
        [[ "$on_stderr" == *"msg"* ]]
    done
}

@test "log_error writes to stderr, not stdout" {
    on_stdout="$(log_error "boom" 2>/dev/null)"
    on_stderr="$(log_error "boom" 2>&1 1>/dev/null)"
    [ -z "$on_stdout" ]
    [[ "$on_stderr" == *"[ERROR]"* ]]
    [[ "$on_stderr" == *"boom"* ]]
}

@test "colour is stripped when NO_COLOR is set" {
    run env NO_COLOR=1 "$BASH" -c "source '$BASE_DIR/lib/logging.sh'; log_info 'plain' 2>&1"
    [ "$status" -eq 0 ]
    # no ESC[ sequences
    [[ "$output" != *$'\033['* ]]
    [[ "$output" == *"[INFO]"* ]]
}

@test "QUIET silences log_info but not log_error" {
    quiet_info="$(QUIET=true log_info "shh" 2>&1)"
    quiet_err="$(QUIET=true log_error "loud" 2>&1)"
    [ -z "$quiet_info" ]
    [[ "$quiet_err" == *"loud"* ]]
}

@test "die exits with the given code and logs the message" {
    run "$BASH" -c "source '$BASE_DIR/lib/logging.sh'; source '$BASE_DIR/lib/validation.sh'; die 'nope' 4"
    [ "$status" -eq 4 ]
    [[ "$output" == *"nope"* ]]
}

@test "die under --json prints a JSON error object on stdout" {
    run "$BASH" -c "source '$BASE_DIR/lib/logging.sh'; source '$BASE_DIR/lib/validation.sh'; JSON_OUTPUT=true die 'bad args' 2 2>/dev/null"
    [ "$status" -eq 2 ]
    echo "$output" | jq -e '.status == "error" and .exit_code == 2 and (.errors[0] == "bad args")'
}
