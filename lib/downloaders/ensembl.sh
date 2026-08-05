#!/usr/bin/env bash

downloaders_ensembl::run_ensembl_download() {

    downloaders_common::prepare_download_environment

    export ENSEMBL_RELEASE

    # Mirrors how download_transcriptome/download_proteome nest their own
    # Ensembl branch: OUTDIR/<kind>/<species>/<type>/, not OUTDIR's root.
    downloaders_ensembl_download::download_ensembl_fasta \
        "$ENSEMBL_SPECIES" \
        "$ENSEMBL_TYPE" \
        "$OUTDIR/ensembl/$ENSEMBL_SPECIES/$ENSEMBL_TYPE"

    downloaders_common::cleanup_temp
}