# What Makes a Word Sound Funny? Sound Predicts Humor Beyond Frequency and Meaning

Mithun Thangaraj, EL161 Machine Learning for Linguistics

Data, code, models and outputs for the EL161 poster and report.

## Contents

- `Master.csv`: source dataset (humor ratings, phoneme counts, lexical and meaning norms).
- `cmudict.dict`: CMU Pronouncing Dictionary (Weide, 1998), used to check phoneme counts and build position features.
- `poster_outputs/analysis.R`: the full analysis (cleaning, nested cross-validated XGBoost, permutation baselines,
  Wilcoxon tests, residual test, SHAP, figures, `results.md`, poster text and report content).
- `poster_outputs/`: all results. `results.md` lists every number; `results_table.csv` has all cross-validation metrics;
  `fold_level_metrics.csv`, `permutation_auc.csv`, `shap_importance.csv` and the other CSVs hold the detailed outputs;
  PNG figures are at 300 dpi.
- `poster_build/`: the A0 poster (PowerPoint and PDF) and `build_poster.py`.
- `report_build/`: the 2-page report (Word and PDF) and `build_report.py`.

## How to reproduce

1. Install R (4.x) and open `poster_outputs/analysis.R` in RStudio, then Source it (or run
   `Rscript poster_outputs/analysis.R` from this folder). Missing packages (tidyverse, xgboost, caret,
   SHAPforxgboost, pROC) are installed automatically. A full run takes about 20 minutes on 10 cores.
2. Outputs are written to `poster_outputs/`. Seeds are fixed (123), so the numbers reproduce exactly.
3. Optional: `python report_build/build_report.py <link>` rebuilds the report (needs python-docx).
   `poster_build/build_poster.py` needs python-pptx and the course's Windsor A0 template (`Template_Windsor.pptx`,
   available on the course page, not redistributed here).

## Data sources

`Master.csv` combines published norms: humor ratings (Engelthaler & Hills, 2018), SUBTLEX-US frequency
(Brysbaert & New, 2009), iconicity (Winter et al., 2024), valence, arousal and dominance (Warriner et al., 2013),
concreteness (Brysbaert et al., 2014) and pronunciations from the CMU Pronouncing Dictionary (Weide, 1998).
Please cite the original sources when reusing these data. Full references are in `poster_outputs/results.md`.

## Method in brief

- Phoneme counts corrected for a substring-counting error, verified against CMUdict, converted to proportions.
- Targets: median split of humor ratings, and top vs bottom 10%.
- Models: phonemes (A); + surprisal, iconicity, length (B); + log frequency (C); meaning + controls (M); M + phonemes (M+P);
  phonological features (F); phonemes + word position (A+Pos).
- Stratified 10-fold cross-validation repeated 5 times; hyperparameters tuned on inner 3-fold CV inside each training fold.
- Permutation baselines, paired Wilcoxon tests on fold-level AUC, a residual test, and SHAP values on test folds.
