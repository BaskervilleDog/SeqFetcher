#!/usr/bin/env bash

# ============================================================
# Utility functions for seqfetcher
# ============================================================

# -------------------------------
# Dependency checking
# -------------------------------

check_command() {
    local cmd="$1"
    command -v "$cmd" &>/dev/null || {
        log_error "Missing dependency: $cmd"
        return 1
    }
}

# -------------------------------
# Directory & logging setup
# -------------------------------

create_dirs() {

    : "${OUTPUT_DIR:?OUTPUT_DIR not set}"
    : "${TEMP_DIR:?TEMP_DIR not set}"

    mkdir -p \
        "$OUTPUT_DIR"/{fastq,metadata,genomes,transcriptomes,proteomes} \
        "$TEMP_DIR"

    # Initialize log file only once
    if [[ -z "${LOG_FILE:-}" ]]; then
        LOG_FILE="${OUTPUT_DIR}/seqfetcher.log"
        : > "$LOG_FILE"
    fi

    log_info "Created output directories in: $OUTPUT_DIR"
    log_info "Temporary directory: $TEMP_DIR"
    log_info "Log file: $LOG_FILE"
}

# -------------------------------
# Cleanup handler
# -------------------------------

cleanup() {
    [[ -d "${TEMP_DIR:-}" ]] || return 0

    log_debug "Cleaning up temporary directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
}

# -------------------------------
# Retry wrapper
# -------------------------------

retry_command() {

    local max_attempts="${MAX_RETRIES:-3}"
    local attempt=1
    local delay=5

    while (( attempt <= max_attempts )); do

        log_debug "Running command (attempt $attempt/$max_attempts): $*"

        if run_command "$@"; then
            return 0
        fi

        if (( attempt < max_attempts )); then
            log_warn "Attempt $attempt failed — retrying in ${delay}s..."
            sleep "$delay"
            ((attempt++))
            delay=$((delay * 2))
        else
            log_error "Command failed after $max_attempts attempts"
            return 1
        fi
    done
}

# -------------------------------
# Command runner (dry-run aware)
# -------------------------------

run_command() {

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] $*"
        return 0
    fi

    log_debug "Executing: $*"
    "$@"
}

# -------------------------------
# Helping
# -------------------------------

is_help() {
    [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]
}

# -------------------------------
# Accession validation
# -------------------------------

validate_accession() {

    local acc="$1"

    [[ -n "$acc" ]] || {
        log_error "Empty accession provided"
        return 1
    }

    local len=${#acc}
    if (( len < 6 || len > 30 )); then
        log_warn "Unusual accession length ($len): $acc"
    fi

    case "$acc" in
        # Assemblies
        GCF_[0-9]*.[0-9]*|GCA_[0-9]*.[0-9]*) return 0 ;;
        # Runs
        SRR[0-9]*|ERR[0-9]*|DRR[0-9]*) return 0 ;;
        # Studies / samples
        GSE[0-9]*|GSM[0-9]*|SRP[0-9]*|ERP[0-9]*|DRP[0-9]*) return 0 ;;
        *)
            log_error "Invalid accession format: $acc"
            log_info "Accepted formats:"
            log_info "  Assemblies: GCF_*, GCA_*"
            log_info "  Runs:       SRR*, ERR*, DRR*"
            log_info "  Studies:    GSE*, GSM*, SRP*, ERP*, DRP*"
            return 1
            ;;
    esac
}

# -------------------------------
# Completion tracking
# -------------------------------

_status_file() {
    echo "${OUTPUT_DIR}/.completed"
}

mark_complete() {

    local accession="$1"
    local status_file
    status_file="$(_status_file)"

    mkdir -p "$(dirname "$status_file")"

    # Avoid duplicates
    grep -qx "$accession" "$status_file" 2>/dev/null || echo "$accession" >> "$status_file"

    log_debug "Marked accession as complete: $accession"
}

is_complete() {

    local accession="$1"
    local status_file
    status_file="$(_status_file)"

    [[ -f "$status_file" ]] && grep -qx "$accession" "$status_file"
}

# -------------------------------
# Progress reporting
# -------------------------------

show_progress() {

    local current="$1"
    local total="$2"
    local accession="$3"

    log_info "[$current/$total] Processing: $accession"
}

# -------------------------------
# Required parameter enforcement
# -------------------------------

require_param() {

    local param_name="$1"
    local param_value="$2"

    if [[ -z "$param_value" ]]; then
        log_error "Missing required parameter: --${param_name}"
        log_info "Run: seqfetcher ${COMMAND} ${SUBCOMMAND} --help"
        exit 1
    fi
}

# -------------------------------
# Environment check
# -------------------------------

check_environment() {

    log_step "Checking environment"

    local deps=(
        fasterq-dump
        prefetch
        parallel-fastq-dump
        wget
        curl
        jq
        ffq
        datasets
        unzip
        gzip
    )

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

    if (( missing > 0 )); then
        log_info ""
        log_info "Suggested installations:"
        log_info "  SRA tools:          conda install -c bioconda sra-tools"
        log_info "  parallel-fastq:    pip install parallel-fastq-dump"
        log_info "  ffq:               pip install ffq"
        log_info "  NCBI datasets:     conda install -c conda-forge ncbi-datasets-cli"
        log_info "  jq:                conda install -c conda-forge jq"
    fi

    return 0
}
