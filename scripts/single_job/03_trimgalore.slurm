#!/bin/bash

#================================================================
# SLURM BATCH JOB SCRIPT - TRIM GALORE SINGLE JOB (ALL SAMPLES)
#================================================================
# NOTE: SBATCH directives use default values. Adjust these directly or use
# sbatch command-line overrides (e.g., sbatch --time=240:00:00 script.slurm)
#SBATCH --job-name=trimgalore_single
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=120:00:00
#SBATCH --output=logs/trimgalore_single_%j.out
#SBATCH --error=logs/trimgalore_single_%j.err

#================================================================
# MODULES
#================================================================
# Load modules as specified in the original script example
module load FastQC
module load trimgalore/0.6.10

#================================================================
# SCRIPT COMMANDS
#================================================================

set -e

echo "--- Job started on $(hostname) at $(date) ---"

# --- 1. Source configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/../../config.sh"

# --- 2. DEFINE DIRECTORIES ---
# Input directory containing the raw, compressed FASTQ files (from download step)
INPUT_DIR="$RAW_DATA_DIR"

# Base output directory. Subdirectories for each sample will be created here.
# This directory will be the INPUT_DIR for your Kneaddata script.
OUTPUT_BASE_DIR="$TRIMMED_DIR"

# Create the base output directory if it doesn't exist
mkdir -p "$OUTPUT_BASE_DIR"

echo "Input directory: $INPUT_DIR"
echo "Base output directory: $OUTPUT_BASE_DIR"

# --- 3. DISCOVER SAMPLES ---
# Find all unique sample prefixes from your project's raw reads directory
mapfile -t samples < <(find "$INPUT_DIR" -name "*_1.fastq.gz" -exec basename {} "_1.fastq.gz" \; | sort -u)

# Verify that samples were found
if [ ${#samples[@]} -eq 0 ]; then
    echo "ERROR: No samples found in $INPUT_DIR"
    echo "Expecting files with the format: <sample>_1.fastq.gz"
    exit 1
fi

echo "--- Found ${#samples[@]} samples to process: ---"
printf '%s\n' "${samples[@]}"
echo "---------------------------------"

# --- 4. PROCESS EACH SAMPLE ---
# We will work inside the base output directory
cd "$OUTPUT_BASE_DIR"

processed_count=0
skipped_count=0

for sample in "${samples[@]}"; do

    # --- AUTO-RESUME CHECK ---
    # Define the expected final output files. Trim Galore renames files,
    # so SRR123_1.fastq.gz becomes SRR123_1_val_1.fq.gz
    final_r1="${sample}/${sample}_1_val_1.fq.gz"
    final_r2="${sample}/${sample}_2_val_2.fq.gz"

    # Check if both final, compressed output files already exist
    if [[ -f "$final_r1" && -f "$final_r2" && -s "$final_r1" && -s "$final_r2" ]]; then
        echo ">>> Sample $sample is already processed. Final files found. Skipping."
        echo "---------------------------------"
        ((skipped_count++))
        continue # This command skips to the next sample in the loop
    fi

    echo ">>> Processing sample: $sample"

    # Create an output subdirectory for this specific sample
    mkdir -p "$sample"

    # Define the full paths for the raw, paired-end read files (compressed)
    r1_file="${INPUT_DIR}/${sample}_1.fastq.gz"
    r2_file="${INPUT_DIR}/${sample}_2.fastq.gz"

    # Sanity check to ensure both paired files exist before processing
    if [[ ! -f "$r1_file" || ! -f "$r2_file" ]]; then
        echo "ERROR: Missing one or both FASTQ files for sample $sample. Skipping."
        echo "Looked for: $r1_file and $r2_file"
        continue
    fi

    # Run Trim Galore with parameters exactly from the original script
    # --gzip: This flag compresses the output files to .fq.gz format.
    # -o "$sample": This directs all output for this sample into its own subdirectory.
    trim_galore \
        --paired \
        --phred33 \
        --quality $TRIMGALORE_QUALITY \
        --stringency $TRIMGALORE_STRINGENCY \
        --length $TRIMGALORE_MIN_LENGTH \
        --gzip \
        --fastqc \
        --cores $SLURM_CPUS_PER_TASK \
        -o "$sample" \
        "$r1_file" "$r2_file"

    # Verify output files were created
    if [[ -f "$final_r1" && -f "$final_r2" && -s "$final_r1" && -s "$final_r2" ]]; then
        echo ">>> Completed processing for $sample"
        ((processed_count++))
    else
        echo ">>> ERROR: Trim Galore failed for sample: $sample"
        echo "Expected output files not found:"
        echo "  R1: $final_r1"
        echo "  R2: $final_r2"
        echo "Files in output directory:"
        ls -la "$sample"
        exit 1
    fi

    echo "---------------------------------"
done

echo "--- Trim Galore processing finished for all samples at $(date) ---"
echo "--- Processed samples: $processed_count ---"
echo "--- Skipped samples: $skipped_count ---"