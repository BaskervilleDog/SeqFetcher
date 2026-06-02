#!/usr/bin/env bash

execute_geo_srr() {
    export OUTPUT_DIR="$OUTDIR"
    export TEMP_DIR
    mkdir -p "$TEMP_DIR"
    
    # Trap to ensure cleanup on exit
    trap cleanup_temp EXIT
    
    create_srr_list_from_geo "$@"
    local result=$?
    
    cleanup_temp
    return $result
}

run_geo_srr() {
    execute_geo_srr "$@"
}