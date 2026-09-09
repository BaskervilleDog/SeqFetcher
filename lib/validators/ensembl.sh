#!/usr/bin/env bash

validators_ensembl::validate_ensembl_download() {

    [[ -z "$ENSEMBL_SPECIES" ]] &&
    {
        log_error "Ensembl FASTA requires --species"
        return "${EX_USAGE:-2}"
    }

    [[ -z "$ENSEMBL_TYPE" ]] &&
    {
        log_error "Ensembl FASTA requires --type"
        return "${EX_USAGE:-2}"
    }

    return 0
}