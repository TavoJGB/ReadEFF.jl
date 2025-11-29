#==========================================================================
    WEALTH CALCULATIONS FOR EFF DATA
    Modular functions to compute assets, debts, and net wealth
==========================================================================#

"""
    sum_na_as_zero(values...)

Sum values treating missing as zero (equivalent to R's na.rm=T).

# Examples
```
sum_na_as_zero(1, 2, missing, 3)  # Returns 6
sum_na_as_zero(missing, missing)   # Returns 0
```
"""
sum_na_as_zero(values...) = sum(skipmissing(collect(values)); init=0.0)

"""
    coalesce_add(x, y)

Add two values, treating missing as the other value (equivalent to R's %+na%).

# Examples
```
coalesce_add(5, 3)        # Returns 8
coalesce_add(missing, 3)  # Returns 3
coalesce_add(5, missing)  # Returns 5
coalesce_add(missing, missing)  # Returns missing
```
"""
function coalesce_add(x, y)
    ismissing(x) && return y
    ismissing(y) && return x
    return x + y
end

# Broadcast-friendly version
coalesce_add(x::AbstractVector, y::AbstractVector) = coalesce_add.(x, y)


## -------------------------------------------------------------------------- ##
#### PRINCIPAL RESIDENCE                                                    ####
## -------------------------------------------------------------------------- ##

"""
    compute_principal_residence_ownership!(df::DataFrame)

Add boolean flags for principal residence ownership status.

Creates columns:
- `pr_owner`: Boolean indicating ownership of principal residence
- `pr_partial_owner`: Boolean indicating partial ownership (before full ownership check)

# Arguments
- `df`: EFF DataFrame with columns `pr_tenure` and `pr_ownall`

# Side Effects
Modifies df in place by adding ownership flag columns
"""
function compute_principal_residence_ownership!(df::DataFrame)
    # Owner of the principal residence (pr_tenure==2)
    df[!, :pr_owner] = coalesce.(df.pr_tenure .== 2, false)
    
    # Partial owner (pr_ownall==2)
    if "pr_ownall" in names(df)
        df[!, :pr_partial_owner] = coalesce.(df.pr_ownall .== 2, false)
    else
        df[!, :pr_partial_owner] .= false
    end
    
    return nothing
end

"""
    fix_principal_residence_percentage!(df::DataFrame)

Fix ownership percentage for principal residence.

Sets `pr_pct` to 100 for full owners and for all owners in early years (≤2005).

# Arguments
- `df`: EFF DataFrame with columns `pr_ownall`, `pr_pct`, `year`, `pr_owner`

# Side Effects
Modifies df.pr_pct in place
"""
function fix_principal_residence_percentage!(df::DataFrame)
    # Full owners: set percentage to 100
    if "pr_ownall" in names(df)
        full_owners = coalesce.(df.pr_ownall .== 1, false)
        df[full_owners, :pr_pct] .= 100
    else
        df.pr_pct .= 100
    end    
    return nothing
end


## -------------------------------------------------------------------------- ##
#### OTHER REAL ESTATE                                                      ####
## -------------------------------------------------------------------------- ##

"""
    fill_missing_real_estate!(df::DataFrame)

Replace missing values with zeros for other real estate variables.

# Arguments
- `df`: EFF DataFrame

# Side Effects
Fills missing values with 0 for real estate value and percentage columns
"""
function fill_missing_real_estate!(df::DataFrame)
    re_value_cols = [:re_val_1, :re_val_2, :re_val_3, :re_val_4]
    re_pct_cols = [:re_pct_1, :re_pct_2, :re_pct_3]
    
    for col in vcat(re_value_cols, re_pct_cols)
        if col in propertynames(df)
            df[!, col] = coalesce.(df[!, col], 0)
        end
    end
    
    # Also fill re_number
    if :re_number in propertynames(df)
        df[!, :re_number] = coalesce.(df.re_number, 0)
    end
    
    return nothing
end


## -------------------------------------------------------------------------- ##
#### REAL ASSETS                                                            ####
## -------------------------------------------------------------------------- ##

"""
    compute_home_asset!(df::DataFrame)

Compute asset value of principal residence.

Creates column `asset_home` = pr_val × pr_pct / 100 for owners, 0 otherwise.

# Arguments
- `df`: EFF DataFrame with columns `pr_owner`, `pr_val`, `pr_pct`

# Side Effects
Adds asset_home column to df
"""
function compute_home_asset!(df::DataFrame)
    df[!, :asset_home] = ifelse.(
        coalesce.(df.pr_owner, false),
        coalesce.(df.pr_val, 0.0) .* coalesce.(df.pr_pct, 0.0) ./ 100,
        0
    )
    return nothing
end

"""
    compute_real_estate_asset!(df::DataFrame)

Compute asset value of other real estate properties.

Creates column `asset_re` summing up to 4 properties with their ownership percentages.

# Arguments
- `df`: EFF DataFrame with columns re_val_i and re_pct_i (i=1:4)

# Side Effects
Adds asset_re column to df
"""
function compute_real_estate_asset!(df::DataFrame)
    df[!, :asset_re] = (
        df.re_val_1 .* df.re_pct_1 ./ 100 .+
        df.re_val_2 .* df.re_pct_2 ./ 100 .+
        df.re_val_3 .* df.re_pct_3 ./ 100 .+
        df.re_val_4
    )
    return nothing
end

"""
    compute_business_assets_early!(df::DataFrame)

Compute business assets for early years (≤2005).

Handles double-counting of properties and cars that may be reported both
individually and as part of business wealth.

# Arguments
- `df`: EFF DataFrame filtered to year ≤ 2005

# Side Effects
Adds asset_business column to df for early years
"""
function compute_business_assets_early!(df::DataFrame)
    # Filter to early years only
    early_mask = df.year .<= 2005
    n_early = sum(early_mask)
    
    if n_early == 0
        return nothing
    end
    
    # Initialize column
    if !(:asset_business in propertynames(df))
        df[!, :asset_business] = zeros(Union{Float64, Missing}, nrow(df))
    end
    
    # Property values for double-counting removal
    prop_values = select(df, [:pr_val, :re_val_1, :re_val_2, :re_val_3, :re_val_4])
    
    # For each person (1-9) and each job (1-3), compute business value
    business_values = zeros(Float64, nrow(df))
    
    for person in 1:9
        for job in 1:3
            # Pattern matching for this person-job combination
            nature_col = Symbol("asset_firm_nature_$(person)_$(job)")
            prop_col = Symbol("asset_firm_property_$(person)_$(job)")
            mktval_col = Symbol("asset_firm_mktval_$(person)_$(job)")
            pct_col = Symbol("asset_firm_ownpct_$(person)_$(job)")
            car_col = Symbol("asset_firm_doublecar_$(person)_$(job)")
            
            # Check if columns exist
            has_cols = all(c -> c in propertynames(df), 
                          [nature_col, prop_col, mktval_col, pct_col])
            
            if !has_cols
                continue
            end
            
            # Get nature (1 = not publicly listed)
            nature = coalesce.(df[!, nature_col] .== 1, false)
            
            # Property value
            prop = coalesce.(df[!, prop_col], 0.0)
            
            # Remove double-counted properties
            prop_removed = zeros(Float64, nrow(df))
            for prop_idx in 1:5
                dummy_col = Symbol("asset_firm_doubleprop$(prop_idx)_$(person)_$(job)")
                if dummy_col in propertynames(df)
                    dummy = coalesce.(df[!, dummy_col], 0.0)
                    prop_val_col = [:pr_val, :re_val_1, :re_val_2, :re_val_3, :re_val_4][prop_idx]
                    prop_removed .+= dummy .* coalesce.(prop_values[!, prop_val_col], 0.0)
                end
            end
            
            # Market value (minus double-counted cars)
            mktval = coalesce.(df[!, mktval_col], 0.0)
            cars_removed = if car_col in propertynames(df)
                coalesce.(df[!, car_col], 0.0)
            else
                zeros(Float64, nrow(df))
            end
            
            # Ownership percentage
            pct = coalesce.(df[!, pct_col], 0.0) ./ 100
            
            # Add to total: (property - removed_property + market - removed_cars) * pct * nature
            business_values .+= (
                (prop .- prop_removed .+ mktval .- cars_removed) .* pct .* nature
            )
        end
    end
    
    df[early_mask, :asset_business] = business_values[early_mask]
    
    return nothing
end

"""
    compute_business_assets_late!(df::DataFrame)

Compute business assets for later years (>2005).

From 2008 onwards, business accounting simplified.

# Arguments
- `df`: EFF DataFrame filtered to year > 2005

# Side Effects
Adds/updates asset_business column to df for later years
"""
function compute_business_assets_late!(df::DataFrame)
    late_mask = df.year .> 2005
    n_late = sum(late_mask)
    
    if n_late == 0
        return nothing
    end
    
    # Initialize column if needed
    if !(:asset_business in propertynames(df))
        df[!, :asset_business] = zeros(Union{Float64, Missing}, nrow(df))
    end
    
    business_values = zeros(Float64, nrow(df))
    
    # Sum asset_firm_val_i * asset_firm_pct_i / 100 for i=1:6
    for i in 1:6
        val_col = Symbol("asset_firm_val_$(i)")
        pct_col = Symbol("asset_firm_pct_$(i)")
        
        if val_col in propertynames(df) && pct_col in propertynames(df)
            business_values .+= (
                coalesce.(df[!, val_col], 0.0) .* 
                coalesce.(df[!, pct_col], 0.0) ./ 100
            )
        end
    end
    
    # Add asset_firm_val_7 (already accounts for ownership percentage)
    if :asset_firm_val_7 in propertynames(df)
        business_values .+= coalesce.(df.asset_firm_val_7, 0.0)
    end
    
    df[late_mask, :asset_business] = business_values[late_mask]
    
    return nothing
end

"""
    compute_business_assets!(df::DataFrame)

Compute business assets for all years.

Dispatches to appropriate function based on year.

# Arguments
- `df`: EFF DataFrame

# Side Effects
Adds asset_business column to df
"""
function compute_business_assets!(df::DataFrame)
    compute_business_assets_early!(df)
    compute_business_assets_late!(df)
    return nothing
end


## -------------------------------------------------------------------------- ##
#### PENSION ASSETS                                                         ####
## -------------------------------------------------------------------------- ##

"""
    compute_pension_sum!(df::DataFrame)

Compute sum of individual pension plans, excluding type 4.

Creates column `asset_pension_sum` by summing pension_1 through pension_10,
excluding those with type==4.

# Arguments
- `df`: EFF DataFrame with pension columns

# Side Effects
Adds asset_pension_sum column to df
"""
function compute_pension_sum!(df::DataFrame)
    pension_sum = zeros(Union{Float64, Missing}, nrow(df))
    
    for i in 1:10
        val_col = Symbol("asset_pension_$(i)")
        type_col = Symbol("asset_pension_type_$(i)")
        
        if val_col in propertynames(df) && type_col in propertynames(df)
            # Add pension value if type != 4
            exclude_type4 = coalesce.(df[!, type_col] .!= 4, true)
            values = coalesce.(df[!, val_col], 0.0)
            pension_sum = coalesce_add.(pension_sum, values .* exclude_type4)
        end
    end
    
    df[!, :asset_pension_sum] = pension_sum
    
    return nothing
end


## -------------------------------------------------------------------------- ##
#### AGGREGATE ASSETS                                                       ####
## -------------------------------------------------------------------------- ##

"""
    compute_funds_sum!(df::DataFrame)

Sum all fund assets (asset_funds_1 through asset_funds_11).

# Arguments
- `df`: EFF DataFrame

# Side Effects
Adds asset_funds_sum column to df
"""
function compute_funds_sum!(df::DataFrame)
    fund_cols = [Symbol("asset_funds_$(i)") for i in 1:11 
                 if Symbol("asset_funds_$(i)") in propertynames(df)]
    
    if isempty(fund_cols)
        df[!, :asset_funds_sum] = zeros(nrow(df))
    else
        # Sum across columns, treating missing as 0
        df[!, :asset_funds_sum] = [sum_na_as_zero(row...) 
                                    for row in eachrow(select(df, fund_cols))]
    end
    
    return nothing
end

"""
    compute_real_assets!(df::DataFrame)

Sum all real assets (home, real estate, business, luxury items).

# Arguments
- `df`: EFF DataFrame

# Side Effects
Adds assets_real column to df
"""
function compute_real_assets!(df::DataFrame)
    real_asset_cols = [:asset_home, :asset_re, :asset_business, :asset_lux]
    existing_cols = filter(c -> c in propertynames(df), real_asset_cols)
    
    df[!, :assets_real] = [sum_na_as_zero(row...) 
                           for row in eachrow(select(df, existing_cols))]
    
    return nothing
end

"""
    compute_financial_assets!(df::DataFrame)

Sum all financial assets.

# Arguments
- `df`: EFF DataFrame

# Side Effects
Adds assets_fin column to df
"""
function compute_financial_assets!(df::DataFrame)
    fin_asset_cols = [
        :asset_bank_house, :asset_bank_unusable, :asset_bank_usable,
        :asset_listed, :asset_funds_sum, :asset_fixedinc,
        :asset_pension, :asset_pension_other,
        :asset_lifeins_1, :asset_lifeins_2, :asset_lifeins_3,
        :asset_lifeins_4, :asset_lifeins_5, :asset_lifeins_6,
        :asset_family, :asset_crypto, :asset_unlisted,
        :asset_otherfin, :asset_managed
    ]
    
    existing_cols = filter(c -> c in propertynames(df), fin_asset_cols)
    
    df[!, :assets_fin] = [sum_na_as_zero(row...) 
                          for row in eachrow(select(df, existing_cols))]
    
    return nothing
end

"""
    compute_total_assets!(df::DataFrame)

Sum all assets (real, financial, cars, furniture).

# Arguments
- `df`: EFF DataFrame

# Side Effects
Adds assets column to df
"""
function compute_total_assets!(df::DataFrame)
    total_asset_cols = [:assets_real, :assets_fin, :asset_cars, :asset_furniture]
    existing_cols = filter(c -> c in propertynames(df), total_asset_cols)
    
    df[!, :assets] = [sum_na_as_zero(row...) 
                      for row in eachrow(select(df, existing_cols))]
    
    return nothing
end


## -------------------------------------------------------------------------- ##
#### DEBTS                                                                  ####
## -------------------------------------------------------------------------- ##

"""
    compute_home_debt!(df::DataFrame)

Compute debt on principal residence.

Sums up to 4 loans on main property, weighted by ownership percentage.

# Arguments
- `df`: EFF DataFrame

# Side Effects
Adds debt_home column to df
"""
function compute_home_debt!(df::DataFrame)
    # Sum pr_loan_1 through pr_loan_4
    loan_cols = [Symbol("pr_loan_$(i)") for i in 1:4 
                 if Symbol("pr_loan_$(i)") in propertynames(df)]
    
    if isempty(loan_cols)
        df[!, :debt_home] = zeros(nrow(df))
        return nothing
    end
    
    loan_sum = [sum_na_as_zero(row...) for row in eachrow(select(df, loan_cols))]
    
    # Weight by ownership percentage for owners, 0 for non-owners
    df[!, :debt_home] = ifelse.(
        coalesce.(df.pr_owner, false),
        loan_sum .* coalesce.(df.pr_pct, 0.0) ./ 100,
        0
    )
    
    return nothing
end

"""
    compute_real_estate_debts!(df::DataFrame)

Compute debts on other real estate properties.

For each property (1-4), sums loans weighted by ownership percentage.

# Arguments
- `df`: EFF DataFrame

# Side Effects
Adds debt_re_1 through debt_re_4 and debt_re_sum columns to df
"""
function compute_real_estate_debts!(df::DataFrame)
    # Process properties 1-3 (with up to 3 loans each)
    for prop in 1:3
        debt_col = Symbol("debt_re_$(prop)")
        pct_col = Symbol("re_pct_$(prop)")
        
        loan_cols = [Symbol("re_$(prop)_loan_$(i)") for i in 1:3 
                     if Symbol("re_$(prop)_loan_$(i)") in propertynames(df)]
        
        if isempty(loan_cols)
            df[!, debt_col] = zeros(nrow(df))
            continue
        end
        
        loan_sum = [sum_na_as_zero(row...) for row in eachrow(select(df, loan_cols))]
        
        # Weight by percentage if owner of >= prop properties
        has_property = coalesce.(df.re_number .>= prop, false)
        pct = pct_col in propertynames(df) ? coalesce.(df[!, pct_col], 100.0) : fill(100.0, nrow(df))
        
        df[!, debt_col] = ifelse.(
            has_property,
            loan_sum .* pct ./ 100,
            0
        )
    end
    
    # Property 4 (direct from re_4_loans)
    if :re_4_loans in propertynames(df)
        has_property = coalesce.(df.re_number .>= 4, false)
        df[!, :debt_re_4] = ifelse.(has_property, coalesce.(df.re_4_loans, 0), 0)
    else
        df[!, :debt_re_4] = zeros(nrow(df))
    end
    
    # Sum all real estate debts
    re_debt_cols = [Symbol("debt_re_$(i)") for i in 1:4]
    df[!, :debt_re_sum] = [sum_na_as_zero(row...) 
                           for row in eachrow(select(df, re_debt_cols))]
    
    return nothing
end

"""
    compute_other_debts!(df::DataFrame)

Sum other debts (debt_other_1 through debt_other_9).

# Arguments
- `df`: EFF DataFrame

# Side Effects
Adds debt_other_sum column to df
"""
function compute_other_debts!(df::DataFrame)
    debt_cols = [Symbol("debt_other_$(i)") for i in 1:9 
                 if Symbol("debt_other_$(i)") in propertynames(df)]
    
    if isempty(debt_cols)
        df[!, :debt_other_sum] = zeros(nrow(df))
    else
        df[!, :debt_other_sum] = [sum_na_as_zero(row...) 
                                   for row in eachrow(select(df, debt_cols))]
    end
    
    return nothing
end

"""
    compute_total_debts!(df::DataFrame)

Sum all debts (home, real estate, other, credit card).

# Arguments
- `df`: EFF DataFrame

# Side Effects
Adds debts column to df
"""
function compute_total_debts!(df::DataFrame)
    debt_cols = [:debt_home, :debt_re_sum, :debt_other_sum, :debt_ccard]
    existing_cols = filter(c -> c in propertynames(df), debt_cols)
    
    df[!, :debts] = [sum_na_as_zero(row...) 
                     for row in eachrow(select(df, existing_cols))]
    
    return nothing
end


## -------------------------------------------------------------------------- ##
#### MAIN FUNCTION                                                          ####
## -------------------------------------------------------------------------- ##

"""
    compute_net_wealth!(df::DataFrame)

Compute net wealth for EFF data.

Executes full wealth calculation pipeline:
1. Principal residence ownership and values
2. Other real estate assets
3. Business assets (different methods for early vs. late years)
4. Pension assets
5. Other financial assets
6. All debts
7. Net wealth = assets - debts

# Arguments
- `df`: EFF individual-level DataFrame

# Side Effects
Adds numerous wealth-related columns to df, culminating in `net_wealth`

# Examples
```
eff = read_eff(data_dir="/data/EFF")
compute_net_wealth!(eff)
describe(eff, :net_wealth)
```
"""
function compute_net_wealth!(df::DataFrame)
    # Principal residence
    compute_principal_residence_ownership!(df)
    fix_principal_residence_percentage!(df)
    
    # Other real estate
    fill_missing_real_estate!(df)
    
    # Real assets
    compute_home_asset!(df)
    compute_real_estate_asset!(df)
    compute_business_assets!(df)
    
    # Financial assets
    compute_pension_sum!(df)
    compute_funds_sum!(df)
    compute_real_assets!(df)
    compute_financial_assets!(df)
    compute_total_assets!(df)
    
    # Debts
    compute_home_debt!(df)
    compute_real_estate_debts!(df)
    compute_other_debts!(df)
    compute_total_debts!(df)
    
    # Net wealth
    df[!, :wealth] = df.assets .- df.debts
    
    return nothing
end
