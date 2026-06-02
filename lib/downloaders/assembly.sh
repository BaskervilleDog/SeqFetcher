#!/usr/bin/env bash

run_assembly_download() {

    prepare_download_environment

    log_info "Starting assembly download"

    if [[ -n "$ACCESSION" ]]; then

        download_assembly \
            "$ACCESSION" \
            "$OUTDIR" \
            false

    else

        download_assemblies_parallel \
            "$ACCESSION_FILE" \
            "$OUTDIR" \
            "$PARALLEL_JOBS"

    fi

    cleanup_temp
}