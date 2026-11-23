# What makes a word sound funny?

Mithun Thangaraj, EL161 Machine Learning for Linguistics

Do the sounds of English words predict humor ratings beyond word frequency and meaning?
XGBoost classifiers on phoneme proportions, 10-fold cross-validation repeated 5 times, permutation baselines and SHAP.

- `analysis.R`: full analysis
- `data/`: Master.csv (humor ratings, phoneme counts, norms) and cmudict.dict
- `output/`: result tables and figures
- `poster.pdf`, `report.pdf`

Run with `Rscript analysis.R` (R packages: tidyverse, xgboost, caret, SHAPforxgboost, pROC). Takes about 20 minutes.

Data come from published norms: Engelthaler & Hills (2018), Brysbaert & New (2009), Warriner et al. (2013),
Brysbaert et al. (2014), Winter et al. (2024), and the CMU Pronouncing Dictionary (Weide, 1998).
