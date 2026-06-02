#!/usr/bin/env bash

run_gene_download() {

    prepare_download_environment

    if [[ "$GENE_ID_USER" == true ]]; then

        local tmp
        tmp=$(mktemp)

        echo "$GENE_ID" |
            tr ',' '\n' > "$tmp"

        input="$tmp"

    else

        input="$GENE_FILE"

    fi

    download_genes_batches \
        "$input" \
        "$OUTDIR" \
        "$PARALLEL_JOBS"

    [[ "$GENE_ID_USER" == true ]] &&
        rm -f "$tmp"

    cleanup_temp
}