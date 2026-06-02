#!/usr/bin/env bash
set -euo pipefail

# PRS-CS schizophrenia PRS template.
# Fill in file paths before running. Do NOT commit real genotype/GWAS/LD reference data.

PRSCS_DIR="${PRSCS_DIR:-$HOME/bio_software/PRScs}"
PYTHON="${PYTHON:-python}"

REF_DIR="/path/to/ldblk_1kg_eas"                    # LD reference directory (not backed up)
BIM_PREFIX="/path/to/target_genotype_prefix"         # prefix for target .bim (not backed up)
SUMSTATS="/path/to/schizophrenia_gwas_sumstats.txt"  # GWAS summary statistics (not backed up)
OUT_DIR="prscs_results"
N_GWAS="100000"                                      # replace with GWAS sample size

mkdir -p "$OUT_DIR"

"$PYTHON" "$PRSCS_DIR/PRScs.py" \
  --ref_dir="$REF_DIR" \
  --bim_prefix="$BIM_PREFIX" \
  --sst_file="$SUMSTATS" \
  --n_gwas="$N_GWAS" \
  --chrom=1 \
  --phi=1e-2 \
  --out_dir="$OUT_DIR" \
  --out_name="schizophrenia_prscs"
