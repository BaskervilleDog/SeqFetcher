#!/usr/bin/env bash

# GEO Download Module
# Functions for downloading GEO supplementary files and extracting SRR lists

#==============================================================
# Helper Functions
#==============================================================

is_help() {
    [[ "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]
}

retry_command() {
    local max_attempts=3
    local attempt=1
    
    while (( attempt <= max_attempts )); do
        if "$@"; then
            return 0
        fi
        log_warning "Attempt $attempt failed, retrying..."
        ((attempt++))
        sleep 2
    done
    
    return 1
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command not found: $1"
        log_error "Please install $1 and try again"
        return 1
    fi
    return 0
}

validate_geo_accession() {
    local accession="$1"
    
    if [[ -z "$accession" ]]; then
        log_error "GEO accession cannot be empty"
        return 1
    fi
    
    # Validate GEO accession format (GSE followed by numbers)
    if [[ ! "$accession" =~ ^GSE[0-9]+$ ]]; then
        log_error "Invalid GEO accession format: $accession"
        log_error "Expected format: GSEXXXXX (e.g., GSE280953)"
        return 1
    fi
    
    return 0
}

#==============================================================
# GEO Help Functions
#==============================================================

geo_help_download_supplementary() {
    cat <<EOF
Usage:
  seqfetcher geo-supp [options]

Options:
  --geo <GSEXXXXX>      GEO series accession
  --outdir DIR          Output directory (default: downloads)
  --help               Show this help

Example:
  seqfetcher geo-supp --geo GSE280953
  seqfetcher geo-supp --geo GSE280953 --outdir geo_data
EOF
}

geo_help_create_srr() {
    cat <<EOF
Usage:
  seqfetcher geo-srr [options]

Options:
  --geo <GSEXXXXX>      GEO series accession
  --out <file>         Output file (default: SRR_list.txt)
  --outdir DIR         Output directory (default: downloads)
  --help               Show this help

Example:
  seqfetcher geo-srr --geo GSE280953 --out runs.txt
  seqfetcher geo-srr --geo GSE280953 --outdir geo_data
EOF
}

#==============================================================
# GEO Download Functions
#==============================================================

download_geo_supplementary() {
    is_help "$1" && { geo_help_download_supplementary; return 0; }
    
    local geo_accession=""
    local output_dir="${OUTPUT_DIR:-downloads}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --geo)
                geo_accession="$2"; shift 2 ;;
            --outdir)
                output_dir="$2"; shift 2 ;;
            --help|-h)
                geo_help_download_supplementary; return 0 ;;
            *)
                log_error "Unknown option: $1"
                geo_help_download_supplementary
                return 1
                ;;
        esac
    done
    
    log_step "Downloading GEO Supplementary Files"
    
    if ! validate_geo_accession "$geo_accession"; then
        return 1
    fi
    
    log_info "Downloading supplementary files for $geo_accession..."
    
    # Convert GSE123456789 -> GSE123456nnn
    local series_stub=$(echo "$geo_accession" | sed 's/\(GSE[0-9]*\)[0-9]\{3\}$/\1nnn/')
    local ftp_base="https://ftp.ncbi.nlm.nih.gov/geo/series/${series_stub}/${geo_accession}/suppl/"
    
    # Create output directories
    mkdir -p "${output_dir}/metadata/${geo_accession}"
    mkdir -p "${TEMP_DIR}"
    
    # Fetch file listing from FTP
    if ! wget -q -O "${TEMP_DIR}/file_list.html" "$ftp_base"; then
        log_error "Could not access GEO FTP site at: $ftp_base"
        log_error "Please verify the GEO accession is correct"
        return 1
    fi
    
    local file_count=0
    
    # Parse HTML and download each file
    while IFS= read -r filename; do
        [[ -z "$filename" ]] && continue
        
        # Skip non-data files (HTML pages, policy links, etc.)
        if [[ "$filename" =~ ^https?:// ]] || \
           [[ "$filename" =~ \.html?$ ]] || \
           [[ "$filename" =~ vulnerability|policy|index\.html ]]; then
            continue
        fi
        
        log_info "  Downloading: $filename"
        
        if retry_command wget -c -q --show-progress \
            -P "${output_dir}/metadata/${geo_accession}" \
            "${ftp_base}${filename}"; then
            ((file_count++))
        else
            log_warning "  Failed: $filename"
        fi
    done < <(grep -o 'href="[^"]*"' "${TEMP_DIR}/file_list.html" | \
        sed 's/href="//;s/"$//' | \
        grep -v '^\.\.' | \
        grep -v '^/')
    
    # Clean up the file list
    rm -f "${TEMP_DIR}/file_list.html"
    
    if (( file_count == 0 )); then
        log_warning "No supplementary files found for $geo_accession"
        return 1
    fi
    
    log_info "✓ Downloaded $file_count file(s)"
    log_info "Files saved to: ${output_dir}/metadata/${geo_accession}/"
}

create_srr_list_from_geo() {
    is_help "$1" && { geo_help_create_srr; return 0; }
    
    local geo_accession=""
    local output_file="SRR_list.txt"
    local output_dir="${OUTPUT_DIR:-downloads}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --geo)
                geo_accession="$2"; shift 2 ;;
            --out)
                output_file="$2"; shift 2 ;;
            --outdir)
                output_dir="$2"; shift 2 ;;
            --help|-h)
                geo_help_create_srr; return 0 ;;
            *)
                log_error "Unknown option: $1"
                geo_help_create_srr
                return 1
                ;;
        esac
    done
    
    log_step "Creating SRR list from GEO accession"
    
    # Check for ffq command
    check_command ffq || return 1
    
    # Validate GEO accession
    validate_geo_accession "$geo_accession" || return 1
    
    # Create temp directory
    mkdir -p "${TEMP_DIR}"
    
    log_info "Fetching SRA information for $geo_accession using ffq..."
    
    local temp_output="${TEMP_DIR}/${geo_accession}_ffq_raw.txt"
    local temp_srr="${TEMP_DIR}/temp_srr.txt"
    
    # Run ffq to get SRA information
    # Note: ffq may report errors at the end but still extract valid SRR accessions
    ffq --ftp "$geo_accession" > "$temp_output" 2>&1 || true
    
    # Check if we got any output
    if [[ ! -s "$temp_output" ]]; then
        log_error "Failed to fetch data for $geo_accession"
        log_error "No output from ffq command"
        return 1
    fi
    
    log_info "Extracting SRR accessions..."
    
    # Try parsing "Parsing run SRR..." lines first
    grep -oP 'Parsing run \K(SRR|ERR|DRR)\d+' "$temp_output" | sort -u > "$temp_srr" 2>/dev/null || true
    
    # Fallback: extract any SRR/ERR/DRR patterns
    [[ ! -s "$temp_srr" ]] && \
        grep -oE '(SRR|ERR|DRR)[0-9]+' "$temp_output" | sort -u > "$temp_srr"
    
    if [[ ! -s "$temp_srr" ]]; then
        log_error "No SRR accessions found for $geo_accession"
        log_error "The GEO entry may not have associated SRA data"
        # Clean up and return
        rm -f "$temp_output" "$temp_srr"
        return 1
    fi
    
    # Ensure output file has absolute or relative path
    if [[ "$output_file" != /* ]] && [[ "$output_file" != ./* ]]; then
        output_file="${output_dir}/${output_file}"
    fi
    
    # Create output directory if needed
    mkdir -p "$(dirname "$output_file")"
    
    cp "$temp_srr" "$output_file"
    
    local count
    count=$(wc -l < "$output_file")
    
    log_info "✓ Found $count SRR accession(s)"
    log_info "Saved to: $output_file"
    
    # Save full ffq log
    local log_output="${output_file%.txt}_ffq_log.txt"
    cp "$temp_output" "$log_output"
    log_info "Full ffq output saved to: $log_output"
    
    # Clean up temporary files
    rm -f "$temp_output" "$temp_srr"
}
