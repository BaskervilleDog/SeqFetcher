#!/usr/bin/env bash


execute_search() {
    log_info "Searching for organism: $ORGANISM"
    mkdir -p "$OUTDIR"
    mkdir -p "$TEMP_DIR"
    
    # Trap to ensure cleanup on exit
    trap cleanup_temp EXIT

    if [[ "$EXTRACT_GENES" == true ]]; then
        extract_gene_ids_from_reference "$ORGANISM" "$OUTPUT_FILE" || { log_error "Gene extraction failed"; cleanup_temp; exit 1; }
        cleanup_temp
        return 0
    fi

    search_metadata_by_organism "$ORGANISM" "$OUTDIR/taxonomy_metadata.tsv" || log_warning "Metadata fetch failed"
    search_assemblies_by_organism "$ORGANISM" "$OUTPUT_FILE" || { log_error "Assembly search failed"; cleanup_temp; exit 1; }

    log_info "Results saved to $OUTPUT_FILE"
    [[ "$INTERACTIVE" == true ]] && download_assemblies_interactive "$OUTPUT_FILE" "$OUTDIR"
    
    cleanup_temp
}

run_search() {
    parse_search_arguments "$@"
    validate_search_inputs
    execute_search
}