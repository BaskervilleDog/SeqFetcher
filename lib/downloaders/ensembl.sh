#!/usr/bin/env bash

run_ensembl_download() {

    prepare_download_environment

    export ENSEMBL_RELEASE

    download_ensembl_fasta \
        "$ENSEMBL_SPECIES" \
        "$ENSEMBL_TYPE" \
        "$OUTDIR"

    cleanup_temp
}