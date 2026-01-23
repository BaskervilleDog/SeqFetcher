# SeqFetcher

A unified command-line tool for searching and downloading genomic data from multiple databases including NCBI, ENA, GEO, and Ensembl.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)

## Overview

SeqFetcher simplifies genomic data retrieval by providing a unified interface to multiple databases and data types.

### Key Features

✨ **Unified Interface** - Single command for all genomic data sources  
🚀 **Parallel Downloads** - Speed up large batch downloads  
🔍 **Smart Search** - Rank results by quality (RefSeq, reference genomes, assembly level)  
📊 **Rich Metadata** - Extract taxonomy and gene information  
✅ **Robust Validation** - MD5 checksums and file size verification  
🎯 **Multiple Sources** - NCBI, ENA, GEO, Ensembl support  
🧬 **Comprehensive Data** - Assemblies, genes, transcriptomes, proteomes, and sequencing reads

### Supported Data Sources

| Source | Data Types | Features |
|--------|------------|----------|
| **NCBI** | Assemblies, genes, SRA reads | Reference genomes, annotations |
| **ENA** | FASTQ files | Direct download, MD5 verification |
| **GEO** | Supplementary files, SRA links | Expression data, metadata |
| **Ensembl** | Transcriptomes, proteomes, FASTA | Latest releases, multiple species |

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
  - [Searching Genomes](#searching-genomes)
  - [Downloading Assemblies](#downloading-assemblies)
  - [Downloading Genes](#downloading-genes)
  - [Downloading SRA Data](#downloading-sra-data)
  - [Downloading from GEO](#downloading-from-geo)
  - [Downloading Transcriptomes](#downloading-transcriptomes)
  - [Downloading Proteomes](#downloading-proteomes)
  - [Downloading from Ensembl](#downloading-from-ensembl)
- [Common Workflows](#common-workflows)
- [File Formats](#file-formats)
- [Troubleshooting](#troubleshooting)

---

## Installation

### Prerequisites

| Tool | Required For | Installation |
|------|-------------|--------------|
| **NCBI Datasets** | Assembly/gene downloads | [Download](https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/) |
| **jq** | JSON parsing | `brew install jq` or `apt-get install jq` |
| **GNU Parallel** | Parallel downloads | `brew install parallel` or `apt-get install parallel` |
| **SRA Toolkit** | SRA downloads (optional) | [Download](https://github.com/ncbi/sra-tools/wiki/02.-Installing-SRA-Toolkit) |
| **wget/curl** | File downloads | Usually pre-installed |

### Install SeqFetcher

```bash
# Clone the repository
git clone https://github.com/BaskervilleDog/seqfetcher.git
cd seqfetcher

# Run installation
chmod +x install.sh
./install.sh

# Add to PATH
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

### Verify Installation

```bash
seqfetcher --help
```

---

## Quick Start

### Search for genomes

```bash
seqfetcher search --organism "Saccharomyces cerevisiae"
```

### Download a reference genome

```bash
seqfetcher download --accession GCF_000005845.2
```

### Download SRA data

```bash
seqfetcher download --sra-method fasterq --sra-accession SRR12345678
```

### Download from GEO

```bash
# Download supplementary files
seqfetcher download --geo GSE280953

# Extract SRA run list
seqfetcher geo-srr --geo GSE280953 --out runs.txt

# Download the sequencing data
seqfetcher download --sra-method fasterq --sra-accession-file runs.txt
```

### Download transcriptome

```bash
seqfetcher download --transcriptome --species homo_sapiens --source auto
```

---

## Usage Guide

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
- `--outdir` - Output directory (default: downloads)
- `--output` - Custom output filename

**Output Files:**
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

**Options:**
- `--assembly` - Assembly accession
- `--species` - Species name
- `--source` - ncbi | ensembl | auto (default: ncbi)
- `--type` - pep (default: pep)

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

## Common Workflows

### Workflow 1: Complete GEO Analysis

```bash
# Download GEO supplementary files
seqfetcher download --geo GSE280953

# Extract SRA accessions
seqfetcher geo-srr --geo GSE280953 --out runs.txt

# Download sequencing data
seqfetcher download --sra-method fasterq --sra-accession-file runs.txt
```

### Workflow 2: Comparative Genomics

```bash
# Search for organism
seqfetcher search --organism "Bacillus subtilis" --output assemblies.tsv

# Download multiple assemblies
seqfetcher download --accession-file assemblies.tsv --jobs 8
```

### Workflow 3: Gene Analysis

```bash
# Extract gene IDs from reference
seqfetcher search --organism "Mus musculus" --extract-genes

# Download the genes
seqfetcher download --gene-file downloads/gene_ids.txt --jobs 6
```

### Workflow 4: RNA-Seq Pipeline

```bash
# Download reference transcriptome
seqfetcher download --transcriptome --species homo_sapiens --source auto

# Download RNA-seq data
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

## Troubleshooting

### "datasets command not found"

**Solution:**
```bash
# macOS
conda install -c conda-forge ncbi-datasets-cli

# Linux
wget https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/latest/linux-amd64/datasets
chmod +x datasets
sudo mv datasets /usr/local/bin/
```

### "jq is required but not installed"

**Solution:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

### SRA downloads fail

**Try alternative method:**
```bash
# Try prefetch instead of fasterq
seqfetcher download --sra-method prefetch --sra-accession SRR12345678

# Or try ENA
seqfetcher download --sra-method ena --sra-accession SRR12345678
```

### Parallel downloads cause errors

**Reduce parallel jobs:**
```bash
seqfetcher download --accession-file list.txt --jobs 2
```

### MD5 checksum mismatch

Files are automatically re-downloaded. If persistent:
```bash
# Delete partial files and retry
rm -rf downloads/fastq/SRR12345678*
seqfetcher download --sra-method ena --sra-accession SRR12345678
```

---

## Performance Tips

### Large Batch Downloads

```bash
# Use multiple parallel jobs
seqfetcher download --accession-file large_list.txt --jobs 16

# Use prefetch for reliability
seqfetcher download --sra-accession-file runs.txt --sra-method prefetch
```

### Storage Requirements

| Data Type | Average Size |
|-----------|--------------|
| Bacterial genome | 5-10 MB |
| Human genome | 3 GB |
| SRA run (bacteria) | 500 MB - 5 GB |
| SRA run (human) | 20-100 GB |

---

## Command Reference

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

---

## Citation

If you use SeqFetcher in your research:

```
SeqFetcher: A unified CLI for genomic data retrieval
GitHub: https://github.com/BaskervilleDog/seqfetcher
```

---

## License

MIT License - see [LICENSE](LICENSE) file for details

---

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## Support

- **Issues**: [GitHub Issues](https://github.com/BaskervilleDog/seqfetcher/issues)
- **Documentation**: [Wiki](https://github.com/BaskervilleDog/seqfetcher/wiki)

---

## Changelog

### Version 1.0.0 (2026-01-22)
- Initial release
- NCBI assemblies, genes, SRA support
- ENA direct download
- GEO integration
- Ensembl transcriptome/proteome support
- Parallel download capability
- Interactive search mode