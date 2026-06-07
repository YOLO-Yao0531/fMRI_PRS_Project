#!/usr/bin/env bash
set -euo pipefail

# High-resolution PRSice-2 C+T workflow for SCZ PRS.
#
# This script follows the two-round clumping strategy described in the
# manuscript text:
#   1) PLINK v1.90 pre-clumping against the 1000 Genomes Phase III EAS LD
#      reference using 250 kb and r2 >= 0.25.
#   2) PRSice clumping/scoring using 250 kb and r2 >= 0.1, then calculating
#      approximately 10,000 PRS thresholds from PT=0.0001 to PT=0.5 in steps
#      of 0.00005.
#
# Notes:
#   - The provided PGC_SCZ.QC.gz header already contains BETA, so this script
#     uses --stat BETA --beta. If your summary statistics instead contain odds
#     ratios, either log-convert OR to BETA before running this script, or set
#     STAT_COLUMN to the OR column and EFFECT_IS_OR=true to let PRSice use --or.
#   - --fastscore is intentionally NOT used because it only scores selected
#     bar-level thresholds and is not appropriate for a full high-resolution
#     PT scan.
#   - --all-score is enabled by default so downstream threshold-wise logistic
#     regression and imaging analyses can reuse all PRS columns. This can create
#     a large file; set ALL_SCORE=false if you only need PRSice summary outputs.

PRSICE_BIN="${PRSICE_BIN:-/ifs1/User/yaolei/bio_software/PRSice/PRSice}"
PLINK_BIN="${PLINK_BIN:-plink}"
BASE="${BASE:-PGC_SCZ.QC.gz}"
TARGET="${TARGET:-impute_qc}"
LDREF="${LDREF:-EAS_phase3_plink1}"
PHENO="${PHENO:-SCZ.txt}"
COV="${COV:-PCA_with_header.txt}"
OUT="${OUT:-PRSice_SCZ_highres}"
THREAD="${THREAD:-1}"

# Base summary-statistics columns.
SNP_COLUMN="${SNP_COLUMN:-ID}"
A1_COLUMN="${A1_COLUMN:-A1}"
A2_COLUMN="${A2_COLUMN:-A2}"
P_COLUMN="${P_COLUMN:-PVAL}"
STAT_COLUMN="${STAT_COLUMN:-BETA}"
EFFECT_IS_OR="${EFFECT_IS_OR:-false}"

# Two-round clumping controls.
RUN_PLINK_ROUND1="${RUN_PLINK_ROUND1:-true}"
ROUND1_OUT="${ROUND1_OUT:-PGC_SCZ_round1_plink_clump}"
ROUND1_SNPS="${ROUND1_SNPS:-${ROUND1_OUT}.snplist}"

# High-resolution PRS controls.
LOWER="${LOWER:-0.0001}"
UPPER="${UPPER:-0.5}"
INTERVAL="${INTERVAL:-0.00005}"
BAR_LEVELS="${BAR_LEVELS:-5e-08,1e-05,0.001,0.01,0.05,0.1,0.5}"
ALL_SCORE="${ALL_SCORE:-true}"
PERM="${PERM:-0}"
SEED="${SEED:-20260529}"

if [[ ! -f "${BASE}" ]]; then
  echo "Base summary statistics not found: ${BASE}" >&2
  exit 1
fi

if [[ ! -f "${TARGET}.bed" || ! -f "${TARGET}.bim" || ! -f "${TARGET}.fam" ]]; then
  echo "Target PLINK files not found: ${TARGET}.bed/.bim/.fam" >&2
  exit 1
fi

if [[ ! -f "${LDREF}.bed" || ! -f "${LDREF}.bim" || ! -f "${LDREF}.fam" ]]; then
  echo "LD reference PLINK files not found: ${LDREF}.bed/.bim/.fam" >&2
  exit 1
fi

if [[ ! -f "${PHENO}" ]]; then
  echo "Phenotype file not found: ${PHENO}" >&2
  exit 1
fi

if [[ "${RUN_PLINK_ROUND1}" == "true" ]]; then
  "${PLINK_BIN}" \
    --bfile "${LDREF}" \
    --clump "${BASE}" \
    --clump-snp-field "${SNP_COLUMN}" \
    --clump-field "${P_COLUMN}" \
    --clump-kb 250 \
    --clump-r2 0.25 \
    --clump-p1 1 \
    --clump-p2 1 \
    --out "${ROUND1_OUT}"

  awk '
    NR == 1 {
      for (i = 1; i <= NF; i++) {
        if ($i == "SNP") snp_col = i
      }
      if (snp_col == "") {
        print "Cannot find SNP column in PLINK clumped file header" > "/dev/stderr"
        exit 1
      }
      next
    }
    $snp_col != "" {print $snp_col}
  ' "${ROUND1_OUT}.clumped" > "${ROUND1_SNPS}"

  if [[ ! -s "${ROUND1_SNPS}" ]]; then
    echo "Round-1 SNP list is empty or missing: ${ROUND1_SNPS}" >&2
    echo "Check PLINK clumping output: ${ROUND1_OUT}.log and ${ROUND1_OUT}.clumped" >&2
    exit 1
  fi
fi

prsice_args=(
  --base "${BASE}"
  --target "${TARGET}"
  --ld "${LDREF}"
  --pheno "${PHENO}"
  --snp "${SNP_COLUMN}"
  --a1 "${A1_COLUMN}"
  --a2 "${A2_COLUMN}"
  --stat "${STAT_COLUMN}"
  --pvalue "${P_COLUMN}"
  --binary-target T
  --clump-kb 250kb
  --clump-r2 0.1
  --clump-p 1
  --score std
  --num-auto 22
  --thread "${THREAD}"
  --lower "${LOWER}"
  --upper "${UPPER}"
  --interval "${INTERVAL}"
  --bar-levels "${BAR_LEVELS}"
  --seed "${SEED}"
  --out "${OUT}"
)

if [[ -f "${COV}" ]]; then
  prsice_args+=(
    --cov "${COV}"
    --cov-col PC1,PC2,PC3,PC4,PC5,PC6,PC7,PC8,PC9,PC10
  )
else
  echo "Covariate file not found: ${COV}; running without --cov/--cov-col." >&2
fi

if [[ "${EFFECT_IS_OR}" == "true" ]]; then
  prsice_args+=(--or)
else
  prsice_args+=(--beta)
fi

if [[ "${RUN_PLINK_ROUND1}" == "true" ]]; then
  prsice_args+=(--extract "${ROUND1_SNPS}")
fi

if [[ "${ALL_SCORE}" == "true" ]]; then
  prsice_args+=(--all-score)
fi

if [[ "${PERM}" != "0" ]]; then
  prsice_args+=(--perm "${PERM}")
fi

"${PRSICE_BIN}" "${prsice_args[@]}"

# Empirical p-value example for the small n=126 target sample:
#   PERM=10000 THREAD=8 bash scripts/run_prsice_highres.sh
# If this is too slow, first reduce thresholds, for example:
#   INTERVAL=0.001 ALL_SCORE=false bash scripts/run_prsice_highres.sh
