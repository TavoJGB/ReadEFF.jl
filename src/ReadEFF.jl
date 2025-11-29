module ReadEFF

    using CSV, DataFrames
    using DataReader    # https://github.com/TavoJGB/DataReader.jl

    BASE_FOLDER = dirname(@__DIR__)

    # Load dependencies
    include(joinpath(BASE_FOLDER, "src", "dep", "utils.jl"))
    include(joinpath(BASE_FOLDER, "src", "dep", "wealth_eff.jl"))
    include(joinpath(BASE_FOLDER, "src", "dep", "setup_reader.jl"))
        export read_eff

end
