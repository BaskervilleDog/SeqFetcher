#!/usr/bin/env bash

validate_sra_accession() {
    local acc="$1"

    # Valid patterns:
    # SRRxxxxxxx, ERRxxxxxxx, DRRxxxxxxx
    # SRP, ERP, DRP projects
    # PRJNAxxxx, PRJEBxxxx
    # GSExxxx (will later expand if you add resolver)

    if [[ "$acc" =~ ^(SRR|ERR|DRR)[0-9]+$ ]]; then
        return 0
    elif [[ "$acc" =~ ^(SRP|ERP|DRP)[0-9]+$ ]]; then
        return 0
    elif [[ "$acc" =~ ^PRJ(NA|EB)[0-9]+$ ]]; then
        return 0
    elif [[ "$acc" =~ ^GSE[0-9]+$ ]]; then
        return 0
    else
        log_error "Invalid FASTQ accession format: $acc"
        log_error "Expected: SRR/ERR/DRRxxxxxx, PRJNAxxxx, PRJEBxxxx, GSExxxx"
        return 1
    fi
}

export -f validate_sra_accession

download_ena() {

    # --------------------------------------------------
    # Help / usage
    # --------------------------------------------------
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<EOF
Usage:
  seqfetcher download ena --accessions <file>

Description:
  Download FASTQ files from the European Nucleotide Archive (ENA)
  using a list of accessions (SRR / ERR / DRR / PRJ / GSE, etc).

Options:
  --accessions <file>   File containing accessions (one per line)
  -h, --help            Show this help message

Notes:
  - Requires: wget or curl, md5sum, numfmt
  - Downloads are saved to: \$OUTPUT_DIR/fastq
  - Completed accessions are tracked and skipped automatically
  - MD5 and file size are verified when available

Example:
  seqfetcher download ena --accessions runs.txt

EOF
        return 0
    fi

    # --------------------------------------------------
    # Argument parsing (simple: only accession file)
    # --------------------------------------------------
    local accession_list="$1"

    if [[ -z "$accession_list" ]]; then
        log_error "Missing accession list file"
        log_info "Run: seqfetcher download ena --help"
        return 1
    fi

    # --------------------------------------------------
    # Dependency checks
    # --------------------------------------------------
    log_step "METHOD 4: Using ENA (European Nucleotide Archive)"

    if [[ ! -f "$accession_list" ]]; then
        log_error "Accession list file not found: $accession_list"
        return 1
    fi

    mkdir -p "$OUTPUT_DIR/fastq" "$TEMP_DIR"

    # --------------------------------------------------
    # Counters / tracking
    # --------------------------------------------------
    local total current success_count fail_count
    local failed_accessions=()

    total=$(grep -cv '^#\|^$' "$accession_list" || echo 0)
    current=0
    success_count=0
    fail_count=0

    # --------------------------------------------------
    # Main loop
    # --------------------------------------------------
    while IFS= read -r accession; do

        [[ -z "$accession" || "$accession" =~ ^# ]] && continue

        ((current++))

        # Validate accession format
        if ! validate_sra_accession "$accession"; then
            ((fail_count++))
            failed_accessions+=("$accession")
            continue
        fi

        log_info "Fetching ENA metadata for $accession..."

        local ena_url
        ena_url="https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${accession}&result=read_run&fields=run_accession,fastq_ftp,fastq_md5,fastq_bytes"

        local meta_file="${TEMP_DIR}/${accession}_ena.txt"

        # Fetch metadata
        if command -v wget &> /dev/null; then
            wget -q -O "$meta_file" "$ena_url" || {
                log_error "Failed to fetch metadata for $accession"
                ((fail_count++))
                failed_accessions+=("$accession")
                continue
            }
        else
            curl -s -o "$meta_file" "$ena_url" || {
                log_error "Failed to fetch metadata for $accession"
                ((fail_count++))
                failed_accessions+=("$accession")
                continue
            }
        fi

        # Validate metadata
        if [[ ! -s "$meta_file" ]]; then
            log_error "No metadata returned for $accession"
            ((fail_count++))
            failed_accessions+=("$accession")
            continue
        fi

        local line_count
        line_count=$(wc -l < "$meta_file")

        if [[ "$line_count" -lt 2 ]]; then
            log_error "No ENA FASTQ data for $accession"
            ((fail_count++))
            failed_accessions+=("$accession")
            continue
        fi

        local has_files=false
        local download_failed=false

        # --------------------------------------------------
        # Parse ENA table (skip header)
        # --------------------------------------------------
        while IFS=$'\t' read -r run_acc ftp_urls md5_sums file_sizes; do

            if [[ -z "$ftp_urls" || "$ftp_urls" == "null" ]]; then
                log_error "No FASTQ files available at ENA for $run_acc"
                log_info  "This accession may only be available via SRA"
                download_failed=true
                continue
            fi

            has_files=true
            log_info "Downloading FASTQ files for $run_acc..."

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
                output_file="${OUTPUT_DIR}/fastq/${filename}"

                size_display="Unknown"
                if [[ -n "$expected_size" && "$expected_size" != "null" ]]; then
                    size_display=$(numfmt --to=iec-i --suffix=B "$expected_size" 2>/dev/null || echo "${expected_size}B")
                fi

                log_info "  Downloading: $filename (Size: $size_display)"

                if wget -c -q --show-progress -O "$output_file" "$ftp_url"; then
                    log_info "  ✓ Downloaded: $filename"

                    # MD5 verification
                    if [[ -n "$expected_md5" && "$expected_md5" != "null" ]]; then
                        log_info "  Verifying MD5 checksum..."
                        actual_md5=$(md5sum "$output_file" | awk '{print $1}')

                        if [[ "$actual_md5" == "$expected_md5" ]]; then
                            log_info "  ✓ Checksum verified"
                        else
                            log_error "  ✗ Checksum mismatch for $filename"
                            log_error "    Expected: $expected_md5"
                            log_error "    Got:      $actual_md5"
                            download_failed=true
                        fi
                    fi

                    # Size verification
                    if [[ -n "$expected_size" && "$expected_size" != "null" ]]; then
                        actual_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null)

                        if [[ "$actual_size" == "$expected_size" ]]; then
                            log_info "  ✓ File size verified"
                        else
                            log_warning "  ⚠ File size mismatch (expected: $expected_size, got: $actual_size)"
                        fi
                    fi
                else
                    log_error "  ✗ Failed to download $filename"
                    download_failed=true
                fi
            done

        done < <(tail -n +2 "$meta_file")

        # --------------------------------------------------
        # Final status per accession
        # --------------------------------------------------
        if [[ "$has_files" == true && "$download_failed" == false ]]; then
            #mark_complete "$accession"
            ((success_count++))
            log_info "✓ Completed: $accession"
        else
            ((fail_count++))
            failed_accessions+=("$accession")
            log_error "✗ Failed: $accession"
        fi

    done < "$accession_list"

    # --------------------------------------------------
    # Summary
    # --------------------------------------------------
    log_info ""
    log_info "==================== DOWNLOAD SUMMARY ===================="
    log_info "Total: $total | Success: $success_count | Failed: $fail_count"

    if [[ "$fail_count" -gt 0 ]]; then
        log_warning ""
        log_warning "Failed accessions (try alternative methods):"
        printf '  - %s\n' "${failed_accessions[@]}"
        log_info ""
        log_info "Alternative download methods:"
        log_info "  1. seqfetcher download --sra-method fasterq --sra-accession"
        log_info "  2. seqfetcher download --sra-method prefetch --sra-accession"
        log_info "  3. seqfetcher download --sra-method parallel --sra-accession"
        return 1
    fi

    log_info "All ENA downloads complete!"
    return 0
}
