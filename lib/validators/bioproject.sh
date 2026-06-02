#!/usr/bin/env bash

validate_bioproject_srr() {

    [[ -z "$BIOPROJECT_ACCESSION" ]] &&
    {
        log_error "Must specify --bioproject PRJNAXXXXXX"
        exit 1
    }
}