function preprocess(vars)
    # Add variables needed to compute net wealth
    aux_hvars = filter(:level => ( h -> (h=="household") ), vars)
    wealthlist_path = joinpath(BASE_FOLDER, "var_lists", "eff_vars_wealth.csv")
    wealthlist = filter(:varkey => key -> !(key ∈ aux_hvars.varkey), CSV.read(wealthlist_path, DataFrame; comment="#"))
    # Flag auxiliary variables
    vars.type .= "User"
    wealthlist.level .= "household"
    wealthlist.type .= "Internal"
    # Return updated lists
    return vcat(vars, wealthlist)
end

function _ensure_internal_wealth_aliases!(df::DataFrame, vars::DataFrame)
    wealthlist_path = joinpath(BASE_FOLDER, "var_lists", "eff_vars_wealth.csv")
    wealthlist = CSV.read(wealthlist_path, DataFrame; comment="#")

    # If a required internal wealth variable is missing by its canonical name,
    # recover it from any user-selected alias sharing the same varkey.
    for row in eachrow(wealthlist)
        canonical = Symbol(row.varname)
        canonical in propertynames(df) && continue

        candidate_names = vars.varname[vars.varkey .== row.varkey]
        for candidate in candidate_names
            candidate_sym = Symbol(candidate)
            if candidate_sym in propertynames(df)
                df[!, canonical] = df[!, candidate_sym]
                break
            end
        end
    end

    return nothing
end

_normalize_level_name(level::AbstractString) = Symbol(replace(lowercase(strip(level)), " " => "_", "-" => "_"))

function _get_level_name(varlist::DataFrame)
    levels = unique(varlist.level)
    length(levels) == 1 || throw(ErrorException("Each varlist must contain a single level"))
    return _normalize_level_name(string(only(levels)))
end

function _drop_missing_type_if_possible!(df::DataFrame)
    for col in names(df)
        if !any(ismissing, df[!, col])
            df[!, col] = disallowmissing(df[!, col])
        end
    end
    return nothing
end

function _drop_fully_missing_payload_rows!(df::DataFrame, id_cols::Vector{Symbol})
    payload_cols = filter(col -> !(col in id_cols), Symbol.(names(df)))
    isempty(payload_cols) && return nothing

    filter!(row -> any(col -> !ismissing(row[col]), payload_cols), df)
    return nothing
end

function _has_indexed_suffix(col::AbstractString, key::AbstractString)
    prefix = key * "_"
    startswith(col, prefix) || return false
    suffix = col[(ncodeunits(prefix) + 1):end]
    return !isempty(suffix) && all(isdigit, suffix)
end

function _pivot_if_needed(df::DataFrame, level::Symbol, c_vars::Dict)
    level == :household && return (deepcopy(df), Symbol[])
    isempty(c_vars) && return (deepcopy(df), Symbol[])

    has_indexed_columns = any(keys(c_vars)) do key
        any(col -> _has_indexed_suffix(string(col), key), names(df))
    end
    has_indexed_columns || return (deepcopy(df), Symbol[])

    id_vars = [:year, :imputation, :hid]
    pivot_key = level == :individual ? :individual : level
    return DataReader.pivot_longer(df, id_vars, c_vars; pivot_key), [pivot_key]
end

function postprocess(args...)

    length(args) % 2 == 0 || throw(ArgumentError("postprocess expects dataframes and varlists in pairs"))
    nlevels = length(args) ÷ 2

    dfs = args[1:nlevels]
    varlists = args[(nlevels + 1):end]

    all(df -> df isa DataFrame, dfs) || throw(ArgumentError("Invalid dataframe inputs in postprocess"))
    all(vs -> vs isa DataFrame, varlists) || throw(ArgumentError("Invalid varlist inputs in postprocess"))

    year = only(unique(dfs[1].year))
    h_ids = [:year, :hid, :imputation]

    level_order = [_get_level_name(vs) for vs in varlists]
    processed = Dict{Symbol, DataFrame}()
    ids_by_level = Dict{Symbol, Vector{Symbol}}()

    # Per-level generic processing
    for i in eachindex(level_order)
        level = level_order[i]
        raw_df = dfs[i]
        vars = varlists[i]

        c_vars = DataReader.get_time_filtered_variables(vars; year)
        level_df, extra_ids = _pivot_if_needed(raw_df, level, c_vars)
        rename!(level_df, c_vars)

        level_ids = [h_ids; extra_ids]
        all(id -> id in names(level_df), level_ids) && sort!(level_df, level_ids)

        processed[level] = level_df
        ids_by_level[level] = level_ids
    end

    # Specific logic: individual level
    if haskey(processed, :individual)
        ii_final = processed[:individual]

        # Keep only the actual individuals in each household
        # - Size of the household
        leftjoin!(ii_final, select(processed[:household], [h_ids; :h_size]), on=h_ids)
        # - Remove empty observations (# individual > household size)
        filter!(row -> !ismissing(row.h_size) && row.individual <= row.h_size, ii_final)

        # Additional variables
        # - Age
        compute_age_if_missing!(ii_final)
        # - Head of household
        head = (ii_final.rel2hh .== 1)
        ii_final[!, :head] = ifelse.(ismissing.(head), false, head)
        begin # Correction: there are two heads in this household
            ii_final[(ii_final.year .== 2022) .& (ii_final.hid .== 3671) .& (ii_final.individual .== 3), :head] .= false
        end
        # - Individual identifier
        ii_final[!, :id] = ii_final.hid .* 10 .+ ii_final.individual

        processed[:individual] = ii_final
    end

    # Specific logic: household level
    if haskey(processed, :household)
        hh_final = processed[:household]

        household_idx = findfirst(==( :household), level_order)
        if !isnothing(household_idx)
            _ensure_internal_wealth_aliases!(hh_final, varlists[household_idx])
        end

        compute_net_wealth!(hh_final)
        eff_tenure!(hh_final)

        if :c_wgt in names(hh_final)
            rename!(hh_final, :c_wgt => :weight)
        end

        processed[:household] = hh_final
    end

    # Final selection and cleanup per level
    for i in eachindex(level_order)
        level = level_order[i]
        level_df = processed[level]
        vars = varlists[i]

        # Keep only requested variables
        user_vars = DataReader.get_selected_varnames(
            filter(:type => t -> t == "User", vars);
            variable_mapper=DataReader.get_time_filtered_variables,
            year
        )
        computed_vars = level == :individual ? ["head", "age", "id"] :
                        level == :household ? ["h_tenure", "wealth", "weight"] :
                        String[]
        keep_cols = unique([string.(ids_by_level[level]); computed_vars; user_vars])
        keep_cols = filter(col -> col in names(level_df), keep_cols)
        select!(level_df, keep_cols)

        # For extra pivoted levels (e.g. real_estate), drop rows with no payload data.
        # Generated identifiers alone are not informative observations.
        if (level != :individual) && (length(ids_by_level[level]) > length(h_ids))
            _drop_fully_missing_payload_rows!(level_df, ids_by_level[level])
        end

        # Remove Missing type from columns that no longer have missing values
        _drop_missing_type_if_possible!(level_df)

        if :year in names(level_df)
            level_df[!, :year] .-= 1
        end

        processed[level] = level_df
    end

    # Return in the same order expected by read_multilevel_database
    return [processed[level] for level in level_order]
end


# Read EFF
read_eff(datadir::String, identifier_ranges; kwargs...) = read_multilevel_database(
    datadir, identifier_ranges, get_household_id_var;
    filefinder, preprocess, postprocess, do_rename=false,
    variable_mapper=DataReader.get_time_filtered_variables, kwargs...
)