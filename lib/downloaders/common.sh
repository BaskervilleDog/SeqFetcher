#!/usr/bin/env bash

prepare_download_environment() {
    mkdir -p "$OUTDIR"
    mkdir -p "$TEMP_DIR"

    export OUTPUT_DIR="$OUTDIR"
    export TEMP_DIR

    trap cleanup_temp EXIT
}

cleanup_temp() {
    if [[ -d "$TEMP_DIR" ]]; then
        log_info "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}