#!/usr/bin/env bash

# Annotation-only download: GFF3/GTF (and optionally GBFF) for an assembly,
# without the genome FASTA. Reuses the NCBI datasets genome-package path with
# a restricted --include (see downloaders_ncbi_download::_download_genome_package).

downloaders_annotation::run_annotation_download() {

    downloaders_common::prepare_download_environment

    export ANNOTATION_FORMATS FORCE

    log_info "Starting annotation download ($ANNOTATION_FORMATS)"

    local rc=0
    if [[ -n "$ACCESSION" ]]; then
        downloaders_ncbi_download::download_annotation "$ACCESSION" "$OUTDIR" "$ANNOTATION_FORMATS" || rc=$?
    else
        downloaders_ncbi_download::download_annotations_parallel \
            "$ACCESSION_FILE" "$OUTDIR" "$PARALLEL_JOBS" || rc=$?
    fi

    downloaders_common::cleanup_temp
    return "$rc"
}
