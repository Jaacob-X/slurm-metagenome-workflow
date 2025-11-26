#!/bin/bash

#================================================================
# SLURM BATCH JOB SCRIPT - FASTQC SINGLE JOB (ALL SAMPLES)
#================================================================
# NOTE: SBATCH directives use default values. Adjust these directly or use
# sbatch command-line overrides (e.g., sbatch --cpus-per-task=16 script.slurm)
#SBATCH --job-name=fastqc_single
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=24:00:00
#SBATCH --output=logs/fastqc_single_%j.out
#SBATCH --error=logs/fastqc_single_%j.err

#================================================================
# SCRIPT COMMANDS
#================================================================

set -e

echo "--- Job started on $(hostname) at $(date) ---"

# --- 1. Set up environment ---
module load fastqc/0.12.1

# --- 2. Source configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/../../config.sh"

# --- 3. Create directories ---
mkdir -p "$FASTQC_DIR"
mkdir -p "$LOGS_DIR"

# --- 4. DEFINE DIRECTORIES ---
# Use your project's raw read directory as the input
INPUT_DIR="$RAW_DATA_DIR"
OUTPUT_DIR="$FASTQC_DIR"

# Create a new directory for the FastQC output
mkdir -p "$OUTPUT_DIR"

# --- 5. FILE PROCESSING ---
echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"

# Counter for processed samples
processed_count=0
skipped_count=0

# Loop through each paired-end read set in the input directory
# This pattern matches files ending in _1.fastq.gz to identify the forward reads (compressed input)
for r1_file in "$INPUT_DIR"/*_1.fastq.gz; do
    # Extract the sample name prefix from the R1 filename
    # This removes the directory path and the "_1.fastq.gz" suffix
    sample=$(basename "$r1_file" _1.fastq.gz)

    # Define the corresponding R2 (reverse) file
    r2_file="$INPUT_DIR/${sample}_2.fastq.gz"

    # Define output files to check for auto-resume
    output_r1="${OUTPUT_DIR}/${sample}/${sample}_1_fastqc.html"
    output_r2="${OUTPUT_DIR}/${sample}/${sample}_2_fastqc.html"

    # Auto-resume check: skip if already processed
    if [[ -f "$output_r1" && -f "$output_r2" ]]; then
        echo "--- Skipping sample: $sample (already processed) ---"
        ((skipped_count++))
        continue
    fi

    echo "--- Starting FastQC for sample: $sample ---"
    echo "R1 file: $r1_file"
    echo "R2 file: $r2_file"

    # Create sample-specific output directory
    sample_output_dir="${OUTPUT_DIR}/${sample}"
    mkdir -p "$sample_output_dir"

    # Run FastQC on both the R1 and R2 files for a given sample.
    # The output for both will be placed in the same directory.
    fastqc -o "$sample_output_dir" "$r1_file" "$r2_file"

    # Verify output was created
    if [[ -f "$output_r1" && -f "$output_r2" ]]; then
        echo "--- Successfully completed FastQC for sample: $sample ---"
        ((processed_count++))
    else
        echo "--- ERROR: FastQC failed for sample: $sample ---"
        exit 1
    fi
done

echo "--- FastQC analysis complete. Results are in $OUTPUT_DIR ---"
echo "--- Processed samples: $processed_count ---"
echo "--- Skipped samples: $skipped_count ---"
echo "--- Job finished at $(date) ---"