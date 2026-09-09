# Command Reference

Full usage guide for every SeqFetcher command. For installation and a
30-second quick start, see the [README](../README.md).

## Table of Contents

- [Global Options](#global-options)
- [Exit Codes](#exit-codes)
- [Machine-Readable Output (`--json`)](#machine-readable-output---json)
- [Lockfile (`seqfetcher.lock.json`)](#lockfile-seqfetcherlockjson)
- [Idempotency & Resume](#idempotency--resume)
- [Output Layout](#output-layout)
- [Searching Genomes](#searching-genomes)
- [Downloading Assemblies](#downloading-assemblies)
- [Downloading Annotation Only](#downloading-annotation-only)
- [Downloading Genes](#downloading-genes)
- [Downloading SRA Data](#downloading-sra-data)
- [Downloading from GEO](#downloading-from-geo)
- [SRA runinfo (`sra-info`)](#sra-runinfo-sra-info)
- [Downloading Transcriptomes](#downloading-transcriptomes)
- [Downloading Proteomes](#downloading-proteomes)
- [Downloading Structures](#downloading-structures)
- [Downloading from Ensembl](#downloading-from-ensembl)
- [Downloading Orthologs](#downloading-orthologs)
- [Common Workflows](#common-workflows)
- [File Formats](#file-formats)
- [Full Option Reference](#full-option-reference)

---

## Global Options

These go **before** the command (`seqfetcher [global options] <command> …`)
and apply to every command:

| Option | Effect |
|--------|--------|
| `--json` | Emit one machine-readable result object on **stdout**. All logs go to stderr, so `seqfetcher --json … 2>/dev/null \| jq .` yields clean JSON. |
| `--quiet`, `-q` | Silence `[INFO]`/`[STEP]`/`[SUCCESS]`; warnings and errors still print. |
| `--no-color` | Disable ANSI colour (also honoured via the `NO_COLOR` env var and auto-off when stderr is not a TTY). |
| `--force` | Re-download even when the lockfile already records the artifact as complete. |
| `--require-pinned` | Refuse any source that would resolve to "latest" (currently: Ensembl without `--release`). Exits `2`. |
| `--version` | Print the version and exit. |

**stdout vs stderr:** stdout carries only the payload — the ranked table
(`search`), the run list (`geo-srr`/`bp-srr`), or the `--json` object.
Everything else (progress, warnings, errors, summaries) is on stderr.

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Unexpected / internal error |
| `2` | Usage error - bad flag, missing required option, unknown command |
| `3` | A required external tool is missing (`datasets`, `jq`, …) |
| `4` | Valid query, but the upstream source has no data |
| `5` | Network / API / download failure after retries |
| `6` | Checksum or size mismatch on a downloaded file |
| `7` | Batch partial - some items downloaded, some failed |

A batch (`--accession-file`, `--sra-accession-file`, …) exits `7` when it
finishes with a mix of successes and failures, `5` when everything failed,
`0` when everything succeeded (or was already present).

## Machine-Readable Output (`--json`)

`download` emits:

```json
{
  "seqfetcher_version": "1.1.0",
  "command": "download",
  "status": "success | partial | error",
  "exit_code": 0,
  "outdir": "downloads",
  "lockfile": "downloads/seqfetcher.lock.json",
  "counts": { "total": 3, "downloaded": 2, "skipped": 1, "failed": 0 },
  "items": [
    { "key": "GCF_000005845.2:assembly", "accession": "GCF_000005845.2",
      "type": "assembly", "source": "ncbi-datasets", "status": "downloaded",
      "files": [ { "path": "...", "bytes": 12345678, "md5": "..." } ] }
  ]
}
```

`search` emits `{ command, status, organism, count, assemblies: [...], files: {table, accessions, taxonomy} }`.
`geo-srr` / `bp-srr` / `sra-info` emit `{ command, status, count, runs: [...], files: {run_list, metadata_tsv} }`.
A usage error under `--json` still prints `{ "status": "error", "exit_code": 2, "errors": [...] }`.

## Lockfile (`seqfetcher.lock.json`)

Every run writes a merged lockfile at `<outdir>/seqfetcher.lock.json`:

```json
{
  "schema": 1,
  "seqfetcher_version": "1.1.0",
  "runs": [
    { "command": "download", "argv": ["--accession","GCF_000005845.2"],
      "started_at": "...", "finished_at": "...", "status": "success",
      "exit_code": 0,
      "tool_versions": { "seqfetcher": "1.1.0", "datasets": "18.36.0", "jq": "1.8.2", "curl": "8.22.0" } }
  ],
  "artifacts": {
    "GCF_000005845.2:assembly": {
      "accession": "GCF_000005845.2", "type": "assembly",
      "source": "ncbi-datasets", "db_release": "Ensembl 116 | n/a",
      "status": "downloaded", "requested_at": "...",
      "files": [ { "path": "...", "bytes": 123, "md5": "..." } ],
      "tool": { "datasets": "18.36.0" }
    }
  }
}
```

It is the download **checkpoint**: re-running a command skips any artifact
already recorded `downloaded` (whose file, if single-file, still matches its
recorded checksum). Commit it alongside a pipeline for reproducibility.

## Idempotency & Resume

Downloads are **idempotent by default**. Re-running a `download` skips work
that is already present and verified; a batch that partly failed retries
only the missing items on the next run. `--force` ignores the lockfile and
re-downloads everything.

Writes are **atomic**: a file is fetched to `<name>.part` and renamed only
after (where a checksum is available) verification; `datasets` archives are
extracted in a staging dir under `--outdir`'s temp area and moved into place
in one step. A killed job never leaves a half-written file or a
half-extracted directory at the real path.

### Reproducibility / release pinning

- **NCBI assemblies** are version-pinned by their accession (`GCF_x.N`); the
  `datasets` CLI version is recorded per run.
- **Ensembl** resolves to the latest release unless you pass `--release N`.
  An unpinned run prints a warning and records the release it resolved to;
  `--require-pinned` turns the warning into a hard error.

---

## Output Layout

Every command writes under `--outdir` (default `downloads/`). Tables and
accession/run lists - anything you'd open in a spreadsheet or feed back
into another `seqfetcher` command as an `--*-file` argument, not sequence
data - are kept separate from downloaded files, under `tables/`:

```
downloads/
├── tables/                              search, geo-srr, and bp-srr output
│   ├── taxonomy_metadata.tsv              search
│   ├── assemblies.tsv                     search
│   ├── assemblies_accessions.txt          search
│   ├── gene_ids.txt                       search --extract-genes
│   ├── gene_ids_metadata.tsv              search --extract-genes
│   ├── GEO_SRR_list.txt                   geo-srr
│   ├── GEO_SRR_list_metadata.tsv          geo-srr
│   ├── BioProject_SRR_list.txt            bp-srr
│   ├── BioProject_SRR_list_metadata.tsv   bp-srr
│   ├── sra_runinfo.tsv                    sra-info
│   └── sra_runinfo_runs.txt               sra-info
├── <ACCESSION>/                         download --accession(-file)
├── annotations/<ACCESSION>/             download --annotation
├── batch_N_genes_X_to_Y/                download --gene-id / --gene-file
├── fastq/                               download --sra-method ...
├── metadata/<GSE>/                      download --geo (supplementary files)
├── transcriptomes/<accession-or-species>/...   download --transcriptome
├── proteomes/<accession-or-species>/...        download --proteome --source ncbi|ensembl
├── proteomes/uniprot/<UPID>/            download --proteome --source uniprot
├── structures/alphafold/               download --structure --alphafold
├── structures/pdb/                     download --structure --pdb
├── ensembl/<species>/<type>/            download --ensembl-fasta
└── orthologs/<accession>/               download --ortholog(-file)
```

`--output`/`--out` still take any filename or path you give them as-is
(absolute, or starting with `./`) - the `tables/` nesting is only what
happens when you don't override it.

---

### Searching Genomes

#### Basic Search

```bash
seqfetcher search --organism "Homo sapiens"
```

**Output:**
```
[STEP] Searching NCBI assemblies for: Homo sapiens
Found 50000+ assemblies in NCBI
Showing top 50 assemblies (ranked: GCF + reference first)

ID   ACCESSION          ORGANISM           LEVEL        STATUS      REFSEQ_CATEGORY    NAME
---- ------------------ ------------------ ------------ ----------- ------------------ ----------
1    GCF_000001405.40  Homo sapiens       Chromosome   Complete    reference genome   GRCh38.p14
...
```

**Options:**
- `--organism` - Scientific name (required)
- `--top` - Number of top-ranked assemblies to display and write to the table (default: 50)
- `--outdir` - Output directory (default: downloads)
- `--output` - Custom output filename

**Output Files** (see [Output Layout](#output-layout) - all under `tables/`):
- `assemblies.tsv` - Full assembly metadata
- `assemblies_accessions.txt` - Accession numbers only
- `taxonomy_metadata.tsv` - Taxonomic information

#### Interactive Mode

```bash
seqfetcher search --organism "Salmonella enterica" --interactive
```

Select specific assemblies to download:
```
Enter assembly IDs to download (comma or space separated, or ranges like 1-5)
Example: 1,3,5 or 1 3 5 or 1-5
IDs: 1-3,7
```

#### Extract Gene IDs

```bash
seqfetcher search --organism "Bacillus subtilis" --extract-genes
```

Outputs gene IDs and metadata from the reference genome.

---

### Downloading Assemblies

#### Single Assembly

```bash
seqfetcher download --accession GCF_000005845.2
```

**Downloaded files include:**
- Genome sequences (FASTA)
- GFF3 annotations
- GTF annotations
- CDS sequences
- Protein sequences

#### Multiple Assemblies

```bash
# Create accession list
cat > assemblies.txt << EOF
GCF_000005845.2
GCF_000008865.2
GCF_000742135.1
EOF

# Download in parallel (8 jobs)
seqfetcher download --accession-file assemblies.txt --jobs 8
```

### Downloading Annotation Only

Fetch GFF3/GTF (and optionally GBFF) for an assembly **without** the genome
FASTA - `datasets` with a restricted `--include`.

```bash
seqfetcher download --annotation --accession GCF_000009045.1
seqfetcher download --annotation --accession-file accs.txt --annotation-formats gff3
```

**Options:**
- `--annotation` - select annotation-only mode (wins over `--assembly` in any order)
- `--annotation-formats` - comma-separated, subset of `gff3,gtf,gbff` (default `gff3,gtf`)

Output: `<outdir>/annotations/<ACCESSION>/`; lockfile key `<ACCESSION>:annotation`.

---

### Downloading Genes

#### By Gene ID

```bash
# Single gene
seqfetcher download --gene-id 945803

# Multiple genes (comma-separated)
seqfetcher download --gene-id 945803,944742,945006
```

#### From File

```bash
# Create gene ID file
cat > genes.txt << EOF
945803
944742
945006
EOF

# Download
seqfetcher download --gene-file genes.txt --jobs 4
```

---

### Downloading SRA Data

SeqFetcher supports four methods for downloading sequencing reads:

| Method | Speed | Reliability | Best For |
|--------|-------|-------------|----------|
| `fasterq` | ⚡⚡ Fast | Good | Quick downloads, small datasets |
| `prefetch` | ⚡ Moderate | ⭐⭐⭐ Excellent | Most reliable, large datasets |
| `parallel` | ⚡⚡⚡ Fastest | Good | High-performance systems |
| `ena` | ⚡⚡ Fast | ⭐⭐ Very good | Alternative source, MD5 verification |

#### Method 1: fasterq-dump

```bash
seqfetcher download --sra-method fasterq --sra-accession SRR12345678
```

Direct streaming download with automatic compression.

#### Method 2: prefetch

```bash
seqfetcher download --sra-method prefetch --sra-accession SRR12345678
```

Two-stage download (prefetch → convert) - most reliable for large files.

#### Method 3: parallel-fastq-dump

```bash
seqfetcher download --sra-method parallel --sra-accession SRR12345678
```

Multi-threaded download - fastest option.

#### Method 4: ENA

```bash
seqfetcher download --sra-method ena --sra-accession SRR12345678
```

Download from European servers with MD5 verification.

#### Batch Downloads

```bash
# Create run list
cat > sra_runs.txt << EOF
SRR12345678
SRR12345679
SRR12345680
EOF

# Download all
seqfetcher download --sra-method prefetch --sra-accession-file sra_runs.txt
```

**Supported accessions:** SRR, ERR, DRR, SRP, PRJNA, PRJEB, GSE

---

### Downloading from GEO

#### Download Supplementary Files

```bash
seqfetcher download --geo GSE280953
```

Downloads all supplementary files from a GEO series.

#### Extract SRA Run List

```bash
# Extract SRR accessions to file
seqfetcher geo-srr --geo GSE280953 --out my_runs.txt
```

#### Complete GEO Workflow

```bash
# Step 1: Download supplementary files
seqfetcher download --geo GSE280953

# Step 2: Extract SRA run accessions
seqfetcher geo-srr --geo GSE280953 --out runs.txt

# Step 3: Download sequencing data
seqfetcher download --sra-method fasterq --sra-accession-file runs.txt
```

---

### SRA runinfo (`sra-info`)

Fetch the SRA **runinfo table** - one row per run with library / instrument /
spot-count / BioSample metadata - for any SRA-resolvable accession, **without
downloading the reads**. `geo-srr` and `bp-srr` produce this as a side effect
for GEO series and BioProjects respectively; `sra-info` exposes it directly.

```bash
seqfetcher sra-info --accession SRP012482
seqfetcher sra-info --accession PRJNA231221,SRP012482 --out runs.txt
seqfetcher sra-info --accession-file accessions.txt --outdir study_meta
```

Accepts **SRR/ERR/DRR, SRX, SRP/ERP/DRP and BioProject (PRJNA/PRJEB/PRJDB)** -
anything searchable in the NCBI SRA database. Resolution is at the SRA
*experiment* level: a run accession returns that run **and its siblings in the
same experiment**.

**Options:**
- `--accession ACC[,ACC,...]` - one or more accessions (required unless `--accession-file`)
- `--accession-file FILE` - one accession per line
- `--out FILE` - run-list filename (default `sra_runinfo_runs.txt`)
- `--outdir DIR` - output directory

**Output** (under `<outdir>/tables/`):
- `sra_runinfo.tsv` - full runinfo table
- `sra_runinfo_runs.txt` - run accessions, one per line

`--json` → `{ command: "sra-info", count, runs: [...], files: {run_list, metadata_tsv} }`.
Exit `4` when nothing resolves.

---

### Downloading Transcriptomes

#### From Assembly

```bash
seqfetcher download --transcriptome --assembly GCF_000001405.40
```

#### From Species

```bash
# Auto-detect best source (tries NCBI, then Ensembl)
seqfetcher download --transcriptome --species homo_sapiens --source auto
```

#### Specify Source and Type

```bash
# Download from Ensembl
seqfetcher download --transcriptome \
  --species mus_musculus \
  --source ensembl \
  --type cdna
```

**Options:**
- `--assembly` - Assembly accession (GCF/GCA)
- `--species` - Species name (e.g., homo_sapiens)
- `--source` - ncbi | ensembl | auto (default: ncbi)
- `--type` - cdna | cds | ncrna (default: cdna)

---

### Downloading Proteomes

#### From Assembly

```bash
seqfetcher download --proteome --assembly GCF_000001405.40
```

#### From Species

```bash
seqfetcher download --proteome --species drosophila_melanogaster --source auto
```

#### From UniProt (whole reference proteome, one gzipped FASTA)

```bash
seqfetcher download --proteome --proteome-id UP000005640
```

`--proteome-id` implies `--source uniprot`. The FASTA comes from the UniProt
REST stream endpoint; the current UniProt release (e.g. `2026_03`) is
recorded as `db_release` in the lockfile. UniProt has no historical-release
download, so `--require-pinned` only warns.

**Options:**
- `--assembly` - Assembly accession (source ncbi/ensembl/auto)
- `--species` - Species name (source ensembl/auto)
- `--source` - ncbi | ensembl | auto | uniprot (default: ncbi)
- `--proteome-id` - UniProt proteome id `UPXXXXXXXXX` (source uniprot)
- `--type` - pep (default: pep; ncbi/ensembl only)

Output: `<outdir>/proteomes/uniprot/<UPID>/<UPID>.fasta.gz`.

---

### Downloading Structures

Fetch predicted (AlphaFold) or experimental (RCSB PDB) protein structures by
explicit id. One `--structure` type; give AlphaFold **UniProt accessions** and
PDB **4-character ids**.

```bash
# AlphaFold models (mmCIF) for two UniProt accessions
seqfetcher download --structure --alphafold P04637,P0DP23 --format cif

# RCSB PDB structures
seqfetcher download --structure --pdb 1TUP,4HHB
seqfetcher download --structure --pdb-file ids.txt
```

**Options:**
- `--alphafold` / `--alphafold-file` - UniProt accessions (comma list / file)
- `--pdb` / `--pdb-file` - PDB ids (comma list / file)
- `--format` - `pdb` (default) or `cif`

Output: `<outdir>/structures/alphafold/AF-<ACC>-F1-model_v<N>.<fmt>` and
`<outdir>/structures/pdb/<ID>.<fmt>`. AlphaFold model version is recorded as
`db_release`; PDB ids are immutable. A batch with a mix of hits and misses
exits `7`; an id with no structure exits `4`.

---

### Downloading from Ensembl

Download FASTA files directly from Ensembl FTP:

```bash
# Download human cDNA sequences
seqfetcher download --ensembl-fasta --species homo_sapiens --type cdna

# Download mouse proteins from specific release
seqfetcher download --ensembl-fasta \
  --species mus_musculus \
  --type pep \
  --release 110
```

**Sequence types:**
- `cdna` - cDNA sequences
- `cds` - Coding sequences
- `dna` - Genomic DNA
- `ncrna` - Non-coding RNA
- `pep` - Peptide sequences

---

### Downloading Orthologs

Given a gene (as a protein/nucleotide accession or a numeric Gene ID),
resolve it to its NCBI Gene ID via Entrez and download every known
ortholog's protein sequence as one deduplicated FASTA.

```bash
# By RefSeq protein accession
seqfetcher download --ortholog NP_001416352.1

# By RefSeq nucleotide accession
seqfetcher download --ortholog NM_001429423.1

# By numeric Gene ID
seqfetcher download --ortholog 672

# Multiple accessions/Gene IDs (comma-separated)
seqfetcher download --ortholog NP_001416352.1,672

# From a file (one per line), 8 in parallel
seqfetcher download --ortholog-file genes.txt --jobs 8
```

**Options:**
- `--ortholog ACC[,ACC,...]` - Accession(s) or Gene ID(s)
- `--ortholog-file FILE` - File with one accession/Gene ID per line
- `--jobs, -j NUM` - Parallel accessions (default: 4)

**Accepted formats:**
- `NP_` / `XP_` / `WP_` - RefSeq protein accessions
- `NM_` / `XM_` / `NG_` - RefSeq nucleotide accessions
- Numeric - NCBI Gene IDs

**Output:** `downloads/orthologs/<accession>/orthologs_<gene_id>.fasta`

**Limitations** (inherited from the NCBI Datasets ortholog API, not
something SeqFetcher can work around):
- Coverage is vertebrates and insects only - other taxa return 0 orthologs.
- The raw API response has been observed to cap around ~499 records;
  SeqFetcher warns when a result's raw count lands right at that mark,
  since it may mean the set is truncated. A large result well past that
  (thousands of sequences for a big gene family, say) is not a truncation
  signal and isn't flagged.

**Optional:** set `NCBI_API_KEY` to raise the Entrez rate limit from 3 to
10 requests/second (register free at
[ncbi.nlm.nih.gov/account](https://www.ncbi.nlm.nih.gov/account/)):

```bash
export NCBI_API_KEY=your_key_here
```

---

## Common Workflows

### Workflow 1: Complete GEO Analysis

```bash
seqfetcher download --geo GSE280953
seqfetcher geo-srr --geo GSE280953 --out runs.txt
seqfetcher download --sra-method fasterq --sra-accession-file runs.txt
```

### Workflow 2: Comparative Genomics

```bash
seqfetcher search --organism "Bacillus subtilis" --output assemblies.tsv
seqfetcher download --accession-file assemblies.tsv --jobs 8
```

### Workflow 3: Gene Analysis

```bash
seqfetcher search --organism "Mus musculus" --extract-genes
seqfetcher download --gene-file downloads/tables/gene_ids.txt --jobs 6
```

### Workflow 4: RNA-Seq Pipeline

```bash
seqfetcher download --transcriptome --species homo_sapiens --source auto
seqfetcher download --sra-method prefetch --sra-accession-file rnaseq_runs.txt
```

---

## File Formats

### Assembly Metadata (TSV)

```tsv
ACCESSION       ORGANISM                LEVEL       STATUS      REFSEQ_CATEGORY     NAME
GCF_000005845.2 Escherichia coli str... Chromosome  Complete    reference genome    ASM584v2
```

### Gene Metadata (TSV)

```tsv
EntrezID  Symbol  GeneID          Chromosome  Start    End      Strand  GeneType
945803    thrL    gene-b0001      NC_000913.3 190      255      +       protein_coding
```

### SRR List (TXT)

```
SRR12345678
SRR12345679
SRR12345680
```

---

## Full Option Reference

### Search Command

```bash
seqfetcher search --organism "ORGANISM" [OPTIONS]
```

**Options:**
- `--organism "NAME"` - Organism name (required)
- `--outdir DIR` - Output directory
- `--output FILE` - Custom output file
- `--interactive, -i` - Interactive selection mode
- `--extract-genes` - Extract gene IDs

### Download Command

```bash
seqfetcher download [OPTIONS]
```

**Assembly Options:**
- `--accession ACC` - Single assembly
- `--accession-file FILE` - Multiple assemblies

**Gene Options:**
- `--gene-id ID[,ID,...]` - Gene IDs
- `--gene-file FILE` - Gene ID file

**SRA Options:**
- `--sra-method METHOD` - fasterq | prefetch | parallel | ena
- `--sra-accession ACC` - Single SRA accession
- `--sra-accession-file FILE` - SRA accession file

**GEO Options:**
- `--geo GSEXXXXX` - GEO series accession

**Ensembl Options:**
- `--ensembl-fasta` - Download from Ensembl FTP
- `--species NAME` - Species name
- `--type TYPE` - cdna | cds | dna | ncrna | pep
- `--release NUM` - Ensembl release number

**Transcriptome Options:**
- `--transcriptome` - Download transcriptome
- `--assembly ACC` - Assembly accession
- `--species NAME` - Species name
- `--source SOURCE` - ncbi | ensembl | auto
- `--type TYPE` - cdna | cds | ncrna

**Proteome Options:**
- `--proteome` - Download proteome
- `--assembly ACC` - Assembly accession
- `--species NAME` - Species name
- `--source SOURCE` - ncbi | ensembl | auto

**Ortholog Options:**
- `--ortholog ACC[,ACC,...]` - Accession(s) or Gene ID(s)
- `--ortholog-file FILE` - File with one accession/Gene ID per line

**General Options:**
- `--outdir DIR` - Output directory
- `--jobs, -j NUM` - Parallel jobs (default: 4)

### GEO-SRR Command

```bash
seqfetcher geo-srr --geo GSEXXXXX [OPTIONS]
```

**Options:**
- `--geo GSEXXXXX` - GEO series accession
- `--out FILE` - Output file (default: SRR_list.txt)
- `--outdir DIR` - Output directory

### BP-SRR Command

```bash
seqfetcher bp-srr --bioproject PRJNAXXXXXX [OPTIONS]
```

**Options:**
- `--bioproject PRJNAXXXXXX` - BioProject accession (required)
- `--out FILE` - Output file (default: SRR_list.txt)
- `--outdir DIR` - Output directory
