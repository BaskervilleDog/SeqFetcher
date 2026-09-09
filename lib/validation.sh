#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# Exit-code contract (documented in docs/COMMAND_REFERENCE.md).
# Sourced before every parser/validator/downloader, so the constants and
# `die` (lib/logging.sh) are available everywhere.
# ---------------------------------------------------------------------------
: "${EX_OK:=0}"          # success
: "${EX_ERROR:=1}"       # unexpected / internal error
: "${EX_USAGE:=2}"       # bad flag, missing required option, unknown command
: "${EX_DEPENDENCY:=3}"  # a required external tool is missing
: "${EX_NOTFOUND:=4}"    # valid query, but the upstream source has no data
: "${EX_NETWORK:=5}"     # API / download failure after retries
: "${EX_INTEGRITY:=6}"   # checksum / size mismatch
: "${EX_PARTIAL:=7}"     # batch: some items succeeded, some failed

# A missing required CLI tool is always fatal - there is no recovery path -
# so these exit straight away with EX_DEPENDENCY rather than returning a
# status a caller has to thread back up to main().
require_datasets() {
    command -v datasets >/dev/null 2>&1 && return 0
    die "NCBI datasets command not found - install: https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/" "$EX_DEPENDENCY"
}

require_jq() {
    command -v jq >/dev/null 2>&1 && return 0
    die "jq is required but not installed - install: apt-get install jq / brew install jq" "$EX_DEPENDENCY"
}

validate_accession() {
    local acc="$1"
    if [[ ! "$acc" =~ ^GC[AF]_[0-9]{9}\.[0-9]+$ ]]; then
        log_error "Invalid accession format: $acc"
        log_error "Expected format: GCF_XXXXXXXXX.X or GCA_XXXXXXXXX.X"
        return 1
    fi
    return 0
}