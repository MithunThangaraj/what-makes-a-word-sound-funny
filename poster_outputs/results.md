# Results: What Makes a Word Sound Funny?

Permutations: 200 shuffles for models A and C; 100 for the extension models M, M+P, A+Pos and F (a full run with 200 exceeded the 25-minute budget); 100 for the residual test.

All numbers in this file were written by `analysis.R`. Run time: 19.6 minutes (nested CV 2.8 min, permutation baseline 15.4 min, residual test 0.8 min, 9 parallel workers).

## 1. Data

- Rows in Master.csv: 42222 (known bad row 41831 dropped)
- Rows with a humor rating: 4852
- Rows removed for missing or zero phoneme length / phoneme counts: 0; duplicated words removed: 0
- **Final cleaned N = 4852**
- Phoneme count fix: the raw count columns were built by substring matching (W also counted UW/OW/AW; Y counted IY/AY/EY/OY; R counted ER; T, D, S, Z counted TH, DH, SH, ZH; N and G counted NG). Rows whose counts sum to Phoneme_Length: 37.1% before the fix, 100.0% after; rows still mismatched: 0
- CMUdict check (random 50 words, seed 123): 50/50 match the first CMUdict pronunciation exactly (50/50 match some pronunciation); no rebuild needed
- CMUdict check, all 4852 words: 4825 match the first pronunciation, 15 match a variant, 12 mismatch, 0 not in CMUdict (mismatches: acid, estate, esteem, extreme, interest, libel, module, niche, office, regard, thesis, tulip; these look like alternative pronunciations)
- Humor rating: mean 2.40, SD 0.43, median 2.33, range 1.18 to 4.32
- **Modelling N (complete cases on all model C features, shared by A, B, C) = 4518**
- Median split: funny = rating > 2.33; N = 4518 (2196 funny, 2322 not funny)
- Extreme groups: funny = rating >= 2.97 (top 10%), not funny = rating <= 1.93 (bottom 10%); N = 894 (434 funny, 460 not funny)

## 2. Descriptive correlations with humor

| Variable | r | 95% CI | p | n |
|---|---|---|---|---|
| Phoneme_Length | -0.086 | [-0.114, -0.058] | < .001 | 4852 |
| Average_Surprisal | 0.081 | [0.053, 0.109] | < .001 | 4852 |
| Winter_Ico | 0.259 | [0.231, 0.286] | < .001 | 4518 |
| log_freq | -0.269 | [-0.295, -0.243] | < .001 | 4852 |
| Valence_Glasgow | 0.249 | [0.208, 0.289] | < .001 | 2066 |
| Recog_Memory | 0.298 | [0.266, 0.330] | < .001 | 3173 |

Phoneme proportions (Pearson r with humor, BH-FDR corrected), sorted:

| Phoneme | r | p | q (FDR) | n |
|---|---|---|---|---|
| UW | 0.126 | < .001 | < .001 | 4852 |
| AH | 0.073 | < .001 | < .001 | 4852 |
| G | 0.070 | < .001 | < .001 | 4852 |
| B | 0.069 | < .001 | < .001 | 4852 |
| P | 0.054 | < .001 | < .001 | 4852 |
| W | 0.054 | < .001 | < .001 | 4852 |
| AA | 0.048 | < .001 | .002 | 4852 |
| NG | 0.047 | .001 | .003 | 4852 |
| IY | 0.044 | .002 | .004 | 4852 |
| K | 0.042 | .003 | .007 | 4852 |
| HH | 0.034 | .017 | .029 | 4852 |
| IH | 0.032 | .024 | .041 | 4852 |
| M | 0.024 | .102 | .159 | 4852 |
| SH | 0.020 | .163 | .244 | 4852 |
| Z | 0.020 | .170 | .245 | 4852 |
| F | 0.018 | .203 | .283 | 4852 |
| AE | 0.018 | .219 | .294 | 4852 |
| CH | 0.017 | .226 | .294 | 4852 |
| JH | 0.015 | .282 | .336 | 4852 |
| Y | 0.015 | .284 | .336 | 4852 |
| OW | 0.012 | .393 | .451 | 4852 |
| UH | 0.005 | .713 | .772 | 4852 |
| ER | 0.001 | .929 | .954 | 4852 |
| OY | 0.000 | .992 | .992 | 4852 |
| L | -0.004 | .773 | .815 | 4852 |
| DH | -0.010 | .486 | .541 | 4852 |
| AW | -0.016 | .260 | .328 | 4852 |
| ZH | -0.027 | .057 | .092 | 4852 |
| D | -0.039 | .007 | .013 | 4852 |
| S | -0.043 | .003 | .006 | 4852 |
| TH | -0.049 | < .001 | .002 | 4852 |
| AO | -0.054 | < .001 | < .001 | 4852 |
| T | -0.055 | < .001 | < .001 | 4852 |
| V | -0.059 | < .001 | < .001 | 4852 |
| AY | -0.068 | < .001 | < .001 | 4852 |
| N | -0.074 | < .001 | < .001 | 4852 |
| EY | -0.093 | < .001 | < .001 | 4852 |
| R | -0.106 | < .001 | < .001 | 4852 |
| EH | -0.114 | < .001 | < .001 | 4852 |

Phonemes with FDR q < .05: 23 of 39 (positive: AH, AA, IY, B, K, HH, IH, G, W, UW, P, NG; negative: EY, T, EH, AY, AO, S, D, N, R, TH, V)

## 3. Cross-validated performance (mean ± SD over 50 outer test folds)

Model C_noSurp is a supplementary ablation (model C without Average_Surprisal).

| Target | Model | N | Accuracy | AUC | Precision | Recall | F1 |
|---|---|---|---|---|---|---|---|
| median | A | 4518 | 0.599 ± 0.021 | 0.631 ± 0.023 | 0.598 ± 0.025 | 0.534 ± 0.032 | 0.564 ± 0.026 |
| median | B | 4518 | 0.619 ± 0.020 | 0.661 ± 0.022 | 0.637 ± 0.029 | 0.506 ± 0.034 | 0.564 ± 0.026 |
| median | C | 4518 | 0.657 ± 0.020 | 0.717 ± 0.022 | 0.659 ± 0.023 | 0.611 ± 0.032 | 0.633 ± 0.024 |
| median | C_noSurp | 4518 | 0.659 ± 0.020 | 0.718 ± 0.022 | 0.662 ± 0.024 | 0.612 ± 0.028 | 0.635 ± 0.022 |
| median | M | 4438 | 0.668 ± 0.024 | 0.735 ± 0.024 | 0.659 ± 0.027 | 0.640 ± 0.035 | 0.649 ± 0.027 |
| median | MP | 4438 | 0.678 ± 0.023 | 0.751 ± 0.024 | 0.671 ± 0.024 | 0.649 ± 0.035 | 0.659 ± 0.027 |
| median | M_NRC | 3362 | 0.677 ± 0.029 | 0.737 ± 0.029 | 0.658 ± 0.037 | 0.581 ± 0.045 | 0.616 ± 0.037 |
| median | MP_NRC | 3362 | 0.683 ± 0.025 | 0.746 ± 0.027 | 0.665 ± 0.032 | 0.589 ± 0.041 | 0.624 ± 0.033 |
| median | APos | 4518 | 0.604 ± 0.023 | 0.641 ± 0.024 | 0.602 ± 0.026 | 0.548 ± 0.033 | 0.574 ± 0.027 |
| median | F | 4518 | 0.589 ± 0.024 | 0.621 ± 0.025 | 0.590 ± 0.030 | 0.506 ± 0.031 | 0.544 ± 0.026 |
| extreme | A | 894 | 0.715 ± 0.050 | 0.785 ± 0.046 | 0.708 ± 0.059 | 0.710 ± 0.068 | 0.707 ± 0.051 |
| extreme | B | 894 | 0.747 ± 0.044 | 0.818 ± 0.039 | 0.754 ± 0.054 | 0.715 ± 0.060 | 0.733 ± 0.048 |
| extreme | C | 894 | 0.784 ± 0.047 | 0.879 ± 0.034 | 0.782 ± 0.050 | 0.773 ± 0.066 | 0.776 ± 0.051 |
| extreme | C_noSurp | 894 | 0.782 ± 0.044 | 0.878 ± 0.037 | 0.779 ± 0.050 | 0.773 ± 0.061 | 0.775 ± 0.047 |
| extreme | M | 868 | 0.843 ± 0.041 | 0.917 ± 0.030 | 0.832 ± 0.051 | 0.838 ± 0.060 | 0.834 ± 0.044 |
| extreme | MP | 868 | 0.853 ± 0.044 | 0.931 ± 0.030 | 0.843 ± 0.060 | 0.850 ± 0.061 | 0.844 ± 0.047 |
| extreme | M_NRC | 630 | 0.845 ± 0.052 | 0.922 ± 0.037 | 0.818 ± 0.074 | 0.780 ± 0.098 | 0.795 ± 0.072 |
| extreme | MP_NRC | 630 | 0.863 ± 0.046 | 0.930 ± 0.035 | 0.840 ± 0.071 | 0.806 ± 0.085 | 0.819 ± 0.063 |
| extreme | APos | 894 | 0.733 ± 0.046 | 0.803 ± 0.044 | 0.732 ± 0.051 | 0.712 ± 0.073 | 0.720 ± 0.052 |
| extreme | F | 894 | 0.693 ± 0.055 | 0.759 ± 0.056 | 0.699 ± 0.066 | 0.653 ± 0.078 | 0.673 ± 0.061 |

Pooled confusion matrices (summed over 50 test folds; each word counted 5 times):

| Target | Model | TP | FP | TN | FN |
|---|---|---|---|---|---|
| median | A | 5863 | 3948 | 7662 | 5117 |
| median | B | 5558 | 3174 | 8436 | 5422 |
| median | C | 6705 | 3478 | 8132 | 4275 |
| median | C_noSurp | 6716 | 3439 | 8171 | 4264 |
| median | M | 6820 | 3531 | 8004 | 3835 |
| median | MP | 6914 | 3394 | 8141 | 3741 |
| median | M_NRC | 4366 | 2272 | 7018 | 3154 |
| median | MP_NRC | 4429 | 2235 | 7055 | 3091 |
| median | APos | 6019 | 3976 | 7634 | 4961 |
| median | F | 5554 | 3866 | 7744 | 5426 |
| extreme | A | 1541 | 647 | 1653 | 629 |
| extreme | B | 1552 | 512 | 1788 | 618 |
| extreme | C | 1678 | 472 | 1828 | 492 |
| extreme | C_noSurp | 1677 | 480 | 1820 | 493 |
| extreme | M | 1714 | 352 | 1943 | 331 |
| extreme | MP | 1738 | 333 | 1962 | 307 |
| extreme | M_NRC | 955 | 218 | 1707 | 270 |
| extreme | MP_NRC | 987 | 194 | 1731 | 238 |
| extreme | APos | 1545 | 570 | 1730 | 625 |
| extreme | F | 1417 | 618 | 1682 | 753 |

Best model by mean AUC: median = model C; extreme = model C

### Hyperparameters chosen by the inner 3-fold CV

| Target | Model | Most chosen max_depth | Most chosen eta | Folds chosen (of 50) | nrounds median [min, max] |
|---|---|---|---|---|---|
| median | A | 4 | 0.05 | 12 | 105.5 [40, 310] |
| median | B | 4 | 0.05 | 17 | 116 [21, 321] |
| median | C | 2 | 0.05 | 18 | 167.5 [51, 377] |
| median | C_noSurp | 4 | 0.05 | 21 | 139 [46, 394] |
| median | M | 2 | 0.05 | 23 | 116 [25, 287] |
| median | MP | 4 | 0.05 | 21 | 203 [77, 503] |
| median | M_NRC | 2 | 0.05 | 29 | 196 [39, 320] |
| median | MP_NRC | 2 | 0.05 | 28 | 245.5 [90, 407] |
| median | APos | 4 | 0.05 | 11 | 169.5 [57, 607] |
| median | F | 4 | 0.05 | 27 | 58.5 [8, 278] |
| extreme | A | 2 | 0.05 | 20 | 100 [15, 262] |
| extreme | B | 2 | 0.1 | 18 | 115.5 [12, 336] |
| extreme | C | 2 | 0.05 | 27 | 182 [85, 359] |
| extreme | C_noSurp | 2 | 0.1 | 25 | 150.5 [40, 326] |
| extreme | M | 2 | 0.1 | 25 | 163 [78, 350] |
| extreme | MP | 2 | 0.1 | 23 | 265.5 [89, 459] |
| extreme | M_NRC | 2 | 0.1 | 14 | 129.5 [38, 351] |
| extreme | MP_NRC | 4 | 0.05 | 16 | 216 [78, 485] |
| extreme | APos | 2 | 0.05 | 14 | 114 [23, 326] |
| extreme | F | 2 | 0.1 | 18 | 74.5 [8, 213] |

## 4. Permutation baseline (200 label shuffles, single stratified 10-fold CV each, same nested tuning)

| Target | Model | Observed AUC | Permuted AUC mean ± SD | Permuted AUC max | Shuffles >= observed | Empirical p |
|---|---|---|---|---|---|---|
| extreme | A | 0.785 | 0.498 ± 0.021 | 0.560 | 0 | 0.0050 |
| extreme | APos | 0.803 | 0.497 ± 0.022 | 0.581 | 0 | 0.0099 |
| extreme | C | 0.879 | 0.499 ± 0.024 | 0.573 | 0 | 0.0050 |
| extreme | F | 0.759 | 0.501 ± 0.023 | 0.560 | 0 | 0.0099 |
| extreme | M | 0.917 | 0.500 ± 0.026 | 0.560 | 0 | 0.0099 |
| extreme | MP | 0.931 | 0.498 ± 0.023 | 0.550 | 0 | 0.0099 |
| median | A | 0.631 | 0.501 ± 0.011 | 0.536 | 0 | 0.0050 |
| median | APos | 0.641 | 0.502 ± 0.011 | 0.536 | 0 | 0.0099 |
| median | C | 0.717 | 0.499 ± 0.010 | 0.526 | 0 | 0.0050 |
| median | F | 0.621 | 0.501 ± 0.012 | 0.528 | 0 | 0.0099 |
| median | M | 0.735 | 0.500 ± 0.010 | 0.524 | 0 | 0.0099 |
| median | MP | 0.751 | 0.500 ± 0.010 | 0.526 | 0 | 0.0099 |

Empirical p = (1 + number of shuffles with AUC >= observed) / (200 + 1). The smallest possible value is 0.0050.

## 5. Model comparison: paired Wilcoxon signed-rank tests on fold-level AUC

| Target | Comparison | Mean AUC diff | Median AUC diff | Folds better | V | p |
|---|---|---|---|---|---|---|
| median | B vs A | 0.0305 | 0.0295 | 48/50 | 1262.0 | < .001 |
| extreme | B vs A | 0.0329 | 0.0316 | 41/50 | 1157.0 | < .001 |
| median | C vs B | 0.0558 | 0.0567 | 49/50 | 1274.0 | < .001 |
| extreme | C vs B | 0.0609 | 0.0609 | 48/50 | 1269.0 | < .001 |
| median | C vs C_noSurp | -0.0011 | -0.0007 | 22/50 | 509.0 | .217 |
| extreme | C vs C_noSurp | 0.0008 | 0.0010 | 28/50 | 715.5 | .454 |
| median | MP vs M | 0.0157 | 0.0175 | 45/50 | 1237.0 | < .001 |
| extreme | MP vs M | 0.0132 | 0.0119 | 46/50 | 1217.0 | < .001 |
| median | MP_NRC vs M_NRC | 0.0086 | 0.0088 | 42/50 | 1180.0 | < .001 |
| extreme | MP_NRC vs M_NRC | 0.0087 | 0.0107 | 37/50 | 939.5 | .001 |
| median | APos vs A | 0.0105 | 0.0068 | 39/50 | 1092.0 | < .001 |
| extreme | APos vs A | 0.0185 | 0.0183 | 38/50 | 1112.0 | < .001 |
| median | F vs A | -0.0103 | -0.0128 | 17/50 | 294.0 | < .001 |
| extreme | F vs A | -0.0257 | -0.0211 | 12/50 | 227.0 | < .001 |

## 6. SHAP importance (mean |SHAP| over 50 test folds) and stability (% folds in top 10)

**Model A, Median split** (top 15)

| Rank | Feature | Mean abs SHAP | SD | % folds top 10 | Spearman(value, SHAP) |
|---|---|---|---|---|---|
| 1 | EH | 0.0919 | 0.0107 | 100 | -0.57 |
| 2 | R | 0.0817 | 0.0141 | 100 | -0.80 |
| 3 | AH | 0.0744 | 0.0110 | 100 | 0.63 |
| 4 | EY | 0.0734 | 0.0094 | 100 | -0.50 |
| 5 | T | 0.0718 | 0.0123 | 100 | -0.76 |
| 6 | UW | 0.0665 | 0.0094 | 100 | 0.41 |
| 7 | P | 0.0636 | 0.0084 | 100 | 0.31 |
| 8 | N | 0.0558 | 0.0113 | 94 | -0.74 |
| 9 | G | 0.0453 | 0.0087 | 90 | 0.46 |
| 10 | AY | 0.0413 | 0.0074 | 72 | -0.45 |
| 11 | D | 0.0317 | 0.0100 | 14 | -0.64 |
| 12 | IY | 0.0316 | 0.0085 | 12 | 0.39 |
| 13 | S | 0.0295 | 0.0063 | 4 | 0.31 |
| 14 | AO | 0.0276 | 0.0070 | 8 | -0.44 |
| 15 | B | 0.0263 | 0.0092 | 0 | 0.56 |

**Model C, Median split** (top 15)

| Rank | Feature | Mean abs SHAP | SD | % folds top 10 | Spearman(value, SHAP) |
|---|---|---|---|---|---|
| 1 | log frequency | 0.5072 | 0.0252 | 100 | -0.98 |
| 2 | Iconicity | 0.2762 | 0.0166 | 100 | 0.97 |
| 3 | Length | 0.1170 | 0.0127 | 100 | -0.87 |
| 4 | AH | 0.0881 | 0.0154 | 100 | 0.76 |
| 5 | R | 0.0668 | 0.0141 | 100 | -0.80 |
| 6 | EY | 0.0518 | 0.0103 | 94 | -0.50 |
| 7 | EH | 0.0500 | 0.0095 | 86 | -0.56 |
| 8 | UW | 0.0490 | 0.0093 | 92 | 0.42 |
| 9 | Surprisal | 0.0445 | 0.0125 | 74 | 0.61 |
| 10 | IY | 0.0404 | 0.0098 | 64 | 0.56 |
| 11 | P | 0.0355 | 0.0100 | 44 | 0.34 |
| 12 | AY | 0.0352 | 0.0082 | 26 | -0.45 |
| 13 | G | 0.0257 | 0.0080 | 2 | 0.46 |
| 14 | AO | 0.0247 | 0.0073 | 4 | -0.44 |
| 15 | TH | 0.0226 | 0.0070 | 2 | -0.27 |

**Model A, Extreme 10% vs 10%** (top 15)

| Rank | Feature | Mean abs SHAP | SD | % folds top 10 | Spearman(value, SHAP) |
|---|---|---|---|---|---|
| 1 | EH | 0.2788 | 0.0484 | 100 | -0.56 |
| 2 | N | 0.2584 | 0.0474 | 100 | -0.73 |
| 3 | R | 0.2107 | 0.0436 | 100 | -0.76 |
| 4 | AH | 0.1342 | 0.0394 | 100 | 0.60 |
| 5 | UW | 0.1258 | 0.0343 | 100 | 0.44 |
| 6 | P | 0.1131 | 0.0320 | 100 | 0.63 |
| 7 | EY | 0.1005 | 0.0244 | 96 | -0.48 |
| 8 | IY | 0.0863 | 0.0328 | 68 | 0.52 |
| 9 | T | 0.0808 | 0.0294 | 64 | -0.77 |
| 10 | S | 0.0675 | 0.0269 | 38 | -0.77 |
| 11 | W | 0.0667 | 0.0211 | 38 | 0.43 |
| 12 | AY | 0.0620 | 0.0221 | 26 | -0.37 |
| 13 | L | 0.0586 | 0.0227 | 28 | -0.15 |
| 14 | V | 0.0564 | 0.0220 | 20 | -0.33 |
| 15 | B | 0.0550 | 0.0182 | 14 | 0.58 |

**Model C, Extreme 10% vs 10%** (top 15)

| Rank | Feature | Mean abs SHAP | SD | % folds top 10 | Spearman(value, SHAP) |
|---|---|---|---|---|---|
| 1 | log frequency | 1.0358 | 0.0862 | 100 | -0.98 |
| 2 | Iconicity | 0.6358 | 0.0562 | 100 | 0.99 |
| 3 | Length | 0.3964 | 0.0498 | 100 | -0.68 |
| 4 | EH | 0.1952 | 0.0305 | 100 | -0.56 |
| 5 | N | 0.1822 | 0.0402 | 100 | -0.73 |
| 6 | R | 0.1708 | 0.0354 | 100 | -0.76 |
| 7 | Surprisal | 0.1418 | 0.0428 | 92 | -0.77 |
| 8 | IY | 0.1282 | 0.0274 | 88 | 0.59 |
| 9 | AH | 0.1151 | 0.0290 | 72 | 0.71 |
| 10 | S | 0.1048 | 0.0360 | 50 | -0.78 |
| 11 | UW | 0.0916 | 0.0300 | 36 | 0.46 |
| 12 | L | 0.0851 | 0.0334 | 22 | -0.73 |
| 13 | AY | 0.0808 | 0.0225 | 14 | -0.36 |
| 14 | AA | 0.0720 | 0.0216 | 4 | 0.53 |
| 15 | K | 0.0665 | 0.0325 | 6 | 0.65 |

## 7. Funny-leaning and unfunny-leaning phonemes (model A, median split)

Leaning = mean averaged SHAP value among words that contain the phoneme (phonemes in at least 30 words). Examples: the 8 highest-rated (funny) or lowest-rated (unfunny) words containing the phoneme, with ratings.

| Leaning | Phoneme | Words with it | Mean SHAP when present | Importance rank | Examples |
|---|---|---|---|---|---|
| funny | UW | 298 | 0.4987 | 6 | booty (4.32), hooter (4.12), booby (4.07), oomph (3.93), buffoon (3.89), douche (3.86), oodles (3.84), fruitcake (3.83) |
| funny | G | 347 | 0.2995 | 9 | gaggle (3.82), chug (3.73), dingo (3.68), boogie (3.68), groin (3.65), gobble (3.65), jiggle (3.65), piggy (3.56) |
| funny | W | 279 | 0.2067 | 16 | waddle (4.05), whimsy (3.80), weasel (3.69), quickie (3.69), weirdo (3.68), wallop (3.67), whiz (3.61), wad (3.59) |
| funny | P | 818 | 0.1473 | 7 | rump (3.74), pooch (3.68), wallop (3.67), yap (3.66), panties (3.65), polka (3.59), bop (3.58), striptease (3.57) |
| funny | NG | 210 | 0.1409 | 25 | tinkle (3.96), funk (3.75), hanky (3.74), dingo (3.68), honky (3.56), dinghy (3.53), dumpling (3.50), spunk (3.43) |
| unfunny | EY | 410 | -0.4098 | 4 | rape (1.18), pain (1.39), hate (1.44), slave (1.48), grade (1.53), racist (1.54), plague (1.58), dismay (1.59) |
| unfunny | EH | 547 | -0.3934 | 1 | torment (1.31), death (1.32), nightmare (1.33), neglect (1.38), revenge (1.44), terror (1.44), distress (1.48), dead (1.51) |
| unfunny | TH | 116 | -0.3907 | 21 | death (1.32), theft (1.57), bloodbath (1.61), loathing (1.65), author (1.67), health (1.68), breath (1.73), anthrax (1.76) |
| unfunny | AY | 333 | -0.2800 | 10 | nightmare (1.33), dislike (1.46), blind (1.57), die (1.67), silence (1.68), cry (1.70), typhoid (1.71), liar (1.73) |
| unfunny | V | 207 | -0.2572 | 17 | divorce (1.41), convict (1.42), revenge (1.44), slave (1.48), grievance (1.56), victim (1.57), conserve (1.58), grave (1.60) |

## 8. Does Average_Surprisal still contribute in model C?

| Target | Rank in C | Mean abs SHAP | % folds top 10 | Spearman(surprisal, SHAP) | AUC gain C over C_noSurp | Folds better | Wilcoxon p |
|---|---|---|---|---|---|---|---|
| extreme | 7 of 43 | 0.1418 | 92 | -0.77 | 0.0008 | 28/50 | .454 |
| median | 9 of 43 | 0.0445 | 74 | 0.61 | -0.0011 | 22/50 | .217 |

## 9. Extension 1: sound vs meaning

Coverage of candidate meaning columns among the 4852 rated words (main set needs at least 90% coverage):

| Column | N | Coverage % | Use |
|---|---|---|---|
| Valence_Warr | 4852 | 100.0 | main meaning set |
| Arousal_Warr | 4852 | 100.0 | main meaning set |
| Dominance_Warr | 4852 | 100.0 | main meaning set |
| Conc_Brys | 4731 | 97.5 | main meaning set |
| Emot_Assoc_Anger | 3524 | 72.6 | sensitivity analysis only (coverage below 90%) |
| Emot_Assoc_Anticipation | 3524 | 72.6 | sensitivity analysis only (coverage below 90%) |
| Emot_Assoc_Disgust | 3524 | 72.6 | sensitivity analysis only (coverage below 90%) |
| Emot_Assoc_Fear | 3524 | 72.6 | sensitivity analysis only (coverage below 90%) |
| Emot_Assoc_Joy | 3524 | 72.6 | sensitivity analysis only (coverage below 90%) |
| Emot_Assoc_Negative | 3524 | 72.6 | sensitivity analysis only (coverage below 90%) |
| Emot_Assoc_Positive | 3524 | 72.6 | sensitivity analysis only (coverage below 90%) |
| Emot_Assoc_Sadness | 3524 | 72.6 | sensitivity analysis only (coverage below 90%) |
| Emot_Assoc_Surprise | 3524 | 72.6 | sensitivity analysis only (coverage below 90%) |
| Emot_Assoc_Trust | 3524 | 72.6 | sensitivity analysis only (coverage below 90%) |
| Valence_Glasgow | 2066 | 42.6 | not used (Glasgow norms, low coverage) |

- Main meaning set: Valence_Warr, Arousal_Warr, Dominance_Warr, Conc_Brys.
- Dropped from the main set: Emot_Assoc_Anger, Emot_Assoc_Anticipation, Emot_Assoc_Disgust, Emot_Assoc_Fear, Emot_Assoc_Joy, Emot_Assoc_Negative, Emot_Assoc_Positive, Emot_Assoc_Sadness, Emot_Assoc_Surprise, Emot_Assoc_Trust (coverage 72.6%; requiring them would cut N from 4438 to 3362). They are used in a sensitivity analysis on N = 3362.
- Valence_Glasgow is not used (2066 words).
- **Sample with complete meaning features and controls: N = 4438** (median split: 2131 funny / 2307 not; extreme: N = 868, 409 funny / 459 not).
- M = meaning + log_freq + Winter_Ico + Phoneme_Length + Average_Surprisal; M+P = M + 39 phoneme proportions. Same folds for M and M+P (stratified 10 x 5, seed 123, nested tuning).

| Target | Model | N | Accuracy | AUC | F1 |
|---|---|---|---|---|---|
| median | M | 4438 | 0.668 ± 0.024 | 0.735 ± 0.024 | 0.649 ± 0.027 |
| median | M+P | 4438 | 0.678 ± 0.023 | 0.751 ± 0.024 | 0.659 ± 0.027 |
| median | M (+NRC) | 3362 | 0.677 ± 0.029 | 0.737 ± 0.029 | 0.616 ± 0.037 |
| median | M+P (+NRC) | 3362 | 0.683 ± 0.025 | 0.746 ± 0.027 | 0.624 ± 0.033 |
| extreme | M | 868 | 0.843 ± 0.041 | 0.917 ± 0.030 | 0.834 ± 0.044 |
| extreme | M+P | 868 | 0.853 ± 0.044 | 0.931 ± 0.030 | 0.844 ± 0.047 |
| extreme | M (+NRC) | 630 | 0.845 ± 0.052 | 0.922 ± 0.037 | 0.795 ± 0.072 |
| extreme | M+P (+NRC) | 630 | 0.863 ± 0.046 | 0.930 ± 0.035 | 0.819 ± 0.063 |

Paired Wilcoxon tests (fold-level AUC):

| Target | Comparison | Mean AUC diff | Folds better | V | p |
|---|---|---|---|---|---|
| median | M+P vs M | 0.0157 | 45/50 | 1237.0 | < .001 |
| extreme | M+P vs M | 0.0132 | 46/50 | 1217.0 | < .001 |
| median | M+P (+NRC) vs M (+NRC) | 0.0086 | 42/50 | 1180.0 | < .001 |
| extreme | M+P (+NRC) vs M (+NRC) | 0.0087 | 37/50 | 939.5 | .001 |

Permutation baseline for the extension models:

| Target | Model | Observed AUC | Permuted AUC mean ± SD | Shuffles | Shuffles >= observed | Empirical p |
|---|---|---|---|---|---|---|
| extreme | A+Pos | 0.803 | 0.497 ± 0.022 | 100 | 0 | 0.0099 |
| extreme | F | 0.759 | 0.501 ± 0.023 | 100 | 0 | 0.0099 |
| extreme | M | 0.917 | 0.500 ± 0.026 | 100 | 0 | 0.0099 |
| extreme | M+P | 0.931 | 0.498 ± 0.023 | 100 | 0 | 0.0099 |
| median | A+Pos | 0.641 | 0.502 ± 0.011 | 100 | 0 | 0.0099 |
| median | F | 0.621 | 0.501 ± 0.012 | 100 | 0 | 0.0099 |
| median | M | 0.735 | 0.500 ± 0.010 | 100 | 0 | 0.0099 |
| median | M+P | 0.751 | 0.500 ± 0.010 | 100 | 0 | 0.0099 |

### Residual test

Within each of the 50 outer folds (median-split folds of the meaning sample, N = 4438): linear model of the continuous humor rating on the M features, fitted on the training fold only; XGBoost regression (same nested tuning) on the 39 phoneme proportions predicts the training residuals; scored on test-fold residuals. Null: 100 shuffles of the phoneme rows, single 10-fold CV each.

- Linear meaning model alone, test-fold R² on the humor rating: 0.211 ± 0.030
- **Phonemes on residuals: test-fold R² = 0.063 ± 0.035; correlation r = 0.254 ± 0.067**
- Shuffled phonemes: R² = -0.001 ± 0.001 (max 0.002); mean r = -0.002
- Empirical p (R²) = 0.0099 (0 shuffles >= observed); empirical p (r) = 0.0099; smallest possible p = 0.0099

### SHAP for M+P: same sounds as model A?

| Target | Phoneme share of total mean abs SHAP (%) | Phonemes in top 10 | Top phoneme (rank) |
|---|---|---|---|
| extreme | 30.1 | 2 | N (8) |
| median | 30.3 | 3 | AH (7) |

- M+P funny-leaning (median split): UW, G, AH, IY, NG. Model A: UW, G, W, P, NG. Overlap: 3/5 (UW, G, NG).
- M+P unfunny-leaning: TH, AY, EY, EH, AO. Model A: EY, EH, TH, AY, V. Overlap: 4/5 (EY, EH, TH, AY).
- Across 37 phonemes (each in at least 30 words), mean SHAP when present in A vs M+P: Spearman rho = 0.91; same sign for 35/37.

**Model M+P, Median split** (top 15)

| Rank | Feature | Type | Mean abs SHAP | % folds top 10 | Spearman(value, SHAP) |
|---|---|---|---|---|---|
| 1 | log frequency | Lexical control | 0.5557 | 100 | -0.97 |
| 2 | Iconicity | Lexical control | 0.2927 | 100 | 0.97 |
| 3 | Valence | Meaning | 0.2503 | 100 | 0.94 |
| 4 | Concreteness | Meaning | 0.1812 | 100 | 0.98 |
| 5 | Arousal | Meaning | 0.1619 | 100 | 0.95 |
| 6 | Length | Lexical control | 0.1145 | 100 | -0.89 |
| 7 | AH | Phoneme | 0.0889 | 100 | 0.77 |
| 8 | Dominance | Meaning | 0.0759 | 96 | -0.53 |
| 9 | R | Phoneme | 0.0654 | 94 | -0.80 |
| 10 | UW | Phoneme | 0.0504 | 44 | 0.42 |
| 11 | EY | Phoneme | 0.0499 | 28 | -0.50 |
| 12 | EH | Phoneme | 0.0454 | 26 | -0.56 |
| 13 | AY | Phoneme | 0.0425 | 2 | -0.45 |
| 14 | Surprisal | Lexical control | 0.0368 | 10 | 0.34 |
| 15 | IY | Phoneme | 0.0339 | 0 | 0.56 |

## 10. Extension 2: position in the word

- Source: CMUdict first pronunciation, stress removed, whole-token matching; words without a CMUdict entry: 0.
- Features (74): first phoneme one-hot (33 phonemes with at least 10 words), last phoneme one-hot (29), two-phoneme endings with at least 50 words (11: AH M, AH N, AH S, AH T, IH K, IH NG, N D, N S, N T, S T, T ER), and the syllabic -le flag (consonant + AH L).
- Endings were added as candidate flags without looking at humor; their importance is judged by SHAP inside CV.

**-le ending vs other words (descriptive, all 4852 words):**

| Group | N | Mean humor | SD |
|---|---|---|---|
| -le ending | 222 | 2.510 | 0.459 |
| other words | 4630 | 2.391 | 0.423 |

- Welch t(239.4) = 3.79, p < .001; mean difference = 0.119 [95% CI 0.057, 0.181]; Cohen's d = 0.28
- 10 random -le words (seed 123), sorted by rating: tinkle (3.96), bubble (3.00), oral (2.79), uncle (2.45), steeple (2.43), wrestle (2.32), social (2.28), settle (1.84), dental (1.80), eagle (1.75)
- The phonological rule also includes -al/-el spellings. Split by spelling within the -le group:

| Group | N | Mean humor | SD |
|---|---|---|---|
| -le spelling (e.g. gaggle) | 119 | 2.622 | 0.502 |
| other spellings (e.g. social) | 103 | 2.381 | 0.365 |

- Spelled -le words vs words without the ending: Welch t(122.4) = 4.98, p < .001; Cohen's d = 0.54

**A+Pos vs A (same folds):**

| Target | Model | AUC | F1 |
|---|---|---|---|
| median | A | 0.631 ± 0.023 | 0.564 ± 0.026 |
| median | A+Pos | 0.641 ± 0.024 | 0.574 ± 0.027 |
| extreme | A | 0.785 ± 0.046 | 0.707 ± 0.051 |
| extreme | A+Pos | 0.803 ± 0.044 | 0.720 ± 0.052 |

| Target | Comparison | Mean AUC diff | Folds better | V | p |
|---|---|---|---|---|---|
| median | A+Pos vs A | 0.0105 | 39/50 | 1092.0 | < .001 |
| extreme | A+Pos vs A | 0.0185 | 38/50 | 1112.0 | < .001 |

Top position features in A+Pos by mean abs SHAP (rank among all 113 features):

| Target | Feature | Rank | Mean abs SHAP | % folds top 10 | Words with it | Mean SHAP when present |
|---|---|---|---|---|---|---|
| extreme | last: IY | 4 | 0.1905 | 100 | 67 | 1.384 |
| extreme | first: K | 19 | 0.0298 | 0 | 82 | -0.162 |
| extreme | -le ending | 21 | 0.0281 | 0 | 51 | 0.248 |
| extreme | ending: AH N | 24 | 0.0257 | 0 | 33 | -0.319 |
| extreme | last: N | 25 | 0.0256 | 0 | 70 | -0.154 |
| extreme | last: K | 26 | 0.0254 | 0 | 67 | 0.169 |
| extreme | last: T | 27 | 0.0249 | 2 | 131 | -0.080 |
| extreme | last: S | 28 | 0.0205 | 0 | 70 | -0.128 |
| median | last: IY | 8 | 0.0489 | 80 | 208 | 0.542 |
| median | first: K | 12 | 0.0334 | 8 | 445 | -0.166 |
| median | last: T | 17 | 0.0295 | 16 | 670 | -0.103 |
| median | first: AE | 26 | 0.0185 | 0 | 51 | -0.859 |
| median | first: T | 27 | 0.0170 | 0 | 272 | 0.139 |
| median | first: IH | 31 | 0.0147 | 0 | 47 | -0.732 |
| median | ending: AH N | 34 | 0.0113 | 0 | 164 | -0.152 |
| median | ending: IH NG | 35 | 0.0106 | 0 | 91 | -0.266 |

## 11. Extension 3: phonological features

Mapping (diphthongs classified by their first element; F, V and W coded labial; Y grouped with postalveolar; R coded alveolar):

| phoneme | type | voicing | manner | place | height | backness | rounded | diphthong |
|---|---|---|---|---|---|---|---|---|
| B | consonant | voiced | stop | labial |  |  |  |  |
| P | consonant | voiceless | stop | labial |  |  |  |  |
| D | consonant | voiced | stop | alveolar |  |  |  |  |
| T | consonant | voiceless | stop | alveolar |  |  |  |  |
| G | consonant | voiced | stop | velar |  |  |  |  |
| K | consonant | voiceless | stop | velar |  |  |  |  |
| CH | consonant | voiceless | affricate | postalveolar |  |  |  |  |
| JH | consonant | voiced | affricate | postalveolar |  |  |  |  |
| F | consonant | voiceless | fricative | labial |  |  |  |  |
| V | consonant | voiced | fricative | labial |  |  |  |  |
| TH | consonant | voiceless | fricative | dental |  |  |  |  |
| DH | consonant | voiced | fricative | dental |  |  |  |  |
| S | consonant | voiceless | fricative | alveolar |  |  |  |  |
| Z | consonant | voiced | fricative | alveolar |  |  |  |  |
| SH | consonant | voiceless | fricative | postalveolar |  |  |  |  |
| ZH | consonant | voiced | fricative | postalveolar |  |  |  |  |
| HH | consonant | voiceless | fricative | glottal |  |  |  |  |
| M | consonant | voiced | nasal | labial |  |  |  |  |
| N | consonant | voiced | nasal | alveolar |  |  |  |  |
| NG | consonant | voiced | nasal | velar |  |  |  |  |
| L | consonant | voiced | liquid | alveolar |  |  |  |  |
| R | consonant | voiced | liquid | alveolar |  |  |  |  |
| W | consonant | voiced | glide | labial |  |  |  |  |
| Y | consonant | voiced | glide | postalveolar |  |  |  |  |
| IY | vowel |  |  |  | high | front | unrounded | monophthong |
| IH | vowel |  |  |  | high | front | unrounded | monophthong |
| EY | vowel |  |  |  | mid | front | unrounded | diphthong |
| EH | vowel |  |  |  | mid | front | unrounded | monophthong |
| AE | vowel |  |  |  | low | front | unrounded | monophthong |
| AH | vowel |  |  |  | mid | central | unrounded | monophthong |
| ER | vowel |  |  |  | mid | central | unrounded | monophthong |
| AA | vowel |  |  |  | low | back | unrounded | monophthong |
| AO | vowel |  |  |  | mid | back | rounded | monophthong |
| UW | vowel |  |  |  | high | back | rounded | monophthong |
| UH | vowel |  |  |  | high | back | rounded | monophthong |
| OW | vowel |  |  |  | mid | back | rounded | diphthong |
| AW | vowel |  |  |  | low | central | unrounded | diphthong |
| AY | vowel |  |  |  | low | central | unrounded | diphthong |
| OY | vowel |  |  |  | mid | back | rounded | diphthong |

- 27 features, each the proportion of the word's phonemes that has the feature: vowel, voiced, voiceless, stop, fricative, affricate, nasal, liquid, glide, labial, dental, alveolar, postalveolar, velar, glottal, voiced stop, voiceless stop, voiced fricative, voiceless fricative, high, mid, low, front, central, back, rounded, diphthong.

**F vs A (same folds):**

| Target | Model | AUC | F1 |
|---|---|---|---|
| median | A | 0.631 ± 0.023 | 0.564 ± 0.026 |
| median | F | 0.621 ± 0.025 | 0.544 ± 0.026 |
| extreme | A | 0.785 ± 0.046 | 0.707 ± 0.051 |
| extreme | F | 0.759 ± 0.056 | 0.673 ± 0.061 |

| Target | Comparison | Mean AUC diff | Folds better | V | p |
|---|---|---|---|---|---|
| median | F vs A | -0.0103 | 17/50 | 294.0 | < .001 |
| extreme | F vs A | -0.0257 | 12/50 | 227.0 | < .001 |

**Model F, Median split** (all features; direction = Spearman between feature value and its SHAP)

| Rank | Feature | Mean abs SHAP | % folds top 10 | Spearman(value, SHAP) | Direction |
|---|---|---|---|---|---|
| 1 | alveolar | 0.1415 | 100 | -0.86 | toward not funny |
| 2 | front | 0.0847 | 100 | -0.88 | toward not funny |
| 3 | high | 0.0707 | 100 | 0.85 | toward funny |
| 4 | central | 0.0668 | 98 | 0.82 | toward funny |
| 5 | diphthong | 0.0640 | 100 | -0.75 | toward not funny |
| 6 | mid | 0.0632 | 98 | -0.94 | toward not funny |
| 7 | back | 0.0516 | 96 | 0.63 | toward funny |
| 8 | velar | 0.0498 | 98 | 0.25 | toward funny |
| 9 | labial | 0.0443 | 90 | 0.74 | toward funny |
| 10 | stop | 0.0380 | 72 | 0.41 | toward funny |
| 11 | voiced stop | 0.0308 | 26 | 0.75 | toward funny |
| 12 | liquid | 0.0257 | 6 | -0.81 | toward not funny |
| 13 | vowel | 0.0255 | 6 | -0.40 | toward not funny |
| 14 | voiceless | 0.0233 | 2 | 0.31 | toward funny |
| 15 | dental | 0.0221 | 2 | -0.30 | toward not funny |
| 16 | voiceless stop | 0.0220 | 4 | -0.67 | toward not funny |
| 17 | voiced | 0.0203 | 0 | 0.45 | toward funny |
| 18 | low | 0.0170 | 2 | 0.10 | toward funny |
| 19 | voiceless fricative | 0.0155 | 0 | 0.81 | toward funny |
| 20 | rounded | 0.0142 | 0 | 0.63 | toward funny |
| 21 | nasal | 0.0120 | 0 | -0.12 | toward not funny |
| 22 | postalveolar | 0.0107 | 0 | 0.26 | toward funny |
| 23 | fricative | 0.0094 | 0 | 0.36 | toward funny |
| 24 | glide | 0.0069 | 0 | 0.41 | toward funny |
| 25 | voiced fricative | 0.0068 | 0 | -0.25 | toward not funny |
| 26 | glottal | 0.0049 | 0 | 0.34 | toward funny |
| 27 | affricate | 0.0028 | 0 | -0.01 | toward not funny |

**Model F, Extreme 10% vs 10%** (all features; direction = Spearman between feature value and its SHAP)

| Rank | Feature | Mean abs SHAP | % folds top 10 | Spearman(value, SHAP) | Direction |
|---|---|---|---|---|---|
| 1 | alveolar | 0.4831 | 100 | -0.83 | toward not funny |
| 2 | high | 0.2645 | 100 | 0.83 | toward funny |
| 3 | front | 0.2283 | 100 | -0.77 | toward not funny |
| 4 | diphthong | 0.1710 | 100 | -0.72 | toward not funny |
| 5 | central | 0.1340 | 100 | 0.81 | toward funny |
| 6 | mid | 0.1160 | 94 | -0.92 | toward not funny |
| 7 | stop | 0.1120 | 100 | 0.58 | toward funny |
| 8 | labial | 0.0968 | 98 | 0.91 | toward funny |
| 9 | back | 0.0730 | 74 | 0.77 | toward funny |
| 10 | liquid | 0.0639 | 52 | -0.82 | toward not funny |
| 11 | nasal | 0.0620 | 46 | -0.87 | toward not funny |
| 12 | velar | 0.0394 | 10 | -0.16 | toward not funny |
| 13 | glide | 0.0334 | 10 | 0.47 | toward funny |
| 14 | vowel | 0.0329 | 6 | 0.54 | toward funny |
| 15 | voiceless | 0.0302 | 0 | 0.77 | toward funny |
| 16 | fricative | 0.0290 | 4 | -0.78 | toward not funny |
| 17 | voiced fricative | 0.0286 | 4 | -0.49 | toward not funny |
| 18 | voiced stop | 0.0278 | 0 | 0.81 | toward funny |
| 19 | voiced | 0.0270 | 0 | -0.65 | toward not funny |
| 20 | low | 0.0223 | 2 | 0.19 | toward funny |
| 21 | voiceless stop | 0.0132 | 0 | 0.37 | toward funny |
| 22 | rounded | 0.0129 | 0 | 0.00 | toward funny |
| 23 | postalveolar | 0.0121 | 0 | -0.49 | toward not funny |
| 24 | voiceless fricative | 0.0099 | 0 | -0.25 | toward not funny |
| 25 | dental | 0.0084 | 0 | -0.29 | toward not funny |
| 26 | affricate | 0.0053 | 0 | 0.35 | toward funny |
| 27 | glottal | 0.0022 | 0 | 0.06 | toward funny |

---

# Draft poster text (original A/B/C analysis; the final poster text is in poster_text.md)

## Introduction

- Sound symbolism: word sounds are not fully arbitrary; some sounds carry meaning (size, shape, emotion).
- Engelthaler & Hills (2018) collected humor ratings (1-5) for about 5,000 English words.
- Kilpatrick & Flaksman (2025): humorous words have higher phonemic surprisal and are more memorable, despite their positive valence.
- Open questions: which specific sounds make a word funny, and is it the sound or just that funny words are rare?

## Research Question

- Do specific phonemes predict whether an English word is rated funny?
- Does that effect survive controls for word frequency and iconicity?

## Data & Method

- 4852 words with humor ratings (Engelthaler & Hills, 2018); 4518 with complete features used for all models.
- Data check: raw phoneme counts double-counted symbols inside longer ARPABET symbols (e.g. W inside OW); corrected so counts sum to word length in 100.0% of words (was 37.1%).
- Features: proportions of 39 CMU phonemes (count / word length); phonemic surprisal; iconicity (Winter et al., 2024); length in phonemes; log10 word frequency (SUBTLEX-US; Brysbaert & New, 2009). Meaning: Warriner et al. (2013); concreteness: Brysbaert et al. (2014). Pronunciations: CMUdict (Weide, 1998).
- Targets: (a) median split at 2.33 (N = 4518); (b) top 10% vs bottom 10% (N = 894).
- Models (XGBoost, Chen & Guestrin, 2016): A = phonemes; B = A + surprisal, iconicity, length; C = B + frequency.
- Nested CV: stratified 10-fold x 5 repeats (50 test folds), same folds for every model.
- Tuning only inside each training fold: inner 3-fold CV over max_depth {2, 4, 6} x eta {0.05, 0.1}, nrounds by early stopping.
- Baseline: 200 label permutations rerun through the same pipeline (models A and C).
- Model comparison: paired Wilcoxon tests on fold-level AUC. Interpretation: SHAP (Lundberg & Lee, 2017) on test folds only.

## Results

- Humor correlates negatively with frequency (r = -0.27), positively with iconicity (r = 0.26) and positively with surprisal (r = 0.08).
- Valence r = 0.25 (n = 2066); recognition memory r = 0.30 (n = 3173).
- 23 of 39 phonemes correlate with humor after FDR correction.
- Median split AUC: A = 0.631, B = 0.661, C = 0.717; chance (permutation) = 0.500.
- Extreme 10% vs 10% AUC: A = 0.785, B = 0.818, C = 0.879; chance (permutation) = 0.499.
- Phonemes alone beat every permutation: empirical p = 0.005 and 0.005 (median split, extreme).
- Adding surprisal, iconicity and length (B vs A): median split +0.031 AUC (48/50 folds better, Wilcoxon p < .001); extreme +0.033 AUC (41/50 folds better, Wilcoxon p < .001).
- Adding frequency (C vs B): median split +0.056 AUC (49/50 folds better, Wilcoxon p < .001); extreme +0.061 AUC (48/50 folds better, Wilcoxon p < .001).
- Top SHAP features in model C (median split): log frequency, Iconicity, Length, AH, R.
- Funny-leaning phonemes: UW, G, W, P, NG. Unfunny-leaning: EY, EH, TH, AY, V.
- In model C, frequency: higher values push toward 'not funny' (Spearman value vs SHAP = -0.98); iconicity: higher values push toward 'funny' (0.97).
- Surprisal in model C (Median split): rank 9 of 43, top 10 in 74% of folds, Spearman value vs SHAP = 0.61; AUC of C minus C without surprisal = -0.0011 (Wilcoxon p .217).
- Surprisal in model C (Extreme 10% vs 10%): rank 7 of 43, top 10 in 92% of folds, Spearman value vs SHAP = -0.77; AUC of C minus C without surprisal = 0.0008 (Wilcoxon p .454).

## Discussion

- Sound alone carries information about humor: phoneme-only model A beats all 200 label-shuffled models on both targets.
- Frequency is the top SHAP feature and adds AUC on top of sound (C > B): rarer words are rated funnier.
- Some phonemes stay in the top 10 of model C in at least half of the folds (AH, R, EY, EH, UW, IY), so their effect is not explained away by frequency.
- Surprisal: the raw correlation matches Kilpatrick & Flaksman (2025): funnier words have higher phonemic surprisal (r = 0.08) and are better recognised (r = 0.30).
- But surprisal adds no predictive value once frequency, iconicity and length are controlled: AUC of C minus C without surprisal = -0.0011 (p .217, median split) and 0.0008 (p .454, extreme).
- Higher-surprisal words tend to be rarer (r = -0.16, p < .001), so the earlier surprisal effect may be partly driven by frequency.
- With frequency, iconicity and length controlled, the surprisal direction is unstable: toward 'funny' in the median split, toward 'not funny' in the extreme groups.
- The extreme-group task is easier than the median split, as expected when middling words are removed.

## Limitations

- Humor ratings exist for about 5,000 words; iconicity is missing for some, reducing N to 4518.
- Phoneme proportions ignore order, stress and syllable position; specific clusters may matter more than single sounds.
- The 50 repeated-CV folds overlap, so Wilcoxon p-values are optimistic (folds are not independent).
- Only 200 permutations: the smallest possible empirical p is 0.005.
- Phoneme effects may partly reflect meaning, not sound: unfunny-leaning words (pain, death, theft) are semantically negative. Valence ratings exist for only 2066 of 4852 words, so valence was not controlled in the main models.
- SHAP shows associations inside the model, not causal effects of sounds on humor; correlated features share credit.
- Surprisal here is an average of phoneme-bigram surprisals; other surprisal measures may behave differently.
- Only a median and an extreme split are modelled; a regression on the full 1-5 rating would use more information.

## Conclusion

- Best cross-validated AUC: 0.717 (median split) and 0.879 (extreme groups).
- Which sounds are funny: UW, G, W, P, NG; which are not: EY, EH, TH, AY, V.
- All estimates come from test folds never used for tuning, checked against a permutation baseline and SHAP stability across 50 folds.

## References

- Brysbaert, M., & New, B. (2009). Moving beyond Kučera and Francis. *Behavior Research Methods, 41*(4), 977-990.
- Brysbaert, M., Warriner, A. B., & Kuperman, V. (2014). Concreteness ratings for 40 thousand generally known English word lemmas. *Behavior Research Methods, 46*(3), 904-911.
- Chen, T., & Guestrin, C. (2016). XGBoost: A scalable tree boosting system. *Proceedings of KDD 2016*, 785-794.
- Engelthaler, T., & Hills, T. T. (2018). Humor norms for 4,997 English words. *Behavior Research Methods, 50*(3), 1116-1124.
- Kilpatrick, A., & Flaksman, M. (2025). The Exception of Humor: Iconicity, Phonemic Surprisal, Memory Recall, and Emotional Associations. *Proceedings of the 1st Workshop on Computational Humor (CHum)*, 1-8. ACL.
- Lundberg, S. M., & Lee, S.-I. (2017). A unified approach to interpreting model predictions. *NeurIPS 30*.
- Warriner, A. B., Kuperman, V., & Brysbaert, M. (2013). Norms of valence, arousal, and dominance for 13,915 English lemmas. *Behavior Research Methods, 45*(4), 1191-1207.
- Weide, R. (1998). *The CMU Pronouncing Dictionary*. Carnegie Mellon University.
- Winter, B., Lupyan, G., Perry, L. K., Dingemanse, M., & Perlman, M. (2024). Iconicity ratings for 14,000+ English words. *Behavior Research Methods, 56*, 1640-1655.
