#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# seqfetcher — Unified sequencing data fetcher
# ============================================================

VERSION="1.2.0"

# -------------------------------
# Defaults / globals
# -------------------------------
THREADS=8
OUTPUT_DIR="downloads"
TEMP_DIR="temp_downloads"
DRY_RUN=false
VERBOSE=false
MAX_SIZE="200G"
MAX_RETRIES=3
ENSEMBL_BASE="https://ftp.ensembl.org/pub/current_fasta"
LOG_FILE=""

# -------------------------------
# Logging
# -------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    local msg="[INFO] $*"
    echo -e "${GREEN}${msg}${NC}"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

log_warn() {
    local msg="[WARN] $*"
    echo -e "${YELLOW}${msg}${NC}"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

log_error() {
    local msg="[ERROR] $*"
    echo -e "${RED}${msg}${NC}" >&2
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

log_step() {
    local msg="== $* =="
    echo -e "\n${BLUE}${msg}${NC}\n"
    [[ -n "$LOG_FILE" ]] && echo "" >> "$LOG_FILE"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

log_debug() {
    [[ "$VERBOSE" == true ]] && log_info "[DEBUG] $*"
}

# -------------------------------
# Utilities
# -------------------------------
check_command() {
    command -v "$1" &>/dev/null || {
        log_error "Missing dependency: $1"
        return 1
    }
}

create_dirs() {
    mkdir -p "$OUTPUT_DIR"/{fastq,metadata,genomes,transcriptomes,proteomes}
    mkdir -p "$TEMP_DIR"
    LOG_FILE="${OUTPUT_DIR}/seqfetcher.log"
    log_info "Created output directories"
    log_info "Log file: $LOG_FILE"
}

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        log_debug "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

retry_command() {
    local max_attempts=${MAX_RETRIES}
    local attempt=1
    local delay=5
    
    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
            sleep $delay
            ((attempt++))
            delay=$((delay * 2))
        else
            log_error "All $max_attempts attempts failed"
            return 1
        fi
    done
}

run_command() {
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

validate_accession() {
    local acc=$1
    
    [[ -z "$acc" ]] && {
        log_error "Empty accession provided"
        return 1
    }
    
    local len=${#acc}
    if [[ $len -lt 6 || $len -gt 30 ]]; then
        log_warn "Unusual accession length: $len characters"
    fi
    
    case "$acc" in
        GCF_[0-9]*.[0-9]*|GCA_[0-9]*.[0-9]*) return 0 ;;
        SRR[0-9]*|ERR[0-9]*|DRR[0-9]*) return 0 ;;
        GSE[0-9]*|GSM[0-9]*|SRP[0-9]*|ERP[0-9]*|DRP[0-9]*) return 0 ;;
        *) 
            log_error "Invalid accession format: $acc"
            log_info "Valid formats: GCF_*, GCA_*, SRR*, ERR*, DRR*, GSE*, GSM*"
            return 1
            ;;
    esac
}

mark_complete() {
    local accession=$1
    local status_file="${OUTPUT_DIR}/.completed"
    echo "$accession" >> "$status_file"
    log_debug "Marked $accession as complete"
}

is_complete() {
    local accession=$1
    local status_file="${OUTPUT_DIR}/.completed"
    [[ -f "$status_file" ]] && grep -q "^${accession}$" "$status_file"
}

show_progress() {
    local current=$1
    local total=$2
    local accession=$3
    log_info "[$current/$total] Processing: $accession"
}

# ==============================================================================
# METHOD 1: SRA-TOOLS (fasterq-dump)
# ==============================================================================

download_sra_fasterq() {
    log_step "METHOD 1: Using fasterq-dump (SRA Toolkit)"
    
    if ! check_command fasterq-dump; then
        log_error "Install with: conda install -c bioconda sra-tools"
        return 1
    fi
    
    local accession_list=$1
    
    if [[ ! -f "$accession_list" ]]; then
        log_error "Accession list file not found: $accession_list"
        return 1
    fi
    
    local total=$(grep -cv '^#\|^$' "$accession_list" || echo 0)
    local current=0
    local success=0
    local failed=0
    local failed_list=()
    
    log_info "Reading accessions from: $accession_list"
    log_info "Total accessions: $total"
    
    while IFS= read -r accession; do
        [[ -z "$accession" || "$accession" =~ ^# ]] && continue
        
        ((current++))
        show_progress "$current" "$total" "$accession"
        
        if is_complete "$accession"; then
            log_info "Skipping $accession (already completed)"
            ((success++))
            continue
        fi
        
        if ! validate_accession "$accession"; then
            ((failed++))
            failed_list+=("$accession")
            continue
        fi
        
        log_info "Downloading $accession with fasterq-dump..."
        
        if retry_command fasterq-dump "$accession" \
            --outdir "${OUTPUT_DIR}/fastq" \
            --temp "${TEMP_DIR}" \
            --threads "$THREADS" \
            --split-files \
            --progress; then
            
            log_info "Compressing FASTQ files for $accession..."
            find "${OUTPUT_DIR}/fastq" -name "${accession}*.fastq" -type f -exec gzip {} \; 2>/dev/null || true
            
            mark_complete "$accession"
            ((success++))
            log_info "✓ Completed: $accession"
        else
            log_error "✗ Failed: $accession"
            ((failed++))
            failed_list+=("$accession")
        fi
        
    done < "$accession_list"
    
    log_info ""
    log_info "==================== DOWNLOAD SUMMARY ===================="
    log_info "Total: $total | Success: $success | Failed: $failed"
    
    if [[ $failed -gt 0 ]]; then
        log_warn "Failed accessions:"
        printf '  - %s\n' "${failed_list[@]}"
        return 1
    fi
    
    log_info "All downloads complete!"
    return 0
}

# ==============================================================================
# METHOD 2: SRA-TOOLS with PREFETCH
# ==============================================================================

download_sra_prefetch() {
    log_step "METHOD 2: Using prefetch + fasterq-dump (More robust)"
    
    if ! check_command prefetch || ! check_command fasterq-dump; then
        log_error "Install with: conda install -c bioconda sra-tools"
        return 1
    fi
    
    local accession_list=$1
    
    if [[ ! -f "$accession_list" ]]; then
        log_error "Accession list file not found: $accession_list"
        return 1
    fi
    
    local total=$(grep -cv '^#\|^$' "$accession_list" || echo 0)
    local current=0
    local success=0
    local failed=0
    local failed_list=()
    
    while IFS= read -r accession; do
        [[ -z "$accession" || "$accession" =~ ^# ]] && continue
        
        ((current++))
        show_progress "$current" "$total" "$accession"
        
        if is_complete "$accession"; then
            log_info "Skipping $accession (already completed)"
            ((success++))
            continue
        fi
        
        if ! validate_accession "$accession"; then
            ((failed++))
            failed_list+=("$accession")
            continue
        fi
        
        log_info "Pre-fetching $accession..."
        
        if retry_command prefetch "$accession" \
            --max-size "$MAX_SIZE" \
            --output-directory "${TEMP_DIR}" \
            --progress; then
            
            log_info "Converting $accession to FASTQ..."
            
            if fasterq-dump "${TEMP_DIR}/${accession}/${accession}.sra" \
                --outdir "${OUTPUT_DIR}/fastq" \
                --temp "${TEMP_DIR}/temp" \
                --threads "$THREADS" \
                --split-files \
                --progress; then
                
                gzip "${OUTPUT_DIR}/fastq/${accession}"*.fastq 2>/dev/null || true
                rm -rf "${TEMP_DIR}/${accession}"
                
                mark_complete "$accession"
                ((success++))
                log_info "✓ Completed: $accession"
            else
                log_error "✗ Failed to convert: $accession"
                ((failed++))
                failed_list+=("$accession")
            fi
        else
            log_error "✗ Failed to prefetch: $accession"
            ((failed++))
            failed_list+=("$accession")
        fi
        
    done < "$accession_list"
    
    log_info ""
    log_info "==================== DOWNLOAD SUMMARY ===================="
    log_info "Total: $total | Success: $success | Failed: $failed"
    
    if [[ $failed -gt 0 ]]; then
        log_warn "Failed accessions:"
        printf '  - %s\n' "${failed_list[@]}"
        return 1
    fi
    
    log_info "All downloads complete!"
    return 0
}

# ==============================================================================
# METHOD 3: PARALLEL-FASTQ-DUMP
# ==============================================================================

download_parallel_fastq() {
    log_step "METHOD 3: Using parallel-fastq-dump (Fastest)"
    
    if ! check_command parallel-fastq-dump; then
        log_error "Install with: pip install parallel-fastq-dump"
        return 1
    fi
    
    local accession_list=$1
    
    if [[ ! -f "$accession_list" ]]; then
        log_error "Accession list file not found: $accession_list"
        return 1
    fi
    
    local total=$(grep -cv '^#\|^$' "$accession_list" || echo 0)
    local current=0
    local success=0
    local failed=0
    local failed_list=()
    
    while IFS= read -r accession; do
        [[ -z "$accession" || "$accession" =~ ^# ]] && continue
        
        ((current++))
        show_progress "$current" "$total" "$accession"
        
        if is_complete "$accession"; then
            log_info "Skipping $accession (already completed)"
            ((success++))
            continue
        fi
        
        if ! validate_accession "$accession"; then
            ((failed++))
            failed_list+=("$accession")
            continue
        fi
        
        log_info "Downloading $accession with parallel-fastq-dump..."
        
        if retry_command parallel-fastq-dump \
            --sra-id "$accession" \
            --threads "$THREADS" \
            --outdir "${OUTPUT_DIR}/fastq" \
            --split-files \
            --tmpdir "${TEMP_DIR}" \
            --gzip; then
            
            mark_complete "$accession"
            ((success++))
            log_info "✓ Completed: $accession"
        else
            log_error "✗ Failed: $accession"
            ((failed++))
            failed_list+=("$accession")
        fi
        
    done < "$accession_list"
    
    log_info ""
    log_info "==================== DOWNLOAD SUMMARY ===================="
    log_info "Total: $total | Success: $success | Failed: $failed"
    
    if [[ $failed -gt 0 ]]; then
        log_warn "Failed accessions:"
        printf '  - %s\n' "${failed_list[@]}"
        return 1
    fi
    
    log_info "All downloads complete!"
    return 0
}

# ==============================================================================
# METHOD 4: ENA
# ==============================================================================

download_ena() {
    log_step "METHOD 4: Using ENA (European Nucleotide Archive)"
    
    if ! check_command wget && ! check_command curl; then
        log_error "Please install wget or curl"
        return 1
    fi
    
    local accession_list=$1
    
    if [[ ! -f "$accession_list" ]]; then
        log_error "Accession list file not found: $accession_list"
        return 1
    fi
    
    local total=$(grep -cv '^#\|^$' "$accession_list" || echo 0)
    local current=0
    local success_count=0
    local fail_count=0
    local failed_accessions=()
    
    while IFS= read -r accession; do
        [[ -z "$accession" || "$accession" =~ ^# ]] && continue
        
        ((current++))
        show_progress "$current" "$total" "$accession"
        
        if is_complete "$accession"; then
            log_info "Skipping $accession (already completed)"
            ((success_count++))
            continue
        fi
        
        if ! validate_accession "$accession"; then
            ((fail_count++))
            failed_accessions+=("$accession")
            continue
        fi
        
        log_info "Fetching ENA metadata for $accession..."
        
        local ena_url="https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${accession}&result=read_run&fields=run_accession,fastq_ftp,fastq_md5,fastq_bytes"
        
        if command -v wget &> /dev/null; then
            wget -q -O "${TEMP_DIR}/${accession}_ena.txt" "$ena_url" || {
                log_error "Failed to fetch metadata for $accession"
                ((fail_count++))
                failed_accessions+=("$accession")
                continue
            }
        else
            curl -s -o "${TEMP_DIR}/${accession}_ena.txt" "$ena_url" || {
                log_error "Failed to fetch metadata for $accession"
                ((fail_count++))
                failed_accessions+=("$accession")
                continue
            }
        fi
        
        if [[ ! -s "${TEMP_DIR}/${accession}_ena.txt" ]]; then
            log_error "No metadata returned for $accession"
            ((fail_count++))
            failed_accessions+=("$accession")
            continue
        fi
        
        local line_count=$(wc -l < "${TEMP_DIR}/${accession}_ena.txt")
        if [[ $line_count -lt 2 ]]; then
            log_error "No data in ENA for $accession"
            ((fail_count++))
            failed_accessions+=("$accession")
            continue
        fi
        
        local has_files=false
        local download_failed=false
        
        while IFS=$'\t' read -r run_acc ftp_urls md5_sums file_sizes; do
            
            if [[ -z "$ftp_urls" || "$ftp_urls" == "null" ]]; then
                log_error "No FASTQ files available at ENA for $run_acc"
                log_info "This accession may only be available through SRA"
                download_failed=true
                continue
            fi
            
            has_files=true
            log_info "Downloading FASTQ files for $run_acc..."
            
            IFS=';' read -ra FTP_ARRAY <<< "$ftp_urls"
            IFS=';' read -ra MD5_ARRAY <<< "$md5_sums"
            IFS=';' read -ra SIZE_ARRAY <<< "$file_sizes"
            
            for i in "${!FTP_ARRAY[@]}"; do
                ftp_url="${FTP_ARRAY[$i]}"
                expected_md5="${MD5_ARRAY[$i]}"
                expected_size="${SIZE_ARRAY[$i]}"
                
                [[ ! "$ftp_url" =~ ^ftp:// ]] && ftp_url="ftp://$ftp_url"
                
                filename=$(basename "$ftp_url")
                output_file="${OUTPUT_DIR}/fastq/${filename}"
                
                local size_display="Unknown"
                if [[ -n "$expected_size" && "$expected_size" != "null" ]]; then
                    size_display=$(numfmt --to=iec-i --suffix=B "$expected_size" 2>/dev/null || echo "${expected_size}B")
                fi
                
                log_info "  Downloading: $filename (Size: $size_display)"
                
                if retry_command wget -c -q --show-progress -O "$output_file" "$ftp_url"; then
                    log_info "  ✓ Downloaded: $filename"
                    
                    if [[ -n "$expected_md5" && "$expected_md5" != "null" ]]; then
                        log_info "  Verifying MD5 checksum..."
                        actual_md5=$(md5sum "$output_file" | awk '{print $1}')
                        
                        if [[ "$actual_md5" == "$expected_md5" ]]; then
                            log_info "  ✓ Checksum verified"
                        else
                            log_error "  ✗ Checksum mismatch for $filename"
                            log_error "    Expected: $expected_md5"
                            log_error "    Got: $actual_md5"
                            download_failed=true
                        fi
                    fi
                    
                    if [[ -n "$expected_size" && "$expected_size" != "null" ]]; then
                        actual_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null)
                        if [[ "$actual_size" == "$expected_size" ]]; then
                            log_info "  ✓ File size verified"
                        else
                            log_warn "  ⚠ File size mismatch (expected: $expected_size, got: $actual_size)"
                        fi
                    fi
                else
                    log_error "  ✗ Failed to download $filename"
                    download_failed=true
                fi
            done
            
        done < <(tail -n +2 "${TEMP_DIR}/${accession}_ena.txt")
        
        if [[ "$has_files" == true && "$download_failed" == false ]]; then
            mark_complete "$accession"
            ((success_count++))
            log_info "✓ Completed: $accession"
        else
            ((fail_count++))
            failed_accessions+=("$accession")
            log_error "✗ Failed: $accession"
        fi
        
    done < "$accession_list"
    
    log_info ""
    log_info "==================== DOWNLOAD SUMMARY ===================="
    log_info "Total: $total | Success: $success_count | Failed: $fail_count"
    
    if [[ $fail_count -gt 0 ]]; then
        log_warn ""
        log_warn "Failed accessions (try alternative methods):"
        printf '  - %s\n' "${failed_accessions[@]}"
        log_info ""
        log_info "Alternative download methods:"
        log_info "  1. seqfetcher download fastq --accessions <file> --source sra --method fasterq"
        log_info "  2. seqfetcher download fastq --accessions <file> --source sra --method prefetch"
        log_info "  3. seqfetcher download fastq --accessions <file> --source sra --method parallel"
        return 1
    fi
    
    log_info "All downloads complete!"
    return 0
}

# ==============================================================================
# METHOD 5: NCBI DATASETS
# ==============================================================================

download_ncbi_datasets() {
    log_step "METHOD 5: Using NCBI Datasets CLI"
    
    if ! check_command datasets; then
        log_error "Install with: conda install -c conda-forge ncbi-datasets-cli"
        return 1
    fi
    
    local accession=$1
    local download_type=${2:-genome}
    local include="${3:-genome}"
    
    if ! validate_accession "$accession"; then
        return 1
    fi
    
    log_info "Processing: $accession"
    
    local output_dir="${OUTPUT_DIR}/genomes/${accession}"
    mkdir -p "$output_dir"
    
    case $download_type in
        genome)
            log_info "Downloading genome assembly..."
            
            local zip_file="${output_dir}/${accession}_genome.zip"
            
            local include_args=()
            local valid_includes=()
            
            IFS=',' read -ra ITEMS <<< "$include"
            for item in "${ITEMS[@]}"; do
                item=$(echo "$item" | tr -d ' ')
                case "$item" in
                    genome) valid_includes+=("$item"); include_args+=(--include genome) ;;
                    cdna) valid_includes+=("$item"); include_args+=(--include rna) ;;
                    rna) valid_includes+=("$item"); include_args+=(--include rna) ;;
                    pep|protein) valid_includes+=("protein"); include_args+=(--include protein) ;;
                    gff|gff3) valid_includes+=("gff"); include_args+=(--include gff3) ;;
                    gtf) valid_includes+=("gtf"); include_args+=(--include gtf) ;;
                    cds) valid_includes+=("cds"); include_args+=(--include cds) ;;
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
            
            if run_command datasets download genome accession "$accession" \
                "${include_args[@]}" \
                --filename "$zip_file"; then
                
                log_info "Extracting files to: $output_dir"
                if unzip -q "$zip_file" -d "$output_dir"; then
                    log_info "✓ Genome download complete!"
                    
                    # Optionally remove zip file
                    # rm -f "$zip_file"
                    
                    log_info ""
                    log_info "Directory structure:"
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
            
            if run_command datasets download gene accession "$accession" --filename "$zip_file"; then
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
            
            if run_command datasets download genome accession "$accession" \
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

# ==============================================================================
# SEARCH NCBI ASSEMBLIES
# ==============================================================================

search_ncbi_assemblies() {
    log_step "Searching NCBI Assemblies"

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

# ==============================================================================
# SEARCH AND DOWNLOAD ASSEMBLY
# ==============================================================================

search_and_download_assembly() {
    log_step "Search and Download Assembly"
    
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

# ==============================================================================
# ENSEMBL FASTA
# ==============================================================================

get_latest_ensembl_release() {
    log_info "Detecting latest Ensembl release..." >&2

    local releases rel fallback

    # Lista limpa e única de releases
    releases=$(curl -fs https://ftp.ensembl.org/pub/ \
        | grep -oE 'release-[0-9]+' \
        | sed 's/release-//' \
        | sort -n \
        | uniq)

    if [[ -z "$releases" ]]; then
        log_error "Failed to retrieve Ensembl releases list" >&2
        return 1
    fi

    rel=$(echo "$releases" | tail -n 1)

    # Tenta regressivamente até achar um release válido
    for fallback in $(echo "$releases" | tac); do
        if curl -fsI "https://ftp.ensembl.org/pub/release-${fallback}/fasta/${species_dir}/" >/dev/null; then
            if [[ "$fallback" != "$rel" ]]; then
                log_warn "Release $rel incomplete, falling back to $fallback" >&2
            fi
            echo "$fallback"
            return 0
        fi
    done

    log_error "No valid Ensembl release found" >&2
    return 1
}

download_ensembl_fasta() {
    local species_input="$1"
    local fasta_type="$2"
    local output_dir="$3"

    mkdir -p "$output_dir"

    local species_dir
    species_dir=$(echo "$species_input" | tr '[:upper:]' '[:lower:]')

    local release
    if [[ -n "${ENSEMBL_RELEASE:-}" ]]; then
        release="$ENSEMBL_RELEASE"
    else
        release=$(get_latest_ensembl_release "$species_dir" | tr -d '\r\n[:space:]') || return 1
    fi

    local species_prefix
    species_prefix=$(echo "$species_dir" | awk -F_ 'BEGIN{OFS="_"}{
        $1 = toupper(substr($1,1,1)) tolower(substr($1,2))
        for(i=2;i<=NF;i++){
            $i = tolower($i)
        }
        print
    }')

    case "$fasta_type" in
        cdna|cds|dna|ncrna|pep) ;;
        *)
            log_error "Invalid Ensembl FASTA type: $fasta_type"
            log_info "Valid types: cdna, cds, dna, ncrna, pep"
            return 1
            ;;
    esac

    local base_url="https://ftp.ensembl.org/pub/release-${release}/fasta/${species_dir}/${fasta_type}"

    log_info "Querying Ensembl FTP for ${species_prefix} (${fasta_type})..."
    log_info "Using Ensembl release: $release"
    log_info "URL: $base_url/"

    local file_name
    file_name=$(curl -fs "$base_url/" \
        | grep -oE "${species_prefix}\.[^.]+\.${fasta_type}\.all\.fa\.gz" \
        | head -n 1)

    if [[ -z "$file_name" ]]; then
        log_warn "Primary pattern failed, trying fallback pattern..."
        file_name=$(curl -fs "$base_url/" \
            | grep -oE "[^\" ]+\.${fasta_type}\.all\.fa\.gz" \
            | head -n 1)
    fi

    if [[ -z "$file_name" ]]; then
        log_error "Could not find ${fasta_type} FASTA for ${species_input}"
        log_info "Checked: $base_url/"
        return 1
    fi

    local url="${base_url}/${file_name}"
    local out_file="${output_dir}/${file_name}"

    log_info "Downloading: $file_name"
    log_info "Final URL: $url"

    if [[ -f "$out_file" ]]; then
        log_info "File already exists, skipping download: $out_file"
        return 0
    fi

    retry_command curl -L -o "$out_file" "$url" || return 1

    log_info "✓ Downloaded ${fasta_type} FASTA"
    return 0
}

# ==============================================================================
# TRANSCRIPTOME DOWNLOAD
# ==============================================================================

download_transcriptome() {
    local accession=${1:-}
    local species=${2:-}
    local source=${3:-ncbi}
    local fasta_type="${4:-cdna}"

    log_step "Downloading transcriptome"

    case "$source" in
        ncbi)
            [[ -z "$accession" ]] && {
                log_error "NCBI source requires --assembly"
                return 1
            }

            check_command datasets || return 1

            local output_dir="${OUTPUT_DIR}/transcriptomes/${accession}"
            mkdir -p "$output_dir"
            local zip_file="${output_dir}/${accession}_transcriptome.zip"

            log_info "Using NCBI datasets for $accession..."

            if retry_command datasets download genome accession "$accession" \
                --include rna,gff3,gbff,gtf,seq-report \
                --filename "$zip_file"; then

                unzip -q "$zip_file" -d "$output_dir" || return 1
                log_info "✓ Transcriptome downloaded from NCBI"
                return 0
            fi

            log_error "NCBI transcriptome unavailable for $accession"
            return 1
            ;;

        ensembl)
            [[ -z "$species" ]] && {
                log_error "Ensembl source requires --species"
                return 1
            }

            fasta_type="${ENSEMBL_TYPE:-$fasta_type}"

            log_info "Using Ensembl database for $species"
            log_info "FASTA type: $fasta_type"

            local output_dir="${OUTPUT_DIR}/transcriptomes/${species}/${fasta_type}"
            mkdir -p "$output_dir"

            download_ensembl_fasta "$species" "$fasta_type" "$output_dir"
            return $?
            ;;

        auto)
            [[ -n "$accession" ]] && \
                download_transcriptome "$accession" "$species" "ncbi" "$fasta_type" && return 0

            [[ -n "$species" ]] && \
                download_transcriptome "$accession" "$species" "ensembl" "$fasta_type" && return 0

            log_error "Auto mode failed"
            return 1
            ;;

        *)
            log_error "Unknown source: $source"
            return 1
            ;;
    esac
}

# ==============================================================================
# PROTEOME DOWNLOAD
# ==============================================================================

download_proteome() {
    local accession=${1:-}
    local species=${2:-}
    local source=${3:-ncbi}
    local fasta_type="${4:-pep}"

    log_step "Downloading proteome"

    case "$source" in
        ncbi)
            [[ -z "$accession" ]] && {
                log_error "NCBI source requires --assembly"
                return 1
            }

            check_command datasets || return 1

            local output_dir="${OUTPUT_DIR}/proteomes/${accession}"
            mkdir -p "$output_dir"
            local zip_file="${output_dir}/${accession}_proteome.zip"

            log_info "Using NCBI datasets for $accession..."

            if retry_command datasets download genome accession "$accession" \
                --include protein,cds,seq-report \
                --filename "$zip_file"; then

                unzip -q "$zip_file" -d "$output_dir" || return 1
                log_info "✓ Proteome downloaded from NCBI"
                return 0
            fi

            log_error "NCBI proteome unavailable for $accession"
            return 1
            ;;

        ensembl)
            [[ -z "$species" ]] && {
                log_error "Ensembl source requires --species"
                return 1
            }

            fasta_type="${ENSEMBL_TYPE:-$fasta_type}"

            log_info "Using Ensembl database for $species"
            log_info "FASTA type: $fasta_type"

            local output_dir="${OUTPUT_DIR}/proteomes/${species}/${fasta_type}"
            mkdir -p "$output_dir"

            download_ensembl_fasta "$species" "$fasta_type" "$output_dir"
            return $?
            ;;

        auto)
            [[ -n "$accession" ]] && \
                download_proteome "$accession" "$species" "ncbi" "$fasta_type" && return 0

            [[ -n "$species" ]] && \
                download_proteome "$accession" "$species" "ensembl" "$fasta_type" && return 0

            log_error "Auto mode failed"
            return 1
            ;;

        *)
            log_error "Unknown source: $source"
            return 1
            ;;
    esac
}

# ==============================================================================
# BATCH DOWNLOADS FROM LIST
# ==============================================================================

download_genomes_from_list() {
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

    local total=$(grep -cv '^#\|^$' "$accession_list" || echo 0)
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

# ==============================================================================
# GEO SUPPLEMENTARY FILES
# ==============================================================================

download_geo_supplementary() {
    log_step "Downloading GEO Supplementary Files"
    
    local geo_accession=$1
    
    if ! validate_accession "$geo_accession"; then
        return 1
    fi
    
    log_info "Downloading supplementary files for $geo_accession..."
    
    local series_stub=$(echo "$geo_accession" | sed 's/\(GSE[0-9]*\)[0-9]\{3\}$/\1nnn/')
    local ftp_base="https://ftp.ncbi.nlm.nih.gov/geo/series/${series_stub}/${geo_accession}/suppl/"
    
    log_info "FTP location: $ftp_base"
    
    mkdir -p "${OUTPUT_DIR}/metadata/${geo_accession}"
    
    if ! wget -q -O "${TEMP_DIR}/file_list.html" "$ftp_base"; then
        log_error "Could not access GEO FTP site"
        return 1
    fi
    
    local file_count=0
    while IFS= read -r filename; do
        [[ -z "$filename" ]] && continue
        
        log_info "  Downloading: $filename"
        if retry_command wget -c -q --show-progress \
            -P "${OUTPUT_DIR}/metadata/${geo_accession}" \
            "${ftp_base}${filename}"; then
            ((file_count++))
        else
            log_warn "  Failed: $filename"
        fi
    done < <(grep -o 'href="[^"]*"' "${TEMP_DIR}/file_list.html" | \
        sed 's/href="//;s/"$//' | \
        grep -v '^\.\.' | \
        grep -v '^/')
    
    log_info "✓ Downloaded $file_count file(s)"
    log_info "Files saved to: ${OUTPUT_DIR}/metadata/${geo_accession}/"
    return 0
}

# ==============================================================================
# GEO TO SRR CONVERSION
# ==============================================================================

create_srr_list_from_geo() {
    log_step "Creating SRR list from GEO accession"
    
    local geo_accession=$1
    local output_file="${2:-SRR_list.txt}"
    
    if ! check_command ffq; then
        log_error "ffq not found. Install with: pip install ffq"
        return 1
    fi
    
    if ! validate_accession "$geo_accession"; then
        return 1
    fi
    
    log_info "Fetching SRA information for $geo_accession using ffq..."
    
    local temp_output="${TEMP_DIR}/${geo_accession}_ffq_raw.txt"
    local temp_srr="${TEMP_DIR}/temp_srr.txt"
    
    if ! ffq --ftp "$geo_accession" > "$temp_output" 2>&1; then
        log_error "Failed to fetch data for $geo_accession"
        cat "$temp_output"
        return 1
    fi
    
    log_info "Extracting SRR accessions..."
    
    grep -oP 'Parsing run \K(SRR|ERR|DRR)\d+' "$temp_output" | sort -u > "$temp_srr" 2>/dev/null || true
    
    if [[ ! -s "$temp_srr" ]]; then
        log_debug "Trying alternative extraction..."
        grep -oE '(SRR|ERR|DRR)[0-9]+' "$temp_output" | sort -u > "$temp_srr"
    fi
    
    if [[ ! -s "$temp_srr" ]]; then
        log_error "No SRR accessions found for $geo_accession"
        log_info "This GEO entry might not have sequencing data in SRA"
        return 1
    fi
    
    cp "$temp_srr" "$output_file"
    
    local count=$(wc -l < "$output_file")
    log_info "✓ Found $count SRR accession(s)"
    log_info "Saved to: $output_file"
    
    if [[ $count -gt 0 ]]; then
        log_info "Preview (first 5):"
        head -n 5 "$output_file" | while read -r srr; do
            echo "  - $srr"
        done
        [[ $count -gt 5 ]] && echo "  ... and $((count - 5)) more"
    fi
    
    # Save full log
    local log_output="${output_file%.txt}_ffq_log.txt"
    cp "$temp_output" "$log_output"
    log_debug "Full ffq output saved to: $log_output"
    
    return 0
}

# ==============================================================================
# ENVIRONMENT CHECK
# ==============================================================================

check_environment() {
    log_step "Checking environment"
    
    local deps=(fasterq-dump prefetch parallel-fastq-dump wget curl jq ffq datasets unzip gzip)
    local available=0
    local missing=0
    
    for cmd in "${deps[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            log_info "✓ $cmd"
            ((available++))
        else
            log_warn "✗ $cmd not found"
            ((missing++))
        fi
    done
    
    log_info ""
    log_info "Summary: $available available, $missing missing"
    
    if [[ $missing -gt 0 ]]; then
        log_info ""
        log_info "Installation suggestions:"
        log_info "  SRA tools: conda install -c bioconda sra-tools"
        log_info "  parallel-fastq-dump: pip install parallel-fastq-dump"
        log_info "  ffq: pip install ffq"
        log_info "  NCBI datasets: conda install -c conda-forge ncbi-datasets-cli"
        log_info "  jq: conda install -c conda-forge jq"
    fi
    
    return 0
}

# ==============================================================================
# HELP
# ==============================================================================

supports_color() {
    if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null) -ge 8 ]]; then
        return 0
    fi
    return 1
}

# Initialize color variables
if supports_color; then
    HELP_BOLD='\033[1m'
    HELP_DIM='\033[2m'
    HELP_CYAN='\033[0;36m'
    HELP_GREEN='\033[0;32m'
    HELP_YELLOW='\033[1;33m'
    HELP_BLUE='\033[0;34m'
    HELP_NC='\033[0m'
else
    HELP_BOLD=''
    HELP_DIM=''
    HELP_CYAN=''
    HELP_GREEN=''
    HELP_YELLOW=''
    HELP_BLUE=''
    HELP_NC=''
fi

HELP_BOLD=''
HELP_DIM=''
HELP_CYAN=''
HELP_GREEN=''
HELP_YELLOW=''
HELP_BLUE=''
HELP_NC=''

show_help() {
cat << EOF

${HELP_BOLD}seqfetcher${HELP_NC} v${VERSION} — Unified sequencing data fetcher
${HELP_DIM}Download genomic data from NCBI, ENA, and Ensembl${HELP_NC}

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher <command> <subcommand> [options]

${HELP_BOLD}COMMANDS${HELP_NC}
  ${HELP_CYAN}discover${HELP_NC}
    assembly                Search for genome assemblies in NCBI
  
  ${HELP_CYAN}download${HELP_NC}
    genome                  Download complete genome assemblies
    transcriptome           Download transcriptome sequences (cDNA/RNA)
    proteome                Download protein sequences
    fastq                   Download RNA-seq FASTQ files
  
  ${HELP_CYAN}convert${HELP_NC}
    geo-to-srr              Convert GEO accession to SRR list
  
  ${HELP_CYAN}check${HELP_NC}                     Check environment & dependencies

${HELP_BOLD}GLOBAL OPTIONS${HELP_NC}
  --outdir DIR              Output directory (default: downloads)
  --threads N               Number of parallel threads (default: 8)
  --max-retries N           Maximum retry attempts (default: 3)
  --dry-run                 Show what would be done without executing
  --verbose                 Enable detailed logging
  --help, -h                Show this help message
  --version, -v             Show version information

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}DETAILED COMMAND REFERENCE${HELP_NC}

${HELP_BOLD}1. DISCOVER ASSEMBLIES${HELP_NC}
   Find available genome assemblies for a species in NCBI

   ${HELP_GREEN}seqfetcher discover assembly${HELP_NC} [options]

   ${HELP_BOLD}Options:${HELP_NC}
     --organism "SPECIES"    Species name (required)
                             Example: "Homo sapiens", "Mus musculus"
     --filter FILTER         Assembly quality filter:
                             ${HELP_DIM}all${HELP_NC}              - All available assemblies
                             ${HELP_DIM}reference${HELP_NC}        - Reference genomes only (recommended)
                             ${HELP_DIM}representative${HELP_NC}   - RefSeq representative genomes
     --out FILE              Output file for accession list
                             (default: assembly_accessions.txt)

   ${HELP_BOLD}Examples:${HELP_NC}
     # Find all mouse reference genomes
     seqfetcher discover assembly --organism "Mus musculus" --filter reference

     # Search for zebrafish assemblies and save to custom file
     seqfetcher discover assembly \\
       --organism "Danio rerio" \\
       --filter all \\
       --out zebrafish_assemblies.txt

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}2. DOWNLOAD GENOME${HELP_NC}
   Download genome assemblies and annotations from NCBI

   ${HELP_GREEN}seqfetcher download genome${HELP_NC} [options]

   ${HELP_BOLD}Options:${HELP_NC}
     --assembly ACCESSION    Single assembly accession (GCF_* or GCA_*)
     --accessions FILE       Batch download from file (one accession per line)
     --organism "SPECIES"    Search and download interactively by species name
     --filter FILTER         Used with --organism (see discover assembly)
     --include TYPES         Comma-separated data types to download:
                             ${HELP_DIM}genome${HELP_NC}   - Genomic FASTA sequences
                             ${HELP_DIM}cdna${HELP_NC}     - cDNA sequences (transcripts)
                             ${HELP_DIM}rna${HELP_NC}      - RNA sequences
                             ${HELP_DIM}pep${HELP_NC}      - Protein sequences
                             ${HELP_DIM}gff${HELP_NC}      - Gene annotations (GFF3 format)
                             ${HELP_DIM}gtf${HELP_NC}      - Gene annotations (GTF format)
                             ${HELP_DIM}cds${HELP_NC}      - Coding sequences
                             (default: genome)

   ${HELP_BOLD}Examples:${HELP_NC}
     # Download complete human reference genome with all annotations
     seqfetcher download genome \\
       --assembly GCF_000001405.40 \\
       --include genome,gff,gtf,pep

     # Interactive download - search and choose
     seqfetcher download genome \\
       --organism "Arabidopsis thaliana" \\
       --filter reference \\
       --include genome,cdna

     # Batch download multiple assemblies
     seqfetcher download genome \\
       --accessions assembly_list.txt \\
       --include genome,gff

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}3. DOWNLOAD TRANSCRIPTOME${HELP_NC}
   Download transcriptome sequences from NCBI or Ensembl

   ${HELP_GREEN}seqfetcher download transcriptome${HELP_NC} [options]

   ${HELP_BOLD}Options:${HELP_NC}
     --source SOURCE         Data source (required):
                             ${HELP_DIM}ncbi${HELP_NC}     - NCBI datasets (requires --assembly)
                             ${HELP_DIM}ensembl${HELP_NC}  - Ensembl database (requires --species)
                             ${HELP_DIM}auto${HELP_NC}     - Try NCBI first, fallback to Ensembl
     --assembly ACCESSION    NCBI assembly accession (for NCBI source)
     --species NAME          Ensembl species name (for Ensembl source)
                             Format: genus_species (lowercase, underscore)
                             Examples: homo_sapiens, mus_musculus, danio_rerio
     --ensembl-type TYPE     Ensembl FASTA type (optional):
                             ${HELP_DIM}cdna${HELP_NC}  - cDNA sequences (default)
                             ${HELP_DIM}cds${HELP_NC}   - Coding sequences only
                             ${HELP_DIM}ncrna${HELP_NC} - Non-coding RNA sequences
     --ensembl-release N     Specific Ensembl release number (default: latest)

   ${HELP_BOLD}Examples:${HELP_NC}
     # Download from NCBI using assembly accession
     seqfetcher download transcriptome \\
       --assembly GCF_000001635.27 \\
       --source ncbi

     # Download from Ensembl (no assembly needed!)
     seqfetcher download transcriptome \\
       --species mus_musculus \\
       --source ensembl \\
       --ensembl-type cdna

     # Auto mode: try both sources
     seqfetcher download transcriptome \\
       --assembly GCF_000001405.40 \\
       --species homo_sapiens \\
       --source auto

     # Download specific Ensembl release
     seqfetcher download transcriptome \\
       --species danio_rerio \\
       --source ensembl \\
       --ensembl-release 110

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}4. DOWNLOAD PROTEOME${HELP_NC}
   Download protein sequences from NCBI or Ensembl

   ${HELP_GREEN}seqfetcher download proteome${HELP_NC} [options]

   ${HELP_BOLD}Options:${HELP_NC}
     Same as transcriptome (see above)
     --ensembl-type for proteome: ${HELP_DIM}pep${HELP_NC} (protein sequences)

   ${HELP_BOLD}Examples:${HELP_NC}
     # Download from NCBI
     seqfetcher download proteome \\
       --assembly GCF_000001635.27 \\
       --source ncbi

     # Download from Ensembl
     seqfetcher download proteome \\
       --species mus_musculus \\
       --source ensembl

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}5. DOWNLOAD FASTQ${HELP_NC}
   Download RNA-seq FASTQ files from SRA or ENA

   ${HELP_GREEN}seqfetcher download fastq${HELP_NC} [options]

   ${HELP_BOLD}Options:${HELP_NC}
     --accessions FILE       File with SRA accessions (required)
                             One accession per line (SRR*, ERR*, DRR*)
                             Lines starting with # are ignored
     --source SOURCE         Download source:
                             ${HELP_DIM}ena${HELP_NC}    - European Nucleotide Archive (recommended, faster)
                             ${HELP_DIM}sra${HELP_NC}    - NCBI Sequence Read Archive
     --method METHOD         SRA download method (used with --source sra):
                             ${HELP_DIM}fasterq${HELP_NC}  - fasterq-dump (default)
                             ${HELP_DIM}prefetch${HELP_NC} - prefetch + fasterq-dump (more robust)
                             ${HELP_DIM}parallel${HELP_NC} - parallel-fastq-dump (fastest)

   ${HELP_BOLD}Examples:${HELP_NC}
     # Download from ENA (recommended - fastest with checksums)
     seqfetcher download fastq \\
       --accessions SRR_list.txt \\
       --source ena

     # Download from SRA using fasterq-dump
     seqfetcher download fastq \\
       --accessions SRR_list.txt \\
       --source sra \\
       --method fasterq

     # Use parallel method for faster downloads
     seqfetcher download fastq \\
       --accessions SRR_list.txt \\
       --source sra \\
       --method parallel

   ${HELP_BOLD}Note:${HELP_NC} ENA is recommended as it's typically faster and includes MD5 checksums

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}6. CONVERT GEO TO SRR${HELP_NC}
   Convert GEO accession to SRR accession list

   ${HELP_GREEN}seqfetcher convert geo-to-srr${HELP_NC} [options]

   ${HELP_BOLD}Options:${HELP_NC}
     --geo ACCESSION         GEO accession (required)
                             Examples: GSE280953, GSM*, SRP*
     --out FILE              Output file for SRR list
                             (default: SRR_list.txt)

   ${HELP_BOLD}Examples:${HELP_NC}
     # Convert GEO series to SRR list
     seqfetcher convert geo-to-srr \\
       --geo GSE280953 \\
       --out my_samples.txt

     # Then download the FASTQ files
     seqfetcher download fastq \\
       --accessions my_samples.txt \\
       --source ena

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}7. CHECK ENVIRONMENT${HELP_NC}
   Verify installed dependencies

   ${HELP_GREEN}seqfetcher check${HELP_NC}

   ${HELP_BOLD}Checks for:${HELP_NC}
     • SRA Tools (fasterq-dump, prefetch)
     • parallel-fastq-dump
     • NCBI datasets CLI
     • ffq (for GEO conversion)
     • Standard utilities (wget, curl, jq, gzip)

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}COMMON WORKFLOWS${HELP_NC}

${HELP_YELLOW}Workflow 1: Download complete reference genome with annotations${HELP_NC}
  1. Search for assemblies:
     seqfetcher discover assembly --organism "Homo sapiens" --filter reference

  2. Download genome with all data:
     seqfetcher download genome \\
       --assembly GCF_000001405.40 \\
       --include genome,gff,gtf,cdna,pep

${HELP_YELLOW}Workflow 2: Download RNA-seq data from GEO study${HELP_NC}
  1. Convert GEO to SRR list:
     seqfetcher convert geo-to-srr --geo GSE280953 --out samples.txt

  2. Download FASTQ files:
     seqfetcher download fastq --accessions samples.txt --source ena

${HELP_YELLOW}Workflow 3: Get mouse transcriptome from Ensembl${HELP_NC}
  seqfetcher download transcriptome \\
    --species mus_musculus \\
    --source ensembl \\
    --ensembl-type cdna

${HELP_YELLOW}Workflow 4: Batch download multiple genomes${HELP_NC}
  1. Create accession list (accessions.txt):
     GCF_000001635.27
     GCF_000001405.40
     GCF_000146045.2

  2. Download all:
     seqfetcher download genome \\
       --accessions accessions.txt \\
       --include genome,gff

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}FILE FORMATS${HELP_NC}

${HELP_BOLD}Accession List Format:${HELP_NC}
  # Lines starting with # are comments
  # One accession per line
  SRR123456
  SRR123457
  # Empty lines are ignored
  
  SRR123458

${HELP_BOLD}Output Directory Structure:${HELP_NC}
  downloads/
  ├── fastq/              # FASTQ files
  ├── genomes/            # Genome assemblies
  │   └── GCF_*/          # One directory per assembly
  ├── transcriptomes/     # Transcriptome sequences
  ├── proteomes/          # Protein sequences
  ├── metadata/           # GEO and other metadata
  ├── .completed          # Download tracking file
  └── seqfetcher.log     # Detailed log file

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}FEATURES${HELP_NC}
  ✓ Automatic retry with exponential backoff
  ✓ Resume interrupted downloads
  ✓ MD5 checksum verification (ENA downloads)
  ✓ Progress tracking for batch operations
  ✓ Detailed logging to file
  ✓ Dry-run mode for testing commands
  ✓ Multiple data sources (NCBI, ENA, Ensembl)
  ✓ Parallel download support

${HELP_BOLD}INSTALLATION REQUIREMENTS${HELP_NC}

${HELP_BOLD}Essential (for basic functionality):${HELP_NC}
  • wget or curl
  • gzip
  • unzip

${HELP_BOLD}For SRA downloads:${HELP_NC}
  conda install -c bioconda sra-tools
  pip install parallel-fastq-dump

${HELP_BOLD}For NCBI genome downloads:${HELP_NC}
  conda install -c conda-forge ncbi-datasets-cli

${HELP_BOLD}For GEO conversion:${HELP_NC}
  pip install ffq

${HELP_BOLD}For enhanced functionality:${HELP_NC}
  conda install -c conda-forge jq tree

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}TROUBLESHOOTING${HELP_NC}

${HELP_YELLOW}Problem: Download fails with network error${HELP_NC}
  Solution: Increase retries: --max-retries 5

${HELP_YELLOW}Problem: "No space left on device"${HELP_NC}
  Solution: Change output directory: --outdir /path/to/larger/drive

${HELP_YELLOW}Problem: ENA download fails for specific accession${HELP_NC}
  Solution: Try SRA source: --source sra --method prefetch

${HELP_YELLOW}Problem: Cannot find Ensembl species${HELP_NC}
  Solution: Use exact format (lowercase, underscore):
  • "Homo sapiens" → homo_sapiens
  • "Mus musculus" → mus_musculus

${HELP_YELLOW}Problem: Download seems stuck${HELP_NC}
  Solution: Enable verbose mode to see details: --verbose

${HELP_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${HELP_NC}

${HELP_BOLD}SUPPORT & DOCUMENTATION${HELP_NC}
  GitHub: https://github.com/yourusername/seqfetcher
  Issues: https://github.com/yourusername/seqfetcher/issues
  
${HELP_BOLD}ACCESSION FORMATS${HELP_NC}
  GCF_* / GCA_*  - NCBI genome assemblies
  SRR* / ERR* / DRR*  - SRA run accessions
  GSE* / GSM* - GEO series/sample accessions
  SRP* / ERP* / DRP*  - SRA project accessions

${HELP_DIM}Run 'seqfetcher check' to verify your environment is properly configured${HELP_NC}

EOF
}

show_quick_help() {
cat << EOF
${HELP_BOLD}seqfetcher${HELP_NC} v${VERSION} — Quick Reference

${HELP_BOLD}Common Commands:${HELP_NC}
  seqfetcher discover assembly --organism "Species" --filter reference
  seqfetcher download genome --assembly GCF_* --include genome,gff
  seqfetcher download transcriptome --species species_name --source ensembl
  seqfetcher download fastq --accessions list.txt --source ena
  seqfetcher convert geo-to-srr --geo GSE* --out samples.txt

${HELP_BOLD}Get detailed help:${HELP_NC}
  seqfetcher --help

${HELP_BOLD}Check your environment:${HELP_NC}
  seqfetcher check

EOF
}

# Show help for specific subcommand
show_subcommand_help() {
    local subcommand=$1
    
    case "$subcommand" in
        "discover:assembly")
            cat << EOF
${HELP_BOLD}seqfetcher discover assembly${HELP_NC}

Search for genome assemblies in NCBI database

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher discover assembly --organism "SPECIES" [options]

${HELP_BOLD}REQUIRED${HELP_NC}
  --organism "NAME"    Species name (scientific name recommended)

${HELP_BOLD}OPTIONS${HELP_NC}
  --filter FILTER      all | reference | representative (default: all)
  --out FILE          Output file path (default: assembly_accessions.txt)

${HELP_BOLD}EXAMPLES${HELP_NC}
  seqfetcher discover assembly --organism "Mus musculus" --filter reference
  seqfetcher discover assembly --organism "Zebrafish" --out zebra.txt

${HELP_BOLD}OUTPUT${HELP_NC}
  Creates two files:
  • assembly_accessions.txt - List of accession IDs
  • assembly_accessions_summary.tsv - Detailed table with metadata

EOF
            ;;
        "download:genome")
            cat << EOF
${HELP_BOLD}seqfetcher download genome${HELP_NC}

Download genome assemblies and annotations from NCBI

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher download genome [mode] [options]

${HELP_BOLD}MODES (choose one)${HELP_NC}
  --assembly ACC       Download specific assembly
  --accessions FILE    Batch download from file
  --organism "NAME"    Interactive search and download

${HELP_BOLD}OPTIONS${HELP_NC}
  --include TYPES      Data types: genome,cdna,rna,pep,gff,gtf,cds
  --filter FILTER      For --organism: reference|representative|all

${HELP_BOLD}EXAMPLES${HELP_NC}
  seqfetcher download genome --assembly GCF_000001405.40
  seqfetcher download genome --assembly GCF_* --include genome,gff,pep
  seqfetcher download genome --organism "Human" --filter reference

EOF
            ;;
        "download:transcriptome")
            cat << EOF
${HELP_BOLD}seqfetcher download transcriptome${HELP_NC}

Download transcriptome sequences from NCBI or Ensembl

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher download transcriptome --source SOURCE [options]

${HELP_BOLD}SOURCES${HELP_NC}
  ncbi      Requires: --assembly GCF_*
  ensembl   Requires: --species genus_species
  auto      Try NCBI first, fallback to Ensembl

${HELP_BOLD}OPTIONS${HELP_NC}
  --assembly ACC          NCBI assembly accession
  --species NAME          Ensembl species (format: genus_species)
  --ensembl-type TYPE     cdna | cds | ncrna (default: cdna)
  --ensembl-release N     Specific release number

${HELP_BOLD}EXAMPLES${HELP_NC}
  seqfetcher download transcriptome --source ncbi --assembly GCF_*
  seqfetcher download transcriptome --source ensembl --species mus_musculus
  seqfetcher download transcriptome --source auto --assembly GCF_* --species homo_sapiens

EOF
            ;;
        "download:fastq")
            cat << EOF
${HELP_BOLD}seqfetcher download fastq${HELP_NC}

Download RNA-seq FASTQ files from SRA or ENA

${HELP_BOLD}USAGE${HELP_NC}
  seqfetcher download fastq --accessions FILE [options]

${HELP_BOLD}REQUIRED${HELP_NC}
  --accessions FILE    File with SRR/ERR/DRR accessions (one per line)

${HELP_BOLD}OPTIONS${HELP_NC}
  --source SOURCE      ena | sra (default: ena)
  --method METHOD      For SRA: fasterq | prefetch | parallel

${HELP_BOLD}EXAMPLES${HELP_NC}
  seqfetcher download fastq --accessions list.txt --source ena
  seqfetcher download fastq --accessions list.txt --source sra --method parallel

${HELP_BOLD}RECOMMENDATION${HELP_NC}
  Use --source ena for faster downloads with checksum verification

EOF
            ;;
        *)
            show_help
            ;;
    esac
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

# -------------------------------
# Helper Functions
# -------------------------------

# Validate required parameters
require_param() {
    local param_name=$1
    local param_value=$2
    
    if [[ -z "$param_value" ]]; then
        log_error "Missing required parameter: --${param_name}"
        log_info "Run 'seqfetcher ${COMMAND} ${SUBCOMMAND} --help' for usage information"
        exit 1
    fi
}

# Validate mutually exclusive parameters
check_exclusive_params() {
    local -n params=$1
    local count=0
    local set_params=()
    
    for param in "${params[@]}"; do
        if [[ -n "${!param}" ]]; then
            ((count++))
            set_params+=("--${param,,}")  # Convert to lowercase for display
        fi
    done
    
    if [[ $count -gt 1 ]]; then
        log_error "Conflicting parameters: ${set_params[*]}"
        log_info "Please use only ONE of: ${params[*]}"
        exit 1
    elif [[ $count -eq 0 ]]; then
        log_error "Missing required parameter"
        log_info "Please provide ONE of: ${params[*]}"
        exit 1
    fi
}

# Show contextual help based on command/subcommand
show_contextual_help() {
    local cmd=$1
    local subcmd=$2
    
    if [[ -n "$subcmd" ]]; then
        show_subcommand_help "${cmd}:${subcmd}"
    else
        show_help
    fi
}

# -------------------------------
# Main Argument Parser
# -------------------------------

# Show help if no arguments
if [[ $# -eq 0 ]]; then
    show_quick_help
    exit 0
fi

# Extract command and subcommand
COMMAND=$1
SUBCOMMAND=${2:-}

# Handle special cases before shifting
case "$COMMAND" in
    --help|-h|help)
        show_help
        exit 0
        ;;
    --version|-v|version)
        echo "seqfetcher v$VERSION"
        exit 0
        ;;
    check)
        check_environment
        exit $?
        ;;
esac

# Validate command structure
if [[ -z "$SUBCOMMAND" && "$COMMAND" != "check" ]]; then
    log_error "Missing subcommand for: $COMMAND"
    show_help
    exit 1
fi

# Shift past command and subcommand
shift $(( $# > 1 ? 2 : 1 ))

# Initialize global variables
ENSEMBL_TYPE=""
ENSEMBL_RELEASE=""

# -------------------------------
# Parse Global Flags (before subcommand-specific args)
# -------------------------------
GLOBAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --outdir)
            if [[ -n "${2:-}" ]]; then
                OUTPUT_DIR="$2"
                shift 2
            else
                log_error "--outdir requires a value"
                exit 1
            fi
            ;;
        --threads)
            if [[ -n "${2:-}" ]]; then
                if [[ "$2" =~ ^[0-9]+$ ]]; then
                    THREADS="$2"
                    shift 2
                else
                    log_error "Invalid thread count: $2 (must be a number)"
                    exit 1
                fi
            else
                log_error "--threads requires a value"
                exit 1
            fi
            ;;
        --max-retries)
            if [[ -n "${2:-}" ]]; then
                if [[ "$2" =~ ^[0-9]+$ ]]; then
                    MAX_RETRIES="$2"
                    shift 2
                else
                    log_error "Invalid retry count: $2 (must be a number)"
                    exit 1
                fi
            else
                log_error "--max-retries requires a value"
                exit 1
            fi
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --ensembl-type)
            if [[ -n "${2:-}" ]]; then
                ENSEMBL_TYPE="$2"
                shift 2
            else
                log_error "--ensembl-type requires a value"
                exit 1
            fi
            ;;
        --ensembl-release)
            if [[ -n "${2:-}" ]]; then
                if [[ "$2" =~ ^[0-9]+$ ]]; then
                    ENSEMBL_RELEASE="$2"
                    shift 2
                else
                    log_error "Invalid Ensembl release: $2 (must be a number)"
                    exit 1
                fi
            else
                log_error "--ensembl-release requires a value"
                exit 1
            fi
            ;;
        --help|-h)
            show_contextual_help "$COMMAND" "$SUBCOMMAND"
            exit 0
            ;;
        *)
            # Save non-global args for subcommand processing
            GLOBAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore non-global arguments for subcommand parsing
set -- "${GLOBAL_ARGS[@]}"

# Create output directories (except for help/version/check commands)
create_dirs

# ==============================================================================
# COMMAND DISPATCHER - IMPROVED VERSION
# ==============================================================================

case "$COMMAND:$SUBCOMMAND" in

# ==============================================================================
# DISCOVER ASSEMBLY
# ==============================================================================
discover:assembly)
    ORGANISM=""
    FILTER="all"
    OUTPUT=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --organism)
                # Check if there's a value after the flag
                if [[ -n "${2:-}" ]]; then
                    ORGANISM="$2"
                    shift 2
                else
                    log_error "--organism requires a value"
                    exit 1
                fi
                ;;
            --filter)
                if [[ -n "${2:-}" ]]; then
                    case "$2" in
                        all|reference|representative)
                            FILTER="$2"
                            ;;
                        *)
                            log_error "Invalid filter: $2"
                            log_info "Valid filters: all, reference, representative"
                            exit 1
                            ;;
                    esac
                    shift 2
                else
                    log_error "--filter requires a value"
                    exit 1
                fi
                ;;
            --out|--output)
                if [[ -n "${2:-}" ]]; then
                    OUTPUT="$2"
                    shift 2
                else
                    log_error "--out requires a value"
                    exit 1
                fi
                ;;
            --help|-h)
                show_subcommand_help "discover:assembly"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_subcommand_help "discover:assembly"
                exit 1
                ;;
        esac
    done

    # Validation
    require_param "organism" "$ORGANISM"
    OUTPUT="${OUTPUT:-${OUTPUT_DIR}/assembly_accessions.txt}"

    # Execute
    search_ncbi_assemblies "$ORGANISM" "$OUTPUT" "$FILTER"
    ;;

# ==============================================================================
# DOWNLOAD FASTQ
# ==============================================================================
download:fastq)
    ACCESSIONS=""
    SOURCE="ena"
    METHOD="fasterq"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --accessions)
                if [[ -n "${2:-}" ]]; then
                    ACCESSIONS="$2"
                    if [[ ! -f "$ACCESSIONS" ]]; then
                        log_error "Accession file not found: $ACCESSIONS"
                        exit 1
                    fi
                    shift 2
                else
                    log_error "--accessions requires a value"
                    exit 1
                fi
                ;;
            --source)
                if [[ -n "${2:-}" ]]; then
                    case "$2" in
                        ena|sra)
                            SOURCE="$2"
                            ;;
                        *)
                            log_error "Invalid source: $2"
                            log_info "Valid sources: ena, sra"
                            exit 1
                            ;;
                    esac
                    shift 2
                else
                    log_error "--source requires a value"
                    exit 1
                fi
                ;;
            --method)
                if [[ -n "${2:-}" ]]; then
                    case "$2" in
                        fasterq|prefetch|parallel)
                            METHOD="$2"
                            ;;
                        *)
                            log_error "Invalid method: $2"
                            log_info "Valid methods: fasterq, prefetch, parallel"
                            exit 1
                            ;;
                    esac
                    shift 2
                else
                    log_error "--method requires a value"
                    exit 1
                fi
                ;;
            --help|-h)
                show_subcommand_help "download:fastq"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_subcommand_help "download:fastq"
                exit 1
                ;;
        esac
    done

    # Validation
    require_param "accessions" "$ACCESSIONS"

    # Execute
    case "$SOURCE:$METHOD" in
        ena:*)
            download_ena "$ACCESSIONS"
            ;;
        sra:fasterq)
            download_sra_fasterq "$ACCESSIONS"
            ;;
        sra:prefetch)
            download_sra_prefetch "$ACCESSIONS"
            ;;
        sra:parallel)
            download_parallel_fastq "$ACCESSIONS"
            ;;
        *)
            log_error "Invalid source ($SOURCE) or method ($METHOD)"
            exit 1
            ;;
    esac
    ;;

# ==============================================================================
# DOWNLOAD GENOME
# ==============================================================================
download:genome)
    ASSEMBLY=""
    ACCESSIONS=""
    ORGANISM=""
    INCLUDE="genome"
    FILTER="reference"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --assembly)
                if [[ -n "${2:-}" ]]; then
                    ASSEMBLY="$2"
                    shift 2
                else
                    log_error "--assembly requires a value"
                    exit 1
                fi
                ;;
            --accessions)
                if [[ -n "${2:-}" ]]; then
                    ACCESSIONS="$2"
                    if [[ ! -f "$ACCESSIONS" ]]; then
                        log_error "Accession file not found: $ACCESSIONS"
                        exit 1
                    fi
                    shift 2
                else
                    log_error "--accessions requires a value"
                    exit 1
                fi
                ;;
            --organism)
                if [[ -n "${2:-}" ]]; then
                    ORGANISM="$2"
                    shift 2
                else
                    log_error "--organism requires a value"
                    exit 1
                fi
                ;;
            --include)
                if [[ -n "${2:-}" ]]; then
                    INCLUDE="$2"
                    # Validate include types
                    IFS=',' read -ra TYPES <<< "$INCLUDE"
                    for type in "${TYPES[@]}"; do
                        case "$type" in
                            genome|cdna|rna|pep|protein|gff|gff3|gtf|cds) ;;
                            *)
                                log_warn "Unknown include type: $type"
                                log_info "Valid types: genome, cdna, rna, pep, gff, gtf, cds"
                                ;;
                        esac
                    done
                    shift 2
                else
                    log_error "--include requires a value"
                    exit 1
                fi
                ;;
            --filter)
                if [[ -n "${2:-}" ]]; then
                    case "$2" in
                        all|reference|representative)
                            FILTER="$2"
                            ;;
                        *)
                            log_error "Invalid filter: $2"
                            log_info "Valid filters: all, reference, representative"
                            exit 1
                            ;;
                    esac
                    shift 2
                else
                    log_error "--filter requires a value"
                    exit 1
                fi
                ;;
            --help|-h)
                show_subcommand_help "download:genome"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_subcommand_help "download:genome"
                exit 1
                ;;
        esac
    done

    # Validation - ensure only one mode is specified
    declare -a MODES=(ORGANISM ASSEMBLY ACCESSIONS)
    mode_count=0
    for mode in "${MODES[@]}"; do
        [[ -n "${!mode}" ]] && ((mode_count++))
    done

    if [[ $mode_count -eq 0 ]]; then
        log_error "No input specified"
        log_info "Provide ONE of: --organism, --assembly, or --accessions"
        exit 1
    elif [[ $mode_count -gt 1 ]]; then
        log_error "Multiple input modes specified"
        log_info "Provide only ONE of: --organism, --assembly, or --accessions"
        exit 1
    fi

    if [[ -n "$ORGANISM" ]]; then
        search_and_download_assembly "$ORGANISM" "$FILTER" "$INCLUDE"
    elif [[ -n "$ASSEMBLY" ]]; then
        download_ncbi_datasets "$ASSEMBLY" genome "$INCLUDE"
    elif [[ -n "$ACCESSIONS" ]]; then
        download_genomes_from_list "$ACCESSIONS" "$INCLUDE"
    fi
    ;;

# ==============================================================================
# DOWNLOAD TRANSCRIPTOME
# ==============================================================================
download:transcriptome)
    ASSEMBLY=""
    ACCESSIONS=""
    SPECIES=""
    SOURCE="ncbi"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --assembly)
                if [[ -n "${2:-}" ]]; then
                    ASSEMBLY="$2"
                    shift 2
                else
                    log_error "--assembly requires a value"
                    exit 1
                fi
                ;;
            --accessions)
                if [[ -n "${2:-}" ]]; then
                    ACCESSIONS="$2"
                    if [[ ! -f "$ACCESSIONS" ]]; then
                        log_error "Accession file not found: $ACCESSIONS"
                        exit 1
                    fi
                    shift 2
                else
                    log_error "--accessions requires a value"
                    exit 1
                fi
                ;;
            --species)
                if [[ -n "${2:-}" ]]; then
                    SPECIES="$2"
                    # Validate Ensembl species format (lowercase with underscores)
                    if [[ "$SOURCE" == "ensembl" ]] && [[ ! "$SPECIES" =~ ^[a-z_]+$ ]]; then
                        log_warn "Ensembl species should be lowercase with underscores (e.g., homo_sapiens)"
                    fi
                    shift 2
                else
                    log_error "--species requires a value"
                    exit 1
                fi
                ;;
            --source)
                if [[ -n "${2:-}" ]]; then
                    case "$2" in
                        ncbi|ensembl|auto)
                            SOURCE="$2"
                            ;;
                        *)
                            log_error "Invalid source: $2"
                            log_info "Valid sources: ncbi, ensembl, auto"
                            exit 1
                            ;;
                    esac
                    shift 2
                else
                    log_error "--source requires a value"
                    exit 1
                fi
                ;;
            --help|-h)
                show_subcommand_help "download:transcriptome"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_subcommand_help "download:transcriptome"
                exit 1
                ;;
        esac
    done

    # Validation based on source
    case "$SOURCE" in
        ncbi)
            if [[ -z "$ASSEMBLY" && -z "$ACCESSIONS" ]]; then
                log_error "NCBI source requires --assembly or --accessions"
                exit 1
            fi
            ;;
        ensembl)
            require_param "species" "$SPECIES"
            ;;
        auto)
            if [[ -z "$ASSEMBLY" && -z "$SPECIES" && -z "$ACCESSIONS" ]]; then
                log_error "Auto mode requires --assembly and/or --species"
                exit 1
            fi
            ;;
    esac

    # Execute
    if [[ -n "$ASSEMBLY" ]]; then
        download_transcriptome "$ASSEMBLY" "$SPECIES" "$SOURCE" "$ENSEMBL_TYPE"
    elif [[ -n "$ACCESSIONS" ]]; then
         total=$(grep -cv '^#\|^$' "$ACCESSIONS" || echo 0)
         current=0
        
        while IFS= read -r acc; do
            [[ -z "$acc" || "$acc" =~ ^# ]] && continue
            ((current++))
            log_info "Processing $current/$total: $acc"
            download_transcriptome "$acc" "$SPECIES" "$SOURCE" "$ENSEMBL_TYPE"
        done < "$ACCESSIONS"
    elif [[ -n "$SPECIES" ]]; then
        download_transcriptome "" "$SPECIES" "$SOURCE" "$ENSEMBL_TYPE"
    else
        log_error "Invalid parameter combination"
        log_info "NCBI:    --assembly or --accessions"
        log_info "Ensembl: --species --source ensembl [--ensembl-type cdna|cds|ncrna]"
        log_info "Auto:    --assembly --species --source auto"
        exit 1
    fi
    ;;

# ==============================================================================
# DOWNLOAD PROTEOME
# ==============================================================================
download:proteome)
    ASSEMBLY=""
    ACCESSIONS=""
    SPECIES=""
    SOURCE="ncbi"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --assembly)
                if [[ -n "${2:-}" ]]; then
                    ASSEMBLY="$2"
                    shift 2
                else
                    log_error "--assembly requires a value"
                    exit 1
                fi
                ;;
            --accessions)
                if [[ -n "${2:-}" ]]; then
                    ACCESSIONS="$2"
                    if [[ ! -f "$ACCESSIONS" ]]; then
                        log_error "Accession file not found: $ACCESSIONS"
                        exit 1
                    fi
                    shift 2
                else
                    log_error "--accessions requires a value"
                    exit 1
                fi
                ;;
            --species)
                if [[ -n "${2:-}" ]]; then
                    SPECIES="$2"
                    # Validate Ensembl species format
                    if [[ "$SOURCE" == "ensembl" ]] && [[ ! "$SPECIES" =~ ^[a-z_]+$ ]]; then
                        log_warn "Ensembl species should be lowercase with underscores (e.g., homo_sapiens)"
                    fi
                    shift 2
                else
                    log_error "--species requires a value"
                    exit 1
                fi
                ;;
            --source)
                if [[ -n "${2:-}" ]]; then
                    case "$2" in
                        ncbi|ensembl|auto)
                            SOURCE="$2"
                            ;;
                        *)
                            log_error "Invalid source: $2"
                            log_info "Valid sources: ncbi, ensembl, auto"
                            exit 1
                            ;;
                    esac
                    shift 2
                else
                    log_error "--source requires a value"
                    exit 1
                fi
                ;;
            --help|-h)
                show_subcommand_help "download:proteome"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_subcommand_help "download:proteome"
                exit 1
                ;;
        esac
    done

    # Validation based on source
    case "$SOURCE" in
        ncbi)
            if [[ -z "$ASSEMBLY" && -z "$ACCESSIONS" ]]; then
                log_error "NCBI source requires --assembly or --accessions"
                exit 1
            fi
            ;;
        ensembl)
            require_param "species" "$SPECIES"
            ;;
        auto)
            if [[ -z "$ASSEMBLY" && -z "$SPECIES" && -z "$ACCESSIONS" ]]; then
                log_error "Auto mode requires --assembly and/or --species"
                exit 1
            fi
            ;;
    esac

    # Execute
    if [[ -n "$ASSEMBLY" ]]; then
        download_proteome "$ASSEMBLY" "$SPECIES" "$SOURCE" "$ENSEMBL_TYPE"
    elif [[ -n "$ACCESSIONS" ]]; then
         total=$(grep -cv '^#\|^$' "$ACCESSIONS" || echo 0)
         current=0
        
        while IFS= read -r acc; do
            [[ -z "$acc" || "$acc" =~ ^# ]] && continue
            ((current++))
            log_info "Processing $current/$total: $acc"
            download_proteome "$acc" "$SPECIES" "$SOURCE" "$ENSEMBL_TYPE"
        done < "$ACCESSIONS"
    elif [[ -n "$SPECIES" ]]; then
        download_proteome "" "$SPECIES" "$SOURCE" "$ENSEMBL_TYPE"
    else
        log_error "Invalid parameter combination"
        log_info "NCBI:    --assembly or --accessions"
        log_info "Ensembl: --species --source ensembl [--ensembl-type pep]"
        log_info "Auto:    --assembly --species --source auto"
        exit 1
    fi
    ;;

# ==============================================================================
# CONVERT GEO TO SRR
# ==============================================================================
convert:geo-to-srr)
    GEO=""
    OUT="SRR_list.txt"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --geo)
                if [[ -n "${2:-}" ]]; then
                    GEO="$2"
                    # Basic validation of GEO format
                    if [[ ! "$GEO" =~ ^(GSE|GSM|SRP|ERP|DRP)[0-9]+ ]]; then
                        log_warn "GEO accession format may be invalid: $GEO"
                        log_info "Expected format: GSE*, GSM*, SRP*, ERP*, or DRP* followed by numbers"
                    fi
                    shift 2
                else
                    log_error "--geo requires a value"
                    exit 1
                fi
                ;;
            --out|--output)
                if [[ -n "${2:-}" ]]; then
                    OUT="$2"
                    # Validate output directory exists
                     out_dir=$(dirname "$OUT")
                    if [[ ! -d "$out_dir" ]]; then
                        log_error "Output directory does not exist: $out_dir"
                        exit 1
                    fi
                    shift 2
                else
                    log_error "--out requires a value"
                    exit 1
                fi
                ;;
            --help|-h)
                show_subcommand_help "convert:geo-to-srr"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_subcommand_help "convert:geo-to-srr"
                exit 1
                ;;
        esac
    done

    # Validation
    require_param "geo" "$GEO"

    # Execute
    create_srr_list_from_geo "$GEO" "$OUT"
    ;;

# ==============================================================================
# UNKNOWN COMMAND
# ==============================================================================
*)
    log_error "Unknown command: $COMMAND ${SUBCOMMAND:-}"
    echo ""
    log_info "Available commands:"
    log_info "  discover assembly"
    log_info "  download genome|transcriptome|proteome|fastq"
    log_info "  convert geo-to-srr"
    log_info "  check"
    echo ""
    log_info "Run 'seqfetcher --help' for detailed usage information"
    exit 1
    ;;
esac

# Exit with the status of the last command
exit $?