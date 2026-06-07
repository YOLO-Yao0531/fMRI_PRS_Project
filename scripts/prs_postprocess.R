#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key, default = NULL) {
  idx <- which(args == key)
  if (length(idx) == 0) return(default)
  if (idx == length(args)) stop("Missing value for argument: ", key)
  args[idx + 1]
}

score_file <- get_arg("--score_profile", "SCZ_PRSCS_score.profile")
pheno_file <- get_arg("--pheno", "SCZ.txt")
out_z <- get_arg("--out_z", "SCZ_PRSCS_score_z.txt")
out_merged <- get_arg("--out_merged", "SCZ_PRSCS_pheno_merged.txt")

if (!file.exists(score_file)) {
  stop("Score profile file not found: ", score_file)
}

if (!file.exists(pheno_file)) {
  stop("Phenotype file not found: ", pheno_file)
}

score <- read.table(
  score_file,
  header = TRUE,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  colClasses = "character"
)
if (!all(c("FID", "IID") %in% names(score))) {
  stop("Score profile must include FID and IID columns.")
}

# PLINK 1.9 profile output is commonly SCORE or SCORESUM.
# PLINK 2 output can use SCORE1_SUM.
prs_col <- NULL
for (cn in c("SCORE", "SCORESUM", "SCORE1_SUM")) {
  if (cn %in% names(score)) {
    prs_col <- cn
    break
  }
}

if (is.null(prs_col)) {
  stop("No PRS score column found. Expected one of: SCORE, SCORESUM, SCORE1_SUM.")
}

score$PRS <- as.numeric(score[[prs_col]])
if (all(is.na(score$PRS))) {
  stop("Selected PRS column contains no numeric values: ", prs_col)
}

score$PRS_Z <- as.numeric(scale(score$PRS))
out_score <- score[, c("FID", "IID", "PRS", "PRS_Z")]
write.table(out_score, out_z, sep = "\t", quote = FALSE, row.names = FALSE)

pheno <- read.table(
  pheno_file,
  header = TRUE,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  colClasses = "character"
)
if (!all(c("FID", "IID") %in% names(pheno))) {
  stop("Phenotype file must include FID and IID columns.")
}

merged <- merge(pheno, out_score, by = c("FID", "IID"), all = FALSE)
write.table(merged, out_merged, sep = "\t", quote = FALSE, row.names = FALSE)

if (nrow(merged) == 0) {
  warning("Merged output has 0 rows. Check whether FID/IID match between ", score_file, " and ", pheno_file, ".")
}

cat("Input score file: ", score_file, "\n", sep = "")
cat("PRS column used: ", prs_col, "\n", sep = "")
cat("Input phenotype file: ", pheno_file, "\n", sep = "")
cat("Wrote z-scored PRS: ", out_z, " (", nrow(out_score), " samples)\n", sep = "")
cat("Wrote merged phenotype: ", out_merged, " (", nrow(merged), " matched samples)\n", sep = "")
