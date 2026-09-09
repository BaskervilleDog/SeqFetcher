#!/usr/bin/env bash

downloaders_structure::run_structure_download() {

    downloaders_common::prepare_download_environment

    export STRUCTURE_ALPHAFOLD STRUCTURE_ALPHAFOLD_FILE \
           STRUCTURE_PDB STRUCTURE_PDB_FILE STRUCTURE_FORMAT FORCE

    local rc=0
    downloaders_structure_download::run "$OUTDIR" "$STRUCTURE_FORMAT" || rc=$?

    downloaders_common::cleanup_temp
    return "$rc"
}
