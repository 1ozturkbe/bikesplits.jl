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

function plot_optimal_strategy(model::JuMP.Model, course::Course)
    xvals = [getvalue.(model[:xtime])[1]]
    [push!(xvals, xvals[end] + getvalue.(model[:xtime])[i]) for i=2:length(model[:xtime])];
    p1 = plot(xvals, 3.6*getvalue.(model[:speed]), yaxis = ("Speed (kph)", font(8)))
    p2 = plot(xvals, course.gradients, yaxis = ("Gradient (%)", font(8)))
    p3 = plot(xvals, getvalue.(model[:P]), yaxis = ("Power (W)", font(8)))
    p4 = plot(xvals, getvalue.(model[:W]), yaxis = ("W' (kJ)", font(8)))
    plot(p1, p2, p3, p4, layout = (4, 1), xaxis = ("Time (s)", font(8)), legend = false)
end