#!/usr/bin/env bash

validators_download::validate_download_inputs() {

    case "$DOWNLOAD_TYPE" in

        assembly)
            validators_assembly::validate_assembly_download
            ;;

        gene)
            validators_gene::validate_gene_download
            ;;

        sra)
            validators_sra::validate_sra_download
            ;;

        geo)
            validators_geo::validate_geo_download
            ;;

        ensembl-fasta)
            validators_ensembl::validate_ensembl_download
            ;;

        transcriptome)
            validators_transcriptome::validate_transcriptome_download
            ;;

        proteome)
            validators_proteome::validate_proteome_download
            ;;

        *)
            log_error "Unknown download type: $DOWNLOAD_TYPE"
            exit 1
            ;;

    esac
}