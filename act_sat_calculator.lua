---------------------------------------------------------------
-- ACT/SAT Calculator Program for TI-Nspire
-- Comprehensive Math Toolkit
---------------------------------------------------------------

-- Compatibility shim for testing outside TI-Nspire
if not platform then
  platform = {apilevel = '2.7', window = {invalidate = function() end, width = function() return 318 end, height = function() return 212 end}}
end
if not math.eval then
  math.eval = function(expr) return nil end
end
if not on then
  on = setmetatable({}, {__newindex = function(t,k,v) rawset(t,k,v) end})
end

platform.apilevel = '2.7'

---------------------------------------------------------------
-- GLOBAL STATE
---------------------------------------------------------------
local W, H = 318, 212
local state = "menu"        -- menu, submenu, tool, read
local menuSel = 1
local subSel = 1
local inputSel = 1
local scrollY = 0
local inputs = {}
local inputVals = {}
local results = {}
local currentTool = nil
local cursorPos = {}
local cursorBlink = true
local blinkTimer = 0

---------------------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------------------
local function round(x, n)
  n = n or 4
  local m = 10^n
  return math.floor(x * m + 0.5) / m
end

local function safeEval(expr)
  local ok, val = pcall(function() return math.eval(expr) end)
  if ok and val then return tostring(val) end
  return nil
end

local function safeEvalNum(expr)
  local s = safeEval(expr)
  if s then return tonumber(s) end
  return nil
end

local function gcd(a, b)
  a, b = math.abs(a), math.abs(b)
  while b > 0 do a, b = b, a % b end
  return a
end

local function lcm(a, b)
  if a == 0 and b == 0 then return 0 end
  return math.abs(a * b) / gcd(a, b)
end

local function factorize(n)
  n = math.abs(n)
  if n < 2 then return {{n, 1}} end
  local factors = {}
  local d = 2
  while d * d <= n do
    local count = 0
    while n % d == 0 do count = count + 1; n = n / d end
    if count > 0 then table.insert(factors, {d, count}) end
    d = d + 1
  end
  if n > 1 then table.insert(factors, {n, 1}) end
  return factors
end

local function factorStr(n)
  local f = factorize(n)
  local parts = {}
  for _, p in ipairs(f) do
    if p[2] == 1 then table.insert(parts, tostring(p[1]))
    else table.insert(parts, p[1] .. "^" .. p[2]) end
  end
  return table.concat(parts, "\xC2\xB7")
end

---------------------------------------------------------------
-- MENU STRUCTURE
---------------------------------------------------------------
local menus = {
  {name="Algebra", items={
    {name="Solve any Equation/Inequality", type="tool", id="alg_solve"},
    {name="Solve 2x2 System - Steps", type="tool", id="alg_2x2"},
    {name="Solve 3x3 System - Steps", type="tool", id="alg_3x3"},
    {name="Read: PEMDAS", type="read", id="alg_pemdas"},
    {name="Simplify & Evaluate", type="tool", id="alg_simplify"},
    {name="Factor Integers", type="tool", id="alg_factor"},
    {name="Powers", type="tool", id="alg_powers"},
    {name="Find GCD & LCM", type="tool", id="alg_gcdlcm"},
    {name="Solve Proportion", type="tool", id="alg_proportion"},
    {name="Absolute & Percent Change", type="tool", id="alg_pctchange"},
  }},
  {name="Functions", items={
    {name="Read: Definition of Function", type="read", id="fn_def"},
    {name="Function Explorer", type="tool", id="fn_explore"},
    {name="Evaluate Function", type="tool", id="fn_eval"},
    {name="Intersection of 2 Functions", type="tool", id="fn_intersect"},
    {name="Find f+g", type="tool", id="fn_add"},
    {name="Composition f(g(x))", type="tool", id="fn_compose"},
    {name="Find [f(x+h)-f(x)]/h", type="tool", id="fn_diffquot"},
    {name="Read: Interval Notation", type="read", id="fn_interval"},
  }},
  {name="Polynomials", items={
    {name="Polynomial Explorer", type="tool", id="poly_explore"},
    {name="Find Degree", type="tool", id="poly_degree"},
  }},
  {name="Points and Lines", items={
    {name="Find Slope", type="tool", id="pt_slope"},
    {name="Find y=mx+b", type="tool", id="pt_ymxb"},
    {name="Read: y=k*x", type="read", id="pt_directvar"},
    {name="Read: Linear Functions", type="read", id="pt_linearfn"},
    {name="Point Slope & y=mx+b", type="tool", id="pt_ptslope"},
    {name="Parallel or Perpendicular?", type="tool", id="pt_parperp"},
    {name="Find Parallel/Perp Lines", type="tool", id="pt_findparperp"},
    {name="Read: Absolute Value |x|", type="read", id="pt_absval"},
  }},
  {name="Quadratic & Complex", items={
    {name="Quadratic Equation", type="tool", id="quad_formula"},
    {name="Complete the Square", type="tool", id="quad_complete"},
    {name="Complete Square -> Zeros", type="tool", id="quad_zeros"},
    {name="Complete Square -> Vertex", type="tool", id="quad_vertex"},
    {name="One Complex Number Explorer", type="tool", id="cx_one"},
    {name="Two Complex Numbers Explorer", type="tool", id="cx_two"},
  }},
  {name="Exponents & Logs", items={
    {name="Read: Exponents & Rules", type="read", id="exp_rules"},
    {name="Solve any Equation", type="tool", id="exp_solve"},
    {name="Rule of 72", type="tool", id="exp_rule72"},
    {name="Exponential Growth", type="tool", id="exp_growth"},
    {name="Read: Logarithms & Rules", type="read", id="log_rules"},
    {name="Evaluate Logarithms", type="tool", id="log_eval"},
    {name="Logarithm Solver", type="tool", id="log_solve"},
    {name="Change of Base", type="tool", id="log_cob"},
  }},
  {name="Sequences & Series", items={
    {name="Explicit Seq & Partial Sum", type="tool", id="seq_explicit"},
    {name="Recursive Seq & Partial Sum", type="tool", id="seq_recursive"},
    {name="Sequence Formula Finder", type="tool", id="seq_finder"},
    {name="Geometric Seq & Series", type="tool", id="seq_geometric"},
    {name="Arithmetic Sequence", type="tool", id="seq_arith"},
  }},
  {name="Matrices", items={
    {name="Matrix A Explorer", type="tool", id="mat_explore"},
    {name="A + B", type="tool", id="mat_add"},
    {name="Inverse of A", type="tool", id="mat_inv"},
    {name="Determinant of A", type="tool", id="mat_det"},
    {name="Row Echelon(A)", type="tool", id="mat_ref"},
    {name="RREF(A) - Steps", type="tool", id="mat_rref"},
    {name="Solve A*X=B", type="tool", id="mat_axb"},
    {name="Cramer Rule A*X=B", type="tool", id="mat_cramer"},
  }},
  {name="Circles", items={
    {name="Read: Unit Circle", type="read", id="circ_unit"},
    {name="Read: Circle Properties", type="read", id="circ_props"},
    {name="Find Sector", type="tool", id="circ_sector"},
    {name="Arc Length Solver", type="tool", id="circ_arc"},
  }},
  {name="Trigonometry", items={
    {name="Read: Intro", type="read", id="trig_intro"},
    {name="Solve 90\xC2\xB0 Triangle", type="tool", id="trig_right"},
    {name="Read: 3 Laws", type="read", id="trig_laws"},
    {name="Solve SSS Triangle", type="tool", id="trig_sss"},
    {name="Solve SAS Triangle", type="tool", id="trig_sas"},
    {name="Solve SSA Triangle", type="tool", id="trig_ssa"},
    {name="Solve SAA Triangle", type="tool", id="trig_saa"},
    {name="Evaluate sin(x)", type="tool", id="trig_sinx"},
  }},
  {name="Geometry", items={
    {name="2D: Circle Solver", type="tool", id="geo_circle"},
    {name="2D: Sector", type="tool", id="geo_sector"},
    {name="2D: Arc Length", type="tool", id="geo_arc"},
    {name="2D: Pythagorean Theorem", type="tool", id="geo_pyth"},
    {name="2D: Triangle Solver", type="tool", id="geo_tri"},
    {name="2D: Square Solver", type="tool", id="geo_square"},
    {name="2D: Rectangle Solver", type="tool", id="geo_rect"},
    {name="2D: Parallelogram", type="tool", id="geo_para"},
    {name="2D: Rhombus Solver", type="tool", id="geo_rhombus"},
    {name="2D: Trapezoid Solver", type="tool", id="geo_trap"},
    {name="3D: Sphere Solver", type="tool", id="geo_sphere"},
    {name="3D: Cube Solver", type="tool", id="geo_cube"},
    {name="3D: Cylinder Solver", type="tool", id="geo_cyl"},
    {name="3D: Cone Solver", type="tool", id="geo_cone"},
    {name="3D: Rectangular Prism", type="tool", id="geo_rprism"},
  }},
  {name="Convert", items={
    {name="Polar <-> (x,y)", type="tool", id="conv_polar"},
    {name="Degree <-> Radian", type="tool", id="conv_degrad"},
    {name="Degree to DMS", type="tool", id="conv_dms"},
    {name="Revolution to Deg/Rad", type="tool", id="conv_rev"},
  }},
  {name="SAT Specials", items={
    {name="Sigma S-Notation", type="tool", id="sat_sigma"},
    {name="Count Integers in Range", type="tool", id="sat_count"},
    {name="Count Divisible by N/M", type="tool", id="sat_div"},
    {name="Int Solutions: 2 Vars", type="tool", id="sat_2var"},
    {name="Int Solutions: 3 Vars", type="tool", id="sat_3var"},
  }},
}

---------------------------------------------------------------
-- TOOL DEFINITIONS (inputs and compute functions)
---------------------------------------------------------------
local tools = {}

-- ALGEBRA TOOLS
tools["alg_solve"] = {
  inputs = {{"Equation=", ""}},
  compute = function(v)
    local eq = v[1]
    local r = {}
    local sol = safeEval("solve("..eq..",x)")
    table.insert(r, "Solve: "..eq)
    table.insert(r, "")
    if sol then table.insert(r, "Solution: "..sol)
    else table.insert(r, "No solution found") end
    return r
  end
}

tools["alg_2x2"] = {
  inputs = {{"1.Eqn ", ""}, {"2.Eqn ", ""}},
  compute = function(v)
    local r = {}
    local e1, e2 = v[1], v[2]
    table.insert(r, "System:")
    table.insert(r, " "..e1)
    table.insert(r, " "..e2)
    table.insert(r, "")
    -- Parse ax+by=c from each equation
    local function parseEq(eq)
      -- Try CAS solve
      local sol = safeEval("solve({" ..e1..","..e2.."},{x,y})")
      return sol
    end
    local sol = safeEval("solve({"..e1..","..e2.."},{x,y})")
    if sol then
      table.insert(r, "Solution: "..sol)
      -- Extract x and y values
      local xv = safeEval("x|"..sol)
      local yv = safeEval("y|"..sol)
      if xv then table.insert(r, "") table.insert(r, "x = "..xv) end
      if yv then table.insert(r, "y = "..yv) end
    else
      table.insert(r, "No solution found")
    end
    return r
  end
}

tools["alg_3x3"] = {
  inputs = {{"1.Eqn ", ""}, {"2.Eqn ", ""}, {"3.Eqn ", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "System of 3 Equations:")
    for i = 1, 3 do table.insert(r, " "..v[i]) end
    table.insert(r, "")
    local sol = safeEval("solve({"..v[1]..","..v[2]..","..v[3].."},{x,y,z})")
    if sol then
      table.insert(r, "Solution: "..sol)
      local xv = safeEval("x|"..sol)
      local yv = safeEval("y|"..sol)
      local zv = safeEval("z|"..sol)
      if xv then table.insert(r, "") table.insert(r, "x = "..xv) end
      if yv then table.insert(r, "y = "..yv) end
      if zv then table.insert(r, "z = "..zv) end
    else table.insert(r, "No solution found") end
    return r
  end
}

tools["alg_simplify"] = {
  inputs = {{"Expr=", ""}},
  compute = function(v)
    local r = {}
    local expr = v[1]
    table.insert(r, "Expression: "..expr)
    table.insert(r, "")
    local s = safeEval("expand("..expr..")")
    if s then table.insert(r, "Expanded: "..s) end
    s = safeEval("factor("..expr..")")
    if s then table.insert(r, "Factored: "..s) end
    s = safeEval(expr)
    if s then table.insert(r, "Simplified: "..s) end
    return r
  end
}

tools["alg_factor"] = {
  inputs = {{"Integer=", ""}},
  compute = function(v)
    local n = tonumber(v[1])
    local r = {}
    if not n or n ~= math.floor(n) then
      table.insert(r, "Please enter an integer")
      return r
    end
    n = math.abs(n)
    table.insert(r, "Factor: "..n)
    table.insert(r, "")
    table.insert(r, n.." = "..factorStr(n))
    table.insert(r, "")
    -- List all divisors
    local divs = {}
    for i = 1, n do if n % i == 0 then table.insert(divs, i) end end
    table.insert(r, "Divisors: "..table.concat(divs, ", "))
    table.insert(r, "# of Divisors: "..#divs)
    return r
  end
}

tools["alg_powers"] = {
  inputs = {{"Base=", ""}, {"Exponent=", ""}},
  compute = function(v)
    local r = {}
    local b, e = v[1], v[2]
    table.insert(r, b.."^"..e.." = ")
    local s = safeEval("("..b..")^("..e..")")
    if s then table.insert(r, "  "..s) end
    return r
  end
}

tools["alg_gcdlcm"] = {
  inputs = {{"Integer1=", ""}, {"Integer2=", ""}},
  compute = function(v)
    local a, b = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not a or not b then table.insert(r, "Enter two integers") return r end
    a, b = math.floor(math.abs(a)), math.floor(math.abs(b))
    table.insert(r, a.." = "..factorStr(a))
    table.insert(r, b.." = "..factorStr(b))
    table.insert(r, "")
    local g = gcd(a, b)
    local l = lcm(a, b)
    table.insert(r, "GCD("..a..", "..b..") = "..g)
    table.insert(r, "LCM("..a..", "..b..") = "..l)
    return r
  end
}

tools["alg_proportion"] = {
  inputs = {{"a=", ""}, {"b=", ""}, {"c=", ""}, {"d=", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "Proportion: a/b = c/d")
    table.insert(r, "")
    local a,b,c,d = tonumber(v[1]),tonumber(v[2]),tonumber(v[3]),tonumber(v[4])
    local missing = nil
    if not a and b and c and d then missing="a" a=b*c/d
    elseif a and not b and c and d then missing="b" b=a*d/c
    elseif a and b and not c and d then missing="c" c=a*d/b
    elseif a and b and c and not d then missing="d" d=b*c/a
    end
    if missing then
      table.insert(r, "Missing: "..missing)
      table.insert(r, missing.." = "..round(missing=="a" and a or missing=="b" and b or missing=="c" and c or d))
      table.insert(r, "")
      table.insert(r, round(a).."/"..round(b).." = "..round(c).."/"..round(d))
    else
      table.insert(r, "Leave one field empty to solve")
    end
    return r
  end
}

tools["alg_pctchange"] = {
  inputs = {{"Old Value=", ""}, {"New Value=", ""}},
  compute = function(v)
    local old, new = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not old or not new then table.insert(r, "Enter both values") return r end
    local absC = new - old
    local pctC = (absC / math.abs(old)) * 100
    table.insert(r, "Old Value: "..old)
    table.insert(r, "New Value: "..new)
    table.insert(r, "")
    table.insert(r, "Absolute Change: "..round(absC))
    table.insert(r, "Percent Change: "..round(pctC).."%")
    if pctC > 0 then table.insert(r, "Direction: Increase")
    elseif pctC < 0 then table.insert(r, "Direction: Decrease")
    else table.insert(r, "Direction: No Change") end
    return r
  end
}

-- FUNCTIONS TOOLS
tools["fn_explore"] = {
  inputs = {{"f(x)=", ""}},
  compute = function(v)
    local f = v[1]
    local r = {}
    table.insert(r, "f(x) = "..f)
    table.insert(r, "")
    local z = safeEval("zeros("..f..",x)")
    if z then table.insert(r, "Zeros: "..z) end
    local d = safeEval("d("..f..",x)")
    if d then table.insert(r, "f'(x) = "..d) end
    local dd = safeEval("d("..f..",x,2)")
    if dd then table.insert(r, "f''(x) = "..dd) end
    local intg = safeEval("\xE2\x88\xAB("..f..",x)")
    if not intg then intg = safeEval("integral("..f..",x)") end
    if intg then table.insert(r, "\xE2\x88\xABf(x)dx = "..intg) end
    local dom = safeEval("domain("..f..",x)")
    if dom then table.insert(r, "Domain: "..dom) end
    return r
  end
}

tools["fn_eval"] = {
  inputs = {{"f(x)=", ""}, {"x=", ""}},
  compute = function(v)
    local r = {}
    local f, xv = v[1], v[2]
    table.insert(r, "f(x) = "..f)
    local val = safeEval(f.."|x="..xv)
    if val then table.insert(r, "f("..xv..") = "..val)
    else table.insert(r, "Could not evaluate") end
    return r
  end
}

tools["fn_intersect"] = {
  inputs = {{"f(x)=", ""}, {"g(x)=", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "f(x) = "..v[1])
    table.insert(r, "g(x) = "..v[2])
    table.insert(r, "")
    local sol = safeEval("solve("..v[1].."="..v[2]..",x)")
    if sol then table.insert(r, "Intersection x: "..sol)
    else table.insert(r, "No intersection found") end
    return r
  end
}

tools["fn_add"] = {
  inputs = {{"f(x)=", ""}, {"g(x)=", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "f(x) = "..v[1])
    table.insert(r, "g(x) = "..v[2])
    table.insert(r, "")
    local s = safeEval("expand(("..v[1]..")+("..v[2].."))")
    if s then table.insert(r, "(f+g)(x) = "..s) end
    s = safeEval("expand(("..v[1]..")-("..v[2].."))")
    if s then table.insert(r, "(f-g)(x) = "..s) end
    s = safeEval("expand(("..v[1]..")*("..v[2].."))")
    if s then table.insert(r, "(f\xC2\xB7g)(x) = "..s) end
    s = safeEval("("..v[1]..")/("..v[2]..")")
    if s then table.insert(r, "(f/g)(x) = "..s) end
    return r
  end
}

tools["fn_compose"] = {
  inputs = {{"f(x)=", ""}, {"g(x)=", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "f(x) = "..v[1])
    table.insert(r, "g(x) = "..v[2])
    table.insert(r, "")
    local fog = safeEval(v[1].."|x="..v[2])
    if fog then
      local s = safeEval("expand("..fog..")")
      table.insert(r, "f(g(x)) = "..(s or fog))
    end
    local gof = safeEval(v[2].."|x="..v[1])
    if gof then
      local s = safeEval("expand("..gof..")")
      table.insert(r, "g(f(x)) = "..(s or gof))
    end
    return r
  end
}

tools["fn_diffquot"] = {
  inputs = {{"f(x)=", ""}},
  compute = function(v)
    local r = {}
    local f = v[1]
    table.insert(r, "f(x) = "..f)
    table.insert(r, "")
    -- f(x+h)
    local fxh = safeEval("expand("..f.."|x=x+h)")
    if fxh then table.insert(r, "f(x+h) = "..fxh) end
    -- [f(x+h) - f(x)]/h
    local dq = safeEval("expand(("..f.."|x=x+h - ("..f.."))/h)")
    if dq then table.insert(r, "[f(x+h)-f(x)]/h = "..dq) end
    local deriv = safeEval("d("..f..",x)")
    if deriv then table.insert(r, "") table.insert(r, "As h->0: f'(x) = "..deriv) end
    return r
  end
}

-- POLYNOMIAL TOOLS
tools["poly_explore"] = {
  inputs = {{"p(x)=", ""}},
  compute = function(v)
    local r = {}
    local p = v[1]
    table.insert(r, "p(x) = "..p)
    table.insert(r, "")
    local deg = safeEval("degree("..p..",x)")
    if deg then table.insert(r, "Degree: "..deg) end
    local z = safeEval("zeros("..p..",x)")
    if z then table.insert(r, "Zeros: "..z) end
    local f = safeEval("factor("..p..")")
    if f then table.insert(r, "Factored: "..f) end
    local d = safeEval("d("..p..",x)")
    if d then table.insert(r, "p'(x) = "..d) end
    local lc = safeEval("polyCoeffs("..p..",x)")
    if lc then table.insert(r, "Coefficients: "..lc) end
    return r
  end
}

tools["poly_degree"] = {
  inputs = {{"p(x)=", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "p(x) = "..v[1])
    local deg = safeEval("degree("..v[1]..",x)")
    if deg then table.insert(r, "Degree: "..deg)
    else table.insert(r, "Could not determine degree") end
    return r
  end
}

-- POINTS AND LINES TOOLS
tools["pt_slope"] = {
  inputs = {{"x1=", ""}, {"y1=", ""}, {"x2=", ""}, {"y2=", ""}},
  compute = function(v)
    local x1,y1,x2,y2 = tonumber(v[1]),tonumber(v[2]),tonumber(v[3]),tonumber(v[4])
    local r = {}
    if not (x1 and y1 and x2 and y2) then table.insert(r, "Enter all 4 values") return r end
    table.insert(r, "P1("..x1..", "..y1..")  P2("..x2..", "..y2..")")
    table.insert(r, "")
    if x2 == x1 then
      table.insert(r, "Slope: undefined (vertical)")
    else
      local m = (y2 - y1) / (x2 - x1)
      table.insert(r, "m = (y2-y1)/(x2-x1)")
      table.insert(r, "m = ("..(y2-y1)..") / ("..(x2-x1)..")")
      table.insert(r, "m = "..round(m))
      local b = y1 - m * x1
      table.insert(r, "")
      table.insert(r, "y = "..round(m).."x + "..round(b))
    end
    return r
  end
}

tools["pt_ymxb"] = {
  inputs = {{"m (slope)=", ""}, {"b (intercept)=", ""}},
  compute = function(v)
    local m, b = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not m or not b then table.insert(r, "Enter m and b") return r end
    table.insert(r, "y = "..m.."x + "..b)
    table.insert(r, "")
    table.insert(r, "Slope: "..m)
    table.insert(r, "y-intercept: (0, "..b..")")
    if m ~= 0 then table.insert(r, "x-intercept: ("..round(-b/m)..", 0)") end
    return r
  end
}

tools["pt_ptslope"] = {
  inputs = {{"x1=", ""}, {"y1=", ""}, {"m=", ""}},
  compute = function(v)
    local x1,y1,m = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (x1 and y1 and m) then table.insert(r, "Enter point and slope") return r end
    table.insert(r, "Point: ("..x1..", "..y1..")  Slope: "..m)
    table.insert(r, "")
    table.insert(r, "Point-Slope Form:")
    table.insert(r, "y - "..y1.." = "..m.."(x - "..x1..")")
    local b = y1 - m * x1
    table.insert(r, "")
    table.insert(r, "Slope-Intercept Form:")
    table.insert(r, "y = "..round(m).."x + "..round(b))
    return r
  end
}

tools["pt_parperp"] = {
  inputs = {{"m1=", ""}, {"m2=", ""}},
  compute = function(v)
    local m1, m2 = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not m1 or not m2 then table.insert(r, "Enter both slopes") return r end
    table.insert(r, "m1 = "..m1.."  m2 = "..m2)
    table.insert(r, "")
    if m1 == m2 then table.insert(r, "Lines are PARALLEL (m1 = m2)")
    elseif math.abs(m1 * m2 + 1) < 0.0001 then table.insert(r, "Lines are PERPENDICULAR (m1*m2 = -1)")
    else table.insert(r, "Lines are NEITHER parallel nor perpendicular")
      table.insert(r, "m1*m2 = "..round(m1*m2).." (would be -1 if perp)")
    end
    return r
  end
}

tools["pt_findparperp"] = {
  inputs = {{"m=", ""}, {"x1=", ""}, {"y1=", ""}},
  compute = function(v)
    local m,x1,y1 = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (m and x1 and y1) then table.insert(r, "Enter slope and point") return r end
    table.insert(r, "Through ("..x1..", "..y1..") with m = "..m)
    table.insert(r, "")
    local bp = y1 - m * x1
    table.insert(r, "Parallel line (m="..m.."):")
    table.insert(r, "y = "..round(m).."x + "..round(bp))
    table.insert(r, "")
    if m ~= 0 then
      local mp = -1/m
      local bpp = y1 - mp * x1
      table.insert(r, "Perpendicular line (m="..round(mp).."):")
      table.insert(r, "y = "..round(mp).."x + "..round(bpp))
    else table.insert(r, "Perpendicular: x = "..x1) end
    return r
  end
}

-- QUADRATIC TOOLS
tools["quad_formula"] = {
  inputs = {{"a=", ""}, {"b=", ""}, {"c=", ""}},
  compute = function(v)
    local a,b,c = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a and b and c) then table.insert(r, "Enter a, b, c") return r end
    table.insert(r, a.."x\xC2\xB2 + "..b.."x + "..c.." = 0")
    table.insert(r, "")
    local disc = b*b - 4*a*c
    table.insert(r, "Discriminant = b\xC2\xB2-4ac = "..round(disc))
    table.insert(r, "")
    if disc > 0 then
      local x1 = (-b + math.sqrt(disc)) / (2*a)
      local x2 = (-b - math.sqrt(disc)) / (2*a)
      table.insert(r, "Two Real Solutions:")
      table.insert(r, "x1 = "..round(x1))
      table.insert(r, "x2 = "..round(x2))
    elseif disc == 0 then
      local x1 = -b / (2*a)
      table.insert(r, "One Repeated Solution:")
      table.insert(r, "x = "..round(x1))
    else
      local real = -b / (2*a)
      local imag = math.sqrt(-disc) / (2*a)
      table.insert(r, "Two Complex Solutions:")
      table.insert(r, "x1 = "..round(real).." + "..round(imag).."i")
      table.insert(r, "x2 = "..round(real).." - "..round(imag).."i")
    end
    table.insert(r, "")
    table.insert(r, "Vertex: ("..round(-b/(2*a))..", "..round(c - b*b/(4*a))..")")
    return r
  end
}

tools["quad_complete"] = {
  inputs = {{"a=", ""}, {"b=", ""}, {"c=", ""}},
  compute = function(v)
    local a,b,c = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a and b and c) then table.insert(r, "Enter a, b, c") return r end
    table.insert(r, a.."x\xC2\xB2 + "..b.."x + "..c)
    table.insert(r, "")
    table.insert(r, "Complete the Square:")
    local h = -b / (2*a)
    local k = c - b*b / (4*a)
    table.insert(r, "= "..a.."(x\xC2\xB2 + "..round(b/a).."x) + "..c)
    table.insert(r, "= "..a.."(x + "..round(h)..") \xC2\xB2 + "..round(k))
    table.insert(r, "")
    table.insert(r, "Vertex Form: "..a.."(x - "..round(-h)..")\xC2\xB2 + "..round(k))
    return r
  end
}

tools["quad_zeros"] = tools["quad_formula"]

tools["quad_vertex"] = {
  inputs = {{"a=", ""}, {"b=", ""}, {"c=", ""}},
  compute = function(v)
    local a,b,c = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a and b and c) then table.insert(r, "Enter a, b, c") return r end
    local h = -b / (2*a)
    local k = c - b*b / (4*a)
    table.insert(r, "f(x) = "..a.."x\xC2\xB2 + "..b.."x + "..c)
    table.insert(r, "")
    table.insert(r, "Vertex Form:")
    table.insert(r, "f(x) = "..a.."(x - "..round(h)..")\xC2\xB2 + "..round(k))
    table.insert(r, "")
    table.insert(r, "Vertex: ("..round(h)..", "..round(k)..")")
    table.insert(r, "Axis of Symmetry: x = "..round(h))
    if a > 0 then table.insert(r, "Opens: Upward (minimum)")
    else table.insert(r, "Opens: Downward (maximum)") end
    return r
  end
}

tools["cx_one"] = {
  inputs = {{"z1=", ""}},
  compute = function(v)
    local r = {}
    local z = v[1]
    table.insert(r, "z1 = "..z)
    table.insert(r, "")
    local re = safeEval("real("..z..")")
    local im = safeEval("imag("..z..")")
    if re then table.insert(r, "Real part of "..z.." : "..re) end
    if im then table.insert(r, "Imaginary part of "..z.." : "..im.."i") end
    local rn = tonumber(re) or 0
    local imn = tonumber(im) or 0
    local modulus = math.sqrt(rn*rn + imn*imn)
    table.insert(r, "")
    table.insert(r, "r=Length of "..z.." = |"..z.."| =")
    table.insert(r, "\xE2\x88\x9A("..rn.."\xC2\xB2+("..imn..")\xC2\xB2) = "..round(modulus))
    table.insert(r, "")
    local angle = math.deg(math.atan2(imn, rn))
    table.insert(r, "\xCE\xB8=Angle with x-axis: "..round(angle).."\xC2\xB0")
    table.insert(r, "")
    local conj = safeEval("conj("..z..")")
    if conj then table.insert(r, "Conjugate: "..conj) end
    return r
  end
}

tools["cx_two"] = {
  inputs = {{"z1=", ""}, {"z2=", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "z1 = "..v[1].."  z2 = "..v[2])
    table.insert(r, "")
    local s = safeEval("("..v[1]..") + ("..v[2]..")")
    if s then table.insert(r, "z1 + z2 = "..s) end
    s = safeEval("("..v[1]..") - ("..v[2]..")")
    if s then table.insert(r, "z1 - z2 = "..s) end
    s = safeEval("("..v[1]..") * ("..v[2]..")")
    if s then table.insert(r, "z1 \xC2\xB7 z2 = "..s) end
    s = safeEval("("..v[1]..") / ("..v[2]..")")
    if s then table.insert(r, "z1 / z2 = "..s) end
    return r
  end
}

-- EXPONENTS & LOGS TOOLS
tools["exp_solve"] = {
  inputs = {{"Equation=", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "Solve: "..v[1])
    local sol = safeEval("solve("..v[1]..",x)")
    if sol then table.insert(r, "Solution: "..sol)
    else table.insert(r, "No solution found") end
    return r
  end
}

tools["exp_rule72"] = {
  inputs = {{"Rate(%)=", ""}},
  compute = function(v)
    local rate = tonumber(v[1])
    local r = {}
    if not rate then table.insert(r, "Enter interest rate %") return r end
    table.insert(r, "Rule of 72")
    table.insert(r, "Rate: "..rate.."%")
    table.insert(r, "")
    table.insert(r, "Doubling Time \xE2\x89\x88 72/"..rate)
    table.insert(r, "= "..round(72/rate).." periods")
    return r
  end
}

tools["exp_growth"] = {
  inputs = {{"P0 (initial)=", ""}, {"rate(%)=", ""}, {"t (time)=", ""}},
  compute = function(v)
    local p0,rate,t = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (p0 and rate and t) then table.insert(r, "Enter all values") return r end
    local rr = rate/100
    table.insert(r, "P(t) = P0 \xC2\xB7 (1+r)^t")
    table.insert(r, "P("..t..") = "..p0.." \xC2\xB7 (1+"..rr..")^"..t)
    local result = p0 * (1+rr)^t
    table.insert(r, "= "..round(result, 2))
    table.insert(r, "")
    table.insert(r, "Continuous: P0\xC2\xB7e^(rt)")
    local cont = p0 * math.exp(rr*t)
    table.insert(r, "= "..round(cont, 2))
    return r
  end
}

tools["log_eval"] = {
  inputs = {{"Base=", ""}, {"Value=", ""}},
  compute = function(v)
    local b, val = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not b or not val then table.insert(r, "Enter base and value") return r end
    local result = math.log(val)/math.log(b)
    table.insert(r, "log_"..b.."("..val..") = "..round(result))
    return r
  end
}

tools["log_solve"] = tools["exp_solve"]

tools["log_cob"] = {
  inputs = {{"Base=", ""}, {"Value=", ""}},
  compute = function(v)
    local b, val = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not b or not val then table.insert(r, "Enter base and value") return r end
    table.insert(r, "Change of Base Formula:")
    table.insert(r, "log_"..b.."("..val..") = ln("..val..")/ln("..b..")")
    table.insert(r, "= "..round(math.log(val)).."/"..round(math.log(b)))
    table.insert(r, "= "..round(math.log(val)/math.log(b)))
    return r
  end
}

-- SEQUENCES TOOLS
tools["seq_explicit"] = {
  inputs = {{"a(n)=", ""}, {"n=", ""}},
  compute = function(v)
    local r = {}
    local expr, nv = v[1], tonumber(v[2])
    table.insert(r, "a(n) = "..expr)
    if nv then
      table.insert(r, "")
      for i = 1, math.min(nv, 10) do
        local val = safeEval(expr.."|n="..i)
        if val then table.insert(r, "a("..i..") = "..val) end
      end
      table.insert(r, "")
      local sum = safeEval("sum("..expr..",n,1,"..nv..")")
      if sum then table.insert(r, "Sum(1 to "..nv..") = "..sum) end
    end
    return r
  end
}

tools["seq_recursive"] = tools["seq_explicit"]

tools["seq_finder"] = {
  inputs = {{"Terms (comma sep)=", ""}},
  compute = function(v)
    local r = {}
    local terms = {}
    for t in v[1]:gmatch("[^,]+") do table.insert(terms, tonumber(t:match("^%s*(.-)%s*$"))) end
    if #terms < 3 then table.insert(r, "Enter at least 3 terms") return r end
    table.insert(r, "Terms: "..v[1])
    table.insert(r, "")
    local d = terms[2] - terms[1]
    local isArith = true
    for i = 3, #terms do if terms[i] - terms[i-1] ~= d then isArith = false break end end
    if isArith then
      table.insert(r, "Arithmetic Sequence")
      table.insert(r, "d = "..d)
      table.insert(r, "a(n) = "..terms[1].." + "..d.."(n-1)")
      table.insert(r, "a(n) = "..d.."n + "..(terms[1]-d))
    end
    if terms[1] ~= 0 then
      local ratio = terms[2]/terms[1]
      local isGeo = true
      for i = 3, #terms do if terms[i-1]==0 or terms[i]/terms[i-1] ~= ratio then isGeo = false break end end
      if isGeo then
        table.insert(r, "Geometric Sequence")
        table.insert(r, "r = "..ratio)
        table.insert(r, "a(n) = "..terms[1].." \xC2\xB7 "..ratio.."^(n-1)")
      end
    end
    return r
  end
}

tools["seq_geometric"] = {
  inputs = {{"a1=", ""}, {"r=", ""}, {"n=", ""}},
  compute = function(v)
    local a1,ratio,n = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a1 and ratio and n) then table.insert(r, "Enter a1, r, n") return r end
    table.insert(r, "Geometric: a1="..a1..", r="..ratio)
    table.insert(r, "a(n) = "..a1.." \xC2\xB7 "..ratio.."^(n-1)")
    table.insert(r, "a("..n..") = "..round(a1 * ratio^(n-1)))
    table.insert(r, "")
    if ratio ~= 1 then
      local sn = a1*(1-ratio^n)/(1-ratio)
      table.insert(r, "S("..n..") = "..round(sn))
    end
    if math.abs(ratio) < 1 then
      table.insert(r, "S(inf) = "..round(a1/(1-ratio)))
    end
    return r
  end
}

tools["seq_arith"] = {
  inputs = {{"a(n)=", ""}},
  compute = function(v)
    local r = {}
    local expr = v[1]
    table.insert(r, "a(n) = "..expr)
    local a1 = safeEval(expr.."|n=1")
    local a2 = safeEval(expr.."|n=2")
    if a1 and a2 then
      local d = tonumber(a2) - tonumber(a1)
      table.insert(r, "")
      table.insert(r, "Arithmetic Sequence: a(n)="..expr)
      table.insert(r, "with difference d="..d.." and first term")
      table.insert(r, "a1="..a1)
    end
    return r
  end
}

-- MATRICES TOOLS
tools["mat_explore"] = {
  inputs = {{"Matrix A=", ""}},
  compute = function(v)
    local r = {}
    local a = v[1]
    table.insert(r, "A = "..a)
    table.insert(r, "")
    local det = safeEval("det("..a..")")
    if det then table.insert(r, "det(A) = "..det) end
    local tr = safeEval("trace("..a..")")
    if tr then table.insert(r, "trace(A) = "..tr) end
    local inv = safeEval("("..a..")^(-1)")
    if inv then table.insert(r, "A^(-1) = "..inv) end
    local trans = safeEval("("..a..")^t")
    if trans then table.insert(r, "A^T = "..trans) end
    return r
  end
}

tools["mat_add"] = {
  inputs = {{"Matrix A=", ""}, {"Matrix B=", ""}},
  compute = function(v)
    local r = {}
    local s = safeEval("("..v[1]..")+("..v[2]..")")
    if s then table.insert(r, "A + B = "..s) end
    s = safeEval("("..v[1]..")-("..v[2]..")")
    if s then table.insert(r, "A - B = "..s) end
    s = safeEval("("..v[1]..")*("..v[2]..")")
    if s then table.insert(r, "A * B = "..s) end
    return r
  end
}

tools["mat_inv"] = {
  inputs = {{"Matrix A=", ""}},
  compute = function(v)
    local r = {}
    local inv = safeEval("("..v[1]..")^(-1)")
    if inv then table.insert(r, "A^(-1) = "..inv)
    else table.insert(r, "Matrix is not invertible") end
    return r
  end
}

tools["mat_det"] = {
  inputs = {{"Matrix A=", ""}},
  compute = function(v)
    local r = {}
    local det = safeEval("det("..v[1]..")")
    if det then table.insert(r, "det(A) = "..det)
    else table.insert(r, "Could not compute determinant") end
    return r
  end
}

tools["mat_ref"] = {
  inputs = {{"Matrix A=", ""}},
  compute = function(v)
    local r = {}
    local ref = safeEval("ref("..v[1]..")")
    if ref then table.insert(r, "ref(A) = "..ref) end
    return r
  end
}

tools["mat_rref"] = {
  inputs = {{"Matrix A=", ""}},
  compute = function(v)
    local r = {}
    local rref = safeEval("rref("..v[1]..")")
    if rref then table.insert(r, "rref(A) = "..rref) end
    return r
  end
}

tools["mat_axb"] = {
  inputs = {{"Matrix A=", ""}, {"Matrix B=", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "Solve A*X = B")
    local sol = safeEval("("..v[1]..")^(-1)*("..v[2]..")")
    if sol then table.insert(r, "X = A^(-1)*B = "..sol)
    else table.insert(r, "No solution (A not invertible)") end
    return r
  end
}

tools["mat_cramer"] = tools["mat_axb"]

-- CIRCLES TOOLS
tools["circ_sector"] = {
  inputs = {{"r=", ""}, {"\xCE\xB8 (deg)=", ""}},
  compute = function(v)
    local radius, angle = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not (radius and angle) then table.insert(r, "Enter r and angle") return r end
    local rad = math.rad(angle)
    local area = 0.5 * radius^2 * rad
    table.insert(r, "Sector with r="..radius..", \xCE\xB8="..angle.."\xC2\xB0")
    table.insert(r, "")
    table.insert(r, "Area = \xC2\xBD r\xC2\xB2\xCE\xB8")
    table.insert(r, "= "..round(area))
    local arcLen = radius * rad
    table.insert(r, "Arc Length = r\xCE\xB8 = "..round(arcLen))
    return r
  end
}

tools["circ_arc"] = {
  inputs = {{"r=", ""}, {"\xCE\xB8 (deg)=", ""}},
  compute = function(v)
    local radius, angle = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not (radius and angle) then table.insert(r, "Enter r and angle") return r end
    local arcLen = radius * math.rad(angle)
    table.insert(r, "Arc Length = r \xC2\xB7 \xCE\xB8(rad)")
    table.insert(r, "= "..radius.." \xC2\xB7 "..round(math.rad(angle)))
    table.insert(r, "= "..round(arcLen))
    return r
  end
}

-- TRIGONOMETRY TOOLS
tools["trig_right"] = {
  inputs = {{"a=", ""}, {"b=", ""}, {"c(hyp)=", ""}},
  compute = function(v)
    local a,b,c = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if a and b and not c then c = math.sqrt(a*a+b*b)
    elseif a and c and not b then b = math.sqrt(c*c-a*a)
    elseif b and c and not a then a = math.sqrt(c*c-b*b)
    else table.insert(r, "Enter 2 of 3 sides") return r end
    table.insert(r, "Right Triangle:")
    table.insert(r, "a="..round(a).." b="..round(b).." c="..round(c))
    table.insert(r, "")
    local A = math.deg(math.asin(a/c))
    local B = 90 - A
    table.insert(r, "Angle A = "..round(A).."\xC2\xB0")
    table.insert(r, "Angle B = "..round(B).."\xC2\xB0")
    table.insert(r, "Area = "..round(0.5*a*b))
    table.insert(r, "Perimeter = "..round(a+b+c))
    return r
  end
}

tools["trig_sss"] = {
  inputs = {{"a=", ""}, {"b=", ""}, {"c=", ""}},
  compute = function(v)
    local a,b,c = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a and b and c) then table.insert(r, "Enter all 3 sides") return r end
    local A = math.deg(math.acos((b*b+c*c-a*a)/(2*b*c)))
    local B = math.deg(math.acos((a*a+c*c-b*b)/(2*a*c)))
    local C = 180 - A - B
    table.insert(r, "SSS: a="..a.." b="..b.." c="..c)
    table.insert(r, "A="..round(A).."\xC2\xB0 B="..round(B).."\xC2\xB0 C="..round(C).."\xC2\xB0")
    local s = (a+b+c)/2
    table.insert(r, "Area = "..round(math.sqrt(s*(s-a)*(s-b)*(s-c))))
    return r
  end
}

tools["trig_sas"] = {
  inputs = {{"a=", ""}, {"C (deg)=", ""}, {"b=", ""}},
  compute = function(v)
    local a,C,b = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a and C and b) then table.insert(r, "Enter a, C, b") return r end
    local Cr = math.rad(C)
    local c = math.sqrt(a*a+b*b-2*a*b*math.cos(Cr))
    local A = math.deg(math.asin(a*math.sin(Cr)/c))
    local B = 180 - A - C
    table.insert(r, "SAS: a="..a.." C="..C.."\xC2\xB0 b="..b)
    table.insert(r, "c="..round(c))
    table.insert(r, "A="..round(A).."\xC2\xB0 B="..round(B).."\xC2\xB0")
    table.insert(r, "Area = "..round(0.5*a*b*math.sin(Cr)))
    return r
  end
}

tools["trig_ssa"] = {
  inputs = {{"a=", ""}, {"b=", ""}, {"A (deg)=", ""}},
  compute = function(v)
    local a,b,A = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a and b and A) then table.insert(r, "Enter a, b, A") return r end
    local Ar = math.rad(A)
    local sinB = b*math.sin(Ar)/a
    if sinB > 1 then table.insert(r, "No triangle exists") return r end
    local B = math.deg(math.asin(sinB))
    local C = 180 - A - B
    local c = a*math.sin(math.rad(C))/math.sin(Ar)
    table.insert(r, "SSA: a="..a.." b="..b.." A="..A.."\xC2\xB0")
    table.insert(r, "B="..round(B).."\xC2\xB0 C="..round(C).."\xC2\xB0 c="..round(c))
    table.insert(r, "Area = "..round(0.5*a*c*math.sin(math.rad(B))))
    if sinB < 1 and B < 90 then
      table.insert(r, "")
      table.insert(r, "Ambiguous case - 2nd triangle:")
      local B2 = 180 - B
      local C2 = 180 - A - B2
      if C2 > 0 then
        local c2 = a*math.sin(math.rad(C2))/math.sin(Ar)
        table.insert(r, "B="..round(B2).."\xC2\xB0 C="..round(C2).."\xC2\xB0 c="..round(c2))
      end
    end
    return r
  end
}

tools["trig_saa"] = {
  inputs = {{"a=", ""}, {"A (deg)=", ""}, {"B (deg)=", ""}},
  compute = function(v)
    local a,A,B = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a and A and B) then table.insert(r, "Enter a, A, B") return r end
    local C = 180 - A - B
    local b = a*math.sin(math.rad(B))/math.sin(math.rad(A))
    local c = a*math.sin(math.rad(C))/math.sin(math.rad(A))
    table.insert(r, "SAA: a="..a.." A="..A.."\xC2\xB0 B="..B.."\xC2\xB0")
    table.insert(r, "C="..round(C).."\xC2\xB0 b="..round(b).." c="..round(c))
    table.insert(r, "Area = "..round(0.5*b*c*math.sin(math.rad(A))))
    return r
  end
}

tools["trig_sinx"] = {
  inputs = {{"x (deg)=", ""}},
  compute = function(v)
    local x = tonumber(v[1])
    local r = {}
    if not x then table.insert(r, "Enter angle in degrees") return r end
    local xr = math.rad(x)
    table.insert(r, "x = "..x.."\xC2\xB0 = "..round(xr).." rad")
    table.insert(r, "")
    table.insert(r, "sin("..x.."\xC2\xB0) = "..round(math.sin(xr)))
    table.insert(r, "cos("..x.."\xC2\xB0) = "..round(math.cos(xr)))
    table.insert(r, "tan("..x.."\xC2\xB0) = "..round(math.tan(xr)))
    return r
  end
}

-- GEOMETRY TOOLS
local function geoTool(name, labels, fn)
  tools[name] = { inputs = labels, compute = fn }
end

geoTool("geo_circle", {{"r=", ""}}, function(v)
  local r = {}; local radius = tonumber(v[1])
  if not radius then table.insert(r, "Enter radius") return r end
  table.insert(r, "Circle: r = "..radius)
  table.insert(r, "Area = \xCF\x80r\xC2\xB2 = "..round(math.pi*radius^2))
  table.insert(r, "Circumference = 2\xCF\x80r = "..round(2*math.pi*radius))
  table.insert(r, "Diameter = "..2*radius)
  return r
end)

geoTool("geo_sector", tools["circ_sector"].inputs, tools["circ_sector"].compute)
geoTool("geo_arc", tools["circ_arc"].inputs, tools["circ_arc"].compute)

geoTool("geo_pyth", {{"a=", ""}, {"b=", ""}}, function(v)
  local r = {}; local a,b = tonumber(v[1]),tonumber(v[2])
  if not (a and b) then table.insert(r, "Enter a and b") return r end
  local c = math.sqrt(a*a+b*b)
  table.insert(r, "a\xC2\xB2 + b\xC2\xB2 = c\xC2\xB2")
  table.insert(r, a.."\xC2\xB2 + "..b.."\xC2\xB2 = "..round(c).."\xC2\xB2")
  table.insert(r, "c = "..round(c))
  return r
end)

geoTool("geo_tri", {{"base=", ""}, {"height=", ""}}, function(v)
  local r = {}; local base,h = tonumber(v[1]),tonumber(v[2])
  if not (base and h) then table.insert(r, "Enter base and height") return r end
  table.insert(r, "Triangle: base="..base.." height="..h)
  table.insert(r, "Area = \xC2\xBDbh = "..round(0.5*base*h))
  return r
end)

geoTool("geo_square", {{"side=", ""}}, function(v)
  local r = {}; local s = tonumber(v[1])
  if not s then table.insert(r, "Enter side") return r end
  table.insert(r, "Square: s = "..s)
  table.insert(r, "Area = "..round(s*s))
  table.insert(r, "Perimeter = "..round(4*s))
  table.insert(r, "Diagonal = "..round(s*math.sqrt(2)))
  return r
end)

geoTool("geo_rect", {{"length=", ""}, {"width=", ""}}, function(v)
  local r = {}; local l,w = tonumber(v[1]),tonumber(v[2])
  if not (l and w) then table.insert(r, "Enter l and w") return r end
  table.insert(r, "Rectangle: "..l.." x "..w)
  table.insert(r, "Area = "..round(l*w))
  table.insert(r, "Perimeter = "..round(2*(l+w)))
  table.insert(r, "Diagonal = "..round(math.sqrt(l*l+w*w)))
  return r
end)

geoTool("geo_para", {{"base=", ""}, {"height=", ""}, {"side=", ""}}, function(v)
  local r = {}; local b,h,s = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
  if not (b and h) then table.insert(r, "Enter base and height") return r end
  table.insert(r, "Parallelogram: b="..b.." h="..h)
  table.insert(r, "Area = bh = "..round(b*h))
  if s then table.insert(r, "Perimeter = "..round(2*(b+s))) end
  return r
end)

geoTool("geo_rhombus", {{"d1=", ""}, {"d2=", ""}}, function(v)
  local r = {}; local d1,d2 = tonumber(v[1]),tonumber(v[2])
  if not (d1 and d2) then table.insert(r, "Enter diagonals") return r end
  table.insert(r, "Rhombus: d1="..d1.." d2="..d2)
  table.insert(r, "Area = \xC2\xBDd1\xC2\xB7d2 = "..round(0.5*d1*d2))
  local s = math.sqrt((d1/2)^2+(d2/2)^2)
  table.insert(r, "Side = "..round(s))
  table.insert(r, "Perimeter = "..round(4*s))
  return r
end)

geoTool("geo_trap", {{"a(top)=", ""}, {"b(bot)=", ""}, {"h=", ""}}, function(v)
  local r = {}; local a,b,h = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
  if not (a and b and h) then table.insert(r, "Enter a, b, h") return r end
  table.insert(r, "Trapezoid: a="..a.." b="..b.." h="..h)
  table.insert(r, "Area = \xC2\xBD(a+b)h = "..round(0.5*(a+b)*h))
  return r
end)

geoTool("geo_sphere", {{"r=", ""}}, function(v)
  local r = {}; local radius = tonumber(v[1])
  if not radius then table.insert(r, "Enter radius") return r end
  table.insert(r, "Sphere: r = "..radius)
  table.insert(r, "Volume = 4/3\xCF\x80r\xC2\xB3 = "..round(4/3*math.pi*radius^3))
  table.insert(r, "Surface = 4\xCF\x80r\xC2\xB2 = "..round(4*math.pi*radius^2))
  return r
end)

geoTool("geo_cube", {{"side=", ""}}, function(v)
  local r = {}; local s = tonumber(v[1])
  if not s then table.insert(r, "Enter side") return r end
  table.insert(r, "Cube: s = "..s)
  table.insert(r, "Volume = s\xC2\xB3 = "..round(s^3))
  table.insert(r, "Surface = 6s\xC2\xB2 = "..round(6*s^2))
  table.insert(r, "Diagonal = s\xE2\x88\x9A3 = "..round(s*math.sqrt(3)))
  return r
end)

geoTool("geo_cyl", {{"r=", ""}, {"h=", ""}}, function(v)
  local r = {}; local radius,h = tonumber(v[1]),tonumber(v[2])
  if not (radius and h) then table.insert(r, "Enter r and h") return r end
  table.insert(r, "Cylinder: r="..radius.." h="..h)
  table.insert(r, "Volume = \xCF\x80r\xC2\xB2h = "..round(math.pi*radius^2*h))
  table.insert(r, "Lateral = 2\xCF\x80rh = "..round(2*math.pi*radius*h))
  table.insert(r, "Total SA = "..round(2*math.pi*radius*(radius+h)))
  return r
end)

geoTool("geo_cone", {{"r=", ""}, {"h=", ""}}, function(v)
  local r = {}; local radius,h = tonumber(v[1]),tonumber(v[2])
  if not (radius and h) then table.insert(r, "Enter r and h") return r end
  local slant = math.sqrt(radius^2+h^2)
  table.insert(r, "Cone: r="..radius.." h="..h)
  table.insert(r, "Slant = "..round(slant))
  table.insert(r, "Volume = 1/3\xCF\x80r\xC2\xB2h = "..round(math.pi*radius^2*h/3))
  table.insert(r, "Lateral = \xCF\x80rl = "..round(math.pi*radius*slant))
  table.insert(r, "Total SA = "..round(math.pi*radius*(radius+slant)))
  return r
end)

geoTool("geo_rprism", {{"l=", ""}, {"w=", ""}, {"h=", ""}}, function(v)
  local r = {}; local l,w,h = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
  if not (l and w and h) then table.insert(r, "Enter l, w, h") return r end
  table.insert(r, "Rectangular Prism: "..l.."x"..w.."x"..h)
  table.insert(r, "Volume = "..round(l*w*h))
  table.insert(r, "Surface = "..round(2*(l*w+l*h+w*h)))
  table.insert(r, "Diagonal = "..round(math.sqrt(l*l+w*w+h*h)))
  return r
end)

-- CONVERT TOOLS
tools["conv_polar"] = {
  inputs = {{"x=", ""}, {"y=", ""}},
  compute = function(v)
    local x,y = tonumber(v[1]),tonumber(v[2])
    local r = {}
    if not (x and y) then table.insert(r, "Enter x and y") return r end
    local radius = math.sqrt(x*x+y*y)
    local theta = math.deg(math.atan2(y,x))
    table.insert(r, "(x, y) = ("..x..", "..y..")")
    table.insert(r, "")
    table.insert(r, "r = "..round(radius))
    table.insert(r, "\xCE\xB8 = "..round(theta).."\xC2\xB0 = "..round(math.rad(theta)).." rad")
    table.insert(r, "")
    table.insert(r, "Polar: ("..round(radius)..", "..round(theta).."\xC2\xB0)")
    return r
  end
}

tools["conv_degrad"] = {
  inputs = {{"Degrees=", ""}},
  compute = function(v)
    local d = tonumber(v[1])
    local r = {}
    if not d then table.insert(r, "Enter degrees") return r end
    local rad = math.rad(d)
    table.insert(r, d.."\xC2\xB0 = "..round(rad).." rad")
    table.insert(r, "= "..round(rad/math.pi).."\xCF\x80 rad")
    table.insert(r, "")
    table.insert(r, "Reverse: "..round(rad).." rad = "..round(math.deg(rad)).."\xC2\xB0")
    return r
  end
}

tools["conv_dms"] = {
  inputs = {{"Degrees=", ""}},
  compute = function(v)
    local d = tonumber(v[1])
    local r = {}
    if not d then table.insert(r, "Enter decimal degrees") return r end
    local deg = math.floor(d)
    local minF = (d - deg) * 60
    local min = math.floor(minF)
    local sec = round((minF - min) * 60, 2)
    table.insert(r, d.."\xC2\xB0 = "..deg.."\xC2\xB0 "..min.."' "..sec.."\"")
    return r
  end
}

tools["conv_rev"] = {
  inputs = {{"Revolutions=", ""}},
  compute = function(v)
    local rev = tonumber(v[1])
    local r = {}
    if not rev then table.insert(r, "Enter revolutions") return r end
    table.insert(r, rev.." rev = "..round(rev*360).."\xC2\xB0")
    table.insert(r, "= "..round(rev*2*math.pi).." rad")
    return r
  end
}

-- SAT SPECIALS
tools["sat_sigma"] = {
  inputs = {{"f(n)=", ""}, {"from n=", ""}, {"to n=", ""}},
  compute = function(v)
    local r = {}
    local expr = v[1]
    local a,b = tonumber(v[2]),tonumber(v[3])
    if not (a and b) then table.insert(r, "Enter range") return r end
    table.insert(r, "\xCE\xA3 "..expr.." from n="..a.." to "..b)
    table.insert(r, "")
    local sum = 0
    for i = a, b do
      local val = safeEvalNum(expr.."|n="..i)
      if val then sum = sum + val end
    end
    table.insert(r, "= "..round(sum))
    return r
  end
}

tools["sat_count"] = {
  inputs = {{"Low=", ""}, {"High=", ""}, {"N (step)=", ""}},
  compute = function(v)
    local lo,hi,n = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (lo and hi) then table.insert(r, "Enter range") return r end
    n = n or 1
    local count = math.floor((hi-lo)/n) + 1
    table.insert(r, "Integers from "..lo.." to "..hi)
    if n > 1 then table.insert(r, "stepping by "..n) end
    table.insert(r, "Count = "..count)
    return r
  end
}

tools["sat_div"] = {
  inputs = {{"Low=", ""}, {"High=", ""}, {"N=", ""}, {"M=", ""}},
  compute = function(v)
    local lo,hi,n,m = tonumber(v[1]),tonumber(v[2]),tonumber(v[3]),tonumber(v[4])
    local r = {}
    if not (lo and hi and n) then table.insert(r, "Enter range and N") return r end
    local cntN = math.floor(hi/n) - math.floor((lo-1)/n)
    table.insert(r, "Divisible by "..n..": "..cntN)
    if m then
      local cntM = math.floor(hi/m) - math.floor((lo-1)/m)
      local l = lcm(n,m)
      local cntBoth = math.floor(hi/l) - math.floor((lo-1)/l)
      local cntEither = cntN + cntM - cntBoth
      table.insert(r, "Divisible by "..m..": "..cntM)
      table.insert(r, "Divisible by both: "..cntBoth)
      table.insert(r, "Divisible by either: "..cntEither)
    end
    return r
  end
}

tools["sat_2var"] = {
  inputs = {{"Equation=", ""}, {"x range=", ""}, {"y range=", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "Equation: "..v[1])
    table.insert(r, "Solve with CAS:")
    local sol = safeEval("solve("..v[1]..",{x,y})")
    if sol then table.insert(r, sol)
    else table.insert(r, "Use CAS directly for best results") end
    return r
  end
}

tools["sat_3var"] = {
  inputs = {{"Equation=", ""}},
  compute = function(v)
    local r = {}
    table.insert(r, "Equation: "..v[1])
    local sol = safeEval("solve("..v[1]..",{x,y,z})")
    if sol then table.insert(r, sol)
    else table.insert(r, "Use CAS directly for best results") end
    return r
  end
}

---------------------------------------------------------------
-- READ CONTENT (Reference Cards)
---------------------------------------------------------------
local reads = {}

reads["alg_pemdas"] = {
  "PEMDAS - Order of Operations",
  "",
  "P - Parentheses first",
  "E - Exponents (powers, roots)",
  "M - Multiplication (left to right)",
  "D - Division (left to right)",
  "A - Addition (left to right)",
  "S - Subtraction (left to right)",
  "",
  "Note: M/D have equal priority",
  "Note: A/S have equal priority",
  "Work left to right within",
  "  same priority level.",
}

reads["fn_def"] = {
  "Definition of a Function",
  "",
  "A function f: A -> B assigns",
  "each element of A to exactly",
  "one element of B.",
  "",
  "Vertical Line Test:",
  "A graph is a function if every",
  "vertical line crosses it at",
  "most once.",
  "",
  "Domain: set of valid inputs",
  "Range: set of all outputs",
}

reads["fn_interval"] = {
  "Interval Notation",
  "",
  "(a,b) = {x: a < x < b}   open",
  "[a,b] = {x: a \xE2\x89\xA4 x \xE2\x89\xA4 b}  closed",
  "[a,b) = {x: a \xE2\x89\xA4 x < b}  half-open",
  "(a,b] = {x: a < x \xE2\x89\xA4 b}  half-open",
  "",
  "(-\xE2\x88\x9E, a) = {x: x < a}",
  "(a, \xE2\x88\x9E) = {x: x > a}",
  "(-\xE2\x88\x9E, \xE2\x88\x9E) = all reals",
  "",
  "\xE2\x88\x9E always uses ( not [",
}

reads["pt_directvar"] = {
  "Direct Variation: y = kx",
  "",
  "y varies directly with x",
  "k = constant of variation",
  "k = y/x (the ratio is constant)",
  "",
  "Graph: line through origin",
  "Slope = k",
}

reads["pt_linearfn"] = {
  "Linear Functions",
  "",
  "Slope-Intercept: y = mx + b",
  "  m = slope, b = y-intercept",
  "",
  "Point-Slope: y-y1 = m(x-x1)",
  "",
  "Standard: Ax + By = C",
  "",
  "Slope = rise/run = \xCE\x94y/\xCE\x94x",
  "Parallel lines: same slope",
  "Perpendicular: m1\xC2\xB7m2 = -1",
}

reads["pt_absval"] = {
  "Absolute Value Function",
  "",
  "|x| = x  if x \xE2\x89\xA5 0",
  "|x| = -x if x < 0",
  "",
  "y = |x| is V-shaped",
  "Vertex at origin",
  "",
  "y = a|x-h| + k",
  "  Vertex at (h, k)",
  "  a > 0: opens up",
  "  a < 0: opens down",
}

reads["exp_rules"] = {
  "Exponent Rules",
  "",
  "x^a \xC2\xB7 x^b = x^(a+b)",
  "x^a / x^b = x^(a-b)",
  "(x^a)^b = x^(a\xC2\xB7b)",
  "(xy)^a = x^a \xC2\xB7 y^a",
  "x^0 = 1",
  "x^(-a) = 1/x^a",
  "x^(1/n) = n-th root of x",
}

reads["log_rules"] = {
  "Logarithm Rules",
  "",
  "log_b(xy) = log_b(x)+log_b(y)",
  "log_b(x/y) = log_b(x)-log_b(y)",
  "log_b(x^n) = n\xC2\xB7log_b(x)",
  "log_b(1) = 0",
  "log_b(b) = 1",
  "",
  "Change of Base:",
  "log_b(x) = ln(x)/ln(b)",
  "",
  "b^(log_b(x)) = x",
}

reads["circ_unit"] = {
  "Unit Circle: Key Angles",
  "",
  "0\xC2\xB0: (1, 0)",
  "30\xC2\xB0: (\xE2\x88\x9A3/2, 1/2)",
  "45\xC2\xB0: (\xE2\x88\x9A2/2, \xE2\x88\x9A2/2)",
  "60\xC2\xB0: (1/2, \xE2\x88\x9A3/2)",
  "90\xC2\xB0: (0, 1)",
  "120\xC2\xB0: (-1/2, \xE2\x88\x9A3/2)",
  "135\xC2\xB0: (-\xE2\x88\x9A2/2, \xE2\x88\x9A2/2)",
  "150\xC2\xB0: (-\xE2\x88\x9A3/2, 1/2)",
  "180\xC2\xB0: (-1, 0)",
  "270\xC2\xB0: (0, -1)",
  "360\xC2\xB0: (1, 0)",
}

reads["circ_props"] = {
  "Circle Properties & Formulas",
  "",
  "Area = \xCF\x80r\xC2\xB2",
  "Circumference = 2\xCF\x80r = \xCF\x80d",
  "Diameter = 2r",
  "",
  "Arc Length = r\xCE\xB8 (\xCE\xB8 in rad)",
  "Sector Area = \xC2\xBDr\xC2\xB2\xCE\xB8",
  "",
  "Equation: (x-h)\xC2\xB2+(y-k)\xC2\xB2=r\xC2\xB2",
  "Center: (h, k)",
}

reads["trig_intro"] = {
  "Trigonometry Introduction",
  "",
  "SOH-CAH-TOA",
  "sin = Opposite/Hypotenuse",
  "cos = Adjacent/Hypotenuse",
  "tan = Opposite/Adjacent",
  "",
  "Reciprocals:",
  "csc = 1/sin, sec = 1/cos",
  "cot = 1/tan",
  "",
  "sin\xC2\xB2+cos\xC2\xB2 = 1",
}

reads["trig_laws"] = {
  "Three Laws of Trigonometry",
  "",
  "Law of Sines:",
  "a/sinA = b/sinB = c/sinC",
  "",
  "Law of Cosines:",
  "c\xC2\xB2 = a\xC2\xB2+b\xC2\xB2-2ab\xC2\xB7cos(C)",
  "",
  "Area = \xC2\xBDab\xC2\xB7sin(C)",
  "",
  "Use Sines for: SAA, SSA",
  "Use Cosines for: SAS, SSS",
}

---------------------------------------------------------------
-- RENDERING ENGINE
---------------------------------------------------------------
function on.resize(w, h) W, H = w, h end

function on.paint(gc)
  gc:setColorRGB(255, 255, 255)
  gc:fillRect(0, 0, W, H)
  gc:setColorRGB(0, 0, 0)

  if state == "menu" then drawMenu(gc)
  elseif state == "submenu" then drawSubmenu(gc)
  elseif state == "tool" then drawTool(gc)
  elseif state == "read" then drawRead(gc)
  end
end

function drawMenu(gc)
  gc:setFont("sansserif", "b", 11)
  gc:drawString("ACT/SAT Calculator", 5, 0)
  gc:setFont("sansserif", "r", 10)
  local y = 20
  local vis = math.min(#menus, math.floor((H-25)/16))
  local top = math.max(1, menuSel - vis + 1)
  for i = top, math.min(#menus, top + vis - 1) do
    if i == menuSel then
      gc:setColorRGB(0, 0, 180)
      gc:fillRect(0, y, W, 16)
      gc:setColorRGB(255, 255, 255)
    else
      gc:setColorRGB(0, 0, 0)
    end
    gc:drawString((i)..". "..menus[i].name, 5, y)
    y = y + 16
  end
  gc:setColorRGB(0, 0, 0)
end

function drawSubmenu(gc)
  local menu = menus[menuSel]
  gc:setFont("sansserif", "b", 11)
  gc:drawString(menu.name, 5, 0)
  gc:setFont("sansserif", "r", 10)
  local y = 20
  local items = menu.items
  local vis = math.min(#items, math.floor((H-25)/16))
  local top = math.max(1, subSel - vis + 1)
  for i = top, math.min(#items, top + vis - 1) do
    if i == subSel then
      gc:setColorRGB(0, 0, 180)
      gc:fillRect(0, y, W, 16)
      gc:setColorRGB(255, 255, 255)
    else
      gc:setColorRGB(0, 0, 0)
    end
    gc:drawString(items[i].name, 5, y)
    y = y + 16
  end
  gc:setColorRGB(0, 0, 0)
end

function drawTool(gc)
  local tool = tools[currentTool]
  if not tool then return end
  gc:setFont("sansserif", "r", 10)
  local y = 2
  -- Draw input fields
  for i, inp in ipairs(tool.inputs) do
    local label = inp[1]
    gc:setColorRGB(0, 0, 0)
    gc:drawString(label, 5, y)
    local lw = gc:getStringWidth(label) + 8
    -- Input box
    if i == inputSel then
      gc:setColorRGB(200, 220, 255)
      gc:fillRect(lw, y, W - lw - 5, 16)
      gc:setColorRGB(0, 0, 180)
    else
      gc:setColorRGB(240, 240, 240)
      gc:fillRect(lw, y, W - lw - 5, 16)
      gc:setColorRGB(0, 0, 0)
    end
    gc:drawRect(lw, y, W - lw - 5, 16)
    gc:setColorRGB(0, 0, 0)
    gc:drawString(inputVals[i] or "", lw + 2, y)
    y = y + 20
  end
  -- Draw results
  if #results > 0 then
    y = y + 4
    gc:setColorRGB(0, 0, 0)
    for _, line in ipairs(results) do
      if y > H then break end
      gc:drawString(line, 5, y - scrollY)
      y = y + 15
    end
  end
end

function drawRead(gc)
  local content = reads[currentTool]
  if not content then return end
  gc:setFont("sansserif", "r", 10)
  local y = 2
  for _, line in ipairs(content) do
    if y - scrollY > -15 and y - scrollY < H then
      if _ == 1 then
        gc:setFont("sansserif", "b", 11)
        gc:drawString(line, 5, y - scrollY)
        gc:setFont("sansserif", "r", 10)
      else
        gc:drawString(line, 5, y - scrollY)
      end
    end
    y = y + 15
  end
end

---------------------------------------------------------------
-- INPUT HANDLING
---------------------------------------------------------------
function on.arrowKey(key)
  if state == "menu" then
    if key == "up" then menuSel = math.max(1, menuSel - 1)
    elseif key == "down" then menuSel = math.min(#menus, menuSel + 1) end
  elseif state == "submenu" then
    if key == "up" then subSel = math.max(1, subSel - 1)
    elseif key == "down" then subSel = math.min(#menus[menuSel].items, subSel + 1) end
  elseif state == "tool" then
    local tool = tools[currentTool]
    if tool then
      if key == "up" then inputSel = math.max(1, inputSel - 1)
      elseif key == "down" then
        inputSel = math.min(#tool.inputs, inputSel + 1)
      end
    end
  elseif state == "read" then
    if key == "down" then scrollY = scrollY + 15
    elseif key == "up" then scrollY = math.max(0, scrollY - 15) end
  end
  platform.window:invalidate()
end

function on.enterKey()
  if state == "menu" then
    state = "submenu"
    subSel = 1
  elseif state == "submenu" then
    local item = menus[menuSel].items[subSel]
    currentTool = item.id
    if item.type == "read" then
      state = "read"
      scrollY = 0
    elseif item.type == "tool" then
      state = "tool"
      local tool = tools[currentTool]
      if tool then
        inputVals = {}
        for i, inp in ipairs(tool.inputs) do inputVals[i] = inp[2] end
        inputSel = 1
        results = {}
        scrollY = 0
      end
    end
  elseif state == "tool" then
    -- Compute results
    local tool = tools[currentTool]
    if tool then
      local vals = {}
      for i = 1, #tool.inputs do vals[i] = inputVals[i] or "" end
      local ok, res = pcall(tool.compute, vals)
      if ok and res then results = res else results = {"Error computing"} end
    end
  end
  platform.window:invalidate()
end

function on.escapeKey()
  if state == "submenu" then state = "menu"
  elseif state == "tool" or state == "read" then
    state = "submenu"
    results = {}
    scrollY = 0
  end
  platform.window:invalidate()
end

function on.tabKey()
  if state == "tool" then
    local tool = tools[currentTool]
    if tool then
      inputSel = inputSel + 1
      if inputSel > #tool.inputs then inputSel = 1 end
    end
  end
  platform.window:invalidate()
end

function on.charIn(ch)
  if state == "tool" then
    inputVals[inputSel] = (inputVals[inputSel] or "") .. ch
    platform.window:invalidate()
  end
end

function on.backspaceKey()
  if state == "tool" then
    local s = inputVals[inputSel] or ""
    if #s > 0 then inputVals[inputSel] = s:sub(1, -2) end
    platform.window:invalidate()
  end
end

