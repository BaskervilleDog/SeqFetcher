#!/usr/bin/env bash

validators_sra::validate_sra_download() {

    [[ -z "$SRA_METHOD" ]] &&
    {
        log_error "Must specify --sra-method"
        return "${EX_USAGE:-2}"
    }

    [[ -z "$ACCESSION" &&
       -z "$ACCESSION_FILE" ]] &&
    {
        log_error "Must specify --sra-accession or --sra-accession-file"
        return "${EX_USAGE:-2}"
    }

    [[ -n "$ACCESSION_FILE" &&
       ! -f "$ACCESSION_FILE" ]] &&
    {
        log_error "SRA accession file not found: $ACCESSION_FILE"
        return "${EX_USAGE:-2}"
    }

    return 0
}