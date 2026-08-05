#!/usr/bin/env bash

validators_assembly::validate_assembly_download() {

    [[ -z "$ACCESSION" &&
       -z "$ACCESSION_FILE" ]] &&
    {
        log_error "Must specify --accession or --accession-file"
        exit 1
    }

    [[ -n "$ACCESSION_FILE" &&
       ! -f "$ACCESSION_FILE" ]] &&
    {
        log_error "Accession file not found: $ACCESSION_FILE"
        exit 1
    }

    return 0
}