#!/usr/bin/env bats
# Unit tests for lib/manifest.sh - the seqfetcher.lock.json provenance
# helpers. Pure filesystem + jq, no network, so safe to unit-test per
# docs/CONVENTIONS.md.

load 'test_helper'

setup() {
    reset_config
    # Bats 0.4 does not set BATS_TEST_TMPDIR - make our own.
    MTEST_DIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/sf-manifest.XXXXXX")"
    OUTDIR="$MTEST_DIR/out"
    manifest::init "$OUTDIR"
    manifest::set_context download --accession GCF_000005845.2
}

teardown() {
    manifest::cleanup
    [ -n "$MTEST_DIR" ] && rm -rf "$MTEST_DIR"
}

@test "manifest::init creates the lockfile skeleton" {
    [ -f "$LOCKFILE" ]
    run jq -e '.schema == 1 and (.runs | length == 0) and (.artifacts | length == 0)' "$LOCKFILE"
    [ "$status" -eq 0 ]
}

@test "manifest::record merges an artifact and is idempotent per key" {
    local e='{"accession":"GCF_1.1","type":"assembly","status":"downloaded","files":[{"path":"x","bytes":1,"md5":"aa"}]}'
    manifest::record "GCF_1.1:assembly" "$e"
    manifest::record "GCF_1.1:assembly" "$e"
    run jq '.artifacts | length' "$LOCKFILE"
    [ "$output" -eq 1 ]
    run jq -r '.artifacts["GCF_1.1:assembly"].status' "$LOCKFILE"
    [ "$output" = "downloaded" ]
}

@test "manifest::get and manifest::stored_md5 round-trip" {
    manifest::record "k1" '{"type":"fastq","status":"downloaded","files":[{"path":"r1","bytes":9,"md5":"deadbeef"}]}'
    run manifest::stored_md5 "k1"
    [ "$output" = "deadbeef" ]
    manifest::is_done "k1"
}

@test "manifest::is_done is false for an unknown or failed key" {
    run manifest::is_done "missing"
    [ "$status" -ne 0 ]
    manifest::record "kf" '{"type":"fastq","status":"failed"}'
    run manifest::is_done "kf"
    [ "$status" -ne 0 ]
}

@test "manifest::record_run_only does not touch the lockfile artifact" {
    manifest::record "k" '{"type":"assembly","status":"downloaded","files":[{"path":"p","md5":"x"}]}'
    manifest::record_run_only "k" '{"type":"assembly","status":"skipped"}'
    run jq -r '.artifacts["k"].status' "$LOCKFILE"
    [ "$output" = "downloaded" ]
}

@test "manifest::emit produces valid JSON with counts (only under --json)" {
    manifest::record "a" '{"type":"assembly","status":"downloaded"}'
    manifest::record "b" '{"type":"assembly","status":"failed"}'
    run manifest::emit "partial" 7
    [ -z "$output" ]                      # nothing unless JSON_OUTPUT
    JSON_OUTPUT=true run manifest::emit "partial" 7
    echo "$output" | jq -e '.status == "partial" and .exit_code == 7 and .counts.total == 2 and .counts.downloaded == 1 and .counts.failed == 1'
}

@test "manifest::add_run appends a run record with tool versions" {
    manifest::add_run "success" 0
    run jq -e '.runs[-1] | .command == "download" and .exit_code == 0 and (.tool_versions.jq | type == "string")' "$LOCKFILE"
    [ "$status" -eq 0 ]
}
