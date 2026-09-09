#!/usr/bin/env bash

validators_search::validate_search_inputs() {

    case "$MODE" in
        assemblies|pdb|alphafold) ;;
        *)
            log_error "Invalid --mode: $MODE (expected assemblies, pdb, or alphafold)"
            return "${EX_USAGE:-2}"
            ;;
    esac

    [[ ! "$TOP_N" =~ ^[1-9][0-9]*$ ]] &&
    {
        log_error "Invalid --top: $TOP_N (expected a positive integer)"
        return "${EX_USAGE:-2}"
    }

    case "$MODE" in
        assemblies) validators_search::_validate_assemblies || return $? ;;
        pdb)        validators_search::_validate_pdb || return $? ;;
        alphafold)  validators_search::_validate_alphafold || return $? ;;
    esac

    # Default output table path (mode-specific). --output overrides.
    if [[ -z "$OUTPUT_FILE" ]]; then
        case "$MODE" in
            assemblies)
                OUTPUT_FILE="${OUTDIR}/tables/assemblies.tsv"
                [[ "$EXTRACT_GENES" == true ]] && OUTPUT_FILE="${OUTDIR}/tables/gene_ids.txt"
                ;;
            pdb)       OUTPUT_FILE="${OUTDIR}/tables/pdb_structures.tsv" ;;
            alphafold) OUTPUT_FILE="${OUTDIR}/tables/alphafold_structures.tsv" ;;
        esac
    fi

    return 0
}

validators_search::_validate_assemblies() {
    [[ -z "$ORGANISM" ]] &&
    {
        log_error "Missing --organism"
        return "${EX_USAGE:-2}"
    }
    return 0
}

validators_search::_validate_pdb() {
    [[ -z "$ORGANISM" && -z "$SEARCH_TEXT" && -z "$SEARCH_UNIPROT" && -z "$SEARCH_LIGAND" ]] &&
    {
        log_error "search --pdb needs at least one of --organism / --text / --uniprot / --ligand"
        return "${EX_USAGE:-2}"
    }

    if [[ -n "$SEARCH_METHOD" ]]; then
        case "${SEARCH_METHOD,,}" in
            x-ray|xray|em|cryo-em|nmr) ;;
            *)
                log_error "Invalid --method: $SEARCH_METHOD (expected x-ray, em, or nmr)"
                return "${EX_USAGE:-2}"
                ;;
        esac
    fi

    [[ -n "$SEARCH_MAX_RESOLUTION" && ! "$SEARCH_MAX_RESOLUTION" =~ ^[0-9]+(\.[0-9]+)?$ ]] &&
    {
        log_error "Invalid --max-resolution: $SEARCH_MAX_RESOLUTION (expected a number)"
        return "${EX_USAGE:-2}"
    }
    [[ -n "$SEARCH_MIN_CHAINS" && ! "$SEARCH_MIN_CHAINS" =~ ^[1-9][0-9]*$ ]] &&
    {
        log_error "Invalid --min-chains: $SEARCH_MIN_CHAINS (expected a positive integer)"
        return "${EX_USAGE:-2}"
    }

    local d
    for d in "$SEARCH_AFTER_DATE" "$SEARCH_BEFORE_DATE"; do
        [[ -n "$d" && ! "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] &&
        {
            log_error "Invalid date: $d (expected YYYY-MM-DD)"
            return "${EX_USAGE:-2}"
        }
    done

    if [[ -n "$SEARCH_SORT" ]]; then
        case "$SEARCH_SORT" in
            resolution|date|score) ;;
            *)
                log_error "Invalid --sort: $SEARCH_SORT (expected resolution, date, or score)"
                return "${EX_USAGE:-2}"
                ;;
        esac
    fi

    [[ -n "${SEARCH_GENE}${SEARCH_KEYWORD}${SEARCH_PROTEOME}${SEARCH_TAXON_ID}" || "$SEARCH_REVIEWED" == true ]] &&
        log_warning "--gene/--keyword/--proteome/--taxon-id/--reviewed are AlphaFold filters - ignored with --pdb"

    return 0
}

validators_search::_validate_alphafold() {
    [[ -z "$ORGANISM" && -z "$SEARCH_TAXON_ID" && -z "$SEARCH_TEXT" &&
       -z "$SEARCH_GENE" && -z "$SEARCH_KEYWORD" && -z "$SEARCH_PROTEOME" ]] &&
    {
        log_error "search --alphafold needs at least one of --organism / --taxon-id / --text / --gene / --keyword / --proteome"
        return "${EX_USAGE:-2}"
    }

    [[ -n "$SEARCH_TAXON_ID" && ! "$SEARCH_TAXON_ID" =~ ^[0-9]+$ ]] &&
    {
        log_error "Invalid --taxon-id: $SEARCH_TAXON_ID (expected a number)"
        return "${EX_USAGE:-2}"
    }
    [[ -n "$SEARCH_PROTEOME" && ! "$SEARCH_PROTEOME" =~ ^UP[0-9]{9}$ ]] &&
    {
        log_error "Invalid --proteome: $SEARCH_PROTEOME (expected UP + 9 digits)"
        return "${EX_USAGE:-2}"
    }

    [[ -n "${SEARCH_METHOD}${SEARCH_MAX_RESOLUTION}${SEARCH_UNIPROT}${SEARCH_LIGAND}${SEARCH_MIN_CHAINS}${SEARCH_SORT}" ]] &&
        log_warning "--method/--max-resolution/--uniprot/--ligand/--min-chains/--sort are PDB filters - ignored with --alphafold"

    return 0
}
