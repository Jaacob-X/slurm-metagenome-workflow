# Metagenome Analysis Pipeline for SLURM

Work Done by Jacob(Jingchu) Xu and Charles(Hao) Chen

A comprehensive metagenome analysis pipeline designed for HPC clusters using SLURM job arrays.

> ⚠️ **SYSTEM-SPECIFIC NOTICE**: These scripts are specifically designed for the **Mass General Brigham (MGB) ERISTwo HPC system**. Module loading commands, partition names, and paths are configured for ERISTwo. See [Portability](#portability-to-other-hpc-systems) for adapting to other systems.

## Overview

This pipeline processes metagenomic sequencing data through the following steps:

1. **Download** - Fetch raw reads from SRA using sra-tools
2. **FastQC** - Quality control assessment of raw reads
3. **Trim Galore** - Adapter trimming and quality filtering
4. **Kneaddata** - Host genome removal (human contamination)
5. **Kraken2** - Taxonomic classification
6. **HUMAnN3** - Functional profiling

## ERISTwo-Specific Configuration

This pipeline uses the following ERISTwo modules:

```bash
module load miniforge3          # Conda environment manager
module load fastqc/0.12.1       # Quality control
module load trimgalore/0.6.10   # Read trimming
```

Conda environments required:
- `sra-tools` - For downloading SRA data
- `kneaddata` - For host removal
- `kraken2.1.3` - For taxonomic classification
- `humann3` - For functional profiling

## Portability to Other HPC Systems

⚠️ **Applying this pipeline to other HPC systems requires modifications:**

| Component | ERISTwo Setting | What to Change |
|-----------|-----------------|----------------|
| Module system | `module load miniforge3` | Module names/versions differ per system |
| Partitions | `normal`, `long` | Queue names are system-specific |
| Trimmomatic path | Conda env specific | Must find YOUR kneaddata env path (see below) |
| Database paths | `/data/shenlab/db/...` | Update all database locations |
| Account/billing | Optional `--account` | May be required on your system |

### Finding Your Trimmomatic Path

The `TRIMMOMATIC_PATH` in `config.sh` must point to your specific kneaddata conda environment. To find it:

```bash
conda activate kneaddata
echo $CONDA_PREFIX/share/trimmomatic-*/
```

This will output something like `/home/user/miniconda3/envs/kneaddata/share/trimmomatic-0.39-2/`. Use this path in your `config.sh`.

### Checklist for Porting

1. [ ] Update module names in all `.slurm` scripts
2. [ ] Change partition names to match your system
3. [ ] Verify conda environment names or create new ones
4. [ ] Update all database paths in `config.sh`
5. [ ] Adjust resource allocations (memory, CPUs, time) as needed
6. [ ] Test with a single sample before full runs

## Prerequisites

### Software Requirements
- SLURM job scheduler
- Conda/Mamba package manager
- Required tools: FastQC, Trim Galore, Kneaddata, Kraken2, HUMAnN3

### Database Requirements

See [ENVIRONMENT_SETUP.md](ENVIRONMENT_SETUP.md) for detailed environment setup and database download instructions.

| Database | Tool | Size | Required |
|----------|------|------|----------|
| Human genome (hg39) | Kneaddata | ~6 GB | Yes |
| PlusPF | Kraken2 | ~70 GB | Yes |
| ChocoPhlAn (full) | HUMAnN3 | ~15 GB | Yes |
| UniRef90 Diamond | HUMAnN3 | ~35 GB | Yes |
| MetaPhlAn (mpa_vOct22) | HUMAnN3 | ~1.5 GB | Yes |
| Utility Mapping (full) | HUMAnN3 | ~2.5 GB | Optional* |

\* Utility mapping is only needed for post-processing to add human-readable gene/pathway names to results.

## Installation

1. Clone or download this repository:
   ```bash
   git clone <repository-url>
   cd slurm-metagenome-workflow
   ```

2. Create configuration file:
   ```bash
   cp config_example.sh config.sh
   ```

3. Edit `config.sh` with your settings:
   ```bash
   # Required settings
   PROJECT_ID="your_project"
   BASE_DIR="/path/to/your/project"
   DATABASE_DIR="/path/to/databases"
   SAMPLE_LIST="/path/to/samples.txt"
   NUM_SAMPLES=74  # Number of samples
   # On line 127, update to your kneaddata env path
   TRIMMOMATIC_PATH="/path/to/envs/kneaddata/share/trimmomatic-0.39-2/"  # Path to Trimmomatic
   ```

4. Create your sample list file (one SRR ID per line):
   ```
   SRR15966642
   SRR15966641
   ...
   ```

5. Validate configuration:
   ```bash
   ./run_pipeline.sh --validate-config
   ```

## Usage

### Running Pipeline Steps

Run each step sequentially, waiting for completion before the next:

```bash
# Step 1: Download raw data
./run_pipeline.sh --step download

# Step 2: Quality control (after download completes)
./run_pipeline.sh --step fastqc

# Step 3: Trim reads (after download completes)
./run_pipeline.sh --step trimgalore

# Step 4: Remove host contamination (after trimgalore completes)
./run_pipeline.sh --step kneaddata

# Step 5: Taxonomic classification (after kneaddata completes)
./run_pipeline.sh --step kraken2

# Step 6: Functional profiling (after kneaddata completes)
./run_pipeline.sh --step humann3
```

### Command Options

```bash
./run_pipeline.sh --step STEP [OPTIONS]

Options:
  --step STEP              Required. Step to run (download|fastqc|trimgalore|kneaddata|kraken2|humann3)
  --script-version VER     Use 'array' (default) or 'original' (single-job) scripts
  --dry-run                Show sbatch command without executing
  --resume                 Skip already completed samples
  --validate-config        Validate configuration only
  --help                   Show help message
```

### Examples

```bash
# Preview what would be submitted
./run_pipeline.sh --step fastqc --dry-run

# Use single-job scripts instead of array jobs
./run_pipeline.sh --step trimgalore --script-version original

# Resume after partial completion
./run_pipeline.sh --step kneaddata --resume
```

## Output Structure

After running the pipeline, your `BASE_DIR` will contain:

```
your_project/
├── raw_reads/                 # Downloaded FASTQ files (.fastq.gz)
├── fastqc_results/            # FastQC reports per sample
│   └── SRR*/
├── trimmed_reads/             # Trimmed reads from Trim Galore
│   └── SRR*/
│       ├── *_1_val_1.fq.gz
│       └── *_2_val_2.fq.gz
├── kneaddata_output/          # Host-removed reads
│   └── SRR*/
│       ├── *_kneaddata_paired_1.fastq
│       └── *_kneaddata_paired_2.fastq
├── kraken2_output/            # Taxonomic classifications
│   └── SRR*/
│       ├── *_kraken_report.txt
│       └── *_kraken_output.txt
├── humann3_output/            # Functional profiles
│   └── SRR*/
│       ├── *_genefamilies.tsv
│       ├── *_pathabundance.tsv
│       └── *_pathcoverage.tsv
└── logs/                      # SLURM job logs
```

## Configuration Reference

Key settings in `config.sh`:

### Resource Allocations

| Step | Default CPUs | Default Memory | Default Time |
|------|--------------|----------------|--------------|
| Download | 4 | 4G | 48:00:00 |
| FastQC | 4 | 8G | 2:00:00 |
| Trim Galore | 16 | 32G | 8:00:00 |
| Kneaddata | 16 | 32G | 12:00:00 |
| Kraken2 | 32 | 128G | 8:00:00 |
| HUMAnN3 | 32 | 128G | 16:00:00 |

### Concurrency Limits

Array jobs limit concurrent tasks to prevent overloading the cluster:

```bash
MAX_CONCURRENT_FASTQC=20
MAX_CONCURRENT_TRIMGALORE=20
MAX_CONCURRENT_KNEADDATA=20
MAX_CONCURRENT_KRAKEN2=20
MAX_CONCURRENT_HUMANN3=20
```

### Tool Parameters

```bash
# Trim Galore settings (from original working scripts)
TRIMGALORE_QUALITY=0           # No quality trimming (adapter only)
TRIMGALORE_STRINGENCY=5        # Adapter overlap requirement
TRIMGALORE_MIN_LENGTH=10       # Minimum read length
```

## Monitoring Jobs

```bash
# Check your running jobs
squeue -u $USER

# Check specific job details
scontrol show job <job_id>

# View job array status
squeue -u $USER -r  # Show individual array tasks

# Cancel a job
scancel <job_id>

# Cancel all your jobs
scancel -u $USER
```

## Troubleshooting

### Common Issues

**1. "Module not found" error**
- Verify module names: `module avail fastqc`
- Module names are system-specific; update scripts for your HPC

**2. "Partition not available" error**
- Check available partitions: `sinfo`
- Update `SLURM_PARTITION` in config.sh

**3. Jobs fail immediately**
- Check log files in `logs/` directory
- Verify all paths in config.sh exist
- Ensure conda environments are created

**4. "Sample already processed" but output missing**
- Auto-resume checks specific output files
- Delete incomplete output directories to reprocess

**5. Out of memory errors**
- Increase memory in config.sh (e.g., `KNEADDATA_MEM=64G`)
- Reduce concurrent jobs (e.g., `MAX_CONCURRENT_KNEADDATA=4`)

**6. Database not found**
- Verify database paths in config.sh
- Ensure databases are downloaded and indexed

### Checking Job Logs

```bash
# View recent logs
ls -lt logs/ | head

# Check specific job output
cat logs/fastqc_12345_1.out

# Search for errors across all logs
grep -l "ERROR" logs/*.err
```

## Array vs Single-Job Scripts

| Feature | Array Scripts | Single-Job Scripts |
|---------|---------------|-------------------|
| Speed | 4-20x faster | Sequential processing |
| Resource usage | Parallel samples | One sample at a time |
| Failure handling | One sample fails, others continue | Stops on first failure |
| Best for | Large sample counts | Testing, debugging |

Use `--script-version original` for single-job scripts when debugging or testing.

## Directory Structure

```
slurm-metagenome-workflow/
├── config_example.sh          # Template configuration (copy to config.sh)
├── run_pipeline.sh            # Main pipeline runner
├── ENVIRONMENT_SETUP.md       # Environment and database setup guide
├── README.md                  # This file
├── samples_example.txt        # Example sample list (SRR IDs)
├── env_files/                 # Conda environment YAML files
│   ├── humann3_env.yml
│   ├── kneaddata_env.yml
│   └── kraken_env.yml
└── scripts/
    ├── array_optimized/       # SLURM array job scripts (faster)
    │   ├── 01_download_fixed.slurm
    │   ├── 02_fastqc_array.slurm
    │   ├── 03_trimgalore_array.slurm
    │   ├── 04_kneaddata_array.slurm
    │   ├── 05_kraken2_array.slurm
    │   └── 06_humann3_array.slurm
    └── single_job/            # Single-job scripts (sequential)
        ├── 02_fastqc.slurm
        ├── 03_trimgalore.slurm
        ├── 04_kneaddata.slurm
        ├── 05_kraken2.slurm
        └── 06_humann3.slurm
```
