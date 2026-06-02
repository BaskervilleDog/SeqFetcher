#!/usr/bin/env bash

validate_search_inputs() {

    [[ -z "$ORGANISM" ]] &&
    {
        log_error "Missing --organism"
        exit 1
    }

    [[ "$MODE" != "assemblies" ]] &&
    {
        log_error "Invalid --mode: $MODE"
        exit 1
    }

    if [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="${OUTDIR}/assemblies.tsv"

        [[ "$EXTRACT_GENES" == true ]] &&
            OUTPUT_FILE="${OUTDIR}/gene_ids.txt"
    fi
}