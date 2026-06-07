#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
prsice_file <- if (length(args) >= 1) args[[1]] else "PRSice_SCZ_highres.prsice"
out_prefix <- if (length(args) >= 2) args[[2]] else "PRSice_SCZ_highres_fig1_style"

if (!file.exists(prsice_file)) stop("Input .prsice file not found: ", prsice_file)

x <- read.table(prsice_file, header = TRUE, sep = "", stringsAsFactors = FALSE,
                check.names = FALSE, comment.char = "")

pick_col <- function(candidates, table_names) {
  hit <- candidates[candidates %in% table_names]
  if (length(hit) == 0) stop("Cannot find any of these columns: ", paste(candidates, collapse = ", "))
  hit[[1]]
}

pt_col <- pick_col(c("Threshold", "Pt", "P_T", "PThreshold", "thresh"), names(x))
r2_col <- pick_col(c("R2", "PRS.R2", "Full.R2", "Nagelkerke.R2", "Model.R2"), names(x))
p_col <- pick_col(c("P", "P.value", "P-value", "PRS.P", "Model.P"), names(x))

x$PT_NUM <- as.numeric(x[[pt_col]])
x$R2_NUM <- as.numeric(x[[r2_col]])
x$P_NUM <- as.numeric(x[[p_col]])
x <- x[is.finite(x$PT_NUM) & is.finite(x$R2_NUM) & is.finite(x$P_NUM), ]
x <- x[order(x$PT_NUM), ]
x$NEGLOG10P <- -log10(pmax(x$P_NUM, .Machine$double.xmin))

best <- x[which.max(x$R2_NUM), ]

bar_levels_env <- Sys.getenv("BAR_PTS", unset = "0.001,0.05,0.1,0.2,0.3,best,0.4,0.5")
bar_tokens <- trimws(strsplit(bar_levels_env, ",", fixed = TRUE)[[1]])
bar_levels <- vapply(bar_tokens, function(z) {
  if (tolower(z) == "best") return(best$PT_NUM)
  as.numeric(z)
}, numeric(1))
bar_levels <- unique(bar_levels[is.finite(bar_levels)])
bar_levels <- bar_levels[bar_levels >= min(x$PT_NUM) & bar_levels <= max(x$PT_NUM)]

nearest_rows <- lapply(bar_levels, function(pt) x[which.min(abs(x$PT_NUM - pt)), , drop = FALSE])
bar_dat <- do.call(rbind, nearest_rows)
bar_dat <- bar_dat[!duplicated(bar_dat$PT_NUM), ]

make_cols <- function(values) {
  pal <- grDevices::colorRampPalette(c("#A85C86", "#B33445", "#C21F1F"))(100)
  rng <- range(values, na.rm = TRUE)
  if (diff(rng) == 0) return(rep(pal[50], length(values)))
  idx <- round(1 + 99 * (values - rng[1]) / diff(rng))
  pal[pmax(1, pmin(100, idx))]
}

plot_figure <- function(device_fun, filename, width, height, res = NULL) {
  if (is.null(res)) {
    device_fun(filename, width = width, height = height)
  } else {
    device_fun(filename, width = width, height = height, units = "in", res = res)
  }
  on.exit(grDevices::dev.off(), add = TRUE)

  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par), add = TRUE)

  layout(matrix(c(1, 2), nrow = 1), widths = c(1, 1.2))
  par(family = "serif", mar = c(5.2, 4.8, 3.5, 1.2), oma = c(0, 0, 3, 0))

  bar_cols <- make_cols(bar_dat$NEGLOG10P)
  ymax <- max(bar_dat$R2_NUM, na.rm = TRUE) * 1.25
  bp <- barplot(bar_dat$R2_NUM,
                names.arg = format(bar_dat$PT_NUM, trim = TRUE, scientific = FALSE),
                col = bar_cols, border = NA, ylim = c(0, ymax), las = 2,
                ylab = expression(paste("PRS model fit: ", R^2)),
                xlab = expression(paste(italic(P), "-value threshold (", italic(P)[T], ")")),
                main = "A")
  text(bp, bar_dat$R2_NUM + ymax * 0.03,
       labels = signif(bar_dat$P_NUM, 2), srt = 45, adj = 0, cex = 0.8)

  legend_vals <- pretty(range(bar_dat$NEGLOG10P, na.rm = TRUE), n = 3)
  legend("right", title = expression(paste(-log[10], " model\nP-value")),
         legend = round(legend_vals, 2), fill = make_cols(legend_vals),
         bty = "n", cex = 0.85)

  par(mar = c(5.2, 4.8, 3.5, 1.2))
  plot(x$PT_NUM, x$NEGLOG10P,
       pch = 16, cex = 0.35, col = "black",
       xlab = expression(paste(italic(P), "-value threshold")),
       ylab = expression(paste("PRS model fit: ", -log[10], "(", italic(P), ")")),
       main = "B")

  line_n <- min(80, max(10, floor(nrow(x) / 100)))
  breaks <- unique(round(seq(1, nrow(x), length.out = line_n)))
  trend <- x[breaks, ]
  lines(trend$PT_NUM, trend$NEGLOG10P, col = "#00D923", lwd = 1.2, type = "b", pch = 16, cex = 0.45)
  points(best$PT_NUM, best$NEGLOG10P, col = "#00D923", pch = 17, cex = 1.3)
  text(best$PT_NUM, best$NEGLOG10P, labels = paste0("best PT=", signif(best$PT_NUM, 4)),
       pos = 3, cex = 0.75, col = "#008A16")

  mtext("PRS-SCZ in all participants", outer = TRUE, cex = 1.6, font = 2)
}

plot_figure(grDevices::png, paste0(out_prefix, ".png"), width = 12, height = 6.5, res = 300)
plot_figure(grDevices::pdf, paste0(out_prefix, ".pdf"), width = 12, height = 6.5)

cat("Saved:", paste0(out_prefix, ".png"), "and", paste0(out_prefix, ".pdf"), "\n")
