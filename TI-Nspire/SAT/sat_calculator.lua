---------------------------------------------------------------
-- SAT Calculator Program for TI-Nspire
-- Comprehensive Math Toolkit — IvyTutoring.net
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
if not toolpalette then
  toolpalette = {register = function() end}
end

platform.apilevel = '2.7'

---------------------------------------------------------------
-- GLOBAL STATE
---------------------------------------------------------------
local W, H = 318, 212
local state = "splash"      -- splash, tool, read
local inputSel = 1
local scrollY = 0
local inputVals = {}
local results = {}
local currentTool = nil
local currentToolName = ""
local resultScrollMode = false
local mathEditor = nil       -- D2Editor for pretty math display

---------------------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------------------
local function round(x, n)
  n = n or 3
  local m = 10^n
  return math.floor(x * m + 0.5) / m
end

-- Preprocess user input: insert * for implicit multiplication
-- Only applied to USER input, never to full CAS expressions
local function prepareInput(s)
  if not s or s == "" then return s end
  -- 2x -> 2*x (digit before letter)
  s = s:gsub("(%d)([a-zA-Z])", "%1*%2")
  -- )2 or )x -> )*2 or )*x
  s = s:gsub("(%))([a-zA-Z%d])", "%1*%2")
  return s
end

local function safeEval(expr)
  local ok, val = pcall(function() return math.eval(expr) end)
  if ok and val then
    -- Handle table/list results (e.g. from linSolve)
    if type(val) == "table" then
      local parts = {}
      for i, v in ipairs(val) do
        parts[i] = tostring(v)
      end
      if #parts > 0 then return table.concat(parts, ", ") end
      return nil
    end
    return tostring(val)
  end
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
  return table.concat(parts, " x ")
end

-- Unicode math symbols via string.char (generates UTF-8 bytes at runtime)
local SUP = {}
SUP["0"] = string.char(226, 129, 176)   -- ⁰
SUP["1"] = string.char(194, 185)         -- ¹
SUP["2"] = string.char(194, 178)         -- ²
SUP["3"] = string.char(194, 179)         -- ³
SUP["4"] = string.char(226, 129, 180)   -- ⁴
SUP["5"] = string.char(226, 129, 181)   -- ⁵
SUP["6"] = string.char(226, 129, 182)   -- ⁶
SUP["7"] = string.char(226, 129, 183)   -- ⁷
SUP["8"] = string.char(226, 129, 184)   -- ⁸
SUP["9"] = string.char(226, 129, 185)   -- ⁹
SUP["-"] = string.char(226, 129, 187)   -- ⁻

local DEG  = string.char(194, 176)       -- °
local MUL  = string.char(194, 183)       -- ·
local PI   = string.char(207, 128)       -- π
local THETA = string.char(206, 184)      -- θ
local SQRT = string.char(226, 136, 154)  -- √
local APPROX = string.char(226, 137, 136) -- ≈
local TIMES = string.char(195, 151)      -- ×

-- Convert a number/letter string to superscript
local function toSuperscript(numStr)
  local result = ""
  for i = 1, #numStr do
    local ch = numStr:sub(i, i)
    result = result .. (SUP[ch] or ch)
  end
  return result
end

-- Prettify CAS output for display
local function prettifyMath(s)
  if not s then return s end
  -- Convert ^N (any number of digits, optionally negative) to superscript
  s = s:gsub("%^(%-?%d+)", function(exp) return toSuperscript(exp) end)
  -- Convert ^(single letter) to superscript: x^a -> xᵃ (keep ^ for multi-char)
  s = s:gsub("%^(%a)([^%a%(])", function(letter, after)
    return toSuperscript(letter) .. after
  end)
  s = s:gsub("%^(%a)$", function(letter)
    return toSuperscript(letter)
  end)
  -- Replace * with middle dot in all multiplication contexts
  s = s:gsub(" %* ", " "..MUL.." ")
  s = s:gsub("(%d)%*([%a%(])", "%1"..MUL.."%2")
  s = s:gsub("(%a)%*([%a%(])", "%1"..MUL.."%2")
  s = s:gsub("%)%*([%a%(])", ")"..MUL.."%1")
  -- Named constants
  s = s:gsub("pi", PI)
  s = s:gsub("theta", THETA)
  s = s:gsub("sigma", string.char(207, 131)) -- σ
  s = s:gsub("delta", string.char(206, 148)) -- Δ
  s = s:gsub("sqrt", SQRT)
  s = s:gsub("inf", string.char(226, 136, 158)) -- ∞
  s = s:gsub("<=", string.char(226, 137, 164)) -- ≤
  s = s:gsub(">=", string.char(226, 137, 165)) -- ≥
  s = s:gsub(" deg", DEG)
  s = s:gsub("~=", APPROX)
  return s
end

-- Wrap text to fit screen width
local function wrapText(gc, text, maxW)
  local lines = {}
  if not text or text == "" then return {""} end
  local w = gc:getStringWidth(text)
  if w <= maxW then return {text} end
  -- Word-wrap
  local line = ""
  for word in text:gmatch("%S+") do
    local test = (line == "") and word or (line .. " " .. word)
    if gc:getStringWidth(test) > maxW then
      if line ~= "" then table.insert(lines, line) end
      line = "  " .. word  -- indent continuation
    else
      line = test
    end
  end
  if line ~= "" then table.insert(lines, line) end
  return lines
end

-- Wrap a list of items across multiple result lines
local function wrapList(r, prefix, items, maxW)
  maxW = maxW or 35
  local line = prefix
  for i, item in ipairs(items) do
    local sep = (i == 1) and "" or ", "
    if #line + #sep + #tostring(item) > maxW then
      table.insert(r, line .. ",")
      line = "  " .. tostring(item)
    else
      line = line .. sep .. tostring(item)
    end
  end
  table.insert(r, line)
end

---------------------------------------------------------------
-- TOOL/READ SELECTION HANDLERS (global for toolpalette access)
---------------------------------------------------------------
function selectTool(id, name)
  currentTool = id
  currentToolName = name
  state = "tool"
  -- Hide math editor from previous tool
  if mathEditor then pcall(function() mathEditor:setVisible(false) end) end
  local tool = tools[id]
  if tool then
    inputVals = {}
    for i, inp in ipairs(tool.inputs) do inputVals[i] = inp[2] end
    inputSel = 1
    results = {}
    scrollY = 0
    resultScrollMode = false
  end
  platform.window:invalidate()
end

function selectRead(id, name)
  currentTool = id
  currentToolName = name
  state = "read"
  scrollY = 0
  if mathEditor then pcall(function() mathEditor:setVisible(false) end) end
  platform.window:invalidate()
end

function goHome()
  state = "splash"
  results = {}
  scrollY = 0
  if mathEditor then pcall(function() mathEditor:setVisible(false) end) end
  resultScrollMode = false
  platform.window:invalidate()
end

---------------------------------------------------------------
-- NATIVE TOOLPALETTE MENU
---------------------------------------------------------------
local menu = {
  {"Algebra",
    {"Solve any Equation", function() selectTool("alg_solve", "Solve Equation") end},
    {"Solve 2x2 System", function() selectTool("alg_2x2", "2x2 System") end},
    {"Solve 3x3 System", function() selectTool("alg_3x3", "3x3 System") end},
    {"Linear Inequality", function() selectTool("alg_ineq", "Inequality") end},
    {"Simplify & Evaluate", function() selectTool("alg_simplify", "Simplify") end},
    {"Find y=mx+b", function() selectTool("pt_ymxb", "y=mx+b") end},
    {"Find Slope", function() selectTool("pt_slope", "Slope") end},
    {"Point-Slope Form", function() selectTool("pt_ptslope", "Point-Slope") end},
    {"Parallel or Perp?", function() selectTool("pt_parperp", "Par/Perp") end},
    {"Find Par/Perp Lines", function() selectTool("pt_findparperp", "Find Par/Perp") end},
    {"Read: PEMDAS", function() selectRead("alg_pemdas", "PEMDAS") end},
    {"Read: y=kx", function() selectRead("pt_directvar", "Direct Variation") end},
    {"Read: Linear Functions", function() selectRead("pt_linearfn", "Linear Functions") end},
    {"Read: Absolute Value", function() selectRead("pt_absval", "|x|") end},
    {"Read: Intervals", function() selectRead("fn_interval", "Intervals") end},
  },
  {"Advanced Math",
    {"Quadratic Equation", function() selectTool("quad_formula", "Quadratic") end},
    {"Complete the Square", function() selectTool("quad_complete", "Complete Sq") end},
    {"Complete Sq -> Zeros", function() selectTool("quad_zeros", "Find Zeros") end},
    {"Complete Sq -> Vertex", function() selectTool("quad_vertex", "Find Vertex") end},
    {"Polynomial Explorer", function() selectTool("poly_explore", "Poly Explorer") end},
    {"Find Degree", function() selectTool("poly_degree", "Degree") end},
    {"Rational Expression", function() selectTool("adv_rational", "Rational") end},
    {"Radical Simplifier", function() selectTool("adv_radical", "Radical") end},
    {"Factor Integers", function() selectTool("alg_factor", "Factor") end},
    {"Powers", function() selectTool("alg_powers", "Powers") end},
    {"GCD & LCM", function() selectTool("alg_gcdlcm", "GCD & LCM") end},
    {"Read: Exponent Rules", function() selectRead("exp_rules", "Exp Rules") end},
    {"Solve Exp/Log Eqn", function() selectTool("exp_solve", "Solve") end},
    {"Rule of 72", function() selectTool("exp_rule72", "Rule 72") end},
    {"Exponential Growth", function() selectTool("exp_growth", "Growth") end},
    {"Read: Log Rules", function() selectRead("log_rules", "Log Rules") end},
    {"Evaluate Logarithm", function() selectTool("log_eval", "Evaluate Log") end},
    {"Change of Base", function() selectTool("log_cob", "Change Base") end},
  },
  {"Functions",
    {"Read: Definition", function() selectRead("fn_def", "Functions") end},
    {"Function Explorer", function() selectTool("fn_explore", "f(x) Explorer") end},
    {"Evaluate Function", function() selectTool("fn_eval", "Evaluate f(x)") end},
    {"Intersection of 2", function() selectTool("fn_intersect", "Intersection") end},
    {"Find f+g, f-g, fg, f/g", function() selectTool("fn_add", "f+g") end},
    {"Composition f(g(x))", function() selectTool("fn_compose", "f(g(x))") end},
    {"Difference Quotient", function() selectTool("fn_diffquot", "[f(x+h)-f(x)]/h") end},
    {"1 Complex Number", function() selectTool("cx_one", "Complex z") end},
    {"2 Complex Numbers", function() selectTool("cx_two", "z1 & z2") end},
  },
  {"Problem Solving & Data",
    {"Solve Proportion", function() selectTool("alg_proportion", "Proportion") end},
    {"Percent Change", function() selectTool("alg_pctchange", "% Change") end},
    {"Mean, Median, Mode", function() selectTool("stat_central", "Mean/Med/Mode") end},
    {"Standard Deviation", function() selectTool("stat_stdev", "Std Dev") end},
    {"Five-Number Summary", function() selectTool("stat_5num", "5-Num Summary") end},
    {"Linear Regression", function() selectTool("stat_linreg", "Lin Regression") end},
    {"Two-Way Table", function() selectTool("stat_twoway", "Two-Way Table") end},
    {"Margin of Error", function() selectTool("stat_moe", "Margin of Error") end},
    {"Basic Probability", function() selectTool("prob_basic", "Probability") end},
    {"nCr Combinations", function() selectTool("prob_ncr", "nCr") end},
    {"nPr Permutations", function() selectTool("prob_npr", "nPr") end},
  },
  {"Geometry & Trig",
    {"Circle", function() selectTool("geo_circle", "Circle") end},
    {"Circle Equation", function() selectTool("geo_circleq", "Circle Eqn") end},
    {"Read: Circle Props", function() selectRead("circ_props", "Circle Props") end},
    {"Pythagorean Theorem", function() selectTool("geo_pyth", "Pythagorean") end},
    {"Triangle", function() selectTool("geo_tri", "Triangle") end},
    {"Read: Special Right Tri", function() selectRead("geo_special_rt", "Special Tri") end},
    {"Square", function() selectTool("geo_square", "Square") end},
    {"Rectangle", function() selectTool("geo_rect", "Rectangle") end},
    {"Parallelogram", function() selectTool("geo_para", "Parallelogram") end},
    {"Trapezoid", function() selectTool("geo_trap", "Trapezoid") end},
    {"Sphere", function() selectTool("geo_sphere", "Sphere") end},
    {"Cube", function() selectTool("geo_cube", "Cube") end},
    {"Cylinder", function() selectTool("geo_cyl", "Cylinder") end},
    {"Cone", function() selectTool("geo_cone", "Cone") end},
    {"Pyramid", function() selectTool("geo_pyramid", "Pyramid") end},
    {"Rectangular Prism", function() selectTool("geo_rprism", "Rect Prism") end},
    {"Sector", function() selectTool("geo_sector", "Sector") end},
    {"Arc Length", function() selectTool("geo_arc", "Arc Length") end},
    {"Distance Formula", function() selectTool("pt_distance", "Distance") end},
    {"Midpoint Formula", function() selectTool("pt_midpoint", "Midpoint") end},
    {"Read: SOH-CAH-TOA", function() selectRead("trig_intro", "Trig Intro") end},
    {"Solve Right Triangle", function() selectTool("trig_right", "Right Tri") end},
    {"Evaluate sin/cos/tan", function() selectTool("trig_sinx", "sin/cos/tan") end},
    {"Degree <-> Radian", function() selectTool("conv_degrad", "Deg/Rad") end},
    {"Read: Unit Circle", function() selectRead("circ_unit", "Unit Circle") end},
  },
  {"SAT Specials",
    {"Sigma Notation", function() selectTool("sat_sigma", "Sigma") end},
    {"Count Integers", function() selectTool("sat_count", "Count Int") end},
    {"Count Divisible", function() selectTool("sat_div", "Divisible") end},
    {"Int Soln: 2 Vars", function() selectTool("sat_2var", "2 Vars") end},
    {"Int Soln: 3 Vars", function() selectTool("sat_3var", "3 Vars") end},
    {"Read: SAT Formulas", function() selectRead("sat_formulas", "SAT Formulas") end},
  },
}
toolpalette.register(menu)

---------------------------------------------------------------
-- TOOL DEFINITIONS (inputs and compute functions)
---------------------------------------------------------------
tools = {}

-- ALGEBRA TOOLS
tools["alg_solve"] = {
  inputs = {{"Equation=", "", "e.g. 2x+3=7"}},
  compute = function(v)
    local eq = v[1]
    if eq == "" then return {} end
    local r = {}

    -- Parse LHS and RHS
    local lhs, rhs = eq:match("^(.-)=(.+)$")
    if not lhs or not rhs then
      table.insert(r, "Enter equation with = sign")
      return r
    end

    table.insert(r, "--- Solve for x ---")
    table.insert(r, "")
    table.insert(r, "Given: "..eq)
    table.insert(r, "")

    -- Step 1: Rearrange to standard form
    local rearranged = safeEval("expand(("..lhs..")-("..rhs.."))")
    if rearranged then
      table.insert(r, "Step 1: Rearrange")
      table.insert(r, rearranged.." = 0")
      table.insert(r, "")
    end

    -- Step 2: Factor if possible
    if rearranged then
      local factored = safeEval("factor("..rearranged..")")
      if factored and factored ~= rearranged then
        table.insert(r, "Step 2: Factor")
        table.insert(r, factored.." = 0")
        table.insert(r, "")
      end
    end

    -- Step 3: Solve - exact
    local sol = safeEval("solve("..eq..",x)")
    if not sol then sol = safeEval("nSolve("..eq..",x)") end

    if sol then
      table.insert(r, "--- Solution ---")
      table.insert(r, "")
      table.insert(r, "Exact: "..sol)

      -- Decimal approximation
      local approxSol = safeEval("approx(solve("..eq..",x))")
      if approxSol and approxSol ~= sol then
        table.insert(r, "Decimal: "..approxSol)
      end

      table.insert(r, "")

      -- Step 4: Verify by substitution
      -- Try to extract x value for verification
      local xval = sol:match("x=(.-) or") or sol:match("x=(.+)$") or sol:match("x=(.+)")
      if xval then
        table.insert(r, "--- Verify ---")
        local lhs_val = safeEval("("..lhs..")|x=("..xval..")")
        local rhs_val = safeEval("("..rhs..")|x=("..xval..")")
        if lhs_val and rhs_val then
          table.insert(r, "Plug x="..xval.." back in:")
          table.insert(r, "LHS = "..lhs_val)
          table.insert(r, "RHS = "..rhs_val)
          if lhs_val == rhs_val then
            table.insert(r, "LHS = RHS  (Verified!)")
          end
        end
      end
    else
      table.insert(r, "No solution found")
    end
    return r
  end
}

tools["alg_2x2"] = {
  inputs = {{"1.Eqn ", "", "e.g. x+y=5"}, {"2.Eqn ", "", "e.g. 2x-y=1"}},
  compute = function(v)
    local r = {}
    local e1, e2 = v[1], v[2]
    if e1 == "" or e2 == "" then return r end
    table.insert(r, "--- 2x2 System ---")
    table.insert(r, "")
    table.insert(r, "(1)  "..e1)
    table.insert(r, "(2)  "..e2)
    table.insert(r, "")

    -- Try multiple CAS approaches
    local sol = safeEval("linSolve({"..e1..","..e2.."},{x,y})")
    if not sol then sol = safeEval("solve("..e1.." and "..e2..", {x,y})") end
    if not sol then sol = safeEval("solve({"..e1..","..e2.."},{x,y})") end

    -- Try solving by substitution
    local xSol = safeEval("solve("..e1..",x)")
    local ySol = nil
    if xSol then
      table.insert(r, "--- Substitution ---")
      table.insert(r, "From (1): "..xSol)
      ySol = safeEval("solve("..e2.."|"..xSol..",y)")
      if ySol then
        table.insert(r, "Sub into (2): "..ySol)
        local xFinal = safeEval(xSol.."|"..ySol)
        if xFinal then
          table.insert(r, "Back-sub: "..xFinal)
          if not sol then sol = xFinal.." and "..ySol end
        end
      end
      table.insert(r, "")
    end

    if sol then
      table.insert(r, "--- Solution ---")
      table.insert(r, "")
      table.insert(r, sol)

      -- Get individual x and y values
      local xv = safeEval("solve("..e1.." and "..e2..",x)")
      local yv = safeEval("solve("..e1.." and "..e2..",y)")
      if xv and yv then
        local xn = safeEval("approx("..xv..")")
        local yn = safeEval("approx("..yv..")")
        if xn or yn then
          table.insert(r, "")
          if xn then table.insert(r, "x "..APPROX.." "..xn) end
          if yn then table.insert(r, "y "..APPROX.." "..yn) end
        end
      end

      -- Verify
      table.insert(r, "")
      table.insert(r, "--- Verify ---")
      local check1 = safeEval("("..e1..")|solve("..e1.." and "..e2..",{x,y})")
      local check2 = safeEval("("..e2..")|solve("..e1.." and "..e2..",{x,y})")
      if check1 then table.insert(r, "(1): "..check1) end
      if check2 then table.insert(r, "(2): "..check2) end
    else
      table.insert(r, "No solution found")
    end
    return r
  end
}

tools["alg_3x3"] = {
  inputs = {{"1.Eqn ", "", "e.g. x+y+z=6"}, {"2.Eqn ", "", "e.g. 2x-y=1"}, {"3.Eqn ", "", "e.g. y+z=5"}},
  compute = function(v)
    local r = {}
    if v[1] == "" or v[2] == "" or v[3] == "" then return r end
    table.insert(r, "--- 3x3 System ---")
    table.insert(r, "")
    table.insert(r, "(1)  "..v[1])
    table.insert(r, "(2)  "..v[2])
    table.insert(r, "(3)  "..v[3])
    table.insert(r, "")

    local sol = safeEval("linSolve({"..v[1]..","..v[2]..","..v[3].."},{x,y,z})")
    if not sol then sol = safeEval("solve("..v[1].." and "..v[2].." and "..v[3]..", {x,y,z})") end
    if not sol then sol = safeEval("solve({"..v[1]..","..v[2]..","..v[3].."},{x,y,z})") end

    if sol then
      table.insert(r, "--- Solution ---")
      table.insert(r, "")
      table.insert(r, sol)
      table.insert(r, "")

      -- Get individual values
      local xv = safeEval("solve("..v[1].." and "..v[2].." and "..v[3]..",x)")
      local yv = safeEval("solve("..v[1].." and "..v[2].." and "..v[3]..",y)")
      local zv = safeEval("solve("..v[1].." and "..v[2].." and "..v[3]..",z)")
      if xv then table.insert(r, xv) end
      if yv then table.insert(r, yv) end
      if zv then table.insert(r, zv) end
    else table.insert(r, "No solution found") end
    return r
  end
}

tools["alg_simplify"] = {
  inputs = {{"Expr=", "", "e.g. (x+1)^2"}},
  compute = function(v)
    local r = {}
    local expr = v[1]
    if expr == "" then return r end
    table.insert(r, "--- Simplify/Evaluate ---")
    table.insert(r, "")
    table.insert(r, "Input: "..expr)
    table.insert(r, "")

    -- Try expand
    local s = safeEval("expand("..expr..")")
    if s and s ~= expr then table.insert(r, "Expanded: "..s) end
    -- Try factor
    s = safeEval("factor("..expr..")")
    if s and s ~= expr then table.insert(r, "Factored: "..s) end
    -- Try simplify
    s = safeEval("simplify("..expr..")")
    if s then table.insert(r, "Simplified: "..s) end
    table.insert(r, "")
    -- Try direct evaluation (numeric)
    s = safeEval(expr)
    if s then table.insert(r, "Exact = "..s) end
    -- Try approximate numeric value
    s = safeEval("approx("..expr..")")
    if s then table.insert(r, "Decimal "..APPROX.." "..s) end

    -- Derivative and integral if it contains x
    local d = safeEval("d("..expr..",x)")
    if d then
      table.insert(r, "")
      table.insert(r, "d/dx = "..d)
    end
    local intg = safeEval("integral("..expr..",x)")
    if intg then table.insert(r, "integral = "..intg.." + C") end

    if #r <= 3 then table.insert(r, "Could not simplify") end
    return r
  end
}

tools["alg_factor"] = {
  inputs = {{"Integer=", "", "e.g. 360"}},
  compute = function(v)
    local n = tonumber(v[1])
    local r = {}
    if not n or n ~= math.floor(n) then
      table.insert(r, "Please enter an integer")
      return r
    end
    n = math.abs(n)
    table.insert(r, "--- Prime Factorization ---")
    table.insert(r, "")
    table.insert(r, n.." = "..factorStr(n))
    table.insert(r, "")

    -- List all divisors
    local divs = {}
    for i = 1, n do if n % i == 0 then table.insert(divs, i) end end

    -- Show divisor pairs
    table.insert(r, "--- Divisor Pairs ---")
    local half = math.ceil(#divs / 2)
    for i = 1, half do
      local d1 = divs[i]
      local d2 = n / d1
      if d1 == d2 then
        table.insert(r, d1.." x "..d2)
      else
        table.insert(r, d1.." x "..d2)
      end
    end
    table.insert(r, "")

    wrapList(r, "All ("..#divs.."): ", divs, 30)
    table.insert(r, "")

    -- Is it prime?
    if #divs == 2 then
      table.insert(r, n.." is PRIME")
    elseif #divs == 1 then
      table.insert(r, n.." is a unit")
    else
      table.insert(r, n.." is COMPOSITE")
      table.insert(r, "# of Divisors: "..#divs)
      table.insert(r, "Sum of Divisors: "..round(n * (#divs > 0 and 1 or 0)))
      local sumD = 0
      for _, d in ipairs(divs) do sumD = sumD + d end
      r[#r] = "Sum of Divisors: "..sumD
    end
    return r
  end
}

tools["alg_powers"] = {
  inputs = {{"Base=", "", "e.g. 2"}, {"Exponent=", "", "e.g. 3"}},
  compute = function(v)
    local r = {}
    local b, e = v[1], v[2]
    if b == "" or e == "" then return r end
    table.insert(r, "--- Power ---")
    table.insert(r, "")
    table.insert(r, b.."^"..e)
    table.insert(r, "")
    local exact = safeEval("("..b..")^("..e..")")
    if exact then table.insert(r, "Exact = "..exact) end
    local approx = safeEval("approx(("..b..")^("..e.."))")
    if approx and approx ~= exact then
      table.insert(r, "Decimal "..APPROX.." "..approx)
    end
    table.insert(r, "")
    -- Show the inverse
    if exact then
      table.insert(r, "Inverse: "..b.."^(-"..e..") = ")
      local inv = safeEval("("..b..")^(-("..e.."))")
      if inv then table.insert(r, "  "..inv) end
    end
    -- n-th root
    local root = safeEval("("..b..")^(1/("..e.."))")
    if root then
      table.insert(r, "")
      table.insert(r, b.."^(1/"..e..") = "..root)
      local rootApprox = safeEval("approx(("..b..")^(1/("..e..")))")
      if rootApprox and rootApprox ~= root then
        table.insert(r, "  "..APPROX.." "..rootApprox)
      end
    end
    return r
  end
}

tools["alg_gcdlcm"] = {
  inputs = {{"Integer1=", "", "e.g. 12"}, {"Integer2=", "", "e.g. 18"}},
  compute = function(v)
    local a, b = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not a or not b then table.insert(r, "Enter two integers") return r end
    a, b = math.floor(math.abs(a)), math.floor(math.abs(b))

    table.insert(r, "--- GCD & LCM ---")
    table.insert(r, "")
    table.insert(r, "GCD: Greatest Common Divisor")
    table.insert(r, "LCM: Least Common Multiple")
    table.insert(r, "")
    table.insert(r, "--- Prime Factorizations ---")
    table.insert(r, a.." = "..factorStr(a))
    table.insert(r, b.." = "..factorStr(b))
    table.insert(r, "")

    -- Show Euclidean algorithm steps
    table.insert(r, "--- Euclidean Algorithm ---")
    local x, y = a, b
    while y > 0 do
      local q = math.floor(x / y)
      local rem = x % y
      table.insert(r, x.." = "..q.." x "..y.." + "..rem)
      x, y = y, rem
    end
    table.insert(r, "")

    local g = gcd(a, b)
    local l = lcm(a, b)
    table.insert(r, "--- Results ---")
    table.insert(r, "GCD("..a..", "..b..") = "..g)
    table.insert(r, "LCM("..a..", "..b..") = "..l)
    table.insert(r, "")
    table.insert(r, "Check: GCD x LCM = "..g.." x "..l)
    table.insert(r, "= "..(g*l))
    table.insert(r, a.." x "..b.." = "..(a*b))
    return r
  end
}

tools["alg_proportion"] = {
  inputs = {{"a=", "", "e.g. 3"}, {"b=", "", "e.g. 4"}, {"c=", "", "e.g. 5"}, {"d=", "", "e.g. ?"}},
  compute = function(v)
    local r = {}
    table.insert(r, "--- Cross-Multiplication ---")
    table.insert(r, "")
    table.insert(r, "a/b = c/d")
    table.insert(r, "a*d = b*c")
    table.insert(r, "")
    local a,b,c,d = tonumber(v[1]),tonumber(v[2]),tonumber(v[3]),tonumber(v[4])
    local missing = nil
    if not a and b and c and d then missing="a" a=b*c/d
    elseif a and not b and c and d then missing="b" b=a*d/c
    elseif a and b and not c and d then missing="c" c=a*d/b
    elseif a and b and c and not d then missing="d" d=b*c/a
    end
    if missing then
      table.insert(r, "--- Solve for "..missing.." ---")
      table.insert(r, "")
      if missing == "a" then
        table.insert(r, "a = b*c/d")
        table.insert(r, "a = "..b.." x "..c.." / "..d)
      elseif missing == "b" then
        table.insert(r, "b = a*d/c")
        table.insert(r, "b = "..a.." x "..d.." / "..c)
      elseif missing == "c" then
        table.insert(r, "c = a*d/b")
        table.insert(r, "c = "..a.." x "..d.." / "..b)
      elseif missing == "d" then
        table.insert(r, "d = b*c/a")
        table.insert(r, "d = "..b.." x "..c.." / "..a)
      end
      local val = (missing=="a" and a or missing=="b" and b or missing=="c" and c or d)
      table.insert(r, missing.." = "..round(val))
      table.insert(r, "")
      table.insert(r, "--- Result ---")
      table.insert(r, round(a).."/"..round(b).." = "..round(c).."/"..round(d))
      table.insert(r, "")
      table.insert(r, "--- Verify ---")
      table.insert(r, round(a).." x "..round(d).." = "..round(a*d))
      table.insert(r, round(b).." x "..round(c).." = "..round(b*c))
    else
      table.insert(r, "Leave one field empty to solve")
    end
    return r
  end
}

tools["alg_pctchange"] = {
  inputs = {{"Old Value=", "", "e.g. 100"}, {"New Value=", "", "e.g. 120"}},
  compute = function(v)
    local old, new = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not old or not new then table.insert(r, "Enter both values") return r end
    table.insert(r, "--- Percent Change ---")
    table.insert(r, "")
    table.insert(r, "Formula: (New-Old)/|Old| x 100")
    table.insert(r, "")
    local absC = new - old
    local pctC = (absC / math.abs(old)) * 100
    table.insert(r, "--- Calculation ---")
    table.insert(r, "Change = "..new.." - "..old.." = "..round(absC))
    table.insert(r, "")
    table.insert(r, "% = "..round(absC).." / |"..old.."| x 100")
    table.insert(r, "% = "..round(absC).." / "..math.abs(old).." x 100")
    table.insert(r, "% = "..round(pctC).."%")
    table.insert(r, "")
    table.insert(r, "--- Summary ---")
    if pctC > 0 then table.insert(r, "INCREASE of "..round(pctC).."%")
    elseif pctC < 0 then table.insert(r, "DECREASE of "..round(math.abs(pctC)).."%")
    else table.insert(r, "NO CHANGE") end
    table.insert(r, "")
    -- Multiplier
    local mult = new / old
    table.insert(r, "Multiplier: x"..round(mult))
    table.insert(r, old.." x "..round(mult).." = "..round(old*mult))
    return r
  end
}

-- FUNCTIONS TOOLS
tools["fn_explore"] = {
  inputs = {{"f(x)=", "", "e.g. x^2-1"}},
  compute = function(v)
    local f = v[1]
    local r = {}
    table.insert(r, "f(x) = "..f)
    table.insert(r, "")
    
    local z = safeEval("zeros("..f..",x)")
    if z then table.insert(r, "X-Intercept/Zero : x="..z) end
    
    local yint = safeEval(f.."|x=0")
    if yint then table.insert(r, "Y-Intercept = f(0) = "..yint) end
    
    local f_negx = safeEval("expand("..f.."|x=-x)")
    local f_x = safeEval("expand("..f..")")
    local neg_fx = safeEval("expand(-("..f.."))")
    if f_negx == f_x then table.insert(r, "Symmetry of f(x) : "..f.." is even as f(-x)=f(x)")
    elseif f_negx == neg_fx then table.insert(r, "Symmetry of f(x) : "..f.." is odd as f(-x)=-f(x)")
    else table.insert(r, "Symmetry of f(x) : neither even nor odd") end
    
    local d = safeEval("d("..f..",x)")
    if d then 
      local crit = safeEval("zeros("..d..",x)")
      if crit and crit ~= "{}" then table.insert(r, "Critical pts: x="..crit) end
    end
    
    local min = safeEval("fMin("..f..",x)")
    if min then table.insert(r, "Minimum at x="..min) end
    local max = safeEval("fMax("..f..",x)")
    if max then table.insert(r, "Maximum at x="..max) end
    
    -- old items moved to bottom
    local d_val = safeEval("d("..f..",x)")
    if d_val then table.insert(r, "f'(x) = "..d_val) end
    local intg = safeEval("integral("..f..",x)")
    if not intg then intg = safeEval("integral("..f..",x)") end
    if intg then table.insert(r, "integralf(x)dx = "..intg) end
    
    return r
  end
}

tools["fn_eval"] = {
  inputs = {{"f(x)=", "", "e.g. x^2+3x"}, {"x=", "", "e.g. 3"}},
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
  inputs = {{"f(x)=", "", "e.g. x^2"}, {"g(x)=", "", "e.g. x+9"}},
  compute = function(v)
    local r = {}
    local f, g = v[1], v[2]
    if f == "" or g == "" then return r end
    table.insert(r, "f(x) = "..f)
    table.insert(r, "g(x) = "..g)
    table.insert(r, "")
    table.insert(r, "Set f(x) = g(x):")
    table.insert(r, f.." = "..g)
    table.insert(r, "")
    -- Numeric intersection
    local nsol = safeEval("nSolve("..f.."="..g..",x)")
    if nsol then
      table.insert(r, "They intersect when")
      table.insert(r, "x = "..nsol)
      -- Compute y at intersection
      local yval = safeEval(f.."|x="..nsol)
      if yval then table.insert(r, "y = "..yval) end
    end
    table.insert(r, "")
    -- Exact/symbolic solution
    local sol = safeEval("solve("..f.."="..g..",x)")
    if sol then
      table.insert(r, "Exact Solution:")
      table.insert(r, sol)
    end
    return r
  end
}

tools["fn_add"] = {
  inputs = {{"f(x)=", "", "e.g. x^2+3x"}, {"g(x)=", "", "e.g. x+1"}},
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
    if s then table.insert(r, "(f*g)(x) = "..s) end
    s = safeEval("("..v[1]..")/("..v[2]..")")
    if s then table.insert(r, "(f/g)(x) = "..s) end
    return r
  end
}

tools["fn_compose"] = {
  inputs = {{"f(x)=", "", "e.g. x^2+3x"}, {"g(x)=", "", "e.g. x+1"}},
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
  inputs = {{"f(x)=", "", "e.g. x^2+3x"}},
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
  inputs = {{"p(x)=", "", "e.g. x^3-2x+1"}},
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
  inputs = {{"p(x)=", "", "e.g. x^3-2x+1"}},
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
  inputs = {{"x1=", "", "e.g. 6"}, {"y1=", "", "e.g. 2"}, {"x2=", "", "e.g. 3"}, {"y2=", "", "e.g. 5"}},
  compute = function(v)
    local x1,y1,x2,y2 = tonumber(v[1]),tonumber(v[2]),tonumber(v[3]),tonumber(v[4])
    local r = {}
    if not (x1 and y1 and x2 and y2) then table.insert(r, "Enter all 4 values") return r end
    table.insert(r, "P1("..x1..", "..y1..")  P2("..x2..", "..y2..")")
    table.insert(r, "")
    table.insert(r, "1) Slope:")
    table.insert(r, "m = (y2-y1)/(x2-x1)")
    if x2 == x1 then
      table.insert(r, "m = undefined (vertical)")
    else
      table.insert(r, "m = ("..(y2).."-"..(y1)..")/("..(x2).."-"..(x1)..")")
      table.insert(r, "m = "..(y2-y1).."/"..(x2-x1))
      local m = (y2 - y1) / (x2 - x1)
      table.insert(r, "m = "..round(m))
      table.insert(r, "")
      table.insert(r, "2) Midpoint:")
      table.insert(r, "= ((x1+x2)/2, (y1+y2)/2)")
      local mx = (x1+x2)/2
      local my = (y1+y2)/2
      table.insert(r, "= (("..(x1).."+"..(x2)..")/2, ("..(y1).."+"..(y2)..")/2)")
      table.insert(r, "= ("..round(mx)..", "..round(my)..")")
      table.insert(r, "")
      table.insert(r, "3) Distance:")
      table.insert(r, "d = sqrt((x2-x1)^2+(y2-y1)^2)")
      local dx, dy = x2-x1, y2-y1
      table.insert(r, "= sqrt("..dx.."^2+"..dy.."^2)")
      table.insert(r, "= sqrt("..(dx*dx).."+"..(dy*dy)..")")
      local dist = math.sqrt(dx*dx + dy*dy)
      table.insert(r, "= sqrt("..(dx*dx+dy*dy)..")")
      table.insert(r, "= "..round(dist))
      table.insert(r, "")
      table.insert(r, "4) Equation:")
      local b = y1 - m * x1
      table.insert(r, "y = "..round(m).."x + "..round(b))
    end
    return r
  end
}

tools["pt_ymxb"] = {
  inputs = {{"m (slope)=", "", "e.g. 2"}, {"b (intercept)=", "", "e.g. 3"}},
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
  inputs = {{"x1=", "", "e.g. 1"}, {"y1=", "", "e.g. 2"}, {"m=", "", "e.g. 2"}},
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
  inputs = {{"m1=", "", "e.g. 3"}, {"m2=", "", "e.g. -1/3"}},
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
  inputs = {{"m=", "", "e.g. 2"}, {"x1=", "", "e.g. 1"}, {"y1=", "", "e.g. 2"}},
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
  inputs = {{"a=", "", "e.g. 1"}, {"b=", "", "e.g. -5"}, {"c=", "", "e.g. 6"}},
  compute = function(v)
    local a,b,c = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a and b and c) then table.insert(r, "Enter a, b, c") return r end
    table.insert(r, a.."x^2 + ("..b..")x + ("..c..") = 0")
    table.insert(r, "")
    table.insert(r, "x = (-b +/- sqrt(b^2-4ac))/2a")
    table.insert(r, "")
    table.insert(r, "1) Discriminant:")
    table.insert(r, "b^2 - 4ac")
    table.insert(r, "= ("..b..")^2 - 4("..a..")("..c..")")
    local disc = b*b - 4*a*c
    table.insert(r, "= "..(b*b).." - "..(4*a*c))
    table.insert(r, "= "..round(disc))
    table.insert(r, "")
    if disc > 0 then
      table.insert(r, "2) Two Real Solutions:")
      table.insert(r, "x = (-"..b.." +/- sqrt("..round(disc).."))/"..2*a)
      local x1 = (-b + math.sqrt(disc)) / (2*a)
      local x2 = (-b - math.sqrt(disc)) / (2*a)
      table.insert(r, "")
      table.insert(r, "x1 = (-"..b.."+"..round(math.sqrt(disc))..")/("..2*a..")")
      table.insert(r, "x1 = "..round(x1))
      table.insert(r, "")
      table.insert(r, "x2 = (-"..b.."-"..round(math.sqrt(disc))..")/("..2*a..")")
      table.insert(r, "x2 = "..round(x2))
    elseif disc == 0 then
      local x1 = -b / (2*a)
      table.insert(r, "2) One Repeated Solution:")
      table.insert(r, "x = -"..b.."/"..2*a)
      table.insert(r, "x = "..round(x1))
    else
      local real = -b / (2*a)
      local imag = math.sqrt(-disc) / (2*a)
      table.insert(r, "2) Two Complex Solutions:")
      table.insert(r, "x1 = "..round(real).." + "..round(imag).."i")
      table.insert(r, "x2 = "..round(real).." - "..round(imag).."i")
    end
    table.insert(r, "")
    table.insert(r, "3) Vertex:")
    table.insert(r, "h = -b/(2a) = -"..b.."/("..2*a..")")
    table.insert(r, "h = "..round(-b/(2*a)))
    table.insert(r, "k = f(h) = "..round(c - b*b/(4*a)))
    table.insert(r, "Vertex: ("..round(-b/(2*a))..", "..round(c - b*b/(4*a))..")")
    return r
  end
}

tools["quad_complete"] = {
  inputs = {{"a=", "", "e.g. 3"}, {"b=", "", "e.g. 4"}, {"c=", "", "e.g. 5"}},
  compute = function(v)
    local a,b,c = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a and b and c) then table.insert(r, "Enter a, b, c") return r end
    table.insert(r, a.."x^2 + "..b.."x + "..c)
    table.insert(r, "")
    table.insert(r, "Complete the Square:")
    local h = -b / (2*a)
    local k = c - b*b / (4*a)
    table.insert(r, "= "..a.."(x^2 + "..round(b/a).."x) + "..c)
    table.insert(r, "= "..a.."(x + "..round(h)..") ^2 + "..round(k))
    table.insert(r, "")
    table.insert(r, "Vertex Form: "..a.."(x - "..round(-h)..")^2 + "..round(k))
    return r
  end
}

tools["quad_zeros"] = tools["quad_formula"]

tools["quad_vertex"] = {
  inputs = {{"a=", "", "e.g. 3"}, {"b=", "", "e.g. 4"}, {"c=", "", "e.g. 5"}},
  compute = function(v)
    local a,b,c = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (a and b and c) then table.insert(r, "Enter a, b, c") return r end
    local h = -b / (2*a)
    local k = c - b*b / (4*a)
    table.insert(r, "f(x) = "..a.."x^2 + "..b.."x + "..c)
    table.insert(r, "")
    table.insert(r, "Vertex Form:")
    table.insert(r, "f(x) = "..a.."(x - "..round(h)..")^2 + "..round(k))
    table.insert(r, "")
    table.insert(r, "Vertex: ("..round(h)..", "..round(k)..")")
    table.insert(r, "Axis of Symmetry: x = "..round(h))
    if a > 0 then table.insert(r, "Opens: Upward (minimum)")
    else table.insert(r, "Opens: Downward (maximum)") end
    return r
  end
}

tools["cx_one"] = {
  inputs = {{"z1=", "", "e.g. 3+4i"}},
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
    table.insert(r, "sqrt("..rn.."^2+("..imn..")^2) = "..round(modulus))
    table.insert(r, "")
    local angle = math.deg(math.atan2(imn, rn))
    table.insert(r, "theta=Angle with x-axis: "..round(angle).." deg")
    table.insert(r, "")
    local conj = safeEval("conj("..z..")")
    if conj then table.insert(r, "Conjugate: "..conj) end
    return r
  end
}

tools["cx_two"] = {
  inputs = {{"z1=", "", "e.g. 3+4i"}, {"z2=", "", "e.g. 1-2i"}},
  compute = function(v)
    local r = {}
    table.insert(r, "z1 = "..v[1].."  z2 = "..v[2])
    table.insert(r, "")
    local s = safeEval("("..v[1]..") + ("..v[2]..")")
    if s then table.insert(r, "z1 + z2 = "..s) end
    s = safeEval("("..v[1]..") - ("..v[2]..")")
    if s then table.insert(r, "z1 - z2 = "..s) end
    s = safeEval("("..v[1]..") * ("..v[2]..")")
    if s then table.insert(r, "z1 * z2 = "..s) end
    s = safeEval("("..v[1]..") / ("..v[2]..")")
    if s then table.insert(r, "z1 / z2 = "..s) end
    return r
  end
}

-- EXPONENTS & LOGS TOOLS
tools["exp_solve"] = {
  inputs = {{"Equation=", "", "e.g. 2^x=8"}},
  compute = function(v)
    local r = {}
    table.insert(r, "Solve: "..v[1])
    local sol = safeEval("solve("..v[1]..",x)")
    if not sol then sol = safeEval("nSolve("..v[1]..",x)") end
    if sol then table.insert(r, "Solution: "..sol)
    else table.insert(r, "No solution found") end
    return r
  end
}

tools["exp_rule72"] = {
  inputs = {{"Rate(%)=", "", "e.g. 6"}},
  compute = function(v)
    local rate = tonumber(v[1])
    local r = {}
    if not rate then table.insert(r, "Enter interest rate %") return r end
    table.insert(r, "Rule of 72: Est. years to double")
    table.insert(r, "Rate: "..rate.."%")
    table.insert(r, "")
    table.insert(r, "Time ~= 72 / "..rate)
    table.insert(r, "= "..round(72/rate).." periods")
    return r
  end
}

tools["exp_growth"] = {
  inputs = {{"P0 (initial)=", "", "e.g. 1000"}, {"rate(%)=", "", "e.g. 5"}, {"t (time)=", "", "e.g. 10"}},
  compute = function(v)
    local p0,rate,t = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (p0 and rate and t) then table.insert(r, "Enter all values") return r end
    local rr = rate/100
    table.insert(r, "P(t) = P0 * (1+r)^t")
    table.insert(r, "P("..t..") = "..p0.." * (1+"..rr..")^"..t)
    local result = p0 * (1+rr)^t
    table.insert(r, "= "..round(result, 2))
    table.insert(r, "")
    table.insert(r, "Continuous: P0*e^(rt)")
    local cont = p0 * math.exp(rr*t)
    table.insert(r, "= "..round(cont, 2))
    return r
  end
}

tools["log_eval"] = {
  inputs = {{"Base=", "", "e.g. 2"}, {"Value=", "", "e.g. 100"}},
  compute = function(v)
    local b, val = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not b or not val then table.insert(r, "Enter base and value") return r end
    local result = math.log(val)/math.log(b)
    table.insert(r, "log_"..b.."("..val..") = "..round(result))
    return r
  end
}

-- SAT-SPECIFIC: Linear Inequality Solver
tools["alg_ineq"] = {
  inputs = {{"Inequality=", "", "e.g. 2x+3>7"}},
  compute = function(v)
    local ineq = v[1]
    if ineq == "" then return {} end
    local r = {}
    table.insert(r, "--- Solve Inequality ---")
    table.insert(r, "")
    table.insert(r, "Given: "..ineq)
    table.insert(r, "")

    -- Try to solve with CAS
    local sol = safeEval("solve("..ineq..",x)")
    if sol then
      table.insert(r, "--- Solution ---")
      table.insert(r, "")
      table.insert(r, sol)
    else
      -- Try alternative approaches
      sol = safeEval("nSolve("..ineq..",x)")
      if sol then
        table.insert(r, "--- Numeric Solution ---")
        table.insert(r, sol)
      else
        table.insert(r, "Could not solve")
        table.insert(r, "Try Solve Equation instead")
      end
    end
    return r
  end
}

-- SAT-SPECIFIC: Rational Expression Simplifier
tools["adv_rational"] = {
  inputs = {{"Numerator=", "", "e.g. x^2-1"}, {"Denominator=", "", "e.g. x+1"}},
  compute = function(v)
    local num, den = v[1], v[2]
    local r = {}
    if num == "" or den == "" then return r end
    table.insert(r, "--- Rational Expression ---")
    table.insert(r, "")
    table.insert(r, "("..num..") / ("..den..")")
    table.insert(r, "")

    -- Factor numerator and denominator
    local fnum = safeEval("factor("..num..")")
    local fden = safeEval("factor("..den..")")
    if fnum then table.insert(r, "Num factored: "..fnum) end
    if fden then table.insert(r, "Den factored: "..fden) end
    table.insert(r, "")

    -- Simplify
    local simp = safeEval("simplify(("..num..")/("..den.."))")
    if simp then
      table.insert(r, "Simplified: "..simp)
    end

    -- Find domain restrictions (zeros of denominator)
    local zeros = safeEval("zeros("..den..",x)")
    if zeros then
      table.insert(r, "")
      table.insert(r, "Domain Restriction:")
      table.insert(r, "x "..string.char(226,137,160).." "..zeros)
    end
    return r
  end
}

-- SAT-SPECIFIC: Radical Simplifier
tools["adv_radical"] = {
  inputs = {{"Expression=", "", "e.g. sqrt(72)"}},
  compute = function(v)
    local expr = v[1]
    local r = {}
    if expr == "" then return r end
    table.insert(r, "--- Simplify Radical ---")
    table.insert(r, "")
    table.insert(r, "Input: "..expr)
    table.insert(r, "")

    -- Exact simplification
    local simp = safeEval("simplify("..expr..")")
    if simp then table.insert(r, "Simplified: "..simp) end

    -- Try to factor under radical
    local fact = safeEval("factor("..expr..")")
    if fact and fact ~= simp then
      table.insert(r, "Factored: "..fact)
    end

    -- Decimal approximation
    local approx = safeEval("approx("..expr..")")
    if approx then
      table.insert(r, "")
      table.insert(r, "Decimal "..APPROX.." "..approx)
    end
    return r
  end
}



tools["log_cob"] = {
  inputs = {{"Base=", "", "e.g. 2"}, {"Value=", "", "e.g. 100"}},
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

-- CIRCLES TOOLS
tools["circ_sector"] = {
  inputs = {{"r=", "", "e.g. 5"}, {"theta (deg)=", "", "e.g. 90"}},
  compute = function(v)
    local radius, angle = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not (radius and angle) then table.insert(r, "Enter r and angle") return r end
    local rad = math.rad(angle)
    local area = 0.5 * radius^2 * rad
    table.insert(r, "Sector with r="..radius..", theta="..angle.." deg")
    table.insert(r, "")
    table.insert(r, "Area = 1/2 r^2theta")
    table.insert(r, "= "..round(area))
    local arcLen = radius * rad
    table.insert(r, "Arc Length = rtheta = "..round(arcLen))
    return r
  end
}

tools["circ_arc"] = {
  inputs = {{"r=", "", "e.g. 5"}, {"theta (deg)=", "", "e.g. 90"}},
  compute = function(v)
    local radius, angle = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not (radius and angle) then table.insert(r, "Enter r and angle") return r end
    local arcLen = radius * math.rad(angle)
    table.insert(r, "Arc Length = r * theta(rad)")
    table.insert(r, "= "..radius.." * "..round(math.rad(angle)))
    table.insert(r, "= "..round(arcLen))
    return r
  end
}

-- TRIGONOMETRY TOOLS
tools["trig_right"] = {
  inputs = {{"a=", "", "e.g. 3"}, {"b=", "", "e.g. 4"}, {"c(hyp)=", "", "e.g. 5"}},
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
    table.insert(r, "Angle A = "..round(A).." deg")
    table.insert(r, "Angle B = "..round(B).." deg")
    table.insert(r, "Area = "..round(0.5*a*b))
    table.insert(r, "Perimeter = "..round(a+b+c))
    return r
  end
}



tools["trig_sinx"] = {
  inputs = {{"x (deg)=", "", "e.g. 45"}},
  compute = function(v)
    local x = tonumber(v[1])
    local r = {}
    if not x then table.insert(r, "Enter angle in degrees") return r end
    local xr = math.rad(x)
    table.insert(r, "x = "..x.." deg = "..round(xr).." rad")
    table.insert(r, "")
    table.insert(r, "sin("..x.." deg) = "..round(math.sin(xr)))
    table.insert(r, "cos("..x.." deg) = "..round(math.cos(xr)))
    table.insert(r, "tan("..x.." deg) = "..round(math.tan(xr)))
    return r
  end
}

-- GEOMETRY TOOLS
local function geoTool(name, labels, fn)
  tools[name] = { inputs = labels, compute = fn }
end

geoTool("geo_circle", {{"r=", "", "e.g. 5"}}, function(v)
  local r = {}; local radius = tonumber(v[1])
  if not radius then table.insert(r, "Enter radius") return r end
  table.insert(r, "Circle: r = "..radius)
  table.insert(r, "Area = pir^2 = "..round(math.pi*radius^2))
  table.insert(r, "Circumference = 2pir = "..round(2*math.pi*radius))
  table.insert(r, "Diameter = "..2*radius)
  return r
end)

geoTool("geo_sector", tools["circ_sector"].inputs, tools["circ_sector"].compute)
geoTool("geo_arc", tools["circ_arc"].inputs, tools["circ_arc"].compute)

geoTool("geo_pyth", {{"a=", "", "e.g. 3"}, {"b=", "", "e.g. 4"}}, function(v)
  local r = {}; local a,b = tonumber(v[1]),tonumber(v[2])
  if not (a and b) then table.insert(r, "Enter a and b") return r end
  local c = math.sqrt(a*a+b*b)
  table.insert(r, "a^2 + b^2 = c^2")
  table.insert(r, a.."^2 + "..b.."^2 = "..round(c).."^2")
  table.insert(r, "c = "..round(c))
  return r
end)

geoTool("geo_tri", {{"base=", "", "e.g. 5"}, {"height=", "", "e.g. 8"}}, function(v)
  local r = {}; local base,h = tonumber(v[1]),tonumber(v[2])
  if not (base and h) then table.insert(r, "Enter base and height") return r end
  table.insert(r, "Triangle: base="..base.." height="..h)
  table.insert(r, "Area = 1/2bh = "..round(0.5*base*h))
  return r
end)

geoTool("geo_square", {{"side=", "", "e.g. 6"}}, function(v)
  local r = {}; local s = tonumber(v[1])
  if not s then table.insert(r, "Enter side") return r end
  table.insert(r, "Square: s = "..s)
  table.insert(r, "Area = "..round(s*s))
  table.insert(r, "Perimeter = "..round(4*s))
  table.insert(r, "Diagonal = "..round(s*math.sqrt(2)))
  return r
end)

geoTool("geo_rect", {{"length=", "", "e.g. 8"}, {"width=", "", "e.g. 4"}}, function(v)
  local r = {}; local l,w = tonumber(v[1]),tonumber(v[2])
  if not (l and w) then table.insert(r, "Enter l and w") return r end
  table.insert(r, "Rectangle: "..l.." x "..w)
  table.insert(r, "Area = "..round(l*w))
  table.insert(r, "Perimeter = "..round(2*(l+w)))
  table.insert(r, "Diagonal = "..round(math.sqrt(l*l+w*w)))
  return r
end)

geoTool("geo_para", {{"base=", "", "e.g. 5"}, {"height=", "", "e.g. 8"}, {"side=", "", "e.g. 6"}}, function(v)
  local r = {}; local b,h,s = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
  if not (b and h) then table.insert(r, "Enter base and height") return r end
  table.insert(r, "Parallelogram: b="..b.." h="..h)
  table.insert(r, "Area = bh = "..round(b*h))
  if s then table.insert(r, "Perimeter = "..round(2*(b+s))) end
  return r
end)



geoTool("geo_trap", {{"a(top)=", "", "e.g. 4"}, {"b(bot)=", "", "e.g. 8"}, {"h=", "", "e.g. 5"}}, function(v)
  local r = {}; local a,b,h = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
  if not (a and b and h) then table.insert(r, "Enter a, b, h") return r end
  table.insert(r, "Trapezoid: a="..a.." b="..b.." h="..h)
  table.insert(r, "Area = 1/2(a+b)h = "..round(0.5*(a+b)*h))
  return r
end)

geoTool("geo_sphere", {{"r=", "", "e.g. 5"}}, function(v)
  local r = {}; local radius = tonumber(v[1])
  if not radius then table.insert(r, "Enter radius") return r end
  table.insert(r, "Sphere: r = "..radius)
  table.insert(r, "Volume = 4/3pir^3 = "..round(4/3*math.pi*radius^3))
  table.insert(r, "Surface = 4pir^2 = "..round(4*math.pi*radius^2))
  return r
end)

geoTool("geo_cube", {{"side=", "", "e.g. 6"}}, function(v)
  local r = {}; local s = tonumber(v[1])
  if not s then table.insert(r, "Enter side") return r end
  table.insert(r, "Cube: s = "..s)
  table.insert(r, "Volume = s^3 = "..round(s^3))
  table.insert(r, "Surface = 6s^2 = "..round(6*s^2))
  table.insert(r, "Diagonal = ssqrt3 = "..round(s*math.sqrt(3)))
  return r
end)

geoTool("geo_cyl", {{"r=", "", "e.g. 5"}, {"h=", "", "e.g. 5"}}, function(v)
  local r = {}; local radius,h = tonumber(v[1]),tonumber(v[2])
  if not (radius and h) then table.insert(r, "Enter r and h") return r end
  table.insert(r, "Cylinder: r="..radius.." h="..h)
  table.insert(r, "Volume = pir^2h = "..round(math.pi*radius^2*h))
  table.insert(r, "Lateral = 2pirh = "..round(2*math.pi*radius*h))
  table.insert(r, "Total SA = "..round(2*math.pi*radius*(radius+h)))
  return r
end)

geoTool("geo_cone", {{"r=", "", "e.g. 5"}, {"h=", "", "e.g. 5"}}, function(v)
  local r = {}; local radius,h = tonumber(v[1]),tonumber(v[2])
  if not (radius and h) then table.insert(r, "Enter r and h") return r end
  local slant = math.sqrt(radius^2+h^2)
  table.insert(r, "Cone: r="..radius.." h="..h)
  table.insert(r, "Slant = "..round(slant))
  table.insert(r, "Volume = 1/3pir^2h = "..round(math.pi*radius^2*h/3))
  table.insert(r, "Lateral = pirl = "..round(math.pi*radius*slant))
  table.insert(r, "Total SA = "..round(math.pi*radius*(radius+slant)))
  return r
end)

geoTool("geo_rprism", {{"l=", "", "e.g. l"}, {"w=", ""}, {"h=", "", "e.g. 5"}}, function(v)
  local r = {}; local l,w,h = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
  if not (l and w and h) then table.insert(r, "Enter l, w, h") return r end
  table.insert(r, "Rectangular Prism: "..l.."x"..w.."x"..h)
  table.insert(r, "Volume = "..round(l*w*h))
  table.insert(r, "Surface = "..round(2*(l*w+l*h+w*h)))
  table.insert(r, "Diagonal = "..round(math.sqrt(l*l+w*w+h*h)))
  return r
end)

-- CONVERT TOOLS
tools["conv_degrad"] = {
  inputs = {{"Degrees=", "", "e.g. 45"}},
  compute = function(v)
    local d = tonumber(v[1])
    local r = {}
    if not d then table.insert(r, "Enter degrees") return r end
    local rad = math.rad(d)
    table.insert(r, d.." deg = "..round(rad).." rad")
    table.insert(r, "= "..round(rad/math.pi).."pi rad")
    table.insert(r, "")
    table.insert(r, "Reverse: "..round(rad).." rad = "..round(math.deg(rad)).." deg")
    return r
  end
}

-- SAT-SPECIFIC: Circle Equation Solver
tools["geo_circleq"] = {
  inputs = {{"h (center x)=", "", "e.g. 3"}, {"k (center y)=", "", "e.g. -2"}, {"r (radius)=", "", "e.g. 5"}},
  compute = function(v)
    local h,k,radius = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (h and k and radius) then table.insert(r, "Enter h, k, r") return r end
    table.insert(r, "--- Circle Equation ---")
    table.insert(r, "")
    table.insert(r, "Standard Form:")
    table.insert(r, "(x-"..h..")^2 + (y-"..k..")^2 = "..radius.."^2")
    table.insert(r, "(x-"..h..")^2 + (y-"..k..")^2 = "..round(radius^2))
    table.insert(r, "")
    table.insert(r, "Center: ("..h..", "..k..")")
    table.insert(r, "Radius: "..radius)
    table.insert(r, "")
    -- Expanded (general) form
    local D = -2*h
    local E = -2*k
    local F = h*h + k*k - radius*radius
    table.insert(r, "General Form:")
    table.insert(r, "x^2 + y^2 + ("..round(D)..")x + ("..round(E)..")y + ("..round(F)..") = 0")
    table.insert(r, "")
    table.insert(r, "Area = pir^2 = "..round(math.pi*radius^2))
    table.insert(r, "Circumference = 2pir = "..round(2*math.pi*radius))
    return r
  end
}

-- SAT-SPECIFIC: Pyramid Volume
geoTool("geo_pyramid", {{"l=", "", "e.g. 6"}, {"w=", "", "e.g. 4"}, {"h=", "", "e.g. 5"}}, function(v)
  local r = {}; local l,w,h = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
  if not (l and w and h) then table.insert(r, "Enter l, w, h") return r end
  table.insert(r, "Pyramid: l="..l.." w="..w.." h="..h)
  table.insert(r, "")
  table.insert(r, "V = (1/3)lwh")
  table.insert(r, "V = (1/3)("..l..")("..w..")("..h..")")
  table.insert(r, "V = "..round(l*w*h/3))
  table.insert(r, "")
  table.insert(r, "Base Area = lw = "..round(l*w))
  return r
end)

-- SAT-SPECIFIC: Two-Way Table / Conditional Probability
tools["stat_twoway"] = {
  inputs = {{"a (R1C1)=", "", "e.g. 30"}, {"b (R1C2)=", "", "e.g. 20"}, {"c (R2C1)=", "", "e.g. 10"}, {"d (R2C2)=", "", "e.g. 40"}},
  compute = function(v)
    local a,b,c,d = tonumber(v[1]),tonumber(v[2]),tonumber(v[3]),tonumber(v[4])
    local r = {}
    if not (a and b and c and d) then table.insert(r, "Enter all 4 values") return r end
    local r1 = a + b
    local r2 = c + d
    local c1 = a + c
    local c2 = b + d
    local total = r1 + r2
    table.insert(r, "--- Two-Way Table ---")
    table.insert(r, "")
    table.insert(r, "       C1    C2   Total")
    table.insert(r, "R1   "..a.."    "..b.."    "..r1)
    table.insert(r, "R2   "..c.."    "..d.."    "..r2)
    table.insert(r, "Tot  "..c1.."   "..c2.."   "..total)
    table.insert(r, "")
    table.insert(r, "--- Probabilities ---")
    table.insert(r, "P(R1) = "..round(r1/total))
    table.insert(r, "P(R2) = "..round(r2/total))
    table.insert(r, "P(C1) = "..round(c1/total))
    table.insert(r, "P(C2) = "..round(c2/total))
    table.insert(r, "")
    table.insert(r, "--- Conditional ---")
    table.insert(r, "P(C1|R1) = "..a.."/"..r1.." = "..round(a/r1))
    table.insert(r, "P(C2|R1) = "..b.."/"..r1.." = "..round(b/r1))
    table.insert(r, "P(C1|R2) = "..c.."/"..r2.." = "..round(c/r2))
    table.insert(r, "P(C2|R2) = "..d.."/"..r2.." = "..round(d/r2))
    return r
  end
}

-- SAT-SPECIFIC: Margin of Error
tools["stat_moe"] = {
  inputs = {{"p (proportion)=", "", "e.g. 0.6"}, {"n (sample size)=", "", "e.g. 100"}, {"Conf Level %=", "", "e.g. 95"}},
  compute = function(v)
    local p,n,conf = tonumber(v[1]),tonumber(v[2]),tonumber(v[3])
    local r = {}
    if not (p and n) then table.insert(r, "Enter p and n") return r end
    conf = conf or 95
    -- z-scores for common confidence levels
    local z = 1.96
    if conf == 90 then z = 1.645
    elseif conf == 95 then z = 1.96
    elseif conf == 99 then z = 2.576 end
    table.insert(r, "--- Margin of Error ---")
    table.insert(r, "")
    table.insert(r, "p = "..p.."  n = "..n)
    table.insert(r, "Confidence: "..conf.."%")
    table.insert(r, "z = "..z)
    table.insert(r, "")
    table.insert(r, "MOE = z * sqrt(p(1-p)/n)")
    local se = math.sqrt(p*(1-p)/n)
    local moe = z * se
    table.insert(r, "SE = sqrt("..p.."*"..(1-p).."/"..n..")")
    table.insert(r, "SE = "..round(se, 4))
    table.insert(r, "MOE = "..z.." * "..round(se, 4))
    table.insert(r, "MOE = "..round(moe, 4))
    table.insert(r, "")
    table.insert(r, "--- Confidence Interval ---")
    table.insert(r, "("..round(p-moe, 4)..", "..round(p+moe, 4)..")") 
    table.insert(r, "")
    table.insert(r, round((p-moe)*100, 1).."% to "..round((p+moe)*100, 1).."%")
    return r
  end
}

-- SAT SPECIALS
tools["sat_sigma"] = {
  inputs = {{"f(n)=", "", "e.g. f(n)"}, {"from n=", ""}, {"to n=", ""}},
  compute = function(v)
    local r = {}
    local expr = v[1]
    local a,b = tonumber(v[2]),tonumber(v[3])
    if not (a and b) then table.insert(r, "Enter range") return r end
    table.insert(r, "Sum "..expr.." from n="..a.." to "..b)
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
  inputs = {{"Low=", "", "e.g. Low"}, {"High=", ""}, {"N (step)=", ""}},
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
  inputs = {{"Low=", "", "e.g. Low"}, {"High=", ""}, {"N=", ""}, {"M=", ""}},
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
  inputs = {{"Equation=", "", "e.g. 2^x=8"}, {"x range=", ""}, {"y range=", ""}},
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
  inputs = {{"Equation=", "", "e.g. 2^x=8"}},
  compute = function(v)
    local r = {}
    table.insert(r, "Equation: "..v[1])
    local sol = safeEval("solve("..v[1]..",{x,y,z})")
    if sol then table.insert(r, sol)
    else table.insert(r, "Use CAS directly for best results") end
    return r
  end
}

-- DISTANCE & MIDPOINT TOOLS
tools["pt_distance"] = {
  inputs = {{"x1=", "", "e.g. 1"}, {"y1=", "", "e.g. 2"}, {"x2=", "", "e.g. 4"}, {"y2=", "", "e.g. 6"}},
  compute = function(v)
    local x1,y1,x2,y2 = tonumber(v[1]),tonumber(v[2]),tonumber(v[3]),tonumber(v[4])
    local r = {}
    if not (x1 and y1 and x2 and y2) then table.insert(r, "Enter all 4 values") return r end
    local dx, dy = x2-x1, y2-y1
    local d = math.sqrt(dx*dx + dy*dy)
    table.insert(r, "P1("..x1..", "..y1..")  P2("..x2..", "..y2..")")
    table.insert(r, "3) Distance:")
    table.insert(r, "d = sqrt((x2-x1)^2+(y2-y1)^2)")
    table.insert(r, "= sqrt(("..dx..")^2+("..dy..")^2)")
    table.insert(r, "= sqrt("..(dx*dx+dy*dy)..")")
    table.insert(r, "= "..round(d))
    return r
  end
}

tools["pt_midpoint"] = {
  inputs = {{"x1=", "", "e.g. 1"}, {"y1=", "", "e.g. 2"}, {"x2=", "", "e.g. 4"}, {"y2=", "", "e.g. 6"}},
  compute = function(v)
    local x1,y1,x2,y2 = tonumber(v[1]),tonumber(v[2]),tonumber(v[3]),tonumber(v[4])
    local r = {}
    if not (x1 and y1 and x2 and y2) then table.insert(r, "Enter all 4 values") return r end
    local mx, my = (x1+x2)/2, (y1+y2)/2
    table.insert(r, "P1("..x1..", "..y1..")  P2("..x2..", "..y2..")")
    table.insert(r, "")
    table.insert(r, "Midpoint = ((x1+x2)/2, (y1+y2)/2)")
    table.insert(r, "= (("..x1.."+"..x2..")/2, ("..y1.."+"..y2..")/2)")
    table.insert(r, "= ("..round(mx)..", "..round(my)..")")
    return r
  end
}

-- STATISTICS TOOLS
local function parseList(s)
  local nums = {}
  for t in s:gmatch("[^,]+") do
    local n = tonumber(t:match("^%s*(.-)%s*$"))
    if n then table.insert(nums, n) end
  end
  table.sort(nums)
  return nums
end

local function median(sorted, lo, hi)
  local n = hi - lo + 1
  if n % 2 == 1 then return sorted[lo + (n-1)/2]
  else return (sorted[lo + n/2 - 1] + sorted[lo + n/2]) / 2 end
end

tools["stat_central"] = {
  inputs = {{"Data(csv)=", "", "e.g. Data(csv)"}},
  compute = function(v)
    local r = {}
    local nums = parseList(v[1])
    if #nums == 0 then table.insert(r, "Enter comma-separated numbers") return r end
    local sum = 0
    for _, n in ipairs(nums) do sum = sum + n end
    local mean = sum / #nums
    table.insert(r, "n = "..#nums)
    table.insert(r, "")
    table.insert(r, "Mean = "..round(mean))
    table.insert(r, "Median = "..round(median(nums, 1, #nums)))
    -- Mode
    local freq = {}
    local maxF = 0
    for _, n in ipairs(nums) do freq[n] = (freq[n] or 0) + 1; if freq[n] > maxF then maxF = freq[n] end end
    local modes = {}
    for n, f in pairs(freq) do if f == maxF then table.insert(modes, n) end end
    table.sort(modes)
    if maxF == 1 then table.insert(r, "Mode: none (all unique)")
    else table.insert(r, "Mode: "..table.concat(modes, ", ").." (freq="..maxF..")") end
    table.insert(r, "Sum = "..round(sum))
    table.insert(r, "Range = "..round(nums[#nums] - nums[1]))
    return r
  end
}

tools["stat_stdev"] = {
  inputs = {{"Data(csv)=", "", "e.g. Data(csv)"}},
  compute = function(v)
    local r = {}
    local nums = parseList(v[1])
    if #nums < 2 then table.insert(r, "Enter at least 2 numbers") return r end
    local sum = 0
    for _, n in ipairs(nums) do sum = sum + n end
    local mean = sum / #nums
    local ssq = 0
    for _, n in ipairs(nums) do ssq = ssq + (n - mean)^2 end
    local popSD = math.sqrt(ssq / #nums)
    local samSD = math.sqrt(ssq / (#nums - 1))
    table.insert(r, "n = "..#nums.."  Mean = "..round(mean))
    table.insert(r, "")
    table.insert(r, "Population sigma = "..round(popSD))
    table.insert(r, "Sample s = "..round(samSD))
    table.insert(r, "Variance sigma^2 = "..round(ssq/#nums))
    return r
  end
}

tools["stat_5num"] = {
  inputs = {{"Data(csv)=", "", "e.g. Data(csv)"}},
  compute = function(v)
    local r = {}
    local nums = parseList(v[1])
    if #nums < 4 then table.insert(r, "Enter at least 4 numbers") return r end
    local n = #nums
    local med = median(nums, 1, n)
    local q1, q3
    if n % 2 == 1 then
      local m = (n+1)/2
      q1 = median(nums, 1, m-1)
      q3 = median(nums, m+1, n)
    else
      q1 = median(nums, 1, n/2)
      q3 = median(nums, n/2+1, n)
    end
    table.insert(r, "Five-Number Summary")
    table.insert(r, "")
    table.insert(r, "Min    = "..nums[1])
    table.insert(r, "Q1     = "..round(q1))
    table.insert(r, "Median = "..round(med))
    table.insert(r, "Q3     = "..round(q3))
    table.insert(r, "Max    = "..nums[n])
    table.insert(r, "")
    table.insert(r, "IQR = Q3-Q1 = "..round(q3-q1))
    return r
  end
}

tools["stat_linreg"] = {
  inputs = {{"x vals(csv)=", "", "e.g. x vals(csv)"}, {"y vals(csv)=", ""}},
  compute = function(v)
    local r = {}
    local xs = parseList(v[1])
    local ys = parseList(v[2])
    if #xs < 2 or #xs ~= #ys then table.insert(r, "Enter equal-length x,y lists") return r end
    local n = #xs
    local sx,sy,sxy,sx2 = 0,0,0,0
    for i = 1, n do sx=sx+xs[i]; sy=sy+ys[i]; sxy=sxy+xs[i]*ys[i]; sx2=sx2+xs[i]^2 end
    local m = (n*sxy - sx*sy) / (n*sx2 - sx*sx)
    local b = (sy - m*sx) / n
    table.insert(r, "Linear Regression (n="..n..")")
    table.insert(r, "")
    table.insert(r, "y = "..round(m).."x + "..round(b))
    table.insert(r, "Slope m = "..round(m))
    table.insert(r, "Intercept b = "..round(b))
    -- R^2
    local ybar = sy/n
    local sstot, ssres = 0, 0
    for i = 1, n do sstot=sstot+(ys[i]-ybar)^2; ssres=ssres+(ys[i]-(m*xs[i]+b))^2 end
    if sstot > 0 then table.insert(r, "R^2 = "..round(1 - ssres/sstot)) end
    return r
  end
}

-- PROBABILITY TOOLS
local function factorial(n)
  if n <= 1 then return 1 end
  local f = 1
  for i = 2, n do f = f * i end
  return f
end

tools["prob_ncr"] = {
  inputs = {{"n=", "", "e.g. 10"}, {"r=", "", "e.g. 3"}},
  compute = function(v)
    local n, k = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not (n and k) then table.insert(r, "Enter n and r") return r end
    if k > n or k < 0 then table.insert(r, "Need 0 <= r <= n") return r end
    n, k = math.floor(n), math.floor(k)
    local result = factorial(n) / (factorial(k) * factorial(n-k))
    table.insert(r, "Combinations C(n,r)")
    table.insert(r, "(Order DOES NOT matter)")
    table.insert(r, "e.g. picking a committee")
    table.insert(r, "")
    table.insert(r, "C("..n..","..k..") = "..n.."! / ("..k.."! * "..(n-k).."!)")
    table.insert(r, "= "..result)
    return r
  end
}

tools["prob_npr"] = {
  inputs = {{"n=", "", "e.g. 10"}, {"r=", "", "e.g. 3"}},
  compute = function(v)
    local n, k = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not (n and k) then table.insert(r, "Enter n and r") return r end
    if k > n or k < 0 then table.insert(r, "Need 0 <= r <= n") return r end
    n, k = math.floor(n), math.floor(k)
    local result = factorial(n) / factorial(n-k)
    table.insert(r, "Permutations P(n,r)")
    table.insert(r, "(Order MATTERS)")
    table.insert(r, "e.g. passwords, seating")
    table.insert(r, "")
    table.insert(r, "P("..n..","..k..") = "..n.."! / "..(n-k).."!")
    table.insert(r, "= "..result)
    return r
  end
}

tools["prob_basic"] = {
  inputs = {{"Favorable=", "", "e.g. Favorable"}, {"Total=", ""}},
  compute = function(v)
    local fav, tot = tonumber(v[1]), tonumber(v[2])
    local r = {}
    if not (fav and tot) or tot == 0 then table.insert(r, "Enter favorable and total") return r end
    local p = fav / tot
    table.insert(r, "P(event) = favorable / total")
    table.insert(r, "")
    table.insert(r, "P = "..fav.." / "..tot.." = "..round(p))
    table.insert(r, "= "..round(p*100).."%")
    table.insert(r, "")
    table.insert(r, "Odds for = "..fav..":"..(tot-fav))
    table.insert(r, "Odds against = "..(tot-fav)..":"..fav)
    table.insert(r, "")
    table.insert(r, "P(not event) = "..round(1-p))
    return r
  end
}

---------------------------------------------------------------
-- READ CONTENT (Reference Cards)
---------------------------------------------------------------
reads = {}

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
  "[a,b] = {x: a <= x <= b}  closed",
  "[a,b) = {x: a <= x < b}  half-open",
  "(a,b] = {x: a < x <= b}  half-open",
  "",
  "(-inf, a) = {x: x < a}",
  "(a, inf) = {x: x > a}",
  "(-inf, inf) = all reals",
  "",
  "inf always uses ( not [",
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
  "Slope = rise/run = deltay/deltax",
  "Parallel lines: same slope",
  "Perpendicular: m1*m2 = -1",
}

reads["pt_absval"] = {
  "Absolute Value Function",
  "",
  "|x| = x  if x >= 0",
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
  "x^a * x^b = x^(a+b)",
  "x^a / x^b = x^(a-b)",
  "(x^a)^b = x^(a*b)",
  "(xy)^a = x^a * y^a",
  "x^0 = 1",
  "x^(-a) = 1/x^a",
  "x^(1/n) = n-th root of x",
}

reads["log_rules"] = {
  "Logarithm Rules",
  "",
  "log_b(xy) = log_b(x)+log_b(y)",
  "log_b(x/y) = log_b(x)-log_b(y)",
  "log_b(x^n) = n*log_b(x)",
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
  "0 deg: (1, 0)",
  "30 deg: (sqrt3/2, 1/2)",
  "45 deg: (sqrt2/2, sqrt2/2)",
  "60 deg: (1/2, sqrt3/2)",
  "90 deg: (0, 1)",
  "120 deg: (-1/2, sqrt3/2)",
  "135 deg: (-sqrt2/2, sqrt2/2)",
  "150 deg: (-sqrt3/2, 1/2)",
  "180 deg: (-1, 0)",
  "270 deg: (0, -1)",
  "360 deg: (1, 0)",
}

reads["circ_props"] = {
  "Circle Properties & Formulas",
  "",
  "Area = pir^2",
  "Circumference = 2pir = pid",
  "Diameter = 2r",
  "",
  "Arc Length = rtheta (theta in rad)",
  "Sector Area = 1/2r^2theta",
  "",
  "Equation: (x-h)^2+(y-k)^2=r^2",
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
  "sin^2+cos^2 = 1",
}

reads["geo_special_rt"] = {
  "Special Right Triangles",
  "",
  "--- 45-45-90 Triangle ---",
  "Sides: x, x, x*sqrt(2)",
  "Angles: 45, 45, 90",
  "Legs are equal",
  "Hypotenuse = leg * sqrt(2)",
  "",
  "--- 30-60-90 Triangle ---",
  "Sides: x, x*sqrt(3), 2x",
  "Angles: 30, 60, 90",
  "Short leg opposite 30 deg",
  "Long leg = short * sqrt(3)",
  "Hyp = 2 * short leg",
  "",
  "--- Pythagorean Triples ---",
  "3, 4, 5",
  "5, 12, 13",
  "8, 15, 17",
  "7, 24, 25",
}

reads["sat_formulas"] = {
  "SAT Reference Formulas",
  "",
  "--- Given on SAT ---",
  "Circle: A=pir^2  C=2pir",
  "Rectangle: A=lw",
  "Triangle: A=1/2bh",
  "Pythagorean: a^2+b^2=c^2",
  "V(box) = lwh",
  "V(cylinder) = pir^2h",
  "V(sphere) = 4/3pir^3",
  "V(cone) = 1/3pir^2h",
  "V(pyramid) = 1/3lwh",
  "",
  "--- Must Memorize ---",
  "Slope: m=(y2-y1)/(x2-x1)",
  "y=mx+b  (slope-intercept)",
  "Ax+By=C (standard form)",
  "Quadratic: x=(-b+/-sqrt(b^2-4ac))/2a",
  "Vertex: h=-b/2a",
  "Circle: (x-h)^2+(y-k)^2=r^2",
  "sin=opp/hyp cos=adj/hyp",
  "tan=opp/adj",
}

---------------------------------------------------------------
-- RENDERING ENGINE
---------------------------------------------------------------
function on.resize(w, h) W, H = w, h end

function on.paint(gc)
  gc:setColorRGB(255, 255, 255)
  gc:fillRect(0, 0, W, H)

  if state == "splash" then drawSplash(gc)
  elseif state == "tool" then drawTool(gc)
  elseif state == "read" then drawRead(gc)
  end
end

function drawSplash(gc)
  -- Title in green
  gc:setColorRGB(0, 100, 0)
  gc:setFont("sansserif", "b", 20)
  local title = "SAT Calculator"
  local tw = gc:getStringWidth(title)
  gc:drawString(title, (W - tw) / 2, H / 2 - 40)

  -- Website
  gc:setColorRGB(20, 20, 20)
  gc:setFont("sansserif", "b", 14)
  local url = "IvyTutoring.net"
  local uw = gc:getStringWidth(url)
  gc:drawString(url, (W - uw) / 2, H / 2)

  -- Hint
  gc:setColorRGB(140, 140, 140)
  gc:setFont("sansserif", "r", 9)
  local hint = "Select a tool from the menu"
  local hw = gc:getStringWidth(hint)
  gc:drawString(hint, (W - hw) / 2, H - 24)
end

function drawTool(gc)
  local tool = tools[currentTool]
  if not tool then
    gc:setColorRGB(200, 0, 0)
    gc:setFont("sansserif", "b", 12)
    gc:drawString("Tool not found: "..tostring(currentTool), 8, 30)
    return
  end

  local y = 6
  local boxH = 22
  local rowGap = 10

  -- Draw input fields
  for i, inp in ipairs(tool.inputs) do
    local label = inp[1]

    -- Label - left side
    gc:setColorRGB(0, 0, 0)
    gc:setFont("sansserif", "r", 12)
    gc:drawString(label, 8, y + 2)

    -- Calculate input box position
    local lw = gc:getStringWidth(label) + 16
    local boxX = math.max(lw, 100)
    local boxW = W - boxX - 4

    -- Input box fill
    if i == inputSel and not resultScrollMode then
      gc:setColorRGB(240, 255, 240)
    else
      gc:setColorRGB(255, 255, 255)
    end
    gc:fillRect(boxX, y, boxW, boxH)

    -- Input box border - green
    gc:setColorRGB(0, 130, 0)
    if i == inputSel and not resultScrollMode then
      gc:setPen("medium", "smooth")
    else
      gc:setPen("thin", "smooth")
    end
    gc:drawRect(boxX, y, boxW, boxH)

    -- Input text
    gc:setFont("sansserif", "r", 12)
    local val = inputVals[i] or ""
    if val == "" and i == inputSel then
      gc:setColorRGB(150, 150, 150)
      local hint = inp[3] or ("e.g. " .. string.gsub(label, "[=:]%s*$", ""))
      gc:drawString(hint, boxX + 4, y + 2)
    else
      gc:setColorRGB(0, 0, 0)
      gc:drawString(val, boxX + 4, y + 2)
    end

    y = y + boxH + rowGap
  end

  -- Draw results with pretty math
  if #results > 0 then
    local sepY = y + 2
    gc:setColorRGB(0, 130, 0)
    gc:setPen("thin", "smooth")
    gc:drawLine(4, sepY, W - 4, sepY)
    y = sepY + 8

    gc:setColorRGB(0, 0, 0)
    gc:setFont("sansserif", "r", 12)
    local maxTextW = W - 16
    for _, line in ipairs(results) do
      local pretty = prettifyMath(line)
      local wrapped = wrapText(gc, pretty, maxTextW)
      for _, wl in ipairs(wrapped) do
        local drawY = y - scrollY
        if drawY >= sepY + 4 and drawY < H - 6 then
          gc:drawString(wl, 8, drawY)
        end
        y = y + 18
      end
    end

    -- Scroll indicators
    local contentH = #results * 18
    local visibleH = H - sepY - 10
    if contentH - scrollY > visibleH then
      gc:setColorRGB(0, 130, 0)
      gc:setFont("sansserif", "b", 10)
      local arrow = "v"
      local aw = gc:getStringWidth(arrow)
      gc:drawString(arrow, (W - aw) / 2, H - 14)
    end
    if scrollY > 0 then
      gc:setColorRGB(0, 130, 0)
      gc:setFont("sansserif", "b", 10)
      local arrow = "^"
      local aw = gc:getStringWidth(arrow)
      gc:drawString(arrow, (W - aw) / 2, sepY + 2)
    end
  end
end

function drawRead(gc)
  local content = reads[currentTool]
  if not content then return end

  local y = 6
  local maxTextW = W - 16
  for idx, line in ipairs(content) do
    local pretty = prettifyMath(line)
    if idx == 1 then
      -- Title line - bold, green, no wrap needed
      local drawY = y - scrollY
      if drawY >= 0 and drawY < H - 6 then
        gc:setColorRGB(0, 100, 0)
        gc:setFont("sansserif", "b", 14)
        gc:drawString(pretty, 8, drawY)
      end
      y = y + 18
    else
      -- Content lines - prettify and wrap
      gc:setColorRGB(0, 0, 0)
      gc:setFont("sansserif", "r", 12)
      local wrapped = wrapText(gc, pretty, maxTextW)
      for _, wl in ipairs(wrapped) do
        local drawY = y - scrollY
        if drawY >= 0 and drawY < H - 6 then
          gc:drawString(wl, 8, drawY)
        end
        y = y + 18
      end
    end
  end

  -- Scroll indicators
  local contentH = #content * 18
  if contentH - scrollY > H - 10 then
    gc:setColorRGB(0, 130, 0)
    gc:setFont("sansserif", "b", 10)
    local arrow = "v"
    local aw = gc:getStringWidth(arrow)
    gc:drawString(arrow, (W - aw) / 2, H - 14)
  end
  if scrollY > 0 then
    gc:setColorRGB(0, 130, 0)
    gc:setFont("sansserif", "b", 10)
    local arrow = "^"
    local aw = gc:getStringWidth(arrow)
    gc:drawString(arrow, (W - aw) / 2, 2)
  end
end

---------------------------------------------------------------
-- INPUT HANDLING
---------------------------------------------------------------
local function autoCompute()
  if state == "tool" then
    local tool = tools[currentTool]
    if tool then
      -- Only compute if at least one input has content
      local hasInput = false
      local vals = {}
      for i = 1, #tool.inputs do
        vals[i] = inputVals[i] or ""
        if vals[i] ~= "" then hasInput = true end
      end
      if hasInput then
        -- Preprocess all inputs: insert implicit multiplication
        local pVals = {}
        for i = 1, #vals do pVals[i] = prepareInput(vals[i]) end
        local ok, res = pcall(tool.compute, pVals)
        if ok and res then results = res else results = {} end
      else
        results = {}
      end
      scrollY = 0
    end
  end
end

function on.arrowKey(key)
  if state == "tool" then
    if resultScrollMode then
      if key == "down" then scrollY = scrollY + 18
      elseif key == "up" then scrollY = math.max(0, scrollY - 18) end
    else
      local tool = tools[currentTool]
      if tool then
        if key == "up" then
          if inputSel > 1 then inputSel = inputSel - 1
          else scrollY = math.max(0, scrollY - 18) end
        elseif key == "down" then
          if inputSel < #tool.inputs then inputSel = inputSel + 1
          else scrollY = scrollY + 18 end
        end
      end
    end
  elseif state == "read" then
    if key == "down" then scrollY = scrollY + 18
    elseif key == "up" then scrollY = math.max(0, scrollY - 18) end
  end
  platform.window:invalidate()
end

function on.enterKey()
  if state == "tool" then
    if resultScrollMode then
      resultScrollMode = false
      scrollY = 0
    else
      resultScrollMode = true
    end
  end
  platform.window:invalidate()
end

function on.escapeKey()
  if state == "tool" then
    if resultScrollMode then
      resultScrollMode = false
      scrollY = 0
    else
      goHome()
    end
  elseif state == "read" then
    goHome()
  end
  platform.window:invalidate()
end

function on.tabKey()
  if state == "tool" and not resultScrollMode then
    local tool = tools[currentTool]
    if tool then
      inputSel = inputSel + 1
      if inputSel > #tool.inputs then inputSel = 1 end
    end
  end
  platform.window:invalidate()
end

function on.charIn(ch)
  if state == "tool" and not resultScrollMode then
    inputVals[inputSel] = (inputVals[inputSel] or "") .. ch
    autoCompute()
    platform.window:invalidate()
  end
end

function on.backspaceKey()
  if state == "tool" and not resultScrollMode then
    local s = inputVals[inputSel] or ""
    if #s > 0 then inputVals[inputSel] = s:sub(1, -2) end
    autoCompute()
    platform.window:invalidate()
  end
end

function on.deleteKey()
  if state == "tool" and not resultScrollMode then
    inputVals[inputSel] = ""
    autoCompute()
    platform.window:invalidate()
  end
end

function on.mouseDown(x, y)
  if state == "tool" then
    local tool = tools[currentTool]
    if not tool then return end
    local rowY = 6
    local boxH = 22
    local rowGap = 10
    for i = 1, #tool.inputs do
      if y >= rowY and y <= rowY + boxH then
        inputSel = i
        resultScrollMode = false
        platform.window:invalidate()
        return
      end
      rowY = rowY + boxH + rowGap
    end
  elseif state == "splash" then
    -- clicking splash does nothing
  end
end
