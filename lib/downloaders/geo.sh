#!/usr/bin/env bash

downloaders_geo::run_geo_download() {

    downloaders_common::prepare_download_environment

    log_info "Starting GEO download"

    local rc=0
    downloaders_geo_download::download_geo_supplementary \
        --geo "$GEO_ACCESSION" --outdir "$OUTDIR" || rc=$?

    downloaders_common::cleanup_temp
    return "$rc"
}
