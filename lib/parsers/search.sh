#!/usr/bin/env bash

parsers_search::parse_search_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --organism) ORGANISM="$2"; shift 2 ;;
            --mode) MODE="$2"; shift 2 ;;
            --outdir) OUTDIR="$2"; shift 2 ;;
            --output) OUTPUT_FILE="$2"; shift 2 ;;
            --interactive|-i) INTERACTIVE=true; shift ;;
            --extract-genes) EXTRACT_GENES=true; shift ;;
            --help|-h) show_help; exit 0 ;;
            *) log_error "Unknown option for search: $1"; show_help; exit 1 ;;
        esac
    done
}