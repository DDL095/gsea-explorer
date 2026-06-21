## extract_gsea_capsule.R — GSEA data extraction (gsealens-explorer v0.2.1)
##
## Usage:
##   Rscript extract_gsea_capsule.R <rds_path> <output_dir> [contrast1] [contrast2] ...
##
## Output:
##   {out_dir}/{contrast}_Hallmark.csv
##   {out_dir}/{contrast}_GOBP_top30.csv
##   {out_dir}/{contrast}_ReactKEGG_top30.csv
##   {out_dir}/{contrast}_leading_edge.csv
##   {out_dir}/summary.md
##   {out_dir}/extract_log.txt
##
## Exit code: 0=success, 1=error, 2=validation failed

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  cat("Usage: Rscript extract_gsea_capsule.R <rds_path> <out_dir> [contrasts...]\n")
  quit(status = 1)
}

rds_path   <- args[1]
out_dir    <- args[2]
contrasts_arg <- if (length(args) >= 3) args[3:length(args)] else NULL

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
log_path <- file.path(out_dir, "extract_log.txt")
log_con  <- file(log_path, open = "wt")
log_msg  <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- sprintf("[%s] %s", ts, msg)
  cat(line, "\n")
  cat(line, "\n", file = log_con)
}

log_msg(sprintf("R session: %s", R.version.string))
log_msg(sprintf("RDS: %s", rds_path))
log_msg(sprintf("Output: %s", out_dir))

if (!file.exists(rds_path)) {
  log_msg(sprintf("ERROR: file not found"))
  close(log_con); quit(status = 1)
}

x <- readRDS(rds_path)

# Platform detection (flat if-chain, no nesting, avoids CRLF parser bug)
platform <- "unknown"
cls <- paste(class(x), collapse = ",")
if ("GseaRes" %in% class(x)) platform <- "gsealens"
if ("gseaResult" %in% class(x)) {
  org_val <- tryCatch(x@organism, error = function(e) NULL)
  if (!is.null(org_val) && nzchar(org_val)) {
    platform <- "clusterprofiler"
  }
  if (platform == "unknown") platform <- "enrichit"
}
if (is.list(x) && "pathway" %in% names(x) && "NES" %in% names(x) && "padj" %in% names(x)) {
  platform <- "fgsea"
}
log_msg(sprintf("Platform: %s (class: %s)", platform, paste(class(x), collapse=",")))

if (platform == "gsealens") {
  all_contrasts <- names(x$results)
} else {
  log_msg(sprintf("ERROR: only gsealens supported in this version, got %s", platform))
  close(log_con); quit(status = 1)
}

contrasts <- if (is.null(contrasts_arg)) all_contrasts else intersect(contrasts_arg, all_contrasts)
log_msg(sprintf("Contrasts to process (%d): %s", length(contrasts), paste(contrasts, collapse=", ")))

# Extract significant subset
get_sig <- function(result_list, cn, abs_nes = 1.5, fdr_cut = 0.05,
                    collections = NULL, top_n = NULL) {
  df <- result_list[[cn]]$data@result
  if (nrow(df) == 0) return(df[0,])
  df <- df[!is.na(df$p.adjust) & !is.na(df$NES), ]
  df <- df[df$p.adjust < fdr_cut & abs(df$NES) >= abs_nes, ]
  if (!is.null(collections)) df <- df[df$Collection %in% collections, ]
  df <- df[order(df$p.adjust, -abs(df$NES)), ]
  if (!is.null(top_n)) df <- utils::head(df, top_n)
  df
}

summary_lines <- c("# GSEA 显著通路数量汇总",
                   sprintf("生成时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
                   sprintf("RDS: %s", basename(rds_path)),
                   sprintf("平台: %s", platform),
                   "",
                   "> 使用 |NES| enrichment direction framework: NES>0 = 富集在 left_group, NES<0 = 富集在 right_group",
                   "")

csv_outputs <- c()
for (cn in contrasts) {
  log_msg(sprintf("Processing: %s", cn))
  res_obj <- x$results[[cn]]
  if (is.null(res_obj) || res_obj$status != "Success") {
    log_msg(sprintf("  Skip: status != Success")); next
  }
  full_df <- res_obj$data@result

  # Summary counts (use |NES| enrichment direction framework: enriched_in direction, not up/down)
  n_total <- nrow(full_df)
  n_sig   <- sum(full_df$p.adjust < 0.05, na.rm=TRUE)
  # Get left/right group names from contrast registry
  cr <- x$contrast_registry
  cr_row <- cr[cr$contrast_id == cn, ]
  left_g  <- if (nrow(cr_row) > 0) cr_row$left_group else "Left"
  right_g <- if (nrow(cr_row) > 0) cr_row$right_group else "Right"
  n_left  <- sum(full_df$p.adjust < 0.05 & full_df$NES > 0, na.rm=TRUE)
  n_right <- sum(full_df$p.adjust < 0.05 & full_df$NES < 0, na.rm=TRUE)
  summary_lines <- c(summary_lines,
    sprintf("- **%s** (%s vs %s): 总 %d, 显著 %d (富集在 %s: %d, 富集在 %s: %d)",
            cn, left_g, right_g, n_total, n_sig, left_g, n_left, right_g, n_right))

  # Hallmark
  h <- get_sig(x$results, cn, abs_nes=1.0, collections="H")
  h_path <- file.path(out_dir, sprintf("%s_Hallmark.csv", cn))
  write.csv(h, h_path, row.names=FALSE); csv_outputs <- c(csv_outputs, h_path)
  log_msg(sprintf("  Hallmark: %d rows", nrow(h)))

  # GO:BP — 全量提取 (无 top-N 限制)
  gobp <- get_sig(x$results, cn, abs_nes=1.0, collections="C5")
  gobp_sub <- gobp[gobp$Subcollection == "GO:BP", ]
  gobp_path <- file.path(out_dir, sprintf("%s_GOBP.csv", cn))
  write.csv(gobp_sub, gobp_path, row.names=FALSE); csv_outputs <- c(csv_outputs, gobp_path)
  log_msg(sprintf("  GOBP (full): %d rows", nrow(gobp_sub)))

  # Reactome + KEGG — 全量提取
  react <- get_sig(x$results, cn, abs_nes=1.0, collections="C2")
  react_sub <- react[grepl("REACTOME|KEGG", react$Combo_Name), ]
  react_path <- file.path(out_dir, sprintf("%s_ReactKEGG.csv", cn))
  write.csv(react_sub, react_path, row.names=FALSE); csv_outputs <- c(csv_outputs, react_path)
  log_msg(sprintf("  ReactKEGG (full): %d rows", nrow(react_sub)))

  # leading_edge (Hallmark only)
  if (nrow(h) > 0) {
    le <- data.frame(contrast=cn, pathway_id=h$ID, description=h$Description,
                     NES=h$NES, p.adjust=h$p.adjust, leading_edge_pct=h$leading_edge,
                     core_enrichment=h$core_enrichment, collection=h$Collection,
                     stringsAsFactors=FALSE)
  } else {
    le <- data.frame(contrast=character(), pathway_id=character(), description=character(),
                     NES=numeric(), p.adjust=numeric(), leading_edge_pct=character(),
                     core_enrichment=character(), collection=character())
  }
  le_path <- file.path(out_dir, sprintf("%s_leading_edge.csv", cn))
  write.csv(le, le_path, row.names=FALSE); csv_outputs <- c(csv_outputs, le_path)
  log_msg(sprintf("  leading_edge: %d rows", nrow(le)))

  # === |NES| enrichment direction |NES| 表 (Markdown) ===
  # 合并 Hallmark + GO:BP + Reactome/KEGG 显著通路, 按 |NES| 排序
  all_sig <- get_sig(x$results, cn, abs_nes=1.0, fdr_cut=0.25)
  if (nrow(all_sig) > 0) {
    # 添加 |NES| enrichment direction列
    all_sig$abs_NES <- abs(all_sig$NES)
    all_sig$Enriched_In <- ifelse(all_sig$NES > 0, left_g, right_g)
    all_sig$Confidence <- ifelse(all_sig$abs_NES >= 1.5 & all_sig$p.adjust < 0.05, "High",
                          ifelse(all_sig$abs_NES >= 1.0 & all_sig$p.adjust < 0.25, "Medium", "Low"))
    all_sig <- all_sig[order(-all_sig$abs_NES), ]

    # 统计
    n_high <- sum(all_sig$Confidence == "High")
    n_med  <- sum(all_sig$Confidence == "Medium")
    n_low  <- sum(all_sig$Confidence == "Low")

    # 生成 Markdown 表
    md_lines <- c()
    md_lines <- c(md_lines, sprintf("# |NES| enrichment direction table — %s", cn))
    md_lines <- c(md_lines, "")
    md_lines <- c(md_lines, sprintf("**对比组**: %s vs %s", left_g, right_g))
    md_lines <- c(md_lines, sprintf("**统计概览**: 总 %d 通路 (FDR<0.25, |NES|≥1.0) | 高置信: %d | 中置信: %d | 低置信: %d",
                                    nrow(all_sig), n_high, n_med, n_low))
    md_lines <- c(md_lines, "")
    md_lines <- c(md_lines, "| # | 通路 ID | \\|**|NES| enrichment direction framework**\| | 富集方向 | FDR | Collection | 置信度 |")
    md_lines <- c(md_lines, "|:--:|:-----------|:----:|:-----------:|:------:|:-----------|:------:|")

    for (i in seq_len(min(nrow(all_sig), 500))) {
      row <- all_sig[i, ]
      md_lines <- c(md_lines, sprintf("| %d | `%s` | %.2f | %s | %.2e | %s | %s |",
                    i, row$ID, row$abs_NES, row$Enriched_In, row$p.adjust,
                    row$Display_Collection, row$Confidence))
    }

    if (nrow(all_sig) > 500) {
      md_lines <- c(md_lines, sprintf("\n*(仅显示前 500 / 共 %d 通路)*", nrow(all_sig)))
    }

    md_lines <- c(md_lines, "")
    md_lines <- c(md_lines, "**字段说明**:")
    md_lines <- c(md_lines, "- **\\|**|NES| enrichment direction framework**\|**: 绝对标准化富集分数。≥1.5 显著, ≥2.0 强富集")
    md_lines <- c(md_lines, sprintf("- **富集方向**: 富集在 %s (NES>0) 或 富集在 %s (NES<0)", left_g, right_g))
    md_lines <- c(md_lines, "- **FDR**: 多重检验校正 P 值。FDR < 0.25 是 MSigDB 标准阈值")
    md_lines <- c(md_lines, "- **置信度**: High (|NES|≥1.5+FDR<0.05) / Medium (|NES|≥1.0+FDR<0.25) / Low")

    gsealens_path <- file.path(out_dir, sprintf("%s_gsealens_table.md", cn))
    writeLines(md_lines, gsealens_path)
    log_msg(sprintf("  gsealens_table: %d rows (md)", nrow(all_sig)))
  } else {
    log_msg(sprintf("  gsealens_table: 0 significant pathways"))
  }
}

writeLines(summary_lines, file.path(out_dir, "summary.md"))

# === Validation ===
log_msg("=== Validation ===")
all_ok <- TRUE
for (p in csv_outputs) {
  if (!file.exists(p)) { log_msg(sprintf("  FAIL: %s missing", basename(p))); all_ok <- FALSE; next }
  sz <- file.info(p)$size
  if (sz < 1024) { log_msg(sprintf("  FAIL: %s size=%d", basename(p), sz)); all_ok <- FALSE; next }
  df <- tryCatch(read.csv(p, stringsAsFactors=FALSE), error=function(e) NULL)
  if (is.null(df) || nrow(df) == 0) {
    log_msg(sprintf("  FAIL: %s nrow=0", basename(p))); all_ok <- FALSE; next
  }
  log_msg(sprintf("  OK: %s size=%d nrow=%d", basename(p), sz, nrow(df)))
}

if (all_ok) { log_msg("=== All validated ==="); close(log_con); quit(status = 0) }
else        { log_msg("=== Validation FAILED ==="); close(log_con); quit(status = 2) }
}

# === Wrap as function (so it can be source()'d and called via R-UTF8 -e) ===
extract_main <- function(rds_path, out_dir, contrast_arg = character()) {
  # Re-enter the main flow using these args (instead of commandArgs)
  # This is a thin wrapper that re-executes the body with the given args
  args <- c(rds_path, out_dir, contrast_arg)

  # Save the original commandArgs-based body and run it via a sourced variant
  # We use a child process pattern: write a temp script with hardcoded args
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    sprintf('rds_path <- %s', deparse(rds_path)),
    sprintf('out_dir  <- %s', deparse(out_dir)),
    sprintf('contrast_arg <- c(%s)', paste(sprintf('%s', deparse(contrast_arg)), collapse=", ")),
    # The main body is at lines 25-end; we re-execute it via source() of self
    # by setting a global flag
    'SKIP_CMDARGS <- TRUE',
    sprintf('source(%s, local = FALSE)', deparse(sys.frame(1)$ofile %||% "extract_gsea_capsule.R"))
  ), tmp)
  source(tmp, local = FALSE)
}

# When sourced and SKIP_CMDARGS is FALSE, run the main flow
# When called via extract_main(), the wrapper handles invocation
