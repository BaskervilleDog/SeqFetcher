#!/usr/bin/env bash

#==============================================================
# Download sra-files in loop
#==============================================================

# --- SRA accession validator (local, correct) ---
validate_sra_accession() {
    local acc="$1"
    [[ "$acc" =~ ^(SRR|ERR|DRR)[0-9]+$ ]]
}

_download_sra_loop() {

    local method="$1"
    local accession_list="$2"

    [[ -f "$accession_list" ]] || {
        log_error "Accession list file not found: $accession_list"
        return 1
    }

    local total
    total=$(grep -cv '^#\|^$' "$accession_list" || echo 0)

    local current=0
    local success=0
    local failed=0
    local failed_list=()

    log_info "Reading accessions from: $accession_list"
    log_info "Total accessions: $total"
    log_info "Download method: $method"

    while IFS= read -r accession; do

        [[ -z "$accession" || "$accession" =~ ^# ]] && continue

        ((current++))

        # -----------------------------
        # Validate SRA accession
        # -----------------------------
        if ! validate_sra_accession "$accession"; then
            log_error "Invalid SRA accession format: $accession"
            log_error "Expected: SRRxxxxxx, ERRxxxxxx or DRRxxxxxx"
            ((failed++))
            failed_list+=("$accession")
            continue
        fi

        # -----------------------------
        # Dispatch to method
        # -----------------------------
        if _download_one_sra "$method" "$accession"; then
            ((success++))
            log_info "✓ Completed: $accession"
        else
            log_error "✗ Failed: $accession"
            ((failed++))
            failed_list+=("$accession")
        fi

    done < "$accession_list"

    # -------------------------------
    # Summary
    # -------------------------------

    log_info ""
    log_info "==================== DOWNLOAD SUMMARY ===================="
    log_info "Total: $total | Success: $success | Failed: $failed"

    if (( failed > 0 )); then
        log_error "Failed accessions:"
        printf '  - %s\n' "${failed_list[@]}"
        return 1
    fi

    log_info "All downloads complete!"
    return 0
}

#==============================================================
# Download single sra-files
#==============================================================

_download_one_sra() {

    local method="$1"
    local accession="$2"

    case "$method" in
        fasterq)
            _download_fasterq "$accession"
            ;;
        prefetch)
            _download_prefetch "$accession"
            ;;
        parallel)
            _download_parallel "$accession"
            ;;
        *)
            log_error "Unknown SRA download method: $method"
            return 1
            ;;
    esac
}

#==============================================================
# Download sra-files using fasterq dump
#==============================================================

_download_fasterq() {

    local accession="$1"

    log_info "Downloading $accession with fasterq-dump..."

     fasterq-dump "$accession" \
        --outdir "${OUTPUT_DIR}/fastq" \
        --temp "${TEMP_DIR}" \
        --threads "$THREADS" \
        --split-files \
        --progress || return 1

    log_info "Compressing FASTQ files for $accession"
    find "${OUTPUT_DIR}/fastq" -name "${accession}*.fastq" -type f -exec gzip {} \; 2>/dev/null || true

    return 0
}

#==============================================================
# Download sra-files with prefetch and fasterq dump
#==============================================================

_download_prefetch() {

    local accession="$1"

    log_info "Pre-fetching $accession..."

     prefetch "$accession" \
        --max-size "${MAX_SIZE:-20G}" \
        --output-directory "${TEMP_DIR}" \
        --progress || return 1

    local sra_file="${TEMP_DIR}/${accession}/${accession}.sra"

    [[ -f "$sra_file" ]] || {
        log_error "SRA file not found after prefetch: $sra_file"
        return 1
    }

    log_info "Converting $accession to FASTQ..."

    fasterq-dump "$sra_file" \
        --outdir "${OUTPUT_DIR}/fastq" \
        --temp "${TEMP_DIR}/temp" \
        --threads "$THREADS" \
        --split-files \
        --progress || return 1

    gzip "${OUTPUT_DIR}/fastq/${accession}"*.fastq 2>/dev/null || true
    rm -rf "${TEMP_DIR:?}/${accession}"

    return 0
}

#==============================================================
# Download sra-files parallel-fasterq-dump
#==============================================================

_download_parallel() {

    local accession="$1"

    log_info "Downloading $accession with parallel-fastq-dump..."

    parallel-fastq-dump \
        --sra-id "$accession" \
        --threads "$THREADS" \
        --outdir "${OUTPUT_DIR}/fastq" \
        --split-files \
        --tmpdir "${TEMP_DIR}" \
        --gzip || return 1

    return 0
}

# ============================================================
# Public entry points
# ============================================================

download_sra_fasterq() {
    log_step "METHOD 1: fasterq-dump (simple & fast)"
    _download_sra_loop "fasterq" "$1"
}

download_sra_prefetch() {
    log_step "METHOD 2: prefetch + fasterq-dump (most robust)"
    _download_sra_loop "prefetch" "$1"
}

download_parallel_fastq() {
    log_step "METHOD 3: parallel-fastq-dump (fastest)"
    _download_sra_loop "parallel" "$1"
}
