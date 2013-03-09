## Gurobi.jl

Julia Port of Gurobi Solver. 

The [Gurobi](http://www.gurobi.com) Optimizer is a commercial optimization solver for a variety of mathematical programming problems, including linear programming (LP), quadratic programming (QP), quadratically constrained programming (QCP), mixed integer linear programming (MILP), mixed-integer quadratic programming (MIQP), and mixed-integer quadratically constrained programming (MIQCP).

The Gurobi solver is considered one of the best solvers (in terms of performance and success rate of tackling hard problems) in math programming, and its performance is comparable to (and sometimes superior to) CPLEX.
While in general it would be expensive to purchase a Gurobi license, academic users can get a license for free. 

This package is a wrapper of the Gurobi solver (through its C interface). Currently, this package supports the following types of problems:

* Linear programming (LP)
* Mixed Integer Linear Programming (MILP)
* Quadratic programming (QP)
* Mixed Integer Quadratic Programming (MIQP)

### Installation

Here is the procedure to setup this package:

1. Obtain a license of Gurobi and install Gurobi solver, following the instructions on [Gurobi's website](http://www.gurobi.com).

2. Check out this package to your Julia package directory (e.g. ``~/.julia``)

3. Set environment variable ``GUROBI_LIB`` to the absolute path of the Gurobi shared library. For example, in Mac OS X, you may add the following statement to ``~/.profile``:

    ```bash
    export GUROBI_LIB=/Library/gurobi510/mac64/lib/libgurobi51.so
    ```
    
    Note that the name of the library varies by version, so you have to specify the path to the file itself instead of the directory.
    
4. Now, you can start using it.


### Examples

The usage of this package is straight forward. Here, it demonstrates the use of this package through several examples.

#### Example 1: Linear Programming

Problem formulation:
```
maximize x + y

s.t. 50 x + 24 y <= 2400
     30 x + 33 y <= 2100
     x >= 45, y >= 5
```

Julia code:
```julia
using Gurobi

 # creates an environment, which captures the solver setting 
env = Gurobi.Env()

 # creates an empty model  
model = gurobi_model(env, "lp_01", :maximize)

 # add variables
 # add_cvar!(model, obj_coef, lower_bound, upper_bound)
add_cvar!(model, 1.0, 45., Inf)  # x: x >= 45
add_cvar!(model, 1.0,  5., Inf)  # y: y >= 5

 # For Gurobi, you have to call update_model to have the 
 # lastest changes take effect
update_model!(model)

 # add constraints
 # add_constr!(model, coefs, sense, rhs)
add_constr!(model, [50., 24.], '<', 2400.) # 50 x + 24 y <= 2400
add_constr!(model, [30., 33.], '<', 2100.) # 30 x + 33 y <= 2100
update_model!(model)

println(model)

 # perform optimization
optimize(model)

 # show results
sol = get_solution(model)
println("soln = $(sol)")

objv = get_objval(model)
println("objv = $(objv)")
```

You may also add variables and constraints in batch, as:

```julia

 # add mutliple variables in batch
 # add_cvar!(model, obj_coefs, lower_bound, upper_bound)
add_cvars!(model, [1., 1.], [45., 5.], nothing)

 # add multiple constraints in batch 
 # add_constrs!(model, rowbegin, cind, coeffs, sense, rhs)
 # add_constrs!(model, Cint[1, 3], Cint[1, 2, 1, 2], 
 #    [50., 24., 30., 33.], '<', [2400., 2100.])
```

In ``add_constrs``, the left hand side matrix should be input in the form of compressed sparse rows. Specifically, the begining index of the i-th row is given by ``rowbegin[i]``. In the example above, we have

```julia
rowbegin = Cint[1, 3]
cind = Cint[1, 2, 1, 2] 
coeffs = [50., 24., 30., 33.]
```

Here, ``Cint[1, 3]`` implies the range ``1:2`` is for the first row. Therefore, the first row have nonzeros at positions ``[1, 2]`` and their values are ``[50., 24.]``. Likewise, the second row have nonzeros at ``[1, 2]`` and their values are ``[30., 33.]``.

#### Example 2: Linear programming (in MATLAB-like style)

You may also specify the entire problem in one function call (like MATLAB's ``linprog``).

Problem formulation:
```
maximize 1000 x + 350 y

s.t. x >= 30, y >= 0
     -1. x + 1.5 y <= 0
     12. x + 8.  y <= 1000
     1000 x + 300 y <= 70000
```

Julia code:
```julia
using Gurobi

env = Gurobi.Env()

f = [1000., 350.]
A = [-1. 1.5; 12. 8.; 1000. 300.]
b = [0., 1000., 70000.]
Aeq = nothing
beq = nothing
lb = [0., 30.]
ub = nothing

model = lp_model(env, "lp_02", :maximize, f, A, b, Aeq, beq, lb, ub)
optimize(model)
```


#### Example 3: Quadratic programming  









