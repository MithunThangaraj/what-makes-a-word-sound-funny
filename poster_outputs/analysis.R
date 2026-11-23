###############################################################################
# What Makes a Word Sound Funny?
# Phonemes, Frequency and Humor Ratings with Cross-Validated XGBoost
#
# EL161 Machine Learning for Linguistics, University of Aizu
#
# Runs top to bottom in RStudio (Source) or from a terminal:
#   Rscript poster_outputs/analysis.R
#
# Input : ../Master.csv   (the project folder that contains poster_outputs/)
# Output: poster_outputs/  (PNG figures, results_table.csv, results.md, ...)
#
# Pipeline
#   1. Cleaning           5. Nested, repeated, stratified CV + tuning
#   2. Descriptives       6. Permutation baseline + Wilcoxon model comparison
#   3. Targets            7. SHAP interpretation (importance, stability, ...)
#   4. Feature sets       8. results.md (all numbers written by this script)
###############################################################################

t_start <- Sys.time()

# ---------------------------------------------------------------------------
# 0. Setup
# ---------------------------------------------------------------------------
msg <- function(...) message(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), ...)

pkgs <- c("tidyverse", "xgboost", "caret", "SHAPforxgboost", "pROC")
missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  msg("Installing missing packages: ", paste(missing_pkgs, collapse = ", "))
  install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
}
suppressPackageStartupMessages({
  library(tidyverse)
  library(xgboost)
  library(caret)
  library(SHAPforxgboost)
  library(pROC)
  library(parallel)
})

# Locate the project folder whether the script is sourced in RStudio or run
# with Rscript. The data file lives one level above poster_outputs/.
get_script_dir <- function() {
  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    p <- tryCatch(rstudioapi::getActiveDocumentContext()$path, error = function(e) "")
    if (nzchar(p)) return(dirname(normalizePath(p)))
  }
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a) > 0) return(dirname(normalizePath(sub("^--file=", "", a[1]))))
  getwd()
}
SCRIPT_DIR <- get_script_dir()
ROOT <- if (basename(SCRIPT_DIR) == "poster_outputs") dirname(SCRIPT_DIR) else SCRIPT_DIR
OUT  <- file.path(ROOT, "poster_outputs")
DATA <- file.path(ROOT, "Master.csv")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
if (!file.exists(DATA)) stop("Cannot find Master.csv at ", DATA)
msg("Project folder: ", ROOT)

# ---- Analysis settings -----------------------------------------------------
SEED        <- 123
K_OUTER     <- 10      # outer folds
REPEATS     <- 5       # outer repeats  -> 50 test folds per model
K_INNER     <- 3       # inner folds used only for tuning
GRID        <- expand.grid(max_depth = c(2, 4, 6), eta = c(0.05, 0.1))
MAX_ROUNDS  <- 1000    # upper bound; actual nrounds set by early stopping
EARLY_STOP  <- 30
N_PERM      <- 200     # (original models A and C)
# Label shuffles for the extension models (M, M+P, A+Pos, F). A full run with
# 200 here took 27.2 minutes (over the 25-minute budget), so 100 are used.
N_PERM_NEW  <- 100
N_RESID_PERM <- 100    # shuffles for the residual test (Extension 1)     # label shuffles for the permutation baseline
N_CORES     <- max(1, parallel::detectCores() - 1)
# Developer smoke test only: QUICK=1 Rscript analysis.R  (tiny settings)
if (Sys.getenv("QUICK") == "1") { REPEATS <- 1; N_PERM <- 2; N_PERM_NEW <- 2; N_RESID_PERM <- 2; GRID <- GRID[1:2, ]; MAX_ROUNDS <- 100 }
BASE_PARAMS <- list(objective = "binary:logistic", eval_metric = "auc",
                    subsample = 0.8, colsample_bytree = 0.8,
                    min_child_weight = 1, nthread = 1)

# Plot style: large fonts for an A0 poster
BASE_SIZE <- 22
theme_poster <- theme_minimal(base_size = BASE_SIZE) +
  theme(plot.title = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        plot.background = element_rect(fill = "white", colour = NA),
        legend.position = "bottom")
save_fig <- function(p, name, w = 10, h = 7) {
  ggsave(file.path(OUT, name), p, width = w, height = h, dpi = 300, bg = "white")
  msg("  saved ", name)
}
COL_FUNNY   <- "#D55E00"   # Okabe-Ito vermillion
COL_UNFUNNY <- "#0072B2"   # Okabe-Ito blue
COL_MODELS  <- c(A = "#56B4E9", B = "#009E73", C = "#E69F00")

PH <- c("AH","EY","T","AA","EH","AE","AY","IY","ER","AO","AW","OW","B","S","K",
        "CH","SH","HH","Z","D","JH","IH","Y","OY","F","G","ZH","N","M","R","W",
        "UW","L","P","TH","DH","UH","V","NG")
D_PH <- paste0("d_", PH)

# Readable feature names for figures
nice_label <- function(x) {
  x <- sub("^d_", "", x)
  x <- recode(x, Average_Surprisal = "Surprisal", Winter_Ico = "Iconicity",
              Phoneme_Length = "Length", log_freq = "log frequency",
              Valence_Glasgow = "Valence", Recog_Memory = "Recognition memory",
              Valence_Warr = "Valence", Arousal_Warr = "Arousal", Dominance_Warr = "Dominance",
              Conc_Brys = "Concreteness", pos_le_ending = "-le ending")
  x <- sub("^Emot_Assoc_", "NRC ", x)
  x <- sub("^pos_first_(.*)$", "first: \\1", x)
  x <- sub("^pos_last_(.*)$", "last: \\1", x)
  x <- sub("^pos_end_(.*)_(.*)$", "ending: \\1 \\2", x)
  x <- ifelse(grepl("^f_", x), gsub("_", " ", sub("^f_", "", x)), x)
  x
}
fmt  <- function(x, d = 3) formatC(x, format = "f", digits = d)
fmtp <- function(p) ifelse(p < 0.001, "< .001", sub("^0", "", formatC(p, format = "f", digits = 3)))
pfmt <- function(p) ifelse(p < 0.001, "p < .001", paste0("p = ", fmtp(p)))

# ---------------------------------------------------------------------------
# 1. Cleaning
# ---------------------------------------------------------------------------
msg("STEP 1: reading and cleaning Master.csv")
raw <- read_csv(DATA, na = c("", "NA", "#N/A"),
                col_types = cols(.default = col_character()), progress = FALSE)
n_raw <- nrow(raw)

# Row 41831 is a known bad row (header text such as "DPoS_Brys" sits in data
# columns). Drop it explicitly if it is still that row.
bad_row_dropped <- FALSE
if (n_raw >= 41831 && identical(raw$DPoS_Brys[41831], "DPoS_Brys")) {
  raw <- raw[-41831, ]
  bad_row_dropped <- TRUE
}

num <- function(x) suppressWarnings(as.numeric(x))
EMOT <- c("Emot_Assoc_Anger", "Emot_Assoc_Anticipation", "Emot_Assoc_Disgust", "Emot_Assoc_Fear",
          "Emot_Assoc_Joy", "Emot_Assoc_Negative", "Emot_Assoc_Positive", "Emot_Assoc_Sadness",
          "Emot_Assoc_Surprise", "Emot_Assoc_Trust")
MEANING_CANDIDATES <- c("Valence_Warr", "Arousal_Warr", "Dominance_Warr", "Conc_Brys", EMOT)
keep_cols <- c("Humor_Overall_Enge", "Phoneme_Length", "Average_Surprisal",
               "Winter_Ico", "frequency", "Valence_Glasgow", "Recog_Memory", PH,
               MEANING_CANDIDATES)
dat <- raw %>%
  select(Word, all_of(keep_cols)) %>%
  mutate(across(all_of(keep_cols), num)) %>%
  rename(humor = Humor_Overall_Enge)

n_humor <- sum(!is.na(dat$humor))
dat <- dat %>% filter(!is.na(humor))

# Proportions need a positive phoneme length; duplicated words are removed
n_before_len <- nrow(dat)
dat <- dat %>% filter(!is.na(Phoneme_Length), Phoneme_Length > 0,
                      if_all(all_of(PH), ~ !is.na(.x)))
n_bad_len <- n_before_len - nrow(dat)
# DATA FIX: the phoneme count columns were built by substring matching on the
# ARPABET string, so single-letter-ish symbols also count longer symbols that
# contain them (e.g. "go" = G OW has W = 1; "booty" has Y = 1 from IY; "bang"
# has G = 1 from NG). Subtracting the containing phonemes restores true counts:
# after the fix every row's counts sum exactly to Phoneme_Length.
len_match_before <- mean(rowSums(dat[PH]) == dat$Phoneme_Length)
dat <- dat %>% mutate(
  W = W - UW - OW - AW,
  Y = Y - IY - AY - EY - OY,
  R = R - ER,
  T = T - TH,
  D = D - DH,
  N = N - NG,
  G = G - NG,
  S = S - SH,
  Z = Z - ZH
)
len_match_after <- mean(rowSums(dat[PH]) == dat$Phoneme_Length)
n_negative <- sum(dat[PH] < 0)
if (n_negative > 0) stop("Phoneme count correction produced negative counts")
msg(sprintf("  phoneme counts summing to Phoneme_Length: %.1f%% before fix, %.1f%% after",
            100 * len_match_before, 100 * len_match_after))

n_dup <- sum(duplicated(dat$Word))
dat <- dat %>% distinct(Word, .keep_all = TRUE)

# CMUdict validation of the corrected counts. A random sample of 50 words
# (seed 123) is compared with CMUdict; every word is also checked. If any
# sampled word fails to match, counts are rebuilt from CMUdict (first
# pronunciation) for all words found in it.
CMU_FILE <- file.path(ROOT, "cmudict.dict")
cmu_ran <- file.exists(CMU_FILE)
cmu_rebuilt <- FALSE
if (cmu_ran) {
  msg("  validating phoneme counts against CMUdict")
  cm <- sub(" #.*$", "", readLines(CMU_FILE, warn = FALSE))
  cm_word <- sub("\\(\\d+\\)$", "", sub(" .*$", "", cm))
  cm_pron <- sub("^\\S+ ", "", cm)
  cm_index <- split(seq_along(cm_word), cm_word)
  cm_counts <- function(p) {
    t <- gsub("[0-9]", "", strsplit(p, " ")[[1]])
    vapply(PH, function(q) sum(t == q), numeric(1))
  }
  check_word <- function(i) {
    j <- cm_index[[tolower(dat$Word[i])]]
    if (is.null(j)) return("not in CMUdict")
    mine <- unlist(dat[i, PH])
    ok <- vapply(j, function(jj) all(cm_counts(cm_pron[jj]) == mine), logical(1))
    if (ok[1]) "match, first pronunciation" else if (any(ok)) "match, variant" else "mismatch"
  }
  cmu_status <- vapply(seq_len(nrow(dat)), check_word, character(1))
  set.seed(SEED)
  cmu_sample <- sample(nrow(dat), 50)
  cmu_sample_first <- sum(cmu_status[cmu_sample] == "match, first pronunciation")
  cmu_sample_any   <- sum(grepl("^match", cmu_status[cmu_sample]))
  cmu_full <- table(factor(cmu_status, c("match, first pronunciation", "match, variant",
                                         "mismatch", "not in CMUdict")))
  cmu_mismatch_words <- dat$Word[cmu_status == "mismatch"]
  msg(sprintf("  CMUdict check: %d/50 sampled words match exactly (%d/%d in full sample)",
              cmu_sample_first, sum(grepl("^match", cmu_status)), nrow(dat)))
  if (cmu_sample_any < 50) {
    msg("  sampled mismatch found: rebuilding phoneme counts from CMUdict")
    for (i in which(cmu_status != "not in CMUdict")) {
      cnt <- cm_counts(cm_pron[cm_index[[tolower(dat$Word[i])]][1]])
      dat[i, PH] <- as.list(cnt)
      dat$Phoneme_Length[i] <- sum(cnt)
    }
    cmu_rebuilt <- TRUE
  }
} else {
  msg("  cmudict.dict not found in the project folder; CMUdict check skipped")
}

# Phoneme counts -> proportions; log frequency
dat <- dat %>%
  mutate(across(all_of(PH), ~ .x / Phoneme_Length, .names = "d_{.col}"),
         log_freq = log10(frequency + 1))
n_clean <- nrow(dat)
len_mismatch <- sum(rowSums(dat[PH]) != dat$Phoneme_Length)
msg(sprintf("  raw rows %d, with humor rating %d, final cleaned N = %d",
            n_raw, n_humor, n_clean))

# ---------------------------------------------------------------------------
# 1b. Extension features
# ---------------------------------------------------------------------------
msg("STEP 1b: extension features (meaning, position, phonological features)")

# ---- Extension 1: meaning features, coverage among rated words ---------------
# Columns with at least 90% coverage enter the main meaning set. Columns below
# that threshold are used only in a sensitivity analysis, because requiring
# them would shrink the sample.
COVERAGE_MIN <- 90
meaning_cov <- tibble(column = c(MEANING_CANDIDATES, "Valence_Glasgow")) %>%
  mutate(n = map_int(column, ~ sum(!is.na(dat[[.x]]))), pct = 100 * n / n_clean,
         used = case_when(column == "Valence_Glasgow" ~ "not used (Glasgow norms, low coverage)",
                          pct >= COVERAGE_MIN ~ "main meaning set",
                          TRUE ~ "sensitivity analysis only (coverage below 90%)"))
MEANING     <- meaning_cov$column[meaning_cov$used == "main meaning set"]
MEANING_LOW <- meaning_cov$column[grepl("^sensitivity", meaning_cov$used)]
msg("  main meaning set: ", paste(MEANING, collapse = ", "))

# ---- Extension 2: position features from CMUdict ------------------------------
# First pronunciation, stress digits removed, whole-token matching.
if (!cmu_ran) stop("Extension 2 needs cmudict.dict in the project folder")
CONSONANTS <- c("B","P","D","T","G","K","CH","JH","F","V","TH","DH","S","Z","SH","ZH",
                "HH","M","N","NG","L","R","W","Y")
pron_tokens <- lapply(tolower(dat$Word), function(w) {
  j <- cm_index[[w]]
  if (is.null(j)) character(0) else gsub("[0-9]", "", strsplit(cm_pron[j[1]], " ")[[1]])
})
n_no_pron <- sum(lengths(pron_tokens) == 0)
first_ph <- vapply(pron_tokens, function(t) if (length(t)) t[1] else NA_character_, "")
last_ph  <- vapply(pron_tokens, function(t) if (length(t)) t[length(t)] else NA_character_, "")
end2     <- vapply(pron_tokens, function(t) if (length(t) >= 2) paste(tail(t, 2), collapse = "_") else NA_character_, "")
# Syllabic "-le": consonant + AH L at the end (gaggle, waddle, tinkle)
le_end <- vapply(pron_tokens, function(t) {
  n <- length(t); n >= 3 && t[n - 1] == "AH" && t[n] == "L" && t[n - 2] %in% CONSONANTS
}, logical(1))

MIN_POS_WORDS <- 10   # one-hot columns for phonemes that start/end at least 10 words
MIN_END_WORDS <- 50   # two-phoneme endings used as extra flags
first_keep <- names(which(table(first_ph) >= MIN_POS_WORDS))
last_keep  <- names(which(table(last_ph) >= MIN_POS_WORDS))
end2_keep  <- setdiff(names(which(table(end2) >= MIN_END_WORDS)), "AH_L")  # AH_L ~ the -le flag
for (p in first_keep) dat[[paste0("pos_first_", p)]] <- as.numeric(first_ph == p & !is.na(first_ph))
for (p in last_keep)  dat[[paste0("pos_last_", p)]]  <- as.numeric(last_ph == p & !is.na(last_ph))
for (e in end2_keep)  dat[[paste0("pos_end_", e)]]   <- as.numeric(end2 == e & !is.na(end2))
dat$pos_le_ending <- as.numeric(le_end)
POS_FEATS <- grep("^pos_", names(dat), value = TRUE)
msg(sprintf("  position features: %d (first %d, last %d, two-phoneme endings %d, -le flag)",
            length(POS_FEATS), length(first_keep), length(last_keep), length(end2_keep)))

# Descriptive check: -le ending vs other words
le_t <- t.test(dat$humor[le_end], dat$humor[!le_end])
le_sd_pooled <- sqrt(((sum(le_end) - 1) * var(dat$humor[le_end]) +
                        (sum(!le_end) - 1) * var(dat$humor[!le_end])) / (nrow(dat) - 2))
le_d <- (mean(dat$humor[le_end]) - mean(dat$humor[!le_end])) / le_sd_pooled
set.seed(SEED)
le_examples <- dat %>% filter(le_end) %>% slice_sample(n = 10) %>% arrange(desc(humor)) %>%
  transmute(x = paste0(Word, " (", fmt(humor, 2), ")")) %>% pull(x)
le_summary <- tibble(group = c("-le ending", "other words"), n = c(sum(le_end), sum(!le_end)),
                     mean = c(mean(dat$humor[le_end]), mean(dat$humor[!le_end])),
                     sd = c(sd(dat$humor[le_end]), sd(dat$humor[!le_end])))
# The phonological rule also catches -al / -el spellings (oral, social, dental).
# Descriptive split by spelling inside the -le group:
le_spelled <- le_end & grepl("le$", tolower(dat$Word))
le_other_sp <- le_end & !le_spelled
le_sp_t <- t.test(dat$humor[le_spelled], dat$humor[!le_end])
le_sp_d <- (mean(dat$humor[le_spelled]) - mean(dat$humor[!le_end])) /
  sqrt(((sum(le_spelled) - 1) * var(dat$humor[le_spelled]) + (sum(!le_end) - 1) * var(dat$humor[!le_end])) /
         (sum(le_spelled) + sum(!le_end) - 2))
le_spell_summary <- tibble(group = c("-le spelling (e.g. gaggle)", "other spellings (e.g. social)"),
                           n = c(sum(le_spelled), sum(le_other_sp)),
                           mean = c(mean(dat$humor[le_spelled]), mean(dat$humor[le_other_sp])),
                           sd = c(sd(dat$humor[le_spelled]), sd(dat$humor[le_other_sp])))

# ---- Extension 3: phonological feature mapping ---------------------------------
# Consonants: voicing, manner, place. Vowels: height, backness, rounding, diphthong.
# Diphthongs are classified by their first element. Labiodentals (F, V) and the
# labial-velar glide W are coded labial; the palatal glide Y is grouped with
# postalveolar (the place list has no separate palatal class); R is coded alveolar.
PHON_MAP <- tribble(
  ~phoneme, ~type,       ~voicing,    ~manner,      ~place,         ~height, ~backness, ~rounded, ~diphthong,
  "B",  "consonant", "voiced",    "stop",       "labial",       NA, NA, NA, NA,
  "P",  "consonant", "voiceless", "stop",       "labial",       NA, NA, NA, NA,
  "D",  "consonant", "voiced",    "stop",       "alveolar",     NA, NA, NA, NA,
  "T",  "consonant", "voiceless", "stop",       "alveolar",     NA, NA, NA, NA,
  "G",  "consonant", "voiced",    "stop",       "velar",        NA, NA, NA, NA,
  "K",  "consonant", "voiceless", "stop",       "velar",        NA, NA, NA, NA,
  "CH", "consonant", "voiceless", "affricate",  "postalveolar", NA, NA, NA, NA,
  "JH", "consonant", "voiced",    "affricate",  "postalveolar", NA, NA, NA, NA,
  "F",  "consonant", "voiceless", "fricative",  "labial",       NA, NA, NA, NA,
  "V",  "consonant", "voiced",    "fricative",  "labial",       NA, NA, NA, NA,
  "TH", "consonant", "voiceless", "fricative",  "dental",       NA, NA, NA, NA,
  "DH", "consonant", "voiced",    "fricative",  "dental",       NA, NA, NA, NA,
  "S",  "consonant", "voiceless", "fricative",  "alveolar",     NA, NA, NA, NA,
  "Z",  "consonant", "voiced",    "fricative",  "alveolar",     NA, NA, NA, NA,
  "SH", "consonant", "voiceless", "fricative",  "postalveolar", NA, NA, NA, NA,
  "ZH", "consonant", "voiced",    "fricative",  "postalveolar", NA, NA, NA, NA,
  "HH", "consonant", "voiceless", "fricative",  "glottal",      NA, NA, NA, NA,
  "M",  "consonant", "voiced",    "nasal",      "labial",       NA, NA, NA, NA,
  "N",  "consonant", "voiced",    "nasal",      "alveolar",     NA, NA, NA, NA,
  "NG", "consonant", "voiced",    "nasal",      "velar",        NA, NA, NA, NA,
  "L",  "consonant", "voiced",    "liquid",     "alveolar",     NA, NA, NA, NA,
  "R",  "consonant", "voiced",    "liquid",     "alveolar",     NA, NA, NA, NA,
  "W",  "consonant", "voiced",    "glide",      "labial",       NA, NA, NA, NA,
  "Y",  "consonant", "voiced",    "glide",      "postalveolar", NA, NA, NA, NA,
  "IY", "vowel", NA, NA, NA, "high", "front",   "unrounded", "monophthong",
  "IH", "vowel", NA, NA, NA, "high", "front",   "unrounded", "monophthong",
  "EY", "vowel", NA, NA, NA, "mid",  "front",   "unrounded", "diphthong",
  "EH", "vowel", NA, NA, NA, "mid",  "front",   "unrounded", "monophthong",
  "AE", "vowel", NA, NA, NA, "low",  "front",   "unrounded", "monophthong",
  "AH", "vowel", NA, NA, NA, "mid",  "central", "unrounded", "monophthong",
  "ER", "vowel", NA, NA, NA, "mid",  "central", "unrounded", "monophthong",
  "AA", "vowel", NA, NA, NA, "low",  "back",    "unrounded", "monophthong",
  "AO", "vowel", NA, NA, NA, "mid",  "back",    "rounded",   "monophthong",
  "UW", "vowel", NA, NA, NA, "high", "back",    "rounded",   "monophthong",
  "UH", "vowel", NA, NA, NA, "high", "back",    "rounded",   "monophthong",
  "OW", "vowel", NA, NA, NA, "mid",  "back",    "rounded",   "diphthong",
  "AW", "vowel", NA, NA, NA, "low",  "central", "unrounded", "diphthong",
  "AY", "vowel", NA, NA, NA, "low",  "central", "unrounded", "diphthong",
  "OY", "vowel", NA, NA, NA, "mid",  "back",    "rounded",   "diphthong"
)
stopifnot(setequal(PHON_MAP$phoneme, PH))
pm <- PHON_MAP[match(PH, PHON_MAP$phoneme), ]
is_ <- function(col, val) as.numeric(!is.na(pm[[col]]) & pm[[col]] == val)
FEATMAT <- cbind(
  f_vowel = as.numeric(pm$type == "vowel"),
  f_voiced = is_("voicing", "voiced"), f_voiceless = is_("voicing", "voiceless"),
  f_stop = is_("manner", "stop"), f_fricative = is_("manner", "fricative"),
  f_affricate = is_("manner", "affricate"), f_nasal = is_("manner", "nasal"),
  f_liquid = is_("manner", "liquid"), f_glide = is_("manner", "glide"),
  f_labial = is_("place", "labial"), f_dental = is_("place", "dental"),
  f_alveolar = is_("place", "alveolar"), f_postalveolar = is_("place", "postalveolar"),
  f_velar = is_("place", "velar"), f_glottal = is_("place", "glottal"),
  f_voiced_stop = is_("voicing", "voiced") * is_("manner", "stop"),
  f_voiceless_stop = is_("voicing", "voiceless") * is_("manner", "stop"),
  f_voiced_fricative = is_("voicing", "voiced") * is_("manner", "fricative"),
  f_voiceless_fricative = is_("voicing", "voiceless") * is_("manner", "fricative"),
  f_high = is_("height", "high"), f_mid = is_("height", "mid"), f_low = is_("height", "low"),
  f_front = is_("backness", "front"), f_central = is_("backness", "central"),
  f_back = is_("backness", "back"), f_rounded = is_("rounded", "rounded"),
  f_diphthong = is_("diphthong", "diphthong")
)
F_FEATS <- colnames(FEATMAT)
fprop <- (as.matrix(dat[PH]) %*% FEATMAT) / dat$Phoneme_Length
dat <- bind_cols(dat, as_tibble(fprop))
msg(sprintf("  phonological features: %d", length(F_FEATS)))

# ---------------------------------------------------------------------------
# 2. Descriptives
# ---------------------------------------------------------------------------
msg("STEP 2: descriptives")
humor_median <- median(dat$humor)
humor_desc <- dat %>% summarise(n = n(), mean = mean(humor), sd = sd(humor),
                                median = median(humor), min = min(humor), max = max(humor))

p_hist <- ggplot(dat, aes(humor)) +
  geom_histogram(binwidth = 0.1, fill = "grey55", colour = "white", boundary = 1) +
  geom_vline(xintercept = humor_median, linetype = "dashed", linewidth = 1.2) +
  annotate("label", x = humor_median, y = Inf, vjust = 1.3, hjust = -0.05,
           label = paste0("median = ", fmt(humor_median, 2)), size = 7) +
  labs(title = "Humor ratings (Engelthaler & Hills, 2018)",
       subtitle = paste0("N = ", format(n_clean, big.mark = ","), " English words"),
       x = "Mean humor rating (1-5)", y = "Number of words") +
  theme_poster
save_fig(p_hist, "fig01_humor_histogram.png")

cor_row <- function(x, y, name) {
  ok <- complete.cases(x, y)
  ct <- cor.test(x[ok], y[ok])
  tibble(variable = name, r = unname(ct$estimate), ci_low = ct$conf.int[1],
         ci_high = ct$conf.int[2], p = ct$p.value, n = sum(ok))
}
pred_vars <- c("Phoneme_Length", "Average_Surprisal", "Winter_Ico", "log_freq",
               "Valence_Glasgow", "Recog_Memory")
pred_cor <- map_dfr(pred_vars, ~ cor_row(dat[[.x]], dat$humor, .x))
write_csv(pred_cor, file.path(OUT, "predictor_correlations.csv"))

p_predcor <- pred_cor %>%
  mutate(label = fct_reorder(nice_label(variable), r)) %>%
  ggplot(aes(r, label, fill = r > 0)) +
  geom_col(width = 0.7) +
  geom_errorbar(aes(xmin = ci_low, xmax = ci_high), width = 0.25, orientation = "y", linewidth = 0.9) +
  geom_vline(xintercept = 0) +
  scale_fill_manual(values = c(`TRUE` = COL_FUNNY, `FALSE` = COL_UNFUNNY), guide = "none") +
  labs(title = "Correlations with humor rating",
       subtitle = "Pearson r with 95% CI (pairwise complete cases)",
       x = "Pearson r", y = NULL) +
  theme_poster
save_fig(p_predcor, "fig02_predictor_correlations.png")

ph_cor <- map_dfr(D_PH, ~ cor_row(dat[[.x]], dat$humor, .x)) %>%
  mutate(p_fdr = p.adjust(p, "BH"), phoneme = sub("^d_", "", variable))
write_csv(ph_cor, file.path(OUT, "phoneme_correlations.csv"))

p_phcor <- ph_cor %>%
  mutate(phoneme = fct_reorder(phoneme, r),
         dir = ifelse(r > 0, "more funny", "less funny"),
         sig = ifelse(p_fdr < 0.05, "FDR q < .05", "n.s.")) %>%
  ggplot(aes(phoneme, r, fill = dir, alpha = sig)) +
  geom_col(width = 0.8) +
  geom_hline(yintercept = 0) +
  scale_fill_manual(values = c(`more funny` = COL_FUNNY, `less funny` = COL_UNFUNNY), name = NULL) +
  scale_alpha_manual(values = c(`FDR q < .05` = 1, `n.s.` = 0.35), name = NULL) +
  labs(title = "Phoneme proportion vs. humor rating",
       subtitle = "Pearson r per phoneme (proportion of word's phonemes)",
       x = NULL, y = "Pearson r") +
  theme_poster +
  theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1, size = 15))
save_fig(p_phcor, "fig03_phoneme_correlations.png")

# ---------------------------------------------------------------------------
# 3. Targets and 4. feature sets
# ---------------------------------------------------------------------------
msg("STEP 3-4: targets and feature sets")
q10 <- unname(quantile(dat$humor, 0.10))
q90 <- unname(quantile(dat$humor, 0.90))

FEATS <- list(
  A = D_PH,
  B = c(D_PH, "Average_Surprisal", "Winter_Ico", "Phoneme_Length"),
  C = c(D_PH, "Average_Surprisal", "Winter_Ico", "Phoneme_Length", "log_freq")
)
# Supplementary ablation: model C without surprisal (to test whether
# surprisal adds anything once frequency, iconicity and length are in)
FEATS$C_noSurp <- setdiff(FEATS$C, "Average_Surprisal")
MAIN_MODELS <- c("A", "B", "C")
ORIG_MODELS <- names(FEATS)

# ---- Extension models ----------------------------------------------------------
CONTROLS <- c("log_freq", "Winter_Ico", "Phoneme_Length", "Average_Surprisal")
FEATS$M      <- c(MEANING, CONTROLS)                  # meaning + controls, no phonemes
FEATS$MP     <- c(MEANING, CONTROLS, D_PH)            # M + phoneme proportions
FEATS$M_NRC  <- c(MEANING, MEANING_LOW, CONTROLS)     # sensitivity: + NRC emotions
FEATS$MP_NRC <- c(MEANING, MEANING_LOW, CONTROLS, D_PH)
FEATS$APos   <- c(D_PH, POS_FEATS)                    # A + position features
FEATS$F      <- F_FEATS                               # phonological features only
NEW_MODELS  <- c("M", "MP", "M_NRC", "MP_NRC", "APos", "F")
NEW_PERM_MODELS <- c("M", "MP", "APos", "F")
ALL_MODELS  <- c(ORIG_MODELS, NEW_MODELS)
MODEL_LABEL <- c(A = "A", B = "B", C = "C", C_noSurp = "C without surprisal", M = "M",
                 MP = "M+P", M_NRC = "M (+NRC)", MP_NRC = "M+P (+NRC)", APos = "A+Pos", F = "F")
# Which data sample each model uses ("" = main modelling sample)
SAMPLE_OF <- c(setNames(rep("", length(ORIG_MODELS)), ORIG_MODELS),
               M = "_M", MP = "_M", M_NRC = "_MN", MP_NRC = "_MN", APos = "", F = "")
SHAP_MODELS <- c("A", "C", "MP", "APos", "F")

# Same rows for every model: the intersection (complete cases on all features)
model_dat <- dat %>% filter(if_all(all_of(FEATS$C), ~ !is.na(.x)))
n_model <- nrow(model_dat)

TARGETS <- c("median", "extreme")
TASKDATA <- list(
  median  = model_dat %>% mutate(y = as.integer(humor > humor_median)),
  extreme = model_dat %>% filter(humor >= q90 | humor <= q10) %>%
    mutate(y = as.integer(humor >= q90))
)
TARGET_LABEL <- c(median = "Median split", extreme = "Extreme 10% vs 10%")
target_info <- imap_dfr(TASKDATA[TARGETS], ~ tibble(target = .y, n = nrow(.x),
                                            n_funny = sum(.x$y), n_unfunny = sum(1 - .x$y)))
msg(sprintf("  modelling N (intersection) = %d; median-split N = %d; extreme N = %d",
            n_model, nrow(TASKDATA$median), nrow(TASKDATA$extreme)))

# Outer folds: stratified 10-fold x 5 repeats, one set per target, shared by all models
set.seed(SEED)
FOLDS <- map(TASKDATA, ~ createMultiFolds(factor(.x$y), k = K_OUTER, times = REPEATS))

# Extension 1 samples: rated words with complete meaning features (and all
# controls). Targets use the same thresholds as the main analysis. Each sample
# gets its own stratified 10 x 5 folds (seed 123), shared by M and M+P.
make_targets <- function(df, suffix) {
  out <- list(df %>% mutate(y = as.integer(humor > humor_median)),
              df %>% filter(humor >= q90 | humor <= q10) %>% mutate(y = as.integer(humor >= q90)))
  setNames(out, paste0(TARGETS, suffix))
}
meaning_dat     <- dat %>% filter(if_all(all_of(FEATS$MP), ~ !is.na(.x)))
meaning_nrc_dat <- dat %>% filter(if_all(all_of(FEATS$MP_NRC), ~ !is.na(.x)))
n_meaning <- nrow(meaning_dat); n_meaning_nrc <- nrow(meaning_nrc_dat)
TASKDATA <- c(TASKDATA, make_targets(meaning_dat, "_M"), make_targets(meaning_nrc_dat, "_MN"))
for (key in setdiff(names(TASKDATA), names(FOLDS))) {
  set.seed(SEED)
  FOLDS[[key]] <- createMultiFolds(factor(TASKDATA[[key]]$y), k = K_OUTER, times = REPEATS)
}
msg(sprintf("  Extension 1 samples: meaning N = %d (with NRC emotions N = %d)", n_meaning, n_meaning_nrc))

# ---------------------------------------------------------------------------
# 5. Nested cross-validation
# ---------------------------------------------------------------------------
# One task = one (target, model, outer fold). Inside the outer TRAINING fold
# we run 3-fold stratified CV for every grid cell with early stopping, pick the
# cell with the best inner AUC, refit on the full training fold with that
# nrounds, and score the untouched outer TEST fold.

best_iter <- function(cv) {
  bi <- cv$best_iteration
  if (is.null(bi)) bi <- cv$early_stop$best_iteration
  if (is.null(bi)) bi <- which.max(cv$evaluation_log$test_auc_mean)
  as.integer(bi)
}

tune_and_fit <- function(X, y, tr, te, seed, grid) {
  set.seed(seed)
  inner <- caret::createFolds(factor(y[tr]), k = K_INNER)  # inner test indices
  dtr <- xgboost::xgb.DMatrix(X[tr, , drop = FALSE], label = y[tr])
  best <- NULL
  for (g in seq_len(nrow(grid))) {
    p <- c(BASE_PARAMS, list(max_depth = grid$max_depth[g], eta = grid$eta[g], seed = seed))
    cv <- xgboost::xgb.cv(params = p, data = dtr, nrounds = MAX_ROUNDS, folds = inner,
                          early_stopping_rounds = EARLY_STOP, verbose = 0, showsd = FALSE)
    bi <- best_iter(cv)
    auc <- cv$evaluation_log$test_auc_mean[bi]
    if (is.null(best) || auc > best$auc) best <- list(g = g, nrounds = bi, auc = auc)
  }
  p <- c(BASE_PARAMS, list(max_depth = grid$max_depth[best$g], eta = grid$eta[best$g], seed = seed))
  set.seed(seed)
  fit <- xgboost::xgb.train(params = p, data = dtr, nrounds = best$nrounds, verbose = 0)
  prob <- predict(fit, xgboost::xgb.DMatrix(X[te, , drop = FALSE]))
  list(fit = fit, prob = prob, max_depth = grid$max_depth[best$g],
       eta = grid$eta[best$g], nrounds = best$nrounds, inner_auc = best$auc)
}

# SHAP contributions for one test fold (SHAPforxgboost, with a direct fallback)
shap_matrix <- function(fit, Xte) {
  s <- tryCatch(as.matrix(SHAPforxgboost::shap.values(xgb_model = fit, X_train = Xte)$shap_score),
                error = function(e) NULL)
  if (is.null(s)) {
    s <- predict(fit, xgboost::xgb.DMatrix(Xte), predcontrib = TRUE)
    s <- s[, colnames(Xte), drop = FALSE]
  }
  colnames(s) <- colnames(Xte)
  s
}

fold_metrics <- function(y, prob) {
  pred <- as.integer(prob > 0.5)
  tp <- sum(pred == 1 & y == 1); fp <- sum(pred == 1 & y == 0)
  tn <- sum(pred == 0 & y == 0); fn <- sum(pred == 0 & y == 1)
  prec <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
  rec  <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
  f1   <- if (!is.na(prec) && !is.na(rec) && prec + rec > 0) 2 * prec * rec / (prec + rec) else NA_real_
  auc  <- as.numeric(pROC::auc(pROC::roc(y, prob, levels = c(0, 1), direction = "<", quiet = TRUE)))
  tibble(accuracy = (tp + tn) / length(y), auc = auc, precision = prec,
         recall = rec, f1 = f1, tp = tp, fp = fp, tn = tn, fn = fn)
}

run_task <- function(task) {
  dkey <- paste0(task$target, SAMPLE_OF[[task$model]])
  d  <- TASKDATA[[dkey]]
  X  <- as.matrix(d[, FEATS[[task$model]]])
  y  <- d$y
  tr <- FOLDS[[dkey]][[task$fold]]
  te <- setdiff(seq_len(nrow(d)), tr)
  r  <- tune_and_fit(X, y, tr, te, task$seed, GRID)
  shap <- if (task$model %in% SHAP_MODELS) shap_matrix(r$fit, X[te, , drop = FALSE]) else NULL
  list(target = task$target, model = task$model, fold = task$fold,
       metrics = bind_cols(tibble(target = task$target, model = task$model, fold = task$fold,
                                  max_depth = r$max_depth, eta = r$eta,
                                  nrounds = r$nrounds, inner_auc = r$inner_auc),
                           fold_metrics(y[te], r$prob)),
       te = te, shap = shap)
}

# Permutation task: labels shuffled, single stratified 10-fold CV, same nested tuning
run_perm_task <- function(task) {
  d <- TASKDATA[[paste0(task$target, SAMPLE_OF[[task$model]])]]
  X <- as.matrix(d[, FEATS[[task$model]]])
  set.seed(SEED + 1000 * task$perm)
  y <- sample(d$y)
  folds <- caret::createFolds(factor(y), k = K_OUTER)
  te <- folds[[task$k]]
  tr <- setdiff(seq_len(nrow(d)), te)
  r <- tune_and_fit(X, y, tr, te, task$seed, GRID)
  tibble(target = task$target, model = task$model, perm = task$perm, k = task$k,
         auc = as.numeric(pROC::auc(pROC::roc(y[te], r$prob, levels = c(0, 1),
                                               direction = "<", quiet = TRUE))))
}

# ---- Extension 1 residual test -------------------------------------------------
# Within each outer fold: (1) fit a linear model of the continuous humor rating
# on the M features using the TRAINING fold only; (2) residuals = rating minus
# that model's prediction, for train and test words; (3) XGBoost regression on
# phoneme proportions, tuned with the same nested grid, predicts the training
# residuals; (4) score R2 and correlation on the test-fold residuals.
BASE_PARAMS_REG <- list(objective = "reg:squarederror", eval_metric = "rmse",
                        subsample = 0.8, colsample_bytree = 0.8,
                        min_child_weight = 1, nthread = 1)
best_iter_reg <- function(cv) {
  bi <- cv$best_iteration
  if (is.null(bi)) bi <- cv$early_stop$best_iteration
  if (is.null(bi)) bi <- which.min(cv$evaluation_log$test_rmse_mean)
  as.integer(bi)
}
tune_and_fit_reg <- function(X, y, tr, te, seed, grid) {
  set.seed(seed)
  inner <- caret::createFolds(y[tr], k = K_INNER)
  dtr <- xgboost::xgb.DMatrix(X[tr, , drop = FALSE], label = y[tr])
  best <- NULL
  for (g in seq_len(nrow(grid))) {
    p <- c(BASE_PARAMS_REG, list(max_depth = grid$max_depth[g], eta = grid$eta[g], seed = seed))
    cv <- xgboost::xgb.cv(params = p, data = dtr, nrounds = MAX_ROUNDS, folds = inner,
                          early_stopping_rounds = EARLY_STOP, verbose = 0, showsd = FALSE)
    bi <- best_iter_reg(cv)
    rmse <- cv$evaluation_log$test_rmse_mean[bi]
    if (is.null(best) || rmse < best$rmse) best <- list(g = g, nrounds = bi, rmse = rmse)
  }
  p <- c(BASE_PARAMS_REG, list(max_depth = grid$max_depth[best$g], eta = grid$eta[best$g], seed = seed))
  set.seed(seed)
  fit <- xgboost::xgb.train(params = p, data = dtr, nrounds = best$nrounds, verbose = 0)
  list(pred = predict(fit, xgboost::xgb.DMatrix(X[te, , drop = FALSE])))
}
run_resid_task <- function(task) {
  d   <- TASKDATA[["median_M"]]
  Xph <- as.matrix(d[, D_PH])
  if (is.null(task$perm)) {
    tr <- FOLDS[["median_M"]][[task$fold]]
    te <- setdiff(seq_len(nrow(d)), tr)
  } else {
    # Null: phoneme rows shuffled relative to words, single stratified 10-fold CV
    set.seed(SEED + 7000 * task$perm)
    Xph <- Xph[sample(nrow(Xph)), , drop = FALSE]
    te <- caret::createFolds(factor(d$y), k = K_OUTER)[[task$k]]
    tr <- setdiff(seq_len(nrow(d)), te)
  }
  mdf <- as.data.frame(d[, FEATS$M]); mdf$humor <- d$humor
  lmfit <- lm(humor ~ ., data = mdf[tr, ])
  res <- d$humor - predict(lmfit, newdata = mdf)
  r <- tune_and_fit_reg(Xph, res, tr, te, task$seed, GRID)
  ss_tot <- sum((res[te] - mean(res[tr]))^2)
  tibble(fold = if (is.null(task$fold)) NA_character_ else task$fold,
         perm = if (is.null(task$perm)) NA_integer_ else task$perm,
         k = if (is.null(task$k)) NA_integer_ else task$k,
         r2 = 1 - sum((res[te] - r$pred)^2) / ss_tot,
         # a constant prediction carries no information: count it as r = 0
         cor = if (sd(r$pred) > 0) cor(res[te], r$pred) else 0,
         r2_meaning = 1 - sum((d$humor[te] - (d$humor[te] - res[te]))^2) /
           sum((d$humor[te] - mean(d$humor[tr]))^2))
}

# Parallel backend (PSOCK works in RStudio and Rscript on every OS)
msg(sprintf("STEP 5: nested CV (%d outer folds x %d models x 2 targets, %d grid cells x %d inner folds) on %d cores",
            K_OUTER * REPEATS, length(ALL_MODELS), nrow(GRID), K_INNER, N_CORES))
cl <- makeCluster(N_CORES)
invisible(clusterEvalQ(cl, suppressPackageStartupMessages({
  library(xgboost); library(caret); library(pROC); library(dplyr); library(tibble); library(SHAPforxgboost)
})))
clusterExport(cl, c("TASKDATA", "FEATS", "FOLDS", "GRID", "BASE_PARAMS", "MAX_ROUNDS",
                    "EARLY_STOP", "K_INNER", "K_OUTER", "SEED", "best_iter", "tune_and_fit",
                    "shap_matrix", "fold_metrics", "run_task", "run_perm_task",
                    "SAMPLE_OF", "SHAP_MODELS", "D_PH", "BASE_PARAMS_REG", "best_iter_reg",
                    "tune_and_fit_reg", "run_resid_task"))

tasks <- list(); i <- 0
for (tg in TARGETS) for (m in ORIG_MODELS) for (f in names(FOLDS[[tg]])) {
  i <- i + 1
  tasks[[i]] <- list(target = tg, model = m, fold = f, seed = SEED + i)
}
# Extension models appended with their own seed range, so the original
# models keep exactly the same seeds and results as before
j <- 0
for (tg in TARGETS) for (m in NEW_MODELS) for (f in names(FOLDS[[paste0(tg, SAMPLE_OF[[m]])]])) {
  i <- i + 1; j <- j + 1
  tasks[[i]] <- list(target = tg, model = m, fold = f, seed = SEED + 100000 + j)
}
t_cv <- Sys.time()
cv_out <- parLapplyLB(cl, tasks, run_task)
cv_minutes <- as.numeric(difftime(Sys.time(), t_cv, units = "mins"))
msg(sprintf("  nested CV finished in %.1f minutes", cv_minutes))

fold_res <- map_dfr(cv_out, "metrics") %>%
  mutate(target = factor(target, TARGETS), model = factor(model, ALL_MODELS))
write_csv(fold_res, file.path(OUT, "fold_level_metrics.csv"))

metric_names <- c("accuracy", "auc", "precision", "recall", "f1")
results_table <- fold_res %>%
  group_by(target, model) %>%
  summarise(n_folds = n(),
            across(all_of(metric_names),
                   list(mean = ~ mean(.x, na.rm = TRUE), sd = ~ sd(.x, na.rm = TRUE))),
            TP = sum(tp), FP = sum(fp), TN = sum(tn), FN = sum(fn),
            n = as.integer(sum(tp + fp + tn + fn) / REPEATS),
            n_funny = as.integer(sum(tp + fn) / REPEATS),
            n_unfunny = as.integer(sum(fp + tn) / REPEATS),
            .groups = "drop") %>%
  relocate(n, n_funny, n_unfunny, .after = model)

tuning_summary <- fold_res %>%
  count(target, model, max_depth, eta, name = "folds_selected") %>%
  group_by(target, model) %>% arrange(desc(folds_selected), .by_group = TRUE) %>% ungroup()
nrounds_summary <- fold_res %>% group_by(target, model) %>%
  summarise(nrounds_median = median(nrounds), nrounds_min = min(nrounds),
            nrounds_max = max(nrounds), .groups = "drop")
write_csv(tuning_summary, file.path(OUT, "tuning_summary.csv"))

# ---------------------------------------------------------------------------
# 6a. Permutation baseline
# ---------------------------------------------------------------------------
msg(sprintf("STEP 6: permutation baseline (%d shuffles for A, C; %d for M, M+P, A+Pos, F; 2 targets; 10-fold CV each)",
            N_PERM, N_PERM_NEW))
ptasks <- list(); i <- 0
for (tg in TARGETS) for (m in c("A", "C")) for (pp in seq_len(N_PERM)) for (k in seq_len(K_OUTER)) {
  i <- i + 1
  ptasks[[i]] <- list(target = tg, model = m, perm = pp, k = k, seed = 50000 + i)
}
j <- 0
for (tg in TARGETS) for (m in NEW_PERM_MODELS) for (pp in seq_len(N_PERM_NEW)) for (k in seq_len(K_OUTER)) {
  i <- i + 1; j <- j + 1
  ptasks[[i]] <- list(target = tg, model = m, perm = pp, k = k, seed = 300000 + j)
}
t_perm <- Sys.time()
perm_fold <- bind_rows(parLapplyLB(cl, ptasks, run_perm_task))
perm_minutes <- as.numeric(difftime(Sys.time(), t_perm, units = "mins"))
msg(sprintf("  permutation baseline finished in %.1f minutes", perm_minutes))
msg(sprintf("STEP 6c: residual test (50 folds + %d shuffles x 10 folds)", N_RESID_PERM))
t_resid <- Sys.time()
rtasks <- c(map(seq_along(FOLDS[["median_M"]]), ~ list(fold = names(FOLDS[["median_M"]])[.x], seed = 400000 + .x)),
            unlist(map(seq_len(N_RESID_PERM), function(pp) map(seq_len(K_OUTER), function(k)
              list(perm = pp, k = k, seed = 500000 + 100 * pp + k))), recursive = FALSE))
resid_out <- bind_rows(parLapplyLB(cl, rtasks, run_resid_task))
resid_minutes <- as.numeric(difftime(Sys.time(), t_resid, units = "mins"))
msg(sprintf("  residual test finished in %.1f minutes", resid_minutes))
stopCluster(cl)

perm_runs <- perm_fold %>% group_by(target, model, perm) %>%
  summarise(perm_auc = mean(auc), .groups = "drop")
write_csv(perm_runs, file.path(OUT, "permutation_auc.csv"))
perm_summary <- perm_runs %>%
  left_join(results_table %>% transmute(target = as.character(target),
                                        model = as.character(model), observed_auc = auc_mean),
            by = c("target", "model")) %>%
  group_by(target, model) %>%
  summarise(observed_auc = first(observed_auc), perm_mean = mean(perm_auc),
            perm_sd = sd(perm_auc), perm_max = max(perm_auc),
            n_ge = sum(perm_auc >= observed_auc),
            p_empirical = (1 + n_ge) / (n() + 1), .groups = "drop")
chance_line <- perm_runs %>% filter(model %in% c("A", "C")) %>% group_by(target) %>%
  summarise(chance_auc = mean(perm_auc), chance_q95 = quantile(perm_auc, 0.95), .groups = "drop")

results_table <- results_table %>%
  left_join(perm_summary %>% transmute(target = factor(target, TARGETS),
                                       model = factor(model, ALL_MODELS),
                                       perm_auc_mean = perm_mean, perm_auc_sd = perm_sd,
                                       perm_p_empirical = p_empirical),
            by = c("target", "model"))
write_csv(results_table, file.path(OUT, "results_table.csv"))

# ---------------------------------------------------------------------------
# 6b. Paired Wilcoxon tests on fold-level AUC (same folds for all models)
# ---------------------------------------------------------------------------
wilcox_pair <- function(tg, m1, m2) {
  a <- fold_res %>% filter(target == tg, model == m1) %>% arrange(fold)
  b <- fold_res %>% filter(target == tg, model == m2) %>% arrange(fold)
  stopifnot(identical(a$fold, b$fold))
  wt <- suppressWarnings(wilcox.test(b$auc, a$auc, paired = TRUE, exact = FALSE))
  tibble(target = tg, comparison = paste(m2, "vs", m1),
         mean_diff = mean(b$auc - a$auc), median_diff = median(b$auc - a$auc),
         folds_better = sum(b$auc > a$auc), n_folds = nrow(a),
         V = unname(wt$statistic), p = wt$p.value)
}
wilcox_res <- bind_rows(
  map_dfr(TARGETS, ~ wilcox_pair(.x, "A", "B")),
  map_dfr(TARGETS, ~ wilcox_pair(.x, "B", "C")),
  map_dfr(TARGETS, ~ wilcox_pair(.x, "C_noSurp", "C")),
  # Extensions (each pair shares the same folds)
  map_dfr(TARGETS, ~ wilcox_pair(.x, "M", "MP")),
  map_dfr(TARGETS, ~ wilcox_pair(.x, "M_NRC", "MP_NRC")),
  map_dfr(TARGETS, ~ wilcox_pair(.x, "A", "APos")),
  map_dfr(TARGETS, ~ wilcox_pair(.x, "A", "F"))
)
write_csv(wilcox_res, file.path(OUT, "wilcoxon_tests.csv"))

# ---- Model comparison figure ------------------------------------------------
cmp_dat <- results_table %>% filter(model %in% MAIN_MODELS) %>%
  mutate(target_lab = factor(TARGET_LABEL[as.character(target)], TARGET_LABEL))
chance_dat <- chance_line %>% mutate(target_lab = factor(TARGET_LABEL[target], TARGET_LABEL))
p_cmp <- ggplot(cmp_dat, aes(model, auc_mean, fill = model)) +
  geom_col(width = 0.65) +
  geom_errorbar(aes(ymin = auc_mean - auc_sd, ymax = auc_mean + auc_sd), width = 0.2, linewidth = 1) +
  geom_text(aes(y = auc_mean + auc_sd + 0.03, label = fmt(auc_mean, 3)), size = 7) +
  geom_hline(data = chance_dat, aes(yintercept = chance_auc), linetype = "dashed", linewidth = 1.1) +
  geom_hline(data = chance_dat, aes(yintercept = chance_q95), linetype = "dotted", linewidth = 1.1) +
  facet_wrap(~ target_lab) +
  scale_fill_manual(values = COL_MODELS, guide = "none") +
  coord_cartesian(ylim = c(0.4, 1)) +
  labs(title = "Cross-validated AUC by model",
       subtitle = "Mean ± SD over 50 outer folds; dashed = permutation mean, dotted = permutation 95th pct",
       x = "A: phonemes   B: + surprisal, iconicity, length   C: + log frequency",
       y = "AUC") +
  theme_poster + theme(axis.title.x = element_text(size = 16),
                       plot.subtitle = element_text(size = 15))
save_fig(p_cmp, "fig04_model_comparison.png")

# ---- Pooled confusion matrix for the best model of each target --------------
best_models <- results_table %>% filter(model %in% MAIN_MODELS) %>%
  group_by(target) %>% slice_max(auc_mean, n = 1, with_ties = FALSE) %>% ungroup()
for (j in seq_len(nrow(best_models))) {
  bm <- best_models[j, ]
  cm <- tibble(Actual = c("Funny", "Funny", "Not funny", "Not funny"),
               Predicted = c("Funny", "Not funny", "Funny", "Not funny"),
               n = c(bm$TP, bm$FN, bm$FP, bm$TN)) %>%
    group_by(Actual) %>% mutate(row_pct = n / sum(n)) %>% ungroup() %>%
    mutate(Actual = factor(Actual, c("Not funny", "Funny")),
           Predicted = factor(Predicted, c("Not funny", "Funny")))
  p_cm <- ggplot(cm, aes(Predicted, Actual, fill = row_pct)) +
    geom_tile(colour = "white", linewidth = 2) +
    geom_text(aes(label = paste0(format(n, big.mark = ","), "\n(", fmt(100 * row_pct, 1), "%)"),
                  colour = row_pct > 0.5), size = 9) +
    scale_fill_gradient(low = "#F0F0F0", high = "#1F4E79", limits = c(0, 1), guide = "none") +
    scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "black"), guide = "none") +
    labs(title = paste0("Pooled confusion matrix: model ", bm$model),
         subtitle = paste0(TARGET_LABEL[as.character(bm$target)],
                           "; summed over 50 test folds (each word counted 5 times)"),
         x = "Predicted", y = "Actual") +
    theme_poster + theme(panel.grid = element_blank(), plot.subtitle = element_text(size = 16))
  save_fig(p_cm, paste0("fig05_confusion_", bm$target, "_model", bm$model, ".png"))
}

# ---------------------------------------------------------------------------
# 7. SHAP interpretation (models A and C, both targets)
# ---------------------------------------------------------------------------
msg("STEP 7: SHAP interpretation")
shap_runs <- keep(cv_out, ~ !is.null(.x$shap))

# Per-fold mean |SHAP| for every feature
fold_imp <- map_dfr(shap_runs, function(r)
  tibble(target = r$target, model = r$model, fold = r$fold,
         feature = colnames(r$shap), mean_abs = colMeans(abs(r$shap))))

shap_importance <- fold_imp %>% group_by(target, model, feature) %>%
  summarise(mean_abs_shap = mean(mean_abs), sd_abs_shap = sd(mean_abs), .groups = "drop") %>%
  group_by(target, model) %>% mutate(rank = rank(-mean_abs_shap, ties.method = "first")) %>%
  ungroup() %>% arrange(target, model, rank)

# Stability: % of the 50 folds in which a feature is in the fold's top 10
stability <- fold_imp %>% group_by(target, model, fold) %>%
  mutate(r = rank(-mean_abs, ties.method = "first")) %>% ungroup() %>%
  group_by(target, model, feature) %>%
  summarise(pct_top10 = 100 * mean(r <= 10), .groups = "drop")
shap_importance <- shap_importance %>% left_join(stability, by = c("target", "model", "feature"))
write_csv(shap_importance, file.path(OUT, "shap_importance.csv"))

# Word-level SHAP averaged over the 5 repeats (each word is tested once per repeat)
avg_shap <- function(tg, m) {
  rs <- keep(shap_runs, ~ .x$target == tg && .x$model == m)
  long <- map_dfr(rs, ~ as_tibble(.x$shap) %>% mutate(row = .x$te))
  long %>% group_by(row) %>% summarise(across(everything(), mean), .groups = "drop") %>% arrange(row)
}

feat_type <- function(f) case_when(f %in% D_PH ~ "Phoneme", f %in% c(MEANING, MEANING_LOW) ~ "Meaning",
                                    startsWith(f, "pos_") ~ "Position", startsWith(f, "f_") ~ "Phonological feature",
                                    TRUE ~ "Lexical control")
TYPE_COLS <- c(Phoneme = "#6A51A3", `Lexical control` = "#E69F00", Meaning = "#009E73",
               Position = "#CC79A7", `Phonological feature` = "#0072B2")
dir_info <- list()
for (tg in TARGETS) for (m in SHAP_MODELS) {
  tag <- paste0(m, "_", tg)
  full_figs <- m %in% c("A", "C")      # all four SHAP figures for the original models
  d   <- TASKDATA[[paste0(tg, SAMPLE_OF[[m]])]]
  S   <- avg_shap(tg, m)
  X   <- d[S$row, FEATS[[m]]]
  Smat <- S %>% select(all_of(FEATS[[m]]))

  # (i) importance bar chart, top 15
  imp15 <- shap_importance %>% filter(target == tg, model == m, rank <= 15) %>%
    mutate(lab = fct_reorder(nice_label(feature), mean_abs_shap), type = feat_type(feature))
  if (m == "F") {   # colour phonological features by direction (Spearman of value vs SHAP)
    imp15$type <- ifelse(vapply(as.character(imp15$feature), function(f)
      cor(X[[f]], Smat[[f]], method = "spearman"), numeric(1)) > 0, "toward funny", "toward not funny")
  }
  p_imp <- ggplot(imp15, aes(mean_abs_shap, lab, fill = type)) +
    geom_col(width = 0.75) +
    geom_errorbar(aes(xmin = pmax(0, mean_abs_shap - sd_abs_shap),
                      xmax = mean_abs_shap + sd_abs_shap), width = 0.3, orientation = "y") +
    scale_fill_manual(values = c(TYPE_COLS, `toward funny` = COL_FUNNY, `toward not funny` = COL_UNFUNNY), name = NULL) +
    labs(title = paste0("SHAP importance: model ", MODEL_LABEL[m]),
         subtitle = paste0(TARGET_LABEL[tg], "; mean |SHAP| ± SD over 50 test folds"),
         x = "Mean |SHAP| (log-odds)", y = NULL) +
    theme_poster
  save_fig(p_imp, paste0("fig06_shap_importance_", tag, ".png"))

  # (ii) beeswarm summary (SHAPforxgboost); extension models: median split only
  top_feats <- as.character(imp15$feature)
  if (full_figs || tg == "median") {
  p_bee <- tryCatch({
    lp <- SHAPforxgboost::shap.prep(shap_contrib = as.data.frame(Smat[, top_feats]),
                                    X_train = as.data.frame(X[, top_feats]))
    lp$variable <- factor(nice_label(as.character(lp$variable)),
                          levels = rev(nice_label(top_feats)))
    SHAPforxgboost::shap.plot.summary(lp, dilute = FALSE) +
      theme_poster + theme(legend.position = "bottom", legend.key.width = unit(2.5, "cm")) +
      labs(title = paste0("SHAP summary: model ", MODEL_LABEL[m]), subtitle = TARGET_LABEL[tg],
           y = "SHAP value (impact on log-odds of 'funny')", x = NULL)
  }, error = function(e) {
    msg("  shap.plot.summary failed (", conditionMessage(e), "); using ggplot fallback")
    lp <- map_dfr(top_feats, ~ tibble(feature = .x, shap = Smat[[.x]], value = X[[.x]]) %>%
                    mutate(std = (value - min(value)) / max(1e-12, diff(range(value)))))
    ggplot(lp, aes(shap, factor(nice_label(feature), rev(nice_label(top_feats))), colour = std)) +
      geom_jitter(height = 0.25, size = 0.8, alpha = 0.6) +
      scale_colour_gradient(low = "#FFCC33", high = "#6600CC", name = "Feature value") +
      labs(title = paste0("SHAP summary: model ", m), subtitle = TARGET_LABEL[tg],
           x = "SHAP value", y = NULL) + theme_poster
  })
  save_fig(p_bee, paste0("fig07_shap_beeswarm_", tag, ".png"))
  }

  if (full_figs) {
  # (iii) stability plot: features in the top 10 in at least one fold
  st <- shap_importance %>% filter(target == tg, model == m, pct_top10 > 0) %>%
    mutate(lab = fct_reorder(nice_label(feature), pct_top10), type = feat_type(feature))
  p_st <- ggplot(st, aes(pct_top10, lab, fill = type)) +
    geom_col(width = 0.75) +
    geom_vline(xintercept = c(50, 90), linetype = "dashed") +
    scale_fill_manual(values = c(Phoneme = "#6A51A3", `Lexical control` = "#E69F00"), name = NULL) +
    labs(title = paste0("Stability of SHAP ranking: model ", m),
         subtitle = paste0(TARGET_LABEL[tg], "; % of 50 folds in the top 10"),
         x = "% of folds in top 10", y = NULL) +
    theme_poster + theme(axis.text.y = element_text(size = 14))
  save_fig(p_st, paste0("fig08_stability_", tag, ".png"), h = 9)

  # (iv) dependence plots for the top 3 phonemes
  top3 <- shap_importance %>% filter(target == tg, model == m, feature %in% D_PH) %>%
    slice_min(rank, n = 3) %>% pull(feature)
  dep <- map_dfr(top3, ~ tibble(feature = nice_label(.x), value = X[[.x]], shap = Smat[[.x]])) %>%
    mutate(feature = factor(feature, nice_label(top3)))
  p_dep <- ggplot(dep, aes(value, shap)) +
    geom_hline(yintercept = 0, colour = "grey40") +
    geom_jitter(width = 0.004, height = 0, alpha = 0.35, size = 1.2, colour = "#6A51A3") +
    geom_smooth(method = "gam", formula = y ~ s(x, k = 4), se = FALSE, colour = "black", linewidth = 1.2) +
    facet_wrap(~ feature, scales = "free_x") +
    labs(title = paste0("SHAP dependence, top 3 phonemes: model ", m), subtitle = TARGET_LABEL[tg],
         x = "Proportion of the word's phonemes", y = "SHAP value") +
    theme_poster
  save_fig(p_dep, paste0("fig09_dependence_", tag, ".png"))
  }

  # (v) direction per phoneme: mean SHAP among words that contain it
  #     (also for position flags and phonological features; for continuous
  #     controls and meaning only the Spearman direction is meaningful)
  dir_info[[tag]] <- map_dfr(FEATS[[m]], function(f) {
    is_ph <- f %in% D_PH || startsWith(f, "pos_") || startsWith(f, "f_")
    has <- if (is_ph) X[[f]] > 0 else rep(TRUE, nrow(X))
    tibble(target = tg, model = m, feature = f, n_words_with = sum(has),
           mean_shap_with = if (is_ph) mean(Smat[[f]][has]) else NA_real_,
           spearman_value_shap = suppressWarnings(cor(X[[f]], Smat[[f]], method = "spearman")))
  })
}
direction <- bind_rows(dir_info)
write_csv(direction, file.path(OUT, "shap_direction.csv"))

# Funny-leaning and unfunny-leaning phonemes (model A, median split = the pure
# sound model on the full modelling sample), with example words
MIN_WORDS <- 30
dirA <- direction %>% filter(target == "median", model == "A", n_words_with >= MIN_WORDS) %>%
  left_join(shap_importance %>% filter(target == "median", model == "A") %>%
              select(feature, mean_abs_shap, rank), by = "feature")
funny_ph   <- dirA %>% filter(mean_shap_with > 0) %>% slice_max(mean_shap_with, n = 5)
unfunny_ph <- dirA %>% filter(mean_shap_with < 0) %>% slice_min(mean_shap_with, n = 5)
examples_for <- function(f, funny) {
  w <- model_dat %>% filter(.data[[f]] > 0)
  w <- if (funny) arrange(w, desc(humor)) else arrange(w, humor)
  w %>% slice_head(n = 8) %>% transmute(word = paste0(Word, " (", fmt(humor, 2), ")")) %>%
    pull(word) %>% paste(collapse = ", ")
}
example_tbl <- bind_rows(
  funny_ph %>% mutate(leaning = "funny", examples = map_chr(feature, examples_for, funny = TRUE)),
  unfunny_ph %>% mutate(leaning = "unfunny", examples = map_chr(feature, examples_for, funny = FALSE))
) %>% mutate(phoneme = sub("^d_", "", feature))
write_csv(example_tbl, file.path(OUT, "phoneme_examples.csv"))

# Surprisal in model C: rank, importance, stability, direction, ablation test
surp <- shap_importance %>% filter(model == "C", feature == "Average_Surprisal") %>%
  left_join(direction %>% filter(model == "C", feature == "Average_Surprisal") %>%
              select(target, spearman_value_shap), by = "target") %>%
  left_join(wilcox_res %>% filter(comparison == "C vs C_noSurp") %>%
              select(target, mean_diff, folds_better, n_folds, V, p), by = "target")
write_csv(surp, file.path(OUT, "surprisal_check.csv"))

# ---------------------------------------------------------------------------
# 7b. Extension summaries and figures
# ---------------------------------------------------------------------------
msg("STEP 7b: extension summaries and figures")
tl <- function(x) factor(TARGET_LABEL[as.character(x)], TARGET_LABEL)

# ---- Extension 1: sound vs meaning ---------------------------------------------
svm <- results_table %>% filter(model %in% c("M", "MP")) %>%
  mutate(target_lab = tl(target), model_lab = factor(MODEL_LABEL[as.character(model)], c("M", "M+P")))
svm_chance <- perm_runs %>% filter(model %in% c("M", "MP")) %>% group_by(target) %>%
  summarise(chance_auc = mean(perm_auc), .groups = "drop") %>% mutate(target_lab = tl(target))
svm_wil <- wilcox_res %>% filter(comparison == "MP vs M") %>%
  mutate(target_lab = tl(target),
         lab = paste0("M+P wins ", folds_better, "/", n_folds, " folds, ", pfmt(p)))
p_svm <- ggplot(svm, aes(model_lab, auc_mean, fill = model_lab)) +
  geom_col(width = 0.6) +
  geom_errorbar(aes(ymin = auc_mean - auc_sd, ymax = auc_mean + auc_sd), width = 0.2, linewidth = 1) +
  geom_text(aes(y = auc_mean + auc_sd + 0.03, label = fmt(auc_mean, 3)), size = 7) +
  geom_hline(data = svm_chance, aes(yintercept = chance_auc), linetype = "dashed", linewidth = 1.1) +
  geom_label(data = svm_wil, aes(x = 1.5, y = 0.43, label = lab), inherit.aes = FALSE, size = 5.5,
             fill = "white", linewidth = 0) +
  facet_wrap(~ target_lab) +
  scale_fill_manual(values = c(M = "#009E73", `M+P` = "#6A51A3"), guide = "none") +
  coord_cartesian(ylim = c(0.4, 1)) +
  labs(title = "Do sounds add to meaning?",
       subtitle = paste0("M = meaning + frequency, iconicity, length, surprisal; M+P = M + phonemes
N = ",
                         format(n_meaning, big.mark = ","), " words; mean ± SD over 50 folds; dashed = permutation chance"),
       x = NULL, y = "AUC") +
  theme_poster + theme(plot.subtitle = element_text(size = 15))
save_fig(p_svm, "fig10_sound_vs_meaning.png")

# Residual test
resid_obs  <- resid_out %>% filter(!is.na(fold))
resid_perm <- resid_out %>% filter(!is.na(perm)) %>% group_by(perm) %>%
  summarise(r2 = mean(r2), cor = mean(cor), .groups = "drop")
resid_summary <- tibble(
  n = n_meaning, folds = nrow(resid_obs),
  r2_mean = mean(resid_obs$r2), r2_sd = sd(resid_obs$r2),
  cor_mean = mean(resid_obs$cor), cor_sd = sd(resid_obs$cor),
  r2_meaning_mean = mean(resid_obs$r2_meaning), r2_meaning_sd = sd(resid_obs$r2_meaning),
  perm_r2_mean = mean(resid_perm$r2), perm_r2_sd = sd(resid_perm$r2), perm_r2_max = max(resid_perm$r2),
  perm_cor_mean = mean(resid_perm$cor), n_perm = nrow(resid_perm))
resid_summary <- resid_summary %>%
  mutate(n_ge_r2 = sum(resid_perm$r2 >= r2_mean), p_r2 = (1 + n_ge_r2) / (n_perm + 1),
         n_ge_cor = sum(resid_perm$cor >= cor_mean), p_cor = (1 + n_ge_cor) / (n_perm + 1))
write_csv(resid_summary, file.path(OUT, "residual_test.csv"))
write_csv(resid_out, file.path(OUT, "residual_test_folds.csv"))
p_res <- ggplot(resid_perm, aes(r2)) +
  geom_histogram(bins = 25, fill = "grey65", colour = "white") +
  geom_vline(xintercept = resid_summary$r2_mean, colour = COL_FUNNY, linewidth = 1.6) +
  annotate("label", x = resid_summary$r2_mean, y = Inf, vjust = 1.3, hjust = 1.05, size = 6.5,
           label = paste0("observed R² = ", fmt(resid_summary$r2_mean, 3), "\n", pfmt(resid_summary$p_r2))) +
  labs(title = "Do sounds explain what meaning cannot?",
       subtitle = paste0("Phonemes predicting humor residuals after meaning + controls
(test-fold R²; grey = ",
                         resid_summary$n_perm, " shuffles of the phoneme rows)"),
       x = "Cross-validated R² on residuals", y = "Number of shuffles") +
  theme_poster + theme(plot.subtitle = element_text(size = 16))
save_fig(p_res, "fig11_residual_test.png")

# SHAP for M+P: are the funny / unfunny sounds the same as in model A?
dirMP <- direction %>% filter(target == "median", model == "MP", feature %in% D_PH, n_words_with >= MIN_WORDS)
funny_MP   <- dirMP %>% filter(mean_shap_with > 0) %>% slice_max(mean_shap_with, n = 5)
unfunny_MP <- dirMP %>% filter(mean_shap_with < 0) %>% slice_min(mean_shap_with, n = 5)
dir_both <- inner_join(dirA %>% select(feature, a = mean_shap_with),
                       dirMP %>% select(feature, mp = mean_shap_with), by = "feature")
dir_rho  <- cor(dir_both$a, dir_both$mp, method = "spearman")
dir_sign_agree <- sum(sign(dir_both$a) == sign(dir_both$mp))
overlap_funny   <- intersect(funny_ph$feature, funny_MP$feature)
overlap_unfunny <- intersect(unfunny_ph$feature, unfunny_MP$feature)
ph_share <- shap_importance %>% filter(model == "MP") %>% group_by(target) %>%
  summarise(phoneme_share = 100 * sum(mean_abs_shap[feature %in% D_PH]) / sum(mean_abs_shap),
            n_ph_top10 = sum(feature %in% D_PH & rank <= 10),
            top_phoneme = nice_label(feature[feature %in% D_PH][which.min(rank[feature %in% D_PH])]),
            top_phoneme_rank = min(rank[feature %in% D_PH]), .groups = "drop")

# ---- Extension 2: position ------------------------------------------------------
pos_shap <- shap_importance %>% filter(model == "APos", startsWith(feature, "pos_")) %>%
  left_join(direction %>% filter(model == "APos") %>% select(target, feature, n_words_with, mean_shap_with),
            by = c("target", "feature"))
le_shap <- pos_shap %>% filter(feature == "pos_le_ending")
le_groups <- c("-le spelling", "-al / -el spelling", "no -le ending")
le_dat <- dat %>% mutate(group = factor(case_when(le_spelled ~ le_groups[1], le_other_sp ~ le_groups[2],
                                                  TRUE ~ le_groups[3]), le_groups))
le_n <- table(le_dat$group)
p_le <- ggplot(le_dat, aes(group, humor, fill = group)) +
  geom_boxplot(width = 0.55, outlier.alpha = 0.3, linewidth = 0.9) +
  stat_summary(fun = mean, geom = "point", shape = 23, size = 5, fill = "white") +
  scale_fill_manual(values = setNames(c(COL_FUNNY, "#F0B27A", "grey70"), le_groups), guide = "none") +
  scale_x_discrete(labels = paste0(c("-le spelling\n(gaggle)", "-al / -el\n(social)", "no -le ending\n"),
                                   "\nn = ", format(as.integer(le_n), big.mark = ",", trim = TRUE))) +
  labs(title = "Words ending in syllabic -le",
       subtitle = paste0("Spelled -le vs no ending: d = ", fmt(le_sp_d, 2), ", ", pfmt(le_sp_t$p.value),
                         " (diamond = mean)"),
       x = NULL, y = "Humor rating (1-5)") +
  theme_poster + theme(plot.subtitle = element_text(size = 16))
save_fig(p_le, "fig12_le_ending.png")

# ---- Extension 3: phonological features ----------------------------------------
f_tab <- shap_importance %>% filter(model == "F") %>%
  left_join(direction %>% filter(model == "F") %>% select(target, feature, spearman_value_shap, mean_shap_with),
            by = c("target", "feature"))

# ---- Updated model comparison with all models ---------------------------------
ALL_CMP <- c("A", "APos", "F", "B", "C", "M", "MP")
cmp_all <- results_table %>% filter(model %in% ALL_CMP) %>%
  mutate(target_lab = tl(target),
         model_lab = factor(MODEL_LABEL[as.character(model)], MODEL_LABEL[ALL_CMP]),
         family = case_when(model %in% c("A", "APos", "F") ~ "Sound only",
                            model %in% c("B", "C") ~ "Sound + lexical controls",
                            TRUE ~ "Meaning (N = sample with meaning ratings)"),
         family = factor(family, c("Sound only", "Sound + lexical controls", "Meaning (N = sample with meaning ratings)")))
p_cmp_all <- ggplot(cmp_all, aes(model_lab, auc_mean, fill = family)) +
  geom_col(width = 0.7) +
  geom_errorbar(aes(ymin = auc_mean - auc_sd, ymax = auc_mean + auc_sd), width = 0.25, linewidth = 0.9) +
  geom_text(aes(y = auc_mean + auc_sd + 0.03, label = fmt(auc_mean, 2)), size = 5.5) +
  geom_hline(data = chance_dat, aes(yintercept = chance_auc), linetype = "dashed", linewidth = 1.1) +
  facet_wrap(~ target_lab) +
  scale_fill_manual(values = c(`Sound only` = "#6A51A3", `Sound + lexical controls` = "#E69F00",
                               `Meaning (N = sample with meaning ratings)` = "#009E73"), name = NULL) +
  coord_cartesian(ylim = c(0.4, 1)) +
  guides(fill = guide_legend(nrow = 2)) +
  labs(title = "Cross-validated AUC, all models",
       subtitle = "Mean ± SD over 50 folds; dashed = permutation chance",
       x = NULL, y = "AUC") +
  theme_poster + theme(axis.text.x = element_text(size = 15), legend.text = element_text(size = 15))
save_fig(p_cmp_all, "fig04b_model_comparison_all.png")

# ---------------------------------------------------------------------------
# 8. results.md (every number below is computed in this script)
# ---------------------------------------------------------------------------
msg("STEP 8: writing results.md")
total_minutes <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
L <- character()
add <- function(...) L <<- c(L, paste0(...))
md_table <- function(df) {
  df <- mutate(df, across(everything(), as.character))
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
ms <- function(mean, sd, d = 3) paste0(fmt(mean, d), " ± ", fmt(sd, d))
rt <- function(tg, m) results_table %>% filter(target == tg, model == m)
ps <- function(tg, m) perm_summary %>% filter(target == tg, model == m)
wx <- function(tg, cmp) wilcox_res %>% filter(target == tg, comparison == cmp)
top_n_feats <- function(tg, m, n) shap_importance %>% filter(target == tg, model == m, rank <= n) %>%
  pull(feature) %>% nice_label() %>% paste(collapse = ", ")
sig <- function(p) p < 0.05

add("# Results: What Makes a Word Sound Funny?")
add("")
add("Permutations: ", N_PERM, " shuffles for models A and C; ", N_PERM_NEW,
    " for the extension models M, M+P, A+Pos and F (a full run with 200 exceeded the 25-minute budget); ",
    N_RESID_PERM, " for the residual test.")
add("")
add("All numbers in this file were written by `analysis.R`. Run time: ", fmt(total_minutes, 1),
    " minutes (nested CV ", fmt(cv_minutes, 1), " min, permutation baseline ", fmt(perm_minutes, 1),
    " min, residual test ", fmt(resid_minutes, 1), " min, ", N_CORES, " parallel workers).")
add("")
add("## 1. Data")
add("")
add("- Rows in Master.csv: ", n_raw, if (bad_row_dropped) " (known bad row 41831 dropped)" else "")
add("- Rows with a humor rating: ", n_humor)
add("- Rows removed for missing or zero phoneme length / phoneme counts: ", n_bad_len,
    "; duplicated words removed: ", n_dup)
add("- **Final cleaned N = ", n_clean, "**")
add("- Phoneme count fix: the raw count columns were built by substring matching (W also counted UW/OW/AW; Y counted IY/AY/EY/OY; R counted ER; T, D, S, Z counted TH, DH, SH, ZH; N and G counted NG). Rows whose counts sum to Phoneme_Length: ", fmt(100 * len_match_before, 1), "% before the fix, ", fmt(100 * len_match_after, 1), "% after; rows still mismatched: ", len_mismatch)
if (cmu_ran) {
  add("- CMUdict check (random 50 words, seed ", SEED, "): ", cmu_sample_first,
      "/50 match the first CMUdict pronunciation exactly (", cmu_sample_any, "/50 match some pronunciation)",
      if (cmu_rebuilt) "; counts were rebuilt from CMUdict" else "; no rebuild needed")
  add("- CMUdict check, all ", nrow(dat), " words: ", cmu_full[1], " match the first pronunciation, ",
      cmu_full[2], " match a variant, ", cmu_full[3], " mismatch, ", cmu_full[4], " not in CMUdict",
      if (length(cmu_mismatch_words) > 0) paste0(" (mismatches: ", paste(cmu_mismatch_words, collapse = ", "),
                                                 "; these look like alternative pronunciations)") else "")
} else add("- CMUdict check: not run (cmudict.dict missing)")
add("- Humor rating: mean ", fmt(humor_desc$mean, 2), ", SD ", fmt(humor_desc$sd, 2),
    ", median ", fmt(humor_desc$median, 2), ", range ", fmt(humor_desc$min, 2), " to ", fmt(humor_desc$max, 2))
add("- **Modelling N (complete cases on all model C features, shared by A, B, C) = ", n_model, "**")
add("- Median split: funny = rating > ", fmt(humor_median, 2), "; N = ", target_info$n[1],
    " (", target_info$n_funny[1], " funny, ", target_info$n_unfunny[1], " not funny)")
add("- Extreme groups: funny = rating >= ", fmt(q90, 2), " (top 10%), not funny = rating <= ",
    fmt(q10, 2), " (bottom 10%); N = ", target_info$n[2], " (", target_info$n_funny[2], " funny, ",
    target_info$n_unfunny[2], " not funny)")
add("")
add("## 2. Descriptive correlations with humor")
add("")
L <- c(L, md_table(pred_cor %>% transmute(Variable = variable, r = fmt(r), `95% CI` =
  paste0("[", fmt(ci_low), ", ", fmt(ci_high), "]"), p = fmtp(p), n = n)))
add("")
add("Phoneme proportions (Pearson r with humor, BH-FDR corrected), sorted:")
add("")
L <- c(L, md_table(ph_cor %>% arrange(desc(r)) %>%
  transmute(Phoneme = phoneme, r = fmt(r), p = fmtp(p), `q (FDR)` = fmtp(p_fdr), n = n)))
add("")
add("Phonemes with FDR q < .05: ", sum(ph_cor$p_fdr < 0.05), " of 39 (positive: ",
    paste(ph_cor$phoneme[ph_cor$p_fdr < 0.05 & ph_cor$r > 0], collapse = ", "), "; negative: ",
    paste(ph_cor$phoneme[ph_cor$p_fdr < 0.05 & ph_cor$r < 0], collapse = ", "), ")")
add("")
add("## 3. Cross-validated performance (mean ± SD over ", K_OUTER * REPEATS, " outer test folds)")
add("")
add("Model C_noSurp is a supplementary ablation (model C without Average_Surprisal).")
add("")
L <- c(L, md_table(results_table %>% transmute(
  Target = target, Model = model, N = n, Accuracy = ms(accuracy_mean, accuracy_sd),
  AUC = ms(auc_mean, auc_sd), Precision = ms(precision_mean, precision_sd),
  Recall = ms(recall_mean, recall_sd), F1 = ms(f1_mean, f1_sd))))
add("")
add("Pooled confusion matrices (summed over 50 test folds; each word counted ", REPEATS, " times):")
add("")
L <- c(L, md_table(results_table %>% transmute(Target = target, Model = model, TP, FP, TN, FN)))
add("")
add("Best model by mean AUC: ", paste0(best_models$target, " = model ", best_models$model,
                                         collapse = "; "))
add("")
add("### Hyperparameters chosen by the inner 3-fold CV")
add("")
L <- c(L, md_table(tuning_summary %>% group_by(target, model) %>% slice_head(n = 1) %>% ungroup() %>%
  left_join(nrounds_summary, by = c("target", "model")) %>%
  transmute(Target = target, Model = model, `Most chosen max_depth` = max_depth,
            `Most chosen eta` = eta, `Folds chosen (of 50)` = folds_selected,
            `nrounds median [min, max]` = paste0(nrounds_median, " [", nrounds_min, ", ", nrounds_max, "]"))))
add("")
add("## 4. Permutation baseline (", N_PERM, " label shuffles, single stratified 10-fold CV each, same nested tuning)")
add("")
L <- c(L, md_table(perm_summary %>% transmute(
  Target = target, Model = model, `Observed AUC` = fmt(observed_auc),
  `Permuted AUC mean ± SD` = ms(perm_mean, perm_sd), `Permuted AUC max` = fmt(perm_max),
  `Shuffles >= observed` = n_ge, `Empirical p` = fmt(p_empirical, 4))))
add("")
add("Empirical p = (1 + number of shuffles with AUC >= observed) / (", N_PERM,
    " + 1). The smallest possible value is ", fmt(1 / (N_PERM + 1), 4), ".")
add("")
add("## 5. Model comparison: paired Wilcoxon signed-rank tests on fold-level AUC")
add("")
L <- c(L, md_table(wilcox_res %>% transmute(
  Target = target, Comparison = comparison, `Mean AUC diff` = fmt(mean_diff, 4),
  `Median AUC diff` = fmt(median_diff, 4), `Folds better` = paste0(folds_better, "/", n_folds),
  V = fmt(V, 1), p = fmtp(p))))
add("")
add("## 6. SHAP importance (mean |SHAP| over 50 test folds) and stability (% folds in top 10)")
add("")
for (tg in TARGETS) for (m in c("A", "C")) {
  add("**Model ", m, ", ", TARGET_LABEL[tg], "** (top 15)")
  add("")
  L <- c(L, md_table(shap_importance %>% filter(target == tg, model == m, rank <= 15) %>%
    left_join(direction %>% select(target, model, feature, mean_shap_with, spearman_value_shap),
              by = c("target", "model", "feature")) %>%
    transmute(Rank = rank, Feature = nice_label(feature), `Mean abs SHAP` = fmt(mean_abs_shap, 4),
              SD = fmt(sd_abs_shap, 4), `% folds top 10` = fmt(pct_top10, 0),
              `Spearman(value, SHAP)` = fmt(spearman_value_shap, 2))))
  add("")
}
add("## 7. Funny-leaning and unfunny-leaning phonemes (model A, median split)")
add("")
add("Leaning = mean averaged SHAP value among words that contain the phoneme (phonemes in at least ",
    MIN_WORDS, " words). Examples: the 8 highest-rated (funny) or lowest-rated (unfunny) words containing the phoneme, with ratings.")
add("")
L <- c(L, md_table(example_tbl %>% transmute(
  Leaning = leaning, Phoneme = phoneme, `Words with it` = n_words_with,
  `Mean SHAP when present` = fmt(mean_shap_with, 4), `Importance rank` = rank, Examples = examples)))
add("")
add("## 8. Does Average_Surprisal still contribute in model C?")
add("")
L <- c(L, md_table(surp %>% transmute(
  Target = target, `Rank in C` = paste0(rank, " of ", length(FEATS$C)),
  `Mean abs SHAP` = fmt(mean_abs_shap, 4), `% folds top 10` = fmt(pct_top10, 0),
  `Spearman(surprisal, SHAP)` = fmt(spearman_value_shap, 2),
  `AUC gain C over C_noSurp` = fmt(mean_diff, 4), `Folds better` = paste0(folds_better, "/", n_folds),
  `Wilcoxon p` = fmtp(p))))
add("")

# ---------------------------------------------------------------------------
# Draft poster text (numbers are inserted from the objects above)
# ---------------------------------------------------------------------------
sp_med <- surp %>% filter(target == "median"); sp_ext <- surp %>% filter(target == "extreme")
r_surp <- pred_cor %>% filter(variable == "Average_Surprisal")
r_freq <- pred_cor %>% filter(variable == "log_freq")
r_val  <- pred_cor %>% filter(variable == "Valence_Glasgow")
r_mem  <- pred_cor %>% filter(variable == "Recog_Memory")
r_ico  <- pred_cor %>% filter(variable == "Winter_Ico")
r_len  <- pred_cor %>% filter(variable == "Phoneme_Length")
sf_ct  <- cor.test(dat$Average_Surprisal, dat$log_freq)
r_surp_freq <- unname(sf_ct$estimate)
ab_m <- wx("median", "B vs A"); bc_m <- wx("median", "C vs B")
ab_e <- wx("extreme", "B vs A"); bc_e <- wx("extreme", "C vs B")
sign_word <- function(x) ifelse(x > 0, "positive", "negative")
change_txt <- function(w) sprintf("%s%s AUC (%d/%d folds better, Wilcoxon p %s)",
                                  ifelse(w$mean_diff >= 0, "+", ""), fmt(w$mean_diff, 3),
                                  w$folds_better, w$n_folds, fmtp(w$p))
phA_beats_chance <- all(perm_summary$p_empirical[perm_summary$model == "A"] <= 1 / (N_PERM + 1) + 1e-9)
dir_of <- function(tg, m, f) direction$spearman_value_shap[direction$target == tg & direction$model == m & direction$feature == f]
up_down <- function(x) ifelse(x > 0, "higher values push toward 'funny'", "higher values push toward 'not funny'")
phoneme_top_in_C <- shap_importance %>% filter(model == "C", target == "median", feature %in% D_PH, pct_top10 >= 50)

# ---- Extension sections ------------------------------------------------------
auc_ms <- function(tg, m) ms(rt(tg, m)$auc_mean, rt(tg, m)$auc_sd)
lab_cmp <- function(x) { for (m in names(sort(nchar(MODEL_LABEL), decreasing = TRUE)))
  x <- gsub(paste0("\\b", m, "\\b"), MODEL_LABEL[[m]], x); x }
ext_wil_table <- function(cmps) md_table(wilcox_res %>% filter(comparison %in% cmps) %>% transmute(
  Target = target, Comparison = lab_cmp(comparison), `Mean AUC diff` = fmt(mean_diff, 4),
  `Folds better` = paste0(folds_better, "/", n_folds), V = fmt(V, 1), p = fmtp(p)))
ext_perm_table <- function(ms_) md_table(perm_summary %>% filter(model %in% ms_) %>% transmute(
  Target = target, Model = MODEL_LABEL[model], `Observed AUC` = fmt(observed_auc),
  `Permuted AUC mean ± SD` = ms(perm_mean, perm_sd), `Shuffles` = N_PERM_NEW,
  `Shuffles >= observed` = n_ge, `Empirical p` = fmt(p_empirical, 4)))

add("## 9. Extension 1: sound vs meaning")
add("")
add("Coverage of candidate meaning columns among the ", n_clean, " rated words (main set needs at least ",
    COVERAGE_MIN, "% coverage):")
add("")
L <- c(L, md_table(meaning_cov %>% transmute(Column = column, N = n, `Coverage %` = fmt(pct, 1), Use = used)))
add("")
add("- Main meaning set: ", paste(MEANING, collapse = ", "), ".")
if (length(MEANING_LOW) > 0)
  add("- Dropped from the main set: ", paste(MEANING_LOW, collapse = ", "),
      " (coverage ", fmt(min(meaning_cov$pct[meaning_cov$column %in% MEANING_LOW]), 1),
      "%; requiring them would cut N from ", n_meaning, " to ", n_meaning_nrc,
      "). They are used in a sensitivity analysis on N = ", n_meaning_nrc, ".")
add("- Valence_Glasgow is not used (", meaning_cov$n[meaning_cov$column == "Valence_Glasgow"], " words).")
add("- **Sample with complete meaning features and controls: N = ", n_meaning, "** (median split: ",
    sum(TASKDATA$median_M$y), " funny / ", sum(1 - TASKDATA$median_M$y), " not; extreme: N = ",
    nrow(TASKDATA$extreme_M), ", ", sum(TASKDATA$extreme_M$y), " funny / ", sum(1 - TASKDATA$extreme_M$y), " not).")
add("- M = meaning + log_freq + Winter_Ico + Phoneme_Length + Average_Surprisal; M+P = M + 39 phoneme proportions. Same folds for M and M+P (stratified 10 x 5, seed ", SEED, ", nested tuning).")
add("")
L <- c(L, md_table(results_table %>% filter(model %in% c("M", "MP", "M_NRC", "MP_NRC")) %>% transmute(
  Target = target, Model = MODEL_LABEL[as.character(model)], N = n, Accuracy = ms(accuracy_mean, accuracy_sd),
  AUC = ms(auc_mean, auc_sd), F1 = ms(f1_mean, f1_sd))))
add("")
add("Paired Wilcoxon tests (fold-level AUC):")
add("")
L <- c(L, ext_wil_table(c("MP vs M", "MP_NRC vs M_NRC")))
add("")
add("Permutation baseline for the extension models:")
add("")
L <- c(L, ext_perm_table(NEW_PERM_MODELS))
add("")
add("### Residual test")
add("")
add("Within each of the ", resid_summary$folds, " outer folds (median-split folds of the meaning sample, N = ", n_meaning,
    "): linear model of the continuous humor rating on the M features, fitted on the training fold only; ",
    "XGBoost regression (same nested tuning) on the 39 phoneme proportions predicts the training residuals; scored on test-fold residuals. ",
    "Null: ", resid_summary$n_perm, " shuffles of the phoneme rows, single 10-fold CV each.")
add("")
add("- Linear meaning model alone, test-fold R² on the humor rating: ", ms(resid_summary$r2_meaning_mean, resid_summary$r2_meaning_sd))
add("- **Phonemes on residuals: test-fold R² = ", ms(resid_summary$r2_mean, resid_summary$r2_sd),
    "; correlation r = ", ms(resid_summary$cor_mean, resid_summary$cor_sd), "**")
add("- Shuffled phonemes: R² = ", ms(resid_summary$perm_r2_mean, resid_summary$perm_r2_sd), " (max ",
    fmt(resid_summary$perm_r2_max), "); mean r = ", fmt(resid_summary$perm_cor_mean))
add("- Empirical p (R²) = ", fmt(resid_summary$p_r2, 4), " (", resid_summary$n_ge_r2, " shuffles >= observed); ",
    "empirical p (r) = ", fmt(resid_summary$p_cor, 4), "; smallest possible p = ", fmt(1 / (resid_summary$n_perm + 1), 4))
add("")
add("### SHAP for M+P: same sounds as model A?")
add("")
L <- c(L, md_table(ph_share %>% transmute(Target = target, `Phoneme share of total mean abs SHAP (%)` = fmt(phoneme_share, 1),
  `Phonemes in top 10` = n_ph_top10, `Top phoneme (rank)` = paste0(top_phoneme, " (", top_phoneme_rank, ")"))))
add("")
add("- M+P funny-leaning (median split): ", paste(nice_label(funny_MP$feature), collapse = ", "),
    ". Model A: ", paste(nice_label(funny_ph$feature), collapse = ", "), ". Overlap: ",
    length(overlap_funny), "/5 (", paste(nice_label(overlap_funny), collapse = ", "), ").")
add("- M+P unfunny-leaning: ", paste(nice_label(unfunny_MP$feature), collapse = ", "),
    ". Model A: ", paste(nice_label(unfunny_ph$feature), collapse = ", "), ". Overlap: ",
    length(overlap_unfunny), "/5 (", paste(nice_label(overlap_unfunny), collapse = ", "), ").")
add("- Across ", nrow(dir_both), " phonemes (each in at least ", MIN_WORDS, " words), mean SHAP when present in A vs M+P: Spearman rho = ",
    fmt(dir_rho, 2), "; same sign for ", dir_sign_agree, "/", nrow(dir_both), ".")
add("")
add("**Model M+P, Median split** (top 15)")
add("")
L <- c(L, md_table(shap_importance %>% filter(target == "median", model == "MP", rank <= 15) %>%
  left_join(direction %>% select(target, model, feature, mean_shap_with, spearman_value_shap),
            by = c("target", "model", "feature")) %>%
  transmute(Rank = rank, Feature = nice_label(feature), Type = feat_type(feature),
            `Mean abs SHAP` = fmt(mean_abs_shap, 4), `% folds top 10` = fmt(pct_top10, 0),
            `Spearman(value, SHAP)` = fmt(spearman_value_shap, 2))))
add("")
add("## 10. Extension 2: position in the word")
add("")
add("- Source: CMUdict first pronunciation, stress removed, whole-token matching; words without a CMUdict entry: ", n_no_pron, ".")
add("- Features (", length(POS_FEATS), "): first phoneme one-hot (", length(first_keep), " phonemes with at least ",
    MIN_POS_WORDS, " words), last phoneme one-hot (", length(last_keep), "), two-phoneme endings with at least ",
    MIN_END_WORDS, " words (", length(end2_keep), ": ", paste(gsub("_", " ", end2_keep), collapse = ", "),
    "), and the syllabic -le flag (consonant + AH L).")
add("- Endings were added as candidate flags without looking at humor; their importance is judged by SHAP inside CV.")
add("")
add("**-le ending vs other words (descriptive, all ", n_clean, " words):**")
add("")
L <- c(L, md_table(le_summary %>% transmute(Group = group, N = n, `Mean humor` = fmt(mean, 3), SD = fmt(sd, 3))))
add("")
add("- Welch t(", fmt(le_t$parameter, 1), ") = ", fmt(le_t$statistic, 2), ", ", pfmt(le_t$p.value),
    "; mean difference = ", fmt(diff(rev(le_t$estimate)), 3), " [95% CI ", fmt(le_t$conf.int[1], 3), ", ",
    fmt(le_t$conf.int[2], 3), "]; Cohen's d = ", fmt(le_d, 2))
add("- 10 random -le words (seed ", SEED, "), sorted by rating: ", paste(le_examples, collapse = ", "))
add("- The phonological rule also includes -al/-el spellings. Split by spelling within the -le group:")
add("")
L <- c(L, md_table(le_spell_summary %>% transmute(Group = group, N = n, `Mean humor` = fmt(mean, 3), SD = fmt(sd, 3))))
add("")
add("- Spelled -le words vs words without the ending: Welch t(", fmt(le_sp_t$parameter, 1), ") = ",
    fmt(le_sp_t$statistic, 2), ", ", pfmt(le_sp_t$p.value), "; Cohen's d = ", fmt(le_sp_d, 2))
add("")
add("**A+Pos vs A (same folds):**")
add("")
L <- c(L, md_table(results_table %>% filter(model %in% c("A", "APos")) %>% transmute(
  Target = target, Model = MODEL_LABEL[as.character(model)], AUC = ms(auc_mean, auc_sd), F1 = ms(f1_mean, f1_sd))))
add("")
L <- c(L, ext_wil_table("APos vs A"))
add("")
add("Top position features in A+Pos by mean abs SHAP (rank among all ", length(FEATS$APos), " features):")
add("")
L <- c(L, md_table(pos_shap %>% group_by(target) %>% slice_min(rank, n = 8) %>% ungroup() %>% transmute(
  Target = target, Feature = nice_label(feature), Rank = rank, `Mean abs SHAP` = fmt(mean_abs_shap, 4),
  `% folds top 10` = fmt(pct_top10, 0), `Words with it` = n_words_with,
  `Mean SHAP when present` = fmt(mean_shap_with, 3))))
add("")
add("## 11. Extension 3: phonological features")
add("")
add("Mapping (diphthongs classified by their first element; F, V and W coded labial; Y grouped with postalveolar; R coded alveolar):")
add("")
L <- c(L, md_table(PHON_MAP %>% mutate(across(everything(), ~ ifelse(is.na(.x), "", .x)))))
add("")
add("- ", length(F_FEATS), " features, each the proportion of the word's phonemes that has the feature: ",
    paste(nice_label(F_FEATS), collapse = ", "), ".")
add("")
add("**F vs A (same folds):**")
add("")
L <- c(L, md_table(results_table %>% filter(model %in% c("A", "F")) %>% transmute(
  Target = target, Model = MODEL_LABEL[as.character(model)], AUC = ms(auc_mean, auc_sd), F1 = ms(f1_mean, f1_sd))))
add("")
L <- c(L, ext_wil_table("F vs A"))
add("")
for (tg in TARGETS) {
  add("**Model F, ", TARGET_LABEL[tg], "** (all features; direction = Spearman between feature value and its SHAP)")
  add("")
  L <- c(L, md_table(f_tab %>% filter(target == tg) %>% arrange(rank) %>% transmute(
    Rank = rank, Feature = nice_label(feature), `Mean abs SHAP` = fmt(mean_abs_shap, 4),
    `% folds top 10` = fmt(pct_top10, 0), `Spearman(value, SHAP)` = fmt(spearman_value_shap, 2),
    Direction = ifelse(spearman_value_shap > 0, "toward funny", "toward not funny"))))
  add("")
}

add("---")
add("")
add("# Draft poster text (original A/B/C analysis; the final poster text is in poster_text.md)")
add("")
add("## Introduction")
add("")
add("- Sound symbolism: word sounds are not fully arbitrary; some sounds carry meaning (size, shape, emotion).")
add("- Engelthaler & Hills (2018) collected humor ratings (1-5) for about 5,000 English words.")
add("- Kilpatrick & Flaksman (2025): humorous words have higher phonemic surprisal and are more memorable, despite their positive valence.")
add("- Open questions: which specific sounds make a word funny, and is it the sound or just that funny words are rare?")
add("")
add("## Research Question")
add("")
add("- Do specific phonemes predict whether an English word is rated funny?")
add("- Does that effect survive controls for word frequency and iconicity?")
add("")
add("## Data & Method")
add("")
add("- ", n_clean, " words with humor ratings (Engelthaler & Hills, 2018); ", n_model,
    " with complete features used for all models.")
add("- Data check: raw phoneme counts double-counted symbols inside longer ARPABET symbols (e.g. W inside OW); corrected so counts sum to word length in ", fmt(100 * len_match_after, 1), "% of words (was ", fmt(100 * len_match_before, 1), "%).")
add("- Features: proportions of 39 CMU phonemes (count / word length); phonemic surprisal; iconicity (Winter et al., 2024); length in phonemes; log10 word frequency (SUBTLEX-US; Brysbaert & New, 2009). Meaning: Warriner et al. (2013); concreteness: Brysbaert et al. (2014). Pronunciations: CMUdict (Weide, 1998).")
add("- Targets: (a) median split at ", fmt(humor_median, 2), " (N = ", target_info$n[1],
    "); (b) top 10% vs bottom 10% (N = ", target_info$n[2], ").")
add("- Models (XGBoost, Chen & Guestrin, 2016): A = phonemes; B = A + surprisal, iconicity, length; C = B + frequency.")
add("- Nested CV: stratified 10-fold x 5 repeats (50 test folds), same folds for every model.")
add("- Tuning only inside each training fold: inner 3-fold CV over max_depth {2, 4, 6} x eta {0.05, 0.1}, nrounds by early stopping.")
add("- Baseline: ", N_PERM, " label permutations rerun through the same pipeline (models A and C).")
add("- Model comparison: paired Wilcoxon tests on fold-level AUC. Interpretation: SHAP (Lundberg & Lee, 2017) on test folds only.")
add("")
add("## Results")
add("")
add("- Humor correlates ", sign_word(r_freq$r), "ly with frequency (r = ", fmt(r_freq$r, 2), "), ",
    sign_word(r_ico$r), "ly with iconicity (r = ", fmt(r_ico$r, 2), ") and ",
    sign_word(r_surp$r), "ly with surprisal (r = ", fmt(r_surp$r, 2), ").")
add("- Valence r = ", fmt(r_val$r, 2), " (n = ", r_val$n, "); recognition memory r = ",
    fmt(r_mem$r, 2), " (n = ", r_mem$n, ").")
add("- ", sum(ph_cor$p_fdr < 0.05), " of 39 phonemes correlate with humor after FDR correction.")
for (tg in TARGETS) {
  add("- ", TARGET_LABEL[tg], " AUC: A = ", fmt(rt(tg, "A")$auc_mean), ", B = ", fmt(rt(tg, "B")$auc_mean),
      ", C = ", fmt(rt(tg, "C")$auc_mean), "; chance (permutation) = ",
      fmt(chance_line$chance_auc[chance_line$target == tg]), ".")
}
add("- Phonemes alone beat every permutation: empirical p = ",
    paste(fmt(perm_summary$p_empirical[perm_summary$model == "A"], 3), collapse = " and "),
    " (median split, extreme)", if (phA_beats_chance) "." else " (not significant in every case).")
add("- Adding surprisal, iconicity and length (B vs A): median split ", change_txt(ab_m),
    "; extreme ", change_txt(ab_e), ".")
add("- Adding frequency (C vs B): median split ", change_txt(bc_m), "; extreme ", change_txt(bc_e), ".")
add("- Top SHAP features in model C (median split): ", top_n_feats("median", "C", 5), ".")
add("- Funny-leaning phonemes: ", paste(funny_ph$feature %>% nice_label(), collapse = ", "),
    ". Unfunny-leaning: ", paste(unfunny_ph$feature %>% nice_label(), collapse = ", "), ".")
add("- In model C, frequency: ", up_down(dir_of("median", "C", "log_freq")), " (Spearman value vs SHAP = ",
    fmt(dir_of("median", "C", "log_freq"), 2), "); iconicity: ", up_down(dir_of("median", "C", "Winter_Ico")),
    " (", fmt(dir_of("median", "C", "Winter_Ico"), 2), ").")
for (sp in list(sp_med, sp_ext)) {
  add("- Surprisal in model C (", TARGET_LABEL[sp$target], "): rank ", sp$rank, " of ", length(FEATS$C),
      ", top 10 in ", fmt(sp$pct_top10, 0), "% of folds, Spearman value vs SHAP = ",
      fmt(sp$spearman_value_shap, 2), "; AUC of C minus C without surprisal = ",
      fmt(sp$mean_diff, 4), " (Wilcoxon p ", fmtp(sp$p), ").")
}
add("")
add("## Discussion")
add("")
if (phA_beats_chance) {
  add("- Sound alone carries information about humor: phoneme-only model A beats all ", N_PERM,
      " label-shuffled models on both targets.")
} else {
  add("- Evidence that sound alone predicts humor is mixed across targets (see permutation p-values).")
}
add(if (bc_m$mean_diff > 0 && sig(bc_m$p))
      paste0("- Frequency ", ifelse(shap_importance$rank[shap_importance$target == "median" & shap_importance$model == "C" & shap_importance$feature == "log_freq"] == 1, "is the top SHAP feature and ", ""), "adds AUC on top of sound (C > B): ",
             ifelse(dir_of("median", "C", "log_freq") < 0, "rarer", "more frequent"), " words are rated funnier.")
    else "- Frequency does not significantly improve on model B in the median split.")
add(if (nrow(phoneme_top_in_C) > 0)
      paste0("- Some phonemes stay in the top 10 of model C in at least half of the folds (",
             paste(nice_label(phoneme_top_in_C$feature), collapse = ", "),
             "), so their effect is not explained away by frequency.")
    else "- No phoneme stays in the top 10 of model C in at least half of the folds; once frequency is in, sound effects are small and unstable.")
surp_adds <- any(sig(c(sp_med$p, sp_ext$p)) & c(sp_med$mean_diff, sp_ext$mean_diff) > 0)
add(if (r_surp$r > 0)
      paste0("- Surprisal: the raw correlation matches Kilpatrick & Flaksman (2025): funnier words have higher phonemic surprisal (r = ",
             fmt(r_surp$r, 2), ")", if (r_mem$r > 0) paste0(" and are better recognised (r = ", fmt(r_mem$r, 2), ")") else "", ".")
    else paste0("- Unlike Kilpatrick & Flaksman (2025), the raw surprisal correlation is not positive (r = ", fmt(r_surp$r, 2), ")."))
if (r_surp$r > 0 && !surp_adds) {
  add("- But surprisal adds no predictive value once frequency, iconicity and length are controlled: AUC of C minus C without surprisal = ",
      fmt(sp_med$mean_diff, 4), " (p ", fmtp(sp_med$p), ", median split) and ", fmt(sp_ext$mean_diff, 4),
      " (p ", fmtp(sp_ext$p), ", extreme).")
  add("- ", ifelse(r_surp_freq < 0, "Higher-surprisal words tend to be rarer", "Higher-surprisal words tend to be more frequent"),
      " (r = ", fmt(r_surp_freq, 2), ", p ", fmtp(sf_ct$p.value), "), so the earlier surprisal effect may be partly driven by frequency.")
}
surp_dirs <- c(sp_med$spearman_value_shap, sp_ext$spearman_value_shap)
add(if (all(surp_dirs > 0))
      "- With frequency, iconicity and length controlled, higher surprisal still pushes toward 'funny' in both targets."
    else if (all(surp_dirs < 0))
      "- With frequency, iconicity and length controlled, higher surprisal pushes toward 'not funny' in both targets, reversing the raw direction."
    else paste0("- With frequency, iconicity and length controlled, the surprisal direction is unstable: ",
                ifelse(sp_med$spearman_value_shap > 0, "toward 'funny'", "toward 'not funny'"), " in the median split, ",
                ifelse(sp_ext$spearman_value_shap > 0, "toward 'funny'", "toward 'not funny'"), " in the extreme groups."))
if (surp_adds) add("- Surprisal adds unique predictive value in at least one target: removing it from model C lowers AUC significantly.")
add("- The extreme-group task is easier than the median split, as expected when middling words are removed.")
add("")
add("## Limitations")
add("")
add("- Humor ratings exist for about 5,000 words; iconicity is missing for some, reducing N to ", n_model, ".")
add("- Phoneme proportions ignore order, stress and syllable position; specific clusters may matter more than single sounds.")
add("- The 50 repeated-CV folds overlap, so Wilcoxon p-values are optimistic (folds are not independent).")
add("- Only ", N_PERM, " permutations: the smallest possible empirical p is ", fmt(1 / (N_PERM + 1), 3), ".")
lim_examples <- c("pain", "death", "theft")
if (!all(lim_examples %in% unlist(str_extract_all(example_tbl$examples[example_tbl$leaning == "unfunny"], "[a-z]+"))))
  lim_examples <- head(str_extract(example_tbl$examples[example_tbl$leaning == "unfunny"], "^[a-z]+"), 3)
n_val <- r_val$n
add("- Phoneme effects may partly reflect meaning, not sound: unfunny-leaning words (", paste(lim_examples, collapse = ", "),
    ") are semantically negative. Valence ratings exist for only ", n_val, " of ", n_clean,
    " words, so valence was not controlled in the main models.")
add("- SHAP shows associations inside the model, not causal effects of sounds on humor; correlated features share credit.")
add("- Surprisal here is an average of phoneme-bigram surprisals; other surprisal measures may behave differently.")
add("- Only a median and an extreme split are modelled; a regression on the full 1-5 rating would use more information.")
add("")
add("## Conclusion")
add("")
add("- Best cross-validated AUC: ", fmt(rt("median", best_models$model[best_models$target == "median"])$auc_mean),
    " (median split) and ", fmt(rt("extreme", best_models$model[best_models$target == "extreme"])$auc_mean),
    " (extreme groups).")
add("- Which sounds are funny: ", paste(nice_label(funny_ph$feature), collapse = ", "),
    "; which are not: ", paste(nice_label(unfunny_ph$feature), collapse = ", "), ".")
add("- All estimates come from test folds never used for tuning, checked against a permutation baseline and SHAP stability across 50 folds.")
add("")
add("## References")
add("")
REFS <- c(
  "Brysbaert, M., & New, B. (2009). Moving beyond Kučera and Francis. *Behavior Research Methods, 41*(4), 977-990.",
  "Brysbaert, M., Warriner, A. B., & Kuperman, V. (2014). Concreteness ratings for 40 thousand generally known English word lemmas. *Behavior Research Methods, 46*(3), 904-911.",
  "Chen, T., & Guestrin, C. (2016). XGBoost: A scalable tree boosting system. *Proceedings of KDD 2016*, 785-794.",
  "Engelthaler, T., & Hills, T. T. (2018). Humor norms for 4,997 English words. *Behavior Research Methods, 50*(3), 1116-1124.",
  "Kilpatrick, A., & Flaksman, M. (2025). The Exception of Humor: Iconicity, Phonemic Surprisal, Memory Recall, and Emotional Associations. *Proceedings of the 1st Workshop on Computational Humor (CHum)*, 1-8. ACL.",
  "Lundberg, S. M., & Lee, S.-I. (2017). A unified approach to interpreting model predictions. *NeurIPS 30*.",
  "Warriner, A. B., Kuperman, V., & Brysbaert, M. (2013). Norms of valence, arousal, and dominance for 13,915 English lemmas. *Behavior Research Methods, 45*(4), 1191-1207.",
  "Weide, R. (1998). *The CMU Pronouncing Dictionary*. Carnegie Mellon University.",
  "Winter, B., Lupyan, G., Perry, L. K., Dingemanse, M., & Perlman, M. (2024). Iconicity ratings for 14,000+ English words. *Behavior Research Methods, 56*, 1640-1655."
)
for (r in REFS) add("- ", r)
writeLines(L, file.path(OUT, "results.md"))

# ---------------------------------------------------------------------------
# 9. poster_text.md: final poster text for three A0 portrait columns
#    (numbers inserted from the objects above; word count checked below)
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 9. Poster for a general audience: plain-language figures and text
#    (every number below comes from objects computed above)
# ---------------------------------------------------------------------------
msg("STEP 9: poster figures and poster_text.md for a general audience")

# How each ARPABET symbol sounds, with the CMU Pronouncing Dictionary's own
# key word for that symbol (used for figure labels)
SOUND <- c(AA = "ah", AE = "a", AH = "uh", AO = "aw", AW = "ow", AY = "eye", B = "b", CH = "ch",
           D = "d", DH = "th", EH = "e", ER = "er", EY = "ay", F = "f", G = "g", HH = "h", IH = "i",
           IY = "ee", JH = "j", K = "k", L = "l", M = "m", N = "n", NG = "ng", OW = "oh", OY = "oy",
           P = "p", R = "r", S = "s", SH = "sh", T = "t", TH = "th", UH = "u", UW = "oo", V = "v",
           W = "w", Y = "y", Z = "z", ZH = "zh")
CMU_KEY <- c(AA = "odd", AE = "at", AH = "hut", AO = "ought", AW = "cow", AY = "hide", B = "be",
             CH = "cheese", D = "dee", DH = "thee", EH = "Ed", ER = "hurt", EY = "ate", F = "fee",
             G = "green", HH = "he", IH = "it", IY = "eat", JH = "gee", K = "key", L = "lee", M = "me",
             N = "knee", NG = "ping", OW = "oat", OY = "toy", P = "pee", R = "read", S = "sea",
             SH = "she", T = "tea", TH = "theta", UH = "hood", UW = "two", V = "vee", W = "we",
             Y = "yield", Z = "zee", ZH = "seizure")
sound_lab <- function(ph) paste0("\"", SOUND[ph], "\" as in ", CMU_KEY[ph])
FEATURE_PLAIN <- c(
  log_freq = "Word frequency", Winter_Ico = "Iconicity (sounds like its meaning)",
  Valence_Warr = "Valence (how positive)", Arousal_Warr = "Arousal (how exciting)",
  Dominance_Warr = "Dominance (sense of control)", Conc_Brys = "Concreteness (how tangible)",
  Phoneme_Length = "Word length", Average_Surprisal = "Sound surprisal",
  f_alveolar = "Tongue-tip consonants (t, d, n, s, z, l, r)", f_front = "Front vowels (ee, i, ay, e, a)",
  f_high = "High vowels (ee, i, oo, u)", f_central = "Central vowels (uh, er, ow, eye)",
  f_diphthong = "Gliding vowels (ay, eye, ow, oh, oy)", f_mid = "Mid vowels (ay, e, uh, er, aw, oh, oy)",
  f_back = "Back vowels (ah, aw, oo, u, oh, oy)", f_velar = "Back-of-tongue consonants (k, g, ng)",
  f_labial = "Lip consonants (p, b, m, f, v, w)", f_stop = "Stops (p, b, t, d, k, g)",
  f_voiced_stop = "Voiced stops (b, d, g)", f_liquid = "Liquids (l, r)", f_vowel = "Vowels",
  f_voiceless = "Voiceless consonants", f_dental = "Th sounds", f_voiceless_stop = "Voiceless stops (p, t, k)",
  f_voiced = "Voiced consonants", f_low = "Low vowels (a, ah, ow, eye)", f_rounded = "Rounded vowels (aw, oo, u, oh, oy)",
  f_voiceless_fricative = "Voiceless hissing sounds (f, th, s, sh, h)", f_nasal = "Nasals (m, n, ng)",
  f_postalveolar = "Sh-type sounds (sh, ch, j, zh, y)", f_fricative = "Hissing sounds (f, v, th, s, z, sh, zh, h)",
  f_glide = "Glides (w, y)", f_voiced_fricative = "Voiced hissing sounds (v, th, z, zh)",
  f_glottal = "h", f_affricate = "ch, j")
plain <- function(f) ifelse(f %in% D_PH, paste0("Sound ", sound_lab(sub("^d_", "", f))),
                            ifelse(f %in% names(FEATURE_PLAIN), FEATURE_PLAIN[f], nice_label(f)))
theme_public <- theme_poster + theme(plot.title.position = "plot")
TASK_PLAIN <- c(median = "Funnier vs less funny half", extreme = "Funniest 10% vs least funny 10%")
COL_TASK <- c("#56B4E9", "#0072B2")

svm_m <- wx("median", "MP vs M"); svm_e <- wx("extreme", "MP vs M")

# P1. Adding sounds to meaning
p1 <- svm %>% mutate(task = factor(TASK_PLAIN[as.character(target)], TASK_PLAIN),
                     mdl = factor(ifelse(model == "M", "Meaning\nonly", "Meaning\n+ sounds"),
                                  c("Meaning\nonly", "Meaning\n+ sounds"))) %>%
  ggplot(aes(mdl, auc_mean, fill = mdl)) +
  geom_col(width = 0.6) +
  geom_errorbar(aes(ymin = auc_mean - auc_sd, ymax = auc_mean + auc_sd), width = 0.2, linewidth = 1) +
  geom_text(aes(y = auc_mean + auc_sd + 0.035, label = fmt(auc_mean, 3)), size = 7.5) +
  geom_hline(yintercept = 0.5, linetype = "dashed", linewidth = 1) +
  annotate("text", x = 2.55, y = 0.475, label = "guessing", hjust = 1, size = 6) +
  facet_wrap(~ task) +
  scale_fill_manual(values = c("#009E73", "#6A51A3"), guide = "none") +
  coord_cartesian(ylim = c(0.45, 1)) +
  labs(title = "Adding word sounds improves prediction",
       subtitle = paste0("Same ", format(n_meaning, big.mark = ","), " words, all with meaning, frequency and iconicity;\nsounds won ",
                         svm_m$folds_better, " of ", svm_m$n_folds, " and ", svm_e$folds_better, " of ",
                         svm_e$n_folds, " tests on unseen words"),
       x = NULL, y = "Prediction score (AUC)") +
  theme_public + theme(strip.text = element_text(size = 19, face = "bold"), axis.text.x = element_text(size = 19))
save_fig(p1, "poster_fig_sound_vs_meaning.png")

# P2. Residual test
p2 <- ggplot(resid_perm, aes(r2)) +
  geom_histogram(bins = 25, fill = "grey65", colour = "white") +
  geom_vline(xintercept = resid_summary$r2_mean, colour = COL_FUNNY, linewidth = 2) +
  annotate("label", x = resid_summary$r2_mean, y = Inf, vjust = 1.3, hjust = 1.05, size = 7,
           label = paste0("Real sounds\nR² = ", fmt(resid_summary$r2_mean, 3))) +
  annotate("label", x = max(resid_perm$r2), y = Inf, vjust = 1.3, hjust = -0.1, size = 7,
           label = paste0("Shuffled sounds\n(", resid_summary$n_perm, " runs)"), colour = "grey30") +
  labs(title = "Sounds explain humor that meaning misses",
       subtitle = "After removing what meaning and frequency explain,\nhow much of the rest do sounds predict?",
       x = "Share of the leftover humor explained (R²)", y = "Number of runs") +
  theme_public + theme(plot.subtitle = element_text(size = 19))
save_fig(p2, "poster_fig_residual.png")

# P3. Funniest and least funny sounds (raw correlations, top and bottom 8)
p3_dat <- bind_rows(ph_cor %>% slice_max(r, n = 8), ph_cor %>% slice_min(r, n = 8)) %>%
  mutate(lab = fct_reorder(sound_lab(phoneme), r), dir = ifelse(r > 0, "funnier", "less funny"))
p3 <- ggplot(p3_dat, aes(r, lab, fill = dir)) +
  geom_col(width = 0.75) + geom_vline(xintercept = 0) +
  scale_fill_manual(values = c(funnier = COL_FUNNY, `less funny` = COL_UNFUNNY), name = NULL) +
  labs(title = "Which sounds go with funny words?",
       subtitle = paste0("Correlation between how often a sound appears\nin a word and its humor rating (", format(n_clean, big.mark = ","), " words)"),
       x = "Correlation with humor rating (r)", y = NULL) +
  theme_public + theme(axis.text.y = element_text(size = 19), plot.subtitle = element_text(size = 19))
save_fig(p3, "poster_fig_sounds.png")

# P4. All models, plain names
PLAIN_MODEL <- c(A = "Sounds only", APos = "Sounds + position in word", F = "Sound classes only",
                 B = "Sounds + surprisal, iconicity, length", C = "... + word frequency",
                 M = "Meaning, frequency & iconicity", MP = "... + word sounds")
p4 <- results_table %>% filter(model %in% names(PLAIN_MODEL)) %>%
  mutate(lab = factor(PLAIN_MODEL[as.character(model)], rev(PLAIN_MODEL)),
         task = factor(TASK_PLAIN[as.character(target)], TASK_PLAIN)) %>%
  ggplot(aes(auc_mean, lab, fill = task)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  geom_text(aes(label = fmt(auc_mean, 2)), position = position_dodge(width = 0.8), hjust = -0.15, size = 6) +
  geom_vline(xintercept = 0.5, linetype = "dashed", linewidth = 1) +
  scale_fill_manual(values = setNames(COL_TASK, TASK_PLAIN), name = NULL) +
  coord_cartesian(xlim = c(0.4, 1.0)) +
  guides(fill = guide_legend(nrow = 2)) +
  labs(title = "How well can a computer spot funny words?",
       subtitle = "Prediction score on unseen words: 0.5 = guessing (dashed), 1 = perfect",
       x = "Prediction score (AUC)", y = NULL) +
  theme_public + theme(axis.text.y = element_text(size = 18), plot.subtitle = element_text(size = 18))
save_fig(p4, "poster_fig_models.png")

# P5. What the meaning + sounds model relies on (top 12)
imp_mp <- shap_importance %>% filter(model == "MP", target == "median", rank <= 12) %>%
  left_join(direction %>% filter(model == "MP", target == "median") %>% select(feature, spearman_value_shap), by = "feature") %>%
  mutate(group = case_when(feature %in% D_PH ~ "Word sounds", feature %in% MEANING ~ "Meaning",
                           TRUE ~ "Frequency, iconicity, length"),
         lab = fct_reorder(plain(feature), mean_abs_shap),
         effect = ifelse(spearman_value_shap > 0, "more = funnier", "more = less funny"))
p5 <- ggplot(imp_mp, aes(mean_abs_shap, lab, fill = group)) +
  geom_col(width = 0.75) +
  geom_text(aes(label = effect), hjust = -0.05, size = 5.5) +
  scale_fill_manual(values = c(`Word sounds` = "#6A51A3", Meaning = "#009E73",
                               `Frequency, iconicity, length` = "#E69F00"), name = NULL) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.45))) +
  guides(fill = guide_legend(nrow = 2)) +
  labs(title = "What the model relies on",
       subtitle = "Top 12 features of the meaning + sounds model (SHAP)",
       x = "Average influence on the prediction", y = NULL) +
  theme_public + theme(axis.text.y = element_text(size = 17), plot.subtitle = element_text(size = 18))
save_fig(p5, "poster_fig_what_matters.png")

# P6. Sound classes (model F), top 10, coloured by direction
f_top <- f_tab %>% filter(target == "median", rank <= 10) %>%
  mutate(lab = fct_reorder(plain(feature), mean_abs_shap),
         dir = ifelse(spearman_value_shap > 0, "more = funnier", "more = less funny"))
p6 <- ggplot(f_top, aes(mean_abs_shap, lab, fill = dir)) +
  geom_col(width = 0.75) +
  scale_fill_manual(values = c(`more = funnier` = COL_FUNNY, `more = less funny` = COL_UNFUNNY), name = NULL) +
  labs(title = "Which kinds of sounds lean funny?",
       subtitle = "Sound classes ranked by influence in the model",
       x = "Average influence on the prediction", y = NULL) +
  theme_public + theme(axis.text.y = element_text(size = 17), plot.subtitle = element_text(size = 18))
save_fig(p6, "poster_fig_sound_classes.png")

# ---- Poster text ---------------------------------------------------------------
P <- character()
padd <- function(...) P <<- c(P, paste0(...))
# Words kept off a public university poster (rude, taboo or offensive)
NOT_ON_POSTER <- c("rape", "booty", "booby", "boob", "boobs", "hooter", "hooters", "panties", "quickie",
                   "douche", "groin", "rump", "striptease", "hussy", "honky", "nookie", "butt", "bum",
                   "fart", "poop", "weenie", "wiener", "pecker", "dong", "knockers", "boner", "horny",
                   "sexy", "nipple", "bra", "undies", "slut", "whore", "bitch", "racist", "slave")
pick_examples <- function(exs, skip = NOT_ON_POSTER) {   # one distinct example word per sound
  used <- skip
  vapply(exs, function(ex) {
    w <- str_extract_all(ex, "[a-z]+")[[1]]
    w <- w[!w %in% used][1]
    used <<- c(used, w)
    w
  }, character(1), USE.NAMES = FALSE)
}
svm_m <- wx("median", "MP vs M"); svm_e <- wx("extreme", "MP vs M")
nrc_m <- wx("median", "MP_NRC vs M_NRC"); apos_m <- wx("median", "APos vs A")
pA <- perm_summary %>% filter(model == "A")
share_m <- ph_share %>% filter(target == "median")
stable_f_ph <- intersect(funny_ph$feature, funny_MP$feature)
stable_u_ph <- intersect(unfunny_ph$feature, unfunny_MP$feature)
ex_of <- function(feats, funny) {
  exs <- example_tbl$examples[match(feats, example_tbl$feature)]
  pick_examples(exs)
}
say <- function(feats, funny) {
  ph <- sub("^d_", "", feats)
  paste0("\"", SOUND[ph], "\" (", ex_of(feats, funny), ")", collapse = ", ")
}
top_pos <- pos_shap %>% filter(target == "median") %>% slice_min(rank, n = 1)
top_pos_words <- dat %>% filter(.data[[top_pos$feature]] == 1, !tolower(Word) %in% NOT_ON_POSTER) %>%
  arrange(desc(humor)) %>% slice_head(n = 3) %>% pull(Word)
le_spell_ex <- intersect(c("gaggle", "tinkle"), tolower(dat$Word[le_spelled]))
if (length(le_spell_ex) < 2) le_spell_ex <- head(tolower(dat$Word[le_spelled][order(-dat$humor[le_spelled])]), 2)
f_stable <- f_tab %>% filter(target == "median", pct_top10 >= 90)
short_plain <- function(f) sub(" \\(.*", "", plain(f))
f_up <- f_stable$feature[f_stable$spearman_value_shap > 0]
f_down <- f_stable$feature[f_stable$spearman_value_shap < 0]
sound_adds <- svm_m$mean_diff > 0 && sig(svm_m$p) && svm_e$mean_diff > 0 && sig(svm_e$p)
resid_sig <- resid_summary$p_r2 < 0.05
funny_words <- ex_of(stable_f_ph, TRUE)

body_start <- length(P) + 1
padd("# What Makes a Word Sound Funny?")
padd(if (sound_adds && resid_sig) "### Sound Predicts Humor Beyond Frequency and Meaning"
     else "### Phonemes, frequency, meaning and humor ratings")
padd("")
padd("## COLUMN 1")
padd("")
padd("### The question")
padd("- Funny words are often rare and have funny meanings. Do their sounds still predict humor?")
padd("")
padd("### Background")
padd("- Sound symbolism: some sounds carry meaning.")
padd("- About 5,000 English words rated for humor, 1 to 5 (Engelthaler & Hills, 2018).")
padd("- Funny words have more surprising sounds and are easier to remember (Kilpatrick & Flaksman, 2025).")
padd("")
padd("### Data & Method")
padd("- ", format(n_meaning, big.mark = ","), " words with humor, meaning (Warriner et al., 2013; Brysbaert et al., 2014), SUBTLEX-US frequency (Brysbaert & New, 2009) and iconicity (Winter et al., 2024).")
padd("- Words split into 39 speech sounds (CMUdict; Weide, 1998).")
padd("- Task: tell funnier from less funny words (top vs bottom half; top vs bottom 10%).")
padd("- XGBoost models, always scored on unseen words: 10-fold cross-validation, repeated 5 times.")
padd("- Key test: meaning model vs meaning + sounds on the same words.")
padd("- Chance: models trained on shuffled ratings.")
padd("")
padd("## COLUMN 2")
padd("")
padd("### Results")
padd("- Score (AUC): 0.5 = guessing, 1 = perfect.")
padd("- Sounds alone beat guessing: ", fmt(rt("median", "A")$auc_mean, 2), " (half split), ",
     fmt(rt("extreme", "A")$auc_mean, 2), " (top/bottom 10%); shuffled ratings: ",
     fmt(chance_line$chance_auc[chance_line$target == "median"], 2), " (", pfmt(max(pA$p_empirical)), ").")
padd("- Adding sounds to meaning raises the score from ", fmt(rt("median", "M")$auc_mean, 3), " to ",
     fmt(rt("median", "MP")$auc_mean, 3), " and from ", fmt(rt("extreme", "M")$auc_mean, 3), " to ",
     fmt(rt("extreme", "MP")$auc_mean, 3), ".")
padd("- Sounds won ", svm_m$folds_better, " of ", svm_m$n_folds, " and ", svm_e$folds_better, " of ", svm_e$n_folds,
     " tests (", pfmt(max(svm_m$p, svm_e$p)), ").")
padd("- Sounds explain part of the humor meaning leaves unexplained (R² = ", fmt(resid_summary$r2_mean, 3),
     "; shuffled sounds: about 0, ", pfmt(resid_summary$p_r2), ").")
padd("- Holds with emotion word lists added (", nrc_m$folds_better, " of ", nrc_m$n_folds, " tests, ", pfmt(nrc_m$p), ").")
padd("- Frequency, iconicity and meaning matter most; sounds carry ", fmt(share_m$phoneme_share, 0),
     "% of the weight.")
padd("")
padd("## COLUMN 3")
padd("")
padd("### Which sounds?")
padd("- Funnier: ", say(stable_f_ph, TRUE), ". Less funny: ", say(stable_u_ph, FALSE), ".")
padd("- Endings: a final \"ee\" (", paste(head(top_pos_words, 2), collapse = ", "), ") and words spelled -le (",
     paste(le_spell_ex, collapse = ", "), ") are funnier.")
VOWEL_F <- c("f_high", "f_central", "f_back", "f_front", "f_diphthong", "f_mid", "f_low", "f_rounded", "f_vowel")
cls <- function(fs) paste(tolower(sub(" (vowels|consonants)$", "", short_plain(fs))), collapse = ", ")
padd("- Vowels leaning funny: ", cls(intersect(f_up, VOWEL_F)), "; less funny: ", cls(intersect(f_down, VOWEL_F)),
     ". Consonants leaning funny: ", cls(setdiff(f_up, VOWEL_F)), "; less funny: ", cls(setdiff(f_down, VOWEL_F)), ".")
padd("")
padd("### What it means")
padd(if (sound_adds && resid_sig) "- Sound adds a small but reliable piece of humor on top of meaning and frequency."
     else "- Once meaning and frequency are controlled, sound adds little reliable information.")
padd("- Surprising sound sequences go with funnier words (r = ", fmt(r_surp$r, 2),
     "; Kilpatrick & Flaksman, 2025), but add nothing beyond frequency: rarer words have more surprising sounds (r = ",
     fmt(r_surp_freq, 2), ").")
padd("")
padd("### Limitations")
padd("- Meaning ratings miss some aspects of meaning, such as taboo or rude senses.")
padd("- Results show association, not cause.")
padd("")
padd("### Conclusion")
padd(if (sound_adds && resid_sig)
       paste0("- Words like ", paste(funny_words, collapse = ", "), " are funny partly because of how they sound.")
     else "- Humor ratings are mainly about frequency, iconicity and meaning.")
body_end <- length(P)
padd("")
padd("### References")
for (r in REFS) padd("- ", r)

count_lines <- P[body_start:body_end]
count_lines <- count_lines[!grepl("^#{1,2} |^## COLUMN", count_lines)]
poster_words <- sum(lengths(str_split(str_squish(gsub("[#*-]", " ", paste(count_lines, collapse = " "))), " ")))

padd("")
padd("---")
padd("")
padd("### Recommended figures (6, made for a general audience)")
padd("1. `poster_fig_sounds.png` (column 1, bottom): which sounds go with funny words.")
padd("2. `poster_fig_models.png` (column 1, bottom): how well each model spots funny words.")
padd("3. `poster_fig_sound_vs_meaning.png` (column 2): the main result.")
padd("4. `poster_fig_residual.png` (column 2): sounds explain humor that meaning misses.")
padd("5. `poster_fig_what_matters.png` (column 2): what the meaning + sounds model relies on.")
padd("6. `poster_fig_sound_classes.png` (column 3): which kinds of sounds lean funny.")
padd("")
padd("Word count (body text, excluding title, references and this section): ", poster_words, ".")
writeLines(P, file.path(OUT, "poster_text.md"))
msg("  poster_text.md body word count: ", poster_words)
if (poster_words > 400) msg("  WARNING: poster_text.md body is over 400 words")

# ---------------------------------------------------------------------------
# 10. Course report (2-page abstract in the style of the course's Report Example)
#     Writes report_content.json; ../report_build/build_report.py turns it into
#     a .docx and PDF. Every number is taken from objects computed above.
# ---------------------------------------------------------------------------
msg("STEP 10: writing report_content.json")
IPA <- c(AA = "ɑ", AE = "æ", AH = "ʌ", AO = "ɔ", AW = "aʊ", AY = "aɪ", B = "b", CH = "tʃ", D = "d",
         DH = "ð", EH = "ɛ", ER = "ɝ", EY = "eɪ", F = "f", G = "ɡ", HH = "h", IH = "ɪ", IY = "i",
         JH = "dʒ", K = "k", L = "l", M = "m", N = "n", NG = "ŋ", OW = "oʊ", OY = "ɔɪ", P = "p",
         R = "ɹ", S = "s", SH = "ʃ", T = "t", TH = "θ", UH = "ʊ", UW = "u", V = "v", W = "w",
         Y = "j", Z = "z", ZH = "ʒ")
ipa <- function(f) paste0("/", IPA[sub("^d_", "", f)], "/")
ipa_list <- function(fs) { x <- ipa(fs); if (length(x) < 2) x else paste0(paste(head(x, -1), collapse = ", "), " and ", tail(x, 1)) }
and_list <- function(x) if (length(x) < 2) x else paste0(paste(head(x, -1), collapse = ", "), " and ", tail(x, 1))
rt_ <- function(tg, m, d = 3) fmt(rt(tg, m)$auc_mean, d)
sd_ <- function(tg, m) fmt(rt(tg, m)$auc_sd, 3)
pv <- function(p) ifelse(p < 0.001, "p < .001", paste0("p = ", fmtp(p)))
bc_m <- wx("median", "C vs B"); bc_e <- wx("extreme", "C vs B")
ab_m <- wx("median", "B vs A"); ab_e <- wx("extreme", "B vs A")
fa_m <- wx("median", "F vs A")
pA <- perm_summary %>% filter(model == "A")
r_year <- R.version$year
VOW_F <- c("f_high", "f_central", "f_back", "f_front", "f_diphthong", "f_mid", "f_low", "f_rounded", "f_vowel")
tech <- function(fs) sub("^diphthong$", "diphthongal", nice_label(fs))
f_phrase <- function(fs) {
  v <- intersect(fs, VOW_F); c_ <- setdiff(fs, VOW_F)
  parts <- c(if (length(v)) paste(and_list(tech(v)), "vowels"), if (length(c_)) paste(and_list(tech(c_)), "consonants"))
  paste(parts, collapse = " and ")
}
f_up_r <- f_tab %>% filter(target == "median", pct_top10 >= 90, spearman_value_shap > 0) %>% pull(feature)
f_dn_r <- f_tab %>% filter(target == "median", pct_top10 >= 90, spearman_value_shap < 0) %>% pull(feature)

paras <- c(
  paste0("This study asks whether the sounds of English words predict how funny they are rated, and whether this ",
         "effect survives controls for word frequency, iconicity and meaning. Sound symbolism, the association between ",
         "speech sounds and meanings, has been documented for size, shape and other perceptual qualities, and challenges ",
         "the view that the link between sound and meaning is purely arbitrary. Humor offers a useful test case. ",
         "Engelthaler and Hills (2018) collected humor ratings for 4,997 English words, and Kilpatrick and Flaksman (2025) ",
         "showed that humorous words have higher phonemic surprisal and are more memorable despite their positive valence. ",
         "However, funny words also tend to be rare and to carry distinctive meanings, so it is unclear whether specific ",
         "sounds, rather than frequency or meaning, drive humor ratings."),
  paste0("We build XGBoost classifiers (Chen & Guestrin, 2016) on phoneme proportions and compare them with models that ",
         "add lexical controls and meaning ratings, using nested, repeated cross-validation with permutation baselines. ",
         "We also test a phonological feature model and word-position features, and use SHAP values (Lundberg & Lee, 2017) ",
         "to identify which sounds push words toward funny or not funny."),
  paste0("All the data, the code, and the models are available {LINK}here{/LINK}. Data were processed in R (R Core Team, ", r_year,
         ") with the xgboost, caret (Kuhn, 2008), SHAPforxgboost and pROC (Robin et al., 2011) packages. Of the ",
         format(n_raw, big.mark = ","), " entries in the source dataset, ", format(n_clean, big.mark = ","),
         " words had humor ratings. Phoneme counts from the Carnegie Mellon University Pronouncing Dictionary (Weide, 1998) ",
         "were corrected for a substring-counting error (only ", fmt(100 * len_match_before, 1),
         "% of words originally summed to their phoneme length, 100% after correction; ", cmu_sample_first,
         " of 50 randomly sampled words matched the dictionary exactly) and normalized by word length. Lexical controls were ",
         "phonemic surprisal, iconicity (Winter et al., 2024), length and log10 SUBTLEX-US frequency (Brysbaert & New, 2009); ",
         "meaning features were valence, arousal and dominance (Warriner et al., 2013) and concreteness (Brysbaert et al., 2014). ",
         "Words were classified by a median split of humor ratings (N = ", format(n_model, big.mark = ","),
         ") and by the top versus bottom 10% (N = ", target_info$n[2], "). We compared a phoneme model (A), models adding ",
         "surprisal, iconicity and length (B) and then frequency (C), a meaning model without phonemes (M; N = ",
         format(n_meaning, big.mark = ","), "), the same model with phonemes (M+P), a model of ", length(F_FEATS),
         " phonological features (F) and phonemes plus word-position features (A+Pos). All models were evaluated with ",
         "stratified 10-fold cross-validation repeated 5 times, with hyperparameters tuned by inner 3-fold cross-validation ",
         "inside each training fold only. Chance levels came from label permutations (", N_PERM, " for A and C, ",
         N_PERM_NEW, " for the other models), models sharing folds were compared with paired Wilcoxon tests on fold-level AUC, ",
         "and a residual test asked whether phonemes predict the part of humor that a linear meaning model leaves unexplained (",
         N_RESID_PERM, " permutations)."),
  paste0("Phonemes alone predicted humor above chance: model A reached AUC = ", rt_("median", "A"), " (SD = ", sd_("median", "A"),
         ") for the median split and ", rt_("extreme", "A"), " (SD = ", sd_("extreme", "A"), ") for the extreme groups, against ",
         "permutation means of ", fmt(chance_line$chance_auc[chance_line$target == "median"], 2), " (", pv(max(pA$p_empirical)), "). ",
         "Adding surprisal, iconicity and length, and then frequency, raised AUC to ", rt_("median", "C"), " and ",
         rt_("extreme", "C"), " (", pv(max(ab_m$p, ab_e$p, bc_m$p, bc_e$p)), "). Crucially, adding phonemes to the meaning model ",
         "raised AUC from ", rt_("median", "M"), " to ", rt_("median", "MP"), " (median split) and from ", rt_("extreme", "M"),
         " to ", rt_("extreme", "MP"), " (extreme groups); M+P outperformed M in ", svm_m$folds_better, " and ",
         svm_e$folds_better, " of ", svm_m$n_folds, " folds (", pv(max(svm_m$p, svm_e$p)), "), and the gain held when NRC emotion ",
         "associations were added (N = ", format(n_meaning_nrc, big.mark = ","), "; ", nrc_m$folds_better, " of ", nrc_m$n_folds,
         " folds, ", pv(nrc_m$p), "). In the residual test, phonemes predicted humor left unexplained by meaning and frequency ",
         "(cross-validated R² = ", fmt(resid_summary$r2_mean, 3), ", r = ", fmt(resid_summary$cor_mean, 2),
         "), whereas shuffled phonemes did not (R² = ", fmt(resid_summary$perm_r2_mean, 3), "; ", pv(resid_summary$p_r2), "). ",
         "SHAP directions in M+P closely matched the phoneme-only model (rho = ", fmt(dir_rho, 2), "): ",
         ipa_list(stable_f_ph), " pushed words toward funny and ", ipa_list(stable_u_ph), " toward not funny (Table 1). ",
         "Word-position features added AUC ", fmt(apos_m$mean_diff, 3), " (", pv(apos_m$p), "), with word-final ",
         ipa(sub("^pos_last_", "", top_pos$feature)), " the strongest cue, and words spelled -le were rated funnier than other words ",
         "(d = ", fmt(le_sp_d, 2), "). The phonological feature model reached AUC = ", rt_("median", "F"),
         " (phonemes: ", rt_("median", "A"), "); ", f_phrase(f_up_r), " pushed toward funny, while ",
         f_phrase(f_dn_r), " pushed toward not funny (Table 2)."),
  paste0("Sound therefore contributes to humor ratings beyond word frequency, iconicity and meaning, although the contribution ",
         "is modest: frequency, iconicity and meaning remain the strongest predictors, and phonemes account for ",
         fmt(share_m$phoneme_share, 0), "% of the M+P model's SHAP importance. Phonemic surprisal correlated positively with ",
         "humor (r = ", fmt(r_surp$r, 2), "), in line with Kilpatrick and Flaksman (2025), but removing it from model C did not ",
         "lower AUC (", pv(sp_med$p), " and ", pv(sp_ext$p), "), and higher-surprisal words were rarer (r = ", fmt(r_surp_freq, 2),
         "), suggesting that part of the earlier surprisal effect reflects word frequency. Meaning ratings do not capture taboo ",
         "senses, phoneme proportions ignore stress and order, and overlapping folds make the Wilcoxon p-values optimistic. ",
         "Overall, specific sounds make English words funnier, and cross-validated machine learning with permutation baselines ",
         "can separate this effect from frequency and meaning.")
)

tab_rows <- function(df) lapply(seq_len(nrow(df)), function(i) unname(as.list(df[i, ])))
t1 <- shap_importance %>% filter(model == "MP", target == "median", feature %in% D_PH) %>% slice_min(rank, n = 5) %>%
  left_join(direction %>% filter(model == "MP", target == "median") %>% select(feature, spearman_value_shap), by = "feature") %>%
  transmute(Feature = ipa(feature), Importance = fmt(mean_abs_shap, 3),
            Direction = ifelse(spearman_value_shap > 0, "Funny", "Not funny"))
t2 <- f_tab %>% filter(target == "median") %>% slice_min(rank, n = 5) %>%
  transmute(Feature = tools::toTitleCase(tech(feature)), Importance = fmt(mean_abs_shap, 3),
            Direction = ifelse(spearman_value_shap > 0, "Funny", "Not funny"))

REPORT_REFS <- c(
  "Brysbaert, M., & New, B. (2009). Moving beyond Kučera and Francis. Behavior Research Methods, 41(4), 977-990.",
  "Brysbaert, M., Warriner, A. B., & Kuperman, V. (2014). Concreteness ratings for 40 thousand generally known English word lemmas. Behavior Research Methods, 46(3), 904-911.",
  "Chen, T., & Guestrin, C. (2016). XGBoost: A scalable tree boosting system. Proceedings of KDD 2016, 785-794.",
  "Engelthaler, T., & Hills, T. T. (2018). Humor norms for 4,997 English words. Behavior Research Methods, 50(3), 1116-1124.",
  "Kilpatrick, A., & Flaksman, M. (2025). The Exception of Humor: Iconicity, Phonemic Surprisal, Memory Recall, and Emotional Associations. Proceedings of the 1st Workshop on Computational Humor (CHum), 1-8. ACL.",
  "Kuhn, M. (2008). Building predictive models in R using the caret package. Journal of Statistical Software, 28(5), 1-26.",
  "Lundberg, S. M., & Lee, S.-I. (2017). A unified approach to interpreting model predictions. NeurIPS 30.",
  paste0("R Core Team (", r_year, "). R: A language and environment for statistical computing. R Foundation for Statistical Computing, Vienna, Austria."),
  "Robin, X., Turck, N., Hainard, A., Tiberti, N., Lisacek, F., Sanchez, J.-C., & Müller, M. (2011). pROC: An open-source package for R and S+ to analyze and compare ROC curves. BMC Bioinformatics, 12, 77.",
  "Warriner, A. B., Kuperman, V., & Brysbaert, M. (2013). Norms of valence, arousal, and dominance for 13,915 English lemmas. Behavior Research Methods, 45(4), 1191-1207.",
  "Weide, R. (1998). The CMU Pronouncing Dictionary. Carnegie Mellon University.",
  "Winter, B., Lupyan, G., Perry, L. K., Dingemanse, M., & Perlman, M. (2024). Iconicity ratings for 14,000+ English words. Behavior Research Methods, 56, 1640-1655."
)

report <- list(
  title = "What Makes a Word Sound Funny? Sound Predicts Humor Beyond Frequency and Meaning",
  author = "Mithun Thangaraj",
  affiliation = "EL161 Machine Learning for Linguistics",
  paragraphs = paras,
  table1 = list(caption = "Table 1: Phoneme importance (mean |SHAP| over 50 test folds) and direction in the M+P model (median split).",
                header = names(t1), rows = tab_rows(t1)),
  table2 = list(caption = "Table 2: Phonological feature importance (mean |SHAP| over 50 test folds) and direction in model F (median split).",
                header = names(t2), rows = tab_rows(t2)),
  references = REPORT_REFS
)
jsonlite::write_json(report, file.path(OUT, "report_content.json"), auto_unbox = TRUE, pretty = TRUE)
if (any(grepl("[\u2013\u2014]", c(paras, REPORT_REFS)))) msg("  WARNING: dash character in report text")
msg("  report body words: ", sum(lengths(strsplit(gsub("\\{/?LINK\\}", "", paste(paras, collapse = " ")), "\\s+"))))

save.image(file.path(OUT, "analysis_workspace.RData"))

# ---------------------------------------------------------------------------
# Terminal summary
# ---------------------------------------------------------------------------
cat("\n================ KEY FINDINGS ================\n")
cat(sprintf("Cleaned N = %d; modelling N = %d (median split %d, extreme %d)\n",
            n_clean, n_model, target_info$n[1], target_info$n[2]))
for (tg in TARGETS) {
  cat(sprintf("%-18s AUC  A %.3f (%.3f) | B %.3f (%.3f) | C %.3f (%.3f) | chance %.3f\n",
              TARGET_LABEL[tg], rt(tg, "A")$auc_mean, rt(tg, "A")$auc_sd, rt(tg, "B")$auc_mean,
              rt(tg, "B")$auc_sd, rt(tg, "C")$auc_mean, rt(tg, "C")$auc_sd,
              chance_line$chance_auc[chance_line$target == tg]))
}
cat("Permutation p (A, C):", paste(sprintf("%s/%s=%.3f", perm_summary$target, perm_summary$model,
                                           perm_summary$p_empirical), collapse = "  "), "\n")
cat("Wilcoxon:", paste(sprintf("%s %s: diff %.4f p=%s", wilcox_res$target, wilcox_res$comparison,
                               wilcox_res$mean_diff, fmtp(wilcox_res$p)), collapse = "\n          "), "\n")
cat("Top 5 SHAP, model C (median):", top_n_feats("median", "C", 5), "\n")
cat("Funny-leaning phonemes:  ", paste(nice_label(funny_ph$feature), collapse = ", "), "\n")
cat("Unfunny-leaning phonemes:", paste(nice_label(unfunny_ph$feature), collapse = ", "), "\n")
cat(sprintf("Surprisal in C (median): rank %d, top-10 in %.0f%% of folds, Spearman(value,SHAP) %.2f, ablation p %s\n",
            sp_med$rank, sp_med$pct_top10, sp_med$spearman_value_shap, fmtp(sp_med$p)))
cat("--- Extensions ---\n")
cat(sprintf("Sound vs meaning (N = %d): AUC M %.3f vs M+P %.3f (median, M+P wins %d/50, p %s); %.3f vs %.3f (extreme, %d/50, p %s)\n",
            n_meaning, rt("median", "M")$auc_mean, rt("median", "MP")$auc_mean, svm_m$folds_better, fmtp(svm_m$p),
            rt("extreme", "M")$auc_mean, rt("extreme", "MP")$auc_mean, svm_e$folds_better, fmtp(svm_e$p)))
cat(sprintf("Residual test: R2 %.3f, r %.2f, permutation p %.4f\n", resid_summary$r2_mean, resid_summary$cor_mean, resid_summary$p_r2))
cat(sprintf("Position: A+Pos vs A %+.3f AUC (median, p %s); -le d = %.2f (spelled -le d = %.2f)\n",
            apos_m$mean_diff, fmtp(apos_m$p), le_d, le_sp_d))
cat(sprintf("Phonological features: F AUC %.3f vs A %.3f (median)\n", rt("median", "F")$auc_mean, rt("median", "A")$auc_mean))
cat(sprintf("poster_text.md body words: %d\n", poster_words))
cat(sprintf("Total run time: %.1f minutes\n", total_minutes))
cat("Outputs in:", OUT, "\n")
cat("==============================================\n")
msg("Done.")
