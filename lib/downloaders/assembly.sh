#!/usr/bin/env bash

downloaders_assembly::run_assembly_download() {

    downloaders_common::prepare_download_environment

    log_info "Starting assembly download"

    if [[ -n "$ACCESSION" ]]; then

        downloaders_ncbi_download::download_assembly \
            "$ACCESSION" \
            "$OUTDIR" \
            false

    else

        downloaders_ncbi_download::download_assemblies_parallel \
            "$ACCESSION_FILE" \
            "$OUTDIR" \
            "$PARALLEL_JOBS"

    fi

    downloaders_common::cleanup_temp
}