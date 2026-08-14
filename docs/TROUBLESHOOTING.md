# Troubleshooting & Performance

See also the [Command Reference](COMMAND_REFERENCE.md) and the
[README](../README.md). Run `bash scripts/check_deps.sh` first - most of the
issues below are a missing dependency it will catch in one pass. Most of
them can be avoided entirely by installing via `conda env create -f
../environment.yml` instead of installing each tool by hand (see
README "Installation").

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
