#!/usr/bin/env bash

downloaders_gene::run_gene_download() {

    downloaders_common::prepare_download_environment

    if [[ "$GENE_ID_USER" == true ]]; then

        local tmp
        tmp=$(mktemp)

        echo "$GENE_ID" |
            tr ',' '\n' > "$tmp"

        input="$tmp"

    else

        input="$GENE_FILE"

    fi

    downloaders_ncbi_download::download_genes_batches \
        "$input" \
        "$OUTDIR" \
        "$PARALLEL_JOBS"

    [[ "$GENE_ID_USER" == true ]] &&
        rm -f "$tmp"

    downloaders_common::cleanup_temp
}