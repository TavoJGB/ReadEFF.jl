function preprocess(ivars, hvars)
    # Add variables needed to compute net wealth
    wealthlist_path = joinpath(BASE_FOLDER, "var_lists", "eff_vars_wealth.csv")
    wealthlist = filter(:varkey => key -> !(key ∈ hvars.varkey), CSV.read(wealthlist_path, DataFrame; comment="#"))
    # Flag auxiliary variables
    ivars.type .= "User"
    hvars.type .= "User"
    wealthlist.type .= "Internal"
    # Return updated lists
    return ivars, vcat(hvars, wealthlist)
end

function postprocess(df_ii::DataFrame, df_hh::DataFrame, ivars::DataFrame, hvars::DataFrame)
    
    # Auxiliary
    h_ids = [:year; :hid; :imputation]
    i_ids = [h_ids; :individual]
    
    # Initialize final dataframes
    ii_final = deepcopy(df_ii)
    hh_final = deepcopy(df_hh)

    # Sorting
    sort!(ii_final, i_ids)
    sort!(hh_final, h_ids)

    # Keep only the actual individuals in each household
    # - Size of household
    leftjoin!(ii_final, select(hh_final, [h_ids; :h_size]), on=h_ids)
    # - Remove empty observations
    filter!(row -> row.individual <= row.h_size, ii_final)
    # - Remove Missing type from columns that no longer have missing values
    for col in names(ii_final)
        if !any(ismissing, ii_final[!, col])
            ii_final[!, col] = disallowmissing(ii_final[!, col])
        end
    end
    for col in names(hh_final)
        if !any(ismissing, hh_final[!, col])
            hh_final[!, col] = disallowmissing(hh_final[!, col])
        end
    end

    # Additional variables
    # - Age
    compute_age_if_missing!(ii_final)
    # - Head of household
    head = (ii_final.rel2hh .== 1)
    ii_final[!, :head] = ifelse.(ismissing.(head), false, head)
    begin # Correction: there are two heads in this household
        ii_final[(ii_final.year.==2022) .& (ii_final.hid.==3671) .& (ii_final.individual.==3), :head] .= false
        ii_final[(ii_final.year.==2022) .& (ii_final.hid.==3671) .& (ii_final.individual.==3), :rel2hh] .= missing
    end
    # - Individual identifier
    ii_final[!, :id] = ii_final.hid .* 10 .+ ii_final.individual
    # - Net wealth
    compute_net_wealth!(hh_final)
    # - Housing tenure
    # eff_tenure!(ii_final)
    
    # Keep only requested variables
    select!(ii_final, [string.(i_ids); "head"; filter(:type => t -> t == "User", ivars).varname])
    select!(hh_final, [string.(h_ids); "wealth" ; filter(:type => t -> t == "User", hvars).varname])

    # Weights PROVISIONAL
    rename!(hh_final, :c_wgt => :weight)

    # Return
    return ii_final, hh_final
end


# Read EFF
read_eff(datadir::String, identifier_ranges; kwargs...) = read_database(
    datadir, identifier_ranges, get_household_id_var; filefinder, preprocess, postprocess,
    get_current_variables, kwargs...
)