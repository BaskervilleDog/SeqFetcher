#!/usr/bin/env bash

run_sra_download() {

    prepare_download_environment

    mkdir -p "$OUTDIR/fastq"

    if [[ -n "$ACCESSION" ]]; then

        tmp_sra=$(mktemp)

        echo "$ACCESSION" > "$tmp_sra"

        INPUT_FILE="$tmp_sra"

    else

        INPUT_FILE="$ACCESSION_FILE"

    fi

    export THREADS

    case "$SRA_METHOD" in

        fasterq)
            download_sra_fasterq "$INPUT_FILE"
            ;;

        prefetch)
            download_sra_prefetch "$INPUT_FILE"
            ;;

        parallel)
            download_parallel_fastq "$INPUT_FILE"
            ;;

        ena)
            download_ena "$INPUT_FILE"
            ;;

    esac

    [[ -n "${tmp_sra:-}" ]] &&
        rm -f "$tmp_sra"

    cleanup_temp
}