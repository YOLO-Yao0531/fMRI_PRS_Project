#!/usr/bin/env bash
set -euo pipefail

# Rebuild QC'ed Asian PGC3 SCZ GWAS summary statistics for PRSice/PRS-CS.
#
# This script intentionally detects columns by header names instead of hard-coded
# column numbers. The previous column-number workflow accidentally filtered on
# PVAL > 0.8, which makes PT scans from 0.0001 to 0.5 impossible.

RAW="${RAW:-PGC3_SCZ_wave3.asian.autosome.public.v3.vcf.tsv.gz}"
OUT="${OUT:-PGC_SCZ.QC.gz}"
INFO_MIN="${INFO_MIN:-0.8}"
REMOVE_AMBIGUOUS="${REMOVE_AMBIGUOUS:-true}"

if [[ ! -f "${RAW}" ]]; then
  echo "Raw Asian PGC SCZ file not found: ${RAW}" >&2
  exit 1
fi

tmp_out="${OUT}.tmp"
rm -f "${tmp_out}"

gzip -dc "${RAW}" | awk -v info_min="${INFO_MIN}" -v remove_ambiguous="${REMOVE_AMBIGUOUS}" '
BEGIN { OFS = "\t" }
/^##/ { next }
NR == 1 || /^#CHROM/ {
  for (i = 1; i <= NF; i++) {
    key = $i
    gsub(/^#/, "", key)
    h[key] = i
  }

  required[1] = "CHROM"
  required[2] = "ID"
  required[3] = "POS"
  required[4] = "A1"
  required[5] = "A2"
  required[6] = "BETA"
  required[7] = "SE"
  required[8] = "PVAL"
  for (i = 1; i <= 8; i++) {
    if (!(required[i] in h)) {
      print "ERROR: missing required column " required[i] > "/dev/stderr"
      exit 1
    }
  }

  print "CHROM", "ID", "POS", "A1", "A2", "FCAS", "FCON", "IMPINFO", "BETA", "SE", "PVAL", "NCAS", "NCON", "NEFF"
  next
}
{
  chr = $(h["CHROM"])
  sub(/^chr/, "", chr)
  sub(/^CHR/, "", chr)
  id = $(h["ID"])
  pos = $(h["POS"])
  a1 = toupper($(h["A1"]))
  a2 = toupper($(h["A2"]))
  beta = $(h["BETA"])
  se = $(h["SE"])
  pval = $(h["PVAL"])

  fcas = ("FCAS" in h ? $(h["FCAS"]) : "NA")
  fcon = ("FCON" in h ? $(h["FCON"]) : "NA")
  imp = ("IMPINFO" in h ? $(h["IMPINFO"]) : "NA")
  ncas = ("NCAS" in h ? $(h["NCAS"]) : "NA")
  ncon = ("NCON" in h ? $(h["NCON"]) : "NA")
  neff = ("NEFF" in h ? $(h["NEFF"]) : "NA")

  raw_n++
  if (chr == "" || id == "" || pos == "" || a1 == "" || a2 == "" || beta == "" || se == "" || pval == "") { missing_n++; next }
  if (chr !~ /^([1-9]|1[0-9]|2[0-2])$/) { chr_n++; next }
  if (a1 !~ /^[ACGT]$/ || a2 !~ /^[ACGT]$/) { allele_n++; next }
  if (remove_ambiguous == "true" && ((a1 == "A" && a2 == "T") || (a1 == "T" && a2 == "A") || (a1 == "G" && a2 == "C") || (a1 == "C" && a2 == "G"))) { ambig_n++; next }
  if (("IMPINFO" in h) && (imp == "" || imp == "NA" || imp + 0 < info_min)) { info_n++; next }
  if (pval + 0 <= 0 || pval + 0 > 1) { pval_n++; next }
  if (se + 0 <= 0) { se_n++; next }
  if (seen[id]++) { dup_n++; next }

  kept_n++
  print chr, id, pos, a1, a2, fcas, fcon, imp, beta, se, pval, ncas, ncon, neff
}
END {
  print "QC filter counts:" > "/dev/stderr"
  print "raw_data_rows", raw_n + 0 > "/dev/stderr"
  print "excluded_missing_required", missing_n + 0 > "/dev/stderr"
  print "excluded_non_autosome", chr_n + 0 > "/dev/stderr"
  print "excluded_non_acgt_allele", allele_n + 0 > "/dev/stderr"
  print "excluded_ambiguous", ambig_n + 0 > "/dev/stderr"
  print "excluded_low_info", info_n + 0 > "/dev/stderr"
  print "excluded_bad_pval", pval_n + 0 > "/dev/stderr"
  print "excluded_bad_se", se_n + 0 > "/dev/stderr"
  print "excluded_duplicate_id", dup_n + 0 > "/dev/stderr"
  print "kept", kept_n + 0 > "/dev/stderr"
}
' | gzip > "${tmp_out}"

mv "${tmp_out}" "${OUT}"

echo "Created: ${OUT}"
echo "P-value distribution:"
gzip -dc "${OUT}" | awk '
NR == 1 {
  for (i = 1; i <= NF; i++) if ($i == "PVAL") p = i
  next
}
{
  pv = $p + 0
  n++
  if (pv < min || n == 1) min = pv
  if (pv > max || n == 1) max = pv
  if (pv <= 0.5) n05++
  if (pv <= 0.05) n005++
  if (pv <= 0.001) n0001++
}
END {
  print "total", n + 0
  print "min_PVAL", min
  print "max_PVAL", max
  print "P<=0.5", n05 + 0
  print "P<=0.05", n005 + 0
  print "P<=0.001", n0001 + 0
  if (n05 + 0 == 0) {
    print "ERROR: no SNP has PVAL <= 0.5; do not use this file for PRSice PT scans." > "/dev/stderr"
    exit 1
  }
}'
