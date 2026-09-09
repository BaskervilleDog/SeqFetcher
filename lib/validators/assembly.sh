#!/usr/bin/env bash

validators_assembly::validate_assembly_download() {

    [[ -z "$ACCESSION" &&
       -z "$ACCESSION_FILE" ]] &&
    {
        log_error "Must specify --accession or --accession-file"
        return "${EX_USAGE:-2}"
    }

    [[ -n "$ACCESSION_FILE" &&
       ! -f "$ACCESSION_FILE" ]] &&
    {
        log_error "Accession file not found: $ACCESSION_FILE"
        return "${EX_USAGE:-2}"
    }

    return 0
}