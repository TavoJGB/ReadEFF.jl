using ReadEFF

# Preliminaries
identifier_ranges = (:year => [2002:3:2020;2022], :imputation => 1:5)
datadir = joinpath(pwd(), "..", "..", "IWD_GFC", "HousingEmpirics", "data", "eff")

# Read EFF data
eff_ii, eff_hh = read_eff(
    datadir, identifier_ranges;
    varlists_dir="var_lists", varlist_filename="eff_vars.csv"
)