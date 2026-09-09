#!/usr/bin/env bash

parsers_search::parse_search_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --organism)        ORGANISM="$2"; shift 2 ;;
            --top)             TOP_N="$2"; shift 2 ;;
            --mode)            MODE="$2"; shift 2 ;;
            --outdir)          OUTDIR="$2"; shift 2 ;;
            --output)          OUTPUT_FILE="$2"; shift 2 ;;
            --interactive|-i)  INTERACTIVE=true; shift ;;
            --extract-genes)   EXTRACT_GENES=true; shift ;;

            # --- structure search modes ---
            --pdb)             MODE="pdb"; shift ;;
            --alphafold)       MODE="alphafold"; shift ;;

            # --- shared / PDB filters ---
            --text)            SEARCH_TEXT="$2"; shift 2 ;;
            --method)          SEARCH_METHOD="$2"; shift 2 ;;
            --max-resolution)  SEARCH_MAX_RESOLUTION="$2"; shift 2 ;;
            --uniprot)         SEARCH_UNIPROT="$2"; shift 2 ;;
            --ligand)          SEARCH_LIGAND="$2"; shift 2 ;;
            --after-date)      SEARCH_AFTER_DATE="$2"; shift 2 ;;
            --before-date)     SEARCH_BEFORE_DATE="$2"; shift 2 ;;
            --min-chains)      SEARCH_MIN_CHAINS="$2"; shift 2 ;;
            --sort)            SEARCH_SORT="$2"; shift 2 ;;

            # --- AlphaFold (UniProt) filters ---
            --gene)            SEARCH_GENE="$2"; shift 2 ;;
            --keyword)         SEARCH_KEYWORD="$2"; shift 2 ;;
            --proteome)        SEARCH_PROTEOME="$2"; shift 2 ;;
            --taxon-id)        SEARCH_TAXON_ID="$2"; shift 2 ;;
            --reviewed)        SEARCH_REVIEWED=true; shift ;;
            --check-alphafold) CHECK_ALPHAFOLD=true; shift ;;

            --help|-h)         show_help; exit 0 ;;
            *) log_error "Unknown option for search: $1"; show_help; exit "${EX_USAGE:-2}" ;;
        esac
    done
}
