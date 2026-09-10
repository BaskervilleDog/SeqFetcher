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

@test "--version prints the version and exits 0" {
    run "$SEQFETCHER" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^seqfetcher\ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "an unknown global flag before a command is not treated as a command" {
    # --frob is unknown; it's kept as a positional, so cmd becomes --frob
    run "$SEQFETCHER" --frob
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "search usage error under --json prints a JSON error object on stdout" {
    # bats 0.4 merges stderr into $output, so capture stdout in a subshell.
    run "$BASH" -c "'$SEQFETCHER' --json search 2>/dev/null"
    [ "$status" -eq 2 ]
    echo "$output" | jq -e '.status == "error" and .exit_code == 2'
}

@test "--force is accepted as a global flag (fails later at validation, not on the flag)" {
    run "$SEQFETCHER" --force download
    [ "$status" -eq 2 ]
    [[ "$output" != *"Unknown"* ]]
}

@test "an unknown command exits 2 (EX_USAGE) with an error" {
    run "$SEQFETCHER" not-a-real-command
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown command: not-a-real-command"* ]]
}

@test "search with no --organism exits 2 (EX_USAGE)" {
    run "$SEQFETCHER" search
    [ "$status" -eq 2 ]
    [[ "$output" == *"Missing --organism"* ]]
}

@test "download with no type-selecting option exits 2 (EX_USAGE)" {
    run "$SEQFETCHER" download
    [ "$status" -eq 2 ]
}

@test "geo-srr with no --geo exits 2 (EX_USAGE)" {
    run "$SEQFETCHER" geo-srr
    [ "$status" -eq 2 ]
}

@test "bp-srr with no --bioproject exits 2 (EX_USAGE)" {
    run "$SEQFETCHER" bp-srr
    [ "$status" -eq 2 ]
}

@test "download --annotation with no accession exits 2" {
    run "$SEQFETCHER" download --annotation
    [ "$status" -eq 2 ]
}

@test "download --structure with no ids exits 2" {
    run "$SEQFETCHER" download --structure
    [ "$status" -eq 2 ]
}

@test "download --proteome --source uniprot with no id exits 2" {
    run "$SEQFETCHER" download --proteome --source uniprot
    [ "$status" -eq 2 ]
}

@test "sra-info with no accession exits 2" {
    run "$SEQFETCHER" sra-info
    [ "$status" -eq 2 ]
}

@test "search --pdb / --alphafold with no filter exits 2" {
    run "$SEQFETCHER" search --pdb
    [ "$status" -eq 2 ]
    run "$SEQFETCHER" search --alphafold
    [ "$status" -eq 2 ]
}

@test "a value-taking flag as the final argument does not hang the arg parser" {
    # regression: `shift 2` past the end used to loop forever (bug: --sort)
    for cmd in \
        "search --organism" \
        "search --pdb --sort" \
        "download --accession" \
        "sra-info --accession" \
        "geo-srr --geo" \
        "bp-srr --bioproject"
    do
        run timeout 15 "$SEQFETCHER" $cmd
        [ "$status" -ne 124 ]   # 124 == timeout fired == still hanging
    done
}

@test "help lists the new commands and flags" {
    run "$SEQFETCHER" --help
    [[ "$output" == *"sra-info"* ]]
    [[ "$output" == *"--annotation"* ]]
    [[ "$output" == *"--structure"* ]]
    [[ "$output" == *"--proteome-id"* ]]
    [[ "$output" == *"--pdb"* ]]
    [[ "$output" == *"--alphafold"* ]]
}
