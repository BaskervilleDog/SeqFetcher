#!/bin/bash

# ==============================================================================
# BATCH DOWNLOAD HELPER SCRIPTS
# ==============================================================================
# Additional utility scripts for efficient batch downloading
# ==============================================================================

# ==============================================================================
# 1. SMART DOWNLOAD WITH RETRY AND RESUME
# ==============================================================================

smart_download_sra() {
    local accession=$1
    local output_dir=$2
    local max_retries=${3:-3}
    local threads=${4:-8}
    
    local retry_count=0
    local success=false
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting download: $accession"
    
    while [ $retry_count -lt $max_retries ] && [ "$success" = false ]; do
        
        if [ $retry_count -gt 0 ]; then
            echo "  Retry attempt $retry_count/$max_retries..."
            sleep 10  # Wait before retry
        fi
        
        # Try fasterq-dump with error handling
        if fasterq-dump "$accession" \
            --outdir "$output_dir" \
            --temp "temp_${accession}" \
            --threads "$threads" \
            --split-files \
            --progress 2>&1 | tee "${accession}_download.log"; then
            
            # Compress files
            gzip "${output_dir}/${accession}"*.fastq 2>/dev/null || true
            
            # Verify files exist and are not empty
            if ls "${output_dir}/${accession}"*.fastq.gz 1> /dev/null 2>&1; then
                local file_sizes=$(du -sh "${output_dir}/${accession}"*.fastq.gz)
                echo "  ✓ Success! Files created:"
                echo "$file_sizes"
                success=true
            else
                echo "  ✗ Download failed - no files created"
                retry_count=$((retry_count + 1))
            fi
        else
            echo "  ✗ Download failed with error"
            retry_count=$((retry_count + 1))
        fi
        
        # Cleanup temp directory
        rm -rf "temp_${accession}"
    done
    
    if [ "$success" = false ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAILED: $accession after $max_retries attempts"
        echo "$accession" >> failed_downloads.txt
        return 1
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] COMPLETED: $accession"
        return 0
    fi
}

# ==============================================================================
# 2. PARALLEL BATCH DOWNLOAD WITH GNU PARALLEL
# ==============================================================================

parallel_batch_download() {
    cat << 'EOF' > parallel_download.sh
#!/bin/bash

# This script is called by GNU parallel for each SRR accession

accession=$1
output_dir=$2
threads_per_job=$3

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Processing: $accession"

# Download with fasterq-dump
fasterq-dump "$accession" \
    --outdir "$output_dir" \
    --temp "temp_${accession}_$$" \
    --threads "$threads_per_job" \
    --split-files \
    --progress

# Compress
gzip "${output_dir}/${accession}"*.fastq 2>/dev/null

# Cleanup
rm -rf "temp_${accession}_$$"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed: $accession"
EOF
    
    chmod +x parallel_download.sh
    
    # Usage with GNU parallel
    cat << 'EOF'

# Run parallel downloads:
# Adjust -j based on your system (number of simultaneous downloads)
# Adjust threads_per_job based on total cores / number of jobs

TOTAL_CORES=32
JOBS=4
THREADS_PER_JOB=$((TOTAL_CORES / JOBS))

cat SRR_list.txt | parallel -j $JOBS --joblog parallel_download.log \
    ./parallel_download.sh {} downloads/fastq $THREADS_PER_JOB

EOF
}

# ==============================================================================
# 3. DOWNLOAD WITH PROGRESS TRACKING AND RESUME
# ==============================================================================

download_with_progress() {
    cat << 'EOF' > download_tracker.sh
#!/bin/bash

# Track download progress and resume from last successful download

ACCESSION_LIST=$1
OUTPUT_DIR=$2
COMPLETED_FILE="completed_downloads.txt"
FAILED_FILE="failed_downloads.txt"

# Create tracking files if they don't exist
touch "$COMPLETED_FILE"
touch "$FAILED_FILE"

# Count total, completed, and failed
total=$(wc -l < "$ACCESSION_LIST")
completed=$(wc -l < "$COMPLETED_FILE")
failed=$(wc -l < "$FAILED_FILE")
remaining=$((total - completed - failed))

echo "=== Download Progress ==="
echo "Total accessions: $total"
echo "Completed: $completed"
echo "Failed: $failed"
echo "Remaining: $remaining"
echo ""

# Process each accession
while IFS= read -r accession; do
    
    # Skip if already completed
    if grep -q "^${accession}$" "$COMPLETED_FILE"; then
        echo "Skipping $accession (already completed)"
        continue
    fi
    
    # Skip if previously failed (optional: remove to retry failed ones)
    if grep -q "^${accession}$" "$FAILED_FILE"; then
        echo "Skipping $accession (previously failed)"
        continue
    fi
    
    # Download
    echo "Downloading: $accession"
    
    if fasterq-dump "$accession" \
        --outdir "$OUTPUT_DIR" \
        --threads 8 \
        --split-files \
        --progress; then
        
        # Compress
        gzip "${OUTPUT_DIR}/${accession}"*.fastq 2>/dev/null || true
        
        # Mark as completed
        echo "$accession" >> "$COMPLETED_FILE"
        echo "✓ Completed: $accession"
        
    else
        # Mark as failed
        echo "$accession" >> "$FAILED_FILE"
        echo "✗ Failed: $accession"
    fi
    
    # Update progress
    completed=$(wc -l < "$COMPLETED_FILE")
    failed=$(wc -l < "$FAILED_FILE")
    remaining=$((total - completed - failed))
    echo "Progress: $completed/$total completed, $failed failed, $remaining remaining"
    echo ""
    
done < "$ACCESSION_LIST"

echo "=== Download Summary ==="
echo "Successfully downloaded: $(wc -l < "$COMPLETED_FILE")"
echo "Failed downloads: $(wc -l < "$FAILED_FILE")"
EOF
    
    chmod +x download_tracker.sh
}

# ==============================================================================
# 4. DOWNLOAD AND VERIFY CHECKSUMS
# ==============================================================================

download_with_checksum() {
    cat << 'EOF' > download_verify.sh
#!/bin/bash

# Download from ENA with MD5 verification

accession=$1
output_dir=$2

echo "Fetching metadata for $accession..."

# Get ENA metadata
ena_url="https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${accession}&result=read_run&fields=run_accession,fastq_ftp,fastq_md5"

wget -q -O "${accession}_metadata.txt" "$ena_url"

# Parse and download
tail -n +2 "${accession}_metadata.txt" | while IFS=$'\t' read -r run_acc ftp_urls md5_sums; do
    
    IFS=';' read -ra FTP_ARRAY <<< "$ftp_urls"
    IFS=';' read -ra MD5_ARRAY <<< "$md5_sums"
    
    for i in "${!FTP_ARRAY[@]}"; do
        ftp_url="ftp://${FTP_ARRAY[$i]}"
        expected_md5="${MD5_ARRAY[$i]}"
        filename=$(basename "$ftp_url")
        output_file="${output_dir}/${filename}"
        
        echo "Downloading: $filename"
        
        # Download with resume capability
        wget -c -q --show-progress -O "$output_file" "$ftp_url"
        
        # Verify checksum
        echo "Verifying checksum..."
        actual_md5=$(md5sum "$output_file" | awk '{print $1}')
        
        if [[ "$actual_md5" == "$expected_md5" ]]; then
            echo "✓ Checksum verified: $filename"
        else
            echo "✗ Checksum MISMATCH: $filename"
            echo "  Expected: $expected_md5"
            echo "  Got: $actual_md5"
            echo "$filename" >> checksum_failures.txt
        fi
    done
done

rm "${accession}_metadata.txt"
EOF
    
    chmod +x download_verify.sh
}

# ==============================================================================
# 5. DISK SPACE MONITOR
# ==============================================================================

monitor_disk_space() {
    cat << 'EOF' > disk_monitor.sh
#!/bin/bash

# Monitor disk space during downloads
# Pauses downloads if space is low

MIN_FREE_GB=50
CHECK_INTERVAL=300  # Check every 5 minutes
DOWNLOAD_DIR=$1

echo "Starting disk space monitor..."
echo "Minimum free space: ${MIN_FREE_GB} GB"
echo "Monitoring: $DOWNLOAD_DIR"

while true; do
    # Get free space in GB
    free_space=$(df -BG "$DOWNLOAD_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
    
    if [ "$free_space" -lt "$MIN_FREE_GB" ]; then
        echo "[$(date)] WARNING: Low disk space! ${free_space}GB remaining"
        echo "Pausing downloads..."
        
        # Send alert (customize as needed)
        echo "Low disk space: ${free_space}GB" | mail -s "Download Alert" user@example.com
        
        # Pause all fasterq-dump processes
        pkill -STOP fasterq-dump
        
        echo "Downloads paused. Free up space and resume manually."
        sleep 600  # Wait 10 minutes before checking again
        
    else
        # Resume if previously paused
        pkill -CONT fasterq-dump 2>/dev/null
        
        echo "[$(date)] Disk space OK: ${free_space}GB free"
        sleep "$CHECK_INTERVAL"
    fi
done
EOF
    
    chmod +x disk_monitor.sh
}

# ==============================================================================
# 6. QUALITY CHECK AFTER DOWNLOAD
# ==============================================================================

post_download_qc() {
    cat << 'EOF' > post_download_qc.sh
#!/bin/bash

# Verify downloaded files and generate QC report

output_dir=$1
report_file="download_qc_report.txt"

echo "=== Download Quality Check ===" > "$report_file"
echo "Date: $(date)" >> "$report_file"
echo "" >> "$report_file"

# Count files
total_files=$(find "$output_dir" -name "*.fastq.gz" | wc -l)
echo "Total FASTQ files: $total_files" >> "$report_file"

# Check for empty or corrupted files
echo "" >> "$report_file"
echo "Checking file integrity..." >> "$report_file"

empty_files=0
corrupt_files=0

find "$output_dir" -name "*.fastq.gz" | while read -r file; do
    # Check if file is empty
    if [ ! -s "$file" ]; then
        echo "  EMPTY: $file" >> "$report_file"
        empty_files=$((empty_files + 1))
    else
        # Check if gzip file is valid
        if ! gzip -t "$file" 2>/dev/null; then
            echo "  CORRUPT: $file" >> "$report_file"
            corrupt_files=$((corrupt_files + 1))
        fi
    fi
done

echo "" >> "$report_file"
echo "Empty files: $empty_files" >> "$report_file"
echo "Corrupt files: $corrupt_files" >> "$report_file"

# Calculate total size
total_size=$(du -sh "$output_dir" | cut -f1)
echo "" >> "$report_file"
echo "Total size: $total_size" >> "$report_file"

# Get file size distribution
echo "" >> "$report_file"
echo "File size distribution:" >> "$report_file"
find "$output_dir" -name "*.fastq.gz" -exec du -h {} \; | \
    sort -h | \
    awk '{print $1}' | \
    uniq -c >> "$report_file"

echo "" >> "$report_file"
echo "QC report saved to: $report_file"

cat "$report_file"
EOF
    
    chmod +x post_download_qc.sh
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

echo "=== Batch Download Helper Scripts Generator ==="
echo ""
echo "This script creates several helper utilities:"
echo "  1. smart_download_sra - Download with retry logic"
echo "  2. parallel_download.sh - Parallel batch downloads"
echo "  3. download_tracker.sh - Progress tracking and resume"
echo "  4. download_verify.sh - Download with checksum verification"
echo "  5. disk_monitor.sh - Monitor disk space during downloads"
echo "  6. post_download_qc.sh - Quality check after downloads"
echo ""

read -p "Generate all helper scripts? (y/n): " choice

if [[ $choice == "y" || $choice == "Y" ]]; then
    parallel_batch_download
    download_with_progress
    download_with_checksum
    monitor_disk_space
    post_download_qc
    
    echo ""
    echo "✓ All helper scripts created!"
    echo ""
    echo "Usage examples:"
    echo "  ./download_tracker.sh SRR_list.txt downloads/fastq"
    echo "  ./disk_monitor.sh downloads/fastq &"
    echo "  ./post_download_qc.sh downloads/fastq"
fi