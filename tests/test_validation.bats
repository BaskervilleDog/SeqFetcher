#!/usr/bin/env bats
# Unit tests for lib/validation.sh (require_datasets, require_jq,
# validate_accession) - see docs/CONVENTIONS.md for why this file, like
# logging.sh, is exempt from dir_stem:: namespacing.

load 'test_helper'

@test "validate_accession accepts a well-formed GCF accession" {
    run validate_accession "GCF_000005845.2"
    [ "$status" -eq 0 ]
}

@test "validate_accession accepts a well-formed GCA accession" {
    run validate_accession "GCA_000005845.2"
    [ "$status" -eq 0 ]
}

@test "validate_accession rejects a missing version suffix" {
    run validate_accession "GCF_000005845"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid accession format"* ]]
}

@test "validate_accession rejects a bad prefix" {
    run validate_accession "GXF_000005845.2"
    [ "$status" -eq 1 ]
}

@test "validate_accession rejects an empty string" {
    run validate_accession ""
    [ "$status" -eq 1 ]
}

@test "require_datasets fails with a helpful message when datasets is not on PATH" {
    # PATH="..." "$BASH" (an already-absolute path, not a bare "bash") so
    # the crippled PATH only hides `datasets` from the inner `command -v`,
    # not bash itself from this line's own lookup.
    run env PATH="/nonexistent" "$BASH" -c "source '$BASE_DIR/lib/logging.sh'; source '$BASE_DIR/lib/validation.sh'; require_datasets"
    [ "$status" -eq 3 ]   # EX_DEPENDENCY
    [[ "$output" == *"datasets"* ]]
}

@test "require_jq fails with a helpful message when jq is not on PATH" {
    run env PATH="/nonexistent" "$BASH" -c "source '$BASE_DIR/lib/logging.sh'; source '$BASE_DIR/lib/validation.sh'; require_jq"
    [ "$status" -eq 3 ]   # EX_DEPENDENCY
    [[ "$output" == *"jq"* ]]
}
