#!/usr/bin/env bats
# Unit tests for lib/downloaders/common.sh

load 'test_helper'

# Bats 0.4 (the bioconda build) does not set BATS_TEST_TMPDIR - provide one.
setup() {
    BATS_TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/sf-common.XXXXXX")"
}
teardown() {
    [ -n "$BATS_TEST_TMPDIR" ] && rm -rf "$BATS_TEST_TMPDIR"
}

@test "downloaders_common::is_help recognizes --help" {
    downloaders_common::is_help "--help"
}

@test "downloaders_common::is_help recognizes -h" {
    downloaders_common::is_help "-h"
}

@test "downloaders_common::is_help recognizes bare 'help'" {
    downloaders_common::is_help "help"
}

@test "downloaders_common::is_help rejects an unrelated argument" {
    ! downloaders_common::is_help "--organism"
}

@test "downloaders_common::check_command succeeds for a command on PATH" {
    run downloaders_common::check_command bash
    [ "$status" -eq 0 ]
}

@test "downloaders_common::check_command fails with a helpful message for a missing command" {
    run downloaders_common::check_command definitely-not-a-real-command
    [ "$status" -eq 1 ]
    [[ "$output" == *"definitely-not-a-real-command"* ]]
}

@test "downloaders_common::cleanup_temp removes an existing TEMP_DIR" {
    TEMP_DIR="$BATS_TEST_TMPDIR/temp_downloads"
    mkdir -p "$TEMP_DIR"
    downloaders_common::cleanup_temp
    [ ! -d "$TEMP_DIR" ]
}

@test "downloaders_common::cleanup_temp is a no-op when TEMP_DIR does not exist" {
    TEMP_DIR="$BATS_TEST_TMPDIR/never_created"
    run downloaders_common::cleanup_temp
    [ "$status" -eq 0 ]
}

@test "downloaders_common::prepare_download_environment creates OUTDIR and TEMP_DIR" {
    OUTDIR="$BATS_TEST_TMPDIR/out"
    TEMP_DIR="$BATS_TEST_TMPDIR/tmp"
    downloaders_common::prepare_download_environment
    [ -d "$OUTDIR" ]
    [ -d "$TEMP_DIR" ]
    [ "$OUTPUT_DIR" = "$OUTDIR" ]
}
