#!/usr/bin/env bash

commands_bioproject_srr::execute_bioproject_srr() {
    export OUTPUT_DIR="$OUTDIR"
    export TEMP_DIR
    mkdir -p "$TEMP_DIR"

    trap downloaders_common::cleanup_temp EXIT

    downloaders_bioproject_download::create_srr_list_from_bioproject "$@"
    local result=$?

    downloaders_common::cleanup_temp
    return $result
}

commands_bioproject_srr::run_bioproject_srr() {
    commands_bioproject_srr::execute_bioproject_srr "$@"
}