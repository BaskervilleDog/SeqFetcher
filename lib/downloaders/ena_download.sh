#!/usr/bin/env bash

# ==============================================================================
# Parallelized ENA Download Module
# ==============================================================================
# This module provides parallel download capability for ENA (European Nucleotide Archive)
#
# REQUIREMENTS FOR PARALLEL EXECUTION:
# The following must be exported in the main script or sourced before calling:
#   - Functions: log_info, log_error, log_warning
#   - Variables: OUTPUT_DIR, TEMP_DIR, PARALLEL_JOBS
#
# Example in main script:
#   export -f log_info log_error log_warning
#   export -f downloaders_ena_download::download_ena_worker downloaders_ena_download::download_ena downloaders_sra_download::validate_sra_accession
#   export OUTPUT_DIR TEMP_DIR PARALLEL_JOBS
# ==============================================================================

# --------------------------------------------------
# Validation function (standalone version)
# Use this if downloaders_sra_download::validate_sra_accession is not available
# --------------------------------------------------
if ! command -v downloaders_sra_download::validate_sra_accession &>/dev/null; then
    downloaders_sra_download::validate_sra_accession() {
        local accession="$1"
        
        # Check if empty
        if [[ -z "$accession" ]]; then
            return 1
        fi
        
        # Valid SRA accession patterns:
        # SRR/ERR/DRR followed by numbers (runs)
        # SRX/ERX/DRX followed by numbers (experiments)
        # SRS/ERS/DRS followed by numbers (samples)
        # SRP/ERP/DRP followed by numbers (projects)
        if [[ "$accession" =~ ^(SRR|ERR|DRR|SRX|ERX|DRX|SRS|ERS|DRS|SRP|ERP|DRP)[0-9]+$ ]]; then
            return 0
        fi
        
        return 1
    }
fi

# --------------------------------------------------
# Worker function for downloading a single accession
# --------------------------------------------------
downloaders_ena_download::download_ena_worker() {
    local accession="$1"
    local output_dir="${2:-${OUTPUT_DIR:-downloads}}"
    local temp_dir="${3:-${TEMP_DIR:-temp_downloads}}"
    
    # Validate accession format
    if ! downloaders_sra_download::validate_sra_accession "$accession"; then
        log_error "[$accession] Invalid accession format"
        return 1
    fi

    log_info "[$accession] Fetching ENA metadata..."

    local ena_url
    ena_url="https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${accession}&result=read_run&fields=run_accession,fastq_ftp,fastq_md5,fastq_bytes"

    local meta_file="${temp_dir}/${accession}_ena.txt"

    # Fetch metadata
    if command -v wget &> /dev/null; then
        wget -q -O "$meta_file" "$ena_url" 2>/dev/null || {
            log_error "[$accession] Failed to fetch metadata"
            return 1
        }
    else
        curl -s -o "$meta_file" "$ena_url" || {
            log_error "[$accession] Failed to fetch metadata"
            return 1
        }
    fi

    # Validate metadata
    if [[ ! -s "$meta_file" ]]; then
        log_error "[$accession] No metadata returned"
        return 1
    fi

    local line_count
    line_count=$(wc -l < "$meta_file")

    if [[ "$line_count" -lt 2 ]]; then
        log_error "[$accession] No ENA FASTQ data available"
        return 1
    fi

    local has_files=false
    local download_failed=false

    # Parse ENA table (skip header)
    while IFS=$'\t' read -r run_acc ftp_urls md5_sums file_sizes; do

        if [[ -z "$ftp_urls" || "$ftp_urls" == "null" ]]; then
            log_error "[$accession] No FASTQ files available at ENA"
            log_info  "[$accession] Try SRA download methods"
            download_failed=true
            continue
        fi

        has_files=true
        log_info "[$accession] Downloading FASTQ files for $run_acc..."

        IFS=';' read -ra FTP_ARRAY  <<< "$ftp_urls"
        IFS=';' read -ra MD5_ARRAY  <<< "$md5_sums"
        IFS=';' read -ra SIZE_ARRAY <<< "$file_sizes"

        for i in "${!FTP_ARRAY[@]}"; do

            local ftp_url filename output_file expected_md5 expected_size
            local actual_md5 actual_size size_display

            ftp_url="${FTP_ARRAY[$i]}"
            expected_md5="${MD5_ARRAY[$i]}"
            expected_size="${SIZE_ARRAY[$i]}"

            [[ ! "$ftp_url" =~ ^ftp:// ]] && ftp_url="ftp://$ftp_url"

            filename=$(basename "$ftp_url")
            output_file="${output_dir}/fastq/${filename}"

            local md5_arg=""
            [[ -n "$expected_md5" && "$expected_md5" != "null" ]] && md5_arg="$expected_md5"
            local size_arg=""
            [[ -n "$expected_size" && "$expected_size" != "null" ]] && size_arg="$expected_size"
            local key="${run_acc}:${filename}"

            # Skip-by-default: verified copy already on disk.
            if downloaders_common::already_have "$output_file" "$md5_arg" "$size_arg"; then
                log_info "[$accession] ✓ already present: $filename"
                manifest::record_run_only "$key" "$(jq -n --arg p "$output_file" \
                    '{type:"fastq", source:"ena", status:"skipped", files:[{path:$p}]}')"
                has_files=true
                continue
            fi

            size_display="Unknown"
            [[ -n "$size_arg" ]] && size_display=$(numfmt --to=iec-i --suffix=B "$size_arg" 2>/dev/null || echo "${size_arg}B")
            log_info "[$accession] Downloading: $filename (Size: $size_display)"

            if downloaders_common::atomic_fetch "$ftp_url" "$output_file" "$md5_arg"; then
                log_info "[$accession] ✓ downloaded + verified: $filename"
                manifest::record "$key" "$(jq -n \
                    --arg p "$output_file" --arg u "$ftp_url" \
                    --arg md5 "${LAST_FETCH_MD5:-}" --argjson bytes "${LAST_FETCH_BYTES:-0}" \
                    '{type:"fastq", source:"ena", source_url:$u, status:"downloaded",
                      files:[{path:$p, bytes:$bytes, md5:$md5}]}')"
            else
                log_error "[$accession] ✗ failed to download $filename"
                manifest::record "$key" "$(jq -n --arg p "$output_file" \
                    '{type:"fastq", source:"ena", status:"failed", files:[{path:$p}]}')"
                download_failed=true
            fi
        done

    done < <(tail -n +2 "$meta_file")

    # Final status
    if [[ "$has_files" == true && "$download_failed" == false ]]; then
        log_info "[$accession] ✓ Completed successfully"
        return 0
    else
        log_error "[$accession] ✗ Failed"
        return 1
    fi
}

# --------------------------------------------------
# Main parallelized ENA download function
# --------------------------------------------------
downloaders_ena_download::download_ena() {

    # Help / usage
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<EOF
Usage:
  seqfetcher download --sra-method ena --sra-accession-file <file> [OPTIONS]

Description:
  Download FASTQ files from the European Nucleotide Archive (ENA)
  using a list of accessions (SRR / ERR / DRR / PRJ / GSE, etc).
  Downloads run in parallel for faster processing.

Options:
  --sra-accession-file <file>   File containing accessions (one per line)
  --jobs, -j <N>                Number of parallel downloads (default: 4)
  --outdir <dir>                Output directory (default: downloads)
  -h, --help                    Show this help message

Notes:
  - Requires: wget or curl, md5sum, numfmt
  - Downloads are saved to: \$OUTPUT_DIR/fastq
  - Already downloaded files are skipped automatically
  - MD5 and file size are verified when available
  - Parallel execution requires GNU parallel (optional but recommended)

Examples:
  # Download with default settings (4 parallel jobs)
  seqfetcher download --sra-method ena --sra-accession-file runs.txt

  # Download with 8 parallel jobs
  seqfetcher download --sra-method ena --sra-accession-file runs.txt --jobs 8

  # Download to custom directory
  seqfetcher download --sra-method ena --sra-accession-file runs.txt --outdir my_data

EOF
        return 0
    fi

    # Argument parsing
    local accession_list="$1"
    local parallel_jobs="${PARALLEL_JOBS:-4}"
    local output_dir="${OUTPUT_DIR:-downloads}"
    local temp_dir="${TEMP_DIR:-temp_downloads}"

    if [[ -z "$accession_list" ]]; then
        log_error "Missing accession list file"
        log_info "Run: seqfetcher download --sra-method ena --help"
        return 1
    fi

    # Dependency checks
    log_step "METHOD 4: Using ENA (European Nucleotide Archive) - Parallel Mode"

    if [[ ! -f "$accession_list" ]]; then
        log_error "Accession list file not found: $accession_list"
        return 1
    fi

    mkdir -p "$output_dir/fastq" "$temp_dir"

    # Count total accessions
    local total
    total=$(grep -cv '^#\|^$' "$accession_list" || echo 0)

    log_info "Total accessions to process: $total"
    log_info "Parallel jobs: $parallel_jobs"
    log_info "Output directory: $output_dir/fastq"
    log_info ""

    # Export necessary variables for parallel execution
    export OUTPUT_DIR="$output_dir"
    export TEMP_DIR="$temp_dir"
    export -f downloaders_ena_download::download_ena_worker downloaders_sra_download::validate_sra_accession
    export -f log_info log_error log_warning log_success 2>/dev/null || true
    export -f downloaders_common::already_have downloaders_common::atomic_fetch \
              downloaders_common::md5 downloaders_common::_bytes \
              manifest::record manifest::record_run_only manifest::_record_locked \
              manifest::_with_lock manifest::get manifest::stored_md5 manifest::is_done 2>/dev/null || true

    # Check if GNU parallel is available
    if command -v parallel &> /dev/null; then
        log_info "Using GNU parallel for downloads..."
        
        # Use GNU parallel with proper environment passing
        grep -v '^#\|^$' "$accession_list" | \
            parallel --jobs "$parallel_jobs" \
                     --line-buffer \
                     --keep-order \
                     --env OUTPUT_DIR \
                     --env TEMP_DIR \
                     --env LOCKFILE \
                     --env MANIFEST_RUN \
                     --env MANIFEST_CMD \
                     --env MANIFEST_STARTED \
                     --env FORCE \
                     --env NO_COLOR \
                     --env QUIET \
                     downloaders_ena_download::download_ena_worker {} "$output_dir" "$temp_dir"
        
        local exit_code=$?
        
    else
        log_warning "GNU parallel not found, using built-in parallel execution"
        log_info "Install GNU parallel for better performance: apt-get install parallel"
        log_info ""
        
        # Built-in parallel execution using background jobs
        local pids=()
        local failed_accessions=()
        local success_count=0
        local fail_count=0
        
        while IFS= read -r accession; do
            [[ -z "$accession" || "$accession" =~ ^# ]] && continue
            
            # Wait if we've reached max parallel jobs
            while [[ ${#pids[@]} -ge $parallel_jobs ]]; do
                for i in "${!pids[@]}"; do
                    if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                        wait "${pids[$i]}"
                        if [[ $? -eq 0 ]]; then
                            ((success_count++))
                        else
                            ((fail_count++))
                        fi
                        unset "pids[$i]"
                    fi
                done
                pids=("${pids[@]}")  # Re-index array
                sleep 0.1
            done
            
            # Start new download in background
            downloaders_ena_download::download_ena_worker "$accession" "$output_dir" "$temp_dir" &
            pids+=($!)
            
        done < "$accession_list"
        
        # Wait for remaining jobs
        for pid in "${pids[@]}"; do
            wait "$pid"
            if [[ $? -eq 0 ]]; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        done
        
        local exit_code=0
        [[ $fail_count -gt 0 ]] && exit_code=1
    fi

    # Summary
    log_info ""
    log_info "==================== DOWNLOAD SUMMARY ===================="
    
    if command -v parallel &> /dev/null; then
        # With GNU parallel, count successes/failures by checking metadata files
        local success_count=0
        local fail_count=0
        
        while IFS= read -r accession; do
            [[ -z "$accession" || "$accession" =~ ^# ]] && continue
            
            # Check if download was successful by looking in fastq directory
            local found_file=false
            for f in "$output_dir/fastq/${accession}"*.fastq* "$output_dir/fastq/"*"${accession}"*.fastq*; do
                if [[ -f "$f" ]]; then
                    found_file=true
                    break
                fi
            done
            
            if [[ "$found_file" == true ]]; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        done < "$accession_list"
        
        exit_code=0
        [[ $fail_count -gt 0 ]] && exit_code=1
    fi
    
    log_info "Total: $total | Success: $success_count | Failed: $fail_count"

    if [[ $fail_count -gt 0 ]]; then
        log_warning "Some downloads failed. Try alternative methods:"
        log_info "  1. seqfetcher download --sra-method fasterq --sra-accession-file runs.txt"
        log_info "  2. seqfetcher download --sra-method prefetch --sra-accession-file runs.txt"
        log_info "  3. seqfetcher download --sra-method parallel --sra-accession-file runs.txt"
    else
        log_info "All ENA downloads complete!"
    fi

    downloaders_common::batch_exit_code "$success_count" "$fail_count"
}