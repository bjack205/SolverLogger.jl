
"Log Level for outer loop iterations (e.g. Augmented Lagrangian). LogLevel(-100)"
const OuterLoop = LogLevel(-100)
"Log Level for inner loop iterations (e.g. iLQR). LogLevel(-200)"
const InnerLoop = LogLevel(-200)
"Log Level for internal solve methods (e.g. forward pass for iLQR). LogLevel(-500)"
const InnerIters = LogLevel(-500)

function default_logger(verbose::Bool)
    verbose == false ? min_level = Logging.Warn : min_level = InnerLoop

    logger = SolverLogger(min_level)
    inner_cols = [:iter, :cost, :expected, :z, :α, :info]
    inner_widths = [5,     14,      12,    10, 10,    50]
    outer_cols = [:iter, :total, :c_max, :info]
    outer_widths = [6,          7,        12,        50]
    add_level!(logger, InnerLoop, inner_cols, inner_widths, print_color=:green,indent=4)
    add_level!(logger, OuterLoop, outer_cols, outer_widths, print_color=:yellow,indent=0)
    return logger
end


"""
    LogData

Holds logging information about a particular print level, meant to assemble
a table of output where `cols` gives the order and names of columns, `widths`
are the column widths, and `print` will turn on/off printing the column.

All values can be cached at any moment in time to accumulate a history of the
data.

# Constructors
```julia
LogData(metadata::NamedTuple=(color=:default, header_frequency=10, indent=0))
LogData(cols, widths; do_print=trues(length(cols)), vartypes=fill(Any, length(cols)),
    color=:default, header_frequency=10, indent=0)
```
"""
mutable struct LogData
    cols::Vector{Symbol}
    widths::Vector{Int}
    print::BitArray{1}
    data::Dict{Symbol,Any}
    cache::Dict{Symbol,Vector}
    freq::Int
    color::Symbol
    indent::Int
    function LogData(cols,widths,print::BitArray{1},data::Dict{Symbol,Any},
            cache::Dict{Symbol,Vector}, freq::Int,color::Symbol,indent::Int)
        new(cols,widths,print,data,cache,freq,color,indent)
    end
end

Base.getindex(ldata::LogData,index::Symbol) = ldata.data[index]

function LogData(;header_frequency=10, color=:default, indent=0)
    LogData(Symbol[],Int[],BitArray{1}(), Dict{Symbol,Any}(),Dict{Symbol,Vector}(),
        header_frequency, color, indent)
end

function LogData(cols,widths; do_print=trues(length(cols)), vartypes=fill(Any,length(cols)),
        color=:default, header_frequency=10, indent=0)
    ldata = LogData(header_frequency=header_frequency, color=color, indent=indent)
    for (col,width,prnt,vartype) in zip(cols,widths,do_print,vartypes)
        add_col!(ldata,col,width,do_print=prnt,vartype=vartype)
    end
    ldata
end

"""
    cache_data!(ldata)

Store the current data in the cache
"""
function cache_data!(ldata::LogData)
    for (key,val) in ldata.data
        if isempty(val)
            if eltype(ldata.cache[key]) <: AbstractFloat
                val = NaN
            elseif eltype(ldata.cache[key]) <: Integer
                val = 0
            end
        end
        push!(ldata.cache[key],val)
    end
end

"""
    cache_size(ldata)

Size of the current cache
"""
function cache_size(ldata::LogData)
    if isempty(ldata.cols) || isempty(ldata.cache)
        return 0
    else
        return length(ldata.cache[ldata.cols[1]])
    end
end

"""
    clear!(ldata)

Clear the current data fields (not the cache)
"""
function clear!(ldata::LogData)
    for key in keys(ldata.data)
        if key == :info
            ldata.data[key] = String[]
        else
            ldata.data[key] = ""
        end
    end
end

"""
    clear_cache!(ldata)

Clear the cache from the log data
"""
function clear_cache!(ldata::LogData)
    for key in keys(ldata.data)
        if key == :info
            ldata.cache[key] = Vector{Vector{String}}()
        else
            ldata.cache[key] = Vector{eltype(ldata.cache[key])}()
        end
    end
end

"""
    add_col!(ldata::LogData, name::Symbol, width=10, idx=0, do_print=true, vartype=Any)

Add a column to the table
# Arguments
* idx: specify the order in the table. 0 will insert at the end, and any negative number will index from the end
* do_print: specify whether the variable should be printed or just kept for caching purposes. Default=true
* vartype: Type of the variable (recommended). Default=Any
"""
function add_col!(ldata::LogData,name::Symbol,width::Int=10,idx::Int=0; do_print::Bool=true, vartype::Type=Any)
    # Don't add a duplicate column
    if name ∈ ldata.cols; return nothing end

    # Set location
    name == :info ? idx = 0 : nothing
    if idx <= 0
        idx = length(ldata.cols) + 1 + idx
    end

    # Add to ldata
    if name == :info
        ldata.data[name] = String[]
        ldata.cache[name] = Vector{String}[]
    else
        ldata.data[name] = ""
        ldata.cache[name] = Vector{vartype}(undef,cache_size(ldata))
    end
    insert!(ldata.cols,idx,name)
    insert!(ldata.widths,idx,width)
    insert!(ldata.print,idx,do_print)

    return nothing
end

"""
    create_header(ldata, delim="")

Create the header row (returns a string)
"""
function create_header(ldata::LogData, delim::String="")
    indent = ldata.indent
    repeat(" ",indent) * join([rpad(col, width) for (col,width,do_print) in zip(ldata.cols,ldata.widths,ldata.print) if do_print],delim) * "\n" * repeat("_",indent) * repeat('-',sum(ldata.widths)) *"\n"
end

"""
    create_row(ldata)

Create a data row (returns a string)
"""
function create_row(ldata::LogData)
    indent = ldata.indent
    row = repeat(" ",indent) * join([begin rpad(trim_entry(ldata.data[col],width),width) end for (col,width,do_print) in zip(ldata.cols,ldata.widths,ldata.print) if col != :info && do_print])
    if :info in ldata.cols
        row *= join(ldata.data[:info],". ")
    end
    return row
end

function trim_entry(data::Float64,width::Int; pad=true, kwargs...)
    base = log10(abs(data))
    if -ceil(width/2)+1 < base < floor(width / 2) && isfinite(data)
        if base > 0
            prec = width - ceil(Int,base) - 3
        else
            prec = width - 4
        end
        if prec <= 0
            width = width - prec + 1
            prec = 1
        end
        val = format(data,precision=prec,conversion="f",stripzeros=true,positivespace=true; kwargs...)
    elseif !isfinite(data)
        val = string(data)
    else
        width <= 8 ? width = 10 : nothing
        val = format(data,conversion="e",precision=width-8,stripzeros=true,positivespace=true; kwargs...)
    end
    if pad
        val = rpad(val,width)
    end
    return val
end

function trim_entry(data::String,width; pad=true)
    if length(data) > width-2
        return data[1:width-2]
    end
    return data
end

function trim_entry(data::Int, width::Int; pad=true, kwargs...)
    if pad
        rpad(format(data; kwargs...), width)
    else
        format(data; kwargs...)
    end
end

function trim_entry(data,width; pad=true, kwargs...)
    data
end





"""
    SolverLogger <: Logging.AbstractLogger

Logger class for generating output in a tabular format (by iteration)

In general, only levels "registered" with the logger will be used, otherwise
they are passed off to the global logger. Typical use will include setting up
the LogLevels that will be logged as tables, and then using @logmsg to send
information to the logger. When enough data has been gathered, the user can then
print a row for a certain level.
"""
struct SolverLogger <: Logging.AbstractLogger
    io::IO
    min_level::LogLevel
    default_width::Int
    leveldata::Dict{LogLevel,LogData}
    default_logger::ConsoleLogger
end

Base.getindex(logger::SolverLogger, level::LogLevel) = logger.leveldata[level]


function SolverLogger(min_level::LogLevel=Logging.Info; default_width=10, io::IO=stderr,
        default_logger=ConsoleLogger(stderr, min_level))
    SolverLogger(io,min_level,default_width,Dict{LogLevel,LogData}(), default_logger)
end

"""
    add_level!(logger, level::LogLevel, cols, widths; print_color=:default)

"Register" a level with the logger, creating a LogData entry responsible for storing
data generated at that level. Additional keyword arguments (from LogData constructor)

* vartypes = Vector of variable types for each column
* do_print = BitArray specifying whether or now the column should be printed (or just cached and not printed)
"""
function add_level!(logger::SolverLogger, level::LogLevel, cols=Symbol[], widths=Int[],
        vartypes=fill(Any,length(cols)); print_color=:default, indent=0, kwargs...)
    logger.leveldata[level] = LogData(cols, widths, vartypes=vartypes,
        color=print_color, indent=indent; kwargs...)
end


function print_level(level::LogLevel, logger=current_logger())
    ldata = logger[level]
    if cache_size(ldata) % ldata.freq == 0
        print_header(logger,level)
    end
    print_row(logger,level)
end

"""
    print_header(logger::SolverLogger, level::LogLevel)

Print the header row for a given level (in color)
"""
function print_header(logger::SolverLogger,level::LogLevel)
    if level in keys(logger.leveldata) && level >= logger.min_level
        ldata = logger.leveldata[level]
        printstyled(logger.io,create_header(ldata),
            bold=true,color=ldata.color)
        # clear_cache!(logger.leveldata[level])
    end
end

"""
    print_row(logger:SolverLogger, level::LogLevel)

Print a row of data and cache it with LogData
"""
function print_row(logger::SolverLogger,level::LogLevel)
    if level >= logger.min_level
        flush(logger.io)
        ldata = logger.leveldata[level]
        row = create_row(ldata)
        println(logger.io, row)
        cache_data!(ldata)
        clear!(ldata)
    end
end



"""
    handle_message(logger::SolverLogger, level, message, _module, group, id, file, line;
        value=NaN, print=true, loc=-1, width=logger.default_width())

Send data from log events to LogData columns
The message needs to be a symbol that corresponds to the column name
The value is provided as a keyword argument `value=...`
If the level is not "registered" it is passed on to the global logger

If the message is not in the list of columns, it will be added, in which case
the type is inferred from the value and printing can be specified.

Usage Example:
@info :myvar value=10.2  # Sends a value of 10.2 to the column "myvar"

"""
function Logging.handle_message(logger::SolverLogger, level, message::Symbol, _module, group,
        id, file, line; value=NaN, print=true, loc=-1, width=logger.default_width)
    if level in keys(logger.leveldata)
        if level >= logger.min_level
            ldata = logger.leveldata[level]
            if !(message in ldata.cols)
                :info in ldata.cols ? idx = loc : idx = 0  # add before last "info" column
                width = max(width,length(string(message))+1)
                add_col!(ldata, message, width, idx, do_print=print, vartype=typeof(value))
            end
            logger.leveldata[level].data[message] = value
        end
    else level >= logger.min_level
        # Pass off to global logger
        Logging.handle_message(logger.default_logger, level, message, _module, group, id, file, line)
    end
end

function Logging.handle_message(logger::SolverLogger, level, message::String, _module, group, id, file, line; value=NaN)
    if level in keys(logger.leveldata)
        if level >= logger.min_level
            ldata = logger.leveldata[level]
            if !(:info in ldata.cols)
                add_col!(ldata, :info, 20)
                ldata.data[:info] = String[]
            end
            # Append message to info field
            push!(ldata.data[:info], message)
        end
    else
        # Pass off to global logger
        Logging.handle_message(logger.default_logger, level, message, _module, group, id, file, line)
    end
end

function Logging.shouldlog(logger::SolverLogger, level, _module, group, id)
    true  # Accept everything
end

function Logging.min_enabled_level(logger::SolverLogger)
    return logger.min_level
end
