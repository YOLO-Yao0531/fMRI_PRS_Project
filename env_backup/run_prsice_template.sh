#!/usr/bin/env bash
set -euo pipefail

# PRSice schizophrenia PRS template.
# Fill in file paths before running. Do NOT commit real genotype/GWAS/phenotype data.

PRSICE_R="${PRSICE_R:-$HOME/bio_software/PRSice/PRSice.R}"
PRSICE_BIN="${PRSICE_BIN:-$HOME/bio_software/PRSice/PRSice_linux}"
PLINK="${PLINK:-$HOME/bio_software/plink}"

BASE_GWAS="/path/to/schizophrenia_gwas_sumstats.txt"   # GWAS summary statistics (not backed up)
TARGET_PREFIX="/path/to/target_genotype_prefix"         # prefix for .bed/.bim/.fam (not backed up)
PHENO_FILE="/path/to/phenotype.tsv"                     # sample phenotype/covariate file (not backed up)
OUT_DIR="prsice_results"

mkdir -p "$OUT_DIR"

Rscript "$PRSICE_R" \
  --prsice "$PRSICE_BIN" \
  --plink "$PLINK" \
  --base "$BASE_GWAS" \
  --target "$TARGET_PREFIX" \
  --pheno "$PHENO_FILE" \
  --binary-target F \
  --stat OR \
  --or \
  --snp SNP \
  --chr CHR \
  --bp BP \
  --A1 A1 \
  --A2 A2 \
  --pvalue P \
  --out "$OUT_DIR/schizophrenia_prsice"
