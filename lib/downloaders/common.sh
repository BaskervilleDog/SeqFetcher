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

is_help() {
    [[ "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command not found: $1"
        log_error "Please install $1 and try again"
        return 1
    fi
    return 0
}