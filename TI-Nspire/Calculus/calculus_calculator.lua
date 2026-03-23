---------------------------------------------------------------
-- CALCULUS CALCULATOR for TI-Nspire
-- IvyTutoring.net
---------------------------------------------------------------

-- Desktop/CAS Compatibility Shim
if not platform then
  platform = {window = {invalidate = function() end, setFocus = function() end}}
  toolpalette = {register = function() end, enable = function() end}
end
pcall(function() platform.window:setFocus(true) end)

---------------------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------------------
local W, H = 320, 212

function round(x, dp)
  dp = dp or 4
  if type(x) ~= "number" then return tostring(x) end
  local m = 10^dp
  return math.floor(x * m + 0.5) / m
end

local function gcd(a, b) a,b=math.abs(a),math.abs(b); while b~=0 do a,b=b,a%b end; return a end
local function lcm(a, b) return math.abs(a*b)/gcd(a,b) end

local APPROX = string.char(226, 137, 136)

local function safeEval(expr)
  if math.eval then
    local ok, result = pcall(math.eval, expr)
    if ok and result ~= nil then return tostring(result) end
  end
  return nil
end

local function safeEvalNum(expr)
  local s = safeEval(expr)
  if s then return tonumber(s) end
  return nil
end

local function prepareInput(s)
  s = s:gsub("(%d)(%a)", "%1*%2")
  s = s:gsub("(%a)%(", "%1*(")
  s = s:gsub("%)%(", ")*(")
  s = s:gsub("%)(%a)", ")*%1")
  s = s:gsub("(%d)%(", "%1*(")
  return s
end

local prettyMap = {
  {"sqrt", "\226\136\154"}, {"pi", "\207\128"}, {"theta", "\206\184"},
  {">=", "\226\137\165"}, {"<=", "\226\137\164"}, {"!=", "\226\137\160"},
  {"inf", "\226\136\158"}, {"delta", "\206\148"}, {"alpha", "\206\177"},
  {"beta", "\206\178"}, {"gamma", "\206\179"}, {"sigma", "\207\131"},
  {"epsilon", "\206\181"}, {"lambda", "\206\187"}, {"integral", "\226\136\171"},
  {"->", "\226\134\146"}, {"sum", "\206\163"},
}

function prettifyMath(s)
  if type(s) ~= "string" then return tostring(s) end
  for _, pair in ipairs(prettyMap) do s = s:gsub(pair[1], pair[2]) end
  return s
end

function wrapText(gc, text, maxW)
  if gc:getStringWidth(text) <= maxW then return {text} end
  local lines = {}; local cur = ""
  for word in text:gmatch("%S+") do
    local test = cur == "" and word or (cur .. " " .. word)
    if gc:getStringWidth(test) > maxW and cur ~= "" then
      table.insert(lines, cur); cur = word
    else cur = test end
  end
  if cur ~= "" then table.insert(lines, cur) end
  return lines
end

---------------------------------------------------------------
-- STATE
---------------------------------------------------------------
local state = "splash"
local currentTool = ""
local inputVals = {}
local inputSel = 1
local results = {}
local scrollY = 0
local resultScrollMode = false
local tools = {}
local reads = {}

function goHome()
  state = "splash"; currentTool = ""; inputVals = {}; inputSel = 1
  results = {}; scrollY = 0; resultScrollMode = false
end

function selectTool(id, name)
  currentTool = id; state = "tool"; inputVals = {}; inputSel = 1
  results = {}; scrollY = 0; resultScrollMode = false
  platform.window:invalidate()
end

function selectRead(id, name)
  currentTool = id; state = "read"; scrollY = 0; resultScrollMode = false
  platform.window:invalidate()
end

---------------------------------------------------------------
-- NATIVE TOOLPALETTE MENU
---------------------------------------------------------------
local menu = {
  {"Limits",
    {"Evaluate Limit", function() selectTool("lim_eval", "Limit") end},
    {"One-Sided Limits", function() selectTool("lim_onesided", "One-Sided") end},
    {"Limit at Infinity", function() selectTool("lim_inf", "Lim at Inf") end},
    {"Continuity Test", function() selectTool("lim_continuity", "Continuity") end},
    {"Read: Limit Laws", function() selectRead("read_limits", "Limit Laws") end},
  },
  {"Derivatives",
    {"Derivative", function() selectTool("deriv_basic", "Derivative") end},
    {"n-th Derivative", function() selectTool("deriv_nth", "n-th Deriv") end},
    {"Derivative at a Point", function() selectTool("deriv_point", "d/dx at a") end},
    {"Implicit d/dx", function() selectTool("deriv_implicit", "Implicit") end},
    {"Read: Derivative Rules", function() selectRead("read_derivrules", "Deriv Rules") end},
    {"Read: Trig Derivatives", function() selectRead("read_trigderiv", "Trig Deriv") end},
  },
  {"Applications of Deriv",
    {"Tangent / Normal Line", function() selectTool("app_tangent", "Tangent") end},
    {"Critical Points", function() selectTool("app_critical", "Critical Pts") end},
    {"Inflection Points", function() selectTool("app_inflect", "Inflection") end},
    {"Mean Value Theorem", function() selectTool("app_mvt", "MVT") end},
    {"Linear Approximation", function() selectTool("app_linear", "Lin Approx") end},
    {"Related Rates Helper", function() selectTool("app_related", "Related Rates") end},
    {"Read: Optimization", function() selectRead("read_optimize", "Optimization") end},
  },
  {"Integrals",
    {"Indefinite Integral", function() selectTool("int_indef", "Indef Integ") end},
    {"Definite Integral", function() selectTool("int_def", "Def Integ") end},
    {"u-Substitution", function() selectTool("int_usub", "u-Sub") end},
    {"Integration by Parts", function() selectTool("int_parts", "by Parts") end},
    {"Read: Integration Rules", function() selectRead("read_intrules", "Int Rules") end},
    {"Read: Trig Integrals", function() selectRead("read_trigint", "Trig Int") end},
  },
  {"Applications of Integ",
    {"Area Between Curves", function() selectTool("intapp_area", "Area") end},
    {"Volume: Disk/Washer", function() selectTool("intapp_disk", "Disk/Washer") end},
    {"Volume: Shell Method", function() selectTool("intapp_shell", "Shell") end},
    {"Average Value", function() selectTool("intapp_avg", "Avg Value") end},
    {"Arc Length", function() selectTool("intapp_arclen", "Arc Length") end},
    {"Read: FTC", function() selectRead("read_ftc", "FTC") end},
  },
  {"Series (BC)",
    {"Taylor Polynomial", function() selectTool("ser_taylor", "Taylor") end},
    {"Partial Sum", function() selectTool("ser_partial", "Partial Sum") end},
    {"Geometric Series", function() selectTool("ser_geo", "Geo Series") end},
    {"Power Series", function() selectTool("ser_power", "Power Series") end},
    {"Read: Convergence", function() selectRead("read_converge", "Convergence") end},
  },
  {"Diff Equations",
    {"Solve ODE", function() selectTool("de_solve", "Solve ODE") end},
    {"Euler's Method", function() selectTool("de_euler", "Euler") end},
    {"Separation of Vars", function() selectTool("de_sep", "Sep of Vars") end},
    {"Read: Common DEs", function() selectRead("read_de", "Common DEs") end},
  },
}
toolpalette.register(menu)

---------------------------------------------------------------
-- LIMITS TOOLS
---------------------------------------------------------------
tools["lim_eval"] = {
  inputs = {{"f(x)=", "", "e.g. sin(x)/x"}, {"x ->", "", "e.g. 0"}},
  compute = function(v)
    local r = {}
    local fx, a = v[1], v[2]
    if fx == "" then return r end
    table.insert(r, "--- Limit ---")
    table.insert(r, "lim f(x) as x -> "..a)
    table.insert(r, "f(x) = "..fx)
    table.insert(r, "")
    local lim = safeEval("limit("..fx..",x,"..a..")")
    if lim then table.insert(r, "= "..lim)
    else table.insert(r, "Could not evaluate") end
    return r
  end
}

tools["lim_onesided"] = {
  inputs = {{"f(x)=", "", "e.g. 1/x"}, {"x ->", "", "e.g. 0"}},
  compute = function(v)
    local r = {}
    local fx, a = v[1], v[2]
    if fx == "" then return r end
    table.insert(r, "--- One-Sided Limits ---")
    table.insert(r, "f(x) = "..fx..", x -> "..a)
    table.insert(r, "")
    local lp = safeEval("limit("..fx..",x,"..a..",1)")
    local lm = safeEval("limit("..fx..",x,"..a..",-1)")
    local lb = safeEval("limit("..fx..",x,"..a..")")
    if lm then table.insert(r, "Left  (x->"..a.."^-): "..lm) end
    if lp then table.insert(r, "Right (x->"..a.."^+): "..lp) end
    table.insert(r, "")
    if lb then table.insert(r, "Two-sided: "..lb)
    else table.insert(r, "Two-sided limit DNE") end
    return r
  end
}

tools["lim_inf"] = {
  inputs = {{"f(x)=", "", "e.g. (3x+1)/(x-2)"}},
  compute = function(v)
    local r = {}
    local fx = v[1]
    if fx == "" then return r end
    table.insert(r, "--- Limits at Infinity ---")
    table.insert(r, "f(x) = "..fx)
    table.insert(r, "")
    local lp = safeEval("limit("..fx..",x,inf)")
    local lm = safeEval("limit("..fx..",x,-inf)")
    if lp then table.insert(r, "lim x->+inf: "..lp) end
    if lm then table.insert(r, "lim x->-inf: "..lm) end
    if lp then
      table.insert(r, "")
      table.insert(r, "Horizontal Asymptote:")
      table.insert(r, "y = "..lp)
    end
    return r
  end
}

tools["lim_continuity"] = {
  inputs = {{"f(x)=", "", "e.g. x^2"}, {"at x=", "", "e.g. 2"}},
  compute = function(v)
    local r = {}
    local fx, a = v[1], v[2]
    if fx == "" or a == "" then return r end
    table.insert(r, "--- Continuity Test ---")
    table.insert(r, "f(x) = "..fx.." at x = "..a)
    table.insert(r, "")
    local fa = safeEval("("..fx..")|x="..a)
    local lim = safeEval("limit("..fx..",x,"..a..")")
    table.insert(r, "1) f("..a..") = "..(fa or "undefined"))
    table.insert(r, "2) lim = "..(lim or "DNE"))
    table.insert(r, "")
    if fa and lim and fa == lim then
      table.insert(r, "f("..a..") = lim => CONTINUOUS")
    else
      table.insert(r, "NOT continuous at x = "..a)
    end
    return r
  end
}

---------------------------------------------------------------
-- DERIVATIVES TOOLS
---------------------------------------------------------------
tools["deriv_basic"] = {
  inputs = {{"f(x)=", "", "e.g. x^3+2x"}},
  compute = function(v)
    local r = {}
    local fx = v[1]
    if fx == "" then return r end
    table.insert(r, "--- Derivative ---")
    table.insert(r, "f(x) = "..fx)
    table.insert(r, "")
    local d1 = safeEval("derivative("..fx..",x)")
    if d1 then
      table.insert(r, "f'(x) = "..d1)
      local d1s = safeEval("simplify("..d1..")")
      if d1s and d1s ~= d1 then table.insert(r, "     = "..d1s) end
    end
    local d2 = safeEval("derivative("..fx..",x,2)")
    if d2 then
      table.insert(r, "")
      table.insert(r, "f''(x) = "..d2)
    end
    return r
  end
}

tools["deriv_nth"] = {
  inputs = {{"f(x)=", "", "e.g. sin(x)"}, {"n=", "", "e.g. 3"}},
  compute = function(v)
    local r = {}
    local fx = v[1]
    local n = tonumber(v[2])
    if fx == "" or not n then return r end
    table.insert(r, "--- n-th Derivative ---")
    table.insert(r, "f(x) = "..fx)
    table.insert(r, "")
    for i = 1, math.min(n, 6) do
      local di = safeEval("derivative("..fx..",x,"..i..")")
      if di then
        local label = "f"..string.rep("'", i).."(x)"
        table.insert(r, label.." = "..di)
      end
    end
    return r
  end
}

tools["deriv_point"] = {
  inputs = {{"f(x)=", "", "e.g. x^2+1"}, {"at x=", "", "e.g. 3"}},
  compute = function(v)
    local r = {}
    local fx, a = v[1], v[2]
    if fx == "" or a == "" then return r end
    table.insert(r, "--- Derivative at Point ---")
    table.insert(r, "f(x) = "..fx..", x = "..a)
    table.insert(r, "")
    local fa = safeEval("("..fx..")|x="..a)
    if fa then table.insert(r, "f("..a..") = "..fa) end
    local d1 = safeEval("derivative("..fx..",x)")
    if d1 then
      table.insert(r, "f'(x) = "..d1)
      local d1a = safeEval("("..d1..")|x="..a)
      if d1a then
        table.insert(r, "f'("..a..") = "..d1a)
        table.insert(r, "")
        table.insert(r, "Slope at x="..a..": "..d1a)
      end
    end
    return r
  end
}

tools["deriv_implicit"] = {
  inputs = {{"Equation=", "", "e.g. x^2+y^2=25"}},
  compute = function(v)
    local r = {}
    local eq = v[1]
    if eq == "" then return r end
    table.insert(r, "--- Implicit Differentiation ---")
    table.insert(r, eq)
    table.insert(r, "")
    local sol = safeEval("impDif("..eq..",x,y)")
    if sol then
      table.insert(r, "dy/dx = "..sol)
    else
      table.insert(r, "Use CAS: impDif("..eq..",x,y)")
    end
    return r
  end
}

---------------------------------------------------------------
-- APPLICATIONS OF DERIVATIVES
---------------------------------------------------------------
tools["app_tangent"] = {
  inputs = {{"f(x)=", "", "e.g. x^2"}, {"at x=", "", "e.g. 2"}},
  compute = function(v)
    local r = {}
    local fx, a = v[1], v[2]
    if fx == "" or a == "" then return r end
    table.insert(r, "--- Tangent & Normal ---")
    table.insert(r, "f(x) = "..fx.." at x = "..a)
    table.insert(r, "")
    local fa = safeEval("("..fx..")|x="..a)
    local d1 = safeEval("derivative("..fx..",x)")
    local m
    if d1 then m = safeEval("("..d1..")|x="..a) end
    if fa and m then
      table.insert(r, "Point: ("..a..", "..fa..")")
      table.insert(r, "Slope m = "..m)
      table.insert(r, "")
      table.insert(r, "Tangent Line:")
      table.insert(r, "y - "..fa.." = "..m.."(x - "..a..")")
      local simp = safeEval("simplify("..m.."*(x-"..a..")+"..fa..")")
      if simp then table.insert(r, "y = "..simp) end
      table.insert(r, "")
      local mn = tonumber(m)
      if mn and mn ~= 0 then
        local nm = round(-1/mn)
        table.insert(r, "Normal Line:")
        table.insert(r, "slope = -1/m = "..nm)
      end
    end
    return r
  end
}

tools["app_critical"] = {
  inputs = {{"f(x)=", "", "e.g. x^3-3x"}},
  compute = function(v)
    local r = {}
    local fx = v[1]
    if fx == "" then return r end
    table.insert(r, "--- Critical Points ---")
    table.insert(r, "f(x) = "..fx)
    table.insert(r, "")
    local d1 = safeEval("derivative("..fx..",x)")
    if d1 then
      table.insert(r, "f'(x) = "..d1)
      local zeros = safeEval("zeros("..d1..",x)")
      if zeros then
        table.insert(r, "f'(x) = 0 at x = "..zeros)
        table.insert(r, "")
        local d2 = safeEval("derivative("..fx..",x,2)")
        if d2 then
          table.insert(r, "f''(x) = "..d2)
          table.insert(r, "")
          table.insert(r, "2nd Derivative Test:")
          -- Try to evaluate at each critical point
          local pts = zeros:gsub("[{}]","")
          for pt in pts:gmatch("[^,]+") do
            local p = pt:match("^%s*(.-)%s*$")
            local d2v = safeEval("("..d2..")|x="..p)
            local fv = safeEval("("..fx..")|x="..p)
            if d2v and fv then
              local class = "inconclusive"
              local d2n = tonumber(d2v)
              if d2n and d2n > 0 then class = "LOCAL MIN"
              elseif d2n and d2n < 0 then class = "LOCAL MAX" end
              table.insert(r, "x="..p..": f="..fv..", f''="..d2v.." -> "..class)
            end
          end
        end
      end
    end
    return r
  end
}

tools["app_inflect"] = {
  inputs = {{"f(x)=", "", "e.g. x^3-3x"}},
  compute = function(v)
    local r = {}
    local fx = v[1]
    if fx == "" then return r end
    table.insert(r, "--- Inflection Points ---")
    table.insert(r, "f(x) = "..fx)
    table.insert(r, "")
    local d2 = safeEval("derivative("..fx..",x,2)")
    if d2 then
      table.insert(r, "f''(x) = "..d2)
      local zeros = safeEval("zeros("..d2..",x)")
      if zeros then
        table.insert(r, "f''(x) = 0 at x = "..zeros)
        table.insert(r, "")
        local pts = zeros:gsub("[{}]","")
        for pt in pts:gmatch("[^,]+") do
          local p = pt:match("^%s*(.-)%s*$")
          local fv = safeEval("("..fx..")|x="..p)
          if fv then table.insert(r, "Inflection: ("..p..", "..fv..")") end
        end
      end
    end
    return r
  end
}

tools["app_mvt"] = {
  inputs = {{"f(x)=", "", "e.g. x^2"}, {"a=", "", "e.g. 1"}, {"b=", "", "e.g. 3"}},
  compute = function(v)
    local r = {}
    local fx = v[1]
    local a, b = v[2], v[3]
    if fx == "" or a == "" or b == "" then return r end
    table.insert(r, "--- Mean Value Theorem ---")
    table.insert(r, "f(x) = "..fx.." on ["..a..", "..b.."]")
    table.insert(r, "")
    local fa = safeEval("("..fx..")|x="..a)
    local fb = safeEval("("..fx..")|x="..b)
    if fa and fb then
      local an, bn = tonumber(a), tonumber(b)
      local fan, fbn = tonumber(fa), tonumber(fb)
      if an and bn and fan and fbn then
        local avg = round((fbn - fan) / (bn - an))
        table.insert(r, "f("..a..") = "..fa)
        table.insert(r, "f("..b..") = "..fb)
        table.insert(r, "")
        table.insert(r, "Avg rate = [f(b)-f(a)]/(b-a)")
        table.insert(r, "= "..avg)
        table.insert(r, "")
        local d1 = safeEval("derivative("..fx..",x)")
        if d1 then
          table.insert(r, "f'(x) = "..d1)
          local c = safeEval("solve("..d1.."="..avg..",x)")
          if c then
            table.insert(r, "f'(c) = "..avg.." when:")
            table.insert(r, c)
          end
        end
      end
    end
    return r
  end
}

tools["app_linear"] = {
  inputs = {{"f(x)=", "", "e.g. sqrt(x)"}, {"at x=", "", "e.g. 4"}, {"estimate x=", "", "e.g. 4.1"}},
  compute = function(v)
    local r = {}
    local fx, a, est = v[1], v[2], v[3]
    if fx == "" or a == "" then return r end
    table.insert(r, "--- Linear Approximation ---")
    table.insert(r, "L(x) = f(a) + f'(a)(x-a)")
    table.insert(r, "")
    local fa = safeEval("("..fx..")|x="..a)
    local d1 = safeEval("derivative("..fx..",x)")
    local d1a
    if d1 then d1a = safeEval("("..d1..")|x="..a) end
    if fa and d1a then
      table.insert(r, "f("..a..") = "..fa)
      table.insert(r, "f'("..a..") = "..d1a)
      table.insert(r, "")
      table.insert(r, "L(x) = "..fa.." + "..d1a.."(x - "..a..")")
      if est and est ~= "" then
        local Lest = safeEval(fa.."+"..d1a.."*("..est.."-"..a..")")
        local exact = safeEval("("..fx..")|x="..est)
        if Lest then table.insert(r, ""); table.insert(r, "L("..est..") "..APPROX.." "..Lest) end
        if exact then table.insert(r, "f("..est..") = "..exact) end
      end
    end
    return r
  end
}

tools["app_related"] = {
  inputs = {{"Equation=", "", "e.g. x^2+y^2=25"}, {"dx/dt=", "", "e.g. 3"}, {"at x=", "", "e.g. 3"}},
  compute = function(v)
    local r = {}
    local eq, dxdt, x0 = v[1], v[2], v[3]
    if eq == "" then return r end
    table.insert(r, "--- Related Rates ---")
    table.insert(r, eq)
    table.insert(r, "")
    table.insert(r, "Differentiate implicitly")
    table.insert(r, "w.r.t. t using CAS:")
    local imp = safeEval("impDif("..eq..",x,y)")
    if imp then
      table.insert(r, "dy/dx = "..imp)
      table.insert(r, "")
      table.insert(r, "dy/dt = (dy/dx)(dx/dt)")
      if dxdt ~= "" and x0 ~= "" then
        table.insert(r, "dx/dt = "..dxdt.." at x = "..x0)
      end
    end
    return r
  end
}

---------------------------------------------------------------
-- INTEGRALS TOOLS
---------------------------------------------------------------
tools["int_indef"] = {
  inputs = {{"f(x)=", "", "e.g. x^2+3x"}},
  compute = function(v)
    local r = {}
    local fx = v[1]
    if fx == "" then return r end
    table.insert(r, "--- Indefinite Integral ---")
    table.insert(r, "integral "..fx.." dx")
    table.insert(r, "")
    local result = safeEval("integral("..fx..",x)")
    if result then table.insert(r, "= "..result.." + C")
    else table.insert(r, "Could not integrate") end
    return r
  end
}

tools["int_def"] = {
  inputs = {{"f(x)=", "", "e.g. x^2"}, {"a=", "", "e.g. 0"}, {"b=", "", "e.g. 3"}},
  compute = function(v)
    local r = {}
    local fx, a, b = v[1], v[2], v[3]
    if fx == "" or a == "" or b == "" then return r end
    table.insert(r, "--- Definite Integral ---")
    table.insert(r, "integral "..fx.." dx from "..a.." to "..b)
    table.insert(r, "")
    local exact = safeEval("integral("..fx..",x,"..a..","..b..")")
    if exact then table.insert(r, "Exact: "..exact) end
    local approx = safeEval("approx(integral("..fx..",x,"..a..","..b.."))")
    if approx then table.insert(r, "Decimal "..APPROX.." "..approx) end
    local anti = safeEval("integral("..fx..",x)")
    if anti then table.insert(r, ""); table.insert(r, "Antiderivative: "..anti) end
    return r
  end
}

tools["int_usub"] = {
  inputs = {{"f(x)=", "", "e.g. 2x*cos(x^2)"}, {"u=", "", "e.g. x^2"}},
  compute = function(v)
    local r = {}
    local fx, u = v[1], v[2]
    if fx == "" then return r end
    table.insert(r, "--- u-Substitution ---")
    table.insert(r, "integral "..fx.." dx")
    table.insert(r, "")
    if u ~= "" then
      local du = safeEval("derivative("..u..",x)")
      if du then
        table.insert(r, "Let u = "..u)
        table.insert(r, "du/dx = "..du)
        table.insert(r, "du = ("..du..")dx")
      end
    end
    table.insert(r, "")
    local result = safeEval("integral("..fx..",x)")
    if result then table.insert(r, "Result: "..result.." + C") end
    return r
  end
}

tools["int_parts"] = {
  inputs = {{"f(x)=", "", "e.g. x*e^x"}, {"u=", "", "e.g. x"}, {"dv=", "", "e.g. e^x"}},
  compute = function(v)
    local r = {}
    local fx, u, dv = v[1], v[2], v[3]
    if fx == "" then return r end
    table.insert(r, "--- Integration by Parts ---")
    table.insert(r, "integral u dv = uv - integral v du")
    table.insert(r, "")
    if u ~= "" and dv ~= "" then
      local du = safeEval("derivative("..u..",x)")
      local vv = safeEval("integral("..dv..",x)")
      if du then table.insert(r, "u = "..u.."  ->  du = ("..du..")dx") end
      if vv then table.insert(r, "dv = ("..dv..")dx  ->  v = "..vv) end
    end
    table.insert(r, "")
    local result = safeEval("integral("..fx..",x)")
    if result then table.insert(r, "Result: "..result.." + C") end
    return r
  end
}

---------------------------------------------------------------
-- APPLICATIONS OF INTEGRALS
---------------------------------------------------------------
tools["intapp_area"] = {
  inputs = {{"f(x)=", "", "e.g. x^2"}, {"g(x)=", "", "e.g. x"}, {"a=", "", "e.g. 0"}, {"b=", "", "e.g. 1"}},
  compute = function(v)
    local r = {}
    local fx, gx, a, b = v[1], v[2], v[3], v[4]
    if fx == "" or gx == "" or a == "" or b == "" then return r end
    table.insert(r, "--- Area Between Curves ---")
    table.insert(r, "f(x) = "..fx..", g(x) = "..gx)
    table.insert(r, "on ["..a..", "..b.."]")
    table.insert(r, "")
    local area = safeEval("integral(abs(("..fx..")-("..gx..")),x,"..a..","..b..")")
    if area then table.insert(r, "Area = "..area) end
    local ap = safeEval("approx(integral(abs(("..fx..")-("..gx..")),x,"..a..","..b.."))")
    if ap then table.insert(r, APPROX.." "..ap) end
    return r
  end
}

tools["intapp_disk"] = {
  inputs = {{"R(x)=", "", "outer, e.g. sqrt(x)"}, {"r(x)=", "", "inner, e.g. 0"}, {"a=", "", "e.g. 0"}, {"b=", "", "e.g. 4"}},
  compute = function(v)
    local r = {}
    local R, ri, a, b = v[1], v[2], v[3], v[4]
    if R == "" or a == "" or b == "" then return r end
    table.insert(r, "--- Volume: Disk/Washer ---")
    table.insert(r, "V = pi * integral [R(x)^2 - r(x)^2] dx")
    table.insert(r, "")
    local inner = (ri ~= "" and ri ~= "0") and ri or nil
    local expr = inner and ("(("..R..")^2-("..inner..")^2)") or ("("..R..")^2")
    local vol = safeEval("pi*integral("..expr..",x,"..a..","..b..")")
    if vol then table.insert(r, "V = "..vol) end
    local ap = safeEval("approx(pi*integral("..expr..",x,"..a..","..b.."))")
    if ap then table.insert(r, APPROX.." "..ap) end
    return r
  end
}

tools["intapp_shell"] = {
  inputs = {{"f(x)=", "", "e.g. x^2"}, {"a=", "", "e.g. 0"}, {"b=", "", "e.g. 2"}},
  compute = function(v)
    local r = {}
    local fx, a, b = v[1], v[2], v[3]
    if fx == "" or a == "" or b == "" then return r end
    table.insert(r, "--- Volume: Shell Method ---")
    table.insert(r, "V = 2pi * integral x*f(x) dx")
    table.insert(r, "")
    local vol = safeEval("2*pi*integral(x*("..fx.."),x,"..a..","..b..")")
    if vol then table.insert(r, "V = "..vol) end
    local ap = safeEval("approx(2*pi*integral(x*("..fx.."),x,"..a..","..b.."))")
    if ap then table.insert(r, APPROX.." "..ap) end
    return r
  end
}

tools["intapp_avg"] = {
  inputs = {{"f(x)=", "", "e.g. x^2"}, {"a=", "", "e.g. 0"}, {"b=", "", "e.g. 3"}},
  compute = function(v)
    local r = {}
    local fx, a, b = v[1], v[2], v[3]
    if fx == "" or a == "" or b == "" then return r end
    table.insert(r, "--- Average Value ---")
    table.insert(r, "f_avg = 1/(b-a) * integral f dx")
    table.insert(r, "")
    local intg = safeEval("integral("..fx..",x,"..a..","..b..")")
    if intg then
      table.insert(r, "integral = "..intg)
      local avg = safeEval("("..intg..")/("..b.."-"..a..")")
      if avg then table.insert(r, "f_avg = "..avg) end
      local ap = safeEval("approx(("..intg..")/("..b.."-"..a.."))")
      if ap then table.insert(r, APPROX.." "..ap) end
    end
    return r
  end
}

tools["intapp_arclen"] = {
  inputs = {{"f(x)=", "", "e.g. x^2"}, {"a=", "", "e.g. 0"}, {"b=", "", "e.g. 1"}},
  compute = function(v)
    local r = {}
    local fx, a, b = v[1], v[2], v[3]
    if fx == "" or a == "" or b == "" then return r end
    table.insert(r, "--- Arc Length ---")
    table.insert(r, "L = integral sqrt(1+[f'(x)]^2) dx")
    table.insert(r, "")
    local d1 = safeEval("derivative("..fx..",x)")
    if d1 then
      table.insert(r, "f'(x) = "..d1)
      local len = safeEval("integral(sqrt(1+("..d1..")^2),x,"..a..","..b..")")
      if len then table.insert(r, "L = "..len) end
      local ap = safeEval("approx(integral(sqrt(1+("..d1..")^2),x,"..a..","..b.."))")
      if ap then table.insert(r, APPROX.." "..ap) end
    end
    return r
  end
}

---------------------------------------------------------------
-- SERIES TOOLS (BC)
---------------------------------------------------------------
tools["ser_taylor"] = {
  inputs = {{"f(x)=", "", "e.g. e^x"}, {"about a=", "", "e.g. 0"}, {"order=", "", "e.g. 5"}},
  compute = function(v)
    local r = {}
    local fx, a = v[1], v[2]
    local n = tonumber(v[3])
    if fx == "" or not n then return r end
    if a == "" then a = "0" end
    table.insert(r, "--- Taylor Polynomial ---")
    table.insert(r, "f(x) = "..fx.." about a = "..a)
    table.insert(r, "")
    local taylor = safeEval("taylor("..fx..",x,"..a..","..n..")")
    if taylor then
      table.insert(r, "P"..n.."(x) = "..taylor)
    end
    return r
  end
}

tools["ser_partial"] = {
  inputs = {{"a(n)=", "", "e.g. 1/n^2"}, {"from n=", "", "e.g. 1"}, {"to n=", "", "e.g. 100"}},
  compute = function(v)
    local r = {}
    local expr = v[1]
    local a, b = tonumber(v[2]), tonumber(v[3])
    if expr == "" or not a or not b then return r end
    table.insert(r, "--- Partial Sum ---")
    table.insert(r, "Sum a(n) from n="..a.." to "..b)
    table.insert(r, "a(n) = "..expr)
    table.insert(r, "")
    local sumexpr = safeEval("sum("..expr..",n,"..a..","..b..")")
    if sumexpr then
      table.insert(r, "S = "..sumexpr)
      local ap = safeEval("approx(sum("..expr..",n,"..a..","..b.."))")
      if ap then table.insert(r, APPROX.." "..ap) end
    end
    return r
  end
}

tools["ser_geo"] = {
  inputs = {{"a (first)=", "", "e.g. 1"}, {"r (ratio)=", "", "e.g. 0.5"}, {"n terms=", "", "e.g. 10"}},
  compute = function(v)
    local r = {}
    local a, ratio, n = tonumber(v[1]), tonumber(v[2]), tonumber(v[3])
    if not a or not ratio then return r end
    table.insert(r, "--- Geometric Series ---")
    table.insert(r, "a = "..a..", r = "..ratio)
    table.insert(r, "")
    if n then
      local sn = a * (1 - ratio^n) / (1 - ratio)
      table.insert(r, "S("..n..") = a(1-r^n)/(1-r)")
      table.insert(r, "= "..round(sn))
    end
    if math.abs(ratio) < 1 then
      table.insert(r, "")
      table.insert(r, "Converges (|r| < 1)")
      table.insert(r, "S(inf) = a/(1-r) = "..round(a/(1-ratio)))
    else
      table.insert(r, ""); table.insert(r, "Diverges (|r| >= 1)")
    end
    return r
  end
}

tools["ser_power"] = {
  inputs = {{"f(x)=", "", "e.g. 1/(1-x)"}, {"about a=", "", "e.g. 0"}},
  compute = function(v)
    local r = {}
    local fx, a = v[1], v[2]
    if fx == "" then return r end
    if a == "" then a = "0" end
    table.insert(r, "--- Power Series ---")
    table.insert(r, "f(x) = "..fx)
    table.insert(r, "")
    local taylor = safeEval("taylor("..fx..",x,"..a..",6)")
    if taylor then
      table.insert(r, "Series (6 terms):")
      table.insert(r, taylor.." + ...")
    end
    return r
  end
}

---------------------------------------------------------------
-- DIFFERENTIAL EQUATIONS
---------------------------------------------------------------
tools["de_solve"] = {
  inputs = {{"ODE=", "", "e.g. y'=2x"}, {"IC: y(x0)=y0", "", "e.g. y(0)=1"}},
  compute = function(v)
    local r = {}
    local ode, ic = v[1], v[2]
    if ode == "" then return r end
    table.insert(r, "--- Solve ODE ---")
    table.insert(r, ode)
    table.insert(r, "")
    local sol
    if ic ~= "" then
      sol = safeEval("deSolve("..ode.." and "..ic..",x,y)")
    else
      sol = safeEval("deSolve("..ode..",x,y)")
    end
    if sol then table.insert(r, "Solution:"); table.insert(r, sol)
    else table.insert(r, "Use CAS: deSolve(ode,x,y)") end
    return r
  end
}

tools["de_euler"] = {
  inputs = {{"dy/dx=", "", "e.g. x+y"}, {"x0=", "", "e.g. 0"}, {"y0=", "", "e.g. 1"}, {"h=", "", "e.g. 0.1"}, {"steps=", "", "e.g. 5"}},
  compute = function(v)
    local r = {}
    local expr = v[1]
    local x0, y0 = tonumber(v[2]), tonumber(v[3])
    local h, steps = tonumber(v[4]), tonumber(v[5])
    if expr == "" or not x0 or not y0 or not h or not steps then return r end
    table.insert(r, "--- Euler's Method ---")
    table.insert(r, "dy/dx = "..expr)
    table.insert(r, "h = "..h..", start ("..x0..", "..y0..")")
    table.insert(r, "")
    local x, y = x0, y0
    for i = 1, steps do
      local slope = safeEvalNum(expr.."|x="..x.."|y="..y)
      if not slope then break end
      table.insert(r, "("..round(x,4)..", "..round(y,4)..") m="..round(slope,4))
      y = y + h * slope
      x = x + h
    end
    table.insert(r, "("..round(x,4)..", "..round(y,4)..")")
    table.insert(r, "")
    table.insert(r, "Final: y("..round(x,4)..") "..APPROX.." "..round(y,4))
    return r
  end
}

tools["de_sep"] = {
  inputs = {{"dy/dx=", "", "e.g. y*x"}},
  compute = function(v)
    local r = {}
    local expr = v[1]
    if expr == "" then return r end
    table.insert(r, "--- Separation of Variables ---")
    table.insert(r, "dy/dx = "..expr)
    table.insert(r, "")
    local sol = safeEval("deSolve(y'="..expr..",x,y)")
    if sol then table.insert(r, "Solution:"); table.insert(r, sol)
    else table.insert(r, "Use CAS: deSolve(y'="..expr..",x,y)") end
    return r
  end
}

---------------------------------------------------------------
-- READ (REFERENCE) CARDS
---------------------------------------------------------------
reads["read_limits"] = {
  "LIMIT LAWS",
  "",
  "Sum: lim[f+g] = lim f + lim g",
  "Product: lim[fg] = (lim f)(lim g)",
  "Quotient: lim[f/g] = lim f / lim g",
  "  (if lim g != 0)",
  "Constant: lim[cf] = c * lim f",
  "Power: lim[f^n] = (lim f)^n",
  "",
  "SQUEEZE THEOREM:",
  "If g(x) <= f(x) <= h(x) near a",
  "and lim g = lim h = L, then lim f = L",
  "",
  "L'HOPITAL'S RULE:",
  "If lim f/g = 0/0 or inf/inf, then",
  "lim f/g = lim f'/g' (if exists)",
  "",
  "COMMON LIMITS:",
  "lim sin(x)/x = 1 as x->0",
  "lim (1-cos(x))/x = 0 as x->0",
  "lim (1+1/n)^n = e as n->inf",
  "lim e^x = inf as x->inf",
  "lim e^x = 0 as x->-inf",
  "lim ln(x) = -inf as x->0+",
}

reads["read_derivrules"] = {
  "DERIVATIVE RULES",
  "",
  "Power: d/dx[x^n] = n*x^(n-1)",
  "Constant: d/dx[c] = 0",
  "Sum: d/dx[f+g] = f' + g'",
  "Const Mult: d/dx[cf] = c*f'",
  "",
  "PRODUCT RULE:",
  "d/dx[fg] = f'g + fg'",
  "",
  "QUOTIENT RULE:",
  "d/dx[f/g] = (f'g - fg')/g^2",
  "",
  "CHAIN RULE:",
  "d/dx[f(g(x))] = f'(g(x))*g'(x)",
  "",
  "EXPONENTIAL & LOG:",
  "d/dx[e^x] = e^x",
  "d/dx[a^x] = a^x * ln(a)",
  "d/dx[ln(x)] = 1/x",
  "d/dx[log_a(x)] = 1/(x*ln(a))",
}

reads["read_trigderiv"] = {
  "TRIG DERIVATIVES",
  "",
  "d/dx[sin(x)] = cos(x)",
  "d/dx[cos(x)] = -sin(x)",
  "d/dx[tan(x)] = sec^2(x)",
  "d/dx[cot(x)] = -csc^2(x)",
  "d/dx[sec(x)] = sec(x)tan(x)",
  "d/dx[csc(x)] = -csc(x)cot(x)",
  "",
  "INVERSE TRIG:",
  "d/dx[arcsin(x)] = 1/sqrt(1-x^2)",
  "d/dx[arccos(x)] = -1/sqrt(1-x^2)",
  "d/dx[arctan(x)] = 1/(1+x^2)",
}

reads["read_optimize"] = {
  "OPTIMIZATION STEPS",
  "",
  "1. Draw a diagram (if applicable)",
  "2. Identify: what to maximize/",
  "   minimize, constraints",
  "3. Write the objective function",
  "4. Use constraint to reduce to 1",
  "   variable",
  "5. Find f'(x) = 0 (critical pts)",
  "6. Use 2nd deriv test or endpoints",
  "   to verify max/min",
  "7. Answer the original question",
  "",
  "Closed interval: check endpoints!",
  "Open interval: use 2nd deriv test",
}

reads["read_intrules"] = {
  "INTEGRATION RULES",
  "",
  "Power: int x^n dx = x^(n+1)/(n+1)+C",
  "  (n != -1)",
  "int 1/x dx = ln|x| + C",
  "int e^x dx = e^x + C",
  "int a^x dx = a^x/ln(a) + C",
  "",
  "TRIG:",
  "int sin(x) dx = -cos(x) + C",
  "int cos(x) dx = sin(x) + C",
  "int sec^2(x) dx = tan(x) + C",
  "int csc^2(x) dx = -cot(x) + C",
  "int sec(x)tan(x) dx = sec(x) + C",
  "int csc(x)cot(x) dx = -csc(x)+C",
  "",
  "u-SUB: int f(g(x))g'(x)dx",
  "  Let u=g(x), du=g'(x)dx",
  "",
  "BY PARTS: int u dv = uv - int v du",
  "  LIATE: Log, Inv Trig, Alg,",
  "         Trig, Exp",
}

reads["read_trigint"] = {
  "TRIG INTEGRALS",
  "",
  "int tan(x) dx = -ln|cos(x)| + C",
  "int cot(x) dx = ln|sin(x)| + C",
  "int sec(x) dx = ln|sec(x)+tan(x)|+C",
  "int csc(x) dx = -ln|csc(x)+cot(x)|+C",
  "",
  "IDENTITIES FOR INTEGRATION:",
  "sin^2(x) = (1-cos(2x))/2",
  "cos^2(x) = (1+cos(2x))/2",
  "sin(x)cos(x) = sin(2x)/2",
  "",
  "TRIG SUB:",
  "sqrt(a^2-x^2): x = a*sin(t)",
  "sqrt(a^2+x^2): x = a*tan(t)",
  "sqrt(x^2-a^2): x = a*sec(t)",
}

reads["read_ftc"] = {
  "FUNDAMENTAL THEOREM OF CALCULUS",
  "",
  "FTC Part 1:",
  "  If F(x) = integral[a to x] f(t)dt",
  "  then F'(x) = f(x)",
  "",
  "  With chain rule:",
  "  d/dx int[a to g(x)] f(t)dt",
  "  = f(g(x)) * g'(x)",
  "",
  "FTC Part 2:",
  "  integral[a to b] f(x)dx",
  "  = F(b) - F(a)",
  "  where F'(x) = f(x)",
  "",
  "MEAN VALUE THEOREM (Integrals):",
  "  f(c) = 1/(b-a) * int[a,b] f(x)dx",
  "  for some c in [a,b]",
}

reads["read_converge"] = {
  "CONVERGENCE TESTS (BC)",
  "",
  "1) n-th TERM (Divergence):",
  "   If lim a_n != 0, diverges",
  "",
  "2) GEOMETRIC: |r| < 1 converges",
  "   Sum = a/(1-r)",
  "",
  "3) p-SERIES: 1/n^p",
  "   Converges if p > 1",
  "",
  "4) INTEGRAL TEST:",
  "   Sum ~ integral (both converge",
  "   or both diverge)",
  "",
  "5) COMPARISON:",
  "   a_n <= b_n, Sum b_n conv =>",
  "   Sum a_n conv",
  "",
  "6) LIMIT COMPARISON:",
  "   lim a_n/b_n = L (finite, >0)",
  "   => both converge or diverge",
  "",
  "7) RATIO TEST:",
  "   lim |a_(n+1)/a_n| < 1 => conv",
  "   > 1 => div, = 1 => inconclusive",
  "",
  "8) ALTERNATING SERIES:",
  "   |a_n| decreasing & lim=0 => conv",
}

reads["read_de"] = {
  "COMMON DIFFERENTIAL EQUATIONS",
  "",
  "SEPARABLE: dy/dx = f(x)*g(y)",
  "  Separate: dy/g(y) = f(x)dx",
  "  Integrate both sides",
  "",
  "LINEAR 1st ORDER: y' + P(x)y = Q(x)",
  "  IF: mu = e^(int P(x)dx)",
  "  y = (1/mu) * int mu*Q(x) dx",
  "",
  "EXPONENTIAL GROWTH/DECAY:",
  "  dy/dt = ky",
  "  y = y_0 * e^(kt)",
  "  k > 0: growth, k < 0: decay",
  "",
  "LOGISTIC:",
  "  dy/dt = ky(1 - y/L)",
  "  y = L/(1 + Ae^(-kt))",
  "  L = carrying capacity",
  "",
  "SLOPE FIELDS:",
  "  Plot (x,y) -> dy/dx at each pt",
  "  Solution curves follow field",
}

---------------------------------------------------------------
-- RENDERING ENGINE
---------------------------------------------------------------
function drawSplash(gc)
  gc:setFont("sansserif", "b", 12)
  gc:setColorRGB(0, 100, 0)
  gc:drawString("CALCULUS", W/2 - gc:getStringWidth("CALCULUS")/2, 55)
  gc:setFont("sansserif", "r", 10)
  gc:drawString("Calculator", W/2 - gc:getStringWidth("Calculator")/2, 75)
  gc:setColorRGB(80,80,80)
  gc:setFont("sansserif", "r", 9)
  local lines = {
    "Use Menu button to select a tool.",
    "Enter values and press Enter.",
    "",
    "Covers: Limits, Derivatives,",
    "Integrals, Series, Diff Eq",
    "",
    "IvyTutoring.net"
  }
  for i, l in ipairs(lines) do
    gc:drawString(l, W/2 - gc:getStringWidth(l)/2, 95 + i*14)
  end
end

function drawTool(gc)
  local t = tools[currentTool]
  if not t then return end
  local y = 4
  gc:setFont("sansserif", "b", 9)
  gc:setColorRGB(0, 100, 0)
  gc:drawString(currentTool, 4, y); y = y + 14

  gc:setFont("sansserif", "r", 9)
  gc:setColorRGB(0,0,0)
  for i, inp in ipairs(t.inputs) do
    local label = inp[1]
    local val = inputVals[i] or ""
    if i == inputSel then
      gc:setColorRGB(0,0,180)
      gc:drawString("> "..label..val.."_", 4, y)
    else
      gc:setColorRGB(0,0,0)
      gc:drawString("  "..label..val, 4, y)
    end
    y = y + 13
  end
  y = y + 4

  if #results > 0 then
    gc:setColorRGB(0,100,0)
    gc:drawLine(4, y, W-4, y); y = y + 6
    local startIdx = scrollY + 1
    for i = startIdx, #results do
      if y > H - 4 then break end
      gc:setColorRGB(0,0,0)
      local line = prettifyMath(results[i])
      if line:sub(1,3) == "---" then
        gc:setFont("sansserif", "b", 9)
        gc:setColorRGB(0,100,0)
        line = line:gsub("%-%-%-", "")
      elseif line == "" then
        y = y + 4; gc:setFont("sansserif", "r", 9)
      else
        gc:setFont("sansserif", "r", 9)
        gc:setColorRGB(0,0,0)
      end
      local wrapped = wrapText(gc, line, W-8)
      for _, wl in ipairs(wrapped) do
        if y > H - 4 then break end
        gc:drawString(wl, 6, y); y = y + 12
      end
    end
  end
end

function drawRead(gc)
  local rd = reads[currentTool]
  if not rd then return end
  gc:setFont("sansserif", "b", 9)
  gc:setColorRGB(0,100,0)
  gc:drawString(rd[1], 4, 4)
  gc:setFont("sansserif", "r", 9)
  gc:setColorRGB(0,0,0)
  local y = 20
  local startIdx = scrollY + 2
  for i = startIdx, #rd do
    if y > H - 4 then break end
    local line = prettifyMath(rd[i])
    local wrapped = wrapText(gc, line, W-8)
    for _, wl in ipairs(wrapped) do
      if y > H - 4 then break end
      gc:drawString(wl, 6, y); y = y + 12
    end
  end
end

function on.paint(gc)
  gc:setColorRGB(255,255,255)
  gc:fillRect(0, 0, W, H)
  if state == "splash" then drawSplash(gc)
  elseif state == "tool" then drawTool(gc)
  elseif state == "read" then drawRead(gc) end
end

---------------------------------------------------------------
-- INPUT HANDLING
---------------------------------------------------------------
function on.arrowKey(key)
  if state == "tool" then
    local t = tools[currentTool]
    if not t then return end
    if resultScrollMode then
      if key == "up" then scrollY = math.max(0, scrollY - 1) end
      if key == "down" then scrollY = scrollY + 1 end
    else
      if key == "up" then inputSel = math.max(1, inputSel - 1) end
      if key == "down" then inputSel = math.min(#t.inputs, inputSel + 1) end
    end
  elseif state == "read" then
    if key == "up" then scrollY = math.max(0, scrollY - 1) end
    if key == "down" then scrollY = scrollY + 1 end
  end
  platform.window:invalidate()
end

function on.enterKey()
  if state == "splash" then return end
  if state == "tool" then
    local t = tools[currentTool]
    if not t then return end
    if not resultScrollMode then
      local vals = {}
      for i, inp in ipairs(t.inputs) do
        vals[i] = inputVals[i] or ""
      end
      results = t.compute(vals) or {}
      resultScrollMode = true; scrollY = 0
    end
  end
  platform.window:invalidate()
end

function on.escapeKey()
  if resultScrollMode then
    resultScrollMode = false; scrollY = 0; results = {}
  else goHome() end
  platform.window:invalidate()
end

function on.tabKey()
  if state == "tool" then
    local t = tools[currentTool]
    if t then inputSel = (inputSel % #t.inputs) + 1 end
  end
  platform.window:invalidate()
end

function on.charIn(ch)
  if state == "tool" and not resultScrollMode then
    local idx = inputSel
    inputVals[idx] = (inputVals[idx] or "") .. ch
    platform.window:invalidate()
  end
end

function on.backspaceKey()
  if state == "tool" and not resultScrollMode then
    local idx = inputSel
    local s = inputVals[idx] or ""
    inputVals[idx] = s:sub(1, -2)
    platform.window:invalidate()
  end
end

function on.deleteKey()
  if state == "tool" and not resultScrollMode then
    inputVals[inputSel] = ""
    platform.window:invalidate()
  end
end

function on.mouseDown(x, y)
  if state == "splash" then return end
end
