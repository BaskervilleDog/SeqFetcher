#!/usr/bin/env bash

geo_help_download_supplementary() {
cat <<EOF
Usage:
  seqfetcher geo-supp [options]

Options:
  --geo <GSEXXXXX>      GEO series accession
  --help               Show this help

Example:
  seqfetcher geo-supp --geo GSE280953
EOF
}

geo_help_create_srr() {
cat <<EOF
Usage:
  seqfetcher geo-srr [options]

Options:
  --geo <GSEXXXXX>      GEO series accession
  --out <file>         Output file (default: SRR_list.txt)
  --help               Show this help

Example:
  seqfetcher geo-srr --geo GSE280953 --out runs.txt
EOF
}

download_geo_supplementary() {

    is_help "$1" && { geo_help_download_supplementary; return 0; }

    local geo_accession=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --geo)  geo_accession="$2"; shift 2 ;;
            --help|-h) geo_help_download_supplementary; return 0 ;;
            *)
                log_error "Unknown option: $1"
                geo_help_download_supplementary
                return 1
                ;;
        esac
    done

    log_step "Downloading GEO Supplementary Files"

    if ! validate_accession "$geo_accession"; then
        return 1
    fi

    log_info "Downloading supplementary files for $geo_accession..."

    local series_stub=$(echo "$geo_accession" | sed 's/\(GSE[0-9]*\)[0-9]\{3\}$/\1nnn/')
    local ftp_base="https://ftp.ncbi.nlm.nih.gov/geo/series/${series_stub}/${geo_accession}/suppl/"

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
    done < <(grep -o 'href="[^"]*"' "${TEMP_DIR}/file_list.html" |
        sed 's/href="//;s/"$//' |
        grep -v '^\.\.' |
        grep -v '^/')

    log_info "✓ Downloaded $file_count file(s)"
    log_info "Files saved to: ${OUTPUT_DIR}/metadata/${geo_accession}/"
}

create_srr_list_from_geo() {

    is_help "$1" && { geo_help_create_srr; return 0; }

    local geo_accession=""
    local output_file="SRR_list.txt"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --geo) geo_accession="$2"; shift 2 ;;
            --out) output_file="$2"; shift 2 ;;
            --help|-h) geo_help_create_srr; return 0 ;;
            *)
                log_error "Unknown option: $1"
                geo_help_create_srr
                return 1
                ;;
        esac
    done

    log_step "Creating SRR list from GEO accession"

    check_command ffq || return 1
    validate_accession "$geo_accession" || return 1

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

    [[ ! -s "$temp_srr" ]] && \
        grep -oE '(SRR|ERR|DRR)[0-9]+' "$temp_output" | sort -u > "$temp_srr"

    if [[ ! -s "$temp_srr" ]]; then
        log_error "No SRR accessions found for $geo_accession"
        return 1
    fi

    cp "$temp_srr" "$output_file"

    local count
    count=$(wc -l < "$output_file")

    log_info "✓ Found $count SRR accession(s)"
    log_info "Saved to: $output_file"

    local log_output="${output_file%.txt}_ffq_log.txt"
    cp "$temp_output" "$log_output"
    log_debug "Full ffq output saved to: $log_output"
}