# Generative AI and Mortgage Underwriting: Replication Code

Code and data to reproduce every table, figure, and in-text statistic in
Bowen, Price, Stein, and Yang (2026), "Generative AI and the Evolution of
Mortgage Underwriting: Measuring and Mitigating Racial Disparities," *The
Journal of Real Estate Finance and Economics*
([journal article](https://link.springer.com/article/10.1007/s11146-026-10085-4);
[paper page](https://bowen.finance/research/ai-mortgage-underwriting/), with the
PDF and SSRN version).

The study is an audit experiment. Real 2022 HMDA loan applications are sent to
large language models (LLMs) while the applicant's race (or a proxy for it:
a name or a city) and credit score are varied. The models' approval and
interest-rate recommendations are then compared. [EXHIBITS.md](EXHIBITS.md)
lists every experiment and exhibit and where each is produced.

## Pipeline

| Step | Script | What it does | Output |
|---|---|---|---|
| 1 | `01_get_data.py` | Downloads the 2022 HMDA LAR file (880 MB) from the CFPB, applies the sample restrictions, and checks the result against the file used in the paper | `input_data/2022_public_lar_csv_filtered.zip` |
| 2 | `02_get_experiment_results.py` | Draws the 1,000 applications, builds every prompt in the paper (170,000), and sends them to the LLMs through Expected Parrot | `output_data/sample_1000.csv`, `output_data/experiment_results.csv` |
| 3 | `03_analysis.do` | Estimates everything in the paper | `exhibits/` (tables, figures, and the log `03_analysis.log`) |

Step 2 cannot reproduce the paper's LLM responses, because most of the models
have been retired (see [below](#rerunning-the-llm-calls)). The paper's responses
are distributed as `output_data/experiment_results.csv`, so replication runs
steps 1 and 3 and uses the distributed responses in place of step 2.

## Replicating the paper

1. Set up Python (see [Software](#software)) and run step 1 (only used if you run step 2):

   ```bash
   python 01_get_data.py
   ```

   It downloads the raw file into `raw_data/` (skipped if already there),
   filters it, and prints whether the output is identical to the file used in
   the paper. It needs about 12 GB of RAM. Alternatively, download
   `2022_public_lar_csv_filtered.zip` from this repository's GitHub release
   into `input_data/`.

2. Download `experiment_results.csv` from this repository's GitHub release
   into `output_data/`. (`output_data/sample_1000.csv` and everything in
   `input_data/` other than the LAR file are already in the repository.)

3. From the repository root, run in Stata:

   ```stata
   do 03_analysis.do
   ```

   All exhibits and the log are written to `exhibits/`, named by their number
   in the paper (`table3_panelA.tex`, `figure4.eps`, ...). Section 12 of the
   log prints the in-text statistics.

## Rerunning the LLM calls (step 2)

To collect new responses instead of using the distributed ones, put your
Expected Parrot key in a `.env` file at the repository root
(`EXPECTED_PARROT_API_KEY=...`) and run step 2 once:

```bash
python 02_get_experiment_results.py
```

This one call sends all 170,000 prompts and writes
`output_data/experiment_results.csv`, overwriting the distributed file, in the
same format. It saves results in chunks under `output_data/edsl_runs/`, so an
interrupted run can be restarted with the same command.

Each prompt is a single free-text EDSL question whose text is the complete
Figure 2 prompt. The model receives exactly that text, with no system prompt
or added instructions (the script checks this), and its reply is stored as-is.
Replies not in the requested `approval,rate` format are re-sent up to 10 times.

Expect different results from the paper:
- **Retired models.** As of November 2026, these are no longer served:
  `gpt-4-0125-preview` (the baseline LLM), `gpt-4-0613`,
  `gpt-4-turbo-2024-04-09`, the Claude 3 models, Groq's `llama3-70b-8192`, and
  `deepseek-chat-v3.1`. Calls to them fail and their rows are left empty. The
  `MODELS` table in the script records the paper's endpoint IDs and how EDSL
  reaches each model today.
- **Nondeterminism.** Responses vary even at temperature 0.
- **Call settings.** EDSL does not pass OpenAI's `seed=42`. The 2026 models the
  paper reached through OpenRouter are reached through their developers' APIs
  (or DeepInfra for the open-weight models). Models that reason before
  answering can use up the paper's `max_tokens` (20 for OpenAI and OpenRouter
  calls) before returning text; raise it with `--max-tokens`.

Options for testing. Their output files get a suffix (`_n2`, `_standin`,
`_subset`), so they never overwrite the full results:

```bash
python 02_get_experiment_results.py --n-loans 2                      # first 2 loans of every arm
python 02_get_experiment_results.py --blocks names --models gpt-4-0125-preview
python 02_get_experiment_results.py --n-loans 2 --stand-in anthropic:claude-haiku-5-5 openai:gpt-6-luna
```

`--stand-in` sends every call to cheap current models to exercise the pipeline;
those results are not substitutes for the paper's models.

### How the responses in `output_data/experiment_results.csv` were obtained by the authors

The paper's responses were collected in 2024-2026 by calling provider APIs directly. The Internet
Appendix shows the call functions used by the authors. The original code is available upon request but is somewhat clunky. 

In lieu of my janky human made 2024 code, I asked Opus 5.5 to convert the 02_ file to show how it could take advantage of 
Expected Parrot to collect LLM replies; its tooling is superior to my homebrewed stuff, and certainly would run our experiments quickly. 
I'm not 100% sure Opus 5.5 wrote code that works - it's code style with Expected Parrot functions is pretty ungainly, don't hold that 
against the package - but Opus ran several tests that made sense and passed a few I suggested. 
I like Expected Parrot and wanted to share it! 

## Software

**Python.** Steps 1 and 2 were run with Python 3.11.16 on Windows 11. The
environment is pinned in `environment.yml` (direct dependencies) and
`requirements.lock.txt` (every package):

```bash
conda env create -f environment.yml && conda activate genai_mortgages
# or
uv venv --python 3.11.16 && uv pip install -r requirements.lock.txt
```

Step 1's output was also checked to be identical under pandas 2.2.3 (Python 3.13.5).

**Stata.** Step 3 was run with StataNow/MP 19.5 (Windows). Missing packages are
installed automatically. The versions used were reghdfe 6.13.1, ftools 2.50.0,
center 1.10, coefplot 1.8.8, binscatter 7.02, winsor 1.3.0, estout 3.31,
grc1leg 1.0.5, and schemepack (for the `white_hue` scheme). The top of the log
records the versions used in each run.
Table A1 uses Stata's Python integration to read the LAR file; `python query`
must point to a Python with pandas (we used Python 3.13.5 with pandas 2.2.3).

## Data

- **HMDA**: 2022 snapshot national loan-level dataset, CFPB/FFIEC,
  <https://ffiec.cfpb.gov/data-publication/snapshot-national-loan-level-dataset/2022>.
- **Names** (`input_data/validated_names.csv`): Crabtree, Kim, Gaddis, et al.
  (2023), "Validated names for experimental studies on race and ethnicity,"
  *Scientific Data* 10, 130. Only names that more than 80% of respondents
  perceived as Black or white are used.
- **Cities** (`input_data/state_racial_cities.csv`): for each state, the places
  with 50,000+ residents that have the highest and lowest Black population
  share in the 2020 Census (P.L. 94-171 redistricting data, Census API
  `2020/dec/pl`, variables `P1_001N` and `P1_004N`). West Virginia has no such
  place, so its city-experiment prompts read "City: nan", as in the original
  runs.
- **Freddie Mac** (`input_data/freddie_hmda_sample_1000.csv`): the 1,000 HMDA
  loans used in Experiments 7A and 7B (Tables 7-9, Figure 5), matched to Freddie
  Mac's Single-Family Loan-Level Dataset (2022 originations, performance through
  2024Q3). For each loan: the HMDA loan ID, Freddie Mac loan sequence number,
  credit score, whether the loan was ever 30+ days delinquent, and the HMDA
  fields used in the prompts and analysis.

## Repository layout

```
01_get_data.py                  download and filter the 2022 LAR file
02_get_experiment_results.py    run the experiments through Expected Parrot (EDSL)
03_analysis.do                  all tables, figures, in-text numbers -> exhibits/
EXHIBITS.md                     experiments and exhibits, with their files
environment.yml                 pinned conda environment
requirements.txt                pinned direct dependencies
requirements.lock.txt           every package in the environment used
input_data/                     names, cities, Freddie Mac sample; filtered LAR (release)
output_data/                    sample_1000.csv; experiment_results.csv (release)
exhibits/                       generated tables (.tex), figures (.eps/.png), log
```
