#!/usr/bin/env bash

validators_ensembl::validate_ensembl_download() {

    [[ -z "$ENSEMBL_SPECIES" ]] &&
    {
        log_error "Ensembl FASTA requires --species"
        exit 1
    }

    [[ -z "$ENSEMBL_TYPE" ]] &&
    {
        log_error "Ensembl FASTA requires --type"
        exit 1
    }

    return 0
}