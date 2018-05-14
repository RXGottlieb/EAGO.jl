#workspace()
using EAGO
using JuMP
using Ipopt
using MathProgBase
using BenchmarkTools
using IntervalArithmetic
using Plots

function Isolated_Pressure(N::Int,R::Float64,Lpt::T,Svt::Float64,Kt::Float64,Pvv::Float64) where T<:Real

    # Pressure Profile
    att = R*sqrt(Lpt*Svt/Kt)

    # N -- number of spatial grid points
    r = linspace(0,R,N)
    r = r/R
    dr = 1/(N-1)
    ivdr2 = 1./dr^2
    att2 = att^2
    A = zeros(N,N)
    F = zeros(N,1)

    #at = zeros(N,1)

    M = N

    #for i in 1:M
#        at[i] = att
#    end

    for i in 2:M-1
        A[i,i-1] = -1/r[i]/dr + ivdr2
        #A[i,i] = -2./dr^2 - (at[i]^2)
        A[i,i] = -2.*ivdr2 - (att2)
        A[i,i+1] = 1./r[i]/dr + ivdr2
        #F[i] = -(at[i]^2)*Pvv
        F[i] = -(att2)*Pvv
    end

    # Boundary condtions for isolated tumor model
    A[1,1] = -2/dr^2 - (att^2)
    A[1,2] = 2/dr^2
    F[1] = -att2*Pvv
    A[N,N] = 1.0

    # Solution of linear problem for pressure distribution
    P = A\F
    return P
end

function Isolated_Pressure_Form(N::Int,R::Float64,Lpt::T,Svt::Float64,Kt::Float64,Pvv::Float64) where T<:Real

    att = R*sqrt(Lpt*Svt/Kt)
    #println("att: $att")
    r = Vector(linspace(0,R,N))/R
    dimP = zeros(T,N)
    dimV = zeros(T,N)
    #dimP[2:end] = one(T) - sinh.(att*r[2:end])./(sinh(att)*r[2:end])
    dimP[2:end] = [one(T) for i=2:N]
    #dimV[2:end] = (att*r[2:end].*cosh.(att*r[2:end])-sinh.(att*r[2:end]))./(sinh(att)*r[2:end].^2)
    dimV[2:end] = [one(T) for i=2:N]

    Pinf = zero(T)
    Pdel = Pvv - Pinf
    P = Pdel*dimP+Pinf
    V = (Kt*Pdel/R)*dimV
    P[1] = one(T)

    return P,V
end


# Concentration Profile
function MST(t::Float64,c::Vector{T},P::VecOrMat{T},N::Int,sigma::Float64,
             Peff::Float64,Lpt::T,Svt::Float64,Kt::Float64,Pvv::Float64,
             Pv::Float64,D::Float64,r::Vector{Float64},dr::Float64,kd::Float64) where T<:Real

    co::Float64 = 1.0 # dimensionless drug concentration
    tspan::Float64 = 24.0*3600.0 # length of simulation type

    f::Vector{T} = zeros(T,N)
    cv::Float64 = co*exp(-t/kd/3600.0)  # vascular concentration of the drug following exponential decay
    coeff1::Float64 = Peff*Svt
    coeff2::T = Lpt*(Svt*Pv*cv*(1.0-sigma))
    coeff3::Float64 = 2.0*D/dr
    coeff4::Float64 = D/dr^2
    f[1] = 2.0*D*(c[2]-c[1])/dr^2 + Peff*Svt*(cv-c[1]) + coeff2*(Pvv-P[1])

    for j in 2:N-1
        f[j] = ((coeff3/r[j])*((c[j+1]-c[j])) + coeff4*(c[j+1]-2.0*c[j]+c[j-1]) +
        Kt*((P[j+1]-P[j-1])/(2.0*dr))*((c[j+1]-c[j])/dr) + coeff1*(cv-c[j])) + coeff2*(Pvv-P[j])
    end

    f[N] = zero(T)
    return f
end

function MST_Form(t::Float64,c::Vector{T},P::Vector{T},V::Vector{T},N::Int,sigma::Float64,
                Peff::Float64,Lpt::T,Svt::Float64,Kt::Float64,Pvv::Float64,
                Pv::Float64,D::Float64,r::Vector{Float64},dr::Float64,kd::Float64) where T<:Real

    co::Float64 = 1.0 # dimensionless drug concentration
    tspan::Float64 = 24.0*3600.0 # length of simulation type

    f::Vector{T} = zeros(T,N)
    cv::Float64 = co*exp(-t/kd/3600.0)  # vascular concentration of the drug following exponential decay
    coeff1::Float64 = Peff*Svt
    coeff2::T = Lpt*(Svt*Pv*cv*(1.0-sigma))
    coeff3::Float64 = 2.0*D/dr
    coeff4::Float64 = D/dr^2
    f[1] = 2.0*D*(c[2]-c[1])/dr^2 + Peff*Svt*(cv-c[1]) + coeff2*(Pvv-P[1])

    for j in 2:N-1
        f[j] = ((coeff3/r[j])*((c[j+1]-c[j])) + coeff4*(c[j+1]-2.0*c[j]+c[j-1]) -
               V[j]*((c[j+1]-c[j])/dr) + coeff1*(cv-c[j])) + coeff2*(Pvv-P[j])
    end

    f[N] = zero(T)
    return f
end


function RK4(x0::Float64,y0::Vector{T},h::Float64,n_out::Int,i_out::Int,
             P::VecOrMat{T},N::Int64,sigma::Float64,Peff::Float64,Lpt::T,Svt::Float64,
             Kt::Float64,Pvv::Float64,Pv::Float64,D::Float64,r::Vector{Float64},
             dr::Float64,kd::Float64) where T<:Real

    xout = zeros(T,n_out+1)
    yout = zeros(T,n_out+1,length(y0))
    xout[1] = x0
    yout[1,:] = y0
    x = x0
    y = y0
    for j = 2:n_out+1
        for k = 1:i_out
            k1 = MST(x,y,P,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
            k2 = MST(x+0.5*h,y+0.5*h*k1,P,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
            k3 = MST(x+0.5*h,y+0.5*h*k2,P,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
            k4 = MST(x,y+h*k3,P,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
            y = y + (h/6.0)*(k1 + 2.0*k2 + 2.0*k3 + k4)
            x = x + h
        end
        xout[j] = x
        yout[j,:] = y
    end
    return xout, yout
end


function RK4_Form(x0::Float64,y0::Vector{T},h::Float64,n_out::Int,i_out::Int,
                  P::VecOrMat{T},V::Vector{T},N::Int64,sigma::Float64,Peff::Float64,Lpt::T,Svt::Float64,
                  Kt::Float64,Pvv::Float64,Pv::Float64,D::Float64,r::Vector{Float64},
                  dr::Float64,kd::Float64) where T<:Real

    xout = zeros(T,n_out+1)
    yout = zeros(T,n_out+1,length(y0))
    xout[1] = x0
    yout[1,:] = y0
    x = x0
    y = y0
    for j = 2:n_out+1
        for k = 1:i_out
            k1 = MST_Form(x,y,P,V,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
            k2 = MST_Form(x+0.5*h,y+0.5*h*k1,P,V,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
            k3 = MST_Form(x+0.5*h,y+0.5*h*k2,P,V,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
            k4 = MST_Form(x,y+h*k3,P,V,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
            y = min(max(y + (h/6.0)*(k1 + 2.0*k2 + 2.0*k3 + k4),0.0),1.0)
            #y = y + (h/6.0)*(k1 + 2.0*k2 + 2.0*k3 + k4)
            x = x + h
        end
        xout[j] = x
        yout[j,:] = y
    end
    return xout, yout
end

function Isolated_Model(N::Int,Kt::Float64,Lpt::T,Svt::Float64,D::Float64,
                        sigma::Float64,Peff::Float64,R::Float64,Pv::Float64,
                        Pvv::Float64,kd::Float64,n_nodes::Int) where T<:Real

    r = Vector(linspace(0,R,N))
    r = r/R
    dr = 1.0/(N-1)

    # Solution of steady state pressure model
    P = Isolated_Pressure(N,R,Lpt,Svt,Kt,Pvv)

    # Initial solute concentration
    c_0 = zeros(T,N)
    c_0[N] = one(T)


    time_end = 24*3600.0 # length of simulation (seconds)
    n_out = n_nodes - 1
    h = time_end/n_out;
    i_out = 1

    time, c = RK4(0.0,c_0,h,n_out,i_out,P,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
    return time, c
end


function Isolated_Model_Form(N::Int,Kt::Float64,Lpt::T,Svt::Float64,D::Float64,
                        sigma::Float64,Peff::Float64,R::Float64,Pv::Float64,
                        Pvv::Float64,kd::Float64,n_nodes::Int) where T<:Real

    r = Vector(linspace(0,R,N))
    r = r/R
    dr = 1.0/(N-1)

    # Solution of steady state pressure model
    P,V = Isolated_Pressure_Form(N,R,Lpt,Svt,Kt,Pvv)

    # Initial solute concentration
    c_0 = zeros(T,N)
    c_0[N] = one(T)

    time_end = 24*3600.0 # length of simulation (seconds)
    n_out = n_nodes - 1
    h = time_end/n_out;
    i_out = 1

    time, c = RK4_Form(0.0,c_0,h,n_out,i_out,P,V,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
    return time, c
end

function Fitting_Objective(N::Int,Kt::Float64,Lpt::T,Svt::Float64,D::Float64,
                           sigma::Float64,Peff::Float64,R::Float64,Pv::Float64,
                           Pvv::Float64,kd::Float64,n_nodes::Int,n_time::Int,
                           cref::VecOrMat{Float64}) where T<:Real

    r = Vector(linspace(0,R,N))
    r = r/R
    dr = 1.0/(N-1)

    # Solution of steady state pressure model
    P,V = Isolated_Pressure_Form(N,R,Lpt,Svt,Kt,Pvv)

    # Initial solute concentration
    c_0 = zeros(T,N)
    c_0[N] = one(T)

    time_end = 24*3600.0 # length of simulation (seconds)
    n_out = n_nodes - 1
    h = time_end/n_out;
    i_out = 1

    time, c = RK4_Form(0.0,c_0,h,n_out,i_out,P,V,N,sigma,Peff,Lpt,Svt,Kt,Pvv,Pv,D,r,dr,kd)
    #println("n_time")
    SSE = zero(T)
    for j = 1:n_time
        c_model = mean(c[j*Int(floor(n_nodes/n_time)),:])
        #println("c_model at $j: $c_model")
        SSE = SSE + (c_model-cref[j])^2
    end

    return SSE
end

idx = 2

# Input space nodes and time nodes
N = 100
n_nodes = 400 #6000
n_time = 30

# Parameters for creating data for fit
co = 1
t = (3600/n_time).*Array(1:n_time)
s = EAGO_NLPSolver(LBD_func_relax = "NS-STD-OFF",
                    LBDsolvertype = "LP",
                    #LBD_func_relax = "Interval",
                    #LBDsolvertype = "Interval",
                    UBDsolvertype = "Interval",
                    probe_depth = -1,
                    variable_depth = 1000000000000,
                    DAG_depth = -1,
                    STD_RR_depth = -1,
                    validated = true)

# Input known metabolic parameters for Rhodamine
Peff_set = [9.59873e-07;4.6098e-06;2.80047e-06]
Kt = 0.9e-7              # Hydraulic conductivity of tumor
Lpt = 5.0e-6             # hydraulic conductivity of tumor vessels
Svt = 200.0                # tumor vascular density
D = 2.0e-7                 # solute diffusion coefficient
sigma = 0.0                # solute reflection coefficient
Perm = Peff_set[idx]*0.8 # solute vascular permeability
R = 1.0                   # tumor radius (cm)
Pv = 25.0                  # vascular pressure (mmHg)
Pvv = 1.0                 # vascular pressure dimensionless
kd = 1480*60.0             #blood circulation time of drug in hours

cref1 = (co*Peff_set[1]*Svt*kd/(1-Peff_set[1]*Svt*kd))*(exp(-Peff_set[1]*Svt*t)-exp(-t/kd))
tcalc, ccalc = Isolated_Model_Form(N,Kt,Lpt,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes)
tcalc1, ccalc1 = Isolated_Model_Form(N,Kt,Lpt,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes)
#objv1 = Fitting_Objective(N,Kt,6e-9,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
#objv2 = Fitting_Objective(N,Kt,6e-7,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
#=
a = zeros(100)
for i=1:100
    j = (i-1)*((6e-7)-(6e-9))/(100.0)+6e-9
    a[i] = Fitting_Objective(N,Kt,j,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
end
=#
#plotly()
#plot(a)
#gui()

#@btime Fitting_Objective(N,Kt,6e-9,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
#@btime Fitting_Objective(N,Kt,6e-7,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
#plotly()
#plot(tcalc,ccalc[:,10])
#plot!(tcalc1,ccalc1[:,10])
#gui()
#@time Isolated_Model_Form(N,Kt,Lpt,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes)
#@time Fitting_Objective(N,Kt,Lpt,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
#@time Fitting_Objective(N,Kt,Interval(6e-9,6e-7),Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
println("IntervalEval")
IntvObj = Fitting_Objective(N,Kt,Interval(6e-9,6.000000000000000001e-7),Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
IntvObj1 = Fitting_Objective(N,Kt,Interval(6e-8,6.000000000000000001e-7),Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
IntvObj2 = Fitting_Objective(N,Kt,Interval(6e-9,6.000000000000000001e-9),Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
#IntvObj = Fitting_Objective(N,Kt,Interval(6e-9,6e-7),Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
IntvP,IntvV = Isolated_Pressure_Form(N,R,6e-9,Svt,Kt,Pvv)

# Fits the data for control, rhodamine
cref1 = (co*Peff_set[1]*Svt*kd/(1-Peff_set[1]*Svt*kd))*(exp(-Peff_set[1]*Svt*t)-exp(-t/kd))
tcalc, ccalc = Isolated_Model_Form(N,Kt,Lpt,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes)
objv = Fitting_Objective(N,Kt,Lpt,Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
f1(x) = Fitting_Objective(N,Kt,x[1],Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref1)
m1 = MathProgBase.NonlinearModel(s)
MathProgBase.loadproblem!(m1, 1, 0, [6e-9], [6e-7],[], [], :Min, f1, [])
MathProgBase.optimize!(m1)

# Fits the data for 3mg/kg, rhodamine
cref2 = (co*Peff_set[2]*Svt*kd/(1-Peff_set[2]*Svt*kd))*(exp(-Peff_set[2]*Svt*t)-exp(-t/kd))
f2(x) = Fitting_Objective(N,Kt,x[1],Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref2)
m2 = MathProgBase.NonlinearModel(s)
MathProgBase.loadproblem!(m2, 1, 0, [6e-9], [6e-7],[], [], :Min, f2, [])
MathProgBase.optimize!(m2)

# Fits the data for 30mg/kg, rhodamine
cref3 = (co*Peff_set[3]*Svt*kd/(1-Peff_set[3]*Svt*kd))*(exp(-Peff_set[3]*Svt*t)-exp(-t/kd))
f3(x) = Fitting_Objective(N,Kt,x[1],Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref3)
m3 = MathProgBase.NonlinearModel(s)
MathProgBase.loadproblem!(m3, 1, 0, [6e-9], [6e-7],[], [], :Min, f3, [])
MathProgBase.optimize!(m3)


# Input known metabolic parameters
Peff_set = [8.18378e-07;4.30307e-06;1.62231e-06]
Kt = 0.9e-7              # Hydraulic conductivity of tumor
Lpt = 5.0e-6             # hydraulic conductivity of tumor vessels
Svt = 200.0                # tumor vascular density
D = 1.4375e-07                 # solute diffusion coefficient
sigma = 0.0                # solute reflection coefficient
Perm = Peff_set[idx]*0.8 # solute vascular permeability
R = 1.0                   # tumor radius (cm)
Pv = 25.0                  # vascular pressure (mmHg)
Pvv = 1.0                 # vascular pressure dimensionless
kd = 1298*60.0             #blood circulation time of drug in hours

# Fits the data for control, rhodamine
cref4 = (co*Peff_set[1]*Svt*kd/(1-Peff_set[1]*Svt*kd))*(exp(-Peff_set[1]*Svt*t)-exp(-t/kd))
f4(x) = Fitting_Objective(N,Kt,x[1],Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref4)
m4 = MathProgBase.NonlinearModel(s)
MathProgBase.loadproblem!(m4, 1, 0, [6e-9], [6e-7],[], [], :Min, f4, [])
MathProgBase.optimize!(m4)

# Fits the data for 3mg/kg, rhodamine
cref5 = (co*Peff_set[2]*Svt*kd/(1-Peff_set[2]*Svt*kd))*(exp(-Peff_set[2]*Svt*t)-exp(-t/kd))
f5(x) = Fitting_Objective(N,Kt,x[1],Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref5)
m5 = MathProgBase.NonlinearModel(s)
MathProgBase.loadproblem!(m5, 1, 0, [6e-9], [6e-7],[], [], :Min, f5, [])
MathProgBase.optimize!(m5)

# Fits the data for 30mg/kg, rhodamine
cref6 = (co*Peff_set[3]*Svt*kd/(1-Peff_set[3]*Svt*kd))*(exp(-Peff_set[3]*Svt*t)-exp(-t/kd))
f6(x) = Fitting_Objective(N,Kt,x[1],Svt,D,sigma,Peff_set[1],R,Pv,Pvv,kd,n_nodes,n_time,cref6)
m6 = MathProgBase.NonlinearModel(s)
MathProgBase.loadproblem!(m6, 1, 0, [6e-9], [6e-7],[], [], :Min, f6, [])
MathProgBase.optimize!(m6)
