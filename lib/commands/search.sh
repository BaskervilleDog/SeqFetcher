#!/usr/bin/env bash


commands_search::execute_search() {
    log_info "Searching for organism: $ORGANISM"
    mkdir -p "$OUTDIR"
    mkdir -p "$TEMP_DIR"

    # Trap to ensure cleanup on exit
    trap downloaders_common::cleanup_temp EXIT

    if [[ "$EXTRACT_GENES" == true ]]; then
        downloaders_ncbi_search::extract_gene_ids_from_reference "$ORGANISM" "$OUTPUT_FILE" \
            || { log_error "Gene extraction failed"; return "${EX_NETWORK:-5}"; }
        return 0
    fi

    downloaders_ncbi_search::search_metadata_by_organism "$ORGANISM" "$OUTDIR/tables/taxonomy_metadata.tsv" \
        || log_warning "Metadata fetch failed"
    downloaders_ncbi_search::search_assemblies_by_organism "$ORGANISM" "$OUTPUT_FILE" "$TOP_N" \
        || { log_error "Assembly search failed"; return "${EX_NETWORK:-5}"; }

    log_info "Results saved to $OUTPUT_FILE"
    [[ "$INTERACTIVE" == true ]] && downloaders_ncbi_download::download_assemblies_interactive "$OUTPUT_FILE" "$OUTDIR"

    return 0
}

# Build the --json payload for `search` directly from the results TSV
# (the ranked assembly table), rather than from the download accumulator.
commands_search::emit_json() {
    local status="$1" code="$2"
    command -v jq >/dev/null 2>&1 || return 0
    local tsv="$OUTPUT_FILE"
    local rows='[]'
    [[ -s "$tsv" ]] && rows="$(jq -R -s '
        split("\n") | map(select(length > 0)) | .[1:]
        | map(split("\t"))
        | map({accession: .[0], organism: .[1], level: .[2],
               status: .[3], refseq_category: .[4], name: .[5]})' "$tsv")"

    jq -n \
        --arg ver "${SEQFETCHER_VERSION:-unknown}" \
        --arg organism "$ORGANISM" \
        --arg status "$status" \
        --argjson code "$code" \
        --arg outdir "$OUTDIR" \
        --arg table "$tsv" \
        --arg accessions "${tsv%.tsv}_accessions.txt" \
        --arg taxonomy "$OUTDIR/tables/taxonomy_metadata.tsv" \
        --argjson assemblies "$rows" \
        '{seqfetcher_version: $ver, command: "search", status: $status,
          exit_code: $code, organism: $organism, outdir: $outdir,
          files: {table: $table, accessions: $accessions, taxonomy: $taxonomy},
          count: ($assemblies | length), assemblies: $assemblies}'
}

commands_search::run_search() {
    parsers_search::parse_search_arguments "$@"
    validators_search::validate_search_inputs || die "Invalid search arguments" "${EX_USAGE:-2}"

    manifest::init "$OUTDIR"
    manifest::set_context search "$@"

    local rc=0
    commands_search::execute_search || rc=$?

    local status="success"
    [[ $rc -ne 0 ]] && status="error"

    manifest::add_run "$status" "$rc"
    if [[ "${JSON_OUTPUT:-false}" == true ]]; then
        commands_search::emit_json "$status" "$rc"
    fi
    manifest::cleanup
    return "$rc"
}
