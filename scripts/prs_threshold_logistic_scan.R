#!/usr/bin/env Rscript

# Re-run PT-wise logistic regression from PRSice all-score output:
#   SCZ ~ PRS + PC1 + ... + PC10
# Uses base R only and computes Nagelkerke pseudo-R2 manually.

args <- commandArgs(trailingOnly = TRUE)
score_file <- if (length(args) >= 1) args[[1]] else NA_character_
pheno_file <- if (length(args) >= 2) args[[2]] else "SCZ.txt"
cov_file <- if (length(args) >= 3) args[[3]] else "PCA_with_header.txt"
out_file <- if (length(args) >= 4) args[[4]] else "PRS_threshold_logistic_results.txt"

if (is.na(score_file)) {
  candidates <- c("PRSice_SCZ_highres.all_score", "PRSice_SCZ_highres.all.score")
  score_file <- candidates[file.exists(candidates)][1]
}
if (is.na(score_file) || !file.exists(score_file)) {
  stop("Cannot find PRSice all-score file. Expected PRSice_SCZ_highres.all_score or .all.score, or pass it as argument 1.")
}
if (!file.exists(pheno_file)) stop("Phenotype file not found: ", pheno_file)

read_tab <- function(path) {
  read.table(path, header = TRUE, sep = "", stringsAsFactors = FALSE,
             check.names = FALSE, comment.char = "")
}

nagelkerke_r2 <- function(fit_full, fit_null) {
  n <- stats::nobs(fit_full)
  ll_full <- as.numeric(stats::logLik(fit_full))
  ll_null <- as.numeric(stats::logLik(fit_null))
  cs <- 1 - exp((2 / n) * (ll_null - ll_full))
  max_cs <- 1 - exp((2 / n) * ll_null)
  cs / max_cs
}

score <- read_tab(score_file)
pheno <- read_tab(pheno_file)
use_cov <- file.exists(cov_file)
if (use_cov) {
  cov <- read_tab(cov_file)
} else {
  message("Covariate file not found: ", cov_file, "; fitting PHENO ~ PRS only.")
}

required_ids <- c("FID", "IID")
if (!all(required_ids %in% names(score))) stop("Score file must contain FID and IID")
if (!all(required_ids %in% names(pheno))) stop("SCZ.txt must contain FID and IID")
if (use_cov && !all(required_ids %in% names(cov))) stop("PCA_with_header.txt must contain FID and IID")

pheno_candidates <- setdiff(names(pheno), required_ids)
if (length(pheno_candidates) == 0) stop("No phenotype column found in SCZ.txt")
pheno_col <- pheno_candidates[[1]]

pheno_keep <- pheno[, c("FID", "IID", pheno_col), drop = FALSE]
names(pheno_keep)[names(pheno_keep) == pheno_col] <- "PHENO"

dat <- merge(score, pheno_keep, by = c("FID", "IID"))

pc_cols <- paste0("PC", 1:10)
if (use_cov) {
  dat <- merge(dat, cov, by = c("FID", "IID"))
  if (!all(pc_cols %in% names(dat))) {
    stop("Missing one or more PC columns: ", paste(setdiff(pc_cols, names(dat)), collapse = ", "))
  }
} else {
  pc_cols <- character(0)
}

# Force common binary encodings to 0/1 for logistic regression.
u <- sort(unique(dat$PHENO[!is.na(dat$PHENO)]))
if (all(u %in% c(1, 2))) {
  dat$PHENO <- ifelse(dat$PHENO == 2, 1, 0)
} else if (!all(u %in% c(0, 1))) {
  stop("PHENO must be binary coded as 0/1 or 1/2; observed values: ", paste(u, collapse = ", "))
}

non_prs <- c("FID", "IID", "PHENO", pc_cols)
prs_cols <- setdiff(names(dat), non_prs)
if (length(prs_cols) == 0) stop("No PRS threshold columns found in score file")

if (length(pc_cols) > 0) {
  fit_null <- stats::glm(PHENO ~ ., data = dat[, c("PHENO", pc_cols), drop = FALSE],
                         family = stats::binomial())
} else {
  fit_null <- stats::glm(PHENO ~ 1, data = dat[, "PHENO", drop = FALSE],
                         family = stats::binomial())
}

res <- vector("list", length(prs_cols))
for (i in seq_along(prs_cols)) {
  prs <- prs_cols[[i]]
  model_dat <- dat[, c("PHENO", prs, pc_cols), drop = FALSE]
  names(model_dat)[2] <- "PRS"

  if (length(pc_cols) > 0) {
    fit_full <- stats::glm(PHENO ~ PRS + ., data = model_dat,
                           family = stats::binomial())
  } else {
    fit_full <- stats::glm(PHENO ~ PRS, data = model_dat,
                           family = stats::binomial())
  }
  sm <- summary(fit_full)$coefficients

  res[[i]] <- data.frame(
    PT = prs,
    beta = sm["PRS", "Estimate"],
    se = sm["PRS", "Std. Error"],
    p = sm["PRS", "Pr(>|z|)"],
    nagelkerke_r2 = nagelkerke_r2(fit_full, fit_null),
    stringsAsFactors = FALSE
  )
}

res <- do.call(rbind, res)
res <- res[order(res$p), ]
write.table(res, out_file, sep = "\t", quote = FALSE, row.names = FALSE)
cat("Saved:", out_file, "\n")
