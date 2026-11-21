# Exhibit punch list

Every table, figure, and data-dependent number in the paper and its appendices,
with the experiment(s) it uses and where it is produced. Experiment numbers match
Table 1 of the paper and the `$exp*` globals in `03_analysis.do`.

## Experiments (Table 1)

| Exp. | Description | Signal | Prompt | Model(s) | N | Stata global |
|---|---|---|---|---|---|---|
| 1 | Main | Race: Black, White | Baseline | GPT-4 Turbo (`gpt-4-0125-preview`) | 6,000 | `$exp1` |
| 2 | More demographics | Race: Asian, Black, Hispanic, White, None | Baseline | GPT-4 Turbo | 15,000 | `$exp2` |
| 3 | LLMs | Race: Black, White | Baseline | 16 LLMs (Appendix list) | 94,059 | `$exp3` |
| 4 | Names | Black name, White name | Baseline | GPT-4 Turbo | 6,000 | `$exp4` |
| 5 | Cities | Black city, White city | Baseline | GPT-4 Turbo (`gpt-4-turbo-2024-04-09`) | 6,000 | `$exp5` |
| 6A | Mitigation of Exp. 1 | Race | Baseline + Mitigation | GPT-4 Turbo | 12,000 | `$exp6a` |
| 6B | Alt. mitigation of Exp. 1 | Race | Baseline + Alt. (ECOA) mitigation | GPT-4 Turbo | 12,000 | `$exp6b` |
| 6C | Mitigation of Exp. 4 | Name | Baseline + Mitigation | GPT-4 Turbo | 12,000 | `$exp6c` |
| 6D | Mitigation of Exp. 5 | City | Baseline + Mitigation | GPT-4 Turbo (`gpt-4-turbo-2024-04-09`) | 12,000 | `$exp6d` |
| 7A | Actual score, race undisclosed | None | Baseline | GPT-4 Turbo | 1,000 | `$exp7a` |
| 7B | Actual score, race disclosed | Actual race | Baseline | GPT-4 Turbo | 1,000 | `$exp7b` |
| A1 | Age | Age 30, 50, 70 | Baseline | GPT-4 Turbo | 9,000 | `$expA1` |
| A2 | Gender | Female, Male | Baseline | GPT-4 Turbo | 6,000 | `$expA2` |
| 1R | Exp. 1 rerun, July 2024 (Table A2 cols 1-4) | Race | Baseline | GPT-4 Turbo, temp 0 | 6,000 | `$exp1R` |
| 1T | Exp. 1 rerun, July 2024 (Table A2 cols 5-8) | Race | Baseline | GPT-4 Turbo, temp 0.3 | 6,000 | `$exp1T` |

Experiments 1-6 and A1-A2 use the same 1,000 HMDA applications
(`output_data/sample_1000.csv`) with manipulated credit scores of 640, 715, and 790.
Experiments 7A-7B use 1,000 HMDA-Freddie Mac matched loans with their actual
credit scores (`input_data/freddie_hmda_sample_1000.csv`).
Experiments 2, 3, 6A and 6B reuse the Experiment 1 responses for their
baseline/GPT-4 Turbo cells; 6C reuses Exp. 4 and 6D reuses Exp. 5.

Exhibit files in `exhibits/` are named by their number in the paper. The last
column gives the filename the paper's LaTeX source currently `\input`s.

## Main-text tables

| # | Label | Content | Exp. | File | Paper's LaTeX file |
|---|---|---|---|---|---|
| 1 | `tab:experiments` | Experiment designs and N | all | none: hand-written LaTeX; the N column is printed in the log (section 1) | |
| 2 | `tab:summ_stats` | Panel A: HMDA sample stats | sample | `table2_panelA.tex` | `tab_sumstats_hmda_1000.tex` |
| 2 | | Panel B: LLM outcome stats by experiment | 1-6D | `table2_panelB.tex` | `tab_sumstats_experiments.tex` |
| 3 | `tab:main_results` | Panel A: race and approval, 5 cols | 1 | `table3_panelA.tex` | `tab_main_results_gpt_approval.tex` |
| 3 | | Panel B: race and interest rate, 5 cols | 1 | `table3_panelB.tex` | `tab_main_results_gpt_interest_rate.tex` |
| 4 | `tab:allrace_main` | Race/ethnicity vs. None, 4 cols | 2 | `table4.tex` | `tab_allrace_main.tex` |
| 5 | `tab:proxy_results` | Panel A: names, 4 cols | 4 | `table5_panelA.tex` | `tab_proxy_results_name.tex` |
| 5 | | Panel B: cities, 4 cols | 5 | `table5_panelB.tex` | `tab_proxy_results_city.tex` |
| 6 | `tab:mitigate_prompts` | Mitigation, 8 cols (Eq. 3) | 6A-6D | `table6.tex` | `tab_mitigate_prompts.tex` |
| 7 | `tab:rate_determinants` | LLM rate on score/DTI/LTV, no FE | 7A | `table7.tex` | `tab_rate_determinants.tex` |
| 8 | `tab:delinq` | Delinquency on rate spread / LLM rate / score | 7A | `table8.tex` | `tab_delinq.tex` |
| 9 | `tab:true_race` | Outcomes and true race, 8 cols | 7A, 7B | `table9.tex` | `tab_true_race.tex` |

## Main-text figures

| # | Label | Content | Exp. | File | Paper's LaTeX file |
|---|---|---|---|---|---|
| 1 | `fig:gptSelfEval` | ChatGPT screenshot (March 2024) | none | none: static image | `AskChatGPTifitdiscriminates.png` |
| 2 | `fig:prompt` | Prompt templates | none | none: static LaTeX; the prompt text is in `02_get_experiment_results.py` | |
| 3 | `fig:otherLLMs` | Coefficient plot, 16 LLMs (Eq. 1) | 3 | `figure3.eps` / `.png` | `fig_otherLLMs.eps` |
| 4 | `fig:mitigation` | Predicted outcomes by score, race, prompt (Eq. 4) | 6A | `figure4.eps` / `.png` | `fig_mitigation.eps` |
| 5 | `fig:gpt_rate_performance` | Binscatter, LLM rate vs. actual rate spread | 7A | `figure5.png` / `.eps` | `fig_gpt_rate_performance.png` |

## Appendix

| # | Label | Content | Exp. | File | Paper's LaTeX file |
|---|---|---|---|---|---|
| list | (untitled) | 16 LLMs, developer, release, endpoint ID | 3 | none: static LaTeX; the model list is `MODELS` in `02_get_experiment_results.py` | |
| A1 | `tab:hmda_subset_comparison` | Entire filtered HMDA vs. the 1,000 study loans | sample | `tableA1.tex` | `TA1_hmdacomp.tex` |
| A2 | `tab:main_robustness` | Exp. 1 rerun (July 2024) at temperature 0 and 0.3 | 1R, 1T | `tableA2.tex` | `tab_main_robustness.tex` |
| A3 | `tab:age_test` | Age and recommendations | A1 | `tableA3.tex` | `tab_age_test.tex` |
| A4 | `tab:gender_test` | Gender and recommendations | A2 | `tableA4.tex` | `tab_gender_test.tex` |
| A5 | `tab:otherLLMs` | Panel A (approval), models 1-8 | 3 | `tableA5_panelA_part1.tex` | `tab_otherLLMs_approv_p1.tex` |
| A5 | | Panel A (approval), models 9-16 | 3 | `tableA5_panelA_part2.tex` | `tab_otherLLMs_approv_p2.tex` |
| A5 | | Panel B (interest rate), models 1-8 | 3 | `tableA5_panelB_part1.tex` | `tab_otherLLMs_rate_p1.tex` |
| A5 | | Panel B (interest rate), models 9-16 | 3 | `tableA5_panelB_part2.tex` | `tab_otherLLMs_rate_p2.tex` |
| IA | (code listing) | API call functions used at collection | none | none: static LaTeX | |

## Numbers in the text that are not read directly off an exhibit

All are printed in `exhibits/03_analysis.log` under section 12 ("In-text statistics").
"Reproduces" means the log matches the number in the paper.

| Where | Statistic | Exp. | Status |
|---|---|---|---|
| Sec. 2.3 | Race effects persist at score 715 excluding 5% tails of LTV and DTI | 1 | Reproduces (approval -0.061, rate 0.346) |
| Sec. 3.3 fn | Power calc: 962 per group for a 3.7 pp difference | HMDA | 962 follows from the stated 7.4% rejection rate; the data give 7.2% (eligible population) or 7.7% (all filtered loans) |
| Sec. 3.3 | 92% approval, 4.98% rate, 27bp spread, DTI 37.2%, LTV ~80% | sample | Reproduces (Table 2A) |
| Sec. 3.3 | LLM approval 84-94%, rate 4.44-5.41% across experiments | 1-6D | Reproduces |
| Sec. 4.1 | Credit score equivalents ~120 pts (approval), ~30 pts (rate) | 1 | Reproduces (121, 31) |
| Sec. 4.1 | Score-654 example: 13.3 pp, 47bp, 5.61% vs 6.08%, $36,100 | 1 | Reproduces, using the text's $334,000 loan amount (not the mean of any file here: the study sample averages $398,050) |
| Sec. 4.2 | 13/16 negative approval coefficients (11 significant); 15/16 positive, significant rate coefficients | 3 | Reproduces |
| Sec. 4.2 | Average CSE 37 pts (approval), 15 pts (rate) | 3 | Reproduces |
| Sec. 4.2 | Answer rates: Llama 4 Scout ~86%; Claude 3 Opus 74% for Black applicants | 3 | Reproduces |
| Sec. 4.2 | Average approval 84% (52%-100%); average rate 5.4% (4.29%-6.98%) | 3 | Reproduces |
| Sec. 4.3 | Name approval gap 95% CI [0.4, 2.3] pp; city CI [-1.0, 0.2] pp | 4, 5 | Reproduces |
| Sec. 4.3 fn | Benjamini-Hochberg: all 5 significant proxy estimates survive | 3, 4, 5, A1, A2 | Reproduces |
| Sec. 5.1 | Mitigation p-values and % reductions | 6A-6D | Reproduces (Table 6 rows) |
| Sec. 5.1 fn | Mitigated race x score approval slope p = 0.47; rate slope 11.4bp, cut by 7.9bp, residual 3.5bp | 6A | Reproduces |
| Sec. 6.1, Fig. 5 | Slope 0.55, t = 14.46 | 7A | Slope reproduces. 14.46 is the OLS t that `binscatter, reportreg` prints. The caption calls it heteroskedasticity-robust; the robust t is 10.57 |
| Sec. 6.1 | Adding credit score cuts the LLM-rate delinquency coefficient by 78% | 7A | 77.4% at full precision; 78% from the rounded Table 8 coefficients |
| Sec. 6.2 fn | Black delinquency CIs [-7.3, 9.4] and [-11.0, 6.0] pp; 97 of 1,000 delinquent; t = 3.51 | 7A | Reproduces |
| Table A1 caption | 2,383,561 loans in the eligible population | HMDA | Reproduces (asserted in the code) |

## Differences from the paper's exhibit files

`03_analysis.do` reproduces every `.tex` exhibit file except two cells. In each,
the coefficient lies exactly on a rounding boundary (x.xxx5), because rates move
in 0.5-point steps, so floating-point summation order decides the third decimal:
- Table 4, column 3, Hispanic: 0.118 (paper 0.117)
- Table 6, column 2, Mitigation x BlackSignal: -0.215 (paper -0.214)

Figure 4 places the points at exactly 640/715/790. The original was offset by
about one point because it un-standardized using the whole dataset's mean.
