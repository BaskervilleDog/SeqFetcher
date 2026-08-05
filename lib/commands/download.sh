#!/usr/bin/env bash

commands_download::execute_download() {

    log_info \
        "Starting download ($DOWNLOAD_TYPE)"

    case "$DOWNLOAD_TYPE" in

        assembly)
            downloaders_assembly::run_assembly_download
            ;;

        gene)
            downloaders_gene::run_gene_download
            ;;

        sra)
            downloaders_sra::run_sra_download
            ;;

        geo)
            downloaders_geo::run_geo_download
            ;;

        ensembl-fasta)
            downloaders_ensembl::run_ensembl_download
            ;;

        transcriptome)
            downloaders_transcriptome::run_transcriptome_download
            ;;

        proteome)
            downloaders_proteome::run_proteome_download
            ;;
        *)
            log_error "Unknown download type: $DOWNLOAD_TYPE"
            exit 1
            ;;

    esac
}

commands_download::run_download() {
    parsers_download::parse_download_arguments "$@"
    validators_download::validate_download_inputs
    commands_download::execute_download
}