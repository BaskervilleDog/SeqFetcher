#!/usr/bin/env bash

validators_bioproject::validate_bioproject_srr() {

    [[ -z "$BIOPROJECT_ACCESSION" ]] &&
    {
        log_error "Must specify --bioproject PRJNAXXXXXX"
        return "${EX_USAGE:-2}"
    }

    return 0
}