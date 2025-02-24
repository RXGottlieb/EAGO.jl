"""
    $(TYPEDEF)

An abstract type the subtypes of which are associated with functions method
overloaded for new extensions. An instance of this is the `DefaultExt <: ExtensionType`
structure in the EAGO `Optimizer` in the `ext_type` field.
"""
abstract type ExtensionType end
struct DefaultExt <: ExtensionType end
MOIU.map_indices(::Function, x::ExtensionType) = x
MOIU.map_indices(::Function, x::DefaultExt) = x
