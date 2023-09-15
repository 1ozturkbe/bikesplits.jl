""" Rider parameters."""
@with_kw mutable struct Rider
    Pmax::Real = 1000                # Maximum power (W)
    CP::Real = 300                   # Critical power (W)
    Wmax::Real = 15000               # Energy above CP (J)   
    mass::Real = 75                  # Mass (kg)
    Crr::Real = 0.05                 # Coeff of rolling resistance (J/(kgm/s))
    CdA::Real = 0.25                 # Drag area (m^2)
end

""" Course parameters. """
@with_kw mutable struct Course
    name::String = "Course"          # Course name
    lengths::Array                   # Lengths of sectors (m)
    gradients::Array                 # Gradients of sectors (%)
    n = length(lengths)              # Number of sectors
    rho::Real = 1.2                  # Air density (kg/m^3)
end

""" Training plan weeks."""
@with_kw mutable struct TrainingWeek
    name::Int = 0
    TSS::Float64 = 0
    type::String = ""
end
