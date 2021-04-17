"""
Scatters 2D results from JuMP.Models or Arrays
""" 
function scatter_2d(m::JuMP.Model, d1::Union{Array, Symbol} = :Wcost, 
                                   d2::Union{Array, Symbol} = :P)
    if d1 isa Symbol
        if d2 isa Symbol
            scatter(getvalue.(m[d1]), getvalue.(m[d2]))
        else
            scatter(getvalue.(m[d1]), d2)
        end
    else
        if d2 isa Symbol
            scatter(d1, getvalue.(m[d2]))
        else
            scatter(d1, d2)
        end
    end
end