## sniff_platform.R — Detect GSEA output platform (gsealens-explorer v0.2.1)
##
## Usage:
##   Rscript sniff_platform.R <rds_path>
##
## Output to stdout: gsealens | enrichit | clusterprofiler | fgsea | unknown
## Exit code: 0=detected, 1=unknown, 2=file not found

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  cat("Usage: Rscript sniff_platform.R <rds_path>\n")
  quit(status = 2)
}

rds_path <- args[1]
if (!file.exists(rds_path)) { cat("ERROR: file not found\n"); quit(status = 2) }

x <- readRDS(rds_path)

if (inherits(x, "GseaRes")) { cat("gsealens\n"); quit(status = 0) }
if (inherits(x, "gseaResult")) {
  org <- tryCatch(x@organism, error = function(e) NULL)
  if (!is.null(org) && nzchar(org)) { cat("clusterprofiler\n") }
  else                              { cat("enrichit\n") }
  quit(status = 0)
}
if (is.list(x) && "pathway" %in% names(x) && "NES" %in% names(x) && "padj" %in% names(x)) {
  cat("fgsea\n"); quit(status = 0)
}

cat("unknown\n")
quit(status = 1)
