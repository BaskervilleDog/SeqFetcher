#!/usr/bin/env bash


commands_search::execute_search() {
    log_info "Searching for organism: $ORGANISM"
    mkdir -p "$OUTDIR"
    mkdir -p "$TEMP_DIR"
    
    # Trap to ensure cleanup on exit
    trap downloaders_common::cleanup_temp EXIT

    if [[ "$EXTRACT_GENES" == true ]]; then
        downloaders_ncbi_search::extract_gene_ids_from_reference "$ORGANISM" "$OUTPUT_FILE" || { log_error "Gene extraction failed"; downloaders_common::cleanup_temp; exit 1; }
        downloaders_common::cleanup_temp
        return 0
    fi

    downloaders_ncbi_search::search_metadata_by_organism "$ORGANISM" "$OUTDIR/tables/taxonomy_metadata.tsv" || log_warning "Metadata fetch failed"
    downloaders_ncbi_search::search_assemblies_by_organism "$ORGANISM" "$OUTPUT_FILE" || { log_error "Assembly search failed"; downloaders_common::cleanup_temp; exit 1; }

    log_info "Results saved to $OUTPUT_FILE"
    [[ "$INTERACTIVE" == true ]] && downloaders_ncbi_download::download_assemblies_interactive "$OUTPUT_FILE" "$OUTDIR"
    
    downloaders_common::cleanup_temp
}

commands_search::run_search() {
    parsers_search::parse_search_arguments "$@"
    validators_search::validate_search_inputs
    commands_search::execute_search
}