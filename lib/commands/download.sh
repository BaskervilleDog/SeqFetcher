#!/usr/bin/env bash

execute_download() {

    log_info \
        "Starting download ($DOWNLOAD_TYPE)"

    case "$DOWNLOAD_TYPE" in

        assembly)
            run_assembly_download
            ;;

        gene)
            run_gene_download
            ;;

        sra)
            run_sra_download
            ;;

        geo)
            run_geo_download
            ;;

        ensembl-fasta)
            run_ensembl_download
            ;;

        transcriptome)
            run_transcriptome_download
            ;;

        proteome)
            run_proteome_download
            ;;
        *)
            log_error "Unknown download type: $DOWNLOAD_TYPE"
            exit 1
            ;;

    esac
}

run_download() {
    parse_download_arguments "$@"
    validate_download_inputs
    execute_download
}