#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
infile <- if (length(args) >= 1) args[[1]] else "PRSice_SCZ_highres.prsice"
outfile <- if (length(args) >= 2) args[[2]] else "best_PT_summary.txt"

if (!file.exists(infile)) stop("Input .prsice file not found: ", infile)

x <- read.table(infile, header = TRUE, sep = "", stringsAsFactors = FALSE,
                check.names = FALSE, comment.char = "")

pick_col <- function(candidates, table_names, required = TRUE) {
  hit <- candidates[candidates %in% table_names]
  if (length(hit) > 0) return(hit[[1]])
  if (required) stop("Cannot find any of these columns: ", paste(candidates, collapse = ", "))
  NA_character_
}

pt_col <- pick_col(c("Threshold", "Pt", "P_T", "PThreshold", "thresh"), names(x))
r2_col <- pick_col(c("R2", "PRS.R2", "Full.R2", "Nagelkerke.R2", "Model.R2"), names(x))
p_col <- pick_col(c("P", "P.value", "P-value", "PRS.P", "Model.P"), names(x))

x[[r2_col]] <- as.numeric(x[[r2_col]])
best_i <- which.max(x[[r2_col]])
best <- x[best_i, , drop = FALSE]

res <- data.frame(
  best_threshold = best[[pt_col]],
  max_nagelkerke_r2 = best[[r2_col]],
  p_value = best[[p_col]],
  stringsAsFactors = FALSE
)

write.table(res, outfile, sep = "\t", quote = FALSE, row.names = FALSE)
cat("Saved:", outfile, "\n")
print(res)
