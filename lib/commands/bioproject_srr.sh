#!/usr/bin/env bash

execute_bioproject_srr() {
    export OUTPUT_DIR="$OUTDIR"
    export TEMP_DIR
    mkdir -p "$TEMP_DIR"

    trap cleanup_temp EXIT

    create_srr_list_from_bioproject "$@"
    local result=$?

    cleanup_temp
    return $result
}

run_bioproject_srr() {
    execute_bioproject_srr "$@"
}