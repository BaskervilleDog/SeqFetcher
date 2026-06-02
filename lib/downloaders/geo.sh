#!/usr/bin/env bash

run_geo_download() {

    prepare_download_environment

    log_info "Starting GEO download"

    download_geo_supplementary \
        --geo "$GEO_ACCESSION" \
        --outdir "$OUTDIR"

    cleanup_temp
}