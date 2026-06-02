#!/usr/bin/env bash

validate_sra_download() {

    [[ -z "$SRA_METHOD" ]] &&
    {
        log_error "Must specify --sra-method"
        exit 1
    }

    [[ -z "$ACCESSION" &&
       -z "$ACCESSION_FILE" ]] &&
    {
        log_error "Must specify --sra-accession or --sra-accession-file"
        exit 1
    }

    [[ -n "$ACCESSION_FILE" &&
       ! -f "$ACCESSION_FILE" ]] &&
    {
        log_error "SRA accession file not found: $ACCESSION_FILE"
        exit 1
    }
}