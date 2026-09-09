#!/usr/bin/env bash

validators_structure::validate_structure_download() {

    [[ -z "$STRUCTURE_ALPHAFOLD" && -z "$STRUCTURE_ALPHAFOLD_FILE" &&
       -z "$STRUCTURE_PDB"       && -z "$STRUCTURE_PDB_FILE" ]] &&
    {
        log_error "Structure download requires --alphafold / --alphafold-file / --pdb / --pdb-file"
        return "${EX_USAGE:-2}"
    }

    case "$STRUCTURE_FORMAT" in
        pdb|cif) ;;
        *)
            log_error "Invalid --format: $STRUCTURE_FORMAT (allowed: pdb, cif)"
            return "${EX_USAGE:-2}"
            ;;
    esac

    [[ -n "$STRUCTURE_ALPHAFOLD_FILE" && ! -f "$STRUCTURE_ALPHAFOLD_FILE" ]] &&
    {
        log_error "AlphaFold id file not found: $STRUCTURE_ALPHAFOLD_FILE"
        return "${EX_USAGE:-2}"
    }
    [[ -n "$STRUCTURE_PDB_FILE" && ! -f "$STRUCTURE_PDB_FILE" ]] &&
    {
        log_error "PDB id file not found: $STRUCTURE_PDB_FILE"
        return "${EX_USAGE:-2}"
    }

    # Inline PDB ids (from --pdb) must be 4 alphanumerics.
    if [[ -n "$STRUCTURE_PDB" ]]; then
        local id
        IFS=',' read -ra _pdb_ids <<< "$STRUCTURE_PDB"
        for id in "${_pdb_ids[@]}"; do
            id="${id// /}"
            [[ "$id" =~ ^[0-9A-Za-z]{4}$ ]] ||
            {
                log_error "Invalid PDB id: '$id' (expected 4 alphanumeric characters)"
                return "${EX_USAGE:-2}"
            }
        done
    fi

    return 0
}
