# UnitCommitment.jl

## Introduction

This package is a modification of the original [UnitCommitment.jl](https://github.com/ANL-CEEESA/UnitCommitment.jl) package. It has been adapted and extended by HierarchKlay to include additional functionalities and improvements.

## Modifications

### 1. Function `build_mymodel`

- **Description**:
  ```julia
  function build_mymodel(;
      instance::UnitCommitmentInstance,
      optimizer = nothing,
      formulation = Formulation(),
      variable_names::Bool = false,
      is_min_updown::Bool = true,
      is_pre_contingency::Bool = true,
      is_post_contingency::Bool = false,
  )::JuMP.Model
  ```
- **Purpose**: The `build_mymodel` function is an adaptation of the original  `build_model` function. It constructs a model that excludes constraints and objective terms related to:
  - **Startup costs of delays** (Only basic startup costs are considered)
  - **Bus curtailment**
  - **Reserve shortfall penalties**
- Additionally, this model does not account for:
  - **Profiled generators**
  - **Price-sensitive loads**
  - **Energy storage**
  - Reserve terms in ramping constraints
- However, it provides flexibility by allowing the inclusion or exclusion of:
  - **Pre-contingency and post-contingency security constraints**
  - **Min up/down time constraints** through specific parameters.

### 2. Function `statistic`

* **Description** :

  ```julia
  function statistic(model::JuMP.Model)::Statistic
  ```
* **Purpose** : This function collects and returns comprehensive solution statistics from the model, including:

  * Build time metrics
  * Solve time details
  * Number of nodes processed
  * Objective value
  * Optimality gap
  * Additional special statistics for various methods

## New Methods

### 1. Function `direct_optimize!`

- **Description**:

  ```julia
  function direct_optimize!(model::JuMP.Model)::Nothing
  ```
- **Purpose**: The `direct_optimize!` function provides an alternative to the original `optimize!` function. Unlike `optimize!`, which employs the [**Transmission Constraint Filtering**](https://ieeexplore.ieee.org/document/8613085) method to solve the problem, `direct_optimize!` directly solves the original model without any filtering, offering a more straightforward optimization approach.

### 2. Function `optimize!`

* **Description** :

```julia
function optimize!(model::JuMP.Model;
    is_early_stopped::Bool = false,
    max_search_per_period::Int = 5,
    max_violations_per_line::Int = 1,
    max_violations_per_period::Int = 5,
)::Nothing
```

* **Purpose** : An enhanced version of the original `optimize!` function that provides control over the constraint filtering process. It offers two approaches:

  * When `is_early_stopped = true`: Adds surrogate constraints based on the methodology described in [this research paper](https://kns.cnki.net/kcms2/article/abstract?v=rdiHbV4QUxbzu_3bb68Q9311pxOjEgh_ZabGH-R2qgN_NqzD2vRwG4pG8p5ReAR2Xewu90i2aOD7ZitTFvpGqWPAlxdlDjmSpAQgcK4nPTZCObS_u6GG7q7AYXxJu91qgzCECH6YsBrnfSe_t-YRxiIkyptYXzyEae4d6TMJK72rJ5Xge5IOA9MaJKHQ1915&uniplatform=NZKPT&language=CHS)
  * When `is_early_stopped = false`: Uses original TCF method to add the most violated constraints
* **Parameters** :

  * `max_search_per_period`: Limits the number of constraints searched per period (active when `is_early_stopped = true`)
  * `max_violations_per_line`: Limits the number of violated constraints added per transmission line
  * `max_violations_per_period`: Limits the number of violated constraints added per period

### 3. Function `callback_optimize!`

* **Description** :

```julia
function callback_optimize!(;
    model::JuMP.Model,
    is_root_check::Bool = false,
    is_gen_min_time::Bool = false,
    is_gen_pre_conting::Bool = true,
    is_gen_post_conting::Bool = true,
    is_early_stopped::Bool = false,
    max_search_per_period::Int = 5,
    max_violations_per_period::Int = 5,
)::Nothing
```

* **Purpose** : Solves the security constrained unit commitment problem using [Surrogate Lazy Constraint Filtering (SLCF) method](https://kns.cnki.net/kcms2/article/abstract?v=rdiHbV4QUxbzu_3bb68Q9311pxOjEgh_ZabGH-R2qgN_NqzD2vRwG4pG8p5ReAR2Xewu90i2aOD7ZitTFvpGqWPAlxdlDjmSpAQgcK4nPTZCObS_u6GG7q7AYXxJu91qgzCECH6YsBrnfSe_t-YRxiIkyptYXzyEae4d6TMJK72rJ5Xge5IOA9MaJKHQ1915&uniplatform=NZKPT&language=CHS). This function provides fine-grained control over constraint generation and filtering strategies.
* **Parameters** :

  * `is_root_check`: Controls whether to use LP relaxation at root node for generating violated constraints (experimental feature, may be unstable)
  * `is_gen_min_time`: Determines if min up/down time constraints should be generated
  * `is_gen_pre_conting`: Controls generation of pre-contingency constraints
  * `is_gen_post_conting`: Controls generation of post-contingency constraints
  * `is_early_stopped`: Determines whether to use surrogate constraints (see `optimize!` function)
  * `max_search_per_period`: Limits the number of surrogate constraints per period
  * `max_violations_per_period`: Maximum number of violated constraints to add per time period
* `is_root_check`: Controls whether to use LP relaxation at root node for generating violated constraints
* `is_gen_min_time`: Determines if min up/down time constraints should be generated
* `is_gen_pre_conting`: Controls generation of pre-contingency constraints
* `is_gen_post_conting`: Controls generation of post-contingency constraints
* `is_early_stopped`: Determines whether to use surrogate constraints (see `optimize!` function)
* `max_search_per_period`: Limits the number of constraints searched per period
* `max_violations_per_period`: Limits the number of violated constraints added per period

## Tutorial: How to Add a Local Julia Package

1. **Ensure Clean Environment** : Start by ensuring that **UnitCommitment.jl** is not already installed in your Julia environment.
2. **Clone the Repository** : Git clone this repository to your local device:

   ```bash
   git clone git@github.com:HierarchKlay/UnitCommitment.jl.git
   ```
3. **Add the Local Package** : Use the following commands to add the cloned package to your Julia environment:

   ```julia
   using Pkg
   Pkg.develop(path="/path-to-repository")
   ```

Replace `"/path-to-repository"` with the actual path to the cloned repository on your device.

## Branches

+ `master`:  This branch includes the modified version of the package with the updates and enhancements that I’ve implemented.
+ `dev`: This branch contains the original, unmodified version of the package.
+ `240815`: This branch includes modifications to implement `build_mymodel` and `direct_optimize!` functions, while retaining all other original package functionality.

## License

This modified package retains the original BSD license. See LICENSE.md for more details.
