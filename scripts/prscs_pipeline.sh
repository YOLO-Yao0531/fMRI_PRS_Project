#!/usr/bin/env bash
set -euo pipefail

#############################################
# PRS-CS pipeline for schizophrenia (SCZ)
# Inputs expected in working directory:
#   impute_qc.bed/.bim/.fam
#   SCZ.txt
#   PGC_SCZ.QC.gz
#   (optional) EAS_phase3_plink1.* (NOT the official PRS-CS LD blocks)
#############################################

# ========== User-configurable variables ==========
TARGET_PREFIX="impute_qc"
PHENO_FILE="SCZ.txt"
GWAS_RAW="PGC_SCZ.QC.gz"
GWAS_PRSCS="PGC_SCZ.PRSCS.txt"

# IMPORTANT: set this to official PRS-CS LD reference directory, e.g. ldblk_1kg_eas
REF_DIR="/path/to/ldblk_1kg_eas"

# Path to PRS-CS script (PRScs.py)
PRSCS_PY="/path/to/PRScs.py"

# Output directory
OUT_DIR="prscs_out"
OUT_NAME="SCZ_PRSCS"

# GWAS sample size for PRS-CS --n_gwas
# For case-control schizophrenia GWAS, effective sample size (NEFF) is generally preferred.
# Please verify the correct total N or effective N from your GWAS source before running.
GWAS_SAMPLE_SIZE="PLEASE_REPLACE_WITH_NEFF_OR_TOTAL_N"

# Threads for compression/sorting steps if needed later
THREADS=4
# ================================================

mkdir -p "${OUT_DIR}"

echo "[1/10] Checking required input files..."
for f in "${TARGET_PREFIX}.bed" "${TARGET_PREFIX}.bim" "${TARGET_PREFIX}.fam" "${PHENO_FILE}" "${GWAS_RAW}"; do
  [[ -f "$f" ]] || { echo "Missing file: $f"; exit 1; }
done

echo "[2/10] Converting GWAS summary statistics into PRS-CS format..."
# Required columns for PRS-CS: SNP A1 A2 BETA P
# Mapping:
#   SNP  <- ID
#   A1   <- A1
#   A2   <- A2
#   BETA <- BETA
#   P    <- PVAL
zcat "${GWAS_RAW}" | awk 'BEGIN{OFS="\t"}
NR==1{
  for(i=1;i<=NF;i++) h[$i]=i;
  needed[1]="ID"; needed[2]="A1"; needed[3]="A2"; needed[4]="BETA"; needed[5]="PVAL";
  for(i=1;i<=5;i++) if(!(needed[i] in h)){print "ERROR: missing column " needed[i] > "/dev/stderr"; exit 1}
  print "SNP","A1","A2","BETA","P";
  next
}
{
  snp=$h["ID"]; a1=$h["A1"]; a2=$h["A2"]; beta=$h["BETA"]; p=$h["PVAL"];
  if(snp=="" || a1=="" || a2=="" || beta=="" || p=="") next;
  print snp,a1,a2,beta,p;
}' > "${GWAS_PRSCS}"

echo "Created: ${GWAS_PRSCS}"

echo "[3/10] Reminder about LD reference..."
echo "Your EAS_phase3_plink1.bed/bim/fam is a standard PLINK dataset."
echo "PRS-CS typically requires official LD block reference directory (e.g., ldblk_1kg_eas)."
echo "Current REF_DIR=${REF_DIR}"

if [[ "${GWAS_SAMPLE_SIZE}" == "PLEASE_REPLACE_WITH_NEFF_OR_TOTAL_N" ]]; then
  echo "ERROR: Please set GWAS_SAMPLE_SIZE before running PRS-CS." >&2
  exit 1
fi
if [[ ! -d "${REF_DIR}" ]]; then
  echo "ERROR: REF_DIR does not exist: ${REF_DIR}" >&2
  exit 1
fi
if [[ ! -f "${PRSCS_PY}" ]]; then
  echo "ERROR: PRSCS_PY not found: ${PRSCS_PY}" >&2
  exit 1
fi

echo "[4/10] Running PRS-CS for chromosomes 1-22..."
for CHR in $(seq 1 22); do
  echo "Running chromosome ${CHR}..."
  python "${PRSCS_PY}" \
    --ref_dir="${REF_DIR}" \
    --bim_prefix="${TARGET_PREFIX}" \
    --sst_file="${GWAS_PRSCS}" \
    --n_gwas="${GWAS_SAMPLE_SIZE}" \
    --chrom="${CHR}" \
    --out_dir="${OUT_DIR}" \
    --out_name="${OUT_NAME}"
done

echo "[5/10] Merging posterior effect files from chr1-22..."
EFFECT_MERGED="${OUT_DIR}/${OUT_NAME}_effects.txt"
FIRST=1
> "${EFFECT_MERGED}"
for CHR in $(seq 1 22); do
  FILE="${OUT_DIR}/${OUT_NAME}_pst_eff_a1_b0.5_phi1e-02_chr${CHR}.txt"
  [[ -f "${FILE}" ]] || { echo "Missing PRS-CS output: ${FILE}"; exit 1; }
  if [[ ${FIRST} -eq 1 ]]; then
    cat "${FILE}" > "${EFFECT_MERGED}"
    FIRST=0
  else
    awk 'NR>1' "${FILE}" >> "${EFFECT_MERGED}"
  fi
done

echo "Created: ${EFFECT_MERGED}"

echo "[6/10] Computing PRS using PLINK --score..."
# PRS-CS output columns usually: CHR SNP BP A1 A2 BETA
# For plink --score <file> <SNP_col> <allele_col> <score_col> header sum
# So: SNP=2, effect allele(A1)=4, effect size(BETA)=6
plink \
  --bfile "${TARGET_PREFIX}" \
  --score "${EFFECT_MERGED}" 2 4 6 header sum \
  --out "${OUT_DIR}/${OUT_NAME}_score"

echo "[7/10] Standardizing PRS and merging with phenotype using R script..."
Rscript scripts/prs_postprocess.R \
  --score_profile "${OUT_DIR}/${OUT_NAME}_score.profile" \
  --pheno "${PHENO_FILE}" \
  --out_z "${OUT_DIR}/${OUT_NAME}_score_z.txt" \
  --out_merged "${OUT_DIR}/${OUT_NAME}_pheno_merged.txt"

echo "[8/10] Optional quick logistic regression checks (in R script output)."
echo "[9/10] Potential QC checks to perform are listed below."
cat <<'EOT'
QC checklist:
1) Genome build consistency: confirm PGC_SCZ.QC.gz build (hg19/GRCh37 vs hg38) matches target BIM BP/CHR.
2) Confirm GWAS A1 is effect allele.
3) Confirm PRS-CS output A1 is the allele to use in plink --score (typically yes).
4) Check strand-ambiguous SNPs (A/T, C/G).
5) Optionally remove A/T and C/G SNPs before scoring.
6) Check SNP ID overlap between target BIM and GWAS ID.
7) If target IDs are chr:pos but GWAS is rsID, map IDs via dbSNP or reference BIM and update IDs.
8) If plink allele mismatch occurs:
   - inspect .log and .nopred files
   - verify allele coding and strand
   - enforce uppercase alleles
   - liftover build if needed
   - harmonize IDs and remove problematic SNPs.
EOT

echo "[10/10] Done."
echo "Key outputs:"
echo "  ${GWAS_PRSCS}"
echo "  ${EFFECT_MERGED}"
echo "  ${OUT_DIR}/${OUT_NAME}_score.profile"
echo "  ${OUT_DIR}/${OUT_NAME}_score_z.txt"
echo "  ${OUT_DIR}/${OUT_NAME}_pheno_merged.txt"
