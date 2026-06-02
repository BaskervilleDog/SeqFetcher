#!/usr/bin/env bash

validate_download_inputs() {

    case "$DOWNLOAD_TYPE" in

        assembly)
            validate_assembly_download
            ;;

        gene)
            validate_gene_download
            ;;

        sra)
            validate_sra_download
            ;;

        geo)
            validate_geo_download
            ;;

        ensembl-fasta)
            validate_ensembl_download
            ;;

        transcriptome)
            validate_transcriptome_download
            ;;

        proteome)
            validate_proteome_download
            ;;

        *)
            log_error "Unknown download type: $DOWNLOAD_TYPE"
            exit 1
            ;;

    esac
}