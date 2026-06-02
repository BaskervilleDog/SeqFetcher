#!/usr/bin/env bash

run_transcriptome_download() {

    prepare_download_environment

    export ENSEMBL_TYPE
    export ENSEMBL_RELEASE

    download_transcriptome \
        "$TRANSCRIPTOME_ASSEMBLY" \
        "$TRANSCRIPTOME_SPECIES" \
        "$TRANSCRIPTOME_SOURCE" \
        "$TRANSCRIPTOME_TYPE"

    cleanup_temp
}