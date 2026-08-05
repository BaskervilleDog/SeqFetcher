#!/usr/bin/env bash

downloaders_ensembl::run_ensembl_download() {

    downloaders_common::prepare_download_environment

    export ENSEMBL_RELEASE

    downloaders_ensembl_download::download_ensembl_fasta \
        "$ENSEMBL_SPECIES" \
        "$ENSEMBL_TYPE" \
        "$OUTDIR"

    downloaders_common::cleanup_temp
}