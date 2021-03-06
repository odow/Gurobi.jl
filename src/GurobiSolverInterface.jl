# GurobiMathProgInterface
# Standardized MILP interface

export GurobiSolver

type GurobiMathProgModel <: AbstractMathProgModel
    inner::Model
    last_op_type::Symbol  # To support arbitrary order of addVar/addCon
                          # Two possibilities :Var :Con
    lazycb
    cutcb
    heuristiccb
    infocb
end
function GurobiMathProgModel(;options...)
   env = Env()
   setparam!(env, "InfUnbdInfo", 1)
   for (name,value) in options
       setparam!(env, string(name), value)
   end
   m = GurobiMathProgModel(Model(env,""; finalize_env=true), :Con, nothing, nothing, nothing, nothing)
   return m
end


immutable GurobiSolver <: AbstractMathProgSolver
    options
end
GurobiSolver(;kwargs...) = GurobiSolver(kwargs)
model(s::GurobiSolver) = GurobiMathProgModel(;s.options...)

loadproblem!(m::GurobiMathProgModel, filename::String) = read_model(m.inner, filename)

function loadproblem!(m::GurobiMathProgModel, A, collb, colub, obj, rowlb, rowub, sense)
  reset_model!(m.inner)
  add_cvars!(m.inner, float(obj), float(collb), float(colub))
  update_model!(m.inner)

  neginf = typemin(eltype(rowlb))
  posinf = typemax(eltype(rowub))

  # check if we have any range constraints
  # to properly support these, we will need to keep track of the 
  # slack variables automatically added by gurobi.
  rangeconstrs = any((rowlb .!= rowub) & (rowlb .> neginf) & (rowub .< posinf))
  if rangeconstrs
      warn("Julia Gurobi interface doesn't properly support range (two-sided) constraints. See Gurobi.jl issue #14")
      add_rangeconstrs!(m.inner, float(A), float(rowlb), float(rowub))
  else
      b = Array(Float64,length(rowlb))
      senses = Array(Cchar,length(rowlb))
      for i in 1:length(rowlb)
          if rowlb[i] == rowub[i]
              senses[i] = '='
              b[i] = rowlb[i]
          elseif rowlb[i] > neginf
              senses[i] = '>'
              b[i] = rowlb[i]
          else
              @assert rowub[i] < posinf
              senses[i] = '<'
              b[i] = rowub[i]
          end
      end
      add_constrs!(m.inner, float(A), senses, b)
  end
  
  update_model!(m.inner)
  setsense!(m,sense)
end

writeproblem(m::GurobiMathProgModel, filename::String) = write_model(m.inner, filename)

getvarLB(m::GurobiMathProgModel)     = get_dblattrarray (m.inner, "LB", 1, num_vars(m.inner))
setvarLB!(m::GurobiMathProgModel, l) = set_dblattrarray!(m.inner, "LB", 1, num_vars(m.inner), l)

getvarUB(m::GurobiMathProgModel)     = get_dblattrarray (m.inner, "UB", 1, num_vars(m.inner))
setvarUB!(m::GurobiMathProgModel, u) = set_dblattrarray!(m.inner, "UB", 1, num_vars(m.inner), u)

function getconstrLB(m::GurobiMathProgModel)
    sense = get_charattrarray(m.inner, "Sense", 1, num_constrs(m.inner))
    ret   = get_dblattrarray(m.inner, "RHS", 1, num_constrs(m.inner))
    for i = 1:num_constrs(m.inner)
        if sense[i] == '>' || sense[i] == '='
            # Do nothing
        else
            # LEQ constraint, so LB is -Inf
            ret[i] = -Inf
        end
     end
     return ret
end
function setconstrLB!(m::GurobiMathProgModel, lb)
    sense_changed = false  
    sense = get_charattrarray(m.inner, "Sense", 1, num_constrs(m.inner))
    rhs   = get_dblattrarray(m.inner, "RHS", 1, num_constrs(m.inner))
    for i = 1:num_constrs(m.inner)
        if sense[i] == '>' || sense[i] == '='
            # Do nothing
        elseif sense[i] == '<'
            if lb[i] != -Inf
                # LEQ constraint with non-NegInf LB implies a range
                # Might be an equality change though
                if isapprox(lb[i], rhs[i])
                  # Seems to be equality
                  sense[i] = '='
                  sense_changed = true
                else
                  # Guess not
                  error("Tried to set LB != -Inf on a LEQ constraint (index $i)")
                end
            else
                # don't change this RHS
                lb[i] = rhs[i]
            end
        end
    end
    if sense_changed
      set_charattrarray!(m.inner, "Sense", 1, num_constrs(m.inner), sense)
    end
    set_dblattrarray!(m.inner, "RHS", 1, num_constrs(m.inner), lb)
    updatemodel!(m)
end
function getconstrUB(m::GurobiMathProgModel)
    sense = get_charattrarray(m.inner, "Sense", 1, num_constrs(m.inner))
    ret   = get_dblattrarray(m.inner, "RHS", 1, num_constrs(m.inner))
    for i = 1:num_constrs(m.inner)
        if sense[i] == '<' || sense[i] == '='
            # Do nothing
        else
            # GEQ constraint, so UB is +Inf
            ret[i] = +Inf
        end
    end
    return ret
end
function setconstrUB!(m::GurobiMathProgModel, ub)
    sense_changed = false
    sense = get_charattrarray(m.inner, "Sense", 1, num_constrs(m.inner))
    rhs   = get_dblattrarray(m.inner, "RHS", 1, num_constrs(m.inner))
    for i = 1:num_constrs(m.inner)
        if sense[i] == '<' || sense[i] == '='
            # Do nothing
        elseif sense[i] == '>'
            if ub[i] != Inf
                # GEQ constraint with non-Inf UB implies a range
                # Might be an equality change though
                if isapprox(ub[i], rhs[i])
                  # Seems to be equality
                  sense[i] = '='
                  sense_changed = true
                else
                  # Guess not
                  error("Tried to set UB != +Inf on a GEQ constraint (index $i)")
                end
            else
                # don't change this RHS
                ub[i] = rhs[i]
            end
        end
    end
    if sense_changed
      set_charattrarray!(m.inner, "Sense", 1, num_constrs(m.inner), sense)
    end
    set_dblattrarray!(m.inner, "RHS", 1, num_constrs(m.inner), ub)
    updatemodel!(m)
end

getobj(m::GurobiMathProgModel)     = get_dblattrarray (m.inner, "Obj", 1, num_vars(m.inner)   )
setobj!(m::GurobiMathProgModel, c) = set_dblattrarray!(m.inner, "Obj", 1, num_vars(m.inner), c)

function addvar!(m::GurobiMathProgModel, constridx, constrcoef, l, u, objcoef)
    if m.last_op_type == :Con
        updatemodel!(m)
        m.last_op_type = :Var
    end
    add_var!(m.inner, length(constridx), constridx, float(constrcoef), float(objcoef), float(l), float(u), GRB_CONTINUOUS)
end
function addvar!(m::GurobiMathProgModel, l, u, objcoef)
    if m.last_op_type == :Con
        updatemodel!(m)
        m.last_op_type = :Var
    end
    add_var!(m.inner, 0, Integer[], Float64[], float(objcoef), float(l), float(u), GRB_CONTINUOUS)
end
function addconstr!(m::GurobiMathProgModel, varidx, coef, lb, ub)
    if m.last_op_type == :Var
        updatemodel!(m)
        m.last_op_type = :Con
    end
    if lb == -Inf
        # <= constraint
        add_constr!(m.inner, varidx, coef, '<', ub)
    elseif ub == +Inf
        # >= constraint
        add_constr!(m.inner, varidx, coef, '>', lb)
    elseif lb == ub
        # == constraint
        add_constr!(m.inner, varidx, coef, '=', lb)
    else
        # Range constraint
        error("Adding range constraints not supported yet.")
    end
end
updatemodel!(m::GurobiMathProgModel) = update_model!(m.inner)

getconstrmatrix(m::GurobiMathProgModel) = get_constrmatrix(m.inner)

function setsense!(m::GurobiMathProgModel, sense)
  if sense == :Min
    set_sense!(m.inner, :minimize)
  elseif sense == :Max
    set_sense!(m.inner, :maximize)
  else
    error("Unrecognized objective sense $sense")
  end
end
function getsense(m::GurobiMathProgModel)
  v = get_intattr(m.inner, "ModelSense")
  if v == -1 
    return :Max 
  else
    return :Min
  end
end

numvar(m::GurobiMathProgModel)    = num_vars(m.inner)
numconstr(m::GurobiMathProgModel) = num_constrs(m.inner) + num_qconstrs(m.inner)
numlinconstr(m::GurobiMathProgModel) = num_constrs(m.inner)
numquadconstr(m::GurobiMathProgModel) = num_qconstrs(m.inner)

function optimize!(m::GurobiMathProgModel)
    # set callbacks if present
    if m.lazycb != nothing || m.cutcb != nothing || m.heuristiccb != nothing || m.infocb != nothing
        setmathprogcallback!(m)
    end
    if m.lazycb != nothing
      setparam!(m.inner, "LazyConstraints", 1)
    end
    optimize(m.inner)
end

function status(m::GurobiMathProgModel)
  s = get_status(m.inner)
  if s == :optimal
    return :Optimal
  elseif s == :infeasible
    return :Infeasible
  elseif s == :unbounded
    return :Unbounded
  elseif s == :inf_or_unbd
    Base.warn_once("Gurobi reported infeasible or unbounded. Set InfUnbdInfo=1 for more specific status.")
    return :InfeasibleOrUnbounded
  elseif s == :iteration_limit || s == :node_limit || s == :time_limit || s == :solution_limit
    return :UserLimit
  elseif s == :numeric
    return :Numeric
  elseif s == :suboptimal
    return :Suboptimal # not very useful status
  else
    error("Unrecognized solution status: $s")
  end
end

getobjval(m::GurobiMathProgModel)   = get_objval(m.inner)
getobjbound(m::GurobiMathProgModel) = get_objbound(m.inner)
getsolution(m::GurobiMathProgModel) = get_solution(m.inner)

function getconstrsolution(m::GurobiMathProgModel)
    sense = get_charattrarray(m.inner, "Sense", 1, num_constrs(m.inner))
    rhs   = get_dblattrarray( m.inner, "RHS",   1, num_constrs(m.inner))
    slack = get_dblattrarray( m.inner, "Slack", 1, num_constrs(m.inner))
    ret   = zeros(num_constrs(m.inner))
    for i = 1:num_constrs(m.inner)
        if sense[i] == '='
            # Must be equal to RHS if feasible
            ret[i] = rhs[i]
        elseif sense[i] == '<'
            # <= RHS
            ret[i] = rhs[i] - slack[i]
        elseif sense[i] == '>'
            # >= RHS
            ret[i] = rhs[i] + slack[i]
        end
    end
    return ret
end

function getreducedcosts(m::GurobiMathProgModel)
    if is_qcp(m.inner) && get_int_param(m.inner.env, "QCPDual") == 0
        return fill(NaN, num_vars(m.inner))
    else
        return get_dblattrarray(m.inner, "RC", 1, num_vars(m.inner))
    end
end

function getconstrduals(m::GurobiMathProgModel)
    if is_qcp(m.inner) && get_int_param(m.inner.env, "QCPDual") == 0
        return fill(NaN, num_constrs(m.inner))
    else
        return get_dblattrarray(m.inner, "Pi", 1, num_constrs(m.inner))
    end
end

function getquadconstrduals(m::GurobiMathProgModel)
    if is_qcp(m.inner) && get_int_param(m.inner.env, "QCPDual") == 0
        return fill(NaN, num_qconstrs(m.inner))
    else
        return get_dblattrarray(m.inner, "QCPi", 1, num_qconstrs(m.inner))
    end
end

getinfeasibilityray(m::GurobiMathProgModel) = -get_dblattrarray(m.inner, "FarkasDual", 1, num_constrs(m.inner)) # note sign is flipped
getunboundedray(m::GurobiMathProgModel) = get_dblattrarray(m.inner, "UnbdRay", 1, num_vars(m.inner)) 

getbasis(m::GurobiMathProgModel) = get_basis(m.inner)

getrawsolver(m::GurobiMathProgModel) = m.inner

const var_type_map = Compat.@compat Dict(
  'C' => :Cont,
  'B' => :Bin,
  'I' => :Int,
  'S' => :SemiCont,
  'N' => :SemiInt
)

const rev_var_type_map = Compat.@compat Dict(
  :Cont => 'C',
  :Bin => 'B',
  :Int => 'I',
  :SemiCont => 'S',
  :SemiInt => 'N'
)

function setvartype!(m::GurobiMathProgModel, vartype::Vector{Symbol})
    nvartype = map(x->rev_var_type_map[x], vartype)
    set_charattrarray!(m.inner, "VType", 1, length(nvartype), nvartype)
end

function getvartype(m::GurobiMathProgModel)
    ret = get_charattrarray(m.inner, "VType", 1, num_vars(m.inner))
    map(x->var_type_map[x], ret)
end

function setwarmstart!(m::GurobiMathProgModel, v)
    for j = 1:length(v)
        if isnan(v[j])
            v[j] = 1e101  # GRB_UNDEFINED
        end
    end
    set_dblattrarray!(m.inner, "Start", 1, num_vars(m.inner), v)
end

addsos1!(m::GurobiMathProgModel, idx, weight) = add_sos!(m.inner, :SOS1, idx, weight)
addsos2!(m::GurobiMathProgModel, idx, weight) = add_sos!(m.inner, :SOS2, idx, weight)

# Callbacks


setlazycallback!(m::GurobiMathProgModel,f) = (m.lazycb = f)
setcutcallback!(m::GurobiMathProgModel,f) = (m.cutcb = f)
setheuristiccallback!(m::GurobiMathProgModel,f) = (m.heuristiccb = f)
setinfocallback!(m::GurobiMathProgModel,f) = (m.infocb = f)

type GurobiCallbackData <: MathProgCallbackData
    cbdata::CallbackData
    state::Symbol
    where::Cint
    sol::Vector{Float64}  # Used for heuristic callbacks
#    model::GurobiMathProgModel # not needed?
end

function cbgetmipsolution(d::GurobiCallbackData)
    @assert d.state == :MIPSol
    return cbget_mipsol_sol(d.cbdata, d.where)
end

function cbgetmipsolution(d::GurobiCallbackData,output)
    @assert d.state == :MIPSol
    return cbget_mipsol_sol(d.cbdata, d.where, output)
end

function cbgetlpsolution(d::GurobiCallbackData)
    @assert d.state == :MIPNode
    return cbget_mipnode_rel(d.cbdata, d.where)
end

function cbgetlpsolution(d::GurobiCallbackData, output)
    @assert d.state == :MIPNode
    return cbget_mipnode_rel(d.cbdata, d.where, output)
end


# TODO: macro for these getters?
function cbgetobj(d::GurobiCallbackData)
    if d.state == :MIPNode
        return cbget_mipnode_objbst(d.cbdata, d.where)
    elseif d.state == :MIPInfo
        return cbget_mip_objbst(d.cbdata, d.where)
    elseif d.state == :MIPSol
        error("Gurobi does not implement cbgetobj when state == MIPSol")
        # https://groups.google.com/forum/#!topic/gurobi/Az_X6Ag-y6k
        # https://github.com/JuliaOpt/MathProgBase.jl/issues/23
        # A complex workaround is possible but hasn't been implemented.
        # return cbget_mipsol_objbst(d.cbdata, d.where)
    else
        error("Unrecognized callback state $(d.state)")
    end
end

function cbgetbestbound(d::GurobiCallbackData)
    if d.state == :MIPNode
        return cbget_mipnode_objbnd(d.cbdata, d.where)
    elseif d.state == :MIPSol
        return cbget_mipsol_objbnd(d.cbdata, d.where)
    elseif d.state == :MIPInfo
        return cbget_mip_objbnd(d.cbdata, d.where)
    else
        error("Unrecognized callback state $(d.state)")
    end
end

function cbgetexplorednodes(d::GurobiCallbackData)
    if d.state == :MIPNode
        return cbget_mipnode_nodcnt(d.cbdata, d.where)
    elseif d.state == :MIPSol
        return cbget_mipsol_nodcnt(d.cbdata, d.where)
    elseif d.state == :MIPInfo
        return cbget_mip_nodcnt(d.cbdata, d.where)
    else
        error("Unrecognized callback state $(d.state)")
    end
end

# returns :MIPNode :MIPSol :Other
cbgetstate(d::GurobiCallbackData) = d.state

function cbaddcut!(d::GurobiCallbackData,varidx,varcoef,sense,rhs)
    @assert d.state == :MIPNode
    cbcut(d.cbdata, convert(Vector{Cint}, varidx), float(varcoef), sense, float(rhs))
end

function cbaddlazy!(d::GurobiCallbackData,varidx,varcoef,sense,rhs)
    @assert d.state == :MIPNode || d.state == :MIPSol
    cblazy(d.cbdata, convert(Vector{Cint}, varidx), float(varcoef), sense, float(rhs))
end

function cbaddsolution!(d::GurobiCallbackData)
    # Gurobi doesn't support adding solutions on MIPSol.
    # TODO: support this anyway
    @assert d.state == :MIPNode
    cbsolution(d.cbdata, d.sol)
    # "Wipe" solution back to GRB_UNDEFINIED
    for i in 1:length(d.sol)
        d.sol[i] = 1e101  # GRB_UNDEFINED
    end
end

function cbsetsolutionvalue!(d::GurobiCallbackData,varidx,value)
    d.sol[varidx] = value
end

# breaking abstraction, define our low-level callback to eliminatate
# a level of indirection

function mastercallback(ptr_model::Ptr{Void}, cbdata::Ptr{Void}, where::Cint, userdata::Ptr{Void})

    model = unsafe_pointer_to_objref(userdata)::GurobiMathProgModel
    grbrawcb = CallbackData(cbdata,model.inner)
    if where == CB_MIPSOL
        state = :MIPSol
        grbcb = GurobiCallbackData(grbrawcb, state, where, [0.0])
        if model.lazycb != nothing
            ret = model.lazycb(grbcb)
            if ret == :Exit
                return convert(Cint,10011) # gurobi callback error
            end
        end
    elseif where == CB_MIPNODE
        state = :MIPNode
        # skip callback if node is reported to be cut off or infeasible --
        # nothing to do.
        # TODO: users may want this information
        status = cbget_mipnode_status(grbrawcb, where)
        if status != 2
            return convert(Cint,0)
        end
        grbcb = GurobiCallbackData(grbrawcb, state, where, [0.0])
        if model.cutcb != nothing
            ret = model.cutcb(grbcb)
            if ret == :Exit
                return convert(Cint,10011) # gurobi callback error
            end
        end
        if model.heuristiccb != nothing
            grbcb.sol = fill(1e101, numvar(model))  # GRB_UNDEFINED
            ret = model.heuristiccb(grbcb)
            if ret == :Exit
                return convert(Cint,10011) # gurobi callback error
            end
        end
        if model.lazycb != nothing
            ret = model.lazycb(grbcb)
            if ret == :Exit
                return convert(Cint,10011) # gurobi callback error
            end
        end
    elseif where == CB_MIP
        state = :MIPInfo
        grbcb = GurobiCallbackData(grbrawcb, state, where, [0.0])
        if model.infocb != nothing
            ret = model.infocb(grbcb)
            if ret == :Exit
                return convert(Cint,10011) # gurobi callback error
            end
        end
    end
    return convert(Cint,0)
end

# User callback function should be of the form:
# callback(cbdata::MathProgCallbackData)
# return :Exit to indicate an error

function setmathprogcallback!(model::GurobiMathProgModel)
    
    @windows_only WORD_SIZE == 64 || error("Callbacks not currently supported on Win32. Use 64-bit Julia with 64-bit Gurobi.")
    grbcallback = cfunction(mastercallback, Cint, (Ptr{Void}, Ptr{Void}, Cint, Ptr{Void}))
    ret = @grb_ccall(setcallbackfunc, Cint, (Ptr{Void}, Ptr{Void}, Any), model.inner.ptr_model, grbcallback, model)
    if ret != 0
        throw(GurobiError(model.env, ret))
    end
    nothing
end


# QCQP

function setquadobj!(m::GurobiMathProgModel, rowidx, colidx, quadval)
    delq!(m.inner)
    update_model!(m.inner)
    scaledvals = similar(quadval)
    for i in 1:length(rowidx)
      if rowidx[i] == colidx[i]
        # rescale from matrix format to "terms" format
        scaledvals[i] = quadval[i] / 2
      else
        scaledvals[i] = quadval[i]
      end
    end
    add_qpterms!(m.inner, rowidx, colidx, scaledvals)
    update_model!(m.inner)
end

function addquadconstr!(m::GurobiMathProgModel, linearidx, linearval, quadrowidx, quadcolidx, quadval, sense, rhs)
    if m.last_op_type == :Var
        updatemodel!(m)
        m.last_op_type = :Con
    end
    add_qconstr!(m.inner, linearidx, linearval, quadrowidx, quadcolidx, quadval, sense, rhs)
end

getsolvetime(m::GurobiMathProgModel) = get_runtime(m.inner)
getnodecount(m::GurobiMathProgModel) = get_node_count(m.inner)
