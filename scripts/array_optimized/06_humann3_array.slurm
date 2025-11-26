#!/bin/bash

#================================================================
# SLURM BATCH JOB SCRIPT - HUMANN3 ARRAY PROCESSING
#================================================================
# NOTE: SBATCH directives use default values. Adjust these directly or use
# sbatch command-line overrides (e.g., sbatch --mem=256G script.slurm)
#SBATCH --job-name=humann3_array
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=128G
#SBATCH --time=16:00:00

# --- JOB ARRAY DIRECTIVES ---
# IMPORTANT: Update --array parameter based on your sample count before submission
# Example: --array=1-74%20 for 74 samples with max 20 concurrent jobs
#SBATCH --array=1-2%20
#SBATCH --output=logs/humann3_%A_%a.out
#SBATCH --error=logs/humann3_%A_%a.err

# --- 1. Source configuration ---
# Use SLURM_SUBMIT_DIR (directory where sbatch was run) to find config
source "${SLURM_SUBMIT_DIR}/config.sh"

# --- 2. Create logs directory if it doesn't exist ---
mkdir -p "$LOGS_DIR"

# --- Fail the script if any command fails ---
set -e

#================================================================
# ENVIRONMENT SETUP
#================================================================
echo "--- Activating Conda environment ---"
module load miniforge3
conda activate humann3
command -v humann

#================================================================
# SCRIPT COMMANDS
#================================================================
echo "--- Job $SLURM_ARRAY_JOB_ID, Task $SLURM_ARRAY_TASK_ID started on $(hostname) at $(date) ---"

# --- 1. GET SAMPLE NAME FROM THE LIST ---
# This line reads the sample_list.txt file and picks the line number
# that corresponds to the job array's task ID.
SAMPLE_NAME=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$SAMPLE_LIST")
echo "--- Processing Sample: $SAMPLE_NAME ---"


# --- 3. DEFINE DIRECTORIES ---
INPUT_DIR="${KNEADDATA_DIR}/${SAMPLE_NAME}"
OUTPUT_DIR="${HUMANN3_DIR}/${SAMPLE_NAME}"

# Use paths from configuration
NUC_DB="$HUMANN_NUC_DB"
PROT_DB="$HUMANN_PROT_DB"

mkdir -p "$OUTPUT_DIR"

echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_DIR"

# --- 3. AUTO-RESUME CHECK ---
# This check is now cleaner because we use --output-basename to enforce a consistent filename.
GENE_FAMILIES_FILE="${OUTPUT_DIR}/${SAMPLE_NAME}_concatenated_genefamilies.tsv"
if [[ -f "$GENE_FAMILIES_FILE" && -s "$GENE_FAMILIES_FILE" ]]; then
    echo ">>> Sample $SAMPLE_NAME is already processed. Final files found. Skipping."
    echo "---------------------------------"
    exit 0 # Exit successfully
fi
# --- END OF CHECK ---

echo ">>> Setting up for sample: $SAMPLE_NAME"

r1_file="${INPUT_DIR}/${SAMPLE_NAME}_1_val_1_kneaddata_paired_1.fastq"
r2_file="${INPUT_DIR}/${SAMPLE_NAME}_1_val_1_kneaddata_paired_2.fastq"

if [[ ! -f "$r1_file" || ! -f "$r2_file" ]]; then
    echo "ERROR: Missing clean Kneaddata FASTQ files for sample $SAMPLE_NAME. Skipping."
    exit 1 # Exit with an error
fi

CONCAT_FILE="${OUTPUT_DIR}/${SAMPLE_NAME}_concatenated.fastq.gz"

# --- Step 4: Concatenate and compress paired-end reads ---
echo "    Concatenating reads for $SAMPLE_NAME..."
cat "$r1_file" "$r2_file" | gzip > "$CONCAT_FILE"

# --- Step 5: Run HUMAnN 3 ---
echo "    Running HUMAnN 3 on $SAMPLE_NAME..."
humann \
    --input "$CONCAT_FILE" \
    --output "$OUTPUT_DIR" \
    --nucleotide-database "$NUC_DB" \
    --protein-database "$PROT_DB" \
    --threads $SLURM_CPUS_PER_TASK \
    --o-log "${OUTPUT_DIR}/${SAMPLE_NAME}.log" \
    --metaphlan-options="--bowtie2db $METAPHLAN_DB" \
    --remove-temp-output

# --- Step 6: Clean up the large temporary file ---
echo "    Cleaning up temporary file for $SAMPLE_NAME..."
rm "$CONCAT_FILE"

echo ">>> Completed processing for $SAMPLE_NAME"
echo "--- Job $SLURM_ARRAY_JOB_ID, Task $SLURM_ARRAY_TASK_ID finished at $(date) ---"