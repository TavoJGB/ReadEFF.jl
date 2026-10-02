using ReadEFF

# Preliminaries
identifier_ranges = (:year => [2002:3:2020;2022], :imputation => 1:5)
datadir = joinpath(pwd(), "..", "..", "..", "Datos", "EFF")

# Read EFF data: example 1 (individuals and households)
eff_ii, eff_hh = read_eff(
    datadir, identifier_ranges;
    varlists_dir="var_lists", varlist_filename="eff_vars_ex1.csv"
)

# Read EFF data: example 2 (individuals, households and real estate properties)
eff_ii2, eff_hh2, eff_re = read_eff(
    datadir, identifier_ranges;
    varlists_dir="var_lists", varlist_filename="eff_vars_ex2.csv"
)