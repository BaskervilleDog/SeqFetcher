#!/usr/bin/env bash

downloaders_sra::run_sra_download() {

    downloaders_common::prepare_download_environment

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
            downloaders_sra_download::download_sra_fasterq "$INPUT_FILE"
            ;;

        prefetch)
            downloaders_sra_download::download_sra_prefetch "$INPUT_FILE"
            ;;

        parallel)
            downloaders_sra_download::download_parallel_fastq "$INPUT_FILE"
            ;;

        ena)
            downloaders_ena_download::download_ena "$INPUT_FILE"
            ;;

    esac

    [[ -n "${tmp_sra:-}" ]] &&
        rm -f "$tmp_sra"

    downloaders_common::cleanup_temp
}