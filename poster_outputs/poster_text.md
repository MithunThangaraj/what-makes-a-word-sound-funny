# What Makes a Word Sound Funny?
### Sound Predicts Humor Beyond Frequency and Meaning

## COLUMN 1

### The question
- Funny words are often rare and have funny meanings. Do their sounds still predict humor?

### Background
- Sound symbolism: some sounds carry meaning.
- About 5,000 English words rated for humor, 1 to 5 (Engelthaler & Hills, 2018).
- Funny words have more surprising sounds and are easier to remember (Kilpatrick & Flaksman, 2025).

### Data & Method
- 4,438 words with humor, meaning (Warriner et al., 2013; Brysbaert et al., 2014), SUBTLEX-US frequency (Brysbaert & New, 2009) and iconicity (Winter et al., 2024).
- Words split into 39 speech sounds (CMUdict; Weide, 1998).
- Task: tell funnier from less funny words (top vs bottom half; top vs bottom 10%).
- XGBoost models, always scored on unseen words: 10-fold cross-validation, repeated 5 times.
- Key test: meaning model vs meaning + sounds on the same words.
- Chance: models trained on shuffled ratings.

## COLUMN 2

### Results
- Score (AUC): 0.5 = guessing, 1 = perfect.
- Sounds alone beat guessing: 0.63 (half split), 0.78 (top/bottom 10%); shuffled ratings: 0.50 (p = .005).
- Adding sounds to meaning raises the score from 0.735 to 0.751 and from 0.917 to 0.931.
- Sounds won 45 of 50 and 46 of 50 tests (p < .001).
- Sounds explain part of the humor meaning leaves unexplained (R² = 0.063; shuffled sounds: about 0, p = .010).
- Holds with emotion word lists added (42 of 50 tests, p < .001).
- Frequency, iconicity and meaning matter most; sounds carry 30% of the weight.

## COLUMN 3

### Which sounds?
- Funnier: "oo" (oomph), "g" (gaggle), "ng" (tinkle). Less funny: "ay" (pain), "e" (torment), "th" (death), "eye" (nightmare).
- Endings: a final "ee" (whimsy, hanky) and words spelled -le (gaggle, tinkle) are funnier.
- Vowels leaning funny: high, central, back; less funny: front, gliding, mid. Consonants leaning funny: back-of-tongue, lip; less funny: tongue-tip.

### What it means
- Sound adds a small but reliable piece of humor on top of meaning and frequency.
- Surprising sound sequences go with funnier words (r = 0.08; Kilpatrick & Flaksman, 2025), but add nothing beyond frequency: rarer words have more surprising sounds (r = -0.16).

### Limitations
- Meaning ratings miss some aspects of meaning, such as taboo or rude senses.
- Results show association, not cause.

### Conclusion
- Words like oomph, gaggle, tinkle are funny partly because of how they sound.

### References
- Brysbaert, M., & New, B. (2009). Moving beyond Kučera and Francis. *Behavior Research Methods, 41*(4), 977-990.
- Brysbaert, M., Warriner, A. B., & Kuperman, V. (2014). Concreteness ratings for 40 thousand generally known English word lemmas. *Behavior Research Methods, 46*(3), 904-911.
- Chen, T., & Guestrin, C. (2016). XGBoost: A scalable tree boosting system. *Proceedings of KDD 2016*, 785-794.
- Engelthaler, T., & Hills, T. T. (2018). Humor norms for 4,997 English words. *Behavior Research Methods, 50*(3), 1116-1124.
- Kilpatrick, A., & Flaksman, M. (2025). The Exception of Humor: Iconicity, Phonemic Surprisal, Memory Recall, and Emotional Associations. *Proceedings of the 1st Workshop on Computational Humor (CHum)*, 1-8. ACL.
- Lundberg, S. M., & Lee, S.-I. (2017). A unified approach to interpreting model predictions. *NeurIPS 30*.
- Warriner, A. B., Kuperman, V., & Brysbaert, M. (2013). Norms of valence, arousal, and dominance for 13,915 English lemmas. *Behavior Research Methods, 45*(4), 1191-1207.
- Weide, R. (1998). *The CMU Pronouncing Dictionary*. Carnegie Mellon University.
- Winter, B., Lupyan, G., Perry, L. K., Dingemanse, M., & Perlman, M. (2024). Iconicity ratings for 14,000+ English words. *Behavior Research Methods, 56*, 1640-1655.

---

### Recommended figures (6, made for a general audience)
1. `poster_fig_sounds.png` (column 1, bottom): which sounds go with funny words.
2. `poster_fig_models.png` (column 1, bottom): how well each model spots funny words.
3. `poster_fig_sound_vs_meaning.png` (column 2): the main result.
4. `poster_fig_residual.png` (column 2): sounds explain humor that meaning misses.
5. `poster_fig_what_matters.png` (column 2): what the meaning + sounds model relies on.
6. `poster_fig_sound_classes.png` (column 3): which kinds of sounds lean funny.

Word count (body text, excluding title, references and this section): 377.
