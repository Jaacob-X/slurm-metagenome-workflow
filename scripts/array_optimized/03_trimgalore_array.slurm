#!/bin/bash

#================================================================
# SLURM BATCH JOB SCRIPT - TRIM GALORE ARRAY PROCESSING
#================================================================
# NOTE: SBATCH directives use default values. Adjust these directly or use
# sbatch command-line overrides (e.g., sbatch --cpus-per-task=32 script.slurm)
#SBATCH --job-name=trimgalore_array
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=8:00:00

# --- JOB ARRAY DIRECTIVES ---
# IMPORTANT: Update --array parameter based on your sample count before submission
# Example: --array=1-74%8 for 74 samples with max 8 concurrent jobs
#SBATCH --array=1-2%8
#SBATCH --output=logs/trimgalore_%A_%a.out
#SBATCH --error=logs/trimgalore_%A_%a.err

#================================================================
# SCRIPT COMMANDS
#================================================================

set -e

echo "--- Job $SLURM_ARRAY_JOB_ID, Task $SLURM_ARRAY_TASK_ID started on $(hostname) at $(date) ---"

# --- 1. Set up environment ---
module load FastQC
module load trimgalore/0.6.10

# --- 2. Source configuration ---
# Use SLURM_SUBMIT_DIR (directory where sbatch was run) to find config
source "${SLURM_SUBMIT_DIR}/config.sh"

# --- 3. Create directories ---
mkdir -p "$TRIMMED_DIR"
mkdir -p "$LOGS_DIR"

# --- 4. GET SAMPLE NAME FROM THE LIST ---
SAMPLE_NAME=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$SAMPLE_LIST")
echo "--- Processing Sample: $SAMPLE_NAME ---"

# --- 5. DEFINE DIRECTORIES AND FILES ---
OUTPUT_DIR_SAMPLE="${TRIMMED_DIR}/${SAMPLE_NAME}"
INPUT_R1="${RAW_DATA_DIR}/${SAMPLE_NAME}_1.fastq.gz"
INPUT_R2="${RAW_DATA_DIR}/${SAMPLE_NAME}_2.fastq.gz"

# Trim Galore output files (based on Trim Galore naming convention)
OUTPUT_R1="${OUTPUT_DIR_SAMPLE}/${SAMPLE_NAME}_1_val_1.fq.gz"
OUTPUT_R2="${OUTPUT_DIR_SAMPLE}/${SAMPLE_NAME}_2_val_2.fq.gz"

# --- 6. AUTO-RESUME CHECK ---
if [[ -f "$OUTPUT_R1" && -f "$OUTPUT_R2" && -s "$OUTPUT_R1" && -s "$OUTPUT_R2" ]]; then
    echo ">>> Sample $SAMPLE_NAME is already processed. Trim Galore output found. Skipping."
    echo "---------------------------------"
    exit 0
fi

# --- 7. INPUT VALIDATION ---
if [[ ! -f "$INPUT_R1" || ! -f "$INPUT_R2" ]]; then
    echo "ERROR: Missing input FASTQ files for sample $SAMPLE_NAME:"
    echo "  R1: $INPUT_R1"
    echo "  R2: $INPUT_R2"
    exit 1
fi

# --- 8. CREATE OUTPUT DIRECTORY ---
mkdir -p "$OUTPUT_DIR_SAMPLE"

echo "Input files:"
echo "  R1: $INPUT_R1"
echo "  R2: $INPUT_R2"
echo "Output directory: $OUTPUT_DIR_SAMPLE"

# --- 9. RUN TRIM GALORE ---
echo "Running Trim Galore on $SAMPLE_NAME..."
trim_galore --paired \
    --phred33 \
    --quality $TRIMGALORE_QUALITY \
    --stringency $TRIMGALORE_STRINGENCY \
    --length $TRIMGALORE_MIN_LENGTH \
    --gzip \
    --fastqc \
    --cores $SLURM_CPUS_PER_TASK \
    --output_dir "$OUTPUT_DIR_SAMPLE" \
    "$INPUT_R1" "$INPUT_R2"

# --- 10. VERIFY OUTPUT ---
if [[ -f "$OUTPUT_R1" && -f "$OUTPUT_R2" ]]; then
    echo ">>> Successfully completed Trim Galore for $SAMPLE_NAME"
    echo "Output files:"
    echo "  R1: $OUTPUT_R1"
    echo "  R2: $OUTPUT_R2"
    # Show file sizes for verification
    ls -lh "$OUTPUT_R1" "$OUTPUT_R2"
else
    echo ">>> ERROR: Trim Galore failed for $SAMPLE_NAME"
    echo "Expected output files not found:"
    echo "  R1: $OUTPUT_R1"
    echo "  R2: $OUTPUT_R2"
    echo "Files in output directory:"
    ls -la "$OUTPUT_DIR_SAMPLE"
    exit 1
fi

echo "--- Job $SLURM_ARRAY_JOB_ID, Task $SLURM_ARRAY_TASK_ID finished at $(date) ---"