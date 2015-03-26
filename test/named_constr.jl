# a simple LP example
#  showing how to set and access named constraits.
# and the pitfalls that can be encountered

using Gurobi
using Base.Test

env = Gurobi.Env()

model = Gurobi.Model(env, "lp_01", :maximize)

# add variables
add_cvar!(model, 1.0, 45., Inf)  # x
add_cvar!(model, 1.0,  5., Inf)  # y
update_model!(model)

# add constraints
add_constr!(model, [50., 24.], '<', 2400., "c1")
add_constr!(model, [30., 33.], '<', 2100., "c2")
add_constrs!(model, Cint[1, 3], Cint[1, 2, 1, 2], 
    [50., 24., 30., 33.], '<', [2400., 2100.], ["c2", "c3"])

add_rangeconstr!(model, [1., 1.], 10., 100., "r1")
add_rangeconstr!(model, [1, 2], [1.5, 1.], 15., 120., "r2")
add_rangeconstrs!(model, [1, 3], [1, 2, 1, 2], [1.5, 1., 1.3, 1.1], [15., 20.], [100., 110.], ["r3", "r4"])

update_model!(model)

update_model!(model)



@test Gurobi.get_constr_indx(model, "c1") == 0

c2 = Gurobi.get_constr_indx(model, "c2")
@test (c2 == 1 || c2 == 2)
# Be careful with duplicate names. Gurobi returns one arbitrarily.
# http://www.gurobi.com/documentation/6.0/refman/grbgetconstrbyname.html
# Version 6.0 of the Gurobi reference states "If multiple constraints have the same name, this routine chooses one arbitrarily."

@test Gurobi.get_constr_indx(model, "c3") == 3

@test Gurobi.get_constr_indx(model, "r1") == 4
@test Gurobi.get_constr_indx(model, "r2") == 5
@test Gurobi.get_constr_indx(model, "r3") == 6
@test Gurobi.get_constr_indx(model, "r4") == 7

@test Gurobi.get_constr_indx(model, "mycon") == -1
# Gurobi returns -1 if it cannot find a constraint by that name.
