#!/usr/bin/env bash
set -euo pipefail

#############################################
# PRS-CS pipeline for schizophrenia (SCZ)
# Run this script from your Termius working directory:
#   ~/Data_GENE/PRSCS
#
# Inputs expected in that directory:
#   impute_qc.bed/.bim/.fam
#   SCZ.txt
#   PGC_SCZ.QC.gz
#   ldblk_1kg_eas/
#############################################

WORK_DIR="${WORK_DIR:-$PWD}"
TARGET_PREFIX="${TARGET_PREFIX:-impute_qc}"
PHENO_FILE="${PHENO_FILE:-SCZ.txt}"
GWAS_RAW="${GWAS_RAW:-PGC_SCZ.QC.gz}"
GWAS_PRSCS="${GWAS_PRSCS:-PGC_SCZ.PRSCS.txt}"
REF_DIR="${REF_DIR:-ldblk_1kg_eas}"
PRSCS_PY="${PRSCS_PY:-}"
OUT_DIR="${OUT_DIR:-prscs_out}"
OUT_NAME="${OUT_NAME:-SCZ_PRSCS}"
OUT_PREFIX="${OUT_PREFIX:-${OUT_DIR}/${OUT_NAME}}"
PHI="${PHI:-1e-2}"
GWAS_SAMPLE_SIZE="${GWAS_SAMPLE_SIZE:-}"
PYTHON_BIN="${PYTHON_BIN:-python}"
PLINK_BIN="${PLINK_BIN:-plink}"

cd "${WORK_DIR}"
mkdir -p "${OUT_DIR}"

echo "[1/10] Checking required input files..."
for f in "${TARGET_PREFIX}.bed" "${TARGET_PREFIX}.bim" "${TARGET_PREFIX}.fam" "${PHENO_FILE}" "${GWAS_RAW}"; do
  [[ -f "$f" ]] || { echo "Missing file: $f"; exit 1; }
done
[[ -d "${REF_DIR}" ]] || { echo "Missing PRS-CS LD reference directory: ${REF_DIR}"; exit 1; }

echo "[1/10] Checking GWAS P-value distribution..."
PVAL_LE_05="$(gzip -dc "${GWAS_RAW}" | awk '
  NR==1{
    for(i=1;i<=NF;i++) if($i=="PVAL") p=i;
    if(p==""){print "ERROR_NO_PVAL"; exit}
    next
  }
  {
    pv=$p+0;
    if(pv <= 0.5) n05++;
  }
  END{print n05+0}')"
if [[ "${PVAL_LE_05}" == "ERROR_NO_PVAL" ]]; then
  echo "ERROR: ${GWAS_RAW} does not contain a PVAL column." >&2
  exit 1
fi
if [[ "${PVAL_LE_05}" == "0" ]]; then
  echo "ERROR: ${GWAS_RAW} has 0 SNPs with PVAL <= 0.5." >&2
  echo "This usually means the base file was incorrectly filtered on PVAL > 0.8 instead of IMPINFO > 0.8." >&2
  echo "Rebuild it with rebuild_pgc_scz_asian_base.sh before running PRS-CS." >&2
  exit 1
fi
echo "GWAS SNPs with PVAL <= 0.5: ${PVAL_LE_05}"

if [[ -z "${PRSCS_PY}" ]]; then
  for candidate in "PRScs.py" "PRScs/PRScs.py" "PRS-CS/PRScs.py" "PRScs-master/PRScs.py"; do
    if [[ -f "${candidate}" ]]; then
      PRSCS_PY="${candidate}"
      break
    fi
  done
fi
[[ -f "${PRSCS_PY}" ]] || {
  echo "ERROR: Cannot find PRScs.py." >&2
  echo "Run with: PRSCS_PY=/path/to/PRScs.py bash scripts/prscs_pipeline.sh" >&2
  exit 1
}

echo "[2/10] Converting GWAS summary statistics into PRS-CS format..."
gzip -dc "${GWAS_RAW}" | awk 'BEGIN{OFS="\t"}
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
echo "PRS-CS requires official LD block reference directory, e.g. ldblk_1kg_eas."
echo "Current REF_DIR=${REF_DIR}"

if [[ -z "${GWAS_SAMPLE_SIZE}" ]]; then
  echo "[3/10] GWAS_SAMPLE_SIZE not set; estimating from median NEFF in ${GWAS_RAW}..."
  GWAS_SAMPLE_SIZE="$(gzip -dc "${GWAS_RAW}" | awk '
    NR==1{
      for(i=1;i<=NF;i++) if($i=="NEFF") neff=i;
      if(neff==""){print "ERROR_NO_NEFF"; exit}
      next
    }
    $neff != "" && $neff != "NA" {
      n++;
      a[n]=$neff + 0
    }
    END{
      if(n==0){print "ERROR_EMPTY_NEFF"; exit}
      asort(a);
      if(n % 2){m=a[(n+1)/2]} else {m=(a[n/2]+a[n/2+1])/2}
      printf "%.0f\n", m
    }')"
  if [[ "${GWAS_SAMPLE_SIZE}" == ERROR_* ]]; then
    echo "ERROR: Could not estimate GWAS_SAMPLE_SIZE from NEFF. Please run with GWAS_SAMPLE_SIZE=<N>." >&2
    exit 1
  fi
  echo "Using GWAS_SAMPLE_SIZE=${GWAS_SAMPLE_SIZE} from median NEFF."
fi

echo "[4/10] Running PRS-CS for chromosomes 1-22..."
for CHR in $(seq 1 22); do
  echo "Running chromosome ${CHR}..."
  "${PYTHON_BIN}" "${PRSCS_PY}" \
    --ref_dir="${REF_DIR}" \
    --bim_prefix="${TARGET_PREFIX}" \
    --sst_file="${GWAS_PRSCS}" \
    --n_gwas="${GWAS_SAMPLE_SIZE}" \
    --phi="${PHI}" \
    --chrom="${CHR}" \
    --out_dir="${OUT_PREFIX}" \
    --write_pst=TRUE
done

echo "[5/10] Merging posterior effect files from chr1-22..."
EFFECT_MERGED="${OUT_DIR}/${OUT_NAME}_effects.txt"
printf "CHR\tSNP\tBP\tA1\tA2\tBETA\n" > "${EFFECT_MERGED}"
for CHR in $(seq 1 22); do
  FILE="$(find "${OUT_DIR}" . -maxdepth 1 -type f \( -name "${OUT_NAME}_pst_eff_a1_b0.5_phi*_chr${CHR}.txt" -o -name "${OUT_DIR}_pst_eff_a1_b0.5_phi*_chr${CHR}.txt" \) | sort | head -n 1)"
  [[ -n "${FILE}" ]] || { echo "Missing PRS-CS output for chr${CHR} in ${OUT_DIR}"; exit 1; }
  awk 'BEGIN{OFS="\t"} NR==1 && ($1=="CHR" || $1=="chrom" || $1=="Chrom") {next} {print}' "${FILE}" >> "${EFFECT_MERGED}"
done

echo "Created: ${EFFECT_MERGED}"

echo "[6/10] Computing PRS using PLINK --score..."
"${PLINK_BIN}" \
  --bfile "${TARGET_PREFIX}" \
  --score "${EFFECT_MERGED}" 2 4 6 header sum \
  --out "${OUT_DIR}/${OUT_NAME}_score"

echo "[7/10] Standardizing PRS and merging with phenotype using R script..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
Rscript "${SCRIPT_DIR}/prs_postprocess.R" \
  --score_profile "${OUT_DIR}/${OUT_NAME}_score.profile" \
  --pheno "${PHENO_FILE}" \
  --out_z "${OUT_DIR}/${OUT_NAME}_score_z.txt" \
  --out_merged "${OUT_DIR}/${OUT_NAME}_pheno_merged.txt"

echo "[8/10] Done."
echo "Key outputs:"
echo "  ${GWAS_PRSCS}"
echo "  ${EFFECT_MERGED}"
echo "  ${OUT_DIR}/${OUT_NAME}_score.profile"
echo "  ${OUT_DIR}/${OUT_NAME}_score_z.txt"
echo "  ${OUT_DIR}/${OUT_NAME}_pheno_merged.txt"
