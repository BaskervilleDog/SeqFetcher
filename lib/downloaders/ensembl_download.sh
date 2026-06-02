#!/usr/bin/env bash

get_latest_ensembl_release() {
    local species_dir="$1"

    log_info "Detecting latest Ensembl release..." >&2

    local releases rel fallback

    releases=$(curl -fs https://ftp.ensembl.org/pub/ \
        | grep -oE 'release-[0-9]+' \
        | sed 's/release-//' \
        | sort -n \
        | uniq)

    [[ -z "$releases" ]] && {
        log_error "Failed to retrieve Ensembl releases list" >&2
        return 1
    }

    rel=$(echo "$releases" | tail -n 1)

    for fallback in $(echo "$releases" | tac); do
        if curl -fsI "https://ftp.ensembl.org/pub/release-${fallback}/fasta/${species_dir}/" >/dev/null; then
            [[ "$fallback" != "$rel" ]] && \
                log_warn "Release $rel incomplete, falling back to $fallback" >&2

            echo "$fallback"
            return 0
        fi
    done

    log_error "No valid Ensembl release found" >&2
    return 1
}

download_ensembl_fasta() {

    # --------------------------------------------------
    # Help
    # --------------------------------------------------
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<EOF
Usage:
  seqfetcher download ensembl-fasta --species <name> --type <cdna|cds|dna|ncrna|pep> [--out dir]

Description:
  Download FASTA files directly from Ensembl FTP for a given species.

Options:
  --species <name>     Species name (e.g. Homo_sapiens, mus_musculus)
  --type <type>        FASTA type:
                        cdna   - transcript sequences
                        cds    - coding sequences
                        dna    - genome DNA
                        ncrna  - non-coding RNA
                        pep    - protein sequences
  --out <dir>          Output directory
  --release <num>     Force Ensembl release (optional)
  -h, --help           Show this help message

Examples:
  seqfetcher download ensembl-fasta --species Homo_sapiens --type cdna
  seqfetcher download ensembl-fasta --species mus_musculus --type pep --release 110

Notes:
  - Default release = latest available
  - Output files are .fa.gz from Ensembl FTP

EOF
        return 0
    fi

    # --------------------------------------------------
    # Arguments
    # --------------------------------------------------
    local species_input="$1"
    local fasta_type="$2"
    local output_dir="$3"

    [[ -z "$species_input" || -z "$fasta_type" || -z "$output_dir" ]] && {
        log_error "Missing required arguments"
        log_info "Run: seqfetcher download ensembl-fasta --help"
        return 1
    }

    mkdir -p "$output_dir"

    # --------------------------------------------------
    # Species + release resolution
    # --------------------------------------------------
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
        for(i=2;i<=NF;i++){ $i = tolower($i) }
        print
    }')

    # --------------------------------------------------
    # FASTA type validation
    # --------------------------------------------------
    case "$fasta_type" in
        cdna|cds|dna|ncrna|pep) ;;
        *)
            log_error "Invalid Ensembl FASTA type: $fasta_type"
            log_info "Valid types: cdna, cds, dna, ncrna, pep"
            return 1
            ;;
    esac

    # --------------------------------------------------
    # Query Ensembl FTP
    # --------------------------------------------------
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

    [[ -z "$file_name" ]] && {
        log_error "Could not find ${fasta_type} FASTA for ${species_input}"
        log_info "Checked: $base_url/"
        return 1
    }

    # --------------------------------------------------
    # Download
    # --------------------------------------------------
    local url="${base_url}/${file_name}"
    local out_file="${output_dir}/${file_name}"

    log_info "Downloading: $file_name"
    log_info "Final URL: $url"

    [[ -f "$out_file" ]] && {
        log_info "File already exists, skipping: $out_file"
        return 0
    }

    retry_command curl -L -o "$out_file" "$url" || return 1

    log_info "✓ Downloaded ${fasta_type} FASTA from Ensembl"
    return 0
}

download_transcriptome() {

    # --------------------------------------------------
    # Help
    # --------------------------------------------------
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<EOF
Usage:
  seqfetcher download transcriptome [--assembly <acc>] [--species <name>] [--source ncbi|ensembl|auto] [--type cdna|cds|ncrna]

Description:
  Download transcriptome data either from:
   - NCBI (via genome assembly accession)
   - Ensembl (via species name)
   - Auto mode (tries NCBI first, then Ensembl)

Options:
  --assembly <acc>     NCBI assembly accession (for NCBI source)
  --species <name>    Species name (for Ensembl source)
  --source <mode>     ncbi (default), ensembl, auto
  --type <type>       FASTA type: cdna (default), cds, ncrna
  -h, --help          Show this help message

Examples:
  seqfetcher download transcriptome --assembly GCF_000001405.40
  seqfetcher download transcriptome --species Homo_sapiens --source ensembl --type cdna
  seqfetcher download transcriptome --assembly GCF_000001405.40 --source auto

Notes:
  - NCBI downloads include GTF, GFF3, GBFF when available
  - Ensembl downloads come directly from FTP

EOF
        return 0
    fi

    # --------------------------------------------------
    # Arguments
    # --------------------------------------------------
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

download_proteome() {

    # --------------------------------------------------
    # Help
    # --------------------------------------------------
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<EOF
Usage:
  seqfetcher download proteome [--assembly <acc>] [--species <name>] [--source ncbi|ensembl|auto] [--type pep]

Description:
  Download proteome data either from:
   - NCBI (via genome assembly accession)
   - Ensembl (via species name)
   - Auto mode (tries NCBI first, then Ensembl)

Options:
  --assembly <acc>     NCBI assembly accession (for NCBI source)
  --species <name>    Species name (for Ensembl source)
  --source <mode>     ncbi (default), ensembl, auto
  --type <type>       FASTA type: pep (default)
  -h, --help          Show this help message

Examples:
  seqfetcher download proteome --assembly GCF_000001405.40
  seqfetcher download proteome --species Homo_sapiens --source ensembl
  seqfetcher download proteome --assembly GCF_000001405.40 --source auto

EOF
        return 0
    fi

    # --------------------------------------------------
    # Arguments
    # --------------------------------------------------
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
