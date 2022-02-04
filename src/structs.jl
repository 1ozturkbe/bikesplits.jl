""" Rider parameters."""
@with_kw mutable struct Rider
    Pmax::Real = 1000                # Maximum power (W)
    CP::Real = 300                   # Critical power (W)
    Wmax::Real = 20000               # Energy above CP (J)   
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

""" Training plan parameters. """
@with_kw mutable struct PlanParams
    name::String = "Training Plan"
    hrs::Array = (6, 10)             # min/max hours per week
    TSS::Array = (300, 600)          # min/max TSS per week
    rides::Array = (4,6)             # min/max rides per week

    # Current fitness
    CTL::Real = 40
    Fatigue::Real = 10

    # Racing schedule (days from today)
    As::Array = [120, 160]           # list of A races
    Bs::Array = [140]                # list of B races
    Cs::Array = [100, 150]           # list of C races
end
