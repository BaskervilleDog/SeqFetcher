---
title: "seqfetcher"
output: github_document
---

# SeqFetcher

A unified command-line tool for searching and downloading genomic data from NCBI and ENA databases.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)

## Overview

SeqFetcher simplifies the process of searching and downloading genomic data by providing a unified interface to:

- **NCBI Datasets**: Search and download genome assemblies, genes, and annotations
- **SRA Toolkit**: Download sequencing reads using multiple methods
- **ENA**: Download FASTQ files directly from the European Nucleotide Archive

### Key Features

✨ **Unified Interface** - Single command for all genomic data sources  
🚀 **Parallel Downloads** - Speed up large batch downloads  
🔍 **Smart Search** - Rank results by quality (RefSeq, reference genomes, assembly level)  
📊 **Rich Metadata** - Extract taxonomy and gene information  
✅ **Robust Validation** - MD5 checksums and file size verification  
🎯 **Multiple Methods** - Choose the best download strategy for your needs

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
  - [Searching Genomes](#searching-genomes)
  - [Downloading Assemblies](#downloading-assemblies)
  - [Downloading Genes](#downloading-genes)
  - [Downloading SRA Data](#downloading-sra-data)
  - [Downloading from ENA](#downloading-from-ena)
- [Advanced Usage](#advanced-usage)
- [File Formats](#file-formats)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Installation

### Prerequisites

SeqFetcher requires the following tools:

| Tool | Required For | Installation |
|------|-------------|--------------|
| **NCBI Datasets** | Assembly/gene downloads | [Download](https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/) |
| **jq** | JSON parsing | `brew install jq` or `apt-get install jq` |
| **GNU Parallel** | Parallel downloads | `brew install parallel` or `apt-get install parallel` |
| **SRA Toolkit** | SRA downloads (optional) | [Download](https://github.com/ncbi/sra-tools/wiki/02.-Installing-SRA-Toolkit) |
| **wget/curl** | ENA downloads | Usually pre-installed |

### Install SeqFetcher

```bash
# Clone or download the repository
git clone https://github.com/yourusername/seqfetcher.git
cd seqfetcher

# Run the installation script
chmod +x install.sh
./install.sh

# Add to PATH (if needed)
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

### Verify Installation

```bash
seqfetcher --help
```

---

## Quick Start

### Example 1: Search for E. coli genomes

```bash
seqfetcher search --organism "Escherichia coli"
```

**Output:**
```
[STEP] Searching NCBI assemblies for: Escherichia coli
Found 50000+ assemblies in NCBI
Showing top 50 assemblies (ranked: GCF + reference first)

ID   ACCESSION          ORGANISM                       LEVEL        STATUS      REFSEQ_CATEGORY    NAME
---- ------------------ ------------------------------ ------------ ----------- ------------------ --------
1    GCF_000005845.2   Escherichia coli str. K-12     Chromosome   Complete    reference genome   ASM584v2
2    GCF_000008865.2   Escherichia coli O157:H7       Chromosome   Complete    representative     ASM886v2
...
```

### Example 2: Download a reference genome

```bash
seqfetcher download --accession GCF_000005845.2
```

### Example 3: Download multiple assemblies in parallel

```bash
# Create accession list
echo -e "GCF_000005845.2\nGCF_000008865.2\nGCF_000742135.1" > accessions.txt

# Download with 8 parallel jobs
seqfetcher download --accession-file accessions.txt --jobs 8
```

### Example 4: Download SRA data

```bash
seqfetcher download --sra-accession SRR12345678 --sra-method fasterq
```

---

## Usage Guide

### Searching Genomes

#### Basic Search

```bash
seqfetcher search --organism "ORGANISM_NAME"
```

**Options:**
- `--organism`: Scientific name (e.g., "Homo sapiens", "Escherichia coli")
- `--outdir`: Output directory (default: `downloads`)
- `--output`: Custom output file name

**Output Files:**
- `assemblies.tsv`: Full assembly metadata table
- `assemblies_accessions.txt`: List of accession numbers only
- `taxonomy_metadata.tsv`: Taxonomic classification

#### Interactive Mode

```bash
seqfetcher search --organism "Salmonella enterica" --interactive
```

Interactive mode lets you select specific assemblies to download immediately:

```
Enter assembly IDs to download (comma or space separated, or ranges like 1-5)
Example: 1,3,5 or 1 3 5 or 1-5
IDs: 1-3,7
```

#### Extract Gene IDs from Reference

```bash
seqfetcher search --organism "Bacillus subtilis" --extract-genes
```

**Output Files:**
- `gene_ids.txt`: List of Entrez Gene IDs
- `gene_ids_metadata.tsv`: Full gene metadata (symbol, location, type)

**Metadata columns:**
- EntrezID, Symbol, GeneID, Chromosome, Start, End, Strand, GeneType

---

### Downloading Assemblies

#### Single Assembly

```bash
seqfetcher download --accession GCF_000005845.2
```

**Downloaded data includes:**
- Genome sequences (FASTA)
- GFF3 annotations
- GTF annotations
- CDS sequences
- Protein sequences

#### Multiple Assemblies (Batch)

```bash
# Create accession file
cat > accessions.txt << EOF
GCF_000005845.2
GCF_000008865.2
GCF_000742135.1
EOF

# Download in parallel
seqfetcher download --accession-file accessions.txt --jobs 4
```

**Options:**
- `--jobs`, `-j`: Number of parallel downloads (default: 4)
- `--outdir`: Output directory (default: `downloads`)

**Output structure:**
```
downloads/
├── GCF_000005845.2/
│   └── ncbi_dataset/
│       └── data/
│           └── GCF_000005845.2/
│               ├── genomic.fna
│               ├── genomic.gff
│               ├── genomic.gtf
│               ├── cds_from_genomic.fna
│               └── protein.faa
├── GCF_000008865.2/
└── GCF_000742135.1/
```

---

### Downloading Genes

#### By Gene ID (Entrez ID)

```bash
# Single gene
seqfetcher download --gene-id 945803

# Multiple genes
seqfetcher download --gene-id 945803,944742,945006
```

#### From Gene File

```bash
# Create gene file
cat > genes.txt << EOF
945803
944742
945006
947498
EOF

# Download
seqfetcher download --gene-file genes.txt --jobs 4
```

**Options:**
- `--jobs`, `-j`: Parallel batch downloads (default: 4)

**Output includes:**
- Gene sequences
- RNA sequences
- Protein sequences
- CDS sequences
- Product reports

**Note:** Genes are downloaded in batches of 500 to optimize API usage.

---

### Downloading SRA Data

SeqFetcher supports **four methods** for downloading SRA sequencing data:

| Method | Speed | Reliability | Use Case |
|--------|-------|-------------|----------|
| `fasterq` | ⚡⚡ Fast | Good | Quick downloads, small datasets |
| `prefetch` | ⚡ Moderate | ⭐⭐⭐ Excellent | Most reliable, large datasets |
| `parallel` | ⚡⚡⚡ Fastest | Good | High-performance systems |
| `ena` | ⚡⚡ Fast | ⭐⭐ Very good | Alternative source, MD5 verification |

#### Method 1: fasterq-dump (Simple & Fast)

```bash
seqfetcher download \
  --sra-accession SRR12345678 \
  --sra-method fasterq
```

**Features:**
- Direct streaming download
- Automatic split into paired-end files
- Auto-compression to gzip

#### Method 2: prefetch + fasterq-dump (Most Robust)

```bash
seqfetcher download \
  --sra-accession SRR12345678 \
  --sra-method prefetch
```

**Features:**
- Two-stage download (prefetch → convert)
- Best for large files
- Network interruption recovery

#### Method 3: parallel-fastq-dump (Fastest)

```bash
seqfetcher download \
  --sra-accession SRR12345678 \
  --sra-method parallel
```

**Features:**
- Multi-threaded download
- Fastest for large datasets
- Requires `parallel-fastq-dump` installed

#### Method 4: ENA (European Nucleotide Archive)

```bash
seqfetcher download \
  --sra-accession SRR12345678 \
  --sra-method ena
```

**Features:**
- Download from European servers
- MD5 checksum verification
- File size validation
- Alternative when NCBI is slow

#### Batch SRA Downloads

```bash
# Create accession file
cat > sra_runs.txt << EOF
SRR12345678
SRR12345679
SRR12345680
EOF

# Download all with chosen method
seqfetcher download \
  --sra-accession-file sra_runs.txt \
  --sra-method prefetch
```

**Supported Accession Types:**
- `SRRxxxxxxx` - NCBI SRA runs
- `ERRxxxxxxx` - ENA runs
- `DRRxxxxxxx` - DDBJ runs
- `SRPxxxxxx` - Study accessions
- `PRJNAxxxxx` - BioProject accessions
- `PRJEBxxxxx` - ENA project accessions
- `GSExxxxx` - GEO series accessions

---

### Downloading from ENA

ENA downloads are integrated into the SRA workflow but can provide additional benefits:

```bash
seqfetcher download \
  --sra-accession-file runs.txt \
  --sra-method ena
```

**Advantages:**
- No SRA Toolkit required
- Direct FASTQ download
- MD5 verification included
- Often faster for European users

**Features:**
- Progress tracking
- Automatic retry
- Completed run tracking
- Detailed error reporting

**Output:**
```
[INFO]  Fetching ENA metadata for SRR12345678...
[INFO]  Downloading FASTQ files for SRR12345678...
[INFO]    Downloading: SRR12345678_1.fastq.gz (Size: 2.3 GiB)
[INFO]    ✓ Downloaded: SRR12345678_1.fastq.gz
[INFO]    Verifying MD5 checksum...
[INFO]    ✓ Checksum verified
[INFO]    ✓ File size verified
```

---

## Advanced Usage

### Custom Output Directory

```bash
seqfetcher search --organism "Yersinia pestis" --outdir my_genomes
seqfetcher download --accession GCF_000009065.1 --outdir my_genomes
```

### Combining Search and Download

```bash
# Search and save results
seqfetcher search --organism "Mycobacterium tuberculosis" \
  --outdir tb_data

# Use the generated accession file
seqfetcher download \
  --accession-file tb_data/assemblies_accessions.txt \
  --jobs 8 \
  --outdir tb_data
```

### Gene Extraction Workflow

```bash
# 1. Extract gene IDs from reference genome
seqfetcher search --organism "Escherichia coli" \
  --extract-genes \
  --outdir ecoli_genes

# 2. Download the genes
seqfetcher download \
  --gene-file ecoli_genes/gene_ids.txt \
  --jobs 6 \
  --outdir ecoli_genes
```

### High-Performance Downloads

```bash
# Use all available cores
CORES=$(nproc)

# Download assemblies
seqfetcher download \
  --accession-file large_list.txt \
  --jobs $CORES \
  --outdir genomes

# Download SRA with parallel method
seqfetcher download \
  --sra-accession-file sra_list.txt \
  --sra-method parallel \
  --outdir fastq_data
```

---

## File Formats

### Assembly TSV Format

```tsv
ACCESSION       ORGANISM                LEVEL       STATUS      REFSEQ_CATEGORY     NAME
GCF_000005845.2 Escherichia coli str... Chromosome  Complete    reference genome    ASM584v2
```

### Gene Metadata TSV Format

```tsv
EntrezID  Symbol  GeneID          Chromosome  Start    End      Strand  GeneType
945803    thrL    gene-b0001      NC_000913.3 190      255      +       protein_coding
944742    thrA    gene-b0002      NC_000913.3 337      2799     +       protein_coding
```

### Taxonomy Metadata TSV Format

```tsv
SPECIES              COMMON_NAME      TAX_ID  DOMAIN    KINGDOM   PHYLUM         ...
Escherichia coli     E. coli          562     Bacteria  Bacteria  Proteobacteria ...
```

---

## Troubleshooting

### Common Issues

#### "datasets command not found"

**Solution:**
```bash
# Install NCBI Datasets CLI
# macOS
conda install -c conda-forge ncbi-datasets-cli

# Linux
wget https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/latest/linux-amd64/datasets
chmod +x datasets
sudo mv datasets /usr/local/bin/
```

#### "jq is required but not installed"

**Solution:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

#### SRA downloads fail with "accession not found"

**Possible causes:**
1. Accession format is incorrect (use `SRRxxxxxxx`)
2. Data not available on ENA (try different method)
3. Network issues

**Solutions:**
```bash
# Try alternative method
seqfetcher download --sra-accession SRR12345678 --sra-method prefetch

# Or use ENA
seqfetcher download --sra-accession SRR12345678 --sra-method ena
```

#### Parallel downloads cause errors

**Solution:** Reduce the number of parallel jobs:
```bash
seqfetcher download --accession-file list.txt --jobs 2
```

#### MD5 checksum mismatch (ENA)

**Solution:** Corrupted download, will retry automatically. If persistent:
```bash
# Delete partial files and retry
rm -rf downloads/fastq/SRR12345678*
seqfetcher download --sra-accession SRR12345678 --sra-method ena
```

### Debug Mode

Enable detailed logging:

```bash
# Add to main script temporarily
set -x  # Enable bash debugging
```

---

## Performance Tips

### Optimize for Large Batches

```bash
# Increase parallel jobs (monitor system load)
seqfetcher download --accession-file large_list.txt --jobs 16

# Use prefetch method for reliability
seqfetcher download --sra-accession-file runs.txt --sra-method prefetch
```

### Storage Considerations

| Data Type | Average Size | Notes |
|-----------|--------------|-------|
| Bacterial genome | 5-10 MB | With annotations |
| Human genome | 3 GB | FASTA only |
| SRA run (bacteria) | 500 MB - 5 GB | Depends on coverage |
| SRA run (human) | 20-100 GB | Whole genome sequencing |

### Network Optimization

- Use `prefetch` for unreliable connections
- Use `ena` method if geographically closer to Europe
- Consider institutional mirrors if available

---

## Examples Gallery

### Example 1: Comparative Genomics Study

```bash
# Download multiple strains
cat > strains.txt << EOF
GCF_000005845.2
GCF_000008865.2
GCF_000742135.1
GCF_001544255.1
EOF

seqfetcher download --accession-file strains.txt --jobs 4
```

### Example 2: RNA-Seq Analysis Pipeline

```bash
# Download reference genome
seqfetcher download --accession GCF_000005845.2 --outdir reference

# Extract gene IDs
seqfetcher search --organism "Escherichia coli" \
  --extract-genes --outdir reference

# Download RNA-seq data
seqfetcher download --sra-accession-file rnaseq_runs.txt \
  --sra-method prefetch --outdir rnaseq
```

### Example 3: Pathogen Surveillance

```bash
# Search outbreak strain
seqfetcher search --organism "Salmonella enterica serovar Typhimurium" \
  --outdir outbreak_2024

# Download all relevant assemblies
seqfetcher download \
  --accession-file outbreak_2024/assemblies_accessions.txt \
  --jobs 8 \
  --outdir outbreak_2024
```

---

## Command Reference

### Global Options

```
--help, -h          Show help message
--outdir DIR        Output directory (default: downloads)
--jobs, -j NUMBER   Parallel jobs (default: 4)
```

### Search Command

```bash
seqfetcher search --organism "ORGANISM" [OPTIONS]
```

**Options:**
- `--organism`: Scientific name (required)
- `--interactive, -i`: Interactive selection mode
- `--extract-genes`: Extract gene IDs from reference
- `--output`: Custom output filename

### Download Command

```bash
seqfetcher download [OPTIONS]
```

**Assembly Options:**
- `--accession`: Single accession
- `--accession-file`: File with accessions

**Gene Options:**
- `--gene-id`: Comma-separated gene IDs
- `--gene-file`: File with gene IDs

**SRA Options:**
- `--sra-accession`: Single SRA accession
- `--sra-accession-file`: File with SRA accessions
- `--sra-method`: Method (fasterq|prefetch|parallel|ena)

---

## Citation

If you use SeqFetcher in your research, please cite:

```
SeqFetcher: A unified CLI for genomic data retrieval
GitHub: https://github.com/yourusername/seqfetcher
```

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Development Setup

```bash
git clone https://github.com/yourusername/seqfetcher.git
cd seqfetcher
chmod +x seqfetcher.sh lib/*.sh
./seqfetcher.sh --help
```

---

## License

MIT License - see [LICENSE](LICENSE) file for details

---

## Acknowledgments

- NCBI for the Datasets and SRA Toolkit
- ENA for providing direct FASTQ access
- GNU Parallel developers

---

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/seqfetcher/issues)
- **Documentation**: [Wiki](https://github.com/yourusername/seqfetcher/wiki)
- **Email**: your.email@example.com

---

## Changelog

### Version 1.0.0 (2026-01-22)
- Initial release
- Support for NCBI assemblies, genes, SRA, and ENA
- Parallel download capability
- Interactive search mode
- Gene extraction from reference genomes