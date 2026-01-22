#!/usr/bin/env bash

# ============================================================
# Commands
# ============================================================

cmd_discover_assembly() {

    local ORGANISM=""
    local FILTER="all"
    local OUTPUT=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --organism) ORGANISM="$2"; shift 2 ;;
            --filter)   FILTER="$2"; shift 2 ;;
            --out|--output) OUTPUT="$2"; shift 2 ;;
            --help|-h) help_discover_assembly; return 0 ;;
            *)
                log_error "Unknown option: $1"
                help_discover_assembly
                return 1
                ;;
        esac
    done

    require_param "organism" "$ORGANISM"
    OUTPUT="${OUTPUT:-${OUTPUT_DIR}/assembly_accessions.txt}"

    search_ncbi_assemblies "$ORGANISM" "$OUTPUT" "$FILTER"
}

cmd_download_genome() {

    # -----------------------------
    # No arguments → show help
    # -----------------------------
    if [[ $# -eq 0 ]]; then
        log_error "No genome options provided."
        log_info "Use one of:"
        log_info "  --assembly GCF_xxx"
        log_info "  --organism \"Homo sapiens\""
        log_info "  --accessions ACC1,ACC2"
        return 1
    fi

    local ASSEMBLY=""
    local ACCESSIONS=""
    local ORGANISM=""
    local INCLUDE="genome"
    local FILTER="reference"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --assembly) ASSEMBLY="$2"; shift 2 ;;
            --accessions) ACCESSIONS="$2"; shift 2 ;;
            --organism) ORGANISM="$2"; shift 2 ;;
            --include) INCLUDE="$2"; shift 2 ;;
            --filter)  FILTER="$2"; shift 2 ;;
            --help|-h) help_download_genome; return 0 ;;
            *)
                log_error "Unknown option: $1"
                help_download_genome
                return 1
                ;;
        esac
    done

    # -----------------------------
    # Validate mode
    # -----------------------------
    local modes=0
    [[ -n "$ASSEMBLY" ]] && ((modes++))
    [[ -n "$ACCESSIONS" ]] && ((modes++))
    [[ -n "$ORGANISM" ]] && ((modes++))

    if [[ $modes -ne 1 ]]; then
        log_error "You must specify exactly one of: --assembly, --accessions, or --organism"
        return 1
    fi

    # -----------------------------
    # Dispatch to correct backend
    # -----------------------------
    if [[ -n "$ASSEMBLY" ]]; then
        log_info "Downloading genome by assembly: $ASSEMBLY"
        download_ncbi_datasets "$ASSEMBLY" genome "$INCLUDE"
        return
    fi

    if [[ -n "$ACCESSIONS" ]]; then
        log_info "Downloading genomes from accession list: $ACCESSIONS"
        download_genomes_from_list "$ACCESSIONS" "$INCLUDE"
        return
    fi

    if [[ -n "$ORGANISM" ]]; then
        log_info "Searching and downloading genome by organism: $ORGANISM"
        search_and_download_assembly "$ORGANISM" "$FILTER" "$INCLUDE"
        return
    fi
}

cmd_download_fastq() {

    local ACCESSIONS=""
    local SOURCE="ena"
    local METHOD="fasterq"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --accessions) ACCESSIONS="$2"; shift 2 ;;
            --source) SOURCE="$2"; shift 2 ;;
            --method) METHOD="$2"; shift 2 ;;
            --help|-h) help_download_fastq; return 0 ;;
            *)
                log_error "Unknown option: $1"
                help_download_fastq
                return 1
                ;;
        esac
    done

    require_param "accessions" "$ACCESSIONS"

    case "$SOURCE:$METHOD" in
        ena:*)            download_ena "$ACCESSIONS" ;;
        sra:fasterq)     download_sra_fasterq "$ACCESSIONS" ;;
        sra:prefetch)    download_sra_prefetch "$ACCESSIONS" ;;
        sra:parallel)    download_parallel_fastq "$ACCESSIONS" ;;
        *)
            log_error "Invalid source/method combination"
            help_download_fastq
            return 1
            ;;
    esac
}

cmd_download_transcriptome() {

    local ARGS=("$@")
    download_transcriptome "${ARGS[@]}"
}

cmd_download_proteome() {

    local ARGS=("$@")
    download_proteome "${ARGS[@]}"
}

cmd_convert_geo() {

    local GEO=""
    local OUT="SRR_list.txt"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --geo) GEO="$2"; shift 2 ;;
            --out|--output) OUT="$2"; shift 2 ;;
            --help|-h) help_convert_geo; return 0 ;;
            *)
                log_error "Unknown option: $1"
                help_convert_geo
                return 1
                ;;
        esac
    done

    require_param "geo" "$GEO"
    create_srr_list_from_geo --geo "$GEO" --out "$OUT"
}