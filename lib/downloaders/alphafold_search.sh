#!/usr/bin/env bash

# AlphaFold structure search == UniProt search.
#
# AlphaFold DB has no query interface of its own - it is keyed purely by
# UniProt accession. So "what AlphaFold models exist for X" is a UniProt
# search (rest.uniprot.org/uniprotkb/search), and every result accession
# maps to the model id  AF-<accession>-F1.
#
# Produces a TSV + a bare-accession list that feeds
# `download --structure --alphafold-file`.

UNIPROT_SEARCH_URL="https://rest.uniprot.org/uniprotkb/search"
ALPHAFOLD_PREDICTION_URL="https://alphafold.ebi.ac.uk/api/prediction"

# downloaders_alphafold_search::search_models <output_file> <top_n>
downloaders_alphafold_search::search_models() {
    local output_file="${1:-alphafold_structures.tsv}"
    local top_n="${2:-50}"
    (( top_n > 50000 )) && { log_warning "capping --top at 50000 for an AlphaFold search"; top_n=50000; }

    require_jq || return "${EX_DEPENDENCY:-3}"
    downloaders_common::check_command curl || return "${EX_DEPENDENCY:-3}"

    log_step "Searching UniProt for AlphaFold models"

    # ---- build the UniProt query ----
    local -a parts=()
    if [[ -n "$SEARCH_TAXON_ID" ]]; then
        parts+=("(taxonomy_id:${SEARCH_TAXON_ID})")
    elif [[ -n "$ORGANISM" ]]; then
        parts+=("(organism_name:\"${ORGANISM}\")")
    fi
    [[ "$SEARCH_REVIEWED" == true ]] && parts+=("(reviewed:true)")
    [[ -n "$SEARCH_GENE" ]]     && parts+=("(gene:${SEARCH_GENE})")
    [[ -n "$SEARCH_KEYWORD" ]]  && parts+=("(keyword:${SEARCH_KEYWORD})")
    [[ -n "$SEARCH_PROTEOME" ]] && parts+=("(proteome:${SEARCH_PROTEOME})")
    [[ -n "$SEARCH_TEXT" ]]     && parts+=("(${SEARCH_TEXT})")

    local query; query="$(printf ' AND %s' "${parts[@]}")"; query="${query# AND }"
    local fields="accession,id,protein_name,gene_primary,length,organism_name,reviewed"

    local tmp_rows hdrs
    tmp_rows=$(mktemp) || return "${EX_ERROR:-1}"
    hdrs=$(mktemp) || { rm -f "$tmp_rows"; return "${EX_ERROR:-1}"; }

    # ---- fetch (paginated) ----
    local url total="" release="" got=0 page_size cursor="" first=true
    while :; do
        page_size=$(( top_n - got )); (( page_size > 500 )) && page_size=500
        (( page_size <= 0 )) && break

        if [[ -z "$cursor" ]]; then
            url="${UNIPROT_SEARCH_URL}?query=$(downloaders_alphafold_search::_urlenc "$query")&fields=${fields}&format=tsv&size=${page_size}"
        else
            url="${UNIPROT_SEARCH_URL}?cursor=${cursor}&fields=${fields}&format=tsv&size=${page_size}"
        fi

        : > "$hdrs"
        local body
        body="$(curl -fsS -D "$hdrs" "$url" 2>/dev/null)" || { log_error "UniProt search request failed"; rm -f "$tmp_rows" "$hdrs"; return "${EX_NETWORK:-5}"; }

        if [[ "$first" == true ]]; then
            total="$(grep -i '^x-total-results:' "$hdrs" | awk '{print $2}' | tr -d '\r')"
            release="$(grep -i '^x-uniprot-release:' "$hdrs" | awk '{print $2}' | tr -d '\r')"
            first=false
        fi

        # append rows (skip the header line on every page)
        local n
        n=$(tail -n +2 <<< "$body" | grep -c . || true)
        tail -n +2 <<< "$body" >> "$tmp_rows"
        got=$(( got + n ))

        cursor="$(grep -i '^link:' "$hdrs" | grep -o 'cursor=[^&>]*' | head -n1 | cut -d= -f2)"
        [[ -z "$cursor" || $n -eq 0 || $got -ge $top_n ]] && break
    done
    rm -f "$hdrs"

    local shown; shown=$(grep -c . "$tmp_rows" || true)
    [[ "${shown:-0}" -eq 0 ]] && { log_error "No UniProt entries matched the query"; rm -f "$tmp_rows"; return "${EX_NOTFOUND:-4}"; }

    log_info "Found ${total:-$shown} matching UniProt entries; keeping the top $shown"
    [[ -n "$release" ]] && log_info "UniProt release: $release"

    # ---- optional per-accession AlphaFold check ----
    local extra_header="" checked_file=""
    if [[ "$CHECK_ALPHAFOLD" == true ]]; then
        log_step "Verifying AlphaFold models ($shown accessions, ~3/s)"
        checked_file=$(mktemp)
        local acc rest af ver plddt missing=0
        while IFS=$'\t' read -r acc rest; do
            af="$(curl -fsS "${ALPHAFOLD_PREDICTION_URL}/${acc}" 2>/dev/null)"
            if [[ -n "$af" ]] && jq -e '.[0]' >/dev/null 2>&1 <<< "$af"; then
                ver="$(jq -r '.[0].latestVersion // ""' <<< "$af")"
                plddt="$(jq -r '.[0].globalMetricValue // ""' <<< "$af")"
                printf '%s\t%s\tAF-%s-F1\t%s\t%s\n' "$acc" "$rest" "$acc" "$ver" "$plddt" >> "$checked_file"
            else
                (( missing++ ))
            fi
            sleep 0.34
        done < "$tmp_rows"
        mv "$checked_file" "$tmp_rows"
        (( missing > 0 )) && log_warning "$missing accession(s) had no AlphaFold model - dropped"
        shown=$(grep -c . "$tmp_rows" || true)
        extra_header="\tMODEL_VERSION\tMEAN_PLDDT"
    else
        # add the ALPHAFOLD_ID column
        awk -F'\t' 'BEGIN{OFS="\t"} {print $0, "AF-" $1 "-F1"}' "$tmp_rows" > "${tmp_rows}.2" && mv "${tmp_rows}.2" "$tmp_rows"
    fi

    # ---- write outputs ----
    mkdir -p -- "$(dirname -- "$output_file")"
    {
        printf "ACCESSION\tENTRY_NAME\tPROTEIN\tGENE\tLENGTH\tORGANISM\tREVIEWED\tALPHAFOLD_ID${extra_header}\n"
        cat "$tmp_rows"
    } > "$output_file"
    local acc_file="${output_file%.tsv}_accessions.txt"
    cut -f1 "$tmp_rows" > "$acc_file"

    log_info "Table written to $output_file"
    log_info "Accession list written to $acc_file"

    if [[ "${JSON_OUTPUT:-false}" != true ]]; then
        {
            printf "%-4s %-11s %-13s %-12s %-6s %s\n" "ID" "ACCESSION" "ENTRY_NAME" "GENE" "LEN" "ORGANISM"
            nl -w2 -s"$(printf '\t')" "$tmp_rows" | awk -F'\t' '{
                printf "%-4s %-11s %-13s %-12s %-6s %s\n", $1, $2, $3, $5, $6, $7
            }'
            echo
        } >&2
    fi

    rm -f "$tmp_rows"
    return 0
}

downloaders_alphafold_search::_urlenc() {
    jq -rn --arg s "$1" '$s|@uri'
}
