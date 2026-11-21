********************************************************************************
* 03_analysis.do
*
* Produces every table and figure in the paper, its appendix, and the numbers
* quoted in the text, from
*     output_data/experiment_results.csv          (02_get_experiment_results.py)
*     output_data/sample_1000.csv                 (02_get_experiment_results.py)
*     input_data/freddie_hmda_sample_1000.csv     (delinquency outcomes, Exps. 7A/7B)
*     input_data/2022_public_lar_csv_filtered.zip (01_get_data.py; Table A1 only)
*
* Outputs go to exhibits/, including this file's log (exhibits/03_analysis.log).
* Exhibit files are named by their number in the paper (table3_panelA.tex,
* figure4.eps, tableA5_panelB_part2.tex, ...); see EXHIBITS.md.
* Run from the repository root:   do 03_analysis.do
*
* Experiment numbers follow Table 1 of the paper; see EXHIBITS.md for the full
* exhibit list. Sections:
*    0. Setup and packages
*    1. Load data, define experiments ($exp1 ... $expA2), Table 1 N
*    2. Table 2   Summary statistics
*    3. Table 3   Race and recommendations                      (Exp. 1)
*    4. Table 4   Race, ethnicity, and recommendations          (Exp. 2)
*    5. Figure 3 and Table A5   Other LLMs                      (Exp. 3)
*    6. Table 5   Race proxies                                  (Exps. 4, 5)
*    7. Table 6 and Figure 4   Mitigation                       (Exps. 6A-6D)
*    8. Tables 7-9 and Figure 5   Actual credit scores          (Exps. 7A, 7B)
*    9. Table A1  HMDA universe vs. study sample
*   10. Table A2  Robustness: July 2024 rerun, temperature      (Exp. 1R, 1T)
*   11. Tables A3, A4   Age and gender                          (Exps. A1, A2)
*   12. In-text statistics
********************************************************************************

clear all
set more off
version 19
cap mkdir exhibits
cap log close _all
log using exhibits/03_analysis.log, text replace name(main) nomsg

********************************************************************************
* 0. SETUP AND PACKAGES
********************************************************************************

	foreach p in reghdfe ftools center coefplot binscatter winsor estout schemepack {
		cap which `p'
		if _rc & "`p'" == "schemepack" cap findfile scheme-white_hue.scheme
		if _rc ssc install `p', replace
	}
	cap which grc1leg
	if _rc net install grc1leg, from("http://www.stata.com/users/vwiggins") replace
	cap reghdfe, compile

	* record the software versions used in the log (no license or path details)
	di "Stata " c(stata_version) " (" c(edition_real) "), executable dated " c(born_date) ", " c(os)
	foreach p in reghdfe ftools center coefplot binscatter winsor estout grc1leg {
		qui findfile `p'.ado
		tempname fh
		file open `fh' using `"`r(fn)'"', read text
		file read `fh' line
		while r(eof) == 0 & substr(`"`macval(line)'"', 1, 2) != "*!" {
			file read `fh' line
		}
		file close `fh'
		di `"  `p': `macval(line)'"'
	}
python:
import sys, pandas
print(f"Stata's Python: {sys.version.split()[0]}, pandas {pandas.__version__}")
end

	* Stata's Python (pandas) is used only for Table A1, to read the 700 MB LAR file
	* without loading every column.

********************************************************************************
* 1. LOAD DATA AND DEFINE EXPERIMENTS
********************************************************************************

	import delimited using output_data/experiment_results.csv, clear bindquote(strict)
	foreach v in race gender name_race name_used city_race city_used loan_sequence_number {
		confirm string variable `v'
	}

	*---------------------------------------------------------------------
	* the demographic signal in each prompt
	*---------------------------------------------------------------------

	* `race` is the race shown in the prompt; for the name and city experiments
	* it is the race the name or city signals; "None" if the prompt has no race
	replace race = "None"    if missing(race)
	replace race = name_race if block == "names"
	replace race = city_race if block == "cities"

	label define race_c 1 "Asian" 2 "Black" 3 "Hispanic" 4 "None" 5 "White"
	encode race, gen(race_c) label(race_c)          // White (5) is the base category below

	encode gender, gen(gender_c)                    // 1 Female, 2 Male

	g mitigate   = prompt_version != "baseline"     // mitigation or alternative (ECOA) mitigation prompt
	g name_black = name_race == "Black" if block == "names"
	g city_black = city_race == "Black" if block == "cities"

	g actually_approved = action_taken == 1

	*---------------------------------------------------------------------
	* DTI: HMDA reports 36-49 exactly and buckets outside that range
	*---------------------------------------------------------------------

	replace debt_to_income_ratio = ""   if debt_to_income_ratio == "NA%"
	replace debt_to_income_ratio = "20" if debt_to_income_ratio == "<20%"
	replace debt_to_income_ratio = "60" if debt_to_income_ratio == ">60%"
	replace debt_to_income_ratio = "55" if debt_to_income_ratio == "50%-60%"
	replace debt_to_income_ratio = "25" if debt_to_income_ratio == "20%-<30%"
	replace debt_to_income_ratio = "33" if debt_to_income_ratio == "30%-<36%"
	replace debt_to_income_ratio = subinstr(debt_to_income_ratio,"%","",.)
	destring debt_to_income_ratio, replace

	*---------------------------------------------------------------------
	* labels (", z)" is appended when a variable is standardized)
	*---------------------------------------------------------------------

	lab var gpt_approval                 "Approval (LLM)"
	lab var gpt_interest_rate            "Rate (LLM)"
	lab var score                        "CreditScore (Exp."
	lab var actually_approved            "Approval (Actual)"
	lab var interest_rate                "Rate (Actual)"
	lab var rate_spread                  "Rate Spread (Actual)"
	lab var debt_to_income_ratio         "DTI (Actual"
	lab var combined_loan_to_value_ratio "LTV (Actual"
	lab var mitigate                     "Mitigation"
	lab var name_black                   "BlackName"
	lab var city_black                   "BlackCity"

	*---------------------------------------------------------------------
	* experiment globals (Table 1)
	*---------------------------------------------------------------------

	global base_llm   model == "gpt-4-0125-preview"
	global bw         inlist(race, "Black", "White")

	global exp1   block == "race" & $base_llm & prompt_version == "baseline" & $bw
	global exp2   block == "race" & $base_llm & prompt_version == "baseline"
	global exp3   block == "race"             & prompt_version == "baseline" & $bw
	global exp4   block == "names"  & prompt_version == "baseline"
	global exp5   block == "cities" & prompt_version == "baseline"
	global exp6a  block == "race" & $base_llm & inlist(prompt_version, "baseline", "mitigate")      & $bw
	global exp6b  block == "race" & $base_llm & inlist(prompt_version, "baseline", "mitigate_ecoa") & $bw
	global exp6c  block == "names"
	global exp6d  block == "cities"
	global exp7a  block == "actual_credit" & race == "None"
	global exp7b  block == "actual_credit" & race != "None"
	global expA1  block == "age"
	global expA2  block == "gender"
	global exp1R  block == "rerun_jul2024" & temperature == 0     // Table A2, cols 1-4
	global exp1T  block == "rerun_jul2024" & temperature > 0      // Table A2, cols 5-8 (temperature 0.3)

	*---------------------------------------------------------------------
	* answer rates (Exp. 3), then keep calls with a well-formatted reply
	*---------------------------------------------------------------------

	g answered = !missing(gpt_approval)
	egen ans_rate = mean(100*answered) if $exp3, by(model race)
	tab model race if $exp3, sum(ans_rate) mean nost nofreq

	keep if answered

	*---------------------------------------------------------------------
	* Table 1, column N
	*---------------------------------------------------------------------

	di _n "Table 1: N by experiment"
	foreach e in 1 2 3 4 5 6a 6b 6c 6d 7a 7b A1 A2 1R 1T {
		qui count if ${exp`e'}
		di "  Experiment `e'" _col(20) %9.0fc r(N)
	}

	tempfile analysis
	qui save `analysis'

********************************************************************************
* 2. TABLE 2: SUMMARY STATISTICS
*    table2_panelA.tex, table2_panelB.tex
********************************************************************************

	*-------------------------------------------------------------------------
	* Panel A: the 1,000 HMDA loans (one observation per loan)
	*-------------------------------------------------------------------------

	preserve
		keep if $exp1 & score == 715 & race == "White"
		assert _N == 1000

		lab var interest_rate                "Rate (Actual, \%)"
		lab var rate_spread                  "Rate Spread (Actual, \%)"
		lab var debt_to_income_ratio         "DTI (Actual, \%)"
		lab var combined_loan_to_value_ratio "LTV (Actual, \%)"

		eststo clear
		estpost tabstat actually_approved interest_rate rate_spread debt_to_income_ratio combined_loan_to_value_ratio, c(s) s(n mean sd p50)
		local fmt_seq 2 2 2 1 1
		esttab using "exhibits/table2_panelA.tex", ///
			cells(`"count(fmt(%9.0fc) label("N")) mean(fmt(`fmt_seq') label("Mean")) sd(fmt(`fmt_seq') label("Std.")) p50(fmt(`fmt_seq') label("Median")) "') ///
			nomtitle nonumber label noobs booktabs replace
	restore

	*-------------------------------------------------------------------------
	* Panel B: LLM outcomes by experiment (an observation can be in several experiments)
	*-------------------------------------------------------------------------

	preserve
		local exp_label "\expMain \expAsianHispanic \expLLMs \expNames \expCities \expMitigation \expAltMitigation \expMitigationName \expMitigationCity"
		local exp_macro "exp1 exp2 exp3 exp4 exp5 exp6a exp6b exp6c exp6d"
		local n : word count `exp_label'

		tempfile stacked
		forvalues i = 1/`n' {
			local b : word `i' of `exp_macro'
			use `analysis' if ${`b'}, clear
			keep gpt_approval gpt_interest_rate
			gen byte experiment = `i'
			if `i' > 1 append using `stacked'
			qui save `stacked', replace
		}

		cap label drop experiment_lbl
		forvalues i = 1/`n' {
			local a : word `i' of `exp_label'
			label define experiment_lbl `i' `"`a'"', add
		}
		label values experiment experiment_lbl
		label var experiment "Experiment"
		label var gpt_interest_rate "Rate (LLM, %)"
		tab experiment

		collect: table (var) experiment, stat(n gpt_a) stat(mean gpt_a) stat(sd gpt_a) ///
			stat(n gpt_i) stat(mean gpt_i) stat(sd gpt_i) stat(p50 gpt_i) ///
			nformat(%9.0fc n) nformat(%9.2f mean) nformat(%9.2f sd) nformat(%9.2f p50) nototals
		collect style row stack, delimiter(`" # "') atdelimiter(`" @ "') bardelimiter(`" | "') binder(`"="') spacer indent length(.) wrapon(word) noabbreviate wrap(.) truncate(tail)
		collect style cell border_block, border(right, pattern(nil))
		collect label levels result count "N", name(Table) modify
		collect label levels result mean "Mean", name(Table) modify
		collect label levels result sd "Std.", name(Table) modify
		collect label levels result p50 "Median", name(Table) modify
		collect preview
		collect style tex, nobegintable
		collect export exhibits/table2_panelB_temp1.tex, replace tableonly

		* booktabs rules
		filefilter exhibits/table2_panelB_temp1.tex exhibits/table2_panelB_temp2.tex, from("Experiment} \BS\BS") to("Experiment} \BS\BS \BScmidrule{2-10}") replace
		filefilter exhibits/table2_panelB_temp2.tex exhibits/table2_panelB_temp3.tex, from("ll}\n\BScline{1-10}") to("ll}\n\BStoprule") replace
		filefilter exhibits/table2_panelB_temp3.tex exhibits/table2_panelB_temp4.tex, from("cline{1-10}\n\BSend{tabular}") to("bottomrule\n\BSend{tabular}") replace
		filefilter exhibits/table2_panelB_temp4.tex exhibits/table2_panelB.tex, from("} \BS\BS\n\BScline{1-10}") to("} \BS\BS\n\BSmidrule") replace
		forvalues i = 1/4 {
			cap erase exhibits/table2_panelB_temp`i'.tex
		}
	restore

********************************************************************************
* 3. TABLE 3: RACE AND RECOMMENDATIONS (EXP. 1)
*    table3_panelA.tex (approval), table3_panelB.tex (interest rate)
********************************************************************************

	preserve
		keep if $exp1
		center score debt_to_income_ratio combined_loan_to_value_ratio, addtolabel(", z)") inplace standardize

		qui foreach y in gpt_approval gpt_interest_rate {
			eststo clear
			eststo: reghdfe `y' score ib5.race_c, vce(robust) a(loan_id) noomitted noconstant
			eststo: reghdfe `y' c.score ib5.race_c##c.score, vce(robust) a(loan_id) noconstant noomitted
			eststo: reghdfe `y' c.score ib5.race_c##c.debt_to_income_ratio, vce(robust) a(loan_id) noconstant noomitted
			eststo: reghdfe `y' c.score ib5.race_c##c.combined_loan_to_value_ratio, vce(robust) a(loan_id) noconstant noomitted
			eststo: reghdfe `y' c.score ib5.race_c##c.combined_loan_to_value_ratio ib5.race_c##c.debt_to_income_ratio ib5.race_c##c.score, ///
				vce(robust) a(loan_id) noconstant noomitted
			estadd local LoanFE "Yes", replace : *

			noi esttab, se star(* 0.10 ** 0.05 *** 0.01) b(3) compress nogaps label nomtitle noomitted nobaselevels varwidth(40) ///
				stats(N r2 r2_a, fmt(%9.0fc 2 2)) title("Table 3: Y = `y' (Exp. 1)")
			local panel = cond("`y'" == "gpt_approval", "A", "B")
			noi esttab using "exhibits/table3_panel`panel'.tex", booktabs ///
				star(* 0.10 ** 0.05 *** 0.01) b(3) compress replace nogaps ///
				stats(N r2 r2_a LoanFE, fmt(%9.0fc 2 2 0) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE")) ///
				label nomtitle noomitted nobaselevels nonotes se
		}
	restore

********************************************************************************
* 4. TABLE 4: RACE, ETHNICITY, AND RECOMMENDATIONS (EXP. 2)
*    table4.tex   (None, i.e., no race in the prompt, is the base category)
********************************************************************************

	preserve
		keep if $exp2
		center score debt_to_income_ratio combined_loan_to_value_ratio, addtolabel(", z)") inplace standardize

		eststo clear
		qui foreach y in gpt_approval gpt_interest_rate {
			eststo: reghdfe `y' score ib4.race_c, vce(robust) a(loan_id) noomitted noconstant
			eststo: reghdfe `y' c.score ib4.race_c##c.score, vce(robust) a(loan_id) noconstant noomitted
			noi test 2.race_c#c.score = 3.race_c#c.score     // Black vs. Hispanic interactions
		}
		estadd local LoanFE "Yes", replace : *

		noi esttab, se star(* 0.10 ** 0.05 *** 0.01) b(3) compress nogaps label nomtitle noomitted nobaselevels varwidth(40) ///
			stats(N r2 r2_a, fmt(%9.0fc 2 2)) title("Table 4 (Exp. 2)")
		noi esttab using "exhibits/table4.tex", booktabs ///
			star(* 0.10 ** 0.05 *** 0.01) b(3) compress replace nogaps ///
			stats(N r2 r2_a LoanFE, fmt(%9.0fc 2 2 0) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE")) ///
			label nomtitle noomitted nobaselevels nonotes se substitute(\_ _) extracols(3) ///
			mgroups("Approval" "Interest Rate", pattern(1 0 1 0) ///
				prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
			prehead(`"{\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}"' `"\begin{tabular}{l*{5}{c}} \toprule"')
	restore

********************************************************************************
* 5. FIGURE 3 AND TABLE A5: OTHER LLMS (EXP. 3)
*    figure3.eps/.png
*    tableA5_panelA_part1.tex, tableA5_panelA_part2.tex (approval),
*    tableA5_panelB_part1.tex, tableA5_panelB_part2.tex (interest rate)
********************************************************************************

	* the 16 models, in the order of Figure 3 and Table A5
	local mods "claude-3-sonnet-20240229 claude-3-opus-20240229 anthropic/claude-opus-4.8 anthropic/claude-sonnet-5 deepseek/deepseek-chat-v3.1 deepseek/deepseek-v4-flash google/gemini-2.5-flash-lite google/gemini-3.1-flash-lite llama3-70b-8192 meta-llama/llama-3.1-8b-instruct meta-llama/llama-3.3-70b-instruct meta-llama/llama-4-scout gpt-4-0125-preview gpt-4-0613 openai/gpt-5.4-nano openai/gpt-5.4"
	local n : word count `mods'
	cap label drop model_c
	g model_c = .
	forvalues i = 1/`n' {
		local b : word `i' of `mods'
		replace model_c = `i' if model == "`b'"
		label def model_c `i' "`b'", add
	}
	label values model_c model_c
	assert !missing(model_c) if $exp3

	*-------------------------------------------------------------------------
	* Figure 3: all models in one regression (coefficients identical to the
	* model-by-model regressions in Table A5)
	*-------------------------------------------------------------------------

	preserve
		keep if $exp3
		center score debt_to_income_ratio combined_loan_to_value_ratio, addtolabel(", z)") inplace standardize
		estimates clear
		qui foreach y in gpt_approval gpt_interest_rate {
			reghdfe `y' i.model_c model_c#(c.score ib5.race_c), vce(robust) a(model_c#loan_id) noconstant noomitted
			estimates store llm_`y'
		}
		tab model_c if e(sample)
	restore

	local rename_opts ""
	local label_opts  ""
	local labels `""3 Sonnet" "3 Opus" "4.8 Opus" "5 Sonnet" "v3.1 Chat" "v4 Flash" "2.5 Flash Lite" "3.1 Flash Lite" "3 70b" "3.1 8b" "3.3 70b" "4 Scout" "4-Turbo (Baseline LLM)" "4" "5.4 Nano" "5.4""'
	forvalues i = 1/16 {
		local rename_opts `rename_opts' `i'.model_c#c.score = `i'.model_c#coef `i'.model_c#2.race_c = `i'.model_c#coef
		local lab : word `i' of `labels'
		local label_opts `label_opts' `i'.model_c#coef = "`lab'"
	}

	#delimit ;
	local base_opts
		drop(?.model_c ??.model_c *5.race_c)
		orderby(2:) xline(0, lwidth(thin) lcolor(red)) baselevel yscale(noline alt)
		nooffsets ciopts(recast(rcap)) legend(off) scheme(white_hue)
		rename(`rename_opts')
		coeflabels(`label_opts', labsize(small))
		headings(1.model_c#coef  = "{bf:Anthropic Claude}"
		         5.model_c#coef  = "{bf:DeepSeek}"
		         7.model_c#coef  = "{bf:Google Gemini}"
		         9.model_c#coef  = "{bf:Meta Llama}"
		         13.model_c#coef = "{bf:OpenAI GPT}", labgap(-2))
	;
	twoway (scatteri 0 .5 1 .5, recast(line) msymbol(none) lcolor(gs10) lwidth(medthick)),
		xscale(off range(0 1)) yscale(off range(0 1)) xlabel(none) ylabel(none) xtitle("") ytitle("")
		legend(off) plotregion(margin(zero) lcolor(none)) graphregion(color(white) margin(zero))
		name(g_sep, replace) fxsize(3)
	;
	#delimit cr

	* panels A: approval; B: interest rate. Green = significant at 5%.
	coefplot ///
		(llm_gpt_approval, if(@pval<=0.05) pstyle(p6) keep(*c.score)) ///
		(llm_gpt_approval, if(@pval>0.05)  pstyle(p1) keep(*c.score)) ///
			, bylabel("{&beta}{subscript:CS}") nokey ///
	||  (llm_gpt_approval, if(@pval<=0.05) pstyle(p6) keep(*2.race_c)) ///
		(llm_gpt_approval, if(@pval>0.05)  pstyle(p1) keep(*2.race_c)) ///
			, bylabel("{&beta}{subscript:B}") nokey ///
	|| , ylabel(none) `base_opts' ///
		byopts(cols(2) xrescale title(" (A) {it:y} = LLM Approval", size(medium))) ///
		name(g_approval, replace) fxsize(85)

	coefplot ///
		(llm_gpt_interest_rate, if(@pval<=0.05) pstyle(p6) keep(*c.score)) ///
		(llm_gpt_interest_rate, if(@pval>0.05)  pstyle(p1) keep(*c.score)) ///
			, bylabel("{&beta}{subscript:CS}") nokey ///
	||  (llm_gpt_interest_rate, if(@pval<=0.05) pstyle(p6) keep(*2.race_c)) ///
		(llm_gpt_interest_rate, if(@pval>0.05)  pstyle(p1) keep(*2.race_c)) ///
			, bylabel("{&beta}{subscript:B}") nokey ///
	|| , `base_opts' ///
		byopts(cols(2) xrescale title("           (B) {it:y} = LLM Interest Rate", pos(11) justification(left) size(medium))) ///
		name(g_rate, replace) fxsize(125)

	graph combine g_approval g_sep g_rate, rows(1) imargin(tiny) xsize(6) ysize(5) name(fig3, replace)
	graph export "exhibits/figure3.png", replace name(fig3)
	graph export "exhibits/figure3.eps", replace name(fig3)

	*-------------------------------------------------------------------------
	* Table A5: model by model, with answer rates and credit score equivalents
	*-------------------------------------------------------------------------

	qui sum score if $exp1
	local sample_sd = r(sd)

	tempfile exp3_stats
	qui postfile exp3post str40 model str20 outcome double(b_black p_black b_score cse mean_y) using `exp3_stats', replace

	eststo clear
	preserve
		keep if $exp3
		center score debt_to_income_ratio combined_loan_to_value_ratio, addtolabel(", z)") inplace standardize

		qui foreach y in gpt_approval gpt_interest_rate {
			forval j = 1/`n' {
				local mod : word `j' of `mods'
				eststo, title(`"`mod'"'): reghdfe `y' c.score ib5.race_c if model == `"`mod'"', ///
					vce(robust) a(loan_id) noconstant noomitted
				estadd local LoanFE "Yes"
				* answer rate as in the paper: estimation sample / 3,000 prompts per race.
				* reghdfe drops singleton loans, so this can be slightly below the share of
				* prompts answered (variable ans_rate, listed in section 12).
				count if e(sample) & race == "White"
				estadd scalar ans_rate_white = 100*r(N)/3000
				count if e(sample) & race == "Black"
				estadd scalar ans_rate_black = 100*r(N)/3000
				sum `y' if e(sample)
				estadd scalar e_y = r(mean)
				local mean_y = r(mean)
				sum `y' if e(sample) & race == "White"
				estadd scalar e_yW = r(mean)
				sum `y' if e(sample) & race == "Black"
				estadd scalar e_yB = r(mean)
				estadd scalar cse = (_b[2.race_c]/_b[score])*`sample_sd'
				post exp3post ("`mod'") ("`y'") (_b[2.race_c]) (2*ttail(e(df_r), abs(_b[2.race_c]/_se[2.race_c]))) ///
					(_b[score]) ((_b[2.race_c]/_b[score])*`sample_sd') (`mean_y')
			}
		}
	postclose exp3post

	local stats_opts stats(N r2 r2_a LoanFE e_y e_yW e_yB ans_rate_white ans_rate_black cse, ///
		fmt(%9.0fc 2 2 0 2 2 2 2 2 2) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE" "Avg(y)" "Avg(y $|$ White)" ///
		"Avg(y $|$ Black)" "White Answer Rate (\%)" "Black Answer Rate (\%)" "CSE"))
	local common se star(* 0.10 ** 0.05 *** 0.01) b(3) compress replace nogaps label noomitted nobaselevels nonotes nonumb

	local ml1 `" "\shortstack{\vphantom{Model Opus}3 Sonnet\\(1)}" "\shortstack{\vphantom{Model Opus}3 Opus  \\(2)}" "\shortstack{\vphantom{Model Opus}4.8 Opus  \\(3)}" "\shortstack{\vphantom{Model Opus}5 Sonnet\\(4)}" "\shortstack{\vphantom{Model Opus}v3.1  \\(5)}" "\shortstack{\vphantom{Model Opus}v4    \\(6)}" "\shortstack{\vphantom{Model Opus}2.5   \\(7)}" "\shortstack{\vphantom{Model Opus}3.1   \\(8)}" "'
	local ml2 `" "\shortstack{\vphantom{Model Opus}3 70b   \\(9)}" "\shortstack{\vphantom{Model Opus}3.1 8b  \\(10)}" "\shortstack{\vphantom{Model Opus}3.3 70b \\(11)}" "\shortstack{\vphantom{Model Opus}4 Scout \\(12)}" "\shortstack{\vphantom{Model Opus}4-Turbo \\(13)}" "\shortstack{\vphantom{Model Opus}4       \\(14)}" "\shortstack{\vphantom{Model Opus}5.4 Nano\\(15)}" "\shortstack{\vphantom{Model Opus}5.4     \\(16)}" "'
	local mg1 mgroups("Anthropic Claude" "Deep Seek" "Gemini Flash Lite", pattern(1 0 0 0 1 0 1 0) lhs("Family") prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span}))
	local mg2 mgroups("Meta Llama" "OpenAI GPT", pattern(1 0 0 0 1 0 0 0) lhs("Family") prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span}))
	local lhs lhs("\shortstack{\vphantom{Model Opus}Model\\(\#)}")

	esttab est1 est2 est3 est4 est5 est6 est7 est8 using "exhibits/tableA5_panelA_part1.tex", booktabs mlabels(`ml1', `lhs') `mg1' `stats_opts' `common'
	esttab est9 est10 est11 est12 est13 est14 est15 est16 using "exhibits/tableA5_panelA_part2.tex", booktabs mlabels(`ml2', `lhs') `mg2' `stats_opts' `common'
	esttab est17 est18 est19 est20 est21 est22 est23 est24 using "exhibits/tableA5_panelB_part1.tex",   booktabs mlabels(`ml1', `lhs') `mg1' `stats_opts' `common'
	esttab est25 est26 est27 est28 est29 est30 est31 est32 using "exhibits/tableA5_panelB_part2.tex",   booktabs mlabels(`ml2', `lhs') `mg2' `stats_opts' `common'
	restore

********************************************************************************
* 6. TABLE 5: RACE PROXIES (EXPS. 4 AND 5)
*    table5_panelA.tex (names), table5_panelB.tex (cities)
********************************************************************************

	foreach x in name city {
		local e = cond("`x'" == "name", "exp4", "exp5")
		preserve
			keep if ${`e'}
			center score debt_to_income_ratio combined_loan_to_value_ratio, addtolabel(", z)") inplace standardize

			eststo clear
			qui foreach y in gpt_approval gpt_interest_rate {
				eststo: reghdfe `y' c.score c.`x'_black, vce(robust) a(loan_id) noomitted noconstant
				eststo: reghdfe `y' c.score c.`x'_black##c.score, vce(robust) a(loan_id) noconstant noomitted
			}
			estadd local LoanFE "Yes", replace : *

			noi esttab, se star(* 0.10 ** 0.05 *** 0.01) b(3) compress nogaps label nomtitle noomitted nobaselevels varwidth(40) ///
				stats(N r2 r2_a, fmt(%9.0fc 2 2)) title("Table 5: `x' proxies (Exp. `=cond("`x'"=="name","4","5")')")
			local panel = cond("`x'" == "name", "A", "B")
			noi esttab using "exhibits/table5_panel`panel'.tex", booktabs ///
				star(* 0.10 ** 0.05 *** 0.01) b(3) compress replace nogaps ///
				stats(N r2 r2_a LoanFE, fmt(%9.0fc 2 2 0) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE")) ///
				label nomtitle noomitted nobaselevels nonotes se substitute(\_ _) extracols(3) ///
				mgroups("Approval" "Interest Rate", pattern(1 0 1 0) ///
					prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
				prehead(`"{\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}"' `"\begin{tabular}{l*{5}{c}} \toprule"')
		restore
	}

********************************************************************************
* 7. TABLE 6 AND FIGURE 4: MITIGATION (EXPS. 6A-6D)
*    table6.tex, figure4.eps/.png
********************************************************************************

	*-------------------------------------------------------------------------
	* Table 6: Equation 3. In 6C/6D, race_c is the race signaled by the name/city.
	*-------------------------------------------------------------------------

	eststo clear
	qui foreach e in exp6a exp6b exp6c exp6d {
		foreach y in gpt_approval gpt_interest_rate {
			preserve
				keep if ${`e'}
				center score debt_to_income_ratio combined_loan_to_value_ratio, addtolabel(", z)") inplace standardize

				eststo: reghdfe `y' c.mitigate##(c.score ib5.race_c), vce(robust) a(loan_id) noomitted noconstant
				estadd local LoanFE "Yes"
				test 2.race_c#c.mitigate + 2.race_c = 0
				estadd scalar sum_afterfrac_p1 = r(p)
				estadd scalar sum_beta = _b[2.race_c#c.mitigate] + _b[2.race_c]
				local pct_reduced = round(100*(-_b[2.race_c#c.mitigate]/_b[2.race_c]))
				estadd local pct_reduced = "`pct_reduced'%"
			restore
		}
	}

	esttab, se star(* 0.10 ** 0.05 *** 0.01) b(3) compress nogaps label noomitted drop(5.race_c) varwidth(45) ///
		stats(N sum_beta sum_afterfrac_p1 pct_reduced) title("Table 6 (Exps. 6A, 6B, 6C, 6D)")
	esttab using "exhibits/table6.tex", booktabs type ///
		star(* 0.10 ** 0.05 *** 0.01) b(3) se compress replace nogaps varwidth(45) ///
		stats(N r2 r2_a LoanFE sum_beta sum_afterfrac_p1 pct_reduced, ///
			fmt(%9.0fc 2 2 3 3 2) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE" ///
			"\\ \multicolumn{6}{l}{\textbf{Disparities in mitigation condition:}} \\ \$\beta_{\text{B}} + \beta_{\text{B}\times\text{M}} = 0 \$" ///
			"\$p\$-val: \$\beta_{\text{B}} + \beta_{\text{B}\times\text{M}} = 0 \$" ///
			"% Reduction")) ///
		substitute(\_ _ % \%) label noomitted ///
		order(score 2.race_c *mitigate*) ///
		coeflabels(2.race_c "BlackSignal" 2.race_c#c.mitigate `"Mitigation $\times$ BlackSignal"' ///
			2.race_c#c.mitigate#c.score `"Mitigation # BlackSignal # CreditScore"' ///
			c.mitigate#c.score `"Mitigation $\times$ CreditScore (Exp., z)"' score "CreditScore (Exp., z)") ///
		drop(5.race_c) nonum nonotes ///
		mtitles("\shortstack{Approval   \\ (1)}" "\shortstack{\vphantom{Approval}Int.\ Rate \\ (2)}" ///
			"\shortstack{Approval   \\ (3)}" "\shortstack{\vphantom{Approval}Int.\ Rate \\ (4)}" ///
			"\shortstack{Approval   \\ (5)}" "\shortstack{\vphantom{Approval}Int.\ Rate \\ (6)}" ///
			"\shortstack{Approval   \\ (7)}" "\shortstack{\vphantom{Approval}Int.\ Rate \\ (8)}") ///
		mgroups( ///
			"\shortstack{\vphantom{Demographic Signal:}\expMitigation     \\\vphantom{Demographic Signal:}Mitigation      \\\vphantom{Demographic Signal:}Race }" ///
			"\shortstack{\vphantom{Demographic Signal:}\expAltMitigation  \\\vphantom{Demographic Signal:}Alt.\ Mitigation \\\vphantom{Demographic Signal:}Race }" ///
			"\shortstack{\vphantom{Demographic Signal:}\expMitigationName \\\vphantom{Demographic Signal:}Mitigation      \\\vphantom{Demographic Signal:}Name }" ///
			"\shortstack{\vphantom{Demographic Signal:}\expMitigationCity \\\vphantom{Demographic Signal:}Mitigation      \\\vphantom{Demographic Signal:}City }", ///
			pattern(1 0 1 0 1 0 1 0) span prefix(\multicolumn{@span}{c}{) suffix(}) erepeat(\cmidrule(lr){@span}) ///
			lhs("\shortstack[l]{\vphantom{Demographic Signal:}Experiment: \\\vphantom{Demographic Signal:}Mitigation Prompt:     \\\vphantom{Demographic Signal:}Demographic Signal: }"))

	*-------------------------------------------------------------------------
	* Figure 4: Equation 4, predicted values (incl. loan FE) averaged by score
	*-------------------------------------------------------------------------

	preserve
		keep if $exp6a
		center score debt_to_income_ratio combined_loan_to_value_ratio, addtolabel(")") inplace standardize

		qui foreach y in gpt_approval gpt_interest_rate {
			reghdfe `y' c.mitigate##(c.score##ib5.race_c), vce(robust) a(loan_id) noomitted noconstant resid
			predict pred_`y', xbd
		}

		* back out the experimental scores (three standardized values) for the x-axis
		collapse pred_*, by(score race_c mitigate)
		egen score_rank = group(score)
		replace score = 640 if score_rank == 1
		replace score = 715 if score_rank == 2
		replace score = 790 if score_rank == 3
		lab var score "CreditScore (Exp.)"
		replace pred_gpt_approval = pred_gpt_approval*100
		sort mitigate race_c score
		list

		twoway ///
			(connect pred_gpt_interest_rate score if race_c == 2 & mitigate == 0, color(black) lpattern(dash)) ///
			(connect pred_gpt_interest_rate score if race_c == 2 & mitigate == 1, color(black) lpattern(solid)) ///
			(connect pred_gpt_interest_rate score if race_c == 5 & mitigate == 0, color(white) lpattern(dash)) ///
			(connect pred_gpt_interest_rate score if race_c == 5 & mitigate == 1, color(white) lpattern(solid)), ///
			title(`"LLM Interest Rate"', pos(12) margin(b=7)) xtitle(, margin(t=3)) ytitle("") ///
			ylabel(3.5 "3.5%" 4 "4.0%" 4.5 "4.5%" 5 "5.0%" 5.5 "5.5%", format(%9.0f)) ///
			legend(on pos(6) order(1 `"Black - Baseline"' 2 "Black - Mitigation" 3 `"White - Baseline"' 4 "White - Mitigation") ///
				title("{bf:Race - Prompt}", size(medsmall) margin(7 0 1 0) j(left)) rows(2)) ///
			scheme(economist) name(pred_gpt_i, replace)

		twoway ///
			(connect pred_gpt_approval score if race_c == 2 & mitigate == 0, color(black) lpattern(dash)) ///
			(connect pred_gpt_approval score if race_c == 2 & mitigate == 1, color(black) lpattern(solid)) ///
			(connect pred_gpt_approval score if race_c == 5 & mitigate == 0, color(white) lpattern(dash)) ///
			(connect pred_gpt_approval score if race_c == 5 & mitigate == 1, color(white) lpattern(solid)), ///
			title(`"LLM Approval Decision"', pos(12) margin(b=7)) xtitle(, margin(t=3)) ytitle("") ///
			ylabel(80 "80%" 85 "85%" 90 "90%" 95 "95%" 100 "100%", format(%9.0f)) ///
			legend(on pos(6) order(1 `"Black - Baseline"' 2 "Black - Mitigation" 3 `"White - Baseline"' 4 "White - Mitigation") ///
				symxs(15) size(small) title("{bf:Race - Prompt}", size(small) margin(7 0 1 0) j(left)) rows(2)) ///
			scheme(economist) name(pred_gpt_a, replace)

		grc1leg pred_gpt_a pred_gpt_i, graphregion(fcolor(ebg) lcolor(ebg)) name(fig4, replace)
		graph export "exhibits/figure4.eps", replace name(fig4)
		graph export "exhibits/figure4.png", replace name(fig4)
	restore

********************************************************************************
* 8. TABLES 7-9 AND FIGURE 5: ACTUAL CREDIT SCORES (EXPS. 7A, 7B)
*    table7.tex, figure5.png/.eps,
*    table8.tex, table9.tex
********************************************************************************

	* delinquency (30+ days past due through 2024Q3) from Freddie Mac performance data
	preserve
		import delimited using input_data/freddie_hmda_sample_1000.csv, clear
		keep loan_sequence_number delinquent
		tempfile dlq
		qui save `dlq'
	restore
	merge m:1 loan_sequence_number using `dlq', keep(1 3) nogen
	rename delinquent dlq
	lab var dlq "Delinquent"
	g black_actual = applicant_race_1 == 3 if block == "actual_credit"

	*-------------------------------------------------------------------------
	* Table 7: determinants of LLM rate recommendations (Exp. 7A)
	*-------------------------------------------------------------------------

	preserve
		lab var score "CreditScore (Actual"
		local controls score loan_amount income debt_to_income_ratio combined_loan_to_value_ratio property_value rate_spread
		keep if $exp7a | $exp7b
		* The paper standardized these controls over all six prompt arms collected for
		* each matched loan (four of which are not used here). Each loan appears twice
		* here, so three copies reproduce that scaling exactly.
		expand 3, gen(copy)
		center `controls', addtolabel(", z)") inplace standardize
		drop if copy

		eststo clear
		eststo: reg gpt_interest_rate score                                                    if $exp7a, vce(robust)
		eststo: reg gpt_interest_rate debt_to_income_ratio                                     if $exp7a, vce(robust)
		eststo: reg gpt_interest_rate combined_loan_to_value_ratio                             if $exp7a, vce(robust)
		eststo: reg gpt_interest_rate score debt_to_income_ratio combined_loan_to_value_ratio  if $exp7a, vce(robust)
		estadd local LoanFE "No", replace : *

		esttab, se star(* 0.10 ** 0.05 *** 0.01) b(3) compress nogaps label nomtitle title("Table 7 (Exp. 7A)")
		esttab using "exhibits/table7.tex", booktabs type ///
			star(* 0.10 ** 0.05 *** 0.01) b(3) compress replace nogaps varwidth(30) ///
			stats(N r2 r2_a LoanFE, fmt(%9.0fc 2 2 0) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE")) ///
			label nomtitle nonotes se
	restore

	*-------------------------------------------------------------------------
	* Figure 5: LLM rate vs. actual rate spread (Exp. 7A)
	*-------------------------------------------------------------------------

	binscatter gpt_interest_rate rate_spread if $exp7a, ///
		xtitle("Rate Spread (Actual)") ytitle("Rate (LLM)") aspect(1.1, units) reportreg
	graph export "exhibits/figure5.png", replace
	graph export "exhibits/figure5.eps", replace

	*-------------------------------------------------------------------------
	* Table 8: delinquency (Exp. 7A)
	*-------------------------------------------------------------------------

	preserve
		lab var rate_spread "Rate Spread (Actual"
		lab var score "CreditScore (Actual"
		lab var gpt_interest_rate "Rate (LLM"
		keep if $exp7a
		assert _N == 1000
		center rate_spread gpt_interest_rate score, addtolabel(", z)") inplace standardize

		eststo clear
		eststo: reg dlq c.rate_spread, robust
		eststo: reg dlq c.gpt_interest_rate, robust
		eststo: reg dlq c.rate_spread c.gpt_interest_rate, robust
		eststo: reg dlq c.score, robust
		eststo: reg dlq c.rate_spread c.gpt_interest_rate c.score, robust
		estadd local LoanFE "No", replace : *

		esttab, se star(* 0.10 ** 0.05 *** 0.01) b(3) compress nogaps label nomtitle title("Table 8 (Exp. 7A)")
		esttab using "exhibits/table8.tex", booktabs type ///
			star(* 0.10 ** 0.05 *** 0.01) b(3) compress replace nogaps varwidth(30) ///
			stats(N r2 r2_a LoanFE, fmt(%9.0fc 2 2 0) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE")) ///
			label nomtitle nonotes se
	restore

	*-------------------------------------------------------------------------
	* Table 9: outcomes and true race (Exps. 7A, 7B)
	*-------------------------------------------------------------------------

	preserve
		g black_undisclosed = black_actual
		g black_disclosed   = black_actual
		lab var score "CreditScore (Actual"
		lab var black_undisclosed "Black (Actual; Undisclosed)"
		lab var black_disclosed   "Black (Actual; Disclosed)"

		local controls score loan_amount income debt_to_income_ratio combined_loan_to_value_ratio property_value
		keep if $exp7a | $exp7b
		* The paper standardized these controls over all six prompt arms collected for
		* each matched loan (four of which are not used here). Each loan appears twice
		* here, so three copies reproduce that scaling exactly.
		expand 3, gen(copy)
		center `controls', addtolabel(", z)") inplace standardize
		drop if copy

		eststo clear
		foreach y in dlq rate_spread gpt_interest_rate {
			eststo: reg `y' black_undisclosed                                                          if $exp7a, vce(robust)
			eststo: reg `y' black_undisclosed score debt_to_income_ratio combined_loan_to_value_ratio  if $exp7a, vce(robust)
		}
		* the LLM is told the borrower's actual race
		eststo: reg gpt_interest_rate black_disclosed                                                  if $exp7b, vce(robust)
		eststo: reg gpt_interest_rate black_disclosed score debt_to_income_ratio combined_loan_to_value_ratio if $exp7b, vce(robust)
		estadd local LoanFE "No", replace : *

		esttab, se star(* 0.10 ** 0.05 *** 0.01) b(3) compress nogaps label nomtitle title("Table 9 (Exps. 7A, 7B)")
		esttab using "exhibits/table9.tex", booktabs type ///
			star(* 0.10 ** 0.05 *** 0.01) b(3) compress replace nogaps ///
			se stats(N r2 r2_a LoanFE, fmt(%9.0fc 2 2 0) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE")) ///
			label order(black*) nomtitle nonotes substitute(\_ _) extracols(3 5 7) ///
			mgroups("Delinquent" "Rate Spread (Actual)" "Rate (LLM; Race Undisclosed)" "Rate (LLM; Race Disclosed)", pattern(1 0 1 0 1 0 1) ///
				prefix(\multicolumn{2}{>{\centering\arraybackslash}p{3.1cm}}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
			prehead(`"{\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}"' `"\begin{tabular}{l*{11}{c}} \toprule"')
	restore

	qui save `analysis', replace

********************************************************************************
* 9. TABLE A1: ENTIRE FILTERED HMDA VS. THE 1,000 STUDY LOANS
*    tableA1.tex
********************************************************************************

	* The eligible population: every application in the filtered LAR file whose
	* prompt variables are all populated (the rule the study sample was drawn under).

	clear
python:
import numpy as np
import pandas as pd
from sfi import Data

PROMPT_VARS = ['loan_amount', 'combined_loan_to_value_ratio', 'property_value',
               'income', 'debt_to_income_ratio', 'state_code']
MISSING = ['Exempt', 'NA', 'NA%', 'nan', '']
COLS = ['action_taken', 'interest_rate', 'rate_spread', 'debt_to_income_ratio',
        'combined_loan_to_value_ratio', 'applicant_race_1']

df = pd.read_csv('input_data/2022_public_lar_csv_filtered.zip', usecols=sorted(set(COLS) | set(PROMPT_VARS)),
                 dtype={v: str for v in PROMPT_VARS}, low_memory=False)
complete = pd.Series(True, index=df.index)
for v in PROMPT_VARS:
    s = df[v].replace(MISSING, np.nan)
    complete &= s.notna() if v in ('state_code', 'debt_to_income_ratio') else pd.to_numeric(s, errors='coerce').notna()
df['prompt_complete'] = complete.astype(int)
df['combined_loan_to_value_ratio'] = pd.to_numeric(df['combined_loan_to_value_ratio'].replace(MISSING, np.nan), errors='coerce')
print(f'filtered LAR: {len(df):,}; every prompt variable populated: {complete.sum():,}')
df = df[COLS + ['prompt_complete']]

Data.addObs(len(df))
for c in df.columns:
    if df[c].dtype == object:
        Data.addVarStrL(c) if df[c].str.len().max() > 2045 else Data.addVarStr(c, int(df[c].str.len().max()))
        Data.store(c, None, df[c].fillna('').tolist())
    else:
        Data.addVarDouble(c)
        Data.store(c, None, df[c].astype(float).tolist())
end

	preserve
		use `analysis', clear
		keep if $exp2 & race == "None" & score == 715     // one observation per study loan
		assert _N == 1000
		keep action_taken interest_rate rate_spread debt_to_income_ratio combined_loan_to_value_ratio
		g whole_hmda = 0
		tempfile subset
		qui save `subset'
	restore

	* Python returned numeric missing as NaN, which Stata stores as missing
	g whole_hmda = 1
	replace debt_to_income_ratio = ""   if debt_to_income_ratio == "NA%"
	replace debt_to_income_ratio = "20" if debt_to_income_ratio == "<20%"
	replace debt_to_income_ratio = "60" if debt_to_income_ratio == ">60%"
	replace debt_to_income_ratio = "55" if debt_to_income_ratio == "50%-60%"
	replace debt_to_income_ratio = "25" if debt_to_income_ratio == "20%-<30%"
	replace debt_to_income_ratio = "33" if debt_to_income_ratio == "30%-<36%"
	replace debt_to_income_ratio = subinstr(debt_to_income_ratio,"%","",.)
	replace debt_to_income_ratio = ""   if debt_to_income_ratio == "Exempt"
	destring debt_to_income_ratio, replace
	keep if prompt_complete == 1 & !missing(debt_to_income_ratio)
	count
	assert r(N) == 2383561
	append using `subset'

	g actually_approved = action_taken == 1
	sum actually_approved if whole_hmda == 1
	scalar hmda_approval_rate = r(mean)            // used for the power calculation in section 12

	global table_varlist actually_approved interest_rate rate_spread debt_to_income_ratio combined_loan_to_value_ratio

	* winsorize the HMDA universe at 1%/99% (does not change any significance level)
	foreach v in $table_varlist {
		winsor `v' if whole_hmda == 1, g(temp) p(0.01)
		replace temp = `v' if whole_hmda == 0
		drop `v'
		rename temp `v'
	}

	lab var actually_approved            "Approval (Actual)"
	lab var interest_rate                "Rate (Actual)"
	lab var rate_spread                  "Rate Spread (Actual)"
	lab var debt_to_income_ratio         "DTI (Actual)"
	lab var combined_loan_to_value_ratio "LTV (Actual)"

	eststo clear
	eststo whole:  estpost tabstat $table_varlist if whole_hmda == 1, statistics(mean sd) columns(statistics)
	eststo subset: estpost tabstat $table_varlist if whole_hmda == 0, statistics(mean sd) columns(statistics)
	eststo diff1:  estpost ttest   $table_varlist, by(whole_hmda)

	local estopts cells("mean(pattern(1 1 0) fmt(2)) b(star pattern(0 0 1) fmt(2))" "sd(pattern(1 1 0) par([ ])) se(pattern(0 0 1) par)") ///
		mtitle("Entire 2022 HMDA" "Study Subset" "Difference") collabels(none) noobs nonumbers label
	esttab whole subset diff1, `estopts'
	esttab whole subset diff1 using "exhibits/tableA1.tex", `estopts' booktabs replace

	use `analysis', clear

********************************************************************************
* 10. TABLE A2: EXP. 1 RE-COLLECTED IN JULY 2024 AT TEMPERATURE 0 AND 0.3
*     tableA2.tex
********************************************************************************

	preserve
		keep if $exp1R | $exp1T
		center score, addtolabel(", z)") inplace standardize

		eststo clear
		foreach e in exp1R exp1T {
			qui foreach y in gpt_approval gpt_interest_rate {
				eststo: reghdfe `y' score ib5.race_c if ${`e'}, vce(robust) a(loan_id) noomitted noconstant
				eststo: reghdfe `y' c.score ib5.race_c##c.score if ${`e'}, vce(robust) a(loan_id) noconstant noomitted
			}
		}
		estadd local LoanFE "Yes", replace : *

		esttab, se star(* 0.10 ** 0.05 *** 0.01) b(3) compress nogaps label nomtitle noomitted nobaselevels varwidth(40) ///
			stats(N r2 r2_a, fmt(%9.0fc 2 2)) title("Table A2 (Exps. 1R: cols 1-4, 1T: cols 5-8)")
		esttab using "exhibits/tableA2.tex", booktabs type ///
			se star(* 0.10 ** 0.05 *** 0.01) b(3) compress replace nogaps ///
			prehead("{" "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" "\begin{tabular}{l*{11}{c}}" "\toprule" ///
				"Temperature: & \multicolumn{5}{c}{Temperature 0} & & \multicolumn{5}{c}{Temperature 0.3} \\" ///
				"\cmidrule(lr){2-6} \cmidrule(lr){8-11}") ///
			extracols(3 5 7) ///
			mgroups("Approval" "Interest Rate" "Approval" "Interest Rate", pattern(1 0 1 0 1 0 1 0) lhs("Dependent Variable:") ///
				prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
			stats(N r2 r2_a LoanFE, fmt(%9.0fc 2 2 0) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE")) ///
			label nomtitle noomitted nobaselevels varwidth(40) nonotes
	restore

********************************************************************************
* 11. TABLES A3 AND A4: AGE (EXP. A1) AND GENDER (EXP. A2)
*     tableA3.tex, tableA4.tex
********************************************************************************

	preserve
		keep if $expA1
		lab var age "Age"
		center score, addtolabel(", z)") inplace standardize

		eststo clear
		qui foreach y in gpt_approval gpt_interest_rate {
			eststo: reghdfe `y' score ib30.age, vce(robust) a(loan_id) noomitted noconstant
			eststo: reghdfe `y' c.score ib30.age##c.score, vce(robust) a(loan_id) noconstant noomitted
		}
		estadd local LoanFE "Yes", replace : *

		esttab, se star(* 0.10 ** 0.05 *** 0.01) b(3) compress nogaps label nomtitle noomitted nobaselevels varwidth(40) ///
			stats(N r2 r2_a, fmt(%9.0fc 2 2)) title("Table A3 (Exp. A1)")
		esttab using "exhibits/tableA3.tex", booktabs type ///
			star(* 0.10 ** 0.05 *** 0.01) b(3) compress replace nogaps ///
			stats(N r2 r2_a LoanFE, fmt(%9.0fc 2 2 0) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE")) ///
			label nomtitles noomitted nobaselevels nonotes extracols(3) ///
			mgroups("Approval" "Interest Rate", pattern(1 0 1 0) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
			prehead(`"{ \def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}"' `"\begin{tabular}{l*{9}{c}} \toprule"') ///
			se order(score 50.age 70.age 50.age#c.score 70.age#c.score)
	restore

	preserve
		keep if $expA2
		center score debt_to_income_ratio combined_loan_to_value_ratio, addtolabel(", z)") inplace standardize

		eststo clear
		qui foreach y in gpt_approval gpt_interest_rate {
			eststo: reghdfe `y' score ib2.gender_c, vce(robust) a(loan_id) noomitted noconstant
			eststo: reghdfe `y' score c.score##ib2.gender_c, vce(robust) a(loan_id) noomitted noconstant
		}
		estadd local LoanFE "Yes", replace : *

		esttab, se star(* 0.10 ** 0.05 *** 0.01) b(3) compress nogaps label nomtitle noomitted nobaselevels varwidth(40) ///
			stats(N r2 r2_a, fmt(%9.0fc 2 2)) title("Table A4 (Exp. A2)")
		esttab using "exhibits/tableA4.tex", booktabs type ///
			star(* 0.10 ** 0.05 *** 0.01) b(3) compress replace nogaps ///
			stats(N r2 r2_a LoanFE, fmt(%9.0fc 2 2 0) labels("Obs" "R$^2$" "Adj R$^2$" "Loan FE")) ///
			label nomtitles noomitted nobaselevels nonotes extracols(3) ///
			mgroups("Approval" "Interest Rate", pattern(1 0 1 0) prefix(\multicolumn{@span}{c}{) suffix(}) span erepeat(\cmidrule(lr){@span})) ///
			prehead(`"{\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}"' `"\begin{tabular}{l*{9}{c}} \toprule"') ///
			se order(score 1.gender_c 1.gender_c#c.score)
	restore

********************************************************************************
* 12. IN-TEXT STATISTICS
*     Numbers quoted in the text that are not read directly off an exhibit.
********************************************************************************

	di _n(2) "{hline 80}" _n "IN-TEXT STATISTICS" _n "{hline 80}"

	*-------------------------------------------------------------------------
	* Sec. 2.3: Exp. 1 race effects at score 715, excluding the 5% tails of LTV and DTI
	*-------------------------------------------------------------------------

	preserve
		keep if $exp1 & score == 715
		xtile dti_bin = debt_to_income_ratio, n(20)
		xtile ltv_bin = combined_loan_to_value_ratio, n(20)
		drop if inlist(dti_bin, 1, 20) | inlist(ltv_bin, 1, 20)
		di _n "Sec. 2.3: score 715, excluding 5% tails of LTV and DTI (N = " _N ")"
		foreach y in gpt_approval gpt_interest_rate {
			qui reghdfe `y' ib5.race_c, vce(robust) a(loan_id) noconstant
			di "  `y': Black = " %6.3f _b[2.race_c] " (se " %5.3f _se[2.race_c] ")"
		}
	restore

	*-------------------------------------------------------------------------
	* Sec. 3.3, footnote: ex-ante power calculation
	*-------------------------------------------------------------------------

	* The paper states the inputs: a 7.4 pp rejection rate and half of it (3.7 pp) as the
	* detectable difference. The eligible population used here has the rejection rate below.
	di _n "Sec. 3.3 fn: rejection rate in the eligible HMDA population = " %4.2f 100*(1-hmda_approval_rate) " pp"
	di "  Power calculation with the paper's stated inputs (7.4 pp rejection rate, 3.7 pp difference):"
	power twoproportions 0.926 0.889, power(0.8) alpha(0.05)

	*-------------------------------------------------------------------------
	* Sec. 3.3: ranges of LLM averages across experiments (Table 2, Panel B)
	*-------------------------------------------------------------------------

	di _n "Sec. 3.3: LLM averages by experiment (Table 2B)"
	foreach e in 1 2 3 4 5 6a 6b 6c 6d {
		qui sum gpt_approval if ${exp`e'}
		local a = r(mean)
		qui sum gpt_interest_rate if ${exp`e'}
		di "  Exp. `e'" _col(14) "approval " %5.3f `a' "   rate " %5.2f r(mean)
	}

	*-------------------------------------------------------------------------
	* Sec. 4.1: credit score equivalents and the score-654 example (Exp. 1)
	*-------------------------------------------------------------------------

	preserve
		keep if $exp1
		qui sum score
		local sd_cs = r(sd)
		center score debt_to_income_ratio combined_loan_to_value_ratio, inplace standardize
		qui reghdfe gpt_approval score ib5.race_c, vce(robust) a(loan_id)
		local cse_a = _b[2.race_c]/_b[score]*`sd_cs'
		qui reghdfe gpt_approval c.score ib5.race_c##c.score, vce(robust) a(loan_id)
		local gap654_a = _b[2.race_c] - _b[2.race_c#c.score]
		qui reghdfe gpt_interest_rate score ib5.race_c, vce(robust) a(loan_id)
		local cse_r = _b[2.race_c]/_b[score]*`sd_cs'
		qui reghdfe gpt_interest_rate c.score ib5.race_c##c.score, vce(robust) a(loan_id)
		local b_cs = _b[score]
		local gap654_r = _b[2.race_c] - _b[2.race_c#c.score]
		di _n "Sec. 4.1: SD of experimental credit score = " %5.1f `sd_cs'
		di "  CSE approval = " %5.1f `cse_a' " points; CSE rate = " %5.1f `cse_r' " points"
		di "  Score 654 (1 SD below mean): approval gap " %5.3f `gap654_a' "; rate gap " %5.3f `gap654_r' " pp"
	restore

	preserve
		keep if $exp1 & score == 715 & race == "White"
		qui sum interest_rate
		local r0 = r(mean)
	restore
	* the text rounds the rates to two decimals and uses an average loan of 334,000 dollars
	local rW = round(`r0' - `b_cs', .01)
	local rB = round(`rW' + `gap654_r', .01)
	local L  = 334000
	local intW = 360*`L'*(`rW'/1200)/(1-(1+`rW'/1200)^-360) - `L'
	local intB = 360*`L'*(`rB'/1200)/(1-(1+`rB'/1200)^-360) - `L'
	di "  Mean HMDA rate (study sample) " %4.2f `r0' "%; white rate " %4.2f `rW' "%, Black rate " %4.2f `rB' "%"
	di "  Extra lifetime interest on a 334,000-dollar 30-year loan: " %9.0fc `intB'-`intW'

	*-------------------------------------------------------------------------
	* Sec. 4.2: Exp. 3 cross-model summaries (from the Table A5 regressions)
	*-------------------------------------------------------------------------

	preserve
		use `exp3_stats', clear
		di _n "Sec. 4.2: Exp. 3 by model"
		list model outcome b_black p_black cse mean_y, sepby(outcome) noobs abbreviate(12)
		foreach y in gpt_approval gpt_interest_rate {
			qui count if outcome == "`y'" & b_black < 0
			local neg = r(N)
			qui count if outcome == "`y'" & b_black < 0 & p_black < 0.05
			local negsig = r(N)
			qui count if outcome == "`y'" & b_black > 0 & p_black < 0.05
			local possig = r(N)
			qui sum cse if outcome == "`y'"
			local cse = r(mean)
			qui sum mean_y if outcome == "`y'"
			di "  `y': " `neg' " of 16 negative Black coefs (" `negsig' " significant), " `possig' ///
				" positive and significant; average CSE = " %5.1f `cse' "; average y = " %5.3f r(mean) ///
				" [min " %5.3f r(min) ", max " %5.3f r(max) "]"
		}
	restore
	di "  Share of prompts answered, by model and race (%):"
	table model race if $exp3, statistic(mean ans_rate) nformat(%5.1f)

	*-------------------------------------------------------------------------
	* Sec. 4.3: 95% CIs for the proxy approval gaps (Exps. 4, 5)
	*-------------------------------------------------------------------------

	foreach x in name city {
		local e = cond("`x'" == "name", "exp4", "exp5")
		preserve
			keep if ${`e'}
			center score, inplace standardize
			qui reghdfe gpt_approval c.score c.`x'_black, vce(robust) a(loan_id)
			di _n "Sec. 4.3: `x' approval gap = " %6.4f _b[`x'_black] ///
				", 95% CI [" %6.4f _b[`x'_black] - invttail(e(df_r), .025)*_se[`x'_black] ", " ///
				%6.4f _b[`x'_black] + invttail(e(df_r), .025)*_se[`x'_black] "]"
		restore
	}

	*-------------------------------------------------------------------------
	* Sec. 4.3, footnote: Benjamini-Hochberg q-values (5% FDR) by family
	*   cross_model: Black coefficient, 16 models x 2 outcomes (Exp. 3)
	*   proxy: proxy main effects and proxy x score, 2 proxies x 2 outcomes (Exps. 4, 5)
	*   appendix_demographics: age and gender main effects and x score, 2 outcomes (Exps. A1, A2)
	*-------------------------------------------------------------------------

	tempfile bh
	qui postfile bhpost str24 family str60 term double p using `bh', replace

	preserve
		use `exp3_stats', clear
		forvalues i = 1/`=_N' {
			post bhpost ("cross_model") ("`=model[`i']' `=outcome[`i']'") (p_black[`i'])
		}
	restore

	foreach x in name city {
		local e = cond("`x'" == "name", "exp4", "exp5")
		preserve
			keep if ${`e'}
			center score, inplace standardize
			foreach y in gpt_approval gpt_interest_rate {
				qui reghdfe `y' c.score c.`x'_black, vce(robust) a(loan_id)
				post bhpost ("proxy") ("`x'_black `y'") (2*ttail(e(df_r), abs(_b[`x'_black]/_se[`x'_black])))
				qui reghdfe `y' c.score c.`x'_black##c.score, vce(robust) a(loan_id)
				post bhpost ("proxy") ("`x'_black x score `y'") (2*ttail(e(df_r), abs(_b[c.`x'_black#c.score]/_se[c.`x'_black#c.score])))
			}
		restore
	}

	preserve
		keep if $expA1
		center score, inplace standardize
		foreach y in gpt_approval gpt_interest_rate {
			qui reghdfe `y' score ib30.age, vce(robust) a(loan_id)
			foreach a in 50 70 {
				post bhpost ("appendix_demographics") ("age `a' `y'") (2*ttail(e(df_r), abs(_b[`a'.age]/_se[`a'.age])))
			}
			qui reghdfe `y' c.score ib30.age##c.score, vce(robust) a(loan_id)
			foreach a in 50 70 {
				post bhpost ("appendix_demographics") ("age `a' x score `y'") (2*ttail(e(df_r), abs(_b[`a'.age#c.score]/_se[`a'.age#c.score])))
			}
		}
	restore
	preserve
		keep if $expA2
		center score, inplace standardize
		foreach y in gpt_approval gpt_interest_rate {
			qui reghdfe `y' score ib2.gender_c, vce(robust) a(loan_id)
			post bhpost ("appendix_demographics") ("female `y'") (2*ttail(e(df_r), abs(_b[1.gender_c]/_se[1.gender_c])))
			qui reghdfe `y' c.score##ib2.gender_c, vce(robust) a(loan_id)
			post bhpost ("appendix_demographics") ("female x score `y'") (2*ttail(e(df_r), abs(_b[1.gender_c#c.score]/_se[1.gender_c#c.score])))
		}
	restore
	postclose bhpost

	preserve
		use `bh', clear
		bys family (p): gen rank = _n
		bys family: gen m = _N
		gen q_raw = p*m/rank
		gsort family -rank
		by family: gen q = min(1, q_raw) if _n == 1
		by family: replace q = min(q[_n-1], q_raw) if _n > 1
		sort family rank
		di _n "Sec. 4.3 fn: Benjamini-Hochberg q-values"
		list family term p q, sepby(family) noobs abbreviate(20)
		qui count if family == "proxy" & p < 0.05
		local n5 = r(N)
		qui count if family == "proxy" & p < 0.05 & q < 0.05
		di "  proxy family: " `n5' " significant at 5%; " r(N) " remain significant after adjustment"
	restore

	*-------------------------------------------------------------------------
	* Sec. 5.1, Figure 4 footnote: Equation 4 (Exp. 6A)
	*-------------------------------------------------------------------------

	preserve
		keep if $exp6a
		center score debt_to_income_ratio combined_loan_to_value_ratio, inplace standardize
		di _n "Sec. 5.1: Equation 4 (Exp. 6A)"
		foreach y in gpt_approval gpt_interest_rate {
			qui reghdfe `y' c.mitigate##(c.score##ib5.race_c), vce(robust) a(loan_id)
			di "  `y': B x CS = " %6.4f _b[2.race_c#c.score] "; M x B x CS = " %6.4f _b[c.mitigate#2.race_c#c.score]
			qui lincom 2.race_c#c.score + c.mitigate#2.race_c#c.score
			di "     B x CS under mitigation = " %6.4f r(estimate) " (p = " %5.3f r(p) ")"
		}
	restore

	*-------------------------------------------------------------------------
	* Unreported logit versions of Table 3, col. 1 and Table 6, col. 1 (Sec. 4.1, 5.1 fns)
	*-------------------------------------------------------------------------

	preserve
		keep if $exp6a
		center score, inplace standardize
		di _n "Logit robustness (approval)"
		logit gpt_approval score ib5.race_c if !mitigate, vce(robust) nolog
		logit gpt_approval c.mitigate##(c.score ib5.race_c), vce(robust) nolog
	restore

	*-------------------------------------------------------------------------
	* Sec. 6: Figure 5 slope; Table 8 attenuation; Table 9 CIs (Exps. 7A, 7B)
	*-------------------------------------------------------------------------

	qui reg gpt_interest_rate rate_spread if $exp7a
	local t_ols = _b[rate_spread]/_se[rate_spread]
	qui reg gpt_interest_rate rate_spread if $exp7a, vce(robust)
	di _n "Sec. 6.1: Figure 5 slope = " %5.3f _b[rate_spread] "; t = " %5.2f `t_ols' " (OLS SE, as reported by binscatter), " ///
		%5.2f _b[rate_spread]/_se[rate_spread] " (robust SE)"

	preserve
		keep if $exp7a
		center rate_spread gpt_interest_rate score, inplace standardize
		qui reg dlq c.gpt_interest_rate, robust
		local b2 = _b[gpt_interest_rate]
		qui reg dlq c.rate_spread c.gpt_interest_rate c.score, robust
		di "Sec. 6.1: adding credit score changes the LLM-rate delinquency coefficient by " ///
			%4.1f 100*(_b[gpt_interest_rate]/`b2' - 1) "% (" %5.1f 100*(round(_b[gpt_interest_rate], .001)/round(`b2', .001) - 1) ///
			"% using the rounded Table 8 coefficients)"
		qui sum dlq
		di "Sec. 6.2 fn: delinquency rate = " %5.3f r(mean) " (" r(sum) " of " r(N) ")"
		center score debt_to_income_ratio combined_loan_to_value_ratio, inplace standardize
		forvalues c = 1/2 {
			local ctrl = cond(`c' == 2, "score debt_to_income_ratio combined_loan_to_value_ratio", "")
			qui reg dlq black_actual `ctrl', vce(robust)
			di "  Table 9 col. `c': Black = " %6.4f _b[black_actual] ", 95% CI [" ///
				%6.4f _b[black_actual] - invttail(e(df_r), .025)*_se[black_actual] ", " ///
				%6.4f _b[black_actual] + invttail(e(df_r), .025)*_se[black_actual] "]"
		}
		qui reg gpt_interest_rate black_actual, vce(robust)
		di "  Table 9 col. 5: t-stat on Black = " %5.2f _b[black_actual]/_se[black_actual]
	restore

	di _n "Done."
	log close main
