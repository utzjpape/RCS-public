*Prepare South Sudan dataset

ma drop all
set more off
set seed 23081980

local using= "${gsdData}/SSD-NBHS2009-HHData.dta"
capture confirm file "`using'"
if _rc != 0 {
	*parameters
	*data directory
	local sData = "${gsdDataBox}/SSD-NBHS2009"

	* CPI inflation from June 2008 (data collection) to June 2011 is 100/69.12 (NBS)
	* Thus, the 2011 (PPP) poverty line of 1.9/d translates into 1.9/d / 1.543373 = 1.23 USD PPP (2011)
	* Using the ER of 2.95 in 2011, we receive 3.63 SSP/d in 2011 terms
	* In 2008 terms, this is 3.63/100*69.12 = 2.51 SSP/d
	* For a month, this is 2.51 * 365.25 / 12 = 76.4 SSP/m
	local xpovline = 2.51 * 365.25 / 12 

	*get laspeyres
	use "`sData'/NBHS_IND.dta", clear
	keep hhid laspeyres
	duplicates drop
	save "${gsdTemp}/SSD-Deflator.dta", replace

	*CREATE MODULES 
	*for validation of the method, missing data is assumed to be zero
	*as the consumption aggregate implicitly assumes.
	*food consumption
	use "`sData'/NBHS_FOOD.dta", clear
	ren (item value) (foodid xfood)
	merge m:1 hhid using "${gsdTemp}/SSD-Deflator.dta", assert(match) keepusing(laspeyres)
	replace xfood = xfood /7 * 365.25 / 12 / laspeyres
	quiet: include "`sData'/SSD-labels.do"
	label values foodid lfoodid
	keep hhid foodid xfood
	fItems2RCS, hhid(hhid) itemid(foodid) value(xfood)
	save "${gsdTemp}/SSD-HH-FoodItems.dta", replace
	*non food consumption
	use "`sData'/NBHS_NONFOOD.dta", clear
	ren (item q3) (nonfoodid xnonfood)
	replace nonfoodid = 83003 if nonfoodid==830031
	merge m:1 hhid using "${gsdTemp}/SSD-Deflator.dta", assert(match) keepusing(laspeyres)
	replace xnonfood = xnonfood / laspeyres
	quiet: include "`sData'/SSD-labels.do"
	label values nonfoodid lnonfoodid
	*module=5 implies 12m recall; module=4 is a 30d recall
	replace xnonfood = xnonfood / 12 if module==5
	*ATTENTION: Previous code removed households with missing non-food consumption
	*as it is unlikely for aperiod of 12m.
	*drop if nonfoodid>=.
	replace nonfoodid = 11101 if nonfoodid>=.
	keep hhid nonfoodid xnonfood
	collapse (sum) xnonfood, by(hhid nonfoodid)
	fItems2RCS, hhid(hhid) itemid(nonfoodid) value(xnonfood)
	save "${gsdTemp}/SSD-HH-NonFoodItems.dta", replace

	*get household characteristics
	use "`sData'/NBHS_IND.dta", clear
	ren b41 age
	gen age_child = age<15 if age<.
	gen age_adult = inrange(age,15,64) if age<.
	gen age_senior = age>64 if age<.
	collapse (count) hhsize=age (sum) nchild=age_child nadult=age_adult nsenior=age_senior, by(hhid cluster)
	merge 1:1 hhid cluster using "`sData'/NBHS_HH.dta", nogen assert(match) keep(match) keepusing(h1 h5 h9 h3 h7 h8 h10 i* head_sex head_age urban state hhweight) 
	ren (h1 h5 h9 h3 h7 h8 h10 hhweight) (hhhouse hhwater hhtoilet hhsleep hhlight hhcook hhwaste weight)
	ren (head_sex head_age state) (hhsex age strata)
	replace hhsex =1 if hhsex>=.
	*collect durables but we won't use them for the moment
	local li = "21 22 23 24 25 31 32 33 34 35 36 37 38 39"
	gen xdurables = 0
	foreach i of local li {
		replace xdurables = xdurables + i`i'_2 * i`i'_3 if i`i'_1==1 & (i`i'_2 * i`i'_3>0)
	}
	drop i*
	*simplify by setting missing values to conservative answers
	*type
	recode hhhouse (1/2=1) (3/4=2) (5/20=3) (11=4) (-9=4) (.=4)
	label define lhouse 1 "Tent" 2 "Tukul" 3 "House/Apt" 4 "Other", replace
	label values hhhouse lhouse
	*sleep
	recode hhsleep (3/12=3) (-9=0)
	label define lsleep 0 "None" 1 "1 Room" 2 "2 Rooms" 3 ">2 Rooms", replace
	label values hhsleep lsleep
	*water
	recode hhwater (1/4=1) (5=2) (6/11=3) (11/12=4) (-9=4)
	label define lwater 1 "Borehole" 2 "Hand pump" 3 "Open Water" 4 "Other"
	label values hhwater lwater
	*light
	recode hhlight (1/5=1) (6/10=2) (11=3) (-9=3)
	label define llight 1 "Gas / Paraffin" 2 "Other material" 3 "None", replace
	label values hhlight llight
	*cook
	recode hhcook (-9=3) (3/9=3)
	label define lcook 1 "Firewood" 2 "Charcoal" 3 "Other", replace
	label values hhcook lcook
	*toilet
	recode hhtoilet (3/5=3) (6=4) (-9=4)
	label define ltoilet 1 "Pit" 2 "Shared Pit" 3 "Flush/Bucket" 4 "None", replace
	label values hhtoilet ltoilet
	*waste
	recode hhwaste (-9/2=4) (3=3) (4=2) (5=1) (6=4)
	label define lwaste 1 "Burning" 2 "Heap" 3 "Pit" 4 "Other"
	label values hhwaste lwaste
	*add durables and food and non-food
	merge 1:1 hhid using "${gsdTemp}/SSD-HH-FoodItems.dta", nogen keep(match) keepusing(xfood*)
	merge 1:1 hhid using "${gsdTemp}/SSD-HH-NonFoodItems.dta", nogen keep(match) keepusing(xnonfood*)
	gen pchild = nchild / hhsize
	gen psenior = nsenior / hhsize
	order strata cluster hhid, first
	ren (nchild nadult nsenior pchild psenior) mcon_=
	ren (hhhouse hhsleep hhwater hhlight hhcook hhtoilet hhwaste hhsex) mcat_=
	keep hhid strata urban cluster weight hhsize mcon_* mcat_* xdurables xfood* xnonfood*
	order hhid strata urban cluster weight hhsize mcon_* mcat_* xdurables xfood* xnonfood*, first
	*ensure no missing values
	desc, varl
	local lv = r(varlist)
	foreach v of local lv {
		assert !missing(`v')
	}
	*save
	compress
	save "`using'", replace

	*local model = "hhsize pchild psenior i.hhsex i.hhwater i.hhcook hhsleep i.hhhouse i.hhtoilet i.hhwaste i.strata"

	*build consumption model
	merge 1:1 hhid using "`sData'/NBHS_HH.dta", nogen keep(match) assert(match using) keepusing(pc*)
	egen ctf = rowtotal(xfood*)
	replace ctf = ctf / hhsize
	egen ctnf = rowtotal(xnonfood*)
	replace ctnf = ctnf / hhsize
	gen ct_pc = ctf+ctnf + xdurables
	*NOTE THAT WE CANNOT REPRODUCE ORIGINAL CONSUMPTION AGGREGATE
	*assert (round(ct_pc-pcexpm)==0)
	gen poor = ct_pc < `xpovline'
	mean poor [pweight=weight*hhsize]
	mean poor [pweight=weight*hhsize], over(strata)
	reg ct_pc `model'
}
