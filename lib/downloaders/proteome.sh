#!/usr/bin/env bash

run_proteome_download() {

    prepare_download_environment

    export ENSEMBL_TYPE
    export ENSEMBL_RELEASE

    download_proteome \
        "$PROTEOME_ASSEMBLY" \
        "$PROTEOME_SPECIES" \
        "$PROTEOME_SOURCE" \
        "$PROTEOME_TYPE"

    cleanup_temp
}