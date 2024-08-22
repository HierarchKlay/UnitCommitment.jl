# UnitCommitment.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

function _process(filter::_Consec_ViolationFilter, v::_Consec_Violation)::Nothing
    if v.unit.name ∉ keys(filter.queues)
        filter.queues[v.unit.name] =
            PriorityQueue{_Consec_Violation,Float64}()
    end
    q::PriorityQueue{_Consec_Violation,Float64} =
        filter.queues[v.unit.name]
    if length(q) < filter.max_per_unit
        enqueue!(q, v => v.amount)
    else
        if v.amount > peek(q)[1].amount
            dequeue!(q)
            enqueue!(q, v => v.amount)
        end
    end
    return nothing
end

function _concat(filter::_Consec_ViolationFilter)::Array{_Consec_Violation,1}
    violations = Array{_Consec_Violation,1}()
    time_queue = PriorityQueue{_Consec_Violation,Float64}()
    for gn in keys(filter.queues)
        unit_queue = filter.queues[gn]
        while length(unit_queue) > 0
            v = dequeue!(unit_queue)
            if length(time_queue) < filter.max_total
                enqueue!(time_queue, v => v.amount)
            else
                if v.amount > peek(time_queue)[1].amount
                    dequeue!(time_queue)
                    enqueue!(time_queue, v => v.amount)
                end
            end
        end
    end
    while length(time_queue) > 0
        violations = [violations; dequeue!(time_queue)]
    end
    return violations
end
