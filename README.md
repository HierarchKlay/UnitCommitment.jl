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
      is_post_contingency::Bool = true,
  )::JuMP.Model
  ```
- **Purpose**: The **build_mymodel** function is an adaptation of the original **build_model** function. It constructs a model that excludes constraints and objective terms related to  **startup costs** ,  **bus curtailment** , and  **reserve shortfall penalties** . Additionally, this model does not account for  **profiled generators** ,  **price-sensitive loads** , or  **energy storage** . However, it provides flexibility by allowing the inclusion or exclusion of **pre-contingency and post-contingency security constraints and min up/down time constraints** through specific parameters.

### 2. Function `direct_optimize!`

- **Description**:

  ```julia
  function direct_optimize!(model::JuMP.Model)::Nothing
  ```
- **Purpose**: The `direct_optimize!` function provides an alternative to the original `optimize!` function. Unlike `optimize!`, which employs the [**Transmission Constraint Filtering**](https://ieeexplore.ieee.org/document/8613085) method to solve the problem, `direct_optimize!` directly solves the original model without any filtering, offering a more straightforward optimization approach.

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

+ `dev`: This branch contains the original, unmodified version of the package.
+ `240815`:  This branch includes the modified version of the package with the updates and enhancements that I’ve implemented.

## License

This modified package retains the original BSD license. See LICENSE.md for more details.
