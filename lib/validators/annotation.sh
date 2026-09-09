#!/usr/bin/env bash

validators_annotation::validate_annotation_download() {

    # Same accession requirements as an assembly download.
    validators_assembly::validate_assembly_download || return $?

    local fmt
    IFS=',' read -ra _ann_fmts <<< "$ANNOTATION_FORMATS"
    for fmt in "${_ann_fmts[@]}"; do
        case "$fmt" in
            gff3|gtf|gbff) ;;
            *)
                log_error "Invalid --annotation-formats value: '$fmt' (allowed: gff3, gtf, gbff)"
                return "${EX_USAGE:-2}"
                ;;
        esac
    done

    return 0
}
