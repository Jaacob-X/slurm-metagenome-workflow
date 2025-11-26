#!/bin/bash

#================================================================
# SLURM BATCH JOB SCRIPT - HUMANN3 SINGLE JOB (ALL SAMPLES)
#================================================================
# NOTE: SBATCH directives use default values. Adjust these directly or use
# sbatch command-line overrides (e.g., sbatch --mem=256G script.slurm)
#SBATCH --job-name=humann3_single
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=128G
#SBATCH --time=120:00:00
#SBATCH --output=logs/humann3_single_%j.out
#SBATCH --error=logs/humann3_single_%j.err

# --- Fail the script if any command fails
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

echo "--- Job started on $(hostname) at $(date) ---"

# --- 1. Source configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/../../config.sh"

# --- 2. DEFINE DIRECTORIES ---
# Input is the clean output from the Kneaddata step
INPUT_DIR="$KNEADDATA_DIR"
OUTPUT_BASE_DIR="$HUMANN3_DIR"

# Use paths from configuration
NUC_DB="$HUMANN_NUC_DB"
PROT_DB="$HUMANN_PROT_DB"

mkdir -p "$OUTPUT_BASE_DIR"

echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_BASE_DIR"
echo "ChocoPhlAn DB: $NUC_DB"
echo "UniRef DB: $PROT_DB"

# --- 3. PROCESS EACH SAMPLE ---
# Loop through the sample subdirectories in the kneaddata output folder
processed_count=0
skipped_count=0

for SAMPLE_DIR in "$INPUT_DIR"/*; do
    if [ -d "$SAMPLE_DIR" ]; then
        SAMPLE_NAME=$(basename "$SAMPLE_DIR")

        # Define the output directory for this sample
        OUTPUT_DIR="$OUTPUT_BASE_DIR/$SAMPLE_NAME"

        # --- AUTO-RESUME CHECK ---
        GENE_FAMILIES_FILE="${OUTPUT_DIR}/${SAMPLE_NAME}_concatenated_genefamilies.tsv"
        if [[ -f "$GENE_FAMILIES_FILE" && -s "$GENE_FAMILIES_FILE" ]]; then
            echo ">>> Sample $SAMPLE_NAME is already processed. Final files found. Skipping."
            echo "---------------------------------"
            ((skipped_count++))
            continue
        fi
        # --- END OF CHECK ---

        echo ">>> Processing sample: $SAMPLE_NAME"

        mkdir -p "$OUTPUT_DIR"

        # Define paths to the final, clean paired-end FASTQ files from Kneaddata
        r1_file="${SAMPLE_DIR}/${SAMPLE_NAME}_1_val_1_kneaddata_paired_1.fastq"
        r2_file="${SAMPLE_DIR}/${SAMPLE_NAME}_1_val_1_kneaddata_paired_2.fastq"

        if [[ ! -f "$r1_file" || ! -f "$r2_file" ]]; then
            echo "ERROR: Missing clean Kneaddata FASTQ files for sample $SAMPLE_NAME. Skipping."
            continue
        fi

        # Define the temporary concatenated input file
        CONCAT_FILE="${OUTPUT_DIR}/${SAMPLE_NAME}_concatenated.fastq.gz"

        # --- Step 1: Concatenate and compress paired-end reads ---
        echo "    Concatenating reads for $SAMPLE_NAME..."
        cat "$r1_file" "$r2_file" | gzip > "$CONCAT_FILE"

        # --- Step 2: Run HUMAnN 3 ---
        echo "    Running HUMAnN 3 on $SAMPLE_NAME..."
        humann \
            --input "$CONCAT_FILE" \
            --output "$OUTPUT_DIR" \
            --nucleotide-database "$NUC_DB" \
            --protein-database "$PROT_DB" \
            --threads $SLURM_CPUS_PER_TASK \
            --o-log "${OUTPUT_DIR}/${SAMPLE_NAME}.log" \
            --remove-temp-output \
            --metaphlan-options="--bowtie2db $METAPHLAN_DB"

        # --- Step 3: Clean up the large temporary file ---
        echo "    Cleaning up temporary file for $SAMPLE_NAME..."
        rm "$CONCAT_FILE"

        # --- Step 4: Verify output ---
        # Check for expected output files (named based on input filename: sample_concatenated_*)
        genefamilies_file="${OUTPUT_DIR}/${SAMPLE_NAME}_concatenated_genefamilies.tsv"
        pathabundance_file="${OUTPUT_DIR}/${SAMPLE_NAME}_concatenated_pathabundance.tsv"
        pathcoverage_file="${OUTPUT_DIR}/${SAMPLE_NAME}_concatenated_pathcoverage.tsv"

        if [[ -f "$genefamilies_file" && -s "$genefamilies_file" && \
              -f "$pathabundance_file" && -s "$pathabundance_file" && \
              -f "$pathcoverage_file" && -s "$pathcoverage_file" ]]; then
            echo ">>> Successfully completed processing for $SAMPLE_NAME"
            echo "Output files:"
            echo "  Gene families: $genefamilies_file"
            echo "  Path abundance: $pathabundance_file"
            echo "  Path coverage: $pathcoverage_file"
            # Show file sizes for verification
            ls -lh "$genefamilies_file" "$pathabundance_file" "$pathcoverage_file"
            ((processed_count++))
        else
            echo ">>> ERROR: HUMAnN3 failed for sample: $SAMPLE_NAME"
            echo "Expected output files not found:"
            echo "  Gene families: $genefamilies_file"
            echo "  Path abundance: $pathabundance_file"
            echo "  Path coverage: $pathcoverage_file"
            echo "Files in output directory:"
            ls -la "$OUTPUT_DIR"
            exit 1
        fi

        echo "---------------------------------"
    fi
done

echo "--- HUMAnN 3 processing finished for all samples at $(date) ---"
echo "--- Processed samples: $processed_count ---"
echo "--- Skipped samples: $skipped_count ---"