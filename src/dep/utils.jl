get_household_id_var(; year::Int, kwargs...) =  year == 2002 ? "h_number" : "h_$(year)"

filefinder(dir::String; year::Int, imputation::Int) = [
    joinpath(dir, "section6_$(year)_imp$(imputation).csv");
    joinpath(dir, "other_sections_$(year)_imp$(imputation).csv")
]

function get_current_variables(varlist; year::Int, kwargs...)
    # Filter rows valid for this year
    valid_rows = (varlist.firsttime .<= year) .& (varlist.lasttime .>= year)
    
    # Create mapping: standardized name => EFF column name
    return Dict(zip(varlist[valid_rows, :varkey], varlist[valid_rows, :varname]))
end


function compute_age_if_missing!(eff_ii::DataFrame)
    if "age" in names(eff_ii)
        eff_ii[!, :age] .= @. ifelse(ismissing(eff_ii.age) & !ismissing(eff_ii.birthyear), eff_ii.year - eff_ii.birthyear, eff_ii.age)
    elseif "birthyear" in names(eff_ii)
        eff_ii[!, :age] = @. eff_ii.year - eff_ii.birthyear
    end
    return nothing
end



function eff_tenure!(eff::DataFrame)
    eff.h_tenure = map(eff.pr_tenure, eff.head) do val, head
        if !head
            return NoHead
        elseif val == 1
            return Renter
        elseif val == 2
            return Owner
        elseif val == 3
            return NoTenure
        else
            return missing
        end
    end
    return nothing
end