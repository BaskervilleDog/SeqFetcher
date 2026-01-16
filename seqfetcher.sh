#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# seqfetcher — Unified sequencing data fetcher (IMPROVED)
# ============================================================

VERSION="1.1.0"

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

# Cleanup on exit
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        log_debug "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Retry mechanism for network operations
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
            delay=$((delay * 2))  # Exponential backoff
        else
            log_error "All $max_attempts attempts failed"
            return 1
        fi
    done
}

# Execute command with dry-run support
run_command() {
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

# Validate accession format
validate_accession() {
    local acc=$1
    case "$acc" in
        GCF_*|GCA_*) return 0 ;;
        SRR*|ERR*|DRR*) return 0 ;;
        GSE*|GSM*|SRP*|ERP*|DRP*) return 0 ;;
        *) 
            log_error "Invalid accession format: $acc"
            log_info "Valid formats: GCF_*, GCA_*, SRR*, ERR*, DRR*, GSE*, GSM*"
            return 1
            ;;
    esac
}

# Track completed downloads
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

# Progress tracking
show_progress() {
    local current=$1
    local total=$2
    local accession=$3
    log_info "[$current/$total] Processing: $accession"
}

# Capitalize species name for Ensembl (mus_musculus → Mus_musculus)
capitalize_species() {
    local species=$1
    echo "$species" | awk -F_ '{
        result = ""
        for(i=1; i<=NF; i++) {
            result = result toupper(substr($i,1,1)) tolower(substr($i,2))
            if(i < NF) result = result "_"
        }
        print result
    }'
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
            gzip "${OUTPUT_DIR}/fastq/${accession}"*.fastq 2>/dev/null || true
            
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
        
        # Download metadata
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
        
        # Check if metadata was retrieved
        if [[ ! -s "${TEMP_DIR}/${accession}_ena.txt" ]]; then
            log_error "No metadata returned for $accession"
            ((fail_count++))
            failed_accessions+=("$accession")
            continue
        fi
        
        # Check if there are any FTP URLs (more than just header)
        local line_count=$(wc -l < "${TEMP_DIR}/${accession}_ena.txt")
        if [[ $line_count -lt 2 ]]; then
            log_error "No data in ENA for $accession"
            ((fail_count++))
            failed_accessions+=("$accession")
            continue
        fi
        
        # FIX: Use process substitution to avoid subshell
        local has_files=false
        local download_failed=false
        
        while IFS=$'\t' read -r run_acc ftp_urls md5_sums file_sizes; do
            
            # Check if FTP URLs are empty
            if [[ -z "$ftp_urls" || "$ftp_urls" == "null" ]]; then
                log_error "No FASTQ files available at ENA for $run_acc"
                log_info "This accession may only be available through SRA"
                download_failed=true
                continue
            fi
            
            has_files=true
            log_info "Downloading FASTQ files for $run_acc..."
            
            # Split multiple FTP URLs (semicolon-separated)
            IFS=';' read -ra FTP_ARRAY <<< "$ftp_urls"
            IFS=';' read -ra MD5_ARRAY <<< "$md5_sums"
            IFS=';' read -ra SIZE_ARRAY <<< "$file_sizes"
            
            for i in "${!FTP_ARRAY[@]}"; do
                ftp_url="${FTP_ARRAY[$i]}"
                expected_md5="${MD5_ARRAY[$i]}"
                expected_size="${SIZE_ARRAY[$i]}"
                
                # Add ftp:// prefix if missing
                [[ ! "$ftp_url" =~ ^ftp:// ]] && ftp_url="ftp://$ftp_url"
                
                filename=$(basename "$ftp_url")
                output_file="${OUTPUT_DIR}/fastq/${filename}"
                
                # Format size for display
                local size_display="Unknown"
                if [[ -n "$expected_size" && "$expected_size" != "null" ]]; then
                    size_display=$(numfmt --to=iec-i --suffix=B "$expected_size" 2>/dev/null || echo "${expected_size}B")
                fi
                
                log_info "  Downloading: $filename (Size: $size_display)"
                
                # Download with retry
                if retry_command wget -c -q --show-progress -O "$output_file" "$ftp_url"; then
                    log_info "  ✓ Downloaded: $filename"
                    
                    # Verify MD5 checksum
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
                    
                    # Verify file size
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
        
        # Check results
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
    
    # Summary
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
# METHOD 5: NCBI DATASETS (IMPROVED VALIDATION)
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
    
    # Create output directory named after the accession
    local output_dir="${OUTPUT_DIR}/genomes/${accession}"
    mkdir -p "$output_dir"
    
    case $download_type in
        genome)
            log_info "Downloading genome assembly..."
            
            local zip_file="${output_dir}/${accession}_genome.zip"
            
            # Build include arguments with validation
            local include_args=()
            local valid_includes=()
            
            IFS=',' read -ra ITEMS <<< "$include"
            for item in "${ITEMS[@]}"; do
                item=$(echo "$item" | tr -d ' ')  # Trim whitespace
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
# TRANSCRIPTOME DOWNLOAD (IMPROVED WITH ENSEMBL FALLBACK)
# ==============================================================================

download_transcriptome() {
    local accession=$1
    local species=${2:-}
    local fallback=${3:-}

    log_step "Downloading transcriptome for $accession"

    if check_command datasets; then
        local output_dir="${OUTPUT_DIR}/transcriptomes/${accession}"
        mkdir -p "$output_dir"
        local zip_file="${output_dir}/${accession}_transcriptome.zip"

        log_info "Trying NCBI datasets..."
        if retry_command datasets download genome accession "$accession" \
            --include rna,gtf,seq-report \
            --filename "$zip_file"; then

            if unzip -q "$zip_file" -d "$output_dir"; then
                log_info "✓ Transcriptome downloaded from NCBI"
                return 0
            fi
        fi
    fi

    if [[ "$fallback" == "ensembl" && -n "$species" ]]; then
        log_warn "NCBI transcriptome unavailable, trying Ensembl..."
        download_ensembl_transcriptome "$species" "${OUTPUT_DIR}/transcriptomes/${accession}"
        return $?
    fi

    log_error "Transcriptome unavailable for $accession"
    [[ -z "$fallback" ]] && log_info "Tip: Use --fallback ensembl --species <name> to try Ensembl"
    return 1
}

# ==============================================================================
# ENSEMBL TRANSCRIPTOME (IMPROVED SPECIES HANDLING)
# ==============================================================================

download_ensembl_transcriptome() {
    local species=$1
    local output_dir=$2

    mkdir -p "$output_dir"

    # Capitalize species name (mus_musculus → Mus_musculus)
    local species_cap=$(capitalize_species "$species")
    local fasta="${species_cap}.cdna.all.fa.gz"
    local url="${ENSEMBL_BASE}/${species}/cdna/${fasta}"

    log_step "Downloading Ensembl transcriptome: $species"
    log_info "URL: $url"

    if retry_command curl -fL "$url" -o "${output_dir}/${fasta}"; then
        log_info "Decompressing..."
        gunzip -f "${output_dir}/${fasta}"
        log_info "✓ Ensembl transcriptome downloaded"
        return 0
    else
        log_error "Ensembl transcriptome not found for $species"
        log_info "Check species name at: https://www.ensembl.org"
        return 1
    fi
}

# ==============================================================================
# PROTEOME DOWNLOAD
# ==============================================================================

download_proteome() {
    local accession=$1
    local species=${2:-}
    local fallback=${3:-}

    log_step "Downloading proteome for $accession"

    if check_command datasets; then
        local output_dir="${OUTPUT_DIR}/proteomes/${accession}"
        mkdir -p "$output_dir"
        local zip_file="${output_dir}/${accession}_proteome.zip"

        log_info "Trying NCBI datasets..."
        if retry_command datasets download genome accession "$accession" \
            --include protein,seq-report \
            --filename "$zip_file"; then

            if unzip -q "$zip_file" -d "$output_dir"; then
                log_info "✓ Proteome downloaded from NCBI"
                return 0
            fi
        fi
    fi

    if [[ "$fallback" == "ensembl" && -n "$species" ]]; then
        log_warn "NCBI proteome unavailable, trying Ensembl..."
        download_ensembl_proteome "$species" "${OUTPUT_DIR}/proteomes/${accession}"
        return $?
    fi

    log_error "Proteome unavailable for $accession"
    [[ -z "$fallback" ]] && log_info "Tip: Use --fallback ensembl --species <name> to try Ensembl"
    return 1
}

# ==============================================================================
# ENSEMBL PROTEOME
# ==============================================================================

download_ensembl_proteome() {
    local species=$1
    local output_dir=$2

    mkdir -p "$output_dir"

    local species_cap=$(capitalize_species "$species")
    local fasta="${species_cap}.pep.all.fa.gz"
    local url="${ENSEMBL_BASE}/${species}/pep/${fasta}"

    log_step "Downloading Ensembl proteome: $species"
    log_info "URL: $url"

    if retry_command curl -fL "$url" -o "${output_dir}/${fasta}"; then
        log_info "Decompressing..."
        gunzip -f "${output_dir}/${fasta}"
        log_info "✓ Ensembl proteome downloaded"
        return 0
    else
        log_error "Ensembl proteome not found for $species"
        log_info "Check species name at: https://www.ensembl.org"
        return 1
    fi
}

# ==============================================================================
# BATCH DOWNLOADS FROM LIST
# ==============================================================================

download_genomes_from_list() {
    local accession_list=$1
    local include=${2:-genome}

    [[ ! -f "$accession_list" ]] && {
        log_error "Accession list not found: $accession_list"
        return 1
    }

    local total=$(grep -cv '^#\|^$' "$accession_list" || echo 0)
    local current=0
    local success=0
    local failed=0

    log_info "Processing $total genome(s) from list"

    while IFS= read -r accession; do
        [[ -z "$accession" || "$accession" =~ ^# ]] && continue

        ((current++))
        show_progress "$current" "$total" "$accession"

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
    
    # Try multiple extraction patterns
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

show_help() {
cat << 'EOF'
seqfetcher v1.1.0 — unified sequencing data fetcher

USAGE:
  seqfetcher <command> <subcommand> [options]

COMMANDS:
  discover assembly           Search genome assemblies (NCBI)
  download fastq              Download RNA-seq FASTQ files
  download genome             Download genome assemblies
  download transcriptome      Download transcriptome FASTA
  download proteome           Download proteome FASTA
  convert geo-to-srr          Convert GEO accession → SRR list
  check                       Check environment & dependencies

GLOBAL OPTIONS:
  --outdir DIR                Output directory (default: downloads)
  --threads N                 Number of threads (default: 8)
  --dry-run                   Print actions without downloading
  --verbose                   Verbose logging
  --max-retries N             Max retry attempts (default: 3)

FASTQ OPTIONS:
  --accessions FILE           File with SRR/ERR/DRR accessions
  --source ena|sra            Download source (default: ena)
  --method METHOD             SRA method: fasterq|prefetch|parallel

GENOME OPTIONS:
  --assembly ACCESSION        Single assembly accession
  --accessions FILE           Multiple assemblies from file
  --organism "Species name"   Search and download by organism
  --include ITEMS             Data types (comma-separated):
                              genome,cdna,rna,pep,gff,gtf,cds
  --filter FILTER             Assembly filter: all|reference|representative

TRANSCRIPTOME/PROTEOME OPTIONS:
  --assembly ACCESSION        NCBI assembly accession
  --accessions FILE           Multiple from file
  --species name              Ensembl species (e.g., mus_musculus)
  --fallback ensembl          Use Ensembl if NCBI unavailable

EXAMPLES:
  # Search for mouse assemblies
  seqfetcher discover assembly --organism "Mus musculus" --filter reference

  # Download FASTQ from ENA
  seqfetcher download fastq --accessions SRR_list.txt --source ena

  # Download genome with specific data types
  seqfetcher download genome \
    --assembly GCF_000001635.27 \
    --include genome,gff,pep

  # Search and download genome interactively
  seqfetcher download genome \
    --organism "Homo sapiens" \
    --filter reference \
    --include genome,cdna,pep

  # Download transcriptome with Ensembl fallback
  seqfetcher download transcriptome \
    --assembly GCF_000001635.27 \
    --species mus_musculus \
    --fallback ensembl

  # Convert GEO to SRR list
  seqfetcher convert geo-to-srr --geo GSE280953 --out my_samples.txt

  # Check installed dependencies
  seqfetcher check

FEATURES:
  • Automatic retry with exponential backoff
  • Resume interrupted downloads
  • MD5 checksum verification
  • Progress tracking for batch operations
  • Detailed logging to file
  • Dry-run mode for testing

For more information: https://github.com/yourusername/seqfetcher

EOF
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

[[ $# -lt 1 ]] && { show_help; exit 0; }

COMMAND=$1
SUBCOMMAND=${2:-}
shift $(( $# > 1 ? 2 : 1 ))

# Parse global flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --outdir) OUTPUT_DIR="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --max-retries) MAX_RETRIES="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        --help|-h) show_help; exit 0 ;;
        --version) echo "seqfetcher v$VERSION"; exit 0 ;;
        *) break ;;
    esac
done

case "$COMMAND" in
    help|--help|-h|--version|-v|check) ;;
    *) create_dirs ;;
esac

# ==============================================================================
# COMMAND DISPATCHER
# ==============================================================================

case "$COMMAND:$SUBCOMMAND" in

discover:assembly)
    ORGANISM=""
    FILTER="all"
    OUTPUT=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --organism)
                shift
                ORGANISM=""
                while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                    ORGANISM+="$1 "
                    shift
                done
                ORGANISM="${ORGANISM% }"
                ;;
            --filter)
                FILTER="$2"
                shift 2
                ;;
            --out|--output)
                OUTPUT="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$ORGANISM" ]]; then
        log_error "--organism is required"
        exit 1
    fi

    # Default output file
    OUTPUT="${OUTPUT:-${OUTPUT_DIR}/assembly_accessions.txt}"

    search_ncbi_assemblies "$ORGANISM" "$OUTPUT" "$FILTER"
    ;;

download:fastq)
    ACCESSIONS=""
    SOURCE="ena"
    METHOD="fasterq"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --accessions) ACCESSIONS="$2"; shift 2 ;;
            --source) SOURCE="$2"; shift 2 ;;
            --method) METHOD="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -z "$ACCESSIONS" ]] && { log_error "--accessions FILE required"; exit 1; }

    case "$SOURCE:$METHOD" in
        ena:*) download_ena "$ACCESSIONS" ;;
        sra:fasterq) download_sra_fasterq "$ACCESSIONS" ;;
        sra:prefetch) download_sra_prefetch "$ACCESSIONS" ;;
        sra:parallel) download_parallel_fastq "$ACCESSIONS" ;;
        *) log_error "Invalid source ($SOURCE) or method ($METHOD)"; exit 1 ;;
    esac
    ;;

download:genome)
    ASSEMBLY=""
    ACCESSIONS=""
    ORGANISM=""
    INCLUDE="genome"
    FILTER="reference"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --assembly) ASSEMBLY="$2"; shift 2 ;;
            --accessions) ACCESSIONS="$2"; shift 2 ;;
            --organism) ORGANISM="$2"; shift 2 ;;
            --include) INCLUDE="$2"; shift 2 ;;
            --filter) FILTER="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -n "$ORGANISM" ]]; then
        search_and_download_assembly "$ORGANISM" "$FILTER" "$INCLUDE"
    elif [[ -n "$ASSEMBLY" ]]; then
        download_ncbi_datasets "$ASSEMBLY" genome "$INCLUDE"
    elif [[ -n "$ACCESSIONS" ]]; then
        download_genomes_from_list "$ACCESSIONS" "$INCLUDE"
    else
        log_error "Use --organism, --assembly, or --accessions"
        exit 1
    fi
    ;;

download:transcriptome)
    ASSEMBLY=""
    ACCESSIONS=""
    SPECIES=""
    FALLBACK=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --assembly) ASSEMBLY="$2"; shift 2 ;;
            --accessions) ACCESSIONS="$2"; shift 2 ;;
            --species) SPECIES="$2"; shift 2 ;;
            --fallback) FALLBACK="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -n "$ASSEMBLY" ]]; then
        download_transcriptome "$ASSEMBLY" "$SPECIES" "$FALLBACK"
    elif [[ -n "$ACCESSIONS" ]]; then
        while IFS= read -r acc; do
            [[ -z "$acc" || "$acc" =~ ^# ]] && continue
            download_transcriptome "$acc" "$SPECIES" "$FALLBACK"
        done < "$ACCESSIONS"
    else
        log_error "Use --assembly or --accessions"
        exit 1
    fi
    ;;

download:proteome)
    ASSEMBLY=""
    ACCESSIONS=""
    SPECIES=""
    FALLBACK=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --assembly) ASSEMBLY="$2"; shift 2 ;;
            --accessions) ACCESSIONS="$2"; shift 2 ;;
            --species) SPECIES="$2"; shift 2 ;;
            --fallback) FALLBACK="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -n "$ASSEMBLY" ]]; then
        download_proteome "$ASSEMBLY" "$SPECIES" "$FALLBACK"
    elif [[ -n "$ACCESSIONS" ]]; then
        while IFS= read -r acc; do
            [[ -z "$acc" || "$acc" =~ ^# ]] && continue
            download_proteome "$acc" "$SPECIES" "$FALLBACK"
        done < "$ACCESSIONS"
    else
        log_error "Use --assembly or --accessions"
        exit 1
    fi
    ;;

convert:geo-to-srr)
    GEO=""
    OUT="SRR_list.txt"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --geo) GEO="$2"; shift 2 ;;
            --out) OUT="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -z "$GEO" ]] && { log_error "--geo ACCESSION required"; exit 1; }
    create_srr_list_from_geo "$GEO" "$OUT"
    ;;

check:*)
    check_environment
    ;;

help:*|--help|-h)
    show_help
    ;;

--version|-v)
    echo "seqfetcher v$VERSION"
    ;;

*)
    log_error "Unknown command: $COMMAND $SUBCOMMAND"
    log_info "Run 'seqfetcher help' for usage"
    exit 1
    ;;
esac

log_step "DONE"
exit 0
        