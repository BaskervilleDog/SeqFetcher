#!/usr/bin/env bash

downloaders_ensembl_download::get_latest_ensembl_release() {
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

downloaders_ensembl_download::download_ensembl_fasta() {

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
        if [[ "${REQUIRE_PINNED:-false}" == true ]]; then
            die "Ensembl release not pinned - pass --release <n> (or drop --require-pinned)" "${EX_USAGE:-2}"
        fi
        release=$(downloaders_ensembl_download::get_latest_ensembl_release "$species_dir" | tr -d '\r\n[:space:]') || return "${EX_NETWORK:-5}"
        log_warning "Ensembl release not pinned; resolved to $release - pass --release $release to reproduce this dataset"
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
    # Download (atomic + recorded)
    # --------------------------------------------------
    local url="${base_url}/${file_name}"
    local out_file="${output_dir}/${file_name}"
    local key="${species_dir}:${fasta_type}:ensembl-${release}"

    log_info "Downloading: $file_name"
    log_info "Final URL: $url"

    if downloaders_common::already_have "$out_file" "$(manifest::stored_md5 "$key")"; then
        log_info "Already present - skipping: $out_file (use --force to refetch)"
        manifest::record_run_only "$key" "$(jq -n --arg p "$out_file" --arg r "$release" \
            '{type:"ensembl-fasta", source:"ensembl", db_release:("Ensembl " + $r), status:"skipped", files:[{path:$p}]}')"
        return 0
    fi

    downloaders_common::atomic_fetch "$url" "$out_file" || return $?

    log_success "Downloaded ${fasta_type} FASTA from Ensembl (release $release)"
    manifest::record "$key" "$(jq -n \
        --arg p "$out_file" --arg u "$url" --arg r "$release" \
        --arg md5 "${LAST_FETCH_MD5:-}" --argjson bytes "${LAST_FETCH_BYTES:-0}" \
        '{type:"ensembl-fasta", source:"ensembl", source_url:$u,
          db_release:("Ensembl " + $r), status:"downloaded",
          files:[{path:$p, bytes:$bytes, md5:$md5}]}')"
    return 0
}

downloaders_ensembl_download::download_transcriptome() {

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

            downloaders_common::check_command datasets || return "${EX_DEPENDENCY:-3}"

            local output_dir="${OUTPUT_DIR}/transcriptomes/${accession}"
            local key="${accession}:transcriptome"

            if [[ "${FORCE:-false}" != true ]] && manifest::is_done "$key" && [[ -d "$output_dir" ]]; then
                log_info "[$accession] transcriptome already present - skipping"
                manifest::record_run_only "$key" "$(jq -n --arg d "$output_dir" '{accession:"'"$accession"'", type:"transcriptome", source:"ncbi-datasets", status:"skipped", files:[{path:$d}]}')"
                return 0
            fi

            log_info "Using NCBI datasets for $accession..."
            local stage; stage="$(downloaders_common::new_stage)" || return "${EX_ERROR:-1}"

            if downloaders_geo_download::retry_command datasets download genome accession "$accession" \
                --include rna,gff3,gbff,gtf,seq-report \
                --filename "$stage/data.zip" \
               && unzip -q "$stage/data.zip" -d "$stage/extracted" 2>/dev/null \
               && { rm -f "$stage/data.zip"; downloaders_common::promote "$stage/extracted" "$output_dir"; }; then
                rm -rf "$stage"
                log_success "Transcriptome downloaded from NCBI"
                downloaders_ncbi_download::_record_dir "$key" "$accession" "transcriptome" "ncbi-datasets" "$output_dir"
                return 0
            fi

            rm -rf "$stage"
            log_error "NCBI transcriptome unavailable for $accession"
            manifest::record "$key" "$(jq -n '{accession:"'"$accession"'", type:"transcriptome", source:"ncbi-datasets", status:"failed"}')"
            return "${EX_NETWORK:-5}"
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

            downloaders_ensembl_download::download_ensembl_fasta "$species" "$fasta_type" "$output_dir"
            return $?
            ;;

        auto)
            [[ -n "$accession" ]] && \
                downloaders_ensembl_download::download_transcriptome "$accession" "$species" "ncbi" "$fasta_type" && return 0

            [[ -n "$species" ]] && \
                downloaders_ensembl_download::download_transcriptome "$accession" "$species" "ensembl" "$fasta_type" && return 0

            log_error "Auto mode failed"
            return 1
            ;;

        *)
            log_error "Unknown source: $source"
            return 1
            ;;
    esac
}

downloaders_ensembl_download::download_proteome() {

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

            downloaders_common::check_command datasets || return "${EX_DEPENDENCY:-3}"

            local output_dir="${OUTPUT_DIR}/proteomes/${accession}"
            local key="${accession}:proteome"

            if [[ "${FORCE:-false}" != true ]] && manifest::is_done "$key" && [[ -d "$output_dir" ]]; then
                log_info "[$accession] proteome already present - skipping"
                manifest::record_run_only "$key" "$(jq -n --arg d "$output_dir" '{accession:"'"$accession"'", type:"proteome", source:"ncbi-datasets", status:"skipped", files:[{path:$d}]}')"
                return 0
            fi

            log_info "Using NCBI datasets for $accession..."
            local stage; stage="$(downloaders_common::new_stage)" || return "${EX_ERROR:-1}"

            if downloaders_geo_download::retry_command datasets download genome accession "$accession" \
                --include protein,cds,seq-report \
                --filename "$stage/data.zip" \
               && unzip -q "$stage/data.zip" -d "$stage/extracted" 2>/dev/null \
               && { rm -f "$stage/data.zip"; downloaders_common::promote "$stage/extracted" "$output_dir"; }; then
                rm -rf "$stage"
                log_success "Proteome downloaded from NCBI"
                downloaders_ncbi_download::_record_dir "$key" "$accession" "proteome" "ncbi-datasets" "$output_dir"
                return 0
            fi

            rm -rf "$stage"
            log_error "NCBI proteome unavailable for $accession"
            manifest::record "$key" "$(jq -n '{accession:"'"$accession"'", type:"proteome", source:"ncbi-datasets", status:"failed"}')"
            return "${EX_NETWORK:-5}"
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

            downloaders_ensembl_download::download_ensembl_fasta "$species" "$fasta_type" "$output_dir"
            return $?
            ;;

        auto)
            [[ -n "$accession" ]] && \
                downloaders_ensembl_download::download_proteome "$accession" "$species" "ncbi" "$fasta_type" && return 0

            [[ -n "$species" ]] && \
                downloaders_ensembl_download::download_proteome "$accession" "$species" "ensembl" "$fasta_type" && return 0

            log_error "Auto mode failed"
            return 1
            ;;

        *)
            log_error "Unknown source: $source"
            return 1
            ;;
    esac
}
