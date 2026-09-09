#!/usr/bin/env bash


commands_search::execute_search() {
    mkdir -p "$OUTDIR" "$TEMP_DIR"
    trap downloaders_common::cleanup_temp EXIT

    case "$MODE" in
        assemblies)
            log_info "Searching for organism: $ORGANISM"
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
            ;;

        pdb)
            downloaders_pdb_search::search_structures "$OUTPUT_FILE" "$TOP_N" || return $?
            [[ "$INTERACTIVE" == true ]] && \
                downloaders_structure_download::interactive_from_table "$OUTPUT_FILE" pdb
            ;;

        alphafold)
            downloaders_alphafold_search::search_models "$OUTPUT_FILE" "$TOP_N" || return $?
            [[ "$INTERACTIVE" == true ]] && \
                downloaders_structure_download::interactive_from_table "$OUTPUT_FILE" alphafold
            ;;
    esac

    return 0
}

# --json payload, built from the results TSV (not the download accumulator).
commands_search::emit_json() {
    local status="$1" code="$2"
    command -v jq >/dev/null 2>&1 || return 0
    local tsv="$OUTPUT_FILE"

    if [[ "$MODE" == "assemblies" ]]; then
        local rows='[]'
        [[ -s "$tsv" ]] && rows="$(jq -R -s '
            split("\n") | map(select(length > 0)) | .[1:] | map(split("\t"))
            | map({accession: .[0], organism: .[1], level: .[2],
                   status: .[3], refseq_category: .[4], name: .[5]})' "$tsv")"
        jq -n \
            --arg ver "${SEQFETCHER_VERSION:-unknown}" --arg organism "$ORGANISM" \
            --arg status "$status" --argjson code "$code" --arg outdir "$OUTDIR" \
            --arg table "$tsv" --arg accessions "${tsv%.tsv}_accessions.txt" \
            --arg taxonomy "$OUTDIR/tables/taxonomy_metadata.tsv" \
            --argjson assemblies "$rows" \
            '{seqfetcher_version: $ver, command: "search", target: "assemblies",
              status: $status, exit_code: $code, organism: $organism, outdir: $outdir,
              files: {table: $table, accessions: $accessions, taxonomy: $taxonomy},
              count: ($assemblies | length), assemblies: $assemblies}'
        return 0
    fi

    # pdb / alphafold: turn the TSV into an array of {header: value} objects
    local rows='[]' ids_file
    if [[ "$MODE" == "pdb" ]]; then ids_file="${tsv%.tsv}_ids.txt"; else ids_file="${tsv%.tsv}_accessions.txt"; fi
    [[ -s "$tsv" ]] && rows="$(jq -R -s '
        (split("\n") | map(select(length > 0))) as $lines
        | ($lines[0] | split("\t") | map(ascii_downcase)) as $hdr
        | $lines[1:] | map(split("\t") | [$hdr, .] | transpose | map({(.[0]): .[1]}) | add)' "$tsv")"

    jq -n \
        --arg ver "${SEQFETCHER_VERSION:-unknown}" --arg target "$MODE" \
        --arg status "$status" --argjson code "$code" --arg outdir "$OUTDIR" \
        --arg table "$tsv" --arg ids "$ids_file" --argjson structures "$rows" \
        '{seqfetcher_version: $ver, command: "search", target: $target,
          status: $status, exit_code: $code, outdir: $outdir,
          files: {table: $table, ids: $ids},
          count: ($structures | length), structures: $structures}'
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
    [[ "${JSON_OUTPUT:-false}" == true ]] && commands_search::emit_json "$status" "$rc"
    manifest::cleanup
    return "$rc"
}
