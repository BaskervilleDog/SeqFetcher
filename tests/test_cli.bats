#!/usr/bin/env bats
# Integration test: runs the real seqfetcher.sh entry point as a
# subprocess (not the lib/ functions directly), the way
# tests/test_pipeline_integration.bats does in the analysis templates -
# catches "the pieces don't source/dispatch together anymore" regressions
# that the per-file unit tests can't see.
#
# Every case here is chosen to fail at argument validation, before any
# network call, so the suite runs the same offline in CI as on a laptop.

load 'test_helper'

SEQFETCHER="$BASE_DIR/seqfetcher.sh"

@test "no arguments shows help and exits 0" {
    run "$SEQFETCHER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SeqFetcher"* ]]
    [[ "$output" == *"COMMANDS"* ]]
}

@test "--help and -h show help and exit 0" {
    run "$SEQFETCHER" --help
    [ "$status" -eq 0 ]
    run "$SEQFETCHER" -h
    [ "$status" -eq 0 ]
}

@test "an unknown command exits 1 with an error" {
    run "$SEQFETCHER" not-a-real-command
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command: not-a-real-command"* ]]
}

@test "search with no --organism exits 1" {
    run "$SEQFETCHER" search
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing --organism"* ]]
}

@test "download with no type-selecting option exits 1" {
    run "$SEQFETCHER" download
    [ "$status" -eq 1 ]
}

@test "geo-srr with no --geo exits 1" {
    run "$SEQFETCHER" geo-srr
    [ "$status" -eq 1 ]
}

@test "bp-srr with no --bioproject exits 1" {
    run "$SEQFETCHER" bp-srr
    [ "$status" -eq 1 ]
}
