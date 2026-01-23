#!/usr/bin/env bash

require_datasets() {
    if ! command -v datasets >/dev/null 2>&1; then
        log_error "NCBI datasets command not found"
        log_error "Please install from: https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/"
        return 1
    fi
    return 0
}

require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed"
        log_error "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
        return 1
    fi
    return 0
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