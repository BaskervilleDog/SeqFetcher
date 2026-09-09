#!/usr/bin/env bash

# RCSB PDB structure search.
#
# Two public APIs, no key:
#   search.rcsb.org/rcsbsearch/v2/query  - POST a JSON query, get matching
#                                          entry ids + a total count
#   data.rcsb.org/graphql                - one POST for the whole id list ->
#                                          title / method / resolution /
#                                          release date / organism / UniProt
#
# Produces a ranked TSV + a bare-id list that feeds
# `download --structure --pdb-file`. Mirrors
# downloaders_ncbi_search::search_assemblies_by_organism.

RCSB_SEARCH_URL="https://search.rcsb.org/rcsbsearch/v2/query"
RCSB_GRAPHQL_URL="https://data.rcsb.org/graphql"

# downloaders_pdb_search::search_structures <output_file> <top_n>
downloaders_pdb_search::search_structures() {
    local output_file="${1:-pdb_structures.tsv}"
    local top_n="${2:-50}"
    (( top_n > 10000 )) && { log_warning "RCSB caps a query at 10000 rows; using --top 10000"; top_n=10000; }

    require_jq || return "${EX_DEPENDENCY:-3}"
    downloaders_common::check_command curl || return "${EX_DEPENDENCY:-3}"

    log_step "Searching RCSB PDB"

    # ---- build the query ----
    local method_val=""
    case "${SEARCH_METHOD,,}" in
        x-ray|xray) method_val="X-RAY DIFFRACTION" ;;
        em|cryo-em) method_val="ELECTRON MICROSCOPY" ;;
        nmr)        method_val="SOLUTION NMR" ;;
    esac

    local sort_json="null"
    case "$SEARCH_SORT" in
        resolution) sort_json='[{"sort_by":"rcsb_entry_info.resolution_combined","direction":"asc"}]' ;;
        date)       sort_json='[{"sort_by":"rcsb_accession_info.initial_release_date","direction":"desc"}]' ;;
    esac

    local query
    query="$(jq -n \
        --arg text "$SEARCH_TEXT" \
        --arg org "$ORGANISM" \
        --arg method "$method_val" \
        --arg maxres "$SEARCH_MAX_RESOLUTION" \
        --arg minchains "$SEARCH_MIN_CHAINS" \
        --arg after "$SEARCH_AFTER_DATE" \
        --arg before "$SEARCH_BEFORE_DATE" \
        --arg uniprot "$SEARCH_UNIPROT" \
        --arg ligand "$SEARCH_LIGAND" \
        --argjson rows "$top_n" \
        --argjson sort "$sort_json" \
        '
        def term(attr; op; val): {type:"terminal", service:"text",
            parameters:{attribute:attr, operator:op, value:val}};
        def csv($s): ($s | split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0)));

        [ (if $text    != "" then {type:"terminal", service:"full_text", parameters:{value:$text}} else empty end),
          (if $org     != "" then term("rcsb_entity_source_organism.taxonomy_lineage.name"; "exact_match"; $org) else empty end),
          (if $method  != "" then term("exptl.method"; "exact_match"; $method) else empty end),
          (if $maxres  != "" then term("rcsb_entry_info.resolution_combined"; "less_or_equal"; ($maxres | tonumber)) else empty end),
          (if $minchains != "" then term("rcsb_entry_info.polymer_entity_count_protein"; "greater_or_equal"; ($minchains | tonumber)) else empty end),
          (if $after   != "" then term("rcsb_accession_info.initial_release_date"; "greater_or_equal"; $after) else empty end),
          (if $before  != "" then term("rcsb_accession_info.initial_release_date"; "less_or_equal"; $before) else empty end),
          (if $uniprot != "" then term("rcsb_polymer_entity_container_identifiers.reference_sequence_identifiers.database_accession"; "in"; csv($uniprot)) else empty end),
          (if $ligand  != "" then term("rcsb_nonpolymer_entity_container_identifiers.nonpolymer_comp_id"; "in"; (csv($ligand) | map(ascii_upcase))) else empty end)
        ] as $nodes
        | {
            query: (if ($nodes | length) == 1 then $nodes[0]
                    else {type:"group", logical_operator:"and", nodes:$nodes} end),
            return_type: "entry",
            request_options: ({paginate:{start:0, rows:$rows}}
                              + (if $sort != null then {sort:$sort} else {} end))
          }
        ')"

    local tmp_ids tmp_meta
    tmp_ids=$(mktemp) || return "${EX_ERROR:-1}"
    tmp_meta=$(mktemp) || { rm -f "$tmp_ids"; return "${EX_ERROR:-1}"; }

    local resp
    resp="$(curl -fsS -X POST -H "Content-Type: application/json" -d "$query" "$RCSB_SEARCH_URL" 2>/dev/null)"
    if [[ -z "$resp" ]] || ! jq -e . >/dev/null 2>&1 <<< "$resp"; then
        # RCSB returns 204 (empty body) for zero hits
        log_error "No PDB structures matched the query"
        rm -f "$tmp_ids" "$tmp_meta"
        return "${EX_NOTFOUND:-4}"
    fi

    local total
    total="$(jq -r '.total_count // 0' <<< "$resp")"
    jq -r '.result_set[].identifier' <<< "$resp" > "$tmp_ids"
    local shown; shown=$(grep -c . "$tmp_ids")

    [[ "$shown" -eq 0 ]] && { log_error "No PDB structures matched the query"; rm -f "$tmp_ids" "$tmp_meta"; return "${EX_NOTFOUND:-4}"; }

    log_info "Found $total matching structures; fetching metadata for the top $shown"

    # ---- batch metadata via GraphQL ----
    local id_json gql
    id_json="$(jq -R -s 'split("\n") | map(select(length>0))' "$tmp_ids")"
    gql="$(jq -n --argjson ids "$id_json" '{query: ("{ entries(entry_ids: " + ($ids|tojson) + ") { rcsb_id struct { title } exptl { method } rcsb_entry_info { resolution_combined polymer_entity_count_protein } rcsb_accession_info { initial_release_date } polymer_entities { rcsb_entity_source_organism { ncbi_scientific_name } uniprots { rcsb_id } } } }")}')"

    local meta
    meta="$(curl -fsS -X POST -H "Content-Type: application/json" -d "$gql" "$RCSB_GRAPHQL_URL" 2>/dev/null)"
    if [[ -z "$meta" ]] || ! jq -e '.data.entries' >/dev/null 2>&1 <<< "$meta"; then
        log_error "Failed to fetch structure metadata from RCSB"
        rm -f "$tmp_ids" "$tmp_meta"
        return "${EX_NETWORK:-5}"
    fi

    # keep search-result order: index entries by id, then walk the id list
    jq -r --argjson order "$id_json" '
        (.data.entries | map({(.rcsb_id): .}) | add // {}) as $byid
        | $order[]
        | $byid[.] // {rcsb_id: .}
        | [ .rcsb_id,
            (.struct.title // "NA"),
            (.exptl[0].method // "NA"),
            ((.rcsb_entry_info.resolution_combined // []) | .[0] // "NA" | tostring),
            ((.rcsb_accession_info.initial_release_date // "NA") | .[0:10]),
            ([.polymer_entities[]?.rcsb_entity_source_organism[]?.ncbi_scientific_name] | map(select(. != null)) | unique | join(";") | if . == "" then "NA" else . end),
            ([.polymer_entities[]?.uniprots[]?.rcsb_id] | map(select(. != null)) | unique | join(";") | if . == "" then "NA" else . end),
            ((.rcsb_entry_info.polymer_entity_count_protein // "NA") | tostring)
          ] | @tsv
    ' <<< "$meta" > "$tmp_meta"

    # ---- write outputs ----
    mkdir -p -- "$(dirname -- "$output_file")"
    {
        printf "PDB_ID\tTITLE\tMETHOD\tRESOLUTION\tRELEASED\tORGANISM\tUNIPROT\tCHAINS\n"
        cat "$tmp_meta"
    } > "$output_file"
    local ids_file="${output_file%.tsv}_ids.txt"
    cut -f1 "$tmp_meta" > "$ids_file"

    log_info "Table written to $output_file"
    log_info "PDB id list written to $ids_file"

    if [[ "${JSON_OUTPUT:-false}" != true ]]; then
        {
            printf "%-4s %-7s %-46.46s %-14.14s %-6s %-11s %s\n" "ID" "PDB" "TITLE" "METHOD" "RES" "RELEASED" "ORGANISM"
            nl -w2 -s"$(printf '\t')" "$tmp_meta" | awk -F'\t' '{
                printf "%-4s %-7s %-46.46s %-14.14s %-6s %-11s %s\n", $1, $2, $3, $4, $5, $6, $7
            }'
            echo
        } >&2
    fi

    rm -f "$tmp_ids" "$tmp_meta"
    return 0
}
