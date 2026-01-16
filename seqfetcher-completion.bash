#!/usr/bin/env bash

_seqfetcher_completions() {
    local cur prev words cword
    _init_completion || return

    COMMANDS="discover download convert check help"
    DISCOVER_SUB="assembly"
    DOWNLOAD_SUB="fastq genome"
    CONVERT_SUB="geo-to-srr"

    case "${words[1]}" in
        discover)
            COMPREPLY=( $(compgen -W "$DISCOVER_SUB" -- "$cur") )
            ;;
        download)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "$DOWNLOAD_SUB" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "--accessions --source --method --organism --assembly" -- "$cur") )
            fi
            ;;
        convert)
            COMPREPLY=( $(compgen -W "$CONVERT_SUB --geo --out" -- "$cur") )
            ;;
        *)
            COMPREPLY=( $(compgen -W "$COMMANDS" -- "$cur") )
            ;;
    esac
}

complete -F _seqfetcher_completions seqfetcher
