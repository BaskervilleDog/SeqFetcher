#!/usr/bin/env bash

validators_download::validate_download_inputs() {

    case "$DOWNLOAD_TYPE" in

        assembly)
            validators_assembly::validate_assembly_download
            ;;

        annotation)
            validators_annotation::validate_annotation_download
            ;;

        gene)
            validators_gene::validate_gene_download
            ;;

        structure)
            validators_structure::validate_structure_download
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

        ortholog)
            validators_ortholog::validate_ortholog_download
            ;;

        *)
            log_error "Unknown download type: $DOWNLOAD_TYPE"
            return "${EX_USAGE:-2}"
            ;;

    esac
}