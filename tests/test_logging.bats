#!/usr/bin/env bats
# Unit tests for lib/logging.sh
#
# logging.sh is a cross-cutting utility (every other lib/**/*.sh file calls
# into it), not one of the dir_stem::-namespaced modules - see
# docs/CONVENTIONS.md for why it keeps its plain log_* names. These tests
# just confirm each helper writes a recognizable, correctly-streamed
# message rather than testing formatting byte-for-byte.

load 'test_helper'

@test "log_info writes an [INFO] line to stdout" {
    run log_info "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" == *"hello"* ]]
}

@test "log_success writes a [SUCCESS] line to stdout" {
    run log_success "done"
    [[ "$output" == *"[SUCCESS]"* ]]
    [[ "$output" == *"done"* ]]
}

@test "log_warning writes a [WARN] line to stdout" {
    run log_warning "careful"
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"careful"* ]]
}

@test "log_step writes a [STEP] banner to stdout" {
    run log_step "starting"
    [[ "$output" == *"[STEP]"* ]]
    [[ "$output" == *"starting"* ]]
}

@test "log_error writes an [ERROR] line to stderr, not stdout" {
    on_stdout="$(log_error "boom" 2>/dev/null)"
    on_stderr="$(log_error "boom" 2>&1 1>/dev/null)"
    [ -z "$on_stdout" ]
    [[ "$on_stderr" == *"[ERROR]"* ]]
    [[ "$on_stderr" == *"boom"* ]]
}
