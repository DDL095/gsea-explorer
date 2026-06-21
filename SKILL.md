---
name: gsealens-explorer
description: 有状态的 GSEA 富集结果探索性分析。通过持久 R REPL 读取 GSEA Capsule RDS (gsealens) 或通用 GSEA 输出（fgsea / clusterProfiler / enrichit），在关键决策点通过 author_background_template.md 向用户收集实验背景，跨 skill 编排证据整合，产出可审计报告，采用 |NES| enrichment direction framework 解读富集方向。支持多组织 crosstalk 分析（4-6 处理组 × 2+ 组织）。自动并行生成 5 个生物学主题的深度讨论（leading edge + C2 涌现 + 跨主题整合）。触发词：GSEA 富集分析、NES 解读、leading edge、多组织 crosstalk、生物主题讨论、MSigDB 涌现发现、rds_path 驱动。
metadata:
  version: "0.5.5"
  last_updated: "2026-06-16"
  status: active
  task_type: open-ended
---

# gsealens-explorer v0.5.5 — 状态化 GSEA 深度探索框架 (含 rds_path 用户驱动 + 多对比组 cascade + Bioconductor 知识库)

## 0. 设计哲学

> **GSEA 的解读不是 LLM 能独立完成的任务 — 它需要用户的实验背景知识。**
> 本 SKILL 的存在意义: 在 LLM 无法读到的实验背景上建一座桥。

核心改进 (v0.3 vs v0.2):
- **R 持久 REPL** — 不再 Rscript one-shot, 通过 `r-interactive` skill 保持 R 会话
- **全量提取** — 移除 top-30 限制, 全部显著通路都提取
- **GSEAlens 式解读** — 用 |NES| 绝对值 + 富集方向 + 3 级置信度
- **多组织 crosstalk** — 支持 4-6 治疗组 × 2+ 组织类型的联合分析
- **Subagent 并行** — 组织级分析可拆为 subagent, 最后汇总

## 1. R 执行协议 (MANDATORY)

> **禁止 Rscript one-shot** — 所有 R 操作必须通过 `r-interactive` 持久 REPL。

### 1.0 获取 RDS 路径 (S0 第一动作, MANDATORY)

**RDS 路径必须由用户在调用时显式提供**。gsealens-explorer 不绑定任何特定文件夹或文件路径, 所有路径均参数化。

**工作流**:
1. agent 被调用后, **第一个动作**是询问用户 rds_path (用 `vscode_askQuestions` 或接受用户输入)
2. 用户的可能来源:
   - 直接拖入文件 → agent 提取绝对路径
   - 用户粘贴完整路径
   - 用户指定工作目录 + 通配符, agent 用 `glob::glob()` 列出候选 RDS 让用户选
3. 路径获取后写入 session state: `session$rds_path`
4. 若用户未提供路径, **不启动 R**, 直接问
5. 若用户提供的路径不存在 / 无法 readRDS, 立即报错给用户, 不自动重试

**典型对话模板**:
```
agent: "请提供 GSEA Capsule RDS 的绝对路径 (Windows: D:/.../foo.rds; 或 Linux: /home/.../foo.rds)。
       - 也可拖入文件到对话框
       - 也可指定工作目录 + 文件名通配符 (e.g. '~/GSEA/*.rds' 列出所有候选)"

用户: "D:/my_project/gsea_capsule_2026.rds"
agent: [验证路径 → 启动 R REPL → readRDS → 嗅探结构 → 进入 S1]
```

**多文件场景** (多组织 / 多时间点):
- 主 agent 启动前先**问所有文件路径**, 一次性收集 (避免反复打断)
- 写 `session$rds_paths <- list(tissue_A = "...", tissue_B = "...")`

### 启动 R REPL

```
run_in_terminal:
  command: & "C:\Program Files\R\R-4.6.0\bin\x64\R.exe" --interactive --no-save --no-restore
  mode: async
```

捕获 `terminal_id`, 记入 session state, 后续所有 R 命令通过 `send_to_terminal(terminal_id)` 发送。

### 初始化 R 会话

```r
# 首次启动后发送:
if (.Platform$OS.type == "windows") {
  Sys.setlocale("LC_CTYPE", "Chinese (Simplified, China)")
}
cat("R", R.version.string, "| session ready\n")
```

### 读取 RDS (路径参数化)

```r
# ⚠️ 绝对不要硬编码 RDS 路径 — 永远使用 session$rds_path
# 以下是用户提供的真实路径, 在 S0.1 收集后填入
rds_path <- session$rds_path   # e.g. "D:/my_project/gsea_capsule_2026.rds"
stopifnot(file.exists(rds_path))   # 验证存在, 立即报错优于静默失败
x <- readRDS(rds_path)
cat("class:", paste(class(x), collapse=","), "\n")
cat("contrasts:", paste(names(x$results), collapse=", "), "\n")
```

### 全量提取 (无 top-N 限制)

```r
# 提取某对比组的全部显著通路 (FDR<0.05, |NES|>=1.0)
cn <- "AgeCre_vs_Con"
df <- x$results[[cn]]$data@result
df_sig <- df[!is.na(df$p.adjust) & !is.na(df$NES) &
             df$p.adjust < 0.05 & abs(df$NES) >= 1.0, ]
df_sig <- df_sig[order(-abs(df_sig$NES)), ]
cat("Significant pathways:", nrow(df_sig), "\n")

# 按 collection 分组导出
for (coll in c("H", "C5", "C2")) {
  sub <- df_sig[df_sig$Collection == coll, ]
  if (coll == "C5") sub <- sub[sub$Subcollection == "GO:BP", ]
  if (coll == "C2") sub <- sub[grepl("REACTOME|KEGG", sub$Combo_Name), ]
  cat(sprintf("  %s: %d pathways\n", coll, nrow(sub)))
  write.csv(sub, sprintf("out/%s_%s.csv", cn, coll), row.names=FALSE)
}
```

## 2. GSEAlens 式解读框架 (核心 prompt)

> 来自自研项目 [GSEAlens](https://github.com/DDL095/GSEAlens) 的 `17_shiny_mod_AI.R` AI 模块。

### 2.1 黄金法则 (Golden Rule)

| 原则 | 规则 |
|---|---|
| **\|**|NES| enrichment direction framework**| 绝对值** | 直接指示富集强度; \|**|NES| enrichment direction framework**|≥1.5 显著, \|**|NES| enrichment direction framework**|≥2.0 强富集 |
| **富集方向** | NES>0 → 富集在 `{left_group}`; NES<0 → 富集在 `{right_group}` |
| **禁止用词** | ❌ "inhibited" / "decreased" / "下调" / "NEG_in_left" / "被抑制" / "被激活" |
| **允许用词** | ✅ "富集在 X 组" / "在 X 组中更集中" (基于 \|**|NES| enrichment direction framework**|) |
| **基因集名含方向** | 如 `*_DN` = 在某组下调; 结合名字 + \|**|NES| enrichment direction framework**| 综合解读 |

### NES 的本质 [必须理解]

**NES 衡量的是"基因集成员是否倾向于集中在排序基因列表的某一端", 而不是"这些基因是上调还是下调"。**

- NES > 0: 该基因集的成员在 `{left_group}` 组的表达排序中更集中于顶部
- NES < 0: 该基因集的成员在 `{right_group}` 组的表达排序中更集中于顶部
- **NES 的符号只表示富集方向, 不表示基因表达变化方向**

**绝对禁止的错误解读**:
- ❌ "NEG 数量大于 POS, 提示基因集被抑制"
- ❌ "该通路在 treatment 组被激活"
- ❌ "上调通路" / "下调通路"
- ❌ 将 POS 等同于"激活", NEG 等同于"抑制"

**正确的解读方式**:
- ✅ "更多通路富集在 control 组, 说明 treatment 组的基因表达谱在某些方面更接近 control"
- ✅ "该通路富集在 treatment 组 (NES>0), 说明其成员在 treatment 组表达更高"
- ✅ "POS 通路数: N, NEG 通路数: M" (仅描述数量, 不做激活/抑制推断)

### 统计汇总的正确写法

```
✅ "RT_vs_Model: 显著 4415 通路, 其中 NES>0 (富集在 RT) 1884 个, NES<0 (富集在 Model) 2531 个"
❌ "NEG 数量持续大于 POS, 提示处理组整体呈现基因集被抑制为多"
```

### GSEA 图方向约定 [强制]

**GSEA 富集图的标准方向**:
- **左侧 (left)** = NES > 0 = 富集在 `{left_group}` 组 (通常是 treatment)
- **右侧 (right)** = NES < 0 = 富集在 `{right_group}` 组 (通常是 control)

**CSV 输出必须包含两个独立列**:
- `Enriched_In`: 富集在哪个组 (填入实际组名, 如 `RTP` 或 `RT`)
- `NES_sign`: `POS` (NES>0) 或 `NEG` (NES<0)

**禁止** `NEG_in_left` / `POS_in_left` 等混淆命名。

**subagent 必须使用的 R 代码**:
```r
# 从 contrast_registry 获取组名
cr <- x$contrast_registry
cr_row <- cr[cr$contrast_id == cn, ]
left_g  <- cr_row$left_group   # treatment
right_g <- cr_row$right_group  # control

# 正确的方向列
df$Enriched_In <- ifelse(df$NES > 0, left_g, right_g)
df$NES_sign    <- ifelse(df$NES > 0, "POS", "NEG")
df$absNES      <- abs(df$NES)
```

### 2.1.4 跨对比组"方向反转"的精确分类 [v0.5 新增, 强制]

> **来源教训**: 2026-06-14 用户指出"在 RTP_vs_RT 中 NES<0 时,说'富集回 Model 方向'是错误的,因为 right_group=RT 而非 Model"。这个错误源于把不同对比组的 right_group 混为一谈。

**核心理念**: 跨对比组解读 NES 方向变化时,必须**先确认每个对比组的 left/right 角色**,再判断"反转"的真实含义。

#### 两种反转模式

| 模式 | RT_vs_Model NES | RTP_vs_RT NES | 中文含义 | 典型例子 |
|---|---|---|---|---|
| **真反转 (Mirror Flip)** | **< 0** (富集 Model) | **> 0** (富集 RTP) | RT 损伤下沉的程序,P 药在 RTP 中**重新激活** | HYPOXIA, EMT, GLYCOLYSIS, COLLAGEN_FORMATION, MYC_TARGETS |
| **真反转 (Mirror Flip)** | **> 0** (富集 RT) | **< 0** (富集 RT) | RT 富集的程序,P 药**反向压制**了 RT 端的相对富集 | (少见, 通常归为"假反转") |
| **P 压制 (P-Suppression)** | **> 0** (富集 RT) | **< 0** (富集 RT,因为 right_group=RT) | RT 富集的程序,P 药让 RT 端相对富集强度**下降** | IFN-γ, ALLOGRAFT, OXPHOS, JAK-STAT, TCR, KRAS_UP |
| **P 重启 (P-Restoration)** | **< 0** (富集 Model) | **> 0** (富集 RTP) | RT 损伤下沉的程序,P 药在 RTP 中**重启** | HYPOXIA, EMT, GLYCOLYSIS, MYC, UPR, MYOGENESIS, MITOTIC_SPINDLE |
| **RTP 独有 (RTP-Only)** | NS | **> 0** (富集 RTP) | RT 不驱动,P 药特有贡献 | HEME_METABOLISM, E2F_TARGETS, G2M_CHECKPOINT |
| **不变 (Stable)** | **> 0** | **> 0** (或都 < 0) | P 药未改变富集方向 | (需根据具体通路看) |

#### 解读规则 (R 强制代码)

```r
# classify_flip_mode.R
classify_flip_mode <- function(rt_nes, rtp_nes, threshold = 1.5) {
  # rt_nes: NES in RT_vs_Model
  # rtp_nes: NES in RTP_vs_RT
  # Returns: one of "true_flip", "p_suppression", "p_restoration", "rtp_only", "rt_only", "no_flip", "ambiguous"
  
  rt_sig <- !is.na(rt_nes) && abs(rt_nes) >= threshold
  rtp_sig <- !is.na(rtp_nes) && abs(rtp_nes) >= threshold
  
  if (!rt_sig && !rtp_sig) return("no_flip")
  if (rt_sig && !rtp_sig) return("rt_only")
  if (!rt_sig && rtp_sig) return("rtp_only")
  
  # Both significant
  if (sign(rt_nes) != sign(rtp_nes)) {
    if (rt_nes < 0 && rtp_nes > 0) {
      # RT 富集 Model → RTP 富集 RTP (P 重启)
      return("p_restoration")
    } else {
      # RT 富集 RT → RTP 富集 Model (少见, 真反转)
      return("true_flip")
    }
  } else {
    # Same sign: P 压制 (RT 端被拉低) — if both POS and rtp_nes < rt_nes
    if (sign(rt_nes) > 0) {
      return("p_suppression")
    } else {
      # Both NEG, unlikely but possible
      return("ambiguous")
    }
  }
}
```

#### 文本表述规范 (中文, 强制)

| 错误措辞 ❌ | 正确措辞 ✅ |
|---|---|
| "在 RTP_vs_RT 中 NES<0, 即富集回 Model 方向" | "在 RTP_vs_RT 中 NES<0, 意味着该通路在 RT 端仍相对富集(因为 right_group=RT),P 药压制了 RT 端的相对富集强度" |
| "通路从 RT 端回到 Model 端" | "P 药压制了 RT 端的相对富集(在 RT↔Model 这条轴上,RTP 端表型更接近 Model)" |
| "在 RTP_vs_RT 中, Model 富集" | "在 RTP_vs_RT 中, 富集在 RT 端" |
| "通路在 RTP 中下调" | "通路在 RTP 端的相对富集强度下降(NES 减小)" |

#### 关键警示: "接近 Model" ≠ "回到 Model"

- "P 药使 RTP 端的转录表型更接近 Model 端" — 这句话**对**(在 RT↔Model 这条轴上, RTP 端的偏离幅度减小)
- "P 药使 RTP 端回到 Model 端的基线水平" — 这句话**错**(RTP 端与 Model 端仍有显著差异, RTP_vs_Model 中仍有大量显著通路)
- 推荐用"更接近"(比较距离减小)替代"回到"(完全重合)

### 2.1.5 跨对比组解读的"轴"概念 [v0.5 新增]

> **重要**: 多对比组 GSEA 解读时,每对对比组构成一条独立的"比较轴"(axis),跨轴解读必须先确认每条轴的 left/right。

| 对比组 | 比较轴 | 典型含义 |
|---|---|---|
| RT_vs_Model | "RT 损伤轴" | RT 与 Model 的偏离 |
| RTP_vs_Model | "联合治疗轴" | RTP 与 Model 的偏离 |
| RTP_vs_RT | "P 药净效应轴" | RTP 与 RT 的差异 = P 药加入的净效应 |

**P 压制 vs P 重启 取决于通路在 RT_vs_Model 中的方向**:
- 如果通路在 RT_vs_Model 中 NES<0 (Model 富集) → P 药在 RTP 中重新激活 → "P 重启" (HYPOXIA, EMT, ...)
- 如果通路在 RT_vs_Model 中 NES>0 (RT 富集) → P 药在 RTP 中压制 → "P 压制" (IFN-γ, OXPHOS, ...)

**这两者在 RTP_vs_RT 中都表现为 NES 符号变化,但生物学含义完全不同**。

### Markdown 转义规则 [强制]

在 MD 表格中, `|NES|` 的 `|` 会被解析为表格分隔符。必须写成 `\|**|NES| enrichment direction framework**|`:
- ✅ `\|**|NES| enrichment direction framework**| ≥ 1.5`
- ❌ `|NES| ≥ 1.5` (会破坏表格渲染)

### 2.2 3 级置信度 (|NES| enrichment direction framework 标准)

| 级别 | 条件 | 含义 |
|---|---|---|
| **High** | \|**|NES| enrichment direction framework**|≥1.5 且 FDR<0.05 | 高置信,可直接用于结论 |
| **Medium** | \|**|NES| enrichment direction framework**|≥1.0 且 FDR<0.25 | 中置信,需交叉验证 |
| **Low** | 其他 | 低置信,仅供参考 |

### 2.3 描述模板

```
"该基因集在 [{left_group}] 组表现出激活趋势
 (成员在该组整体表达水平更高, |NES| = {abs_nes})。
 [结合基因集名称含义 + leading edge 基因的功能解读]"
```

### 2.4 工作流 (LLM 解读步骤)

1. **确认背景**: A = `{left_group}`, B = `{right_group}`
2. **评估显著性**: FDR q-value (通常 < 0.25), \|**|NES| enrichment direction framework**| 判断强度
3. **分类描述**:
   - 富集在 A → "在 A 组激活的基因集"
   - 富集在 B → "在 B 组激活的基因集"
4. **谨慎解读**: 在客观方向描述完成后, 分析两个方向的生物学意义
5. **结合 leading edge**: 用核心贡献基因给出具体功能解释

### 2.5 全 Collection 深度解读 [强制]

**Agent 必须对以下 4 个 collection 都进行深度分析, 不仅限于 Hallmark:**

| Collection | 通路数 | 分析要求 |
|---|---|---|
| **H (Hallmark)** | 50 | 作为骨架, 识别核心生物学主题 |
| **C5:GO:BP** | 数千显著 | **必须深入** — 识别具体生物学过程, 如炎症、代谢、细胞周期 |
| **C2:CP:REACTOME** | 数百显著 | **必须深入** — 识别信号通路级联, 如 NF-κB、mTOR、JAK-STAT |
| **C2:CP:KEGG** | 数百显著 | **必须深入** — 识别代谢通路, 如氧化磷酸化、脂肪酸代谢 |

**解读流程** (每个 collection 独立执行):
1. 读取对应 CSV (如 `{contrast}_GOBP.csv`)
2. 按 \|**|NES| enrichment direction framework**| 排序, 取 top 50 显著通路
3. 按功能聚类 (如: 炎症相关 GO:BP 一组, 代谢相关一组, 细胞周期一组)
4. 每个聚类给出生物学意义总结
5. 识别聚类间的交叉 (如: 炎症 GO:BP + NF-κB Reactome = 一致的炎症主题)

**禁止**: 只讨论 Hallmark 而忽略 GO:BP / Reactome / KEGG

## 2.7 Medium 阈值通路模块 [v0.5.5 新增, OPTIONAL]

### 定义 (与 High 区分)

| 阈值 | 标准 | 用途 |
|---|---|---|
| **High** | FDR<0.05 且 \|**|NES| enrichment direction framework**|≥1.5 | 主分析默认 |
| **Medium** | FDR≥0.05 且 <0.25, 且 \|**|NES| enrichment direction framework**|≥1.0 且 <1.5 | 候选/辅助分析 |
| **Low** | FDR≥0.25 或 \|**|NES| enrichment direction framework**|<1.0 | 不纳入 |

### 触发条件 (强制)

**默认不纳入主分析**。仅当用户**显式提及**以下任一关键词时才纳入:
- "不显著", "边缘显著", "中等置信", "medium threshold", "放宽阈值"
- 或用户**显式指定关键词** (如 "Wnt pathway", "autophagy", "Wnt 信号通路", "自噬") 来定位 Medium 中的特定通路

### 提取 R 代码

```r
extract_sig_medium <- function(cn, x) {
  df <- x$results[[cn]]$data@result
  cr <- x$contrast_registry
  left_g <- cr$left_group[cr$contrast_id == cn]
  right_g <- cr$right_group[cr$contrast_id == cn]
  df_medium <- df[!is.na(df$p.adjust) & !is.na(df$NES) &
                  df$p.adjust >= 0.05 & df$p.adjust < 0.25 &
                  abs(df$NES) >= 1.0 & abs(df$NES) < 1.5, ]
  df_medium$absNES <- abs(df_medium$NES)
  df_medium$NES_sign <- ifelse(df_medium$NES > 0, "POS", "NEG")
  df_medium$Enriched_In <- ifelse(df_medium$NES > 0, left_g, right_g)
  df_medium <- df_medium[order(-df_medium$absNES), ]
  return(df_medium)
}
```

### Medium 通路处理流程

1. **S4 阶段**: 默认提取到 `evidence/medium/{contrast}_Medium.csv` (不纳入主报告)
2. **触发时**: 用户在 S2-S10 阶段提及关键词 → 调用 `extract_sig_medium()` 重新提取, 加入到对应主题子报告
3. **不触发时**: evidence/medium/ 目录保留作为"备用资产", 可在 follow-up (S10) 时被查询

### Medium 报告输出 (按需, 触发时)

```markdown


## 2b. 跨对比组联合分析 [v0.3.1 新增, 强制]

### 2b.1 问题

当有 3+ 对比组时 (如 `TreatmentA_vs_Control`, `TreatmentB_vs_Control`, `TreatmentB_vs_TreatmentA`),
agent 必须进行**跨对比组联合分析**, 而不是独立处理每个对比组。

### 2b.2 联合分析 R 代码模板

```r
# 读取所有对比组的显著通路
contrasts <- c("TreatmentA_vs_Control", "TreatmentB_vs_Control", "TreatmentB_vs_TreatmentA")
sig_list <- list()
for (cn in contrasts) {
  df <- x$results[[cn]]$data@result
  df_sig <- df[df$p.adjust < 0.05 & abs(df$NES) >= 1.5, ]
  df_sig$contrast <- cn
  df_sig$absNES <- abs(df_sig$NES)
  sig_list[[cn]] <- df_sig
}

# 1. 找出所有对比组共有的通路 (核心签名)
all_ids <- lapply(sig_list, function(d) d$ID)
shared_all <- Reduce(intersect, all_ids)
cat("所有对比组共有通路:", length(shared_all), "\n")

# 2. 找出两两共有但第三个没有的通路
shared_pair <- list()
for (i in 1:(length(contrasts)-1)) {
  for (j in (i+1):length(contrasts)) {
    pair <- intersect(sig_list[[contrasts[i]]]$ID, sig_list[[contrasts[j]]]$ID)
    unique_pair <- setdiff(pair, all_ids[[3-i-j+1]])  # 简化
    shared_pair[[paste(contrasts[i], contrasts[j], sep=" & ")]] <- unique_pair
  }
}

# 3. 找出每个对比组独有的通路
unique_per_contrast <- list()
for (cn in contrasts) {
  others <- setdiff(contrasts, cn)
  other_ids <- unlist(sig_list[others]$ID)
  unique_per_contrast[[cn]] <- setdiff(sig_list[[cn]]$ID, other_ids)
}

# 4. 生成联合比较表
joint_table <- data.frame()
for (pw in unique(shared_all)) {
  row <- data.frame(Pathway = pw)
  for (cn in contrasts) {
    sub <- sig_list[[cn]][sig_list[[cn]]$ID == pw, ]
    if (nrow(sub) > 0) {
      row[[paste0(cn, "_NES")]] <- sub$NES[1]
      row[[paste0(cn, "_absNES")]] <- sub$absNES[1]
      row[[paste0(cn, "_FDR")]] <- sub$p.adjust[1]
      row[[paste0(cn, "_Enriched")]] <- ifelse(sub$NES[1] > 0, "left", "right")
    }
  }
  joint_table <- rbind(joint_table, row)
}
write.csv(joint_table, "cross_contrast_joint.csv", row.names=FALSE)
```

### 2b.3 联合分析解读框架

**必须回答的问题**:
1. **核心签名**: 哪些通路在所有对比组都显著? → 这是该模型的"基础表型"
2. **TreatmentB 特异**: 哪些通路只在 `TreatmentB_vs_Control` 显著但 `TreatmentA_vs_Control` 不显著? → TreatmentB × 损伤的交互效应
3. **TreatmentA 特异**: 哪些通路只在 `TreatmentA_vs_Control` 显著但 `TreatmentB_vs_Control` 不显著? → 单独 TreatmentA 的响应
4. **方向一致性**: 同一通路在不同对比组中方向是否一致?
   - 一致 → 稳定的生物学效应
   - 不一致 → 可能存在代偿或反馈机制
5. **强度变化**: 同一通路在不同对比组中 \|**|NES| enrichment direction framework**| 如何变化?
   - 衰老组更强 → 衰老加剧该通路
   - 衰老组更弱 → 衰老可能抑制该通路的响应能力

### 2b.4 联合分析输出

```
cross_contrast_joint.md:
## 跨对比组联合分析

### 核心签名 (所有对比组共有)
| 通路 | AduCre NES | AgeCre NES | AgeCre_vs_AduCre NES | 方向一致性 | 生物学意义 |

### 衰老特异通路 (仅 AgeCre 显著)
| 通路 | NES | FDR | 生物学意义 |

### 损伤特异通路 (仅 AduCre 显著)
| 通路 | NES | FDR | 生物学意义 |

### 方向不一致通路 (可能存在代偿)
| 通路 | AduCre 方向 | AgeCre 方向 | 解读 |
```

## 3. 多组织 Crosstalk 架构 (v0.3 新增)

### 3.1 场景

用户有 4-6 治疗组 × 2+ 组织类型 (如胰腺 + 肝脏), 需要分析:
- 组织间共享通路 (crosstalk)
- 组织特异通路
- 治疗 × 组织交互效应

### 3.2 架构

```
主 Agent (gsealens-explorer)
  ├── 组织 A subagent
  │     ├── R REPL: 读 RDS_A → 提取全量 → 生成 |NES| 表
  │     ├── SKILL: reactome/quickgo/opentargets/pubmed
  │     └── 输出: tissue_A_report.md
  ├── 组织 B subagent
  │     ├── R REPL: 读 RDS_B → 提取全量 → 生成 |NES| 表
  │     ├── SKILL: reactome/quickgo/opentargets/pubmed
  │     └── 输出: tissue_B_report.md
  └── 主 Agent 汇总
        ├── R REPL: 跨组织 Venn / UpSet / 通路交集
        ├── 共享通路 → crosstalk 解读
        ├── 组织特异 → 特异功能解读
        └── 输出: crosstalk_report.md
```

### 3.3 Crosstalk 解读 prompt

```
你有两个组织 (胰腺 + 肝脏) 的 GSEA 结果, 都有 4-6 个治疗组。

任务:
1. 找出两个组织共有的显著通路 (FDR<0.05, |NES|≥1.5)
   → 这些是"组织间 crosstalk 通路"
2. 对每个 crosstalk 通路:
   - 比较两个组织的 |NES| 大小 → 哪个组织更强烈?
   - 比较富集方向是否一致 → 一致 = 协同, 不一致 = 拮抗
   - 结合 leading edge 基因 → 是否是同一套核心基因?
3. 找出组织特异通路:
   - 仅在胰腺显著的 → 胰腺特异功能
   - 仅在肝脏显著的 → 肝脏特异功能
4. 用 |NES| enrichment direction framework:
   - ❌ "胰腺上调, 肝脏下调"
   - ✅ "该通路在两组织中均富集于治疗组, 但胰腺 |NES|=2.1 > 肝脏 |NES|=1.6"
```

## 3a. MSigDB 本地知识库 — 强绑定涌现发现 (msigdb MCP) [v0.5.2, MANDATORY]

### 定位
gsealens-explorer 的核心能力是**涌现发现** — 不仅解读单条通路, 还要从数十条显著通路的 BRIEF/FULL 描述中提炼出跨通路的共性主题, 发现 LLM 无法从名字直接推断的生物学连接。MSigDB 本地 MCP 是这条涌现链路的**核心基础设施**, 在每个关键阶段都被强制调用。

**与 R 包 `msigdbr` 的关键差异**:
- `msigdbr`: 只给基因列表, 无 BRIEF/FULL/PMID/AUTHORS
- **MSigDB MCP**: 35,361 基因集, 含 BRIEF (一句话简述) + FULL (完整文献背景) + PMID + GEOID + AUTHORS + EXACT_SOURCE

### 数据源
- SQLite 数据库: `<your_msigdb_scraper_dir>/msigdb.db` (~566 MB)
- 全局 MCP server: `msigdb` (在 `mcp.json` 注册, 任意工作区可调用; 若未配置则降级到 `msigdbr` R 包)
- 备用 CLI: `python <your_msigdb_scraper_dir>/msigdb_query.py <tool> --params '{...}'`

### 覆盖范围
35,361 个基因集, 10 个 collection, 4,524,768 基因-集成员行。
- DESCRIPTION_BRIEF 覆盖率: 99%
- DESCRIPTION_FULL 覆盖率: 46%
- PMID 覆盖: CGP (37%), IMMUNESIGDB (99.6%); Hallmark (Liberzon 2016)
- GEOID 覆盖: CGP (37%), IMMUNESIGDB (99.6%); 通路类 (KEGG/Reactome/GO) 无

### MCP 工具 (6 个, 全局可用)

```python
# 1. 完整元数据 (含基因列表) — 最详细
mcp__msigdb__get_geneset(name="KEGG_PARKINSONS_DISEASE")

# 2. 简要元数据 (最常用) — BRIEF/FULL/PMID/GEOID/AUTHORS
mcp__msigdb__get_geneset_brief(name="BARRIER_CANCER_RELAPSE_NORMAL_SAMPLE_UP")

# 3. 反向查找: 包含给定基因的基因集
mcp__msigdb__get_genesets_by_genes(genes=["STAT1","IRF1"], require_all=True, limit=10)
mcp__msigdb__get_genesets_by_genes(genes=["STAT1","IRF1"], require_all=False, collection="H")

# 4. 名称模式搜索 (LIKE)
mcp__msigdb__get_genesets_by_pattern(pattern="%FIBROBLAST%", limit=20)

# 5. 全文搜索 (BRIEF/FULL/EXACT_SOURCE)
mcp__msigdb__search_text(query="oxidative phosphorylation", limit=10)

# 6. Collection 统计
mcp__msigdb__list_collections()
```

### 强绑定使用规则 (MANDATORY, 任意阶段违规视为 G 门控失败)

| 阶段 | 必须调用 | 强制动作 |
|---|---|---|
| **S2 (假设生成)** | `search_text` × 2-3 次 | 用用户提供的关键词 (来自 S1 背景) 在 description_brief/full 中搜索, 看 MSigDB 已有研究覆盖哪些相关机制 |
| **S4 (数据提取)** | — | 仅 R 提取显著通路表 |
| **S5 (知识增广)** | `get_geneset_brief` × top N 通路 | 对 **每个 collection (H/C2/C5/C6) 的 top 20 显著通路** 调一次, 写入 `evidence/msigdb_brief_<collection>.json` |
| **S6 (深度解读)** | `get_geneset_brief` (逐通路) | **每条被解读的通路都必须先调**; 解读文本必须**显式引用** description_full 中的关键句 (否则按"凭名字推断"违规) |
| **S6b (跨对比组)** | `get_genesets_by_genes` | 对 direction-flip 通路 (P-Suppression/P-Restoration/True Flip) 的 leading edge top 10 基因做反向查询, 看是否跨主题共同出现 |
| **S7 (Discussion)** | `search_text` × ≥3 | 用 Discussion 章节中新提出的核心机制名 (如"线粒体复合物 I 抑制")搜索, 确认是否有 MSigDB 已收录的关联基因集 (用于"跨集合印证") |
| **S7b (并行深度)** | 每个主题 subagent: `get_geneset_brief` × top 10 + `get_genesets_by_genes` × leading edge + `search_text` × ≥2 | 写入 `deep_discussion/<theme>_evidence.md` |
| **S10 (Follow-up)** | 按专题 | 用户指定机制时, 围绕该机制做深度搜索 |

### 涌现发现 SOP (SOP = 标准操作流程) [v0.5.2 新增]

涌现不是"读一段描述就总结", 而是**结构化四步法**:

#### 步骤 1: 字段抽取 (EXTRACT)
对 S5 已写入 `evidence/msigdb_brief_*.json` 的所有通路, 程序化抽取:
- `description_full` 全文 (若有)
- `description_brief` 全文 (若有)
- `pmid` (若有)
- `exact_source` (若有)

#### 步骤 2: 关键词聚类 (CLUSTER)
从所有 BRIEF/FULL 文本中**自动抽取高频生物学概念**:
- 名词: 线粒体 / 复合物 I / NADH / 氧化磷酸化 / 自噬 / 凋亡 / 纤维化 / 上皮间充质转化 / 巨噬细胞极化 / DNA 损伤修复...
- 动词/过程: activation / suppression / infiltration / recruitment / polarization / repair...
- 细胞/组织: T cell / macrophage / fibroblast / endothelium / epithelium...

建议工具: R `tidytext::unnest_tokens` + `count()` + `tf-idf`; 或 Python `sklearn.TfidfVectorizer`。

#### 步骤 3: 跨通路主题归纳 (SYNTHESIZE)
按聚类结果把 top 显著通路归入 N 个主题 (N=3-5, 取决于数据):
- 例 1: {KEGG_PARKINSONS_DISEASE, KEGG_HUNTINGTONS_DISEASE, KEGG_ALZHEIMERS_DISEASE} → 共同主题 "线粒体复合物 I / 氧化磷酸化"
- 例 2: {GOBP_T_CELL_ACTIVATION, GOBP_T_CELL_PROLIFERATION, HALLMARK_TNFA_SIGNALING} → 共同主题 "T 细胞激活/增殖 + 炎症信号"

**关键**: 主题命名必须有 BRIEF/FULL 文本支持, **不能**仅凭通路名推断。

#### 步骤 4: 涌现假说生成 (HYPOTHESIZE)
基于跨主题的共同概念, 生成新的生物学假说:
- 模板: "在 [组织] 的 [处理] 背景下, 多个原本独立的 MSigDB 基因集共同指向 [共同机制], 提示 [涌现机制] 可能作为 [核心驱动] 参与 [表型]。"
- 每个涌现假说必须引用 ≥3 条 MSigDB 通路的 description_brief/full 作为支撑。

### KEGG 名称误导专项防御 [MANDATORY]

KEGG_LEGACY / KEGG_MEDICUS 通路**名称字面含义常具误导性**:
- `KEGG_PARKINSONS_DISEASE` 实为 Complex I 线粒体基因集
- `KEGG_HUNTINGTONS_DISEASE` 实为 Complex II + Complex III
- `KEGG_ALZHEIMERS_DISEASE` 实为 Complex IV + 凋亡

**铁律**: 解读任何 KEGG_LEGACY / KEGG_MEDICUS 通路时, **必须**先调 `get_geneset_brief` 看 FULL, 然后**只引用 FULL 描述中的实际机制**, 不能写"该通路与 XX 疾病相关"等基于名称的推断。

### 强制写作规范

- 解读文本中出现 PMID 时, 格式: `[Smith et al., 2020, PMID:12345678]`
- CGP / IMMUNESIGDB 通路引用必须含 PMID (在 MSigDB 已有 PMID 时)
- 引用 `description_full` 时格式: `[MSigDB: KEGG_PARKINSONS_DISEASE 描述: "α-synuclein/复合物 I..."]`

### 解读示例

```
# 解读 KEGG_PARKINSONS_DISEASE 富集时:
get_geneset_brief("KEGG_PARKINSONS_DISEASE")
# → description_full = "PD is a progressive neurodegenerative movement disorder... 
#   mutations in alpha-synuclein, UCHL1, parkin, DJ1, and PINK1... mechanisms that 
#   result in proteasome dysfunction, mitochondrial impairment, and oxidative stress..."
# → 正确解读: 该基因集虽名为"帕金森病", 实际是线粒体复合物 I 基因集合
#   → 与放射治疗引发的线粒体危机直接相关, 而非神经退行性病变

# 解读 CGP 基因集时:
get_geneset_brief("BARRIER_CANCER_RELAPSE_NORMAL_SAMPLE_UP")
# → pmid="16091735", authors="Barrier A, Lemoine A, ..."
# → description_brief="Up-regulated genes in non-neoplastic mucosa samples from
#   colon cancer patients who developed recurrence of the disease."
# → 解读引用: "Barrier 等 (PMID: 16091735) 在结肠癌复发预测研究中发现..."
```
## 3b. 文献验证规则 — bioRxiv 禁用 + 强制 PMC 验证 [v0.5.2, MANDATORY]

### 核心原则
**报告中出现的每一条文献引用都必须经过 MCP 验证。** 不允许凭印象/训练知识编造 PMID、作者、期刊、卷期、DOI 等信息。

### 禁用: bioRxiv/medRxiv 搜索 [HARD BLOCK]

**为什么禁用**:
- bioRxiv 预印本**未经同行评审**, 内容可信度参差
- bioRxiv 搜索极易触发 Cloudflare 人机验证, 经常超时, **拖慢 agent 整体响应 5-30 倍**
- 用户反馈: 搜索时总出现 bioRxiv 会极大拖慢能力

**禁用范围**:
- ❌ `mcp__unified-acade__search_biorxiv`
- ❌ `mcp__unified-acade__search_validate` (含 bioRxiv 子调用)
- ❌ `mcp__unified-acade__smart_search` (含 bioRxiv 子调用)
- ❌ `mcp__unified-acade__search_academic_only` (含 bioRxiv 子调用)
- ❌ `mcp__unified-acade__search_broad` (含 bioRxiv 子调用)
- ❌ `mcp__unified-acade__get_categories` (bioRxiv 类目)
- ❌ `mcp__unified-acade__extract_content` 抓取 biorxiv.org / medrxiv.org
- ❌ `mcp__unified-acade__auto_refresh_auth` (为 bioRxiv 验证解锁)

**例外**: 仅当用户**显式要求** "请检查 bioRxiv 上的最新预印本" 时才允许调用, 且必须先告知用户 bioRxiv 速度慢。

### 强制使用: 替代文献 MCP

| 用途 | 推荐 MCP | 备选 |
|---|---|---|
| PubMed 搜索 (期刊文献, 已发表) | `mcp__deepxiv__search_papers` / `mcp__deepxiv__get_full_paper` | `mcp__research-tools__paper_search` |
| OpenAlex 搜索 (开放学术, 含出版社) | `mcp__unified-acade__search_academic_only` (该工具也搜 OpenAlex/PubMed) | `mcp__research-tools__paper_search` |
| arXiv 预印本 (物理/计算/CS) | `mcp__deepxiv__get_full_paper` | `mcp__unified-acade__extract_content` (限 arxiv.org) |
| 引用验证 (PMID/标题/作者) | `mcp__research-tools__paper_search` | `mcp__deepxiv__search_papers` |
| 期刊影响因子/引用数 | `mcp__research-tools__paper_search` | — |

**优先级**:
1. **`mcp__deepxiv__*`** — 主选, PubMed/arXiv 全文支持, 速度快
2. **`mcp__research-tools__*`** — 次选, 补全验证/引用/期刊信息
3. **`mcp__unified-acade__extract_content`** — 仅用于已确定 URL 的非 bioRxiv 网页

> **ℹ️ v2.1.1 (2026-06-21)**：`mcp_unified-acade` 改为自启动模式，**所有工具自启动即全部可见**，无需预先调用 `activate_search_tools`。`activate_search_tools` 入口保留为 no-op 兼容旧调用。本 skill 的 bioRxiv HARD BLOCK 仍然生效（不允许调用 `search_biorxiv` / `smart_search` / `search_broad` 等含 bioRxiv 的工具）。

### 强制验证规则 (G 门控)

| 场景 | 验证要求 |
|---|---|
| 报告引用 `[Author et al., Year, PMID:12345]` | **必须**先用 `mcp__deepxiv__search_papers` 或 `mcp__research-tools__paper_search` 查到 PMID=12345 真实存在, 拿到 title/author/year 至少 1 项确认 |
| 报告引用 `[MSigDB 通路, PMID:16091735]` (来自 MSigDB MCP 自身数据) | 不需要二次验证 — MSigDB 已抓取 PMID 是已发布源数据, **直接引用即可** |
| 报告引用 `[Author et al., Year]` 但无 PMID | **必须**用 `mcp__deepxiv__search_papers` 搜 author+year+keyword, 找到原始论文并补全 PMID/DOI |
| 报告引用 "据 X 综述报道..." | **必须**找到该综述的 PMID/DOI, 验证后引用 |
| 报告引用 "经典的 Hall 实验室工作..." | **必须**找到具体论文并验证, **不能**用"经典"作为引用理由 |
| 涌现假说中的新机制名 | 如"线粒体复合物 I 抑制" — 不需要专门引一篇文献, 但若写"据 X 研究, 该机制在 Y 中..." 则必须验证 |

**违规判定**:
- ❌ 报告中出现 PMID 但未调用过任何文献 MCP
- ❌ 报告中出现具体作者+年份但 PMID 为空
- ❌ 报告中引用"X 实验室/团队"未指明具体论文

### 搜索策略模板

```python
# 模板 1: 已知 PMID, 验证存在性
mcp__deepxiv__search_papers(query="16091735")
# 期望返回: title, authors, journal, year 与报告一致

# 模板 2: 已知关键词, 找原始论文
mcp__deepxiv__search_papers(
  query="oxidative phosphorylation T cell exhaustion tumor microenvironment",
  max_results=10
)

# 模板 3: 已知作者+关键词, 补全 PMID
mcp__research-tools__paper_search(
  query="Author:Smith AND year:2020 AND keyword:fibroblast"
)

# 模板 4: 拿到 PMID 后取全文
mcp__deepxiv__get_full_paper(arxiv_id="PMID:16091735")  # 或 arxiv_id 形式
```

### 写作规范

- 文献引用格式统一: `[FirstAuthor et al., Year, PMID:12345, Journal]`
- 同一文献多次出现: 第一次给完整信息, 后续可缩写为 `[Smith et al., PMID:12345]`
- 综述 vs 原始研究必须区分: "据综述 [Smith, 2020, PMID:12345]" vs "原始研究 [Smith, 2020, PMID:12345] 显示..."

### 审计

- 报告生成后, G8 门控检查: `grep "PMID:" <report>.md | wc -l` 给出 PMID 数
- 验证证据写入 `evidence/literature_verification.json`: `{"PMID:12345": {"source": "deepxiv", "verified": true, "title": "..."}}`


## 3.5 S1 阶段: 作者背景结构化采集 [v0.5 新增, 强制]

> **目的**: 在 GSEA 解读前, 通过 `author_background_template.md` 结构化采集作者对实验背景的知识, 避免 GSEA 解读时的方向错位、术语歧义、过度推断。
> **重要性**: GSEA 解读高度依赖实验背景(处理组角色、时间点、关键既往知识), 缺少这些会导致 NES 方向解读错误, 假说生成偏离实际。

### 3.5.1 工作流 (Agent 必读)

```
S0  (Agent 启动)
  ↓
  S0.1  获取 rds_path (从用户; 见 §1.0)
  ↓
  S0.2  启动 R REPL, readRDS, 提取 contrast_registry, 嗅探平台 (gsealens/limma_voom/edgeR)
  ↓
  S0.3  验证 RDS 完整性: 必含 fields = (results, de_store, expr_bundle, contrast_registry)
  ↓
  进入 S1 (追问实验背景)
  ↓
S1 Phase 1 (简答, 1 轮 vscode_askQuestions)
  询问第 1 节(实验基本信息)
  - 物种 / 组织 / 样本类型 / n 重复
  - 处理组角色(每个组的 treatment / control / sham)
  - 取材时间点
  ↓
S1 Phase 2 (中答, 1 轮)
  询问第 2 节(科学问题与假设)
  - 主要科学问题
  - 关键假设(2-3 个)
  - 不希望看到的结果
  ↓
S1 Phase 3 (详答, 1-2 轮)
  询问第 3-5 节
  - 处理组生物学意义(每个组的详细描述)
  - 已知通路-表型映射
  - 已发表相关工作
  - 关键局限性
  ↓
S1 Phase 4 (偏好, 1 轮)
  询问第 6 节
  - 期望输出范围
  - 主题优先级
  - 解读风格
  ↓
写入 {out_dir}/author_background.md
  - 把作者所有回答汇总
  - 标注作者 ID + 提交时间
  ↓
S2-S7b (后续所有阶段)
  每次解读 NES 前:
  1. 查 {out_dir}/author_background.md 第 3.1 节
  2. 查 {contrast_registry} 的 left/right 角色
  3. 按 §2.1.4 分类(P 压制 / P 重启 / RTP 独有)
  4. 写报告时严格按 §2.1.4 中文表述规范
```

### 3.5.2 模板文件位置

- **模板原文**: `{SKILL_DIR}/author_background_template.md`
- **项目实例**: `{out_dir}/author_background.md`(由 Agent 写入)

### 3.5.3 模板章节速查

| 章节 | 必填性 | 询问工具 |
|---|---|---|
| 1. 实验基本信息(物种、组织、处理组) | **必填** | `vscode_askQuestions` 4-6 题, multiSelect=false |
| 2. 实验目的与科学问题 | **必填** | 1-2 题, 自由文本 |
| 3. 处理组细节与生物背景(关键!) | **必填** | 2-3 题, 自由文本(每组一段) |
| 4. 数据来源与处理流程 | 选填 | 1-2 题, 自由文本 |
| 5. 关键实验背景与既往知识 | 选填, 强烈建议 | 2-3 题, 自由文本 |
| 6. 报告偏好(输出范围、主题、风格) | 选填 | 1 题, multiSelect=true |

### 3.5.4 与 §2.1.4 的协同

**模板第 3.1 节 + §2.1.4 共同保证 NES 解读正确性**:
- 模板提供"每个处理组的生物学意义" — 决定 NES 方向解读的生物学语境
- §2.1.4 提供"反转模式的精确分类" — 决定 P 压制 vs P 重启 vs RTP 独有的判定
- 两者必须**联合使用**, 缺一不可

### 3.5.5 错误案例警示

> 2026-06-14 教训: 在解读 `RTP_vs_RT` 中 NES<0 时, 直接说"该通路在 RTP_vs_RT 中方向**反向**, 即富集回 Model 方向"。这导致 NES 方向解读错误。

**修正后**:
- 模板第 3.1 节明确每个处理组的角色(RT=治疗组1, RTP=治疗组2, P=放疗增敏药)
- §2.1.4 明确说"RTP_vs_RT 的 right_group=RT, NES<0 仍富集在 RT 端, P 药压制了 RT 端的相对富集"
- 报告表述: "在 RT↔Model 这条比较轴上, RTP 端的免疫表型更接近 Model" (而不是"回到 Model")

## 4. Subagent 调用语义

### 4.1 正常调用

```
用户: "帮我分析这个 GSEA 结果: <rds_path>"
→ 主 agent 启动 gsealens-explorer subagent
→ subagent 从 S0 开始
```

### 4.2 多组织调用

```
用户: "我有两个组织的 GSEA 结果, 一个是胰腺, 一个是肝脏"
→ 主 agent 启动 2 个 gsealens-explorer subagent (并行)
→ 各自独立完成 S0-S6
→ 主 agent 调用 crosstalk 汇总 (S6b)
→ 输出: tissue_A_report.md + tissue_B_report.md + crosstalk_report.md
```

### 4.3 增量调用

```


用户: "上次分析了胰腺, 现在加一个肝脏"
→ 主 agent 检测到已有 tissue_A_report.md
→ 只启动 tissue_B subagent
→ B 完成后调 crosstalk 汇总
```

### 4.4 [v0.5.5 新增] 多 subcollection 调用 — 强制覆盖 26 个 subcollection

**触发条件**: RDS 包含 ≥10 个 subcollection (本研究 26 个)

**架构**:
```
主 Agent (gsealens-explorer v0.5.5)
  ├── Subagent A-E (核心 5 主题)
  ├── Subagent F1 (新, v0.5.5 强制) — CGP 全集 (~740 独立通路)
  ├── Subagent F2 (新, v0.5.5 强制) — WikiPathways/KEGG_MEDICUS/BIOCARTA/PID
  ├── Subagent F3 (新, v0.5.5 强制) — GO:CC/GO:MF/HPO
  ├── Subagent F4 (新, v0.5.5 强制) — IMMUNESIGDB/VAX/3CA/CGN/CM
  ├── Subagent F5 (可选) — TFT/MIR
  └── 主 Agent 汇总
```

**Subagent 分配原则**:
- 每 subagent 处理 2-5 个 subcollection
- 每 subagent ≤ 2000 通路 (LLM 上下文余量)
- 主题相关性聚类 (F1=CGP, F2=路径库, F3=功能注释, F4=免疫癌症)

### 4.5 [v0.5.5 新增] Agent 能力清单 (MANDATORY)

#### 4.5.1 主 Agent 能力清单

| 能力域 | 能力项 | 工具/资源 |
|---|---|---|
| R 数据加载 | RDS 读取, contrast_registry, 全 28343 通路 | R REPL via `r-interactive` |
| S4 数据提取 | **26 subcollection 全部独立 CSV (G13 强制)** | R `extract_all_subcollections()` |
| Medium 阈值 | evidence/medium/ 备用, 默认不纳入 (G14) | R `extract_sig_medium()` |
| Cascade heatmap | 6 簇聚类, NES 矩阵 + Ward.D2 + 星号 | R `pheatmap` |
| 跨对比组联合 | 5201 union, 模式 A/B/C/D 分类 | R + Python |
| MSigDB 知识增广 | 全 26 subcollection BRIEF/FULL/PMID | mcp__msigdb__* |
| 文献验证 | deepxiv + research-tools (bioRxiv 禁用) | mcp__deepxiv__*, mcp__research-tools__* |
| 主题拆分 | **7-11 主题** (5 核心 + F1-F6 增量) | runSubagent |
| Master 整合 | 跨主题信号流图 (Mermaid), 9 大涌现假说 | 主 Agent |
| 质量门控 | **G1-G14** 全套自检 (G13 v0.5.5 新增) | Python |

#### 4.5.2 Subagent F1-F4 能力清单 (核心)

**F1 (CGP)**:
- 输入: `*_CGP.csv` (3 个对比组, 共 1251 通路)
- 输出: `deep_discussion/F1_cgp_perturbations.md` + `evidence/msigdb_brief_F1_cgp.json` + `evidence/literature_verification_F1.json` + `evidence/cgp_cluster_summary.csv`
- 强制: 全 1251 通路纳入, 9 聚类, hub 基因频次, ≥30 胰腺炎 marker 重叠, ≥2 涌现假说

**F2 (路径数据库)**:
- 输入: `*_CP_KEGG_MEDICUS.csv` (55-59), `*_CP_WIKIPATHWAYS.csv` (173-175), `*_CP_BIOCARTA.csv` (33-36), `*_CP_PID.csv` (62-65)
- 强制: KEGG 名称误导防御 (PARKINSONS/ALZHEIMERS/HUNTINGTONS 实际是 Complex I/II/III/IV), ≥2 涌现假说

**F3 (GO:CC/MF + HPO)**:
- 输入: `*_GO_CC.csv`, `*_GO_MF.csv`, `*_HPO.csv` (共 869 通路)
- 强制: 全 869 通路纳入, hub 基因跨通路频次表, ≥3 涌现假说

**F4 (免疫癌症扰动)**:
- 输入: `*_IMMUNESIGDB.csv` (493-669), `*_VAX.csv` (28-44), `*_3CA.csv` (24-51), `*_CGN.csv` (21-79), `*_CM.csv` (32-75) (共 2399 通路)
- 强制: 全 2399 通路纳入, 6 Flip 通路识别, ≥3 涌现假说

#### 4.5.3 Subagent Prompt 模板 (强制规范)

```markdown
# 你是 gsealens-explorer v0.5.5 subagent {F1-F4 或 A-E}

# 工作目录
{out_dir}

# 输入文件
- {list_of_csv_files}

# 任务清单 (强制, 不能跳过)
1. 加载所有相关 CSV, **全部纳入** (不是 top N) — 全量分析!
2. 按 {collection_specific_cluster_logic} 聚类
3. MSigDB BRIEF 调用 (强制 §3a): 每个聚类至少 3 条代表通路
4. leading edge 解析: 至少 10 条核心通路, 提取实际基因名
5. 跨对比组解读 (§2.1.4 NES 反转精确分类): 模式 A/B/C/D 计数
6. 文献验证 (强制 §3b): 任何 PMID 必须用 mcp__deepxiv__search_papers 验证; **禁止 bioRxiv**
7. 涌现发现 (SOP §3a): 至少 2 个新涌现假说, 每个有 ≥3 条 BRIEF/FULL 支撑

# 输出文件 (强制)
- deep_discussion/{topic_id}_{topic_name}.md  (主报告, 15-50 KB)
- evidence/msigdb_brief_{topic_id}.json  (≥15 BRIEF)
- evidence/literature_verification_{topic_id}.json
- evidence/{topic_id}_cluster_summary.csv

# 严格禁止
- ❌ "激活" / "抑制" / "上调" / "下调" 等错误推断
- ❌ 编造 PMID / 作者 / 期刊
- ❌ 仅凭通路名推断生物学 (必须查 BRIEF/FULL)
- ❌ 使用 bioRxiv/medRxiv 搜索
- ❌ 限制 top N — 必须全量分析
- ❌ "代表图"而无 n 标注
```

#### 4.5.4 Subagent 启动时机

| 阶段 | 触发 | Subagent |
|---|---|---|
| **S4 后立即** | RDS 已加载, sig_all 已构造 | F1-F4 (v0.5.5 新) |
| **S6 后** | cascade heatmap 与跨对比组联合表完成 | A-E (5 核心) |
| **S7b** | 主题规划完成 | F5 (可选, TFT + MIR) |
| **S7 末** | 9+ 主题子报告完成 | Master 整合 |

#### 4.5.5 Subagent 失败回退策略

| 失败类型 | 回退方案 |
|---|---|
| 输出过大 (>50KB) 触发长度限制 | 拆分为 2 个 subagent (按 NES 正负拆) |
| 挂起 (>2 分钟无输出) | 用简化 prompt 重启 (MSigDB BRIEF <20 条) |
| MSigDB BRIEF 查询超时 | 用本地 SQLite (`msigdb_scraper/msigdb.db`) |
| 文献验证失败 | 用 `mcp__research-tools__paper_search` 替代 `mcp__deepxiv__*` |

## 5. 数据提取策略 (全量 + 按需)

### 5.1 全量提取 (默认)

```r
# 不限制 top-N, 提取全部显著通路
df_sig <- df[df$p.adjust < 0.05 & abs(df$NES) >= 1.0, ]
```

理由:
- 1M 上下文窗口足够容纳全部 Hallmark (50) + GO:BP (数百显著) + Reactome (数百显著)
- subagent 分拆处理: 每个 collection 一个子任务
- 汇总时才有完整的"涌现"基础

### 5.2 按 collection 分组

| Collection | 通路数 | 提取策略 |
|---|---|---|
| H (Hallmark) | 50 | 全部 (含不显著的) |
| C5:GO:BP | ~数千显著 | 全部显著 (FDR<0.05, \|**|NES| enrichment direction framework**|≥1.0) |
| C2:CP:REACTOME | ~数百显著 | 全部显著 |
| C2:CP:KEGG | ~数百显著 | 全部显著 |
| C5:GO:CC / GO:MF | 可选 | 按需 |
| C7 (ImmuneSigDB) | 可选 | 免疫相关研究时启用 |

### 5.3 输出格式 (|NES| enrichment direction)

CSV 列:
- `ID` — 通路名
- `|NES|` — 绝对值 (新增)
- `NES` — 原始值 (保留)
- `Enriched_In` — 富集方向: `{left_group}` 或 `{right_group}` (新增)
- `Confidence` — High/Medium/Low (新增)
- `p.adjust` — FDR
- `Description` — 通路描述
- `core_enrichment` — leading edge 基因 (/ 分隔)
- `Collection` / `Subcollection`

## 5e. 全量 subcollection 覆盖规则 [v0.5.5 新增, MANDATORY]

### 核心规则

> **gsealens-explorer 必须对 RDS 中所有 subcollection 的 High 显著通路进行全量深度解读, 不能只覆盖 H/C5/C2:REACTOME/C2:KEGG 4 个。**

### 触发条件 (强制)
- 任何 RDS 包含 ≥5 个 subcollection 时 (本研究 26 个), **必须全量覆盖**
- LLM 上下文足够 (1M tokens), 不要"为节省 token 而 top-N"
- 拆分 subagent 并行: 每 subagent 处理 2-5 个 subcollection, 不超过 2000 通路

### S4 阶段输出 CSV 规则 (强制)

```r
# v0.5.5 S4 必做: 26 个 subcollection 全部独立 CSV
# 命名约定: {contrast}_{short_tag 或 Subcollection}.csv
# 例: AduCer_vs_Con_CGP.csv, AduCer_vs_Con_CP_WIKIPATHWAYS.csv

extract_all_subcollections <- function(cn, x) {
  df <- x$results[[cn]]$data@result
  # 提取所有 subcollection (从 used_collections 取 short_tag)
  subcoll_tags <- unique(x$geneset_info$used_collections$short_tag)
  for (tag in subcoll_tags) {
    sub <- df[!is.na(df$p.adjust) & !is.na(df$NES) &
              df$p.adjust < 0.05 & abs(df$NES) >= 1.5 &
              df$Subcollection == subcoll_name_from_tag(tag), ]
    write.csv(sub, sprintf("%s_%s.csv", cn, tag), row.names=FALSE)
  }
}
```

### 26 个 subcollection 必查清单 (v0.5.5)

见 §2.5 全 Collection 深度解读 表格。

## 5b. Leading edge 强度加权 — CPM × logFC 联合过滤 [v0.5.4, OPTIONAL parallel to default GSEA]

### 核心问题
GSEA 的 leading edge 给出"对富集贡献最大的基因", 但**仅按排序指标 (t 统计量) 排序**, 忽略了一个生物学核心问题:

> **低 CPM 的大 logFC ≠ 高 CPM 的大 logFC**

| 场景 | log2FC | CPM (基线) | CPM (处理) | 解读 |
|---|---|---|---|---|
| 场景 A | +3.0 | 2 | 16 | 数学上大差异, 生物学上无意义 (绝对量太低) |
| 场景 B | +1.5 | 100 | 300 | 数学上中等, 生物学上**绝对变化量大** |
| 场景 C | +2.5 | 5 | 40 | 中等, 边缘可信 |

如果不做 CPM 过滤, leading edge 中的低 CPM 噪声基因会**污染 ORA-overlap 分析** 和涌现发现的逻辑链。

### 必备数据
RDS 中必须包含 `expr_bundle$display_expr` (log-CPM 归一化矩阵) 与 `de_store$<contrast>` (含 logFC, padj) 才能进行 CPM 加权。

| RDS 字段 | 用途 |
|---|---|
| `x$expr_bundle$display_expr` | 11761 × N matrix (log-CPM, ENSEMBL ID × sample) |
| `x$expr_bundle$sample_meta$group` | 18 样本分组 (AduCer/AgeCer/Con) |
| `x$de_store$<contrast>` | 含 `logFC, pvalue, padj, SYMBOL, gene_symbol` |
| `x$de_store$<contrast>$gene_symbol` | 用于 SYMBOL → ENSEMBL 映射 |

### 4 步加权流程 (S6 / S7b 强制)

#### 步骤 1: 计算每组 mean_CPM
```r
# 对每个对比组 (AduCer_vs_Con 为例)
left_group  <- "AduCer"
right_group <- "Con"

# expr_bundle rownames 是 ENSEMBL, 需映射
expr_mat   <- x$expr_bundle$display_expr           # log-CPM
sample_grp <- x$expr_bundle$sample_meta$group
left_samples  <- rownames(sample_grp)[sample_grp == left_group]
right_samples <- rownames(sample_grp)[sample_grp == right_group]

mean_cpm_left  <- rowMeans(expr_mat[, left_samples])    # 每个基因在 left 组的 mean log-CPM
mean_cpm_right <- rowMeans(expr_mat[, right_samples])   # 每个基因在 right 组的 mean log-CPM
# 反 log 化 (可选, 便于绝对量比较)
mean_count_left  <- 2^mean_cpm_left
mean_count_right <- 2^mean_cpm_right
```

#### 步骤 2: 定义生物学强度评分 (BIS, Biological Intensity Score)
对每个基因计算:
```r
# BIS = |logFC| × log2(max(mean_count_left, mean_count_right) + 1)
# 这样: 大 logFC 且高表达 → 高分; 大 logFC 但低表达 → 折扣; 小 logFC 但高表达 → 中等

bis_score <- abs(de_df$logFC) * log2(pmax(mean_count_left, mean_count_right) + 1)
```

#### 步骤 3: 双重过滤生成"可信 leading edge"
```r
# 默认阈值 (可调)
CPM_FLOOR <- 10      # mean count 至少 10 才算"真实表达"
PADJ_CUTOFF <- 0.05  # 显著
ABS_LOGFC  <- 1.0    # |logFC| ≥ 1

# 三重过滤
de_trusted <- subset(de_df,
                     padj < PADJ_CUTOFF &
                     abs(logFC) >= ABS_LOGFC &
                     pmax(mean_count_left, mean_count_right) >= CPM_FLOOR)

# 与 leading edge 取交集
le_genes <- unlist(strsplit(core_enrichment_string, "/"))
le_trusted <- intersect(le_genes, de_trusted$gene_symbol)
cat("leading edge total:", length(le_genes),
    "trusted (CPM+p):", length(le_trusted),
    "filtered out:", length(le_genes) - length(le_trusted), "
")
```

#### 步骤 4: 重排 leading edge (按 BIS 降序)
```r
le_ranked <- de_trusted[de_trusted$gene_symbol %in% le_genes, ]
le_ranked <- le_ranked[order(-bis_score[match(le_ranked$gene_symbol, de_trusted$gene_symbol)]), ]
```

### ORA-Overlap 视角 [v0.5.3 新增]

GSEA 解读的本质是**把 leading edge 当作 ORA 集合**, 然后做基因共现分析 — 这是把 S6/S7 涌现发现与"经典 ORA"接通的桥梁。

#### 与经典 ORA 的对应关系

| 经典 ORA 输入 | GSEA leading edge 类比 |
|---|---|
| DE 显著基因集 (DEG list) | `core_enrichment` (GSEA leading edge) |
| 超几何检验 / Fisher 精确 | GSEA 已做 (NES, FDR) |
| Background = 全基因 | `x$expr_bundle` 全部 11761 基因 |
| 通路数据库查询 (Reactome/KEGG/GO) | **MSigDB MCP (mcp__msigdb__get_genesets_by_genes)** |
| 通路内基因共现 | `get_genesets_by_genes(genes = leading_edge)` 找到**包含这些基因的其他通路** |

#### 强制 ORA-Overlap 流程 (S6 / S7b)

```
对每条被深度解读的显著 GSEA 通路 P:
  1. 提取 leading edge (core_enrichment, / 分隔)
  2. CPM × logFC 过滤 → trusted_le (步骤 1-3)
  3. 调用 mcp__msigdb__get_genesets_by_genes(
       genes = trusted_le[1:30],  # top 30 避免噪声
       require_all = false,       # OR 模式, 找到包含任意 trusted_le 基因的集合
       limit = 30
     )
  4. 对返回结果按 match_count 降序排列
  5. 用 BRIEF/FULL 描述检查"共同主题" — 这是涌现发现的核心
```

#### 解读模板 (S6 引用)

```
通路 X (HALLMARK_OXIDATIVE_PHOSPHORYLATION, NES=-1.8) 在 {treatment} 组被抑制。
Leading edge 共 30 个基因, 其中 27 个通过 CPM≥10 + |logFC|≥1 + padj<0.05 三重过滤
(trusted=27, filtered=3, 主要为低 CPM 噪声)。对 trusted_le 做 ORA-overlap
(get_genesets_by_genes, OR 模式) 找到 12 个共现集合, 共同主题为:
  - {REACTOME_RESPIRATORY_ELECTRON_TRANSPORT, BRIEF="..."
  - {KEGG_OXIDATIVE_PHOSPHORYLATION, FULL="Complex I/III/IV 装配..."}
  - {GOBP_MITOCHONDRIAL_RESPIRATORY_CHAIN_COMPLEX_I_ASSEMBLY, ...}
→ 该集合虽名为"氧化磷酸化", 实际同时驱动线粒体呼吸链复合物 I 的组装,
  提示 {treatment} 通过抑制 Complex I 装配而非单纯电子传递链基因表达来削弱 OXPHOS。
```

### 输出物 (写入 evidence/)
- `evidence/leading_edge_cpm_filtered_<contrast>_<pathway>.csv` — 过滤前后对比
- `evidence/ora_overlap_<contrast>_<pathway>.csv` — MSigDB 共现结果
- `evidence/biological_intensity_score.csv` — 所有 DE 基因的 BIS 评分

### G 门控
- G9 [v0.5.3 新增, **v0.5.4 改为 OPTIONAL**]: 当用户**显式启用** CPM 加权时, 任何 leading edge 解读必须先经过 CPM 过滤, 输出 trusted/trusted ratio ≥ 60% (即过滤掉 ≥40% 的低 CPM 基因视为可信)。**默认 (未启用) 时**: 仍可输出 raw leading edge 解读, 不触发 G9。
- 违规 (仅在启用时): 报告出现"leading edge 包含基因 X"但未做 CPM 过滤 → G9 失败

### 与现有 S6 / S7 流程的接入点
- **S6 (深度解读)**: 步骤 6 之前, 调 CPM 过滤 + ORA-overlap
- **S7b (并行深度)**: 每个主题 subagent 必做 CPM 过滤
- **S6b (跨对比组)**: 比较 trusted_le 在不同对比组间的差异, 比 raw leading edge 更稳健
- **S10 (Follow-up)**: 用户指定基因/通路时, BIS 评分作为基因排序权重

## 5c. 多对比组 GSEA 串联热图 — 模式涌现发现 [v0.5.4, MANDATORY for S6/S7]

### 核心思想
单组 GSEA dot plot 只能展示"通路在某对比组中是否显著", 但**多组对比的"通路响应模式"才是真正的涌现信息**。

> **核心假说**: 受同一驱动力调控的通路会呈现**相似的 NES 方向 × 强度 × 显著性 模式**。把这些模式可视化为"通路 × 对比组"热图, 即可通过聚类看到驱动力分层。

### 适用范围
- **3 组**: {A_vs_B, B_vs_C, C_vs_A} 三列
- **4 组**: {A_vs_B, A_vs_C, A_vs_D, B_vs_C, B_vs_D, C_vs_D} 6 列
- **5+ 组**: 全组合 C(n,2) 列; 若 n>5 则按生物学意义选关键子集 (如 treatment vs control, time series)

> **与 GSVA 的区别**: GSVA 在样本级计算通路活性 (per-sample score), 然后用样本聚类。本方法是**基于 GSEA 通路级 NES** 做的, 直接在通路 × 对比组矩阵上聚类 — 适合"通路在多组处理下的差异响应模式"问题, 比 GSVA 更聚焦于 GSEA 已经发现的显著通路。

### 数据准备 R 代码

```r
# 1. 收集所有对比组的显著通路 (FDR<0.05, |NES|>=1.0)
all_sig <- list()
for (cn in names(x$results)) {
  df <- x$results[[cn]]$data@result
  sig <- df[!is.na(df$p.adjust) & !is.na(df$NES) &
            df$p.adjust < 0.05 & abs(df$NES) >= 1.0,
            c("ID", "Description", "NES", "p.adjust", "setSize",
              "Collection", "Subcollection")]
  sig$contrast <- cn
  all_sig[[cn]] <- sig
}
all_sig_df <- do.call(rbind, all_sig)

# 2. 构建通路 × 对比组 NES 矩阵 (核心矩阵)
# 取所有对比组中出现过的显著通路 (union)
all_pathways <- unique(all_sig_df$ID)
contrast_ids <- names(x$results)

nes_mat <- matrix(NA_real_,
                  nrow = length(all_pathways),
                  ncol = length(contrast_ids),
                  dimnames = list(all_pathways, contrast_ids))

padj_mat <- nes_mat  # 同形矩阵, 装 padj
signif_mat <- nes_mat  # 同形, 装显著性星号

for (cn in contrast_ids) {
  df <- x$results[[cn]]$data@result
  matched <- match(all_pathways, df$ID)
  ok <- !is.na(matched)
  nes_mat[ok, cn]   <- df$NES[matched[ok]]
  padj_mat[ok, cn]  <- df$p.adjust[matched[ok]]
  # 显著性星号
  p <- padj_mat[ok, cn]
  sig <- rep("", sum(ok))
  sig[p < 0.1]    <- "."
  sig[p < 0.05]   <- "*"
  sig[p < 0.01]   <- "**"
  sig[p < 0.001]  <- "***"
  sig[p < 0.0001] <- "****"
  signif_mat[ok, cn] <- sig
}

# 3. NES 缺失值 (NS) 用 0 填充, 但显著性矩阵用空字符串
nes_mat_filled <- nes_mat
nes_mat_filled[is.na(nes_mat_filled)] <- 0
```

### 颜色编码 (强制规范)

| 元素 | 编码方式 | 颜色 |
|---|---|---|
| NES 方向 | 红=正 (NES>0, 富集在 left_group), 蓝=负 | `scale_color_gradient2(low="blue", mid="white", high="red")` |
| NES 强度 | 颜色深度 (abs(NES) 越大越饱和) | 0=white, 1=浅, 2=深, 2.5+=最饱和 |
| 显著性 | 文本星号 (`.`/`*`/`**`/`***`/`****`) | 黑色叠加在颜色背景上 |
| NS 通路 | 该格用 0 填充 + 无星号 | 浅灰底 (avoid 误导) |

### 聚类与排序

```r
# 方法 1: Ward.D2 层次聚类 (推荐)
row_dist <- as.dist(1 - cor(t(nes_mat_filled), method="spearman"))
row_hc   <- hclust(row_dist, method="ward.D2")

# 方法 2: 按 NES 模式分箱 (更易解释)
# 把通路按"在哪些对比组显著富集"分箱, 箱内按 |NES| 排序
# 例: bin "A_vs_B only" / "B_vs_C only" / "A_vs_B + B_vs_C" / "all three" 等
```

### 可视化 (R 推荐工具)

```r
# 推荐: pheatmap (聚类 + 注释 + 星号)
library(pheatmap)
library(RColorBrewer)

# 显著性星号叠加 (pheatmap 不原生支持, 需用 display_numbers)
# NES 矩阵 → 仅显示有显著性的位置
display_mat <- ifelse(is.na(padj_mat), "", signif_mat)

pheatmap(nes_mat_filled,
         color = colorRampPalette(c("#2166AC", "white", "#B2182B"))(100),
         breaks = seq(-3, 3, length.out = 101),
         cluster_rows = row_hc,
         cluster_cols = FALSE,  # 对比组按 contrast_registry 顺序固定
         display_numbers = display_mat,
         fontsize_number = 8,
         number_color = "black",
         cellwidth = 20, cellheight = 6,
         main = "Multi-Contrast GSEA Cascade Heatmap")
```

### Python 等价实现

```python
import seaborn as sns
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.cluster.hierarchy import linkage, dendrogram
from scipy.spatial.distance import pdist

# nes_mat: pd.DataFrame, rows=pathways, cols=contrasts
# padj_mat: pd.DataFrame, same shape, padj values
# signif_mat: pd.DataFrame, same shape, star strings

# 1. Cluster rows by Spearman correlation
row_link = linkage(pdist(nes_mat.fillna(0), metric='correlation'),
                   method='ward')
row_order = dendrogram(row_link, no_plot=True)['leaves']

# 2. Build annotation text: NES value + significance stars
annot = nes_mat.round(1).astype(str) + "
" + signif_mat

# 3. Heatmap
fig, ax = plt.subplots(figsize=(len(nes_mat.columns)*0.8,
                                len(nes_mat)*0.18))
sns.heatmap(nes_mat.iloc[row_order].fillna(0),
            cmap='RdBu_r', center=0, vmin=-3, vmax=3,
            annot=annot.iloc[row_order],
            fmt='', annot_kws={'size': 6},
            cbar_kws={'label': 'NES'},
            ax=ax)
ax.set_xlabel('Contrast')
ax.set_ylabel('Pathway (clustered)')
ax.set_title('Multi-Contrast GSEA Cascade Heatmap')
plt.tight_layout()
plt.savefig('cascade_heatmap.png', dpi=300, bbox_inches='tight')
```

### 涌现发现 — 模式归纳

聚类后, 按通路簇给出涌现主题:

| 模式 (3 组示例) | 含义 | 典型通路 | 涌现解读方向 |
|---|---|---|---|
| **All-Positive** | 在所有对比组富集在 left | HALLMARK_INFLAMMATORY_RESPONSE, GO_T_CELL_ACTIVATION | 治疗组的统一激活特征 |
| **All-Negative** | 所有对比组富集在 right | HALLMARK_OXIDATIVE_PHOSPHORYLATION | 治疗组的统一抑制特征 |
| **Flip-A→B vs B→C** | A→B 正, B→C 负 | 上皮间充质转化 / 干细胞性 | B 是中间过渡态 |
| **A→B only** | 仅在 A vs B 中显著 | 应激/免疫 | 该过程只在特定处理下 |
| **B→C only** | 仅在 B vs C 中显著 | 代谢重塑 | 该过程只在恢复/二次处理中 |
| **Mixed direction** | A vs B 正, C vs A 也正 | 代偿性激活 | 双向反馈环 |

### 4 步归纳流程 (强制)

```
1. EXTRACT  — 从 all_sig_df 取出全显著通路, 构建 nes_mat / padj_mat / signif_mat
2. CLUSTER  — Ward.D2 聚类通路行, 提取 N 个簇 (动态 cutree, k=3~7)
3. SUMMARIZE — 每个簇手工/半自动命名主题 (用 mcp__msigdb__get_geneset_brief 抽样验证)
4. INTERPRET — 把每个簇与 S1 实验背景关联, 给出 1-2 句涌现解读
```

### 输出物

- `evidence/cascade_heatmap_<study>.pdf` / `.png` — 高分辨率热图
- `evidence/cascade_clusters.tsv` — 每个簇的通路列表 + 簇名 + 主题解读
- `evidence/cascade_summary.md` — 4 步流程的中间产物

### G 门控
- G11 [v0.5.4 新增]: 跨 ≥3 对比组的 GSEA 报告必须含 cascade heatmap
- 违规: 报告只展示单组 dot plot, 未做多组串联 → G11 失败

### 接入点
- **S6 (深度解读)**: 收尾前必须出 cascade heatmap
- **S6b (跨对比组)**: cascade heatmap 是 S6b 核心交付物之一
- **S7b (并行深度)**: 主题 subagent 可选择性引用本节
- **S10 (Follow-up)**: 用户对"模式"感兴趣时, 重新聚类不同 K 值

### 局限与提示
- 仅展示**显著通路** (FDR<0.05, |NES|≥1.0), NS 不展示 (避免背景噪声)
- 对比组数 > 6 时, 考虑只展示其中 4-5 个最关键的 (用户可在 S3 阶段指定)
- 若通路在某对比组中 NES 接近显著但未达标, 可在图注标"borderline (padj<0.1)"

## 5d. BulkRNA-seq 功能分析知识库扩展 (Bioconductor & 工具盘点) [v0.5.4]

### 定位
gsealens-explorer 的核心数据是 GSEA + MSigDB, 但**涌现发现不应只依赖单一工具**。本节盘点**主流 BulkRNA-seq 功能分析方法**, 标注每个方法的**适用范围、与 gsealens-explorer 的关系、是否可作为 gsealens-explorer 输出的下游/并行**。

> **方法论分层**:
> 1. **过表达分析 (ORA)**: 假设驱动型, 适合"已知基因 → 找通路"
> 2. **功能评分 (FCS / GSEA 类)**: 数据驱动型, 适合"全基因 → 看通路富集"
> 3. **通路活性推断 (Pathway Activity / GSVA / decoupleR)**: 样本级, 适合"每个样本的通路活性"
> 4. **网络与因果 (PPI / Causal)**: 关系驱动型, 适合"通路/基因间因果推断"

### 主流方法清单

#### 1. clusterProfiler 系列 (Bioconductor)

| 包 | 方法 | 适用范围 | 与 gsealens-explorer 关系 |
|---|---|---|---|
| **clusterProfiler** | ORA (enricher/enrichGO/enrichKEGG), GSEA (gseGO/gseKEGG), 通用 | 通用通路富集 (GO/KEGG/Reactome/MSigDB) | gsealens-explorer 内部已用其 GSEA 引擎; 后续 ORA 验证可调 enricher |
| **enrichplot** | dotplot, cnetplot, emapplot, gseaplot, ridgeplot | 富集结果可视化 | gsealens-explorer 推荐的 dotplot/enrichment plot 工具 |
| **DOSE** | DO (Disease Ontology) 富集, GSEA | 疾病本体论 | 可作为 gsealens-explorer S6 的 DO 补充查询 |
| **meshes** | MeSH 词条富集 | MeSH 词条 | 备用, 不主推 |
| **ReactomePA** | Reactome 通路富集 | Reactome 数据库 | 与 MSigDB C2:REACTOME 互补 (ReactomePA 是 Reactome 官方) |
| **ggnewscale** | 多层 ggplot 配色 | 富集图叠加 | 高级可视化 |

**gsealens-explorer 推荐**: 已经使用 clusterProfiler 引擎。ORA 验证时调 `clusterProfiler::enricher(gene=trusted_le, TERM2GENE=...)`。

#### 2. decoupleR (Bioconductor) [用户提及]

| 项 | 描述 |
|---|---|
| **核心思路** | 通用框架, 把**任何**通路/调控网络 (regulon) 的统计方法统一为 "estimate gene-level scores → compute pathway scores" |
| **统计方法** | 10+ 种: wmean, ulm, mlm, viper, gsva, ssgsea, ora, zscore, aucell, wsum, corr, norm_wmean, ... |
| **输入** | 表达矩阵 (log normalized) + 通路/regulon (基因集) |
| **输出** | 每个样本 × 每个通路的活性分数 (matrix) |
| **关键优势** | **统一接口支持多种统计方法**, 可对比 GSEA / GSVA / VIPER / AUCell 等的结果差异 |
| **典型 regulon** | DoRothEA (TF-target), PROGENy (pathway footprint), MSigDB, 用户自定义 |

**与 gsealens-explorer 的关系**:
- gsealens-explorer 的 GSEA 是**通路级 × 对比组** (NES)
- decoupleR 是**样本级 × 通路** (pathway activity)
- 二者**互补**: gsealens-explorer 出"哪些通路在对比组 A vs B 显著", decoupleR 出"每个样本在通路 X 上的活性分数"
- **可作下游**: 用 gsealens-explorer 找到的 top 通路, 调 decoupleR 重算样本级活性, 验证"通路活性是否与样本分组一致"
- **可作并行**: 在 S6b 阶段同时跑 decoupleR (per-sample activity), 与 GSEA NES 做 cross-validation

**调用方式**:
```r
# R
library(decoupleR)
library(viper)  # 或其他 regulon 数据集
# 1. 加载 regulon (如 DoRothEA)
data(viper_regulon)
# 2. decoupleR 计算 (例: VIPER 算法)
acts <- run_viper(mat = expr_mat, network = viper_regulon, .source='source', .target='target')
# 3. 转 long format, 与样本元数据关联
```

```python
# Python (decoupleR 通过 rpy2 调 R, 或直接用 pydeseq2/decoupler-py)
# pip install decoupler-py
import decoupler as dc
acts = dc.run_viper(expr_mat, viper_regulon)
```

#### 3. GSVA / ssGSEA (Bioconductor)

| 包 | 方法 | 适用范围 |
|---|---|---|
| **GSVA** | 样本级通路活性 (非参数, KS-like) | 适合"每个样本的通路分数" |
| **ssGSEA** | 单样本 GSEA (Barbie et al. 2009) | 单样本的通路活性 |

**与 gsealens-explorer 的关系**:
- GSVA 输出**样本 × 通路活性矩阵**, 可直接做跨样本热图、跨组织比较
- **可作下游**: gsealens-explorer 出 top 通路后, 调 GSVA 重算样本级分数, 出 "pathway activity heatmap across samples" (图件模板的补充)
- **§5c 串联热图的替代视角**: GSVA 提供"样本级", GSEA-NES 提供"对比组级", 二者交叉验证

#### 4. AUCell (Bioconductor)

| 项 | 描述 |
|---|---|
| **核心思路** | 对每个细胞/样本, 用 AUC (曲线下面积) 评估基因集的富集, 不需要预设分组 |
| **典型场景** | 单细胞 RNA-seq (scRNA-seq), 但 bulk 也可用 |
| **优势** | 不依赖基因排序或 DEG 列表, 直接对表达矩阵做 |
| **与 gsealens-explorer 的关系** | 主要用于 scRNA-seq; bulk RNA-seq 场景下与 GSEA 互补度低于 decoupleR/GSVA |

#### 5. VIPER (Bioconductor, Alvarez et al. 2016)

| 项 | 描述 |
|---|---|
| **核心思路** | 基于 regulon 的样本级活性推断 (类似 decoupleR 的 viper 算法) |
| **核心优势** | 处理 regulon 方向性 (+/-) 比 GSEA 更严谨 |
| **与 gsealens-explorer 的关系** | 若用户有 TF-target regulon (如 DoRothEA), 可作下游 |

#### 6. fgsea (Bioconductor, fast preranked GSEA)

| 项 | 描述 |
|---|---|
| **核心思路** | GSEA 的快速 R 实现 (无 GUI, 适合 pipeline) |
| **与 gsealens-explorer 的关系** | gsealens-explorer 内部可能已用其; 用户也可独立调 |

#### 7. 通路网络与因果

| 包 | 方法 | 用途 |
|---|---|---|
| **STRINGdb** | PPI 网络 + 通路富集 | 蛋白互作网络 (可选) |
| **graphite** | 多通路数据库统一访问 | KEGG/Reactome/WikiPathways/PathwayCommons 转换 |
| **CEVA** | 单细胞调控网络推断 | 单细胞 (不主推 bulk) |
| **DOSE** | 疾病本体论 | 疾病关联 |
| **rWikiPathways** | WikiPathways 访问 | 替代 Reactome |

#### 8. 其他值得关注的 Bioconductor 包

| 包 | 用途 |
|---|---|
| **AnnotationDbi / org.Hs.eg.db / org.Mm.eg.db** | 基因 ID 转换 (SYMBOL ↔ ENSEMBL ↔ ENTREZ ↔ UNIPROT) |
| **biomaRt** | 远程 Ensembl/Biomart 查询 |
| **tximport** | Salmon/Kallisto 导入 (上游) |
| **DESeq2 / edgeR / limma** | 差异分析 (上游) — gsealens-explorer 不重复 |
| **ComplexHeatmap** | 高级热图 (推荐用于 cascade heatmap) |
| **clusterProfiler / enrichplot** | (已列) |
| **SummarizedExperiment** | gsealens-explorer RDS 的 `dge_list` 就是 DGEList, 可转 SE |
| **iSEE / shiny** | 交互可视化 (可选) |
| **goseq** | 长度偏倚校正的 ORA (适用于非编码或长度偏倚数据) |
| **topGO** | GO 层级结构利用的 ORA |
| **rrvgo** | GO 语义相似性聚类, 减少 GO:BP 冗余 (适合 §5c 聚类后的二次过滤) |

#### 9. Python 工具 (与 R 互补)

| 工具 | 用途 | 链接 |
|---|---|---|
| **decoupler-py** | decoupleR 的 Python 实现 (通过 AnnData) | https://decoupler.readthedocs.io/ |
| **gseapy** | Enrichr API + Python GSEA | https://gseapy.readthedocs.io/ |
| **pydeseq2** | DESeq2 的 Python 实现 | (上游) |
| **gprofiler-official** | g:Profiler Python 客户端 | (ORA 备选) |
| **bioinfokit** | 多种分析可视化 | (辅助) |

### gsealens-explorer 的方法学定位

```
                       ┌────────────────────────────────────────────┐
                       │      gsealens-explorer 核心方法栈 (已实现)      │
                       └────────────────────────────────────────────┘
                                            │
   ┌────────────────────┐         ┌─────────▼──────────┐         ┌────────────────────┐
   │ 上游 (不做)        │         │ 中游 (核心)         │         │ 下游 (推荐扩展)    │
   │ • DESeq2/edgeR     │  ─────► │ • clusterProfiler   │ ──────► │ • decoupleR        │
   │ • Salmon/Kallisto  │         │   (GSEA, ORA)       │         │ • GSVA / ssGSEA    │
   │ • tximport         │         │ • MSigDB MCP (§3a)  │         │ • VIPER            │
   │                    │         │ • fgsea (可能已用)  │         │ • ComplexHeatmap   │
   └────────────────────┘         └────────────────────┘         │ • rrvgo (GO 聚类)  │
                                                                   └────────────────────┘
                                                    │
                                                    │  §5c 跨对比组串联
                                                    │  §5b CPM 加权
                                                    │  §5d 工具盘点 (本节)
```

### gsealens-explorer 内部 R 包依赖清单

| 包 | 用途 | 必装 |
|---|---|---|
| **clusterProfiler** | GSEA + ORA 引擎 | ✅ 必装 |
| **enrichit** | GSEA 封装 (本项目使用) | ✅ 必装 |
| **fgsea** | 备选 GSEA 引擎 | ✅ 必装 |
| **msigdbr** | MSigDB 集合 (与 MSigDB MCP 互补) | ✅ 必装 |
| **org.Hs.eg.db / org.Mm.eg.db** | 基因 ID 转换 | ✅ 必装 |
| **AnnotationDbi** | 注释基础 | ✅ 必装 |
| **DOSE / ReactomePA** | DO/Reactome 备用 | 可选 |
| **ComplexHeatmap / pheatmap** | 热图 | ✅ 必装 |
| **ggplot2 / dplyr / tidyr** | 通用 | ✅ 必装 |
| **decoupleR** | 下游样本级活性 | ❌ 可选 (按需装) |
| **GSVA** | 下游样本级活性 | ❌ 可选 (按需装) |
| **rrvgo** | GO 聚类 | ❌ 可选 |
| **SummarizedExperiment** | SE 对象 | 可选 |

### 方法接入建议 (Roadmap)

| 阶段 | 推荐接入 | 价值 |
|---|---|---|
| **当前 v0.5.4** | §5c cascade heatmap + §5b CPM 加权 | 多对比组模式涌现 |
| **v0.5.5 (可选)** | decoupleR 样本级活性 + 与 GSEA-NES 交叉验证 | 增加"样本级"维度 |
| **v0.5.6 (可选)** | rrvgo GO:BP 语义聚类 (对 §5c 聚类结果二次精炼) | 减少 GO 冗余, 主题更清晰 |
| **v0.5.7 (可选)** | ComplexHeatmap 替代 pheatmap (cascade heatmap 增强) | 出版级热图 (含注释条) |
| **v0.5.8 (可选)** | clusterProfiler::enricher 独立 ORA 验证 | 与 GSEA leading edge 交叉验证 |

## 6. 脚本清单

| 脚本 | 用途 | 执行方式 |
|---|---|---|
| `scripts/extract_gsea_capsule.R` | R 端全量提取 | **R 持久 REPL** via `r-interactive` |
| `scripts/sniff_platform.R` | 平台嗅探 | Rscript one-shot OK (轻量) |
| `scripts/audit_logger.py` | 双格式审计 | python one-shot |
| `scripts/quality_gate_check.py` | G1/G2/G3 门控 | python one-shot |
| `scripts/run_full_pipeline.ps1` | Windows 一键 driver | PowerShell |

## 6b. Discussion 模块 (S7) [v0.3.2 新增]

### 定位
Discussion 不是"再总结一遍数据", 而是**把所有发现串联成一个完整的生物学故事**。
类似论文 Discussion 章节: 从数据出发, 回到生物学意义, 指出局限性, 提出新假说。

### 必须包含的 5 个层次

**层次 1: 主要发现概括** (1-2 段)
- 用 1-2 句话概括最核心发现, 结合用户 S1 的实验背景
- 例: "在脾脏放射治疗模型中, RT 单独处理引发了以 NF-κB/IL-6/JAK-STAT 为核心的急性炎症响应,
  而 RTP 在此基础上进一步激活了 mTORC1 和 MYC 驱动的代谢重塑程序。"

**层次 2: 机制整合** (2-4 段)
- 将 Hallmark / GO:BP / Reactome / KEGG 的发现**交叉整合**, 不是逐 collection 汇报
- 识别**跨 collection 的一致主题** (如: Hallmark TNFα/NF-κB + GO:BP 炎症反应 + Reactome NF-κB 信号 = 一致炎症主题)
- 指出**不同 collection 之间的互补** (Hallmark 给大主题, GO:BP 给具体过程, Reactome 给信号级联)
- 识别**跨对比组的变化趋势** (如: RT→RTP, 炎症通路 |NES| 下降而代谢通路 |NES| 上升)

**层次 3: 与已知文献对接** (1-2 段)
- 引用 S5 知识增广阶段查到的文献
- 将本实验发现与已知机制对接
- 指出一致之处和新发现之处

**层次 4: 局限性与替代解释** (1 段)
- 明确列出局限性
- 对关键发现提出替代解释
- 例: "本分析基于 bulk RNA-seq, 无法区分细胞类型特异的响应;
  NF-κB 通路的富集可能来自免疫细胞浸润而非实质细胞的自主激活。"

**层次 5: 新假说与下一步** (1 段)
- 从数据中涌现的新假说 (用户未明确询问的)
- 建议的下一步实验

### Discussion 写作规则
- ❌ 不能只是"再总结一遍表格"
- ❌ 不能引入数据中没有的结论
- ✅ 必须跨 collection 整合
- ✅ 必须跨对比组整合
- ✅ 必须引用文献
- ✅ 必须指出局限性
- ✅ 必须提出新假说

## 6b2. 并行深度讨论 (S7b) [v0.4 新增]

### 定位
S7 生成"概述级" Discussion。S7b 进一步将分析拆分为 **N 个生物学主题** (数据驱动, 非固定模板), 通过并行 subagent 同时生成深度子报告, 最后汇总为 master discussion。

### S7b.0 主题规划 (强制)

**主题不是固定的 5 个。** Agent 必须根据以下信息动态生成:

1. **S1 实验背景** (Q1-Q5): 造模/组织/动机/策略/预期表型
2. **S6 全 collection 分析结果**: Hallmark/GO:BP/Reactome/KEGG 的 top 信号
3. **S6b 跨对比组联合分析**: 核心签名 + 方向反转 + 特异通路

**主题生成算法**:
```
Step 1: 从 S6 结果中提取"信号簇"
  - 读取各 collection 的 top 30 显著通路 (|NES|≥1.5, FDR<0.05)
  - 按功能聚类: 将语义相关的通路归为一组
  - 每个簇必须包含 ≥3 条通路 (跨 ≥2 个 collection 优先)

Step 2: 结合实验背景确定主题优先级
  - 与用户预期表型 (Q5) 直接相关的簇 → 优先级高
  - 与用户科学动机 (Q3) 相关的簇 → 优先级高
  - 数据中涌现的非预期信号簇 → 作为"探索性"主题

Step 3: 确定最终主题 (3-7 个)
  - 每个主题必须有: 唯一标识符 (A/B/C/...)、主题名称、包含的通路列表、输出文件名

Step 4: 写入 {out_dir}/deep_discussion/theme_plan.md
```

### 参考模式 (非强制模板, 作为经验库)

| 模式 | 何时出现 | 典型通路 |
|------|----------|----------|
| 免疫激活 | 免疫器官/免疫相关实验 | IFN-α/γ, Allograft, T/B cell, NF-κB |
| 代谢重编程 | 能量代谢变化显著时 | OXPHOS, Glycolysis, Fatty acid, TCA |
| ECM/纤维化 | 组织损伤修复/纤维化实验 | EMT, Collagen, TGF-β, ECM |
| DNA 损伤/细胞命运 | 放疗/化疗/基因编辑实验 | p53, Apoptosis, DNA repair, Senescence |
| 翻译/生长程序 | 细胞增殖/分化相关实验 | MYC, mTORC1, Ribosome, Cell cycle |
| 神经/突触 | 神经系统实验 | Synapse, Neurotransmitter, Ion channel |
| 脂质代谢 | 代谢综合征/NAFLD 实验 | Cholesterol, Fatty acid, Lipid |
| 炎症/细胞因子 | 感染/自身免疫实验 | TNF, IL-6, IL-1, Complement |
| 激素响应 | 内分泌相关实验 | Estrogen, Androgen, Thyroid, Insulin |
| 肿瘤微环境 | 肿瘤实验 | Angiogenesis, Immune checkpoint, Hypoxia |

### S7b.1 用户交互 (主题选择)

Agent 自动生成推荐主题后, **必须展示给用户选择**, 不直接执行。

交互方式: 使用 `vscode_askQuestions` 工具, 展示推荐主题表 (multiSelect=true), 允许用户:
- 选择部分主题执行
- 删除不感兴趣的主题
- 新增自定义主题 (如 "脂质代谢", "自噬", "铁死亡")
- 合并主题
- 输入 "全部执行" 跳过选择

用户自由输入处理:
- 输入"脂质代谢" → agent 从 S6 CSV 中筛选相关通路, 自动组装为新主题
- 输入具体通路名 → agent 将该通路及其关联通路组装为新主题
- 输入"合并 A 和 C" → 合并通路列表

### 每个主题 subagent 必须完成的分析

1. **Leading Edge 基因提取** — 从 CSV 的 `core_enrichment` 列提取实际基因列表
2. **Hub 基因识别** — 找出出现在多条通路 leading edge 中的核心基因
3. **C2 先验基因集涌现分析** — 检查 KEGG/Reactome 标签的实际生物学含义
4. **跨对比组动态** — 同一通路在不同对比组中的 NES 变化趋势
5. **跨 collection 交叉验证** — 同一生物学主题在 Hallmark/GO:BP/Reactome/KEGG 中的一致性
6. **文献对接** — 将发现与已知机制对接

### Master Discussion 结构

```markdown
# 深度讨论: {实验名称} GSEA 全景分析

## 一、全局叙事: N 重转录重编程
(1 句话总结 + 全景表 + 跨主题信号流图)

## 二、跨主题核心发现深度整合
(识别子报告之间的交叉)

## 三、C2 先验基因集涌现分析
(KEGG 标签重解读、C2 vs Hallmark 互补关系)

## 四、与已知文献的系统对接

## 五、涌现假说与验证路径

## 六、局限性与替代解释

## 七、结论

## 附录: 子报告导航
```

## 6c. Follow-up 探索 (S10) [v0.3.2 新增]

### 触发条件
用户在阅读主报告后, 对某个通路/机制/基因感兴趣, 要求深入探索。

### 用户触发方式
```
"帮我深挖一下 NF-κB 通路在 RT vs RTP 中的差异"
"我想看 OXIDATIVE_PHOSPHORYLATION 的 leading edge 基因在其他数据集中的表现"
"MTORC1 通路的上游调控因子有哪些?"
```

### Follow-up 报告包含
1. **聚焦通路的详细 |NES| 表** — 跨所有对比组
2. **Leading edge 基因列表** — 标注每个基因在哪些对比组出现
3. **上游调控因子分析** — 用 Reactome / STRING 查上游 regulator
4. **下游效应分析** — 用 Reactome 查 downstream targets
5. **跨对比组变化趋势图** — Mermaid 图
6. **文献支撑** — PubMed/OpenAlex 查该通路在当前实验背景下的相关文献
7. **新假说** — 基于详细分析提出可验证的假说

### Follow-up 输出
```
{out_dir}/followup_{pathway_name}.md
```

### Follow-up 与主报告的关系
- Follow-up 是主报告的**补充**, 不替代
- 可以有多个 Follow-up
- Follow-up 的结论如果与主报告矛盾, 以 Follow-up 为准 (更详细)

## 6d. 论文级可视化排版规范 [v0.5.4, figure planning reference]

### 定位
gsealens-explorer 不做质控类图 (PCA / Volcano / 相关性热图) — 这些是上游分析产物, 应在上游 pipeline (DESeq2/edgeR + FastQC) 输出。本节是**figure planning 规范**, 帮分析工作者把 gsealens-explorer 的核心输出 (GSEA + leading edge + 涌现) 排布成可投稿的论文 figure。

### 设计原则

| 原则 | 含义 |
|---|---|
| **故事驱动** | 每张 figure 回答一个明确的科学问题, 不堆数据 |
| **多面板 (panel)** | 一张 figure 含 A/B/C panel, 讲完一个完整故事 |
| **数据流连贯** | Fig 3 (GSEA dot) → Fig 4 (cascade 热图) → Fig 5 (leading edge) → Fig 6 (机制模型) |
| **配色一致** | 通路方向红/蓝一致; 跨 figure 保持 |
| **字体统一** | 8-10 pt sans-serif, 数值坐标用 Arial/Helvetica |

### gsealens-explorer 推荐 4 张主 figure 模板 (GSEA 核心导向)

> **重要边界**: 本 SKILL 不负责 fig 1 (质控) / fig 2 (DE 结果) 的制作 — 那是上游 pipeline 的产物。gsealens-explorer 的输出从 fig 3 (GSEA 总体) 开始。

#### Figure 3. GSEA 功能富集 (GSEA-level overview) — 3 panel

| Panel | 内容 | 数据源 | 排版 |
|---|---|---|---|
| 3A | Hallmark 显著通路 dot plot (\|**|NES| enrichment direction framework**| × -log10(FDR)) | `results$<contrast>$data` filter Collection=H | dot color = NES 方向 (红=正, 蓝=负), dot size = gene count |
| 3B | GO:BP top 20 dot plot (按 cluster 排序) | `results$<contrast>$data` filter Collection=C5:GO:BP | dot plot, 主题聚类 (可用 rrvgo 二次精炼) |
| 3C | 经典 GSEA enrichment plot (代表性 3-4 条通路) | `core_enrichment` + `genelist` | 经典 GSEA 图, 黑色竖线为 leading edge, ES 曲线, NES + pvalue 标注 |

**图注模板**:
> "Figure 3. Gene set enrichment analysis of {contrast}. (A) Dot plot of significantly enriched Hallmark gene sets (FDR < 0.05, |NES| ≥ 1). Color indicates enrichment direction (red = enriched in {left_group}, blue = enriched in {right_group}); dot size represents gene set size. (B) Top 20 enriched GO:BP terms clustered by biological theme. (C) Representative GSEA enrichment plots for {n} selected pathways; leading edge genes are marked by vertical bars."

**Discussion 引用**:
> "GSEA revealed {n} significantly altered Hallmark pathways (Figure 3A), with strong suppression of OXPHOS and activation of inflammatory programs (Figure 3B-C)."

#### Figure 4. 多对比组 GSEA 串联热图 (cascade heatmap) [v0.5.4 核心] — 1-3 panel

| Panel | 内容 | 数据源 | 排版 |
|---|---|---|---|
| 4A | **3-6 对比组 GSEA cascade heatmap** (通路 × 对比组) | §5c nes_mat / padj_mat / signif_mat | NES 颜色梯度 (红=正, 蓝=负) + 星号叠加; 行 Ward.D2 聚类; 列按 contrast_registry 顺序 |
| 4B | 通路簇平均 NES 折线图 (3-5 个聚类簇) | §5c cascade_clusters.tsv | 每个簇一条折线, x=对比组, y=平均 NES, 标簇主题名 |
| 4C | 涌现模式分布饼图 (All-Pos / All-Neg / Flip / Mixed) | 模式分类统计 | 饼图, 标每类通路数 |

**图注模板**:
> "Figure 4. Multi-contrast GSEA cascade heatmap reveals pathway response patterns. (A) Heatmap of normalized enrichment scores (NES) for {n_sig} significant gene sets across {n_contrast} contrasts. Color indicates NES direction and intensity; asterisks indicate significance (\*p<0.05, \*\*p<0.01, \*\*\*p<0.001). Rows are clustered by Ward.D2 hierarchical clustering using Spearman correlation. (B) Average NES trajectory of {n_cluster} major pathway clusters across contrasts. (C) Distribution of {n_sig} pathways by emergent response pattern."

**Discussion 引用**:
> "To identify pathway response patterns across the experimental design, we performed multi-contrast GSEA cascade analysis (Figure 4A). Hierarchical clustering revealed {n_cluster} major pathway clusters with distinct NES trajectories (Figure 4B), of which {pattern_name} was the dominant pattern (Figure 4C), suggesting {emergent_interpretation}."

#### Figure 5. Leading edge × 涌现发现 (leading edge + ORA-overlap) — 3 panel

| Panel | 内容 | 数据源 | 排版 |
|---|---|---|---|
| 5A | Trusted leading edge 排序热图 (top 通路 × top 基因) | §5b 过滤结果, log2 fold-change | 通路行 × 基因列, 红=高表达, 蓝=低表达, 标 trusted/untrusted |
| 5B | ORA-Overlap 网络图 (leading edge 与其他通路共现) | `mcp__msigdb__get_genesets_by_genes` | 节点=基因集, 边=共享基因数, 节点大小=trusted_le 大小 |
| 5C | 跨对比组 leading edge 比较 (韦恩 / UpSet) | 3 对比组的 trusted_le | 三组韦恩或 UpSet, 标核心签名 |

**图注模板**:
> "Figure 5. Leading edge analysis and emergent biological themes. (A) Heatmap of trusted leading edge genes (n = {n_trusted}, filtered by CPM ≥ 10, |log2FC| ≥ 1, padj < 0.05) across top enriched pathways. Genes were ranked by Biological Intensity Score (|logFC| × log2(max_mean_count + 1)). (B) ORA-overlap network showing pathways that share trusted leading edge genes with {anchor_pathway}. Node size represents the trusted leading edge size; edge width represents shared gene count. (C) Cross-contrast comparison of trusted leading edges, identifying a core signature of {n_core} genes altered in all three contrasts."

**Discussion 引用**:
> "To assess the functional significance of the GSEA leading edge, we filtered genes by both effect size (|log2FC|) and absolute abundance (CPM ≥ 10), generating 'trusted' leading edges that are more likely to represent biologically meaningful changes (Figure 5A). ORA-overlap analysis revealed that {anchor_pathway} shares {n_shared} trusted genes with {other_pathways}, suggesting {emergent_theme} (Figure 5B)."

#### Figure 6. 机制模型图 (mechanism model) — 1 panel

| Panel | 内容 | 数据源 | 排版 |
|---|---|---|---|
| 6A | 综合机制模型 (整合 Fig 3-5 的发现) | Discussion 涌现假说 | 黑白线稿 + 关键分子/通路彩色高亮, 信号箭头 + 抑制线, 圆角矩形=通路, 椭圆=基因 |

**图注模板**:
> "Figure 6. Proposed mechanistic model. Integration of GSEA, cascade heatmap, and trusted leading edge filtering supports a model in which {treatment} induces {phenotype_A} via {mechanism_1} while suppressing {phenotype_B} via {mechanism_2}. Solid arrows indicate activation; blunt arrows indicate inhibition. Molecules highlighted in red/blue are upregulated/downregulated by {treatment}."

**Discussion 引用**:
> "Based on the convergence of multi-level evidence (Figures 3-5), we propose a mechanistic model whereby {treatment} acts through {core_pathway} to {key_effect} (Figure 6)."

### Supplementary 表格 / 图像

| 编号 | 内容 | 来源 |
|---|---|---|
| Table S1 | 完整 GSEA 显著通路列表 (所有 collection) | `results` 全量导出 CSV |
| Table S2 | MSigDB 涌现发现的 BRIEF/FULL 引用 | `mcp__msigdb__get_geneset_brief` 调用记录 |
| Table S3 | cascade heatmap 聚类簇完整列表 | `evidence/cascade_clusters.tsv` |
| Table S4 | ORA-overlap 共现结果 (用 enricher 独立验证) | clusterProfiler::enricher |
| Figure S1 | 上游质控图 (FastQC, 映射率, PCA) | 上游 pipeline 输出 |
| Figure S2 | 上游差异分析图 (Volcano, UpSet) | 上游 pipeline 输出 |
| Figure S3 | 每个主题的 deep discussion 子图 | `deep_discussion/<theme>.md` 关联图像 |
| Figure S4 | GSVA 样本级通路活性热图 (若用) | GSVA 下游 |

### Figure 排版检查清单 (G10 门控)

- [ ] 每张 figure 顶部是否有 1 句话"该图回答什么问题"
- [ ] Panel 编号 (A/B/C/D) 是否清晰, 阅读顺序是否自然
- [ ] 颜色映射是否跨 figure 一致 (NES 红正/蓝负; 治疗组颜色固定)
- [ ] 统计方法是否在图注中标明 (e.g. "padj < 0.05 by BH correction")
- [ ] 样本量 (n) 是否在图注中标明
- [ ] p 值标注是否使用统一格式 (*p < 0.05, **p < 0.01, ***p < 0.001, ****p < 0.0001)
- [ ] 关键基因名是否斜体 (基因) vs 正体 (蛋白) vs 大写 (pathway)
- [ ] Discussion 引用是否精确到 panel (e.g. "Figure 4A")
- [ ] 是否避免了"代表图"(代表性图像)而无 n 标注
- [ ] cascade heatmap 是否标了"颜色= NES, 文字=显著性星号"双重编码

### gsealens-explorer 输出与论文 figure 制作衔接

gsealens-explorer 输出 `01_exploratory_report.md` + `02_discussion.md` + `deep_discussion/` 后, 衔接模板:

```markdown
## 下一步: 论文 figure 制作 (gsealens-explorer 负责范围)

基于本分析, 建议按以下顺序制作 gsealens-explorer 负责的 4 张主 figure
(质控/DE 图由上游 pipeline 负责, 不在 gsealens-explorer 范围内):

1. **Figure 3** (GSEA dot + enrichment plot)
   - 数据已就绪: `results$<contrast>$data` + `core_enrichment` + `genelist`
   - 推荐工具: R `clusterProfiler::dotplot` + `gseaplot2` / `enrichplot`
2. **Figure 4** (cascade heatmap) [v0.5.4 核心]
   - 数据需生成: 运行 §5c 流程 → `evidence/cascade_heatmap_<study>.pdf` + `cascade_clusters.tsv`
   - 推荐工具: R `pheatmap` 或 `ComplexHeatmap` (出版级)
3. **Figure 5** (leading edge + ORA-overlap)
   - 数据需生成: 运行 §5b 流程 → `evidence/leading_edge_cpm_filtered_*.csv` + `evidence/ora_overlap_*.csv`
   - 推荐工具: R `pheatmap` + `igraph` / Cytoscape, 或 Python `seaborn` + `networkx`
4. **Figure 6** (机制模型)
   - 推荐工具: Adobe Illustrator / BioRender / draw.io (本工作区已有 drawio-skill)

每张 figure 的图注模板和 Discussion 引用句已在 §6d 提供, 直接复用即可。
上游质控 (Fig 1) / DE (Fig 2) 由 FastQC + DESeq2 pipeline 负责输出, 不在 gsealens-explorer 范围。
```

### 关键引用原则 (Discussion 中)

- 第一次提某 figure 时, 用完整句: "as shown in Figure 3A"
- 引用具体 panel, 不只说 "Figure 3": "Figure 3B shows..."
- 引用 supplementary 时, 用缩写: "(Table S1, Figure S3)"
- 跨 figure 引用: "These results (Figure 3B) are consistent with the cascade heatmap pattern (Figure 4A)"

### GSEA 图件推荐工具速查 (R vs Python)

| 图件 | R 推荐 | Python 推荐 |
|---|---|---|
| GSEA dot plot | `clusterProfiler::dotplot` / `enrichplot::dotplot` | `gseapy.dotplot` |
| GSEA enrichment plot | `enrichplot::gseaplot2` | `gseapy.gseaplot` |
| Cascade heatmap | `pheatmap` / `ComplexHeatmap` | `seaborn.heatmap` |
| Leading edge heatmap | `pheatmap` | `seaborn.clustermap` |
| ORA-overlap 网络 | `igraph` + `ggraph` / `Cytoscape` 导出 | `networkx` + `matplotlib` |
| 机制模型 | Adobe Illustrator / BioRender / draw.io | draw.io |

## 7. 质量门控 (v0.4 更新)

| Gate | 检查 | 失败处理 |
|---|---|---|
| G1 | 每个结论有 CSV 引用 + \|**|NES| enrichment direction framework**| 值 | 回 S6 |
| G2 | 无 "上调/下调/被抑制/被激活/NEG_in_left" | 回 S6 |
| G3 | 局限性声明含 FDR + \|**|NES| enrichment direction framework**| + 置信度 | 回 S6 |
| **G4** | **全 collection 覆盖** — Hallmark + GO:BP + Reactome + KEGG 都有分析章节 | 回 S6 |
| **G5** | **跨对比组联合分析** — 有核心签名表 + 特异通路表 + 方向一致性表 | 回 S6 |
| **G6** | **NES 语义正确** — 无 "NEG=抑制, POS=激活" 等错误推断; POS/NEG 仅描述富集方向 | 回 S6 |
| **G7** | **[v0.4] 深度讨论完整性** — deep_discussion/ 下有 theme_plan.md + N 个子报告 + 1 个 master (N 由 S7b.0 动态确定, ≥3 且 ≤7) | 回 S7b |
| **G8** | **[v0.4] Leading Edge 解析** — 每个子报告包含实际基因名 (非占位符), 至少 10 个具体基因 | 回 S7b |
| **G9** | **[v0.5.3 / v0.5.4 修订为 OPTIONAL] Leading edge CPM 过滤** — **当用户启用 CPM 加权时**, 每条被深度解读的通路必须有 trusted_le 列表 (CPM≥10 + \|logFC\|≥1 + padj<0.05), trusted/raw ratio ≥ 60%; **未启用时 G9 不适用** | 回 S5b |
| **G10** | **[v0.5.3 / v0.5.4 修订] Figure 排版自检** — gsealens-explorer 负责的 4 张主 figure (Fig 3 GSEA / Fig 4 cascade / Fig 5 leading edge / Fig 6 机制模型) 模板对齐, 颜色一致, 样本量/统计方法/星号均标注; Fig 1 (质控) / Fig 2 (DE) 不在 gsealens-explorer 范围 | 回 S6d |
| **G11** | **[v0.5.4 新增] 多对比组 cascade heatmap** — 当分析包含 ≥3 对比组时, 必须出 cascade heatmap (§5c), 行聚类, NES 颜色 + 显著性星号双重编码 | 回 S5c |
| **G12** | **[v0.5.2 新增] 文献验证 (PMID 都来自 MSigDB 或已验证)** — 所有 PMID 必须由 mcp__deepxiv__search_papers 或 mcp__research-tools__paper_search 验证, 禁止 bioRxiv | 回 S5 |
| **G13** | **[v0.5.5 新增, MANDATORY] 全量 subcollection 覆盖率** — 当 RDS 包含 ≥10 个 subcollection 时, 必须输出全部 subcollection 的独立 CSV (≥10/3 对比组 = ≥30 CSV), F1-F6 主题 subagent 全部分配解读; 不允许只覆盖 H/C5/C2:REACTOME/C2:KEGG 4 类 | 回 S4 |
| **G14** | **[v0.5.5 新增, OPTIONAL] Medium 阈值按需触发** — 默认不纳入 FDR∈[0.05, 0.25) 且 \|**|NES| enrichment direction framework**|∈[1.0, 1.5) 的通路, 仅在用户显式提及"不显著/边缘显著/中等置信/medium threshold"或指定关键词时纳入; evidence/medium/ 目录保留 Medium CSV 作为备用资产 | N/A |

**G6 具体检查**:
- ❌ "NEG 数量大于 POS, 提示基因集被抑制"
- ❌ "该通路在 treatment 组被激活"
- ❌ 将 POS/NEG 数量差异推断为生物学状态
- ✅ "更多通路富集在 control 组"
- ✅ "该通路富集在 treatment 组 (NES>0)"

## 8. 输出结构

**G6 具体检查**:
- ❌ "NEG 数量大于 POS, 提示基因集被抑制"
- ❌ "该通路在 treatment 组被激活"
- ❌ 将 POS/NEG 数量差异推断为生物学状态
- ✅ "更多通路富集在 control 组"
- ✅ "该通路富集在 treatment 组 (NES>0)"

## 8. 输出结构

```
gsea_explore_{study_id}/
├── metadata.json              # 实验元数据 (S1)
├── hypotheses.md              # 研究假设 (S2)
├── plan.md                    # 分析计划 (S3)
├── summary.md                 # 概览
├── {contrast}_Hallmark.csv    # 全量 Hallmark
├── {contrast}_GOBP.csv        # 全量 GO:BP 显著
├── {contrast}_ReactKEGG.csv   # 全量 Reactome/KEGG 显著
├── {contrast}_leading_edge.csv
├── {contrast}_gsealens_table.md  # |NES| enrichment direction |NES| 表
├── cross_contrast_joint.csv   # 跨对比组联合表
├── evidence/                  # SKILL 知识产物
├── 01_exploratory_report.md   # 主报告 (S6+S6b 数据分析)
├── 02_discussion.md           # Discussion 模块 (S7) — 生物学叙事
├── deep_discussion/           # [v0.4] 并行深度讨论 (S7b)
│   ├── theme_plan.md             # S7b.0 主题规划 (数据驱动, 记录主题分配逻辑)
│   ├── 00_master_discussion.md   # 跨主题整合 master 讨论
│   ├── A_{theme_name}.md         # 主题 A (名称由 theme_plan.md 动态确定)
│   ├── B_{theme_name}.md         # 主题 B
│   ├── ...                       # (N 个主题, N≥3 且 ≤7)
│   └── {N}_{theme_name}.md       # 主题 N
├── followup_{pathway}.md      # Follow-up 专题报告 (S10, 可多个)
├── crosstalk_report.md        # 多组织 crosstalk 报告 (如适用)
├── audit.log                  # 人类可读
└── audit.jsonl                # 机读
```

## 9. 相关 SKILL

- `r-interactive` — **强制** (R 持久 REPL)
- **`msigdb-local`** (MCP) — **强制** (MSigDB 本地元数据查询, 见 §3a, 8 阶段强绑定)
- `mcp__deepxiv__*` — **强制** (PubMed/arXiv 全文, 主选文献 MCP)
- `mcp__research-tools__*` — **强制** (引用验证, 期刊信息, 备选文献 MCP)
- `mcp__unified-acade__*` — OpenAlex/PubMed 学术搜索 (用于跨源汇总, 见 §3b) — **v2.1+ 调用前必须先 `activate_search_tools(scope="search")`**
- ❌ **`mcp__unified-acade__*` bioRxiv 相关工具** — **禁用** (见 §3b HARD BLOCK)
- `reactome-skill` / `quickgo-skill` — 通路知识
- `gdm-opentargets-database` — 靶点-疾病
- `gdm-string-database` — PPI (可选)
- `nature-paper2ppt` — 后续手动 PPT
- `academic-paper` — 后续手动论文

## 10. 版本历史

| 版本 | 日期 | 变化 |
|---|---|---|
| v0.1 | 2026-06-13 | 初稿 |
| v0.2 | 2026-06-13 | 平台 profile 化, 双格式审计, 真实 Capsule 端到端验证 |
| v0.2.1 | 2026-06-13 | 用户级, Rscript 修 bug |
| v0.3 | 2026-06-14 | R 持久 REPL, 全量提取, GSEAlens \|**|NES| enrichment direction framework**| 框架, 多组织 crosstalk, subagent 并行 |
| v0.3.1 | 2026-06-14 | 全 collection 深度解读 (Hallmark+GO:BP+Reactome+KEGG), 跨对比组联合分析, G4/G5 门控 |
| v0.3.2 | 2026-06-14 | NES 语义修复 (G6: 禁止"NEG=抑制"), Discussion 模块 (S7), Follow-up 探索 (S10) |
| **v0.4** | **2026-06-14** | **并行深度讨论 (S7b)**: 5 主题并行 subagent 架构, leading edge 基因解析, C2 先验基因集涌现分析, 跨主题整合 master discussion, G7/G8 门控, S1 新增 Q6 讨论偏好 |
| **v0.5** | **2026-06-14** | **NES 反转精确分类**: 真反转 (Mirror Flip) / P 压制 (P-Suppression) / P 重启 (P-Restoration) / RTP 独有 / 跨对比组"轴"概念; **author_background_template.md** 结构化作者背景采集; 修正 v0.4 中"RTP_vs_RT NES<0 即富集回 Model 方向"的错误; 强制代码 `classify_flip_mode()` 与中文表述规范 |
| **v0.5.1** | **2026-06-15** | **MSigDB 本地知识库集成 (§3a)**: 35361 基因集元数据本地查询 (BRIEF/FULL/PMID/GEOID/AUTHORS), 强制 `get_geneset_brief` 解读规则, CGP 基因集 PMID 追溯 |
| **v0.5.2** | **2026-06-15** | **MSigDB MCP 强绑定涌现发现 (§3a)**: 8 阶段强制调用表 (S2/S5/S6/S6b/S7/S7b/S10), 涌现发现 SOP (EXTRACT→CLUSTER→SYNTHESIZE→HYPOTHESIZE 四步法), KEGG 名称误导专项防御; **文献验证规则 (§3b)**: bioRxiv/medRxiv 工具全面禁用 (HARD BLOCK), deepxiv/research-tools 强制验证, G 门控覆盖所有 PMID 引用 |
| **v0.5.3** | **2026-06-15** | **Leading edge CPM 强度加权 + ORA-overlap (§5b)**: 4 步加权流程, BIS (Biological Intensity Score = \|logFC\| × log2(max_mean_count+1)), 双重过滤生成 trusted_le, S6/S6b/S7b/S10 强制使用, G9 门控; **论文级可视化排版规范 (§6d)**: 5 张主 figure 模板 (Fig1 质控/Fig2 DE/Fig3 GSEA/Fig4 leading edge+涌现/Fig5 机制模型), supplementary 清单, G10 门控, Discussion 引用模板, Figure→§6d 衔接清单 |
| **v0.5.4** | **2026-06-15** | **多对比组 GSEA 串联热图 (§5c)**: 通路 × 对比组 NES 矩阵 + Ward.D2 聚类 + 显著性星号叠加 + 4 步涌现归纳 (All-Positive/All-Negative/Flip/Mixed/A-only/B-only 等模式) + G11 门控; **BulkRNA-seq 知识库扩展 (§5d)**: clusterProfiler/GSVA/decoupleR/VIPER/AUCell/fgsea/rrvgo/ComplexHeatmap 工具盘点, 与 gsealens-explorer 关系标注, Roadmap; **§5b 降为 OPTIONAL 并行** (G9 修订); **§6d 重组**: 移除 Fig1 质控/Fig2 DE (上游范围), 保留 Fig3 GSEA dot+enrichment, 新增 Fig4 cascade heatmap (核心), Fig5 leading edge+ORA-overlap, Fig6 机制模型 |
| **v0.5.5** | **2026-06-16** | **rds_path 路径参数化与用户驱动 (§1.0 + S0.1)**: 新增 §1.0 "获取 RDS 路径" 段落, 显式询问用户 (5 种来源), 禁用所有硬编码路径, session$rds_path 持久化, file.exists() 验证, 多文件场景一次性收集; S0 拆分为 S0.1 (询问) / S0.2 (启动 R + readRDS) / S0.3 (验证 RDS 完整性); 移除 SKILL.md §1 中的 ZYH 硬编码示例; agent.md 增加 S0.1 启动第一动作 MANDATORY 规则
| **v0.5.5 (2026-06-16 第 2 次增量)** | **全量 subcollection 覆盖规则 (§5e)**: 强制覆盖 RDS 中全部 subcollection (本研究 26 个), 禁止只覆盖 H/C5/C2:REACTOME/C2:KEGG 4 类; LLM 上下文足够大, 必须全量, 不要 top-N, 拆分 subagent 并行; **Medium 阈值模块 (§2.7)**: 默认不纳入 |FDR∈[0.05, 0.25) ∩ |NES|∈[1.0, 1.5)| 通路, 仅在用户显式提及"不显著/边缘显著/中等置信/medium threshold"或指定关键词时纳入; evidence/medium/ 目录保留 Medium CSV 作为备用资产; **Agent 能力清单 (§4.5)**: 主 Agent 10 项能力 + Subagent F1-F4 详细能力清单 (输入/聚类规则/MSigDB BRIEF 数/涌现假说数/输出文件); Subagent Prompt 模板强制规范 (全量纳入, 不 top-N, ≥15 BRIEF, bioRxiv 禁用); Subagent 启动时机 (S4 后立即 F1-F4, S6 后 A-E, S7b F5 可选, S7 末 Master); Subagent 失败回退策略 (4 类); **G 门控新增 G13 (MANDATORY) + G14 (OPTIONAL)**: G13 验证 subcollection 覆盖率 = 100%, G14 验证 Medium 阈值按需触发; **教训 (来源: 真实 gsealens Capsule, 2026-06-16)**: 分析中, 上一版 v0.5.4 漏过 17 个 subcollection (CGP 463, WikiPathways 175, GO:CC/MF 146+113, HPO 210, IMMUNESIGDB 493, VAX 33, KEGG_MEDICUS 55, BIOCARTA 33, PID 62, 3CA 46, CGN 70, CM 66, TFT 39, MIR 16 通路) — 用户要求"全量分析, LLM 不要 top-N"; **涌现假说示例 (F1-F4)**: PSC-SASP 假说 (F1), 四波响应失衡 (F1), Complex I 全亚基塌缩 (F3), 衰老特异 EMT_3 + Treg 主导免疫豁免 (F4) |

## 11. 教训与改进 (v0.5.5 新增)

### 11.1 v0.5.4 漏过 17 个 subcollection (教训来源: 真实 gsealens Capsule)

| 漏过 subcollection | 显著通路数 (AduCer_vs_Con) | 主题 |
|---|---|---|
| C2:CGP | 463 | F1 (本应解读, v0.5.5 修复) |
| C2:CP:WIKIPATHWAYS | 175 | F2 (本应解读, v0.5.5 修复) |
| C5:GO:CC | 146 | F3 (本应解读, v0.5.5 修复) |
| C5:GO:MF | 113 | F3 (本应解读, v0.5.5 修复) |
| C5:HPO | 210 | F3 (本应解读, v0.5.5 修复) |
| C7:IMMUNESIGDB | 493 (主题 D 仅 34) | F4 (本应解读, v0.5.5 修复) |
| C7:VAX | 33 | F4 (本应解读, v0.5.5 修复) |
| C2:CP:KEGG_MEDICUS | 55 | F2 (本应解读, v0.5.5 修复) |
| C2:CP:BIOCARTA / PID | 33/62 | F2 (本应解读, v0.5.5 修复) |
| C4:3CA/CGN/CM | 46/70/66 | F4 (本应解读, v0.5.5 修复) |
| C3:TFT/MIR | 10+29+12+4 | (F5 备选) |
| **合计漏过** | **~2200 通路** | — |

### 11.2 v0.5.5 修复

1. **S4 阶段强制 (§5e)**: 26 个 subcollection 全部独立 CSV 输出
2. **S7b 阶段并行 subagent**: F1 (CGP), F2 (路径数据库), F3 (GO:CC/MF+HPO), F4 (免疫癌症扰动)
3. **G13 门控**: 启动时自动检查覆盖率
4. **教训写入 SKILL v0.5.5 §10 + §11**

### 11.3 Medium 阈值模块 (§2.7 教训)

- evidence/medium/ 目录保存 `{contrast}_Medium.csv` 备用
- 默认不纳入主分析 (用户没明确说就不要纳入)
- 触发关键词: "不显著", "边缘显著", "中等置信", "medium threshold", 或用户指定具体关键词
- 触发时调用 `extract_sig_medium()` 加入对应主题
- **教训**: 用户偏好主分析聚焦于 High 显著, Medium 阈值只在 follow-up (S10) 或显式触发时启用

### 11.4 Agent 拆分原则 (F1-F6)

| Subagent | 输入 subcollection | 通路数 | 启动时机 |
|---|---|---|---|
| F1 | CGP | 740 | S4 后立即 |
| F2 | KEGG_MEDICUS + WikiPathways + BIOCARTA + PID | 350 | S4 后立即 |
| F3 | GO:CC + GO:MF + HPO | 870 | S4 后立即 |
| F4 | IMMUNESIGDB + VAX + 3CA + CGN + CM | 2400 | S4 后立即 |
| F5 (可选) | TFT + MIR | 60 | S7b |
| Master | 全部主题子报告 | — | S7 末 |

### 11.5 全局 SKILL 同步原则 (新)

> **SKILL 更新必须同步到 2 个位置**:
> 1. **内联 SKILL.md** (`<your_skills_dir>/gsealens-explorer/SKILL.md`) — Agent 实际读取源
> 2. **项目本地 SKILL_vX.Y.Z.md** (`{out_dir}/SKILL_vX.Y.Z.md`) — 本项目参考
>
> 两者必须保持一致。如果只在一个位置更新, 下次调用 Agent 会读取过时的 SKILL。 |
