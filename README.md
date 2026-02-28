# ReadEFF

[![Build Status](https://github.com/TavoJGB/ReadEFF.jl/actions/workflows/CI.yml/badge.svg?branch=)](https://github.com/TavoJGB/ReadEFF.jl/actions/workflows/CI.yml?query=branch%3A)

**ReadEFF.jl** is a Julia package designed to read and process data from the Spanish Survey of Household Finances (Encuesta Financiera de las Familias - EFF) published by Banco de España. The package uses [DataReader.jl](https://github.com/TavoJGB/DataReader.jl) to extract and separate individual- and household-level data.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/TavoJGB/DataReader.jl")
Pkg.add(url="https://github.com/TavoJGB/ReadEFF.jl")
```

## Basic Usage

In the data directory, one needs to add a varlist, which is a CSV file telling DataReader what variables to extract.

```julia
using ReadEFF

# Specify years and imputations to read
identifier_ranges = (:year => [2002:3:2020;2022], :imputation => 1:5)

# Path to directory containing EFF data files
datadir = "path/to/eff/data"

# Read EFF data
eff_ii, eff_hh = read_eff(
    datadir, identifier_ranges;
    varlists_dir="var_lists", 
    varlist_filename="eff_vars.csv"
)
```

### Parameters

- **`datadir`**: Directory containing EFF CSV files. By default, the name format is: `section6_YYYY_impN.csv` and `other_sections_YYYY_impN.csv`. However, it can be changed by providing a `filefinder`.
- **`identifier_ranges`**: Named tuple specifying:
  - `year`: Vector of years to read (e.g., `[2002, 2005, 2008, ..., 2022]`)
  - `imputation`: Range of imputations (typically `1:5` for the 5 EFF imputations)
- **`varlists_dir`**: Directory containing CSV files with variable lists (default: `"var_lists"`)
- **`varlist_filename`**: Name of the CSV file with variables to read (default: `"eff_vars.csv"`)
- **`preprocess`**: Function applied to the variable list before reading. The default adds wealth-calculation variables from `eff_vars_wealth.csv` and flags them as `"Internal"`. You can pass your own function to customize this step.
- **`postprocess`**: Function applied to the raw DataFrames after reading. The default reshapes, renames, computes derived variables, and cleans up. You can pass your own function to customize this step.
- **`filefinder`**: Function that locates the CSV files for a given year and imputation. The default looks for `section6_YYYY_impN.csv` and `other_sections_YYYY_impN.csv`.

### Return Values

The `read_eff` function returns two DataFrames:

- **`eff_ii`**: DataFrame with **individual-level** data (one record per person)
  - Includes identifiers: `year`, `hid` (household ID), `imputation`, `id` (individual ID)
  - Default computed variables: `head` (household head indicator), `age` (computed from birth year if missing)
  - Default individual variables from the varlist: `rel2hh`, `birthyear`, `age`, `gender`, `educ`, `lab_income_direct`, `lab_income_inkind`
  - A different varlist can be provided by the user.
  - Computed variables can be adjusted by the user with `postprocess`.

- **`eff_hh`**: DataFrame with **household-level** data (one record per household)
  - Includes identifiers: `year`, `hid`, `imputation`
  - Default computed variables: `wealth` (net wealth), `h_tenure` (housing tenure), `weight` (household weight)
  - Default household variables from the varlist: `h_size`, `income`
  - A different varlist can be provided by the user.
  - Computed variables can be adjusted by the user with `postprocess`.



## Reading the data

### The Role of DataReader.jl

**DataReader.jl** is the underlying library that provides generic functionality for reading databases. In this case, it is useful for:
- Multi-level structure (here, individuals and households).
- Variables that change names across survey waves or that are not available in all waves.
- Multiple files per period (each EFF wave is split into 2 CSV files).

### Varlists (CSV Variable Files)

#### 1. `eff_vars.csv` - User-Requested Variables

This file defines **which variables you want to read** from the EFF. It contains these columns:

- **`varname`**: Name that the variable will have in the final DataFrame (e.g., `age`, `income`, `educ`).
- **`varkey`**: Original variable code in the EFF (e.g., `p1_2d`, `renthog`, `p1_5`).
- **`firsttime`**: First year this variable appears. In `preprocess`, it allows to identify what variables are available at a given wave.
- **`lasttime`**: Last year this variable appears. In `preprocess`, it allows to identify what variables are available at a given wave.
- **`level`**: Variable level (`individual` or `household`).

**Example:**
```csv
varname,varkey,firsttime,lasttime,level
age,p1_2d,2008,2099,individual
income,renthog,2002,2099,household
educ,p1_5,2002,2099,individual
```



#### 2. `eff_vars_wealth.csv` - Auxiliary Variables for Wealth Calculation

This file contains **additional variables needed to compute net wealth**, but which you don't necessarily want in your final DataFrame. It includes:

- Asset variables: primary residence value, other properties, businesses, financial assets
- Debt variables: mortgages, loans, outstanding debts
- Over 400 variables used in wealth calculations

**Format:**
```csv
varname,varkey,firsttime,lasttime
pr_val,p2_5,2002,2099
pr_buyyear,p2_3,2002,2099
asset_firms_number,p4_102,2008,2099
```

**Why a separate file?**: 
- These variables are instrumental for calculating `wealth` (net wealth)
- They're loaded automatically when you request household-level variables
- They're marked as `"Internal"` type and removed before returning the final result
- Keeps `eff_vars.csv` clean and focused on the variables you actually want to analyze

### Processing Flow

1. **Preprocessing** (`preprocess`):
   - Reads requested variables from `eff_vars.csv`
   - If there are household-level variables, automatically adds variables from `eff_vars_wealth.csv`
   - Marks varlisted variables as `"User"` and non-requested variables needed for computations as `"Internal"`

2. **Data Reading**:
   - For each specified year and imputation:
     - Finds corresponding CSV files (`section6_*` and `other_sections_*`)
     - Reads necessary variables using the correct codes for that year
     - Combines data from multiple files by household ID

3. **Postprocessing** (`postprocess`):
   - Transforms individual data from wide to long format
   - Renames variables to their intuitive names
   - Computes additional variables:
     - `age`: age (if missing, computed from birth year)
     - `head`: household head indicator
     - `id`: unique individual identifier
     - `wealth`: household net wealth
     - `h_tenure`: housing tenure status (`:owner`, `:renter`, `:notenure`)
   - Removes "phantom" individuals: the raw data stores individual variables as columns at the household level (e.g., `age_1`, `age_2`, ..., up to a fixed max), so reshaping to long format creates rows for non-existent members. These are dropped when `individual > h_size`.
   - Removes `"Internal"` variables (by default, those from `eff_vars_wealth.csv`)
   - Adjusts `year` (survey asks about previous year)

## Expected Directory Structure

```
datadir/
├── section6_2002_imp1.csv
├── other_sections_2002_imp1.csv
├── section6_2002_imp2.csv
├── other_sections_2002_imp2.csv
├── ...
├── section6_2022_imp5.csv
└── other_sections_2022_imp5.csv
```

## Complete Example

```julia
using ReadEFF
using DataFrames

# Configuration
identifier_ranges = (:year => [2002, 2005, 2008, 2011, 2014, 2017, 2020, 2022], 
                     :imputation => 1:5)
datadir = "data/eff"

# Read data
eff_ii, eff_hh = read_eff(datadir, identifier_ranges)

# Explore individual data
println("Individual data dimensions: ", size(eff_ii))
println("Individual variables: ", names(eff_ii))

# Explore household data
println("Household data dimensions: ", size(eff_hh))
println("Household variables: ", names(eff_hh))

# Basic analysis
using Statistics
println("Mean wealth by year:")
combine(groupby(eff_hh, :year), :wealth => mean)
```

## Customization

### Custom variable list

You can create your own variable list by modifying `eff_vars.csv`:

1. Open `var_lists/eff_vars.csv`
2. Add the variables you need with the format:
   ```csv
   varname,varkey,firsttime,lasttime,level
   my_variable,p_code,2002,2099,individual
   ```
3. Consult the EFF questionnaire to find variable codes

### Custom `preprocess` and `postprocess`

You can override the default `preprocess` and `postprocess` functions by passing your own as keyword arguments to `read_eff`. This is useful if you want to skip or modify specific processing steps (e.g., wealth computation, year adjustment, or computation of additional variables).

```julia
# Example: custom postprocess that keeps all variables
my_postprocess(df_ii_wide, df_hh, ivars, hvars) = (df_ii_wide, df_hh)

eff_ii, eff_hh = read_eff(
    datadir, identifier_ranges;
    postprocess=my_postprocess
)
```



## Support

For issues or questions:
- **ReadEFF.jl**: https://github.com/TavoJGB/ReadEFF.jl/issues
- **DataReader.jl**: https://github.com/TavoJGB/DataReader.jl/issues
