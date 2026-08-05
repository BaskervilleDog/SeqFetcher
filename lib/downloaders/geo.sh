#!/usr/bin/env bash

downloaders_geo::run_geo_download() {

    downloaders_common::prepare_download_environment

    log_info "Starting GEO download"

    downloaders_geo_download::download_geo_supplementary \
        --geo "$GEO_ACCESSION" \
        --outdir "$OUTDIR"

    downloaders_common::cleanup_temp
}