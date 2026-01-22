#!/usr/bin/env bash

# ============================================================
# Functions for download using NCBI Datasets
# ============================================================

download_ncbi_datasets() {

    # --------------------------------------------------
    # Argument parsing
    # --------------------------------------------------
    local accession="$1"
    local download_type="${2:-genome}"
    local include="${3:-genome}"

    # --------------------------------------------------
    # Dependency checks
    # --------------------------------------------------
    log_step "METHOD 5: Using NCBI Datasets CLI"

    if ! check_command datasets; then
        log_error "Install with: conda install -c conda-forge ncbi-datasets-cli"
        return 1
    fi

    # --------------------------------------------------
    # Validation
    # --------------------------------------------------
    [[ -z "$accession" ]] && {
        log_error "Missing accession"
        log_info "Run: seqfetcher download ncbi --help"
        return 1
    }

    if ! validate_accession "$accession"; then
        return 1
    fi

    log_info "Processing: $accession"

    local output_dir="${OUTPUT_DIR}/genomes/${accession}"
    mkdir -p "$output_dir"

    # --------------------------------------------------
    # Dispatch by type
    # --------------------------------------------------
    case "$download_type" in

        genome)
            log_info "Downloading genome assembly..."

            local zip_file="${output_dir}/${accession}_genome.zip"

            # -------- include parsing --------
            local include_args=()
            local valid_includes=()

            IFS=',' read -ra ITEMS <<< "$include"
            for item in "${ITEMS[@]}"; do
                item=$(echo "$item" | tr -d ' ')
                case "$item" in
                    genome)  valid_includes+=("genome");  include_args+=(--include genome) ;;
                    cdna|rna) valid_includes+=("rna");     include_args+=(--include rna) ;;
                    pep|protein) valid_includes+=("protein"); include_args+=(--include protein) ;;
                    gff|gff3) valid_includes+=("gff");     include_args+=(--include gff3) ;;
                    gtf)     valid_includes+=("gtf");     include_args+=(--include gtf) ;;
                    cds)     valid_includes+=("cds");     include_args+=(--include cds) ;;
                    *)
                        log_warn "Ignoring invalid include value: $item"
                        log_info "Valid values: genome, cdna, rna, pep, gff, gtf, cds"
                        ;;
                esac
            done

            if [[ ${#valid_includes[@]} -eq 0 ]]; then
                log_error "No valid include values provided"
                return 1
            fi

            log_info "Including: ${valid_includes[*]}"

            # -------- download --------
            if datasets download genome accession "$accession" \
                "${include_args[@]}" \
                --filename "$zip_file"; then

                log_info "Extracting files to: $output_dir"

                if unzip -q "$zip_file" -d "$output_dir"; then
                    log_info "✓ Genome download complete!"

                    log_info ""
                    log_info "Directory preview:"
                    tree -L 3 "$output_dir" 2>/dev/null || ls -lhR "$output_dir" | head -20

                    return 0
                else
                    log_error "Failed to extract $zip_file"
                    return 1
                fi
            else
                log_error "Failed to download genome for $accession"
                return 1
            fi
            ;;

        gene)
            log_info "Downloading gene data..."

            local zip_file="${output_dir}/${accession}_genes.zip"

            if datasets download gene accession "$accession" --filename "$zip_file"; then
                unzip -q "$zip_file" -d "$output_dir"
                log_info "✓ Gene download complete!"
                return 0
            else
                log_error "Failed to download gene data"
                return 1
            fi
            ;;

        protein)
            log_info "Downloading protein data..."

            local zip_file="${output_dir}/${accession}_protein.zip"

            if datasets download genome accession "$accession" \
                --include protein --filename "$zip_file"; then
                unzip -q "$zip_file" -d "$output_dir"
                log_info "✓ Protein download complete!"
                return 0
            else
                log_error "Failed to download protein data"
                return 1
            fi
            ;;

        *)
            log_error "Unknown download type: $download_type"
            log_info "Valid types: genome, gene, protein"
            return 1
            ;;
    esac
}


search_ncbi_assemblies() {

    # --------------------------------------------------
    # Help
    # --------------------------------------------------
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<EOF
Usage:
  seqfetcher discover assembly --organism "<name>" [--out file] [--filter all|reference|representative]

Description:
  Search NCBI assemblies for a given organism and generate:
   - TSV summary
   - Accession list (ordered: reference first)

Options:
  --organism <name>     Scientific or common name (required)
  --out <file>         Output accession list file (default: OUTPUT_DIR/assembly_accessions.txt)
  --filter <mode>      all (default), reference, representative
  -h, --help           Show this help message

Examples:
  seqfetcher discover assembly --organism "Mus musculus"
  seqfetcher discover assembly --organism "Homo sapiens" --filter reference
  seqfetcher discover assembly --organism "Arabidopsis thaliana" --out arabidopsis.txt

Outputs:
  - <out>                          Accession list
  - <out>_summary.tsv              Assembly metadata summary

EOF
        return 0
    fi

    # -----------------------------
    # Dependency checks
    # -----------------------------
    command -v datasets >/dev/null 2>&1 || {
        log_error "datasets not found"
        log_error "Install with: conda install -c conda-forge ncbi-datasets-cli"
        return 1
    }

    command -v jq >/dev/null 2>&1 || {
        log_error "jq not found"
        log_error "Install with: conda install -c conda-forge jq"
        return 1
    }

    local organism="$1"
    local accession_out="${2:-${OUTPUT_DIR}/assembly_accessions.txt}"
    local filter="${3:-all}"

    [[ -z "$organism" ]] && {
        log_error "Organism name is required"
        return 1
    }

    local summary_out="${accession_out%.txt}_summary.tsv"
    local tmp_json="${TEMP_DIR}/assemblies.$$.json"

    log_info "Organism: $organism"
    log_info "Filter: $filter"
    log_info "Querying NCBI Datasets API..."

    # -----------------------------
    # Fetch assemblies
    # -----------------------------
    case "$filter" in
        reference)
            datasets summary genome taxon "$organism" --reference > "$tmp_json"
            ;;
        representative)
            datasets summary genome taxon "$organism" --assembly-source RefSeq > "$tmp_json"
            ;;
        *)
            datasets summary genome taxon "$organism" > "$tmp_json"
            ;;
    esac

    [[ ! -s "$tmp_json" ]] && {
        log_error "No data returned from NCBI"
        rm -f "$tmp_json"
        return 1
    }

    jq -e '.reports' "$tmp_json" >/dev/null 2>&1 || {
        log_error "No assemblies found for organism: $organism"
        rm -f "$tmp_json"
        return 1
    }

    local total_count
    total_count=$(jq '.reports | length' "$tmp_json")

    log_info "Found $total_count assembly/assemblies"

    # -----------------------------
    # Write TSV (overwrite)
    # -----------------------------
    echo -e "Accession\tOrganism\tAssembly_Name\tLevel\tRelease_Date\tRefSeq_Category" \
        > "$summary_out"

    jq -r '
        .reports[] |
        [
            .accession,
            .organism.organism_name,
            .assembly_info.assembly_name,
            .assembly_info.assembly_level,
            .assembly_info.release_date,
            (.assembly_info.refseq_category // "N/A")
        ] | @tsv
    ' "$tmp_json" >> "$summary_out"

    # -----------------------------
    # Reorder TSV: reference genomes first
    # -----------------------------
    {
        # Header
        head -n 1 "$summary_out"

        # Reference genomes
        awk -F'\t' '
            NR>1 && tolower($6) ~ /reference genome/
        ' "$summary_out"

        # Remaining assemblies
        awk -F'\t' '
            NR>1 && tolower($6) !~ /reference genome/
        ' "$summary_out"
    } > "${summary_out}.tmp"

    mv "${summary_out}.tmp" "$summary_out"

    # -----------------------------
    # Write accession list (from reordered TSV)
    # -----------------------------
    awk -F'\t' 'NR>1 {print $1}' "$summary_out" > "$accession_out"

    # -----------------------------
# Preview (clean, aligned)
# -----------------------------
log_info ""
log_info "Assembly summary (preview):"
log_info "--------------------------"

if command -v column >/dev/null 2>&1; then
    column -t -s $'\t' "$summary_out" | sed -n '1,10p'
else
    sed -n '1,10p' "$summary_out"
fi

if (( total_count > 9 )); then
    log_info "... and $((total_count - 9)) more assemblies"
fi

    # -----------------------------
    # Reference genome log
    # -----------------------------
    local ref_count
    ref_count=$(awk -F'\t' 'NR>1 && tolower($6) ~ /reference/ {count++} END {print count+0}' "$summary_out")

    if (( ref_count > 0 )); then
        log_info ""
        log_info "📌 Reference genomes: $ref_count"

        awk -F'\t' '
NR>1 && tolower($6) ~ /reference/ {
    printf "  • %s - %s (%s)\n", $1, $3, $6
}' "$summary_out"
    fi

    # Also show chromosome-level count if different
    local chr_count
    chr_count=$(awk -F'\t' 'NR>1 && (tolower($4) ~ /chromosome/ || tolower($4) ~ /complete genome/) {count++} END {print count+0}' "$summary_out")
    
    if (( chr_count > ref_count )); then
        log_info ""
        log_info "ℹ️  Chromosome/Complete-level assemblies: $chr_count (including $ref_count reference)"
    fi

    # -----------------------------
    # Final output
    # -----------------------------
    log_info ""
    log_info "✓ Results saved:"
    log_info "  TSV summary: $summary_out"
    log_info "  Accession list: $accession_out"

    rm -f "$tmp_json"
    return 0
}

search_and_download_assembly() {

    # --------------------------------------------------
    # Help
    # --------------------------------------------------
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<EOF
Usage:
  seqfetcher ncbi auto --organism "<name>" [--filter reference|all] [--include list]

Description:
  Search NCBI assemblies for an organism and interactively download
  one or more genome assemblies.

Options:
  --organism <name>     Organism name (required)
  --filter <mode>      reference (default) or all
  --include <list>     genome include list (default: genome)
  -h, --help           Show this help message

Examples:
  seqfetcher ncbi auto --organism "Mus musculus"
  seqfetcher ncbi auto --organism "Homo sapiens" --filter all --include genome,gff,gtf

EOF
        return 0
    fi
    
    local organism=$1
    local filter=${2:-reference}
    local include=${3:-genome}
    
    if [[ -z "$organism" ]]; then
        log_error "Please provide an organism name"
        return 1
    fi
    
    local temp_list="${TEMP_DIR}/assembly_accessions.txt"
    search_ncbi_assemblies "$organism" "$temp_list" "$filter" || return 1
    
    local count=$(wc -l < "$temp_list")
    
    if [[ $count -eq 0 ]]; then
        log_error "No assemblies found"
        return 1
    elif [[ $count -eq 1 ]]; then
        local accession=$(cat "$temp_list")
        log_info ""
        log_info "Downloading assembly: $accession"
        download_ncbi_datasets "$accession" genome "$include"
    else
        log_info ""
        log_info "Multiple assemblies found. Choose one:"
        log_info ""
        
        local i=1
        while IFS= read -r accession; do
            echo "  $i) $accession"
            ((i++))
        done < "$temp_list"
        
        echo ""
        echo "Options: number (1-$count), 'all', or 'q' to quit"
        
        local choice
        if read -t 120 -p "Enter choice [timeout 120s]: " choice; then
            case "$choice" in
                q|Q)
                    log_info "Cancelled by user"
                    return 0
                    ;;
                all|ALL)
                    log_info "Downloading all assemblies..."
                    local idx=0
                    while IFS= read -r accession; do
                        ((idx++))
                        log_info ""
                        show_progress "$idx" "$count" "$accession"
                        download_ncbi_datasets "$accession" genome "$include"
                    done < "$temp_list"
                    ;;
                ''|*[!0-9]*)
                    log_error "Invalid choice: $choice"
                    return 1
                    ;;
                *)
                    if [[ $choice -ge 1 && $choice -le $count ]]; then
                        local accession=$(sed -n "${choice}p" "$temp_list")
                        log_info ""
                        log_info "Downloading assembly: $accession"
                        download_ncbi_datasets "$accession" genome "$include"
                    else
                        log_error "Invalid number: $choice (must be 1-$count)"
                        return 1
                    fi
                    ;;
            esac
        else
            log_warn "Timeout - downloading first assembly by default"
            local accession=$(head -n 1 "$temp_list")
            download_ncbi_datasets "$accession" genome "$include"
        fi
    fi
    
    return 0
}

download_genomes_from_list() {

    # --------------------------------------------------
    # Help
    # --------------------------------------------------
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<EOF
Usage:
  seqfetcher download ncbi-batch --accessions <file> [--include list]

Description:
  Download multiple genome assemblies from a list of accessions
  using NCBI Datasets CLI.

Options:
  --accessions <file>  File with one accession per line
  --include <list>    Include list (default: genome)
  -h, --help          Show this help message

Examples:
  seqfetcher download ncbi-batch --accessions assemblies.txt
  seqfetcher download ncbi-batch --accessions assemblies.txt --include genome,gff,gtf,cds

Notes:
  - Output directory: \$OUTPUT_DIR/genomes/<accession>/
  - Progress and failures are tracked per accession

EOF
        return 0
    fi
    local accession_list=$1
    local include=${2:-genome}

    log_info "Starting batch genome download..."
    log_info "Reading from: $accession_list"
    log_info "Include types: $include"

    [[ ! -f "$accession_list" ]] && {
        log_error "Accession list not found: $accession_list"
        return 1
    }

    # Debug: show file contents
    log_debug "File contents (first 5 lines):"
    head -n 5 "$accession_list" 2>&1 | while IFS= read -r line; do
        log_debug "  $line"
    done

    local total=$(grep -Ecv '^[[:space:]]*$|^[[:space:]]*#' "$accession_list" || echo 0)
    local current=0
    local success=0
    local failed=0

    log_info "Total accessions found: $total"

    if [[ $total -eq 0 ]]; then
        log_error "No valid accessions in file!"
        return 1
    fi

    while IFS= read -r accession; do
        [[ -z "$accession" || "$accession" =~ ^# ]] && continue

        ((current++))
        show_progress "$current" "$total" "$accession"
        
        log_info "Downloading accession $current/$total: $accession"

        if download_ncbi_datasets "$accession" genome "$include"; then
            ((success++))
        else
            ((failed++))
            log_warn "Failed to download $accession"
        fi
    done < "$accession_list"

    log_info ""
    log_info "==================== BATCH SUMMARY ===================="
    log_info "Total: $total | Success: $success | Failed: $failed"
    
    [[ $failed -gt 0 ]] && return 1
    return 0
}
