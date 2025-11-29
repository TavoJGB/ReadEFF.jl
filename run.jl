using ReadEFF

# Preliminaries
datadir = joinpath(pwd(), "..", "IWTdata", "data", "eff")
identifier_ranges = (:year => [2002:3:2020;2022], :imputation => 1:5)

# Read EFF data
eff_ii, eff_hh = read_eff(datadir, identifier_ranges; i_list_filename="eff_vars_ii.csv", h_list_filename="eff_vars_hh.csv")