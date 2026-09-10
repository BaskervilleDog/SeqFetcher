#!/usr/bin/env bash

parsers_search::parse_search_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --organism)        ORGANISM="$2"; shift 2 || shift ;;
            --top)             TOP_N="$2"; shift 2 || shift ;;
            --mode)            MODE="$2"; shift 2 || shift ;;
            --outdir)          OUTDIR="$2"; shift 2 || shift ;;
            --output)          OUTPUT_FILE="$2"; shift 2 || shift ;;
            --interactive|-i)  INTERACTIVE=true; shift ;;
            --extract-genes)   EXTRACT_GENES=true; shift ;;

            # --- structure search modes ---
            --pdb)             MODE="pdb"; shift ;;
            --alphafold)       MODE="alphafold"; shift ;;

            # --- shared / PDB filters ---
            --text)            SEARCH_TEXT="$2"; shift 2 || shift ;;
            --method)          SEARCH_METHOD="$2"; shift 2 || shift ;;
            --max-resolution)  SEARCH_MAX_RESOLUTION="$2"; shift 2 || shift ;;
            --uniprot)         SEARCH_UNIPROT="$2"; shift 2 || shift ;;
            --ligand)          SEARCH_LIGAND="$2"; shift 2 || shift ;;
            --after-date)      SEARCH_AFTER_DATE="$2"; shift 2 || shift ;;
            --before-date)     SEARCH_BEFORE_DATE="$2"; shift 2 || shift ;;
            --min-chains)      SEARCH_MIN_CHAINS="$2"; shift 2 || shift ;;
            --sort)            SEARCH_SORT="$2"; shift 2 || shift ;;

            # --- AlphaFold (UniProt) filters ---
            --gene)            SEARCH_GENE="$2"; shift 2 || shift ;;
            --keyword)         SEARCH_KEYWORD="$2"; shift 2 || shift ;;
            --proteome)        SEARCH_PROTEOME="$2"; shift 2 || shift ;;
            --taxon-id)        SEARCH_TAXON_ID="$2"; shift 2 || shift ;;
            --reviewed)        SEARCH_REVIEWED=true; shift ;;
            --check-alphafold) CHECK_ALPHAFOLD=true; shift ;;

            --help|-h)         show_help; exit 0 ;;
            *) log_error "Unknown option for search: $1"; show_help; exit "${EX_USAGE:-2}" ;;
        esac
    done
}
