#!/usr/bin/env bash

commands_download::execute_download() {

    log_info "Starting download ($DOWNLOAD_TYPE)"

    case "$DOWNLOAD_TYPE" in
        assembly)      downloaders_assembly::run_assembly_download ;;
        annotation)    downloaders_annotation::run_annotation_download ;;
        gene)          downloaders_gene::run_gene_download ;;
        structure)     downloaders_structure::run_structure_download ;;
        sra)           downloaders_sra::run_sra_download ;;
        geo)           downloaders_geo::run_geo_download ;;
        ensembl-fasta) downloaders_ensembl::run_ensembl_download ;;
        transcriptome) downloaders_transcriptome::run_transcriptome_download ;;
        proteome)      downloaders_proteome::run_proteome_download ;;
        ortholog)      downloaders_ortholog::run_ortholog_download ;;
        *)
            log_error "Unknown download type: $DOWNLOAD_TYPE"
            return "${EX_USAGE:-2}"
            ;;
    esac
}

commands_download::run_download() {
    parsers_download::parse_download_arguments "$@"
    validators_download::validate_download_inputs || die "Invalid download arguments" "${EX_USAGE:-2}"

    manifest::init "$OUTDIR"
    manifest::set_context download "$@"

    local rc=0
    commands_download::execute_download || rc=$?

    local status="success"
    case "$rc" in
        0) status="success" ;;
        "${EX_PARTIAL:-7}") status="partial" ;;
        *) status="error" ;;
    esac

    manifest::add_run "$status" "$rc"
    manifest::emit "$status" "$rc"
    manifest::cleanup
    return "$rc"
}
