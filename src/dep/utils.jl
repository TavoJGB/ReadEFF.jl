get_household_id_var(; year::Int, kwargs...) =  year == 2002 ? "h_number" : "h_$(year)"

filefinder(dir::String; year::Int, imputation::Int) = [
    joinpath(dir, "section6_$(year)_imp$(imputation).csv");
    joinpath(dir, "other_sections_$(year)_imp$(imputation).csv")
]


function compute_age_if_missing!(eff_ii::DataFrame)
    if "age" in names(eff_ii)
        eff_ii[!, :age] .= @. ifelse(ismissing(eff_ii.age) & !ismissing(eff_ii.birthyear), eff_ii.year - eff_ii.birthyear, eff_ii.age)
    elseif "birthyear" in names(eff_ii)
        eff_ii[!, :age] = @. eff_ii.year - eff_ii.birthyear
    end
    return nothing
end



function eff_tenure!(eff::DataFrame)
    eff.h_tenure = map(eff.pr_tenure) do val
        if val == 1
            return :renter
        elseif val == 2
            return :owner
        elseif val == 3
            return :notenure
        else
            return missing
        end
    end
    return nothing
end