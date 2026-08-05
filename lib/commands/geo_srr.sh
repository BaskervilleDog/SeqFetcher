#!/usr/bin/env bash

commands_geo_srr::execute_geo_srr() {
    export OUTPUT_DIR="$OUTDIR"
    export TEMP_DIR
    mkdir -p "$TEMP_DIR"
    
    # Trap to ensure cleanup on exit
    trap downloaders_common::cleanup_temp EXIT
    
    downloaders_geo_download::create_srr_list_from_geo "$@"
    local result=$?
    
    downloaders_common::cleanup_temp
    return $result
}

commands_geo_srr::run_geo_srr() {
    commands_geo_srr::execute_geo_srr "$@"
}