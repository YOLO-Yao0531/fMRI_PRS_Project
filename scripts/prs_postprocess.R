#!/usr/bin/env Rscript
suppressWarnings(suppressMessages({
  library(data.table)
}))

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key, default=NULL){
  idx <- which(args == key)
  if(length(idx)==0) return(default)
  args[idx+1]
}

score_file <- get_arg("--score_profile")
pheno_file <- get_arg("--pheno")
out_z <- get_arg("--out_z", "SCZ_PRSCS_score_z.txt")
out_merged <- get_arg("--out_merged", "SCZ_PRSCS_pheno_merged.txt")

if(is.null(score_file) || is.null(pheno_file)){
  stop("Usage: Rscript prs_postprocess.R --score_profile <file.profile> --pheno <SCZ.txt> [--out_z <file>] [--out_merged <file>]")
}

score <- fread(score_file)
if(!all(c("FID","IID") %in% names(score))) stop("score profile missing FID/IID")

# PLINK profile may provide SCORE or SCORESUM (or both).
prs_col <- NULL
for(cn in c("SCORE","SCORESUM","SCORE1_SUM")){
  if(cn %in% names(score)) { prs_col <- cn; break }
}
if(is.null(prs_col)) stop("No SCORE/SCORESUM/SCORE1_SUM found in profile file")

score[, PRS := get(prs_col)]
score[, PRS_Z := as.numeric(scale(PRS))]
out_dt <- score[, .(FID, IID, PRS, PRS_Z)]
fwrite(out_dt, out_z, sep="\t")

pheno <- fread(pheno_file)
if(!all(c("FID","IID") %in% names(pheno))) stop("phenotype file must include FID and IID")
merged <- merge(pheno, out_dt, by=c("FID","IID"), all=FALSE)
fwrite(merged, out_merged, sep="\t")

# Simple logistic regression checks
# Model 1: SCZ ~ PRS_Z
if("SCZ" %in% names(merged)){
  fit1 <- glm(SCZ ~ PRS_Z, data=merged, family=binomial())
  cat("\n=== Logistic regression: SCZ ~ PRS_Z ===\n")
  print(summary(fit1))

  pcs <- paste0("PC",1:10)
  if(all(pcs %in% names(merged))){
    form2 <- as.formula(paste("SCZ ~ PRS_Z +", paste(pcs, collapse=" + ")))
    fit2 <- glm(form2, data=merged, family=binomial())
    cat("\n=== Logistic regression: SCZ ~ PRS_Z + PC1..PC10 ===\n")
    print(summary(fit2))
  } else {
    cat("\nPC1-PC10 not all found; skipped covariate-adjusted model.\n")
  }
} else {
  cat("\nColumn 'SCZ' not found in merged phenotype; skipped logistic regression.\n")
}

cat("\nWrote:\n", out_z, "\n", out_merged, "\n", sep="")
