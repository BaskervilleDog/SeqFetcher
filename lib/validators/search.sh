#!/usr/bin/env bash

validators_search::validate_search_inputs() {

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
        # Tables/lists, not sequence data, so they live under OUTDIR/tables/
        # rather than cluttering OUTDIR's root alongside downloaded files.
        OUTPUT_FILE="${OUTDIR}/tables/assemblies.tsv"

        [[ "$EXTRACT_GENES" == true ]] &&
            OUTPUT_FILE="${OUTDIR}/tables/gene_ids.txt"
    fi

    return 0
}