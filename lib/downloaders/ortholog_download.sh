#!/usr/bin/env bash

# Ortholog download. Ported from OASIS (EvoMol's Ortholog Alignment &
# Similarity Screener) - this keeps only the accession -> Gene ID ->
# ortholog-FASTA-download slice of that tool, not its downstream local BLAST
# filtering/extraction, which needs BLAST+ (a dependency SeqFetcher doesn't
# otherwise have). See docs/CONVENTIONS.md if BLAST filtering ever gets
# ported too - it belongs here since it manipulates the same protein FASTA.
#
# Two differences from OASIS's version, both to avoid new dependencies:
#   - Entrez esearch/elink calls use retmode=json + jq (already a hard
#     SeqFetcher dependency) instead of OASIS's python3 + xml.etree for the
#     elink step. OASIS's own gene->protein_refseq elink call already used
#     JSON; this just makes the protein/nuccore->gene calls consistent
#     with it.
#   - Entrez retries don't reuse downloaders_geo_download::retry_command:
#     that helper's retry message goes through log_warning, which - like
#     every other log_* function except log_error - writes to stdout. Every
#     caller here captures this function's stdout via $(...), so routing a
#     retry notice through it would splice "[WARN] Attempt..." into the
#     captured Entrez response on any retried call. _entrez_fetch's own
#     retry loop writes straight to stderr instead.

#==============================================================
# Accession-type detection
#==============================================================

# Args: $1 - accession or numeric Gene ID
# Prints one of: protein | nucleotide | gene_id | unknown
downloaders_ortholog_download::detect_accession_type() {
    local acc="$1"
    case "$acc" in
        NP_*|XP_*|WP_*) echo "protein" ;;
        NM_*|XM_*|NG_*) echo "nucleotide" ;;
        [0-9]*)         echo "gene_id" ;;
        *)
            log_error "Unrecognized ortholog accession format: $acc"
            log_error "Supported: NP_ XP_ WP_ NM_ XM_ NG_ or a numeric Gene ID"
            echo "unknown"
            ;;
    esac
}

#==============================================================
# Entrez E-utilities helpers
#==============================================================

# Fetches an Entrez E-utilities endpoint and prints the response body to
# stdout. Retries up to 3 times with exponential back-off (2s, 4s) on a
# failed/empty response, to ride out transient NCBI 429/5xx responses.
#
# Args: $1 - path + query string, e.g. "esearch.fcgi?db=protein&term=..."
downloaders_ortholog_download::_entrez_fetch() {
    local path="$1"
    local url="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/${path}"
    [[ -n "$NCBI_API_KEY" ]] && url="${url}&api_key=${NCBI_API_KEY}"

    local wait_secs=2 result
    for attempt in 1 2 3; do
        if result=$(curl -sS -f --globoff "$url" 2>/dev/null) && [[ -n "$result" ]]; then
            printf '%s' "$result"
            return 0
        fi
        echo "    Entrez request retry $attempt/3 (waiting ${wait_secs}s)..." >&2
        sleep "$wait_secs"
        wait_secs=$(( wait_secs * 2 ))
    done
    return 1
}

# Reads an elink JSON response (retmode=json) from stdin and prints the
# first linked ID found under any of the accepted linkname values.
#
# Args: $1 - space-separated accepted linknames, e.g. "protein_gene protein_gene_refseq"
downloaders_ortholog_download::_elink_first_id() {
    local accepted="$1"
    jq -r --arg names "$accepted" '
        ($names | split(" ")) as $accepted
        | .linksets[]?.linksetdbs[]?
        | select(.linkname as $n | $accepted | index($n))
        | .links[0] // empty
    ' | head -n1
}

# Converts a protein accession (NP_/XP_/WP_) to an NCBI Gene ID.
#   Step 1: esearch protein db by accession -> internal protein UID
#   Step 2: elink protein->gene using that UID -> Gene ID
downloaders_ortholog_download::_resolve_protein_to_gene() {
    local accession="$1"
    # >&2: this function's stdout is the resolved Gene ID, captured whole
    # by resolve_gene_id's caller via $(...) - a progress line on stdout
    # here would get spliced into that value (log_info, like every log_*
    # except log_error, writes to stdout).
    log_info "  [$accession] Resolving protein accession -> Gene ID..." >&2

    local puid
    puid=$(downloaders_ortholog_download::_entrez_fetch \
        "esearch.fcgi?db=protein&term=${accession}[accn]&retmode=json" |
        jq -r '.esearchresult.idlist[0] // empty')

    [[ -z "$puid" ]] && { log_error "  [$accession] Failed to resolve protein UID"; return 1; }

    local gene_id
    gene_id=$(downloaders_ortholog_download::_entrez_fetch \
        "elink.fcgi?dbfrom=protein&db=gene&id=${puid}&retmode=json" |
        downloaders_ortholog_download::_elink_first_id "protein_gene protein_gene_refseq")

    [[ -z "$gene_id" ]] && { log_error "  [$accession] Failed to resolve Gene ID from protein accession"; return 1; }
    echo "$gene_id"
}

# Converts a nucleotide accession (NM_/XM_/NG_) to an NCBI Gene ID.
# Mirrors _resolve_protein_to_gene but queries nuccore and accepts its
# link names instead.
downloaders_ortholog_download::_resolve_nuccore_to_gene() {
    local accession="$1"
    # >&2: same reason as _resolve_protein_to_gene above.
    log_info "  [$accession] Resolving nucleotide accession -> Gene ID..." >&2

    local nuid
    nuid=$(downloaders_ortholog_download::_entrez_fetch \
        "esearch.fcgi?db=nuccore&term=${accession}[accn]&retmode=json" |
        jq -r '.esearchresult.idlist[0] // empty')

    [[ -z "$nuid" ]] && { log_error "  [$accession] Failed to resolve nuccore UID"; return 1; }

    local gene_id
    gene_id=$(downloaders_ortholog_download::_entrez_fetch \
        "elink.fcgi?dbfrom=nuccore&db=gene&id=${nuid}&retmode=json" |
        downloaders_ortholog_download::_elink_first_id "nuccore_gene nucleotide_gene nuccore_gene_refseq")

    [[ -z "$gene_id" ]] && { log_error "  [$accession] Failed to resolve Gene ID from nucleotide accession"; return 1; }
    echo "$gene_id"
}

# Public dispatcher: routes any supported accession to the right resolver.
# A numeric Gene ID is already in the target format and passes through.
#
# Args: $1 - accession, $2 - its type (from detect_accession_type)
downloaders_ortholog_download::resolve_gene_id() {
    local accession="$1" acc_type="$2"
    case "$acc_type" in
        protein)    downloaders_ortholog_download::_resolve_protein_to_gene  "$accession" ;;
        nucleotide) downloaders_ortholog_download::_resolve_nuccore_to_gene  "$accession" ;;
        gene_id)    echo "$accession" ;;
        *)          return 1 ;;
    esac
}

#==============================================================
# Ortholog FASTA fetch
#==============================================================

# Downloads the complete set of orthologous protein sequences for a gene
# from the NCBI Datasets API, extracts them, and deduplicates by accession.
#
# Args: $1 - Gene ID, $2 - destination FASTA path, $3 - label for log lines
#
# Caching: if the destination FASTA already exists and is non-empty, the
# download is skipped - useful when a batch's accessions share a gene.
#
# Coverage: NCBI Datasets ortholog downloads cover vertebrates and insects
# only; other taxa will yield 0 orthologs. The API also silently truncates
# results around ~499 sequences - hitting that gets a loud warning so it
# isn't mistaken for a complete set.
downloaders_ortholog_download::fetch_orthologs() {
    local gene_id="$1" output_faa="$2" label="${3:-$gene_id}"
    local ortho_zip="$TEMP_DIR/orthologs_${gene_id}.zip"
    local ortho_dir="$TEMP_DIR/orthologs_${gene_id}"

    if [[ -s "$output_faa" ]]; then
        local cached
        cached=$(grep -c '^>' "$output_faa" 2>/dev/null || echo 0)
        log_info "  [$label] Using cached ortholog FASTA ($cached sequences)"
        return 0
    fi

    log_warning "  [$label] Ortholog downloads cover vertebrates and insects only"
    log_info "  [$label] Downloading ortholog protein sequences (gene ID: $gene_id)..."

    datasets download gene gene-id "$gene_id" \
        --ortholog all --include protein --filename "$ortho_zip" >/dev/null

    if [[ ! -s "$ortho_zip" ]]; then
        log_error "  [$label] Ortholog download failed for gene ID $gene_id"
        return 1
    fi

    mkdir -p "$ortho_dir"
    unzip -q -o "$ortho_zip" -d "$ortho_dir"

    # The archive may contain one protein FASTA per taxon group - merge them.
    find "$ortho_dir" -type f \( -name "*.faa" -o -name "*.protein.faa" \) \
        -exec cat {} + > "$output_faa"

    if [[ ! -s "$output_faa" ]]; then
        log_error "  [$label] No protein sequences found after extraction"
        rm -rf "$ortho_zip" "$ortho_dir"
        return 1
    fi

    # Deduplicate: some orthologs appear in more than one taxon FAA file.
    # Keep the first occurrence of each header's accession (first field).
    awk '/^>/{
        header=$0; split(header,a," "); id=a[1]
        if (seen[id]++) { skip=1 } else { skip=0; print }
        next
    } !skip { print }' "$output_faa" > "${output_faa}.dedup"
    mv "${output_faa}.dedup" "$output_faa"

    local count
    count=$(grep -c '^>' "$output_faa" 2>/dev/null || echo 0)
    log_info "  [$label] $count ortholog protein sequences ready"

    if [[ "$count" -ge 499 ]]; then
        log_warning "  [$label] Dataset cap reached: $count sequences (NCBI caps ortholog downloads at ~499)"
        log_warning "  [$label] Results are incomplete - split by taxon or use the NCBI web portal"
    fi

    rm -rf "$ortho_zip" "$ortho_dir"
}

#==============================================================
# Single-accession + batch drivers
#==============================================================

# Full single-accession pipeline: detect type -> resolve Gene ID -> fetch
# orthologs. Mirrors downloaders_ncbi_download::download_assembly's shape
# so downloaders_ortholog_download::download_orthologs_batch can background
# it exactly the way download_assemblies_parallel backgrounds that one.
#
# Output: OUTDIR/orthologs/<accession>/orthologs_<gene_id>.fasta
downloaders_ortholog_download::download_ortholog() {
    local accession="$1"
    local outdir="${2:-downloads}"

    [[ -z "$accession" ]] && { log_error "Empty accession"; return 1; }
    accession=$(echo "$accession" | xargs)
    [[ -z "$accession" ]] && { log_error "Accession is empty after trimming"; return 1; }

    require_datasets || return 1
    command -v jq >/dev/null 2>&1 || { log_error "jq is required but not installed"; return 1; }

    local acc_type
    acc_type=$(downloaders_ortholog_download::detect_accession_type "$accession")
    [[ "$acc_type" == "unknown" ]] && return 1

    local gene_id
    gene_id=$(downloaders_ortholog_download::resolve_gene_id "$accession" "$acc_type") || {
        log_error "  [$accession] Could not resolve a Gene ID"
        return 1
    }
    log_info "  [$accession] Gene ID: $gene_id"

    local dest_dir="$outdir/orthologs/$accession"
    mkdir -p "$dest_dir"

    downloaders_ortholog_download::fetch_orthologs \
        "$gene_id" "$dest_dir/orthologs_${gene_id}.fasta" "$accession"
}

# Runs download_ortholog for every accession in ACCESSION_FILE, up to $jobs
# in parallel. Structurally identical to
# downloaders_ncbi_download::download_assemblies_parallel - same
# background-job/kill -0 polling, same summary block - just calling a
# different single-item worker.
downloaders_ortholog_download::download_orthologs_batch() {
    local accession_file="$1"
    local outdir="$2"
    local jobs="${3:-4}"

    [[ ! -f "$accession_file" ]] && { log_error "Ortholog accession file not found: $accession_file"; return 1; }

    mapfile -t accessions < <(grep -vE '^\s*#|^\s*$' "$accession_file")
    local total=${#accessions[@]}

    [[ $total -eq 0 ]] && { log_error "No valid accessions found"; return 1; }

    log_info "Found $total accession(s) to process"
    echo

    local count=0
    local pids=()
    local successful=0
    local failed=0

    for acc in "${accessions[@]}"; do
        count=$((count + 1))

        echo "[$count/$total] Processing: $acc"

        downloaders_ortholog_download::download_ortholog "$acc" "$outdir" &
        pids+=($!)

        # Limit parallel jobs
        while [[ ${#pids[@]} -ge $jobs ]]; do
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                else
                    wait "$pid"
                    [[ $? -eq 0 ]] && ((successful++)) || ((failed++))
                fi
            done
            pids=("${new_pids[@]}")
            [[ ${#pids[@]} -ge $jobs ]] && sleep 0.5
        done
    done

    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
        [[ $? -eq 0 ]] && ((successful++)) || ((failed++))
    done

    echo
    log_info "═══════════════════════════════════════"
    log_info "Ortholog Download Summary"
    log_info "═══════════════════════════════════════"
    log_info "Total: $total"
    echo "[SUCCESS] Successful: $successful"
    [[ $failed -gt 0 ]] && log_error "Failed: $failed"
    log_info "═══════════════════════════════════════"
    echo
}
