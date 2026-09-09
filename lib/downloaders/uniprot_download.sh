#!/usr/bin/env bash

# UniProt proteome download.
#
# UniProt's REST "stream" endpoint returns a whole proteome as one gzipped
# FASTA. It exposes no per-file checksum, so atomic_fetch writes atomically
# but cannot verify - re-runs skip on presence unless --force. The current
# release (e.g. 2026_03) comes back in the X-UniProt-Release header and is
# recorded for provenance; UniProt has no historical-release download, so
# --require-pinned only warns here.

UNIPROT_REST="https://rest.uniprot.org"

# downloaders_uniprot_download::download_proteome <UPID> <outdir>
downloaders_uniprot_download::download_proteome() {
    local upid="$1"
    local outdir="${2:-downloads}"

    [[ "$upid" =~ ^UP[0-9]{9}$ ]] || {
        die "Invalid UniProt proteome id: '$upid' (expected UP + 9 digits)" "${EX_USAGE:-2}"
    }
    downloaders_common::check_command curl || return "${EX_DEPENDENCY:-3}"
    downloaders_common::check_command jq   || return "${EX_DEPENDENCY:-3}"

    log_step "Downloading UniProt proteome $upid"

    local hdrs meta release organism ptype
    hdrs="$(mktemp)"
    meta="$(curl -fsS -D "$hdrs" "${UNIPROT_REST}/proteomes/${upid}" 2>/dev/null)" || {
        rm -f "$hdrs"
        log_error "UniProt has no proteome $upid (or the request failed)"
        return "${EX_NOTFOUND:-4}"
    }
    release="$(grep -i '^x-uniprot-release:' "$hdrs" | awk '{print $2}' | tr -d '\r')"
    rm -f "$hdrs"
    organism="$(jq -r '.taxonomy.scientificName // "unknown"' <<< "$meta")"
    ptype="$(jq -r '.proteomeType // "unknown"' <<< "$meta")"
    log_info "Proteome: $organism ($ptype)"
    [[ -n "$release" ]] && log_info "UniProt release: $release"

    if [[ "${REQUIRE_PINNED:-false}" == true ]]; then
        log_warning "UniProt cannot be pinned to a historical release; recording current release '$release'"
    fi

    local dest_dir="${outdir}/proteomes/uniprot/${upid}"
    local dest="${dest_dir}/${upid}.fasta.gz"
    local key="${upid}:proteome-uniprot"
    local url="${UNIPROT_REST}/uniprotkb/stream?query=proteome:${upid}&format=fasta&compressed=true"

    if downloaders_common::already_have "$dest" "$(manifest::stored_md5 "$key")"; then
        log_info "[$upid] already present - skipping (use --force to refetch)"
        manifest::record_run_only "$key" "$(jq -n --arg p "$dest" --arg o "$organism" \
            '{proteome_id:"'"$upid"'", type:"proteome", source:"uniprot", organism:$o, status:"skipped", files:[{path:$p}]}')"
        return 0
    fi

    local rc
    downloaders_common::atomic_fetch "$url" "$dest"; rc=$?
    if [[ $rc -ne 0 ]]; then
        manifest::record "$key" "$(jq -n '{proteome_id:"'"$upid"'", type:"proteome", source:"uniprot", status:"failed"}')"
        return "$rc"
    fi

    local nseq
    nseq="$(zcat "$dest" 2>/dev/null | grep -c '^>' || echo 0)"
    log_success "[$upid] downloaded $nseq sequences -> $dest"

    manifest::record "$key" "$(jq -n \
        --arg p "$dest" --arg u "$url" --arg o "$organism" \
        --arg rel "${release:-unknown}" \
        --arg md5 "${LAST_FETCH_MD5:-}" --argjson bytes "${LAST_FETCH_BYTES:-0}" \
        --argjson n "${nseq:-0}" \
        '{proteome_id:"'"$upid"'", type:"proteome", source:"uniprot",
          source_url:$u, organism:$o, db_release:("UniProt " + $rel),
          sequences:$n, status:"downloaded",
          files:[{path:$p, bytes:$bytes, md5:$md5}]}')"
    return 0
}

export -f downloaders_uniprot_download::download_proteome 2>/dev/null || true
