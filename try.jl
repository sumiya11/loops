
macro einsum(expr)
    lhs, rhs = expr.args[1], expr.args[2]

    lhsarrays, lhsindices, lhsconstraints = extractindices(lhs)

    rhsarrays, rhsindices, rhsconstraints = extractindices(rhs)

    idx2constraints = Dict{Symbol, Vector{Expr}}()
    newrhsindices = copy(rhsindices)
    j = 1
    for (i, idx) in enumerate(newrhsindices)
        if haskey(idx2constraints, idx)
            push!(idx2constraints[idx], rhsconstraints[j])
            deleteat!(rhsindices, j)
            deleteat!(rhsconstraints, j)
        else
            idx2constraints[idx] = Expr[]
            push!(idx2constraints[idx], rhsconstraints[j])
            j += 1
        end
    end

    for (i, idx) in enumerate(lhsindices)
        lhsconstraints[i] = first(idx2constraints[idx])
    end

    dimensionchecks = Expr[]
    for (idx, constraints) in idx2constraints
        push!(dimensionchecks, :(@assert reduce(isequal, [$(constraints...)], init=true)))
    end

    # output
    @gensym T

    # infer type
    rhstype = :(promote_type($([:(eltype($arr)) for arr in rhsarrays]...)))

    typedefinition = :(local $T = $rhstype)

    if length(lhsconstraints) > 0
        outputdefinition = :(local $(lhsarrays[1]) = zeros($T, $(lhsconstraints...)))
    else
        outputdefinition = :(local $(lhsarrays[1]) = zero($T))
    end
    assignmentop = :(=)

    loopexpr = expr

    @gensym s
    # loopexpr.args[1] = s
    loopexpr.head = :(+=)

    # Nest loops to iterate over the summed out variables
    loopexpr = nestloops(loopexpr, rhsindices, rhsconstraints)

    # Prepend with s = 0, and append with assignment
    # to the left hand side of the equation.
    lhsassignment = Expr(assignmentop, lhs, s)

    loopexpr = quote
        # local $s = zero($T)
        $loopexpr
        # $lhsassignment
    end

    loopexpr = :(@inbounds $loopexpr)

    full_expression = quote
        $typedefinition
        $outputdefinition
        # $(dimensionchecks...)

        let $([lhsindices; rhsindices]...)
            $loopexpr
        end

        $(lhsarrays[1])
    end

    return esc(full_expression)
end

###############################################################################

function nestloops(expr::Expr, indexnames::Vector{Symbol}, constraints::Vector{Expr})
    isempty(indexnames) && return expr

    # Add @simd to the innermost loop
    expr = nestloop(expr, indexnames[1], constraints[1], Val(:nosimd))

    # Add remaining for loops
    for j = 2:length(indexnames)
        expr = nestloop(expr, indexnames[j], constraints[j], Val(:nosimd))
    end

    return expr
end

function nestloop(expr::Expr, indexname::Symbol, constraint::Expr, ::Val{:simd})
    loop = :(for $indexname = 1:$constraint
                 $expr
             end)
    return :(@simd $loop)
end

function nestloop(expr::Expr, indexname::Symbol, constraint::Expr, ::Val{:nosimd})
    loop = :(for $indexname = 1:$constraint
                 $expr
             end)
    return loop
end

###############################################################################

function extractindices(expr)
    arrays, indices, constraints = Symbol[], Symbol[], Expr[]
    extractindices!(expr, arrays, indices, constraints)
    arrays, indices, constraints
end

function extractindices!(idx::Symbol, arr, i, arrays, indices, constraints)
    push!(indices, idx)
    push!(constraints, :(size($arr, $i)))
end

function extractindices!(idx::Number, arr, i, arrays, indices, constraints)
    # pass
end

function extractindices!(expr::Expr, arr::Symbol, i, arrays, indices, constraints)
    for idx in expr.args
        extractindices!(idx, arr, i, arrays, indices, constraints)
    end
end

function extractindices!(expr::Expr, arr::Symbol, head::Val{:call}, i, arrays, indices, constraints)
    for idx in expr.args[2:end]
        extractindices!(idx, arr, i, arrays, indices, constraints)
    end
end

function extractindices!(expr::Expr, arr::Symbol, i, arrays, indices, constraints)
    extractindices!(expr, arr, Val(expr.head), i, arrays, indices, constraints)
end

function extractindices!(expr::Expr, head::Val{:ref}, arrays, indices, constraints)
    arr = first(expr.args)
    push!(arrays, arr)
    for (i, idx) in enumerate(expr.args[2:end])
        extractindices!(idx, arr, i, arrays, indices, constraints)
    end
end

function extractindices!(expr::Expr, head::Val{:call}, arrays, indices, constraints)
    for e in expr.args[2:end]
        extractindices!(e, arrays, indices, constraints)
    end
end

function extractindices!(expr::Expr, head, arrays, indices, constraints)
    for e in expr.args
        extractindices!(e, arrays, indices, constraints)
    end
end

function extractindices!(expr::Expr, arrays, indices, constraints)
    extractindices!(expr, Val(expr.head), arrays, indices, constraints)
end

function extractindices!(expr::Symbol, arrays, indices, constraints)
    push!(arrays, expr)
end

function extractindices!(expr, arrays, indices, constraints)
    # pass
end
