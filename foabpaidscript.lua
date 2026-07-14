
----------------------------------------------------------------------
-- Services / locals
----------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local HttpService      = game:GetService("HttpService")
local Debris           = game:GetService("Debris")
local Stats            = game:GetService("Stats")
local Workspace        = workspace

local LP  = Players.LocalPlayer
local Cam = Workspace.CurrentCamera

-- Combat uses ReplicatedStorage.Packet (signed packet "A" only â€” verified via
-- darkdex live Combat decompile + Hydro remote spy). Packet "C" is gone.

----------------------------------------------------------------------
-- Persistent global so re-execution unloads the old instance
----------------------------------------------------------------------
local genv = (typeof(getgenv) == "function" and getgenv()) or _G
if genv.__FOAB_SUITE and genv.__FOAB_SUITE.Unload then pcall(genv.__FOAB_SUITE.Unload) end
local function destroyFoabGuis()
    local roots = {}
    pcall(function()
        if typeof(gethui) == "function" then
            local h = gethui()
            if h then table.insert(roots, h) end
        end
    end)
    pcall(function() table.insert(roots, game:GetService("CoreGui")) end)
    pcall(function()
        local pg = LP:FindFirstChild("PlayerGui")
        if pg then table.insert(roots, pg) end
    end)
    for _, root in ipairs(roots) do
        if root then
            for _, g in ipairs(root:GetChildren()) do
                local n = g.Name
                if type(n) == "string" and (n:match("^FOAB_Suite") or n == "FOAB_Loader" or n == "FOAB_ESP") then
                    pcall(function() g.Parent = nil end)
                    pcall(function() g:Destroy() end)
                end
            end
        end
    end
end
destroyFoabGuis()
local MY_SESSION = (genv.__FOAB_SESSION or 0) + 1
genv.__FOAB_SESSION = MY_SESSION
local function isCurrent() return genv.__FOAB_SESSION == MY_SESSION end

-- Some executors hard-fail on getconnections; never call it bare.
local function safeGetConnections(signal)
    if typeof(getconnections) ~= "function" or signal == nil then return {} end
    local ok, conns = pcall(getconnections, signal)
    if ok and type(conns) == "table" then return conns end
    return {}
end

----------------------------------------------------------------------
-- Maid (connection / instance cleanup)
----------------------------------------------------------------------
local Maid = { conns = {}, insts = {} }
function Maid:Give(c)     table.insert(self.conns, c); return c end
function Maid:GiveInst(i) table.insert(self.insts, i); return i end
function Maid:Clean()
    for _, c in ipairs(self.conns) do pcall(function() if c then c:Disconnect() end end) end
    for _, i in ipairs(self.insts) do
        pcall(function() if i then i.Parent = nil end end)
        pcall(function() if i then i:Destroy() end end)
    end
    self.conns, self.insts = {}, {}
end

----------------------------------------------------------------------
-- Theme (matte black + crimson) â€” drives palette C and all visuals
----------------------------------------------------------------------
local Theme = {
    Text       = Color3.fromRGB(255, 255, 255),
    SubText    = Color3.fromRGB(163, 163, 163),
    Stroke     = Color3.fromRGB(255, 255, 255),
    Accent     = Color3.fromRGB(214, 31, 58),
    AccentGlow = Color3.fromRGB(255, 59, 92),
    Accent2    = Color3.fromRGB(140, 15, 25),
    Good       = Color3.fromRGB(50, 215, 75),
    Warn       = Color3.fromRGB(255, 214, 10),
    Error      = Color3.fromRGB(255, 69, 58),
}

-- Embedded brand logo (base64 PNG). Decoded â†’ written to the executor's own
-- workspace â†’ loaded as a custom asset, so the logo shows for ANY user with no
-- local file path. Falls back to the "V" wordmark if the executor lacks a
-- filesystem or base64 decoder.
local LOGO_B64 = nil -- large embedded PNG removed for executor compatibility; falls back to "V" wordmark
local function decodeB64(data)
    for _, fn in ipairs({
        function() return crypt.base64decode(data) end,
        function() return crypt.base64.decode(data) end,
        function() return base64.decode(data) end,
        function() return base64_decode(data) end,
        function() return crypt.base64_decode(data) end,
    }) do local ok, res = pcall(fn); if ok and type(res) == "string" and #res > 0 then return res end end
end
local function loadEmbeddedLogo()
    if not LOGO_B64 or #LOGO_B64 < 16 or LOGO_B64:sub(1, 2) == "@@" then return nil end
    local getter = (typeof(getcustomasset) == "function" and getcustomasset)
        or (typeof(getsynasset) == "function" and getsynasset)
    if typeof(writefile) ~= "function" or not getter then return nil end
    local ok, asset = pcall(function()
        local bin = decodeB64(LOGO_B64); if not bin then return nil end
        local path = "VelorixFOAB_logo.png"
        writefile(path, bin)
        return getter(path)
    end)
    return ok and asset or nil
end
local LOGO_ASSET = loadEmbeddedLogo()
local DCPFP_IMAGE = LOGO_ASSET

----------------------------------------------------------------------
-- Combat networking â€” Packet("A") + SecureFire (darkdex/Hydro verified, PV 1368+)
-- Game: workspace.Live.<char>.Combat â†’ Packet("A", Any, Buffer), seed = LP attr "K".
-- Wire types seen: Swing, Weave, Grab, Push, Stomp, Input (+ Hit/Humanoid/Position/Limb).
-- DAMAGE is server-side via real combat handlers (Mobile UI â†’ DoPunch) â†’ RaycastHitboxV4 â†’ SecureFire.
-- Packet-only fires accept on wire but do not deal damage without the hitbox path.
----------------------------------------------------------------------
-- ============================================================================
-- PROTECTED SIGNATURE CORE  (loaded from a separately-Luraph'd chunk)
-- ----------------------------------------------------------------------------
-- The packet signature + SecureFire logic lives in net_core.lua, obfuscated on
-- its OWN (tiny → compiles instantly, unlike the whole suite under Luraph).
-- Paste the Luraph output of net_core.lua between the [=====[  ]=====] below,
-- replacing the @@PASTE...@@ placeholder line. Until you do, combat is inert
-- and the suite warns you, but the rest of the menu still loads normally.
-- Because this core is a VM blob, a leaked copy of the suite is useless — the
-- aura/weave deal zero damage without it.
-- ============================================================================
-- NOTE: if Luraph's output happens to contain the closing ]=====] sequence
-- (extremely rare), add more '=' to BOTH brackets until it doesn't.
local NET_CORE_BLOB = [=====[
return({mS=function(M,m,U)if not(m<0B11100001)then(U[32])[14]=M.V;return 50428;else U[32][0B100__11]=M.hS;end;return nil;end,G=string.sub,aS=function(M,m,U)U=0X46_+(((M.CS((m[26334]>m[0X1718]and M.X[7]or m[0X4E92])-m[0x3Ba4]+M.X[0X4]))==m[0X370E_]and m[0x7168]or m[13887])<m[10820]and m[2161]or m[4044]);m[32660]=(U);return U;end,Y_=function(M)end,aI=function(M,m,U)U=-1954757024+(M.QS((M.CS((M.PS(M.X[0X4]+m[0x2422],(m[15268])))-m[0X52b3]-m[26334]))));m[0x59c0]=(U);return U;end,a=function(M)local m,U=({});U=M:U(m,U);local x;x=M:u(U,m,x);local S;S,x=M:Z(U,x,S,m);x=M:J(U,S,x,m);x=M:L(x,U,m);x=M:N(S,x,U,m);x=M:dI(x,U,m);x=M:WI(U,m,x);x=M:FI(U,S,x,m);x=M:zI(m,x,U);x=M:UI(m,U,x);M:wI(m);S=nil;S=M:uI(S,m);local O,j;x=(115);repeat if x==0B0111_0011__ then m[0X37]=function()return(M:MI(m));end;if not U[4661]then(U)[0X7e10]=(-3149767733+(M.zS((M.PS(U[21171],(U[0X68F2])))-U[0x66De]+U[2058]-M.X[0x2]<M.X[0X6]and M.X[0b010_01]or M.X[0X3],U[0X2f97],U[3599])));x=-46+(M.QS((M.VS((M.QS(x))+U[5469]))+M.X[0B1001]-U[0X68__f2],U[14094]));U[0X1235]=x;else x=U[0X1235];end;elseif x==0x4A then m[60]=(function(K,f,N)local N,B,G,T,e,z,u,p,i,d=K[0xb_],K[0B1001],K[0X5],K[0X4],K[0X3],K[0X6],K[0B1],K[10],(K[0X7]);d=function(...)local V,A,W,w,s=1,m[0B101100](N),(0x0);local N,h=m[0X3b](...);local g,E,_,Z,F,v=0B1,0x1,(m[0X2F]());local X,n,t,k=m[0X9](function()local Y,H,y,P,b,C,a,D,R,o;repeat local Q=(z[g]);if not(Q>=0X65_)then if not(Q>=0X32)then if not(Q>=0X19)then if m[55]==d then m[0x35],m[0X34]=m[0X24],m[0X019];while m[0X7]do(m)[29],m[28]=m[0X2E],m[54];return m[54]==m[0X31];end;elseif m[20]==m[0X32_]then return 15;else if not(Q>=0b1100)then if not(Q<0x6)then if d==m[0X1D]then else if not(Q<9)then if m[0x36]==m[0X2e]then if not(-(0Xc3~=0B1001011))then else m[0b110101],m[54]=-m[0x35],(-m[0X35]);(m)[0b10100__0],m[0X19]=-m[0B11100],(m[0B110100]);end;elseif m[40]==m[50]then m[0X22__]=(-m[48]);m[49]=m[0X14];elseif not(Q>=0XA)then(A)[u[g]]=(i[g]-T[g]);else if Q==0B1011 then(A)[u[g]]=(T[g]^A[p[g]]);else a=(e[g]);H=(i[g]);end;end;else if m[0X2B]==d then return-m[0X20];elseif Q<0X7 then P=T[g];H=H[P];(y)[a]=(H);else if m[0b110]==m[0X32__]then else if Q~=0x8 then H=A;else if m[59]~=m[0B110]then else(m)[0X3b]=-71;(m)[0b1__1001_]=(m[0X2]);end;y=nil;a=nil;H=(nil);P=nil;D=0B1101111;while true do if not(D<=0B10011)then if D>0b1010110 then if D~=111 then H=4503599627370495;a*=H;D=-0X4+((m[0X20][8]((m[0X20][0B1000](D,Q,Q)),Q))+Q+D+Q==D and D or Q);else y=(0X53__);D=(-0X6D+((m[32][0X8]((Q>=D and Q or Q)+D+Q-Q))>=Q and D or Q));continue;end;else if not(D<=0X3d)then H=(H[P]);D=-4294924995+(m[0X20][5]((m[0X20][0X8]((m[32][16](Q<Q and D or D))))+Q-D,(Q)));continue;else P=(m[0X20]);break;end;end;else if not(D<=0x2)then if m[0x2B]==d then if m[0X6]then(m)[0X1d]=(m[0b11001]);m[0B110001]=m[56];end;elseif D~=0x4 then if m[7]==d then while d do return m[25];end;m[6]=m[0X37];end;P=(0X9);D=(0B1001110+((m[0B100000][0B1000](((m[0X20][5](Q,(Q)))>Q and D or D)+Q-Q,Q))-D));continue;else if m[0B10100]==m[0X33]then else H=m[0x20];D=0B111+(((m[0X20][0X8]((m[32][0X012]((m[32][8](Q,Q))+D,(Q)))))<=Q and Q or Q)+D);continue;end;end;else a=(0X0);D=0X66+((m[0x20][0B10100__]((m[32][0b1001_1]((Q>Q and D or Q)-D,Q)),(D)))+Q+Q);end;end;end;if m[0X36]~=m[0x22__]then else if not(m[58])then else(m)[56]=(m[51]);end;end;if m[0X3a]~=m[0X2e]then C=(nil);D=0XA;while true do if D~=0X61 then C=(0B01000);D=(0B1001__101+(((m[0B100000][10]((m[0B10000__0][20]((m[0X20][0B1000](Q,Q,D))-Q,(Q))),D))~=Q and D or Q)+D));else P=(P[C]);break;end;end;C=(m[0X20]);R=(nil);end;D=0X76;while true do if D~=0X005_D then if m[0B100000]==m[0x3A]then while 0X57 do return-(-0X0b9);end;end;R=(0X9);D=(-0x21+(m[32][0X0013]((m[0X20__][0B1010_]((m[0B100000][0x8]((m[0B01000_0__0__][8]((m[0X20][0X13](Q))-Q)),Q)),Q,Q)),Q,D)));continue;else C=C[R];break;end;end;R=m[0X20];o=nil;D=(85);while true do if not(D<=48)then if D==0B1001111 then o=(Q);break;else if m[0x36]==d then return 231;end;o=18;D=16+(m[0x20][0B10001]((m[32][0X14]((m[32][0x8]((m[32][0X8]((m[0X20][8](D,D)),D))<=Q and Q or D,Q)),(Q)))));end;else R=R[o];D=0B1001_000+(m[0X20][0X8]((m[0X2_0][0b010000]((m[0X20][20](D,(Q)))-D+D))+Q));end;end;Y=nil;D=(114);while true do if D==0x29 then if m[0X31]~=m[0X22_]then R=R(o,Y);end;o=(Q);break;elseif D==0b111_0010 then Y=z[g];D=(0B101001+(m[0X20][0XF]((m[0X2_0_][0B10100]((m[0X0020][0B1000]((m[0X020][17](D<Q and Q or D)),Q))+Q,(Q))),(Q))));end;end;R-=o;C=C(R);R=z[g];D=0B1001;while true do if D>9 and D<0X54 then H=H(P);break;elseif D>0X023 then if m[0B10]==m[0X20_]then m[0X28]=(-m[0x3A]);while m[42]do(m)[0x2B]=(m[0X3__1]);m[0B110101],m[0X36]=-(0X8E<=207),m[43]<=m[0X2b];end;end;P=P(C,R,o);D=(0X23+((m[0B100000][0x13]((m[0X20][0B1010](Q>Q and Q or Q)),Q))-D+D-Q));continue;elseif D<35 then o=z[g];D=(-5900460+(m[0x0020][0B101]((m[0B1_000_00][15]((m[0X20][9](Q))+Q+D,(D)))+D,(Q))));continue;end;end;D=(25);while true do if D<=0X24 then if D>0X19 then if H then H=z[g];end;D=(0X2B+(((m[0B100000][0X11__]((m[0X20][17](D))-Q))~=Q and D or D)-D+Q));continue;else P=Q;H=(H>P);D=0X1c+((m[32][17]((Q-D==Q and D or D)-Q>=Q and D or D))+Q);end;else if not(D>=0x76)then if not H then H=(z[g]);end;if m[0X3a]~=m[0B110]then else if not(m[0x30])then else return;end;return;end;D=(110+(((m[32][9](Q-Q+D))>Q and Q or Q)-D+D));else if m[0x20]~=m[56]then else return;end;P=Q;break;end;end;end;if m[0B110111]==m[0x20]then if not(m[36])then else return;end;m[34]=(m[0x001d]);end;H=H==P;if not(H)then else H=Q;end;D=(0Xe);while true do if D>0X15 then H-=P;D=(0XF+(((m[32][0B10010]((m[0x20][10]((m[0X0020][0X11](D)),Q,D))>D and Q or D,(Q)))>=Q and D or D)-D));elseif D>15 and D<0B1110000 then P=(z[g]);D=0B1011011+(((m[0X20][0X5](Q+D-Q-D,(Q)))<Q and Q or D)>=Q and D or Q);elseif D<0XF then if not(not H)then else H=Q;end;D=-0X3+((m[0X20][0B1010]((m[32][0x11](Q<D and D or D))-Q,D))+Q+Q);continue;elseif D>0Xe and D<21 then a+=H;break;end;end;y+=a;(z)[g]=(y);y=e[g];g=(y);end;end;end;end;end;elseif Q<0X3 then if Q<0X1 then A[e[g]]=G[g]+A[p[g]];else if Q~=0X2 then if m[0B10100]~=m[0X6]then else(m)[55]=(m[0B1110_1]);end;W=u[g];for q=0B1,W,0X1 do(A)[q]=(h[q]);end;E=W+0X1;else V=(u[g]);A[V]=A[V]();end;end;else if not(Q>=0b100)then if m[0x2__2__]==m[7]then return m[0X3__2_];end;(A)[e[g]]=z;else if m[0X2]~=m[0X20]then if Q~=0x5 then if m[48]==m[0B10100]then m[46],m[0X6]=-m[0X2a],(m[0X14__]);elseif m[0X2]==m[0B110]then if not(m[0x3])then else m[42]=(2);end;elseif A[p[g]]==A[u[g]]then else g=e[g];end;else y[a]=(H);end;end;end;end;else if not(Q<0x012)then if m[0B11]==m[20]then(m)[0B110001]=m[59];return;end;if not(Q>=0X15)then if Q>=19 then if Q~=20 then A[u[g]]=A[e[g]]*A[p[g]];else A[e[g]]=(m[21](A[p[g]],A[u[g]]));end;else y=p[g];a=(A[e[g]]);A[y+0X1]=(a);A[y]=a[G[g]];end;else if Q<0X17 then if Q~=0B10110 then if not(F)then else for q,I,L in F do if q>=0b1 then if m[0X24]==d then while m[0X2B]do return;end;end;(I)[0B10]=I;I[0X3]=(A[q]);I[0x1]=(0B11);F[q]=nil;end;end;end;return true,p[g],0x0;else if m[0X35]~=m[0X28]then a=(y);H=(2);end;a=(a[H]);end;else if m[0X7]==m[0x014]then while true do m[0b11],m[0X3a]=m[32]and 0B111010_11%0XF6,(0X5F);end;(m)[0X2A]=m[6];else if Q~=0B11000 then y=false;s+=w;if not(w<=0)then y=s<=Z;else y=s>=Z;end;if not(y)then else(A)[u[g]+0B11]=(s);g=e[g];end;else a=(p[g]);H=(A);end;end;end;end;else if not(Q<15)then if not(Q>=0X10)then if m[42]==m[32]then while m[0X33__]do m[0X34_]=m[0B0111000];end;else if A[e[g]]~=A[p[g]]then else g=u[g];end;end;else if Q~=0X11 then y=(e[g]);a=(u[g]);H=(A[y]);m[0XC](A,y+1,y+p[g],a+0b1,H);else(A)[e[g]]=(A[u[g]]..A[p[g]]);end;end;else if not(Q>=0Xd__)then y=A;a=(p[g]);else if Q~=14 then(A)[u[g]]=i[g]~=A[e[g]];else y=(A);a=e[g];end;end;end;end;end;end;else if m[0X28]~=m[0B110111_]then else(m)[0X34__],d=m[2],-(-0XE);end;if not(Q>=0X25)then if Q>=0b01__1111 then if m[0x38]==d then else if Q<0X22 then if Q<32 then P=(A);else if Q==0x21 then if m[56]~=m[40]then else while m[0X3b]do(m)[58]=m[40]+-0X58;return;end;while-97/(0X96%0B1110100)do return-m[40];end;end;y=p[g];(A)[y]=A[y](A[y+0X1],A[y+0x2]);V=y;else A[u[g]]=(A[p[g]]~=T[g]);end;end;else if Q>=0X23 then if m[0X2A]~=m[0x00_20]then else m[0X37__],m[0X037]=m[0X30],m[0X38];if m[0X19]/-0X76 then m[0X24]=(-0b110__1__010 and-0XB__c);end;end;if Q~=0X24 then H-=P;(y)[a]=H;else(A)[e[g]]=(A[u[g]]);end;else(A)[u[g]]=(i[g]>A[e[g]]);end;end;end;else if not(Q<28)then if Q>=0X1d then if Q==0X1E then y=(u[g]);else y=(f[e[g]]);A[p[g]]=y[2][y[0b1]];end;else(A)[e[g]]=#A[u[g]];end;else if Q>=0X1a then if Q==27 then(A)[p[g]]=_[G[g]];else(A)[u[g]]=(A[e[g]]+A[p[g]]);end;else for q=0X1,u[g]do(A)[q]=h[q];end;end;end;end;else if not(Q<43)then if Q>=0X2E then if not(Q<0B1100_00)then if Q~=0b110001 then y=nil;a=(nil);H=nil;P=(0X004_4_);repeat if P<0x44 then H=(4503599627370495);a*=H;break;else if P<0X53 and P>0X16 then if m[0X2e_]==m[3]then if not(m[0x24])then else m[0x36]=m[0B11100];return m[0x1_9]or 177%87;end;while-0Xc8>(0B1001101<244)do(m)[0X35],m[0x7]=m[0X3],m[0X6];end;end;y=-4261412666;P=0B1001100+((m[0x20][0x10]((m[32][0B1000](P-P,P))==e[g]and P or P))+P>=P and e[g]or e[g]);continue;else if P>0X44 then a=0B0;P=-0B1000100__+(((m[0X2_0][0X12]((P+P<=P and P or Q)-P,e[g]))<=P and P or P)+e[g]);end;end;end;until false;H=(m[0B100000]);D=(nil);C=nil;R=nil;P=(0X2e);while true do if m[0X3_2]~=m[0x28]then if P==0X2__f then C=m[0X20__];P=(19+(m[0B10_0000][0B10011]((m[0X20][0x13]((m[0X20][10]((m[0x20][18](P,e[g]))<Q and P or P))-e[g],e[g])))));elseif P==0b00_1000010 then R=0X10;break;elseif P==16 then C=0x0014;D=D[C];P=(-4294965376+((m[0B00100000][15]((m[0b100000][0XA]((m[0X20][0XF]((m[0X20][0X13](Q,P)),(P))),P,e[g]))-P,e[g]))+Q));continue;elseif P==46 then D=(0B10000);H=H[D];P=(-0X3a9+((m[32][0x5]((m[0B01_00000][18](P+e[g],e[g]))<P and P or e[g],e[g]))+P+Q));else if P~=0X35 then else D=(m[32]);P=(-0B10_0101+((m[0x20][16]((m[0X20][0B1111]((m[0X20][0B10001](P+P))+Q,e[g]))))==Q and Q or P));continue;end;end;end;end;C=C[R];o=nil;P=(0X74__);while true do if not(P<=67)then R=m[0x20];P=(-0X33+(m[32][0x13]((m[0B100000][0X11]((m[32][10]((m[0x20][0X5](Q-P,e[g]))+P)))),P)));else o=(8);break;end;end;R=(R[o]);o=Q;Y=(Q);o+=Y;P=0X53;while true do if P==0X38 then D=D(C,R);C=(Q);D+=C;break;elseif P==0x53 then Y=(z[g]);R=R(o,Y);P=(15+((m[0X20][0B1__01]((((m[0X20][0B10_10](P))~=e[g]and P or Q)>=e[g]and Q or P)-Q,e[g]))>P and e[g]or e[g]));else if P==0X16 then if m[34]==m[0x0__037]then while-214 do return;end;(m)[0b110100]=(m[0X28]);end;C=C(R);P=0B1100111+((m[32][0B10011](Q-P,P))+P-e[g]-P<P and Q or P);else if P==0B1111101 then R=(e[g]);P=(-0X45+((m[0B100000][0x10]((m[0b100000][0X8]((m[0B100000][0x8__]((m[0B100000][0X10](e[g]))~=P and Q or Q)),P,P))))<=e[g]and Q or P));end;end;end;end;H=H(D);D=(Q);H-=D;P=0B101110;while true do if m[0X20]==m[0b10]then(m)[53],m[0X20]=m[25],m[0B1__01110];elseif P>0X2E then if not(P>=53)then y+=a;z[g]=(y);break;else H-=D;if m[49]~=m[0X20__]then P=(-4294961238+(m[0X20][16]((m[32][0x8]((m[0X20][0X5_](Q,e[g]))-e[g]-Q,e[g]))-P)));end;continue;end;else if P<=0b10__000 then if m[32]==m[29]then else a+=H;P=-2986344400+(m[32][0X010]((m[32][0X12](e[g]+Q+P+P-Q,e[g]))));continue;end;else D=(Q);P=46+((m[0B1__00000][0X0A](P+e[g],Q))-P+P+e[g]~=Q and e[g]or P);end;end;end;P=0X62;repeat if P==0b11__10011 then if m[6]==m[0X20]then while-142>m[0X32]do m[0B100100],m[0X19]=0Xde,0X0061;end;end;y=(y~=a);P=(-42+(m[0X20][0xa]((m[0X20][0B1010](((m[0x20][0X13](P>e[g]and e[g]or P))~=Q and P or Q)-e[g],P,P)),P)));elseif P==98 then y=(A);P=-4294967297+((m[0X020][0X10](((Q>e[g]and e[g]or Q)<e[g]and P or Q)-P==e[g]and e[g]or e[g]))+P);elseif P==0X36 then if y then y=(p[g]);g=y;end;break;else if P==0X64 then y=(y[a]);a=(G[g]);P=0X70+(m[0x20][17]((m[0B100000][0b101]((m[32][8]((m[0X20][0X1__0](P)),Q,P)),e[g]))+P+P));continue;else if P==89 then a=e[g];P=(0X86+((Q-P+e[g]-P>P and P or e[g])+e[g]-Q));end;end;end;until false;else if m[32]~=m[0B111011]then else(m)[0X3],d=m[0B110011],(m[43]);while m[0X2A]do(m)[0B1_0]=(0X1_2%m[0x20]);return-m[7];end;end;H=(H[P]);P=(i[g]);end;else if Q~=47 then a=e[g];for q=y,a do H=(A);P=q;q=nil;(H)[P]=q;end;else(f[u[g]])[T[g]]=(A[p[g]]);end;end;else if Q<0B101_100 then H=H[P];y[a]=H;else if Q~=45 then a=(u[g]);H=A;else y=(p[g]);A[y](A[y+1]);V=(y-0x1);end;end;end;else if Q>=0x28 then if Q>=0X29 then if Q~=0B10101_0 then H=G[g];else H=A;P=(p[g]);H=H[P];end;else H-=P;y[a]=(H);end;else if m[0X3]==m[0B1_0100_0]then if-(0Xbf and 0XBa)then return-m[0b00101011];end;if not(3)then else return m[0X2e];end;end;if not(Q<0b00100110)then if Q~=0B10_0111 then y=(A);a=(e[g]);H=A;else if m[0X30]~=m[32]then else while m[0X3]do return;end;end;P=(e[g]);H=(H[P]);P=(G[g]);end;else y=e[g];(A[y])(m[0x1_d](A,V,y+0X1));V=y-0X1;end;end;end;end;end;else if not(Q<0B0100101__1)then if Q<0x58 then if not(Q>=81)then if not(Q<0B10011__10)then if m[7]~=m[0X019]then else m[0B101110],m[0B101011]=m[0x3__6],(0X92);if not(m[25])then else(m)[28],m[0x007]=-(0x62/165),(221);end;end;if Q<79 then y=(p[g]);(A)[y]=A[y](m[29](A,V,y+0X1));V=y;else if Q==80 then A[p[g]]=(A[u[g]]<A[e[g]]);else A[e[g]]=(i[g]==G[g]);end;end;else if Q<0x4_c then A[u[g]]=A[p[g]]>=T[g];else if Q==0B1001101 then if m[0x6]~=d then y=(p[g]);V=y+e[g]-1;(A[y])(m[0X1d__](A,V,y+0X1));V=y-1;end;else A[e[g]]=(G[g]>=A[p[g]]);end;end;end;else if not(Q<0B1010100)then if not(Q<0X5__6)then if Q~=0X57 then if not(T[g]<A[p[g]])then g=(u[g]);end;else if F then for q,I,L in F do if not(q>=1)then else(I)[2]=I;I[0X3]=A[q];I[0X01]=(0X3);(F)[q]=nil;end;end;end;return false,u[g],V;end;else if Q==85 then y=(e[g]);a=u[g];H=(p[g]);if a~=0 then V=y+a-1;end;P,D=(nil);if a==1 then P,D=m[0x3b](A[y]());else P,D=m[0X3b](A[y](m[0B11101](A,V,y+0x1)));end;if H~=0X1 then if H==0 then P=(P+y-0B1);V=(P);else P=y+H-0B1_0;V=P+0X1;end;a=0x0;for q=y,P,0b1_ do a+=0B1;(A)[q]=(D[a]);end;else V=y-0b1;end;else y=A;if m[0b10100]==m[6]then while m[0X3_b]do(m)[0B111010]=0B10011101;end;end;a=(p[g]);end;end;else if Q>=82 then if Q~=0x53__ then if not(F)then else for q,I,L in F do if not(q>=0X1)then else if m[0b11100]==m[6]then else(I)[0X2]=(I);(I)[0B11]=A[q];I[1]=0x3;end;F[q]=(nil);end;end;end;y=(p[g]);return false,y,y+u[g]-0X2;else if m[28]~=m[0x28]then g=(e[g]);end;end;else y=A;a=(u[g]);end;end;end;else if Q<0X5E then if not(Q>=0X5b)then if Q>=89 then if Q==0b10_11010 then H=(H[P]);P=(A);D=(p[g]);else if m[0X38]~=m[32]then else return;end;y=(nil);a=nil;H=(0X47);while true do if H==0X7A then a=(0B0);break;else y=0b10000_1__00;H=(-3892313988+(m[0X20][0X12]((m[0x20][10]((m[0X20][0x11]((m[0X0020][0X9](u[g]-H)))),Q,H))-H,u[g])));end;end;if m[0x3B__]==m[0b100000]then else P=4503599627370495;a*=P;end;P=(m[0X20]);D=(nil);C=nil;H=102;while true do if H<=0xd then if H<=8 then D=(m[0b100000]);H=(-0XFFffB_8+(m[0X20][0X14]((m[0X2_0][0B10__010]((m[0X20][0X10](u[g]))+u[g],(H)))-H-Q,(H))));continue;else P=(P[D]);H=(-335864+(m[0X20][0b1111]((m[0X20][0B1001]((m[0X20][0x12](H,u[g]))-H~=u[g]and H or H))+H,(H))));end;else if not(H<=0X47)then if H==0B1111010 then if d~=m[0X0024]then else if not(d)then else return;end;m[0X33],m[0X22]=0B1__0110_100,m[28];end;D=(D[C]);break;else if m[29]~=a then else if m[29]then return-(0X3D/0B10101);end;while m[0x2e]do return m[55];end;end;D=20;H=-0x2179+((m[32][15]((m[0x20][0X9](u[g]))+H,u[g]))-u[g]+H+H);continue;end;else C=(0X9);H=(0x80+((m[0x20][0x5]((m[0x20][0X5]((m[0b100000_][0X11](H)),u[g])),u[g]))-H-u[g]+H));end;end;end;C=m[32];R=nil;H=104;while true do if H==0x27 then C=C[R];R=m[0X20];break;elseif H==0x68 then R=0x14;H=-65+((m[0X20][0B10100]((m[0x20][0x10]((m[32][0x5](Q,u[g]))+Q)),u[g]))+Q>H and H or u[g]);continue;end;end;o=nil;H=(0b101__01_1);while true do if H<0B10101 then R=(R[o]);o=(z[g]);H=0x15+(m[0B100000][0xA]((m[0B100_000][0B1111]((Q<=Q and H or H)+H-u[g]-u[g],(H))),Q,H));elseif H>0x15 then o=0X10;H=(-4294967153+(m[0X20][0X13]((m[0B1__00000][0x8]((H<u[g]and u[g]or u[g])-H,H,H))-Q-H,H,u[g])));continue;elseif not(H<0X2b and H>14)then else if m[0x2e]~=d then R=R(o);end;break;end;end;o=u[g];H=(75);while true do if H>46 and H<53 then C=(u[g]);break;elseif H<47 and H>0b10000 then R=(u[g]);H=47+((m[0X20][0x11]((m[0B10__0000][0B1_010](((m[0X20][16](u[g]))<H and Q or Q)+Q,Q,u[g]))))>Q and H or u[g]);continue;elseif H<0b101_110 then D=D(C);H=(-0xFFFd1+(m[0B00100000][0X12]((m[0X20][0xa]((m[0x20][0X14]((m[0B100_000][0X12](u[g],(H)))-H,u[g])),u[g]))<=u[g]and H or H,(H))));elseif H>53 then C=C(R,o);H=(-0x1D+((H+Q-u[g]-u[g]+H>=H and Q or H)<=H and u[g]or H));elseif not(H>0X2F_ and H<75)then else C-=R;H=-4294966384+(m[32][0B101]((m[0X20__][0X10]((m[0X20][0X9]((m[0X20][0x5](Q,u[g]))-H))-u[g])),u[g]));continue;end;end;D=D>=C;if not(D)then else D=Q;end;H=(107);while true do if H<0X55 then if m[0X14]~=m[36]then else m[0B11],m[0x2]=m[0B101000],(m[0B11101]%m[46]);end;C=(u[g]);H=(-0X15_EB+(m[0x20][0x5](((m[0X20][0X5](u[g]-H-H,u[g]))>u[g]and H or H)<=Q and Q or Q,u[g])));elseif H<0x6b and H>78 then D-=C;break;elseif not(H>85)then else if not(not D)then else D=(Q);end;C=(z[g]);D+=C;H=(78+(m[0X20][17]((m[0X20][17]((m[0b100000][0x14](Q>H and Q or u[g],u[g]))<H and H or Q))==H and Q or Q)));end;end;C=(u[g]);P=P(D,C);H=(0b101001);while true do if not(H>=0X74)then a+=P;H=(-2751463308+(m[0B100000][18]((m[0B100000][0X8]((m[0x20][9]((m[0B1__00000][0x10]((m[0x20][0xA](H,H,H))))))))>H and H or H,u[g])));else if m[49]==m[0X2E]then else y+=a;z[g]=(y);end;break;end;end;y=(A);a=(u[g]);H=66;while true do if H<0b100__0010 then D=(e[g]);H=0B100__11011+((m[0b100000][0XA](((m[0X20][5](u[g],u[g]))-u[g]<H and Q or H)+H,u[g]))-Q);continue;elseif H>66 then if m[52]==m[0B0010100]then else P=P(D);break;end;elseif not(H>0X39 and H<0B1__000100)then else P=m[44];H=(-0X9+(m[32][10]((m[0x20][20](H-H-u[g]-H-u[g],u[g])),H)));end;end;y[a]=P;end;else(A)[u[g]]=e;end;else if Q>=0X5c then if Q~=0X5__d then if not(not(A[e[g]]<G[g]))then else g=(p[g]);end;else(A)[p[g]]=(A[e[g]]==A[u[g]]);end;else if m[20]~=m[0B110000]then(A)[u[g]]=(A[p[g]][T[g]]);end;end;end;else if not(Q>=97)then if Q<0X5F then P=e[g];else if Q==96 then if m[0B10_0010]~=m[29]then else m[46]=((0B10100000>=0X2a)- -0X78);(m)[46]=m[0B101011];end;A[u[g]][T[g]]=i[g];else(A)[p[g]]=A[e[g]]/A[u[g]];end;end;else if not(Q<0X63)then if Q==0X64 then if F then for q,I in F do if q>=0x1 then I[2]=(I);(I)[0x3]=A[q];(I)[0B1_]=3;(F)[q]=nil;end;end;end;if m[54]~=m[0X6]then else return m[25];end;y=(e[g]);V=(y+0x1);return true,y,0X2;else(A)[e[g]]=(A[u[g]]-A[p[g]]);end;else if Q==0X62 then a=e[g];H=(G[g]);P=A;else if m[29]==m[0B110]then if m[0B11001]then(m)[7]=(-0b11011);end;end;(A[e[g]])[A[p[g]]]=(A[u[g]]);end;end;end;end;end;else if m[0X19]==m[54]then m[48],m[6]=0X1__8,m[49]<(214 and 0B1001011__0);while-m[0x2a]do(m)[34],m[20]=m[0X19],(m[0B110010]^(0X16-154));end;else if Q<0X3E then if Q>=56 then if not(Q<59)then if Q<0x3C then A[p[g]]=(A);elseif Q~=0x3d then A[u[g]]=(T[g]>=i[g]);else A[u[g]][A[e[g]]]=(i[g]);end;else if not(Q<0X39)then if m[3]==d then if m[0x020]then return;end;return m[0X35];else if Q==0X3a then(A)[p[g]]=(A[e[g]]<=G[g]);else A[u[g]]=A[p[g]]/T[g];end;end;else H=(A);P=u[g];end;end;else if Q<0b110101 then if m[0X03a]==m[0B1__00000]then if not(m[32])then else m[0X38],m[55]=m[49],(m[0B1__1]);end;else if Q<0x33 then D=p[g];P=(P[D]);H=(H>=P);else if Q~=0X3_4 then if m[0b111011]==m[0B110]then else a=(e[g]);H=A;end;else if not(not(A[p[g]]<A[e[g]]))then else g=u[g];end;end;end;end;else if Q>=0X36 then if Q~=0B01_1_0111 then if A[e[g]]==G[g]then else g=(p[g]);end;else y=(e[g]);a,H,P=s();if not(a)then else(A)[y+0X1]=H;(A)[y+0x2]=(P);g=u[g];end;end;else if not(F)then else for q,I in F do if not(q>=0X1)then else if m[54]~=m[0b10100]then I[0B10]=(I);(I)[0B11]=(A[q]);I[0B1]=0x3;end;(F)[q]=(nil);end;end;end;y=u[g];return false,y,y;end;end;end;else if Q<0X0044 then if m[58]==m[0X20]then if not(5*43*(0B11000000%0XBb))then else m[0B101110],d=m[49],-(-0xD8);return;end;if m[0X2B]then(m)[28]=(m[0B101011]^m[3]);return;end;end;if not(Q<0X4__1)then if Q<0X42 then if m[55]==m[0X6]then else y=nil;a=nil;H=0X68;while true do if m[0B101010]~=a then else m[0b101110],m[32]=-0b1111110,-m[0B110110];return;end;if H==39 then if m[0B10100]==m[0B11]then else a=(0);end;break;else if H~=104 then else y=26;H=7+(m[0X20][10]((m[0B100__000][0X9]((m[0X2__0][5]((m[0x20][17]((m[0X20][16](H+H)))),p[g]))))));continue;end;end;end;end;P=(4503599627370495);a*=P;P=(m[0X20]);D=(nil);C=nil;H=0B11110;repeat if H<101 and H>0X32 then D=(D[C]);H=(-44+((m[0X20][9]((m[32][0x12](H-H+p[g],u[g]))))-u[g]+H));continue;elseif H>0x5_f then if m[0x6]~=m[0B101010]then else(m)[0X7],m[0b110000_]=-(0B1000001-0B110101__),m[0X14];return 0Xd3;end;P=(P[D]);D=m[0X20];H=(((m[0x20][0x13]((m[0x20][0X8]((m[32][0X9__](p[g]))==H and H or p[g],e[g],H))))==e[g]and H or H)-H);elseif H<0X1E then C=0B10001;H=(90+((e[g]+u[g]-H+H-H<Q and p[g]or H)+H));continue;elseif H<0b110010 and H>0X0 then D=0XA;H=-4294967179+((m[0x0020][18]((m[32][0x11](p[g]))-u[g]-H,u[g]))-H+H);else if H>0B1__1110 and H<0X5f then C=m[0X20];break;end;end;until false;if m[0X22]==m[0B110010]then return;end;R=(nil);o=nil;H=101;repeat if H<=50 then if not(H<=0b0)then o=0X9;break;else C=C[R];H=(86+((u[g]-H>H and H or H)-u[g]-H+p[g]+p[g]));end;else if H==101 then if m[0X36]==m[0X6]then repeat return;until false;if(1 or 0X036)%169 then m[3],m[0X2b]=-m[0X2A],(m[0X3]);end;end;R=0XF;H=(-0X8+((m[0X20][0x14]((m[0X20][0Xf]((m[0x20][9](Q-e[g])),u[g]))+H,e[g]))+e[g]));else R=(m[0x20]);H=(-4294960976+((m[0X20][0x10]((m[0X20][19]((m[32][0B101__](H+u[g],e[g])),H))+H))+Q));continue;end;end;until false;Y=nil;H=83;while true do if H<=22 then o=m[0X20__];H=(-903+((m[0X20][8]((m[0X020][0X14]((m[32][0B10010](e[g]-H-Q,u[g])),(H))),Q,Q))+p[g]));else if m[0x1C]==m[25]then while m[0X31]do return m[0B110011];end;if d then(m)[29]=(-m[0B110010]);m[0B111011_],m[0B111]=(135%0X41)^m[0B110101],(m[0X2]);end;end;if H>=0x7D then if m[0X20]~=m[0B111__01]then Y=(15);o=o[Y];end;break;else if m[52]~=d then else if not(m[0B110001])then else(m)[0X2],m[43]=m[0X24],-(-0B10011010);m[51]=(0Xce);end;if not(m[0X0__1D])then else a=(m[0B101011]);end;end;R=(R[o]);H=-0X43+(((m[32][0B10001]((m[0B100000][15](H,u[g]))))-H+H==Q and Q or e[g])+H);end;end;end;if m[0X28]==m[0b111000]then else Y=(u[g]);b=(nil);H=(0B1000101);end;repeat if H==0X45 then b=u[g];H=(90+((m[0B10_0000][0X9]((m[0b1000__00][18](p[g]-u[g]+H,p[g]))+H))+p[g]));continue;else if H==0X60 then o=o(Y,b);H=(-4294966955+((m[32][0X0013]((m[0B100000][17](H))-H-H+p[g]))-H));continue;else if H~=63 then else Y=z[g];break;end;end;end;until false;o-=Y;H=60;repeat if m[0X2E_]~=m[0x1C]then if not(H>0b111100)then if not(H<=0X30)then if d==m[0X2b]then else R=R(o);H=0X6__6+(m[0x20][17]((m[0B100__0__00][0X14]((m[0X20][0x13]((m[0x20][0X13](e[g],H))==H and H or u[g],H,e[g])),u[g]))+u[g]));continue;end;else C=(z[g]);break;end;else if H>0b10011__1__0 then if m[0B110010_]==m[0x22]then if not(-207)then else return;end;else if m[0x14]==m[7]then if m[0B11000_1]then m[0X019],m[49]=0Xf5,-0B1010010;return;end;if m[0x14]then return;end;else if not(H>=0X6b)then D=D(C);H=(-0X5_3FffD0+(m[32][0B10100]((m[32][18](u[g]+H-H<H and H or H,p[g]))+u[g],p[g])));else o=(e[g]);H=(77+((m[0X0020][0X8]((m[0B1_0000_0][17]((e[g]<=H and u[g]or Q)+u[g]))))-H+H));end;end;end;else C=C(R,o);H=-4294966975+((m[0X2_0][0b10000](H+u[g]))+H-H-H-H);end;end;end;until false;D+=C;H=125;while true do if H>0b1101__11 then if H==0B111000 then R=z[g];H=-0x1+(m[32][19](((m[32][0XF](p[g],p[g]))-H>=H and H or e[g])-H>H and p[g]or H));else C=(z[g]);H=-87+((m[32][0B1001]((m[32][0X9](u[g]~=p[g]and p[g]or H))+H))-e[g]+H);continue;end;else if m[0B10001_0]~=m[0X2]then P=P(D,C,R);D=(z[g]);end;break;end;end;P+=D;a+=P;H=(60);while true do if H==0B1001110 then a=e[g];P=(A);H=(0x53+(m[0B100000][0X14]((m[0b100000][0B10000]((m[0X20][0x5__]((m[32][0x8](e[g]-H)),u[g]))+H)),p[g])));continue;elseif m[50]==m[0x2__8]then return m[0X3a];elseif m[0X1d_]==m[0B100000__]then return m[0B110110];elseif H==0X55 then if m[0B101011]~=m[6]then D=u[g];break;end;elseif H==0B111100 then y+=a;H=-0X1656__+((m[0X20][5]((Q-p[g]<H and Q or H)+H+H,p[g]))+Q);else if H==107 then if m[0x34]~=m[0X22]then(z)[g]=(y);y=A;H=-0B0011101+((H-H<u[g]and Q or H)-H+e[g]+e[g]>H and u[g]or H);end;continue;end;end;end;H=(0b1_1__11011);repeat if H<30 then y[a]=P;break;else if H<0X7B and H>30 then D=(D[C]);P=(P[D]);H=(-2147483544+(m[0b10__0__000][18]((m[32][0x10](u[g]))+u[g]-H-H-p[g],u[g])));else if H>0B1100101 then if m[0B11100]~=m[6]then else if not(m[0X1C])then else m[0X36]=(-244);end;end;P=P[D];H=(0x14B+(Q-H+u[g]-H-H+u[g]+u[g]));continue;else if H>0 and H<0X6__5_ then D=(A);C=p[g];H=0X60+((m[0X20][0X12]((m[32][8]((m[32][0xF](H,p[g]))))+H<=e[g]and e[g]or Q,e[g]))>=u[g]and p[g]or e[g]);end;end;end;end;until false;else if Q~=0b1000011__ then H=H[P];else H=(H[y]);y=(A);end;end;else if m[0x35]==m[0X28]then(m)[0B1__10101]=(m[0X36]);elseif m[0x7]==m[20]then return 0x40;else if not(Q>=0X3_f)then P=u[g];else if Q==0x40 then A[e[g]]=(A[u[g]]//A[p[g]]);else A[u[g]]=(A[e[g]]<=A[p[g]]);end;end;end;end;else if not(Q<0B10__00111)then if not(Q>=0X49)then if m[0x6]==m[0X3b__]then while m[0X36]do m[0B111011]=0x5c;end;else if Q==0B1001__000 then if not(not(A[u[g]]<=T[g]))then else g=p[g];end;else y=A;a=e[g];y=y[a];end;end;else if Q==0x4A then if m[0X2a]==m[0b0011001]then else if m[0x33]==d then if 67%0b11100%-0b011101010 then(m)[46]=-201;end;m[0X1C],m[0x33]=m[0X19],-(-0x9c);else if not(A[e[g]])then else g=u[g];end;end;end;else(A)[p[g]]=(G[g]-A[e[g]]);end;end;else if Q<0X45 then P=(G[g]);else if Q==0b1000110 then A[u[g]]=(T[g]>i[g]);else H=(A);P=(e[g]);end;end;end;end;end;end;end;end;else if not(Q>=0X98)then if not(Q>=126)then if m[56]~=m[0X6]then if not(Q<0B1110001)then if not(Q>=0X77)then if Q<0x74 then if not(Q<0X72)then if Q==115 then A[p[g]]=(m[0B10_0000_][e[g]]);else A[p[g]]=(f[e[g]][A[u[g]]]);end;else A[e[g]]=K;end;else if m[0X6]~=m[0x0024]then if not(Q>=0X75)then A[e[g]]=A[p[g]]<G[g];else if Q==0X7__6 then a=e[g];else if m[56]==d then return m[0B10]or m[0b111000];end;P=(G[g]);H+=P;y[a]=H;end;end;end;end;else if Q>=0x7a then if m[0B11__0000]==m[0X0020]then m[0B110110]=(-(0X3e<0X98));if not(m[0X35])then else m[52],m[0X33]=-(211%95),-0X4a;end;elseif m[3]==m[0X6]then return-m[0x28];else if not(Q>=124)then if Q==0X7B then y=u[g];A[y](A[y+1],A[y+0X2]);V=y-1;else if m[0X32]~=m[46]then P=P[D];end;H+=P;if m[0X6__]==m[0x33]then else y[a]=H;end;end;else if Q~=125 then y=A;a=e[g];H=i[g];else if m[0X3a]~=m[6]then else return;end;P=p[g];y=y[P];a[H]=y;end;end;end;else if Q>=0x78 then if Q==121 then if not(not(i[g]<=A[u[g]]))then else g=(e[g]);end;else H*=P;(y)[a]=(H);end;else y=A;end;end;end;else if not(Q>=107)then if m[59]==m[0x19]then while m[0X7]do(m)[0X14]=(m[52]);end;else if m[0B1_10111]==m[20]then(m)[0X0019],m[0X38]=-(-0X65),0X67;if not(d)then else return;end;else if not(Q>=0x6_8)then if Q<0x66 then if m[53]~=m[0B101000]then y=(A);a=p[g];end;H=(nil);else if Q~=0X67 then y=A;else D=p[g];P=P[D];H+=P;end;end;else if Q>=0X69 then if Q~=0B11_01_010_ then A[u[g]]=(T[g]~=i[g]);else V=p[g];A[V]();V-=0X1;end;else if m[56]==m[40]then(m)[0b10100]=-(-0X65);end;y=i[g];a=y[0B1000];H=(#a);P=H>0X0 and{};D=m[0B111100](y,P);m[0X2_3](D,_);A[u[g]]=(D);if P then for K=0x1,H do y=(a[K]);D=(y[0X2_]);C=y[0B1];if D==0X0 then if not F then F=({});end;R=F[C];if not(not R)then else R={[0B1]=C,[0X2]=A};(F)[C]=(R);end;(P)[K-0B1]=(R);else if D~=0x1 then P[K-0X1]=(f[C]);else(P)[K-0B1]=A[C];end;end;end;end;end;end;end;end;else if not(Q>=110)then if Q<0X6C then s=v[2];Z=(v[0X5]);w=v[0b100];v=(v[0B11]);else if Q~=0X6D then P=(e[g]);else if F then for K,q,I in F do if K>=1 then q[0B1__0]=q;q[3]=(A[K]);(q)[0X1]=0B11;F[K]=(nil);end;end;end;return true,u[g],0X1;end;end;else if Q>=111 then if Q~=0X70 then for K=u[g],e[g],0X1 do(A)[K]=nil;end;else(A)[e[g]]=(i[g]);end;else P=T[g];H=H[P];end;end;end;end;end;else if m[0b101010]==m[32]then while 43^0b10000001*m[0X2a]do(m)[0X1C]=m[0X2];m[54],m[56]=m[0B11__1011],(m[34]);end;else if Q<0X8b then if not(Q>=0X84__)then if not(Q>=0b10000001)then if m[0B11100]~=d then else m[0B1110__00],m[0X1C]=-226,m[0x1d];end;if Q<0X7__F then y=(nil);a=(nil);H=(nil);P=(0B11011);repeat if P==0X3e then a=0;H=4503599627370495;break;else y=-0X3d6;P=(-0X40+((m[32][15]((m[32][8]((m[0x20][0B10011](Q,Q,P))+P+P,P,P)),(P)))>P and Q or Q));continue;end;until false;a*=H;H=(m[0X20]);D=nil;P=(0X6);while true do if m[0B10100]~=d then if P<=6 then D=0XF;P=(-339+(m[0X20][15]((m[0x20][0X5]((m[0B100000][0X1_0]((m[0x20][0Xa](Q))-P)),(P)))~=P and P or P,(P))));else H=H[D];break;end;end;end;D=m[0X2__0__];C=0x11;D=(D[C]);R=(nil);P=0x53;repeat if P>0X16 and P<0X7D then C=m[0X20];P=(-0X1e+((m[0X20][0x13]((m[0X20][0X11]((m[0X2__0][0X5_](P+Q,(9)))))+Q))-P));continue;else if P>0X53 then if m[0X0028]==m[0B110100]then else C=(C[R]);end;R=(Q);break;else if not(P<83)then else R=(0X10);P=0b11111_01+(m[0B10000__0__][0X14]((m[0X20][10](P+Q+Q<Q and P or P,P,Q))~=P and P or P,(P)));continue;end;end;end;until false;if m[0b10]==d then else C=C(R);D=D(C);P=0B1010111;end;repeat if P<=0b100001 then if not(P<=12)then if P==0X1e then H=H(D,C);break;else if D then D=Q;end;if m[7]~=m[0X20]then else while m[0B1_11010]do m[0X0019]=(m[0X30]);end;end;P=(-32407+((m[0B100000][0xf__]((m[0x20][0X13](P+P-P,Q,Q)),(0b1000)))-Q+P));end;else if m[55]==m[0X19]then if m[0x24]then m[0x24_],m[0B1_1011__0]=m[0x38],0B111001;return-m[0X2E];end;end;if not D then D=z[g];end;P=(0X105+((m[0x20][0X11]((m[0x20__][0X9](Q))))+P-P-Q-P));continue;end;else if not(P>0B1001010)then if m[7]==m[0b100000]then else D=(D>C);P=0X9E+((m[0X2_0][0X1_1]((m[0X20][0XF]((m[32][0X12]((m[0X2__0][0X11](P)),(m[32][0B111]('>\i8',"\0\0\0\0\0\z  \x00\0\24")))),(0B11011)))==Q and Q or Q))-Q);continue;end;else if m[0B100100]==m[0B101110]then while m[0X14]do(m)[50],m[0X7]=0X48,(-0Xb0~=-0b10101111);end;elseif m[0X32]==m[0X22]then if not(-0B11000001_)then else return m[0X3__0];end;m[0b110010]=-m[0x30];else if not(P<=0B1010111)then C=(0X3);P=-0XDE+(((Q+P>=Q and Q or Q)<P and Q or Q)+Q-Q+Q);else if m[0B100000]==m[0X30]then while true do(m)[0b100010]=0B11011010;end;end;C=(z[g]);P=(0X4a+(m[0x0020][0X12]((m[32][0X11]((m[0x20][0XF](Q<P and Q or P,(0X7)))+Q==P and Q or P)),(0x1))));end;end;end;end;until false;D=(Q);H+=D;P=(0X42);repeat if P>0X39 then if m[0x34]==m[0X2e]then return;else if P==66 then D=(z[g]);P=-405+((m[0X20][15]((m[0X20][0B10__00]((m[0X20][5](P,(0B10000)))-Q+Q,P,P)),(0X13)))-P);continue;else D=Q;H-=D;break;end;end;else if m[0B11100]==m[0X6]then else H-=D;end;P=-152+((m[0X20][0X9]((P<=P and Q or Q)-P))+Q-P+Q);continue;end;until false;if m[0X38]==m[0X6]then else D=Q;end;H+=D;P=0X15;repeat if m[0x24]==m[0b100010]then(m)[0x2_E]=(-(74>145));return;elseif m[7]==d then while-0X9e do(m)[0X3b]=(m[0B0011100]);return;end;else if P>21 then y+=a;break;else a+=H;P=(-1935+((m[0x20][0X14]((m[32][16]((m[0b1000__00][0X13__]((m[32][0b10001](P)))))),(P)))-P+P));continue;end;end;until false;z[g]=y;P=3;repeat if m[0X2b_]==m[0X28_]then if not(-m[0X2e])then else d,m[0X7]=m[0x37],(m[0X1__D]);end;else if P<6 then y=(A);P=-117+(((m[0X20][0b1010__]((m[0b1000__00][0x9](Q)),Q,P))<=P and Q or P)-Q-P+Q);elseif P>0b110 then H=A;break;else if P>3 and P<0B101101 then a=(u[g]);P=44+(m[0x20][0B10001]((m[32][0X1_3](Q-Q+P+Q>=P and P or P,Q,Q))));end;end;end;until false;if m[0X38]==m[40]then else D=(e[g]);P=(0B10__010);while true do if P==73 then D=A;P=0Xda+((m[0X2__0][0X011]((m[0B1000__00__][0Xf__]((m[0X2_0][0X5](P,(m[0X20][0X07](">\i\z\x38","\0\0\0\0\0\0\z  \0\25"))))-P,(0X1d)))))-Q-P);elseif P==20 then C=(p[g]);P=-81821+(m[0X00_20][0B10010]((m[0x20][0x13]((m[0x20][17](P==Q and P or Q))==P and Q or P))>P and P or P,(P)));continue;else if P==18 then H=H[D];P=-4294967221+(m[0X20][0X13]((m[0X20][0B10100](((m[0B100000][0x9](Q))~=Q and P or Q)-P,(P)))-P,P));continue;else if P~=0B1100__011 then else if m[55]~=m[0B011001]then else return;end;D=(D[C]);break;end;end;end;end;end;P=0b0_;repeat if P>0 then(y)[a]=H;break;else if not(P<0X5F)then else H+=D;P=(221+((m[0X20][0XF](P+P,(P)))-Q-P+P-P));continue;end;end;until false;else if m[0X2]==d then while-m[0X14]do m[0B11001],m[0B101010]=m[0X3b],0X9a;return;end;else if Q~=0X80__ then a=e[g];H=A;else if m[0x3__7]==d then while m[0X2b_]~=m[0X36__]do(m)[0B10100],m[0b101011]=m[0X2a],((0X84-0XA_c)*(0Xe2_%0X0022));return-m[2];end;return 0B011101_010;end;P=p[g];H=(H[P]);end;end;end;else if Q>=0x82 then if m[0B10]==m[0X14_]then if not(0b11001__0)then else return;end;while m[0X2b]do return-m[0B111];end;else if Q==0X83__ then if m[0X7]==m[0X6]then return 59^(0X8a/0X7__0);else if not(A[e[g]]<=A[u[g]])then g=p[g];end;end;else A[e[g]]=f[u[g]];end;end;else H={};(y)[a]=H;end;end;else if not(Q<0X087)then if Q<137 then if Q==0B100010_00 then A[u[g]]=(A[e[g]]~=A[p[g]]);else(A)[p[g]]=T[g]<G[g];end;else if m[0X6]==m[0X35]then else if Q==0X8a then if m[0B11101]~=d then v={[0x5__]=Z,[0x4]=w,[0X3]=v,[2]=s};y=(e[g]);w=A[y+0X2]+0X0;Z=(A[y+0X1]+0);end;s=(A[y]-w);g=(u[g]);else y=(nil);a=nil;H=111;while true do if H==111 then y=(165);H=(-4294967289+((m[0B1_00000][0X5]((m[0x0020][18]((m[0B100000][0x11]((m[0B100000][0XA__](H,H,p[g]))))-p[g],p[g])),p[g]))+p[g]));else if H==0x2 then if m[0x2_]==m[0b00110]then while m[0X3__0]do m[2]=(0B1_1101_000);return;end;end;a=0X0;break;end;end;end;if m[28]~=m[34]then P=4503599627370495;end;D=nil;H=(114);while true do if H<67 then P=(m[0B100000]);H=(0X69+((m[0B1000_00][10]((m[0B100000][0b1010]((m[32][0Xf](Q,p[g]))+H,Q))+H,Q))+p[g]));elseif H>0X0072 then D=10;H=(-0X3_1+(p[g]+p[g]+Q-p[g]-Q-p[g]+H));else if H<0x46 and H>0X29 then P=P[D];H=-4294967149+((m[0x20][0B100__0]((m[0X20][0b010000](p[g]+H-H+p[g])),Q))+H);elseif H>0x43 and H<0x72 then if m[0b101__011]~=m[0B100000]then D=(m[0X20_]);end;break;else if H>0B1000110 and H<0X74__ then a*=P;H=0X29+((m[32][0X5](H-H,p[g]))-H+H-Q+Q);end;end;end;end;if m[0B10001_0]~=m[56]then C=0b1001;R=(nil);o=nil;H=0X3D;repeat if H>0X6A and H<0B1111000 then C=(C[R]);R=(m[0X2_0]);o=0Xa;H=-0B001111__1+((m[0x0020_][0x8](((m[0x20][0Xa](Q))==H and H or Q)>H and Q or Q))+H-H);continue;elseif H>119 then R=(0B1_00__0);H=0X2+(m[0X20][16]((m[0X20][0x10]((Q<=H and p[g]or Q)+H-p[g]-Q))));continue;else if H<0x77 and H>61 then R=R[o];break;else if not(H<0X6a)then else D=(D[C]);C=(m[0X20_]);H=-4294967105+((m[0X20][0b10000](H))+p[g]+p[g]-Q+H+H);end;end;end;until false;end;o=m[0X020];Y=nil;b=nil;H=(28);repeat if H==0x1C then if m[0X3A]==d then repeat return;until false;while m[0X2A]do(m)[0X2a]=(m[0X3__2]);return 0B01110111;end;end;Y=0X10;H=-0X5E+((m[0X20][0X11__]((m[32][0X5]((m[0b100000][0B0101]((m[0B100000][0x014](H+H,(H))),p[g])),(H)))))+Q);elseif H==46 then if m[0B110001]~=m[0X6]then else m[0X28],m[49]=m[0x1C],m[0X36];m[58]=0Xb2;end;Y=(m[0X20]);H=(-0X1fFFffBE+(m[0b1000_00][0X12]((m[0B100000][0B1010](H-p[g]+Q,H))-Q-p[g],p[g])));else if H==0X35 then b=0B10000;break;else if H~=0X4b then else o=(o[Y]);H=(0x2d+(m[0b100000__][0b1010]((m[0X20][20]((m[0X20][18]((m[32][0B10011](H,H,Q))>H and Q or p[g],p[g])),p[g]))+H,p[g])));end;end;end;until false;H=(0X6_3);repeat if H>0X63 then b=z[g];break;else if H<0B1100110 then Y=Y[b];H=(0B1100_1001+((m[0X20][0X11]((m[0X20][0X10]((m[0X20][17]((m[32][0b100__1]((m[0X0020][0x13](H))))))))))-H));end;end;until false;Y=Y(b);H=0X11_;while true do if H<0b1001110 and H>17 then R=R(o);H=106+(m[32][0X011]((((m[0X20][0B1010]((m[32][0x1__3](H,H,H))))>H and H or Q)~=Q and H or Q)-p[g]));else if H<85 and H>0B111__100 then if m[34]~=m[46]then else return m[0x3];end;Y=(Q);C=C(R,o,Y);H=(-335544234+(m[0X20][18]((m[0X00_20][18]((m[0X20][0X10__](H-H<Q and Q or H))+H,p[g])),p[g])));elseif H<0x3c then o=o(Y);H=-4294967098+(m[32][0B10000]((m[0B10__0000][0X14]((m[0x20][0x11]((m[0X20][0B10000]((m[0B1000_00][0x010](Q)))))),p[g]))+Q));continue;else if H<0X6b and H>0x4E then if m[29]==m[25]then if not(m[0X36])then else(m)[0B100010]=154;return;end;end;R=p[g];break;else if not(H>0B101010_1)then else o=Q;if m[0B11001__]~=m[0B100000]then H=(0X35+(m[0X20][0X9]((m[32][0X11](((m[0B100000][0X13](p[g],H))<H and H or Q)-H))+H)));end;continue;end;end;end;end;end;H=0X7c;repeat if H~=43 then C-=R;H=-0xE7+(m[0B00100000][10](((m[0X20][0B10011](H-Q+Q,p[g]))<=p[g]and Q or Q)+Q));else R=z[g];C-=R;break;end;until false;D=D(C);H=(0x53);repeat if H==0B1__0__10011_ then if m[0B101011]~=m[0X2__0]then C=(Q);P=P(D,C);end;H=(-0X3D+((m[0X20][0X1_4](((m[0X20][0b001111](H,p[g]))>=p[g]and H or H)-H-p[g],p[g]))<p[g]and H or H));continue;else if H~=0X16 then else if m[0X14]==m[0X2]then if(0x98__-0b1010110__)/0x5F then return m[0X33];end;(m)[0X7]=(m[0X3_8]);end;a+=P;break;end;end;until false;y+=a;z[g]=y;y=A;H=0X75;repeat if H==0B1110101 then if m[0X31_]==m[0X06]then(m)[0X32_],m[0B10000__0]=0B1001110,(0B1000_0010);if not(0X3_a<=m[0B111])then else return;end;end;a=p[g];H=-0x25+((m[32][0b1001]((m[0x20][0x10](H-H))~=H and H or H))+Q~=Q and H or H);continue;else if H==80 then P=(nil);break;end;end;until false;(y)[a]=(P);end;end;end;else if Q<0x85 then(A)[e[g]]=not A[p[g]];else if Q==0X86 then A[u[g]]=m[0X2c](e[g]);else H=f;P=(u[g]);H=H[P];end;end;end;end;else if Q>=145 then if Q<0B10__010100 then if Q<0B100__10010 then P=p[g];H=H[P];else if Q==0B1_001_001__1 then else D=(p[g]);P=(P[D]);end;end;else if not(Q<150)then if Q==0X97 then(A)[u[g]]=(f[e[g]][i[g]]);else A[e[g]]=(-A[p[g]]);end;else if m[0x14]==m[42]then while m[0X31]<0X2f_/0B1100100 do return m[0X2b];end;else if m[0X14]==m[0X35]then if m[29]then m[55]=(-0B1__10101~=m[0x7]);(m)[51],m[0X3]=m[56],(m[40]);end;return;else if Q~=0X95 then A[p[g]][G[g]]=A[e[g]];else if m[0B11101]~=m[0x6]then else return;end;y=nil;a=(nil);H=nil;P=0xA;repeat if m[0b11100__0]==m[0B101__000__]then(m)[0x37],m[0B101010]=m[0B10101__0],0X06e;if 0b1010001 then return;end;elseif m[0B100000]==m[0X35]then return;elseif P>0X4C then a=0;P=0x1F+((((m[0X20][0X8](Q))==Q and Q or Q)+Q>Q and P or P)+P-Q);else if P>0Xa and P<97 then if m[0B101010]==H then return 0X2E;end;H=4503599627370495;a*=H;break;else if P<0X4c then y=-0x3d;P=-4294966967+(m[0x20][8]((m[0B10000__0][0X9]((P>=Q and P or Q)+P))-Q+P,Q));continue;end;end;end;until false;H=m[32];D=(0x8);C=(nil);P=0X2e__;while true do if P==0X10 then C=0X10;P=(329+((P+P<P and P or P)+P-Q-Q-P));else if P==0X2f then if m[0x3B]~=m[0X20]then D=D[C];end;P=(-78+((m[0X20][0b10011]((m[32][0X14](P-P,(0)))-Q==P and P or P,Q,Q))-P));continue;else if P==66 then C=m[0X20];break;else if P==0B101110 then H=H[D];P=(-1220555+(m[0X020][0x12]((m[0X20__][19]((m[0B1__0__0000][0b1111]((m[0B100000][0x13](Q,Q,P)),(m[0x2_0][0X7]('\u{003E}i8',"\x00\x00\0\z \x00\0\0\0\6")))),P,Q))-P==P and Q or Q,(0B1_0011))));else if P~=0B110101 then else D=(m[0B10__0000]);P=-0X85+((m[0X20][0XF]((m[0X20][0x5]((m[0X20][0X13](P))+Q-Q,(26))),(0X0019)))>P and Q or Q);end;end;end;end;end;end;if m[0B100_100]~=m[0X28_]then else if not(m[7])then else m[0X36]=0B10010101;m[46],m[0B100010]=m[0X37],0B10011110;end;end;if m[6]~=m[0B0111011]then R=9;C=(C[R]);R=(m[0b100000]);end;o=0XA;R=R[o];o=(z[g]);Y=z[g];b=nil;P=0B100101;repeat if P==64 then R=R(o,Y,b);o=(z[g]);break;else b=z[g];P=(0X5f+((m[32][9]((m[0B0100000][0X0012](P+Q-P+P,(14)))))-P));continue;end;until false;P=0x20;repeat if P>0b1__00__000 then D=D(C);C=(Q);break;else R-=o;C=C(R);P=0B1010010+(m[0B100000][5]((Q+Q-P+Q>Q and Q or Q)<=Q and Q or Q,(P)));continue;end;until false;D=D>C;P=(84);while true do if P<0x54 then if not(not D)then else D=Q;end;break;else if P>0X23 then if not(D)then else D=(z[g]);end;P=-0B10000101+((Q-P+P<=P and P or Q)-Q+P+P);end;end;end;H=H(D);P=(61);repeat if P>61 then if m[0B111010]==m[0X19]then return;end;H-=D;D=(Q);break;else if not(P<0b01111000)then else D=z[g];P=(-4294967175+((m[0X2__0][0x10]((m[32][0X14]((m[0x20][9]((m[32][0B1010](Q,P,Q)))),(17)))))+P-P));end;end;until false;H+=D;a+=H;y+=a;P=(93);while true do if P>0b11000 then(z)[g]=(y);P=(-0B1000101+((m[0X2__0][5]((m[32][0X10]((m[0X20][9]((m[0X20][0XA](P-Q,P,P)))))),(0X14)))==P and P or P));elseif P<0b110__00 then a=(u[g]);break;else if not(P<93 and P>23)then else y=A;P=-0X225+((m[0X20][0Xf]((m[0X20][0x12](Q-P,(P))),(P)))+Q+Q+Q);end;end;end;if m[55]==m[6]then else H=e;end;y[a]=H;end;end;end;end;end;else if not(Q>=0B10__001110)then if m[0X33]==m[0x2e]then while m[0X33]do return;end;elseif m[0X1C]==m[0b110]then if not(-0x5f*m[0b110011])then else return 0x85;end;(m)[0B011100]=(0B10101011>102)+-28;else if Q<140 then if m[0X24]==m[0X6]then else a=e[g];end;H=(A);P=(u[g]);else if Q~=0X8D then y=(f[e[g]]);y[0b10][y[1]]=(A[p[g]]);else y[a]=(H);end;end;end;else if not(Q<0x8F)then if Q==0X9_0 then m[0X20][u[g]]=A[e[g]];else P=(A);D=(p[g]);P=(P[D]);end;else P=(G[g]);end;end;end;end;end;end;else if not(Q>=0B101__10001)then if Q<0XA4__ then if not(Q<0b10011110)then if Q>=0Xa1 then if not(Q<0Xa2)then if Q~=0xa3_ then if m[0X35]~=m[0b0100010]then else while-(-0XED)do m[0x3]=(-m[0X34_]);(m)[46],d=m[42],(m[0x14]);end;end;(A)[e[g]]=(A[p[g]]>A[u[g]]);else H+=P;end;else if m[0B110110]==d then else a=p[g];H=_;end;P=G[g];end;else if m[0X20]==m[0X6]then elseif not(Q<159)then if Q==0xA0 then y=f;a=e[g];y=y[a];else(A)[e[g]]=G[g]..A[p[g]];end;else(A)[e[g]]=(A[p[g]]-G[g]);end;end;else if m[0X28_]==m[34]then while m[0B10]do return m[0X3A];end;if m[0B1_11000]then return 0XEa;end;elseif m[0X2]==m[0X06]then if m[0B1__11]then m[0B111]=(m[0x003]<0X6D^0XeC);return 139;end;else if Q<0X9B then if Q>=153 then if Q~=154 then A[e[g]]=(A[u[g]]*i[g]);else if m[59]==m[0X14]then if not(223)then else return-42>(0x92>=0B10101000);end;end;A[u[g]]=T[g]<=i[g];end;else A[u[g]]=(i[g]<=A[e[g]]);end;else if m[40]==m[3]then else if not(Q>=156)then a=(T[g]);H=(i[g]);y[a]=H;else if m[0B10__1110]==m[0X32]then else if Q==0X9d then a=(A);H=(p[g]);a=(a[H]);else if m[0X38]~=d then A[e[g]]=A[u[g]][A[p[g]]];end;end;end;end;end;end;end;end;else if Q<170 then if Q<0Xa7 then if not(Q>=0b10100101)then if m[0x28]~=m[0x14]then else if not(m[0X32])then else return;end;end;(A)[p[g]]={};else if Q~=166 then(A)[p[g]]=(nil);else if m[0b101110]~=m[0B110__001]then else if m[0X1d]then return m[28];end;return m[0b110001];end;if m[0X2B]~=m[6]then y=(u[g]);a=(e[g]);for K=y,a,0X1 do if m[0x2e]~=m[50]then elseif 0b100101 then(m)[0B10]=(m[46]);m[0B110110]=-(0X4a+0B111010);end;if m[0X001c]==m[0X6]then while-m[0X2a]do(m)[0X3],m[48]=m[0X20],0xC_0;m[0x22]=m[56];end;while-(0x1A+199)do return m[0X30];end;end;H=(A);P=(K);K=nil;H[P]=K;end;end;end;end;else if Q<168 then P=e[g];H=H[P];else if Q~=169 then a=e[g];H=A;P=(p[g]);else A[e[g]]=A[u[g]]>i[g];end;end;end;else if Q>=0Xad then if Q<175 then if Q==174 then A[p[g]]=G[g]+T[g];else y=(y[a]);a=G[g];H=(A);end;else if Q~=0Xb0 then if m[2]~=m[0X28]then A[p[g]]=A[e[g]]>=A[u[g]];end;else P=(u[g]);H=(H[P]);P=(A);end;end;else if not(Q>=0B10101011)then A[e[g]]=(i[g]<A[u[g]]);else if m[0B110__111]~=m[0x22]then else(m)[0x2e],m[2]=0xD,((20+80)^m[43]);end;if Q==0Xac then local K=(p[g]);if m[49]==m[25]then while-0B1001110_0>m[0b100000]do(m)[0b110000]=(m[55]);(m)[0B110011],m[0X31]=m[0X30],m[0B11100];end;while m[0X07]^m[0X37]do m[0b11101_1],m[0X20]=0B1111101>=m[0x24],(m[0B1010__11]);return;end;elseif m[0B110100]==m[0X6]then if not(-0Xa4*-0X40)then else return-(-0x9F);end;else if not(F)then else for _,q,I in F do if not(_>=K)then else if m[0B10]~=m[0X22]then(q)[0X2]=q;end;q[0x003]=(A[_]);q[0X1]=(0B11);F[_]=(nil);end;end;end;end;else A[p[g]]=p;end;end;end;end;end;else if Q<0b10111110 then if Q>=0XB7 then if m[0X2B]==d then repeat d,m[0X34]=m[0X2__B]==m[50],(m[0X22_]);until false;while m[0x3B]do C=m[0B10__101_1_];d,R=0x7__2,m[6];end;end;if not(Q<186)then if Q<188 then if Q==0b10111011 then y=(nil);a=(nil);H=nil;P=(0X3E);while true do if P==0X20 then H=4503599627370495;P=(0x52+(m[0X20][0B10100]((m[0B100000][0Xa]((m[32][0X9](Q-P<P and Q or Q)),P,P))<=Q and P or P,(P))));elseif P==62 then y=(0X93);P=(-4294840378+(m[32][0b10011]((m[0x20_][0X8]((m[32][0Xf_]((m[0B100000][0B1000](P-Q)),(0xA__))),Q,P))+Q,P)));continue;elseif P==82 then a*=H;H=(m[0B10000_0]);break;else if P==0x5 then a=(0X0__);P=(-4294966914+((m[32][8]((m[0X0020][9]((m[32][18](P,(P)))~=Q and Q or P))-Q,Q,Q))-Q));continue;end;end;end;D=(0X9);C=nil;R=(nil);P=(123);while true do if P>0 and P<0b1100101 then D=(m[0X20]);C=0X13;P=-4294967176+(m[32][0B10000]((m[0B100__000][10]((Q>=P and Q or P)+P+Q+P,P))));continue;elseif m[0X20]==m[28]then return m[0x7];else if P<0X7b and P>30 then D=(D[C]);C=(m[0X20]);P=(m[0X20][0X14]((m[0X20_][0X9]((m[0B100000][0xa_]((m[32][0B001010]((m[0X020][0X5](P,(m[0X20][0X7]('\60i\x38','\u{0C}\0\0\0\0\0\u{00}\0')))),P,Q)),Q,Q))-P)),(25)));elseif P<30 then R=0X10;break;else if m[0X1c]==m[0X22]then if o then return;end;if Y==m[0X38]then else m[53],m[0x1C]=o,(-0B1010111);end;else if P>0B01100101 then H=H[D];P=0x1E+(m[0X20][0B1_0001]((m[0X20][0xA]((m[32][0B10000](P)),P))-Q-Q-P));continue;end;end;end;end;end;local K=118;C=(C[R]);o=(nil);P=0X45;repeat if K~=0X76 then m[40],m[0X2a]=K,m[0B10];elseif P==0X45_ then R=m[32];P=(0B1100000+(m[0B100000][0Xa]((m[32][0XA]((m[0X20][0B1__0011](P,Q,P)),Q,Q))+Q-Q+P,Q,Q)));else if K==117 then while K do return;end;m[0X24],m[0X37]=K,-m[0b1__0101_0];else if P~=0X60 then else local _=0XF9;if _~=0B11_11100 then o=0x5;break;end;end;end;end;until false;if m[0X2e]~=m[0X2A]then else return m[0X31];end;R=(R[o]);Y=(nil);P=0B111011;repeat if P==0B10_11110 then Y=19;break;else o=(m[32]);P=0X00119+((m[0B100000][0X8]((m[0x20][8]((m[0B1000__00][16]((m[32][16](Q))))<=Q and Q or P,P)),Q,P))-Q);continue;end;until false;o=o[Y];b=nil;P=(0X68);repeat if P==0x68 then Y=m[32];P=(-0x94+((m[0X20__][0X8]((m[32][0x0F](Q-Q,(0X11)))-P+P,Q,Q))>=Q and Q or Q));continue;else if P==0b1_00111 then b=(0x9__);P=0X5A+(m[0X20][0X14]((m[0X0020][16](P+P<=P and Q or Q))+Q+Q,(0X1D)));else if P==0x5A then Y=Y[b];break;end;end;end;until false;local _=0XEB;b=(Q);P=(0B100101);repeat if P>0b100__101 then R=R(o,Y);break;else Y=Y(b);o=o(Y);Y=(0X1A);P=-123+((m[0X20][0X8]((m[0x20_][0X8](P,P,Q))-Q-P))-Q>=Q and Q or P);continue;end;until false;P=(0B110010);while true do if P==105 then if _==242 then else R=(Q);end;break;else if P==0X32 then C=C(R);P=0X35+((m[0x20][15]((m[0B100000][0B10001](Q+Q)),(0B1)))-P+P+P);end;end;end;C-=R;P=0X2E;while true do if P<53 then if m[0x31]==m[40]then while-0X5f do return m[0B10];end;m[0B1110__10]=K;end;D=D(C);P=-4294967055+(m[32][0X10]((m[0b0__0100000][0X13](Q+P+P+P))>Q and Q or P));continue;else if P>46 then C=Q;break;end;end;end;if K==0B11110 then return m[0B11];end;D=(D==C);P=(0B111101);repeat if m[0X1d__]==m[0B100010]then if not(_)then else(m)[0X2],m[0B11]=K or-0XE6,-(0x6F or 216);end;elseif P<0X6a then if K==0XC3 then m[0X7]=(-(-0xaf));else if not(D)then else D=(z[g]);end;end;P=-0b10000__000+(m[32][0Xa]((m[0B100000][0B001000](P,P))+P+P-P+Q));continue;elseif P>0X3D and P<0x77 then if K~=118 then else a+=H;y+=a;break;end;elseif P>0b1110111 then if not D then D=Q;end;P=-188+(((m[0B010__0000][0B10011]((m[0x20][20](P,(0B10111))),P))>=P and P or P)+P-P+Q);else if P>0X6A and P<0x78 then H=H(D);P=75+(m[0B100000][9]((m[32][0Xa]((m[0B100000][0X11](Q+P+P-P))))));end;end;until false;(z)[g]=(y);y=(A);P=(99);while true do if _==188 then elseif P~=0X66 then a=p[g];P=0B1001110+(m[32][0x9]((P+Q-Q~=P and P or P)+Q-P));continue;else H=(p);y[a]=(H);break;end;end;else y=p[g];a=u[g];H=A[y];(m[0XC__])(A,y+0X1,V,a+0x1,H);end;else if Q==0b1011110_1 then(A)[u[g]]=u;else v={[0X5]=Z,[0X004]=w,[0X3]=v,[0X2]=s};V=(p[g]);y=m[41](function(...)m[0X1f]();for K,z in...do(m[0X1f])(true,K,z);end;end);y(A[V],A[V+0X1],A[V+0B10]);s=(y);g=u[g];end;end;else if Q<0B101110__00 then y=A;a=(u[g]);else if Q==0B10111001 then A[e[g]]=A[u[g]]%i[g];else a=e[g];H=f;end;end;end;else if Q>=0B10110100 then if Q<0Xb5 then H=H[P];else if Q==182 then if not(not A[p[g]])then else g=u[g];end;else y=e[g];a=(0B0);for K=y,y+(u[g]-0x1)do A[K]=h[E+a];a+=1;end;end;end;else if Q>=0x00B2 then if Q==0X0_0__B3 then(A)[p[g]]=A[e[g]]%A[u[g]];else if F then for K,f in F do if K>=0X1 then(f)[0B10]=f;f[0B11]=(A[K]);(f)[0X1]=0X3;F[K]=nil;end;end;end;return;end;else H=y;y=(0b1);end;end;end;else if not(Q<0B110_0__0100)then if m[0X1_9]==m[58]then if d then return-m[0B101110];end;return-m[0x22];else if not(Q<0xc7)then if Q<0Xc9 then if Q==200 then A[p[g]]=A[u[g]]==T[g];else A[u[g]]=(m[21](A[e[g]],i[g]));end;else if Q~=0B11001010 then y=A;a=(u[g]);y=y[a];else H=G[g];end;end;else local K=0b1000101_0;if Q>=0xC5 then if K==0X20 then else if Q~=0b11000110 then if m[0X28]~=m[0b00110110]then else if not(0Xc1)then else return;end;if 0XF6+m[0B10100_0]then return-K;end;end;P=u[g];H=(H[P]);else y=u[g];a=(N-W-0b1);if not(a<0B0)then else a=-0B1;end;if m[0X1c]==m[0x6]then else H=0;for f=y,y+a do A[f]=(h[E+H]);H+=0X1;end;end;V=y+a;end;end;else if K==0B10000110 then m[0X20]=(K);while-(-0B100111_0)do(m)[0X02B]=(0B11101101^0Xb6)^K;m[0X34]=-0X00__4f%m[40];end;else if K~=0X8A then if not(0x76)then else d=(m[0B11101]);m[56]=(K);end;else if A[e[g]]~=G[g]then else g=p[g];end;end;end;end;end;end;else if Q>=0XC1 then if not(Q>=194)then(A)[p[g]]=(A[e[g]]+G[g]);elseif Q==0Xc3 then y=p[g];a=(u[g]);V=(y+a-0B1);if F then for K,f in F do if not(K>=1)then else(f)[0X2__]=(f);(f)[0B11]=(A[K]);f[0B01]=0x3;F[K]=nil;end;end;end;return true,y,a;else if m[0B100_100]~=m[40]then H+=P;end;end;else if Q>=191 then if Q~=0Xc0 then if m[0X3b]~=m[0B101110]then else return;end;if m[0X2B]==m[0X28]then else y=e[g];A[y]=A[y](A[y+0X1]);end;V=y;else y=e[g];V=y+p[g]-0X1__;(A)[y]=A[y](m[29](A,V,y+0B1));V=(y);end;else H=H[P];P=A;end;end;end;end;end;end;end;g+=1;until false;end);if not(X)then if not(F)then else for K,f in F do if K>=0X1 then(f)[2]=f;f[0b11]=(A[K]);f[0B1]=3;F[K]=nil;end;end;end;if m[2](n)~="\u{73}t\x72\x69ng"then m[0X1E](n,0);else if not(m[0B100](n,'\58(%\100+)[:\r\x0A\93'))then m[0B11110](n,0);else m[0x1E]('Lura\ph\x20S\u{063}\u{0072}\x69\pt:'..(B[g]or'\u{0028}in\116e\u{0072}na\u{006C}\41').."\z  \x3A\x20"..m[0B11010](n),0X0);end;end;else if n then if k==0X1 then if m[0b1101__10]~=m[0x22]then else while 206 do m[0B1010__0],m[6]=m[52],(m[50]);end;return m[0B110110_];end;return A[t]();else return A[t](m[29](A,V,t+0X1__));end;elseif not(t)then else return m[29](A,k,t);end;end;end;return d;end);if not(not U[22])then x=(U[0B10110]);else x=-0X26+((((M.FS(U[2161],(U[0X5315])))+U[2235]==U[14895]and U[0x5315]or U[26866])+U[21269]==U[2058]and U[0X3Ba4]or U[0x66__Da])==U[0X3BA4]and U[0X33_a9]or U[21171]);(U)[0X16]=(x);end;elseif x==0B1100 then O,x=M:fI(m,x,U,O);continue;elseif x==0X65 then(m[0X20])[0XC]=(M.v.ceil);break;elseif x==0B1011000 then(m)[58]=function()local K,f,N=(0X53);repeat if K==0X53 then f=m[0X34]();K=(0x16);else if K~=0X0016 then else N=m[0B10_10](f);(m[0b1_1000])(N,0,m[0x2_5__],m[0B1],f);break;end;end;until false;for K=0X025,0Xa__F,0x7c do if K>0X25 then return N;else if not(K<0Xa1)then else(m)[0x1]=m[0b1]+f;end;end;end;end;if not U[10820]then x=0X3e+(M._S((M.QS((M.TS(U[21269]+U[14094],(U[0X14Ed]))),U[26334]))-U[0X4aae]+U[2416]));(U)[0x2A44]=x;else x=(U[10820]);end;elseif x==0x1e_ then m[0x20_][0B1_001]=(M.H.countlz);m[0X20][0Xf]=M.xS;if not U[14762]then x=-289040795+(M.TS((M.FS((M._S((M._S(U[0X970]))))+M.X[6]-U[19118],(U[0X5__9C0]))),(U[0X7e10])));U[0x39aA]=x;else x=U[14762];end;continue;elseif x==0X21_ then(m)[61]=(function()local K,f,N,B,G,T,e,z,u;B,T,e,G,u,N,z=M:qI(e,B,N,m,T,G,u,z);local p,i,d,V;i,d,p,V=M:EI(p,d,i,V);local A;u,i,p,K,A,V,d,f=M:o_(i,m,e,V,G,N,B,d,T,A,u,p);if K==-0B1 then return;else if K==-0X2 then return f;end;end;A=126;while true do if A<0X7E then for K=0X1,m[49]()do z=M:H_(m,z,V);end;return N;else if A>0B100_010_1 then A=(0B10__00101);N[0X9]=V;end;end;end;end);S=function()local K,f,N,B;K,B,f,N=M:f_(N,m,f,B);if K==-1 then return;end;K=nil;K,B=M:q_(K,B,f,N,m);(m)[45]=nil;for f=0X4E,172,0b1010__010 do if f==0Xa0 then return K;else if f==0X4E then M:E_(m);continue;end;end;end;end;if not(not U[14461])then x=U[14461];else x=0b1011110+((M.FS((M.TS((M.X[9]-U[0X4AAE]<M.X[0X1]and M.X[5]or U[21785])+U[0XE0f],(U[0X2f97]))),(U[0X2_F97])))-U[26334]);U[14461]=(x);end;else if x==123 then j=S();if not U[0x5FB7]then x=0X21+((M.X[7]-U[0X1Fb__8]+U[0X33a9]-U[12183]-U[0X2f97]>M.X[0x9_]and U[15268]or U[2161])-U[0x66de]);(U)[0x5FB7]=x;else x=U[24503];end;elseif x==0b11101 then(m)[0X39]=select;if not U[0X7639]then x=0X40+(M._S((M.TS((M.xS(U[19118]+U[14094],(U[26868])))-M.X[2],(U[8774])))-U[29032]));(U)[0x7639]=x;else x=U[0X7639];end;continue;elseif x==0b101011__1 then m[0X3b]=(function(...)local K=m[0X39]('\z#',...);if K~=0X0 then else return K,m[0x22];end;return K,{...};end);if not U[12499]then x=0B10011__001+((M.TS((M.xS((M.hS(U[4044]-U[0x57c_b])),(U[0X4AaE]))),(U[0X3A2F])))+U[0X53_1_5]-U[10820]);U[0X30D3]=x;else x=U[12499];end;else if x==0X36 then x=M:i_(U,x,m);continue;end;end;end;until false;local K;x=(0X4e);while true do if x>98 and x<0x73 then x=M:g_(U,m,x);elseif x<79 and x>48 then x=M:N_(m,x,U);continue;else if x>0X55 and x<0x62 then x=M:XS(m,U,x);else if x<0X4e then K,x=M:DS(K,x,U,m);continue;elseif x<0B10__10101 and x>0X4e then(m[0X20])[0B1101]=M.j;if not(not U[30304])then x=M:GS(U,x);else x=(0X6__2+(M.FS((M.VS(U[0X4aAe]+U[0X970]-U[12183]+U[2416]+U[0X2422])),(U[0X4aae]))));U[0X7__660]=x;end;elseif x>100 then m[0X20][5]=(M.H.lshift);break;elseif x>0x59 and x<0x64 then if m[0X20]==m[0X2E]then else M:pS(m);end;if not(not U[0X363f])then x=U[0X363F];else x=M:cS(U,x);end;continue;else if x<0X59 and x>0X4F then(m[32])[0X11]=M.Y;if not U[0X526C]then x=M:WS(x,U);else x=(U[0X526c]);end;continue;end;end;end;end;end;x=76;repeat if x==0X3B then return m[60](j,K);else j=m[0X3_C](j,K)(M,S,M.d,m[7],O,m[0b101__010],m[0b110000],m[0B110010],m[54],m[55],M.X,m[0B111__100]);if not(not U[0B1101])then x=(U[0X0D]);else x=0Xb+(M.hS((M.QS((M.CS((M.hS(U[0x68f4]+U[15787]))+M.X[0X9])),U[0X4e92]))));(U)[0b1101]=(x);end;end;until false;end,nI=function(M,m)local U,x=0B1100_10;repeat if U>0X32 and U<0B1101001 then return-0X2,x;else if U<0X34 then U,x=M:oI(x,m,U);continue;else if not(U>0X34)then else m[1]=m[0X1]+0X4;U=0X34__;end;end;end;until false;return nil;end,e_=function(M,M)M=(false);return M;end,zI=function(M,m,U,x)local S;while true do S,U=M:hI(m,U,x);if S==60337 then break;else if S==0X47_1a then continue;end;end;end;m[45]=M.o;(m)[46]=(nil);m[0X2f]=(nil);(m)[0x30]=nil;(m)[0B1__10001]=nil;return U;end,R_=function(M,M,m,U,x,S)x=#M[0X2D];M[0B101101][x+0X1]=(U);S=0X64;(M[45])[x+0B10]=m;return x,S;end,t_=function(M)end,l_=function(M,m,U,x,S,O)if not(x[0B101])then(U)[O]=(x[33][m]);else M:m_(O,S,x,m);end;end,xS=bit32.lrotate,h=[=[LPH)!!LH$)''Y:!?G)Z-65r((*,@TG9$c+9cXQ]/fcei4WR9<1E?Q<7i`fp&fnb.=WIM`3?:I-+WUe.^E#]_#9<db0HD2T-QP5gB,t.r?la#'@3%$B5TLsf(*.<6;B65f1`^NU3uo4[&KLon(`akB/KGKF#TZ5P1*$Q>.30fWCE3[$/0.A(2B>7->TIDs"<C8Y4<6X,-lmXT.if]P"+VO8*B7as*<mNV*>]`+*HiGI*<I6c*=El]*EF0q*=a)3*EO6l*HE0:*C1\d*=Nr.*@`'9*A8Ef*<[Br*<dGp*=X#[*<dHT*E4%U*BkKDJ7flK3,(JW'HL9r#ouGTDTXmY'jOi,J8^NN69[LE3Fb68+Da5!4Dm;GfKDDtA-d\e4D[/q=%GMi#_2qFz4obQ_J@o2iBjk'OEc4EhCh[QMXua^9!=B*_z`l\8]Tg[%q<rod3!`oF/fq?Ii2p.j8b).5*#_8Ng!!!"Dz=8]hUVcPkdef`*:#(Z1`A8H0Rb8kV7<rpKG$@i.oA79CmBl\<:\Y3YRJ65K(F_F\YASbsjBk@Ku(0>$aEs@-r@rc^1Bh=7p!1qflauo_)FNVN1+])8*,A.(.ash(,Fiq7;7]0>Y!J$UZa5G*4efC8$*HQd5NBbRP-<HKRg=qPfeQ:Sb$,rS="b?XFLak#2J-m;>Aor.u78-cBb![j`qk<9I=8W&+#_2qPz('"=7Y>PFPJ5(Yt!!!!)zDR`c(b+Y*C2HS@,<<n$T@:N5-VH7>Fb2OEF#_8;7zBE8)5b)jK_;&u8o!&TU\s8W*!!NT<%!(,Fes8W*!9Ep%IE+*d0"S,W-*<AN//HgU(b,=V2Or^u>b1];,1!5k9<s@6J"b:01<'3hs"=@24JK<JcJ1Of(!!!!)z!?kO&b)UCAEQ[VNqZq_Sz*<6'>!Fo2Ur>g;,;V:^ahAqCm-(`!pJ3FT;!!!91z!Pqh;=/d]O_B!9h(l/6DLO_N.#mgqO/g(H,0.8,3/hS\)/hSb/+<VdZ/g)8Z/1`D+,:G2p5X6YB#mgqk.OZDG/0H&X,pOfk5UIg(-9sg]0.84p-nd5,,9nTb,9nEZ.PE1u/hAP'+<VdL0/"k!$8*YR+<Uss+=]#e5X6VJ5X7S"/1!PH-nZVb5X7R]-71&d5X6YC5X7S".OZMg/hSb-/hSb/5U@m4/grtM,:jr[#mgqk+>52e5X6YK5X7S"+<W.!+=nfe-n6>^5X6YC-9sg]/1N%o+<VdZ+<VdL+<VdL/1r%f,pOff5X6eI+<W-\#mr45+=n`D5X7Rf.R66a-mgDd-718d0.\_/-71#`-9sg]5X6YE5X7S"5X7S".O.2D/hSb-0.\_.5X7R]5X7S"/g)Q-+:/B$+<r!O5X6P:.R66a+=09+/gV_p/hAD(/1N;(/1N;+-nd,(5X7Ra5X7S"5X7S"5X6V\5X7S",="LZ5X6PH5X7S",p4fe+<Ust-6OEa5X7S"5X7S",=!P'-712b5X6YG0-`_I5X7R],pb305U@s65X7S"0-rkK-mh2E/0H&d/hS\+.Nfid5X7R\$7[/C+<Vm85X6YK5X7S"5X7S"-n$W35X7R\/gEVH+<VdL5X6YI-9sg@-8$Dj5X7S"/hA>75X7RZ5UJ-L5U[pD-mh2E-7CDu/2&+s0.7qM-m0WT-71')5X6YB/2&>8,=!e&5X7R_+<W4#+<VdL5U.Bo-7gf80-DT,5X7S",:+m+5X7R\+=KK?+<VdL5X7Ra/1*VI+>+rd+>4'S/2&4j5X7RZ0.8%l5X6PI,p4j+-9sg]-pU$_+<VdZ5UJ$).P<,7+<W-e.R66F,p4<Q5X7S"+=09<+<VdL5U[`t.OZW/,q^f&+:9_J5VFcD+=nj)5UIm%+=na&5VF6&.P)\q5X7R]5UI^@,pO^$5U@g,0-D_k5X7S"/g`hK5X6P:5UI^@,pklB5X7R\-9sg].OZr$$6q2h-8$Sj/g)B(5X7R]5VF6),sX^\5X7R]+>,;o0.\4g.PE1u/g)8f5X6YL5X7S"5X7S"-mgDp5UA'9-7U6*-pU$_/hSOs-7gc%00h!3/gWai/g)Jf5X7R]+<W-\-8-Ja5X7S"5X7S"5X7S"5X7S",="L@5U@g35X7S"5X7S"+=nj)5X6_?5X7S"5X7S"/2'7R5X7S"-8$N.-70'L+=/<b+=\]j0-DA[-pU$_/0H&f5X7R_0.&qL0/"t,+=JHf5X6YL5X7S"5X7S"5X7S"+<W't5X6YI5X7S"/1*VI5X6_?5VFT6/da6[5U.a)5VF6.-pU$_5X6eA5X7S"+<Vd[,q:#[5X7S"-9sg]-9s+7/0c\g5UJ*+5X7S"/g)B(-7(,d5U.g5.R66a.NfiV0.&qL$7[AP0.&:o5X6PH5X7S"+<W4#5UIs'/1r56-9sgC+<W3`-nHJ`-7(o'5X7S"5X7S".P<,70-DAg5X7S"5X7S"+=nj)+<VdL5X6V</hTCS+=]V`5X6VJ5X7S"+=KK?+<VdL+>+cZ5U[`t5X7S"-pU$_+<VdL/g)8Z-7(&i5X7S"5X7S"5X7S"+=nof/h\h"+=09&5VF6&/g)H*+<V"E/g)W/5X7R]-9sg]+<VdZ+<VdL+<VdL0.n@i5X7R]5UJ*55X7S"/1*VI.Oltl+<W9f/1r%f-mg>l5X6VJ5U@Nt/0H&b+=09<#mqn.0-Dem5X7S"+=]WA+<VdL+<VdL+<VdL+<VdL/g)8Z5X7RZ5X7S",q^Z45X7S"5V+<K5X7S"/0H9)+>,&g+<VdL5UJ*+,:jr`+<Ust5Umm05X7S"+<VdO+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL/g`h0#mqn.-n$2\5UJ*+.R66a+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL5U.Bo,:kGo+<Ust/g`1n5UJ$)+=ocC+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL/g`h3#mqn.,9S*8,q^;m+=]WA00hcU+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL0-DA[/1r87#mgqe+>5>R,sW[t5U@O*,:kAm+<VdX+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL0-DA[/hB7Q#mgql.Nfi?,9S*W+>+s*5U[a-5X7S"+=o/l+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL0-DA[/hB7Q#mgqg0/!V<5U@Nq.Ng8h5X7S"5X7S"5U[a'+>,;n+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL+<VdL/3lHF#mr('+:/>\+=\TY5X6YK-m1,e5X7S"5UnB55X7S",sX^\0.J(s+<VdZ+<VdL+<VdL+<VdL.NfiV.O?]"5X6YK$83MQ#mgnE+=]V_5X6VJ+=ng(/g)eu5X7S"5X7S"/hB7Q5X7R\+=09<5X6YK,9SI$/hSJ9/1Nn35U@O&+>,!+#mgqg+:/>\+>4i[5UIs',sX^\+<VdX5UIm/-9sg]5U.C(5X7S"5U.C$+=09<.R66I+>,2f5VF6&.R66a#mr('#mgnE,=!@X,;()k5X7S"-mh2E+<W9f+<VdL+<VdL+<VdL+<VdL+<VdL-n6c#5X6YB-9sg]$7IMZ#mgnE+:/>\+>,&h0.n@i5X7R\5X7S"5X7S"5X7S"5X7S"5X7S"5X7S"5X7S"-pU$_-n$2j#mgnF#mgnE/0H&A/h/M!+<VdL/g)8Z/1`>)/1`>'/hSb-+<VdZ+<VdL/0H&X$48"2T)F&Z5:W\6APNV`DFnqpAS5Rr!In0kMuhj<LLs4e<rnXh5fu7K]*3_k%0$rm**8(>U&oiG%nB^4J,o^QFCdrMCh[QMDImj!*>X**D]a=Xs8N'!!J(4M=,S(dC7t\`b5^u)ZWF;<E\(8m8K\:h+A+aO!1l:qJ3L1;Ec5"c@;p:'GunQe"):oT#(W*^@;p+,!1mt9*Bt)8!C9dCb3B/Q"+ZG;=$C2uclE/\5TRW\D[lo#X]JX-*S;A5M,)4SrDWoMEhO^/b5D<&rZ.kPd8s2t!!n,"zaqFdUl5fEjJEYh38SMZ:@9*P^*G'A0^SK#dJ3VI`G\(aq25aMtfiPI"=-O^+%"K#T4s3fg4?am&66JF%<rjLH#0Ht0L]`0rcWC.S+9m>s4<R3<T7tEN!9XW<zTiV3o=3hljE`WE(:^hjjBk1a_Bi8S]=*/+gkK3h!JAN>%@;'if4U6LZ+<YA^/QX&W!>nllJ>NQQ!!!!)!<<*":;BqK4?O1*69SpC5!2D"+>ueSkuSuM,e@%XJ-$foGT]0U+<YD^!!n*;z*<lKD@@gP2+?U<f3AiO$+A=sA@lumsDEKg4^1>AK:KRB5rXm9V!1k;R*PMLR/7DVQTt8(_2&t]/!!!:Tz9NNnKC'9&K=7ujLQc]mbT(a8859Kq+XP3f,<roa2#_2r!z8,rVi+?TmZ4\S"`_5>@cH#s7@AoD7"as+](=')BL)jj\.AOd\iF)OlsDeX<-6Z,\;ATi*:9Oi*/FD#K&!]=%mbo6h:*RP$NAr9Z'<B155b*PdF!eB"4#_9dLz[/g7-kdiF=Jj7CA=,5/F(EEOdJ-"D+!!&\uzb'hnB&qK.)BJF3`4ZsoM8N\+dC-Fg9EudD-*Ae4,^^,J7z<r`4#-!,%7!]O0]%9H=G!!&Skg)[p.N?-Uk='bN$#(Q^eBQRZZd)na3=*WAf<ltHa+9m@`4_?i@qc_,bg`:qdp78UM!>/DdJ-#:D!!1.Hz=%421Y?1]"Hb1:!)h9G@s8W-!BifR#=,7jt104LsU]I.i"Fr]9D09_b!O)i[z$\/3WE--1mG&h.m=(PlUAlf!C4pulB4@q\"8j5@H#_5N0!!!$kz=7i]=HQ@<baoqfr)-=^jh."M.J,p$Z+@nU&5"\F15!EEuJ,p`n?4XRK*<DU1!M3AG*FZN\njlhCJA\#%+@nX#4ZkiAF`%D6Eb/]sJ-;`N!!!!)!<<*"!>/Bl<rn^j-s&B=1,i9HJ.n,JG@>LrJ95@DDfS;QD.-1V:*>L,Urq:3J>O@5Hs5,*!1jid=$D-7LWX3sb3L(EFeR=,J/[,2+F$'V4ZmsP`Z739H"$o,'-1Y+TnqXLbQ))<J=4s1!!0S8z=77.0s&T?O1ac?h*KsUJJ@chF3Ak:VBg*Y%66JBI=$Af2elMn;=*u"h36Lu2!!n,5z*TI,"J34k*DJX@t,ZeSd)ZtTlF]ZNI4:6ToA3E+!DBNU8hg*@--oq`d.4\pT$4T%#9X.Z)<rl0"BoE(nTnu]d2h,(TJ,u3BASHDnrE!NG=3_fecrUhgN75oMb4+f@mN'%oaoQol$Wm:OAHdT_Ec5u=MBi7R!7(q$z8QPll!O5]e=3PX+[9#+*S]-Pr3Qcmm!!n,>z=/>ot"BPU-=nl&RATJ91FCf<2@UX@e4'-!0W--5`(!=oE!Q%p0=,s#t:!*K&49^8(4[M:p<s8"o:KJu43!=a4Tk2$/9=^>oJ:&594Wloq4ZsoSaui6X;L@i<s',P9=9&=#)HQrH!gm$j=5ZZm\lSnnJ:npnAn>KV+Ne_9En-kC<*0,"S8$,;=0Y09PKEpo!Z>(b5$(`)7X\>=b5O]L#_8<54_c*%4DHfhDF"Y\Ec5W$DJ=#c!=W%OWV?RG?G0DXarm6VLKERfEcG.]E,u25=)N4jOW=J(=8DDgL)g=2=0*^j-s$Fo!G5C7AQ0"eF[C1pDJsW=MuaJkno)m[FB>F^]jo1f>92fGAPrqeF(KK6H#l8n,ZeJn`tHN;!!!:TzoGpj29K``59Kd&P+?X*saoM`KKcSe%X;t"U0N[3R"L_B4r>kAJ=#7Bgg`9EY*M%/lEs@0C@qBIfJ<q9u<sXT`eK$N4+nu+hJFZpe=,Q,AD&iYVEn^YG*U/X-!C^(jJC`8n!!!!)!<<*"=1X@S"b=A/Cgpgpb&8;3(`f+W*<A<)![1WJe'nPOJG=;i!!-@2z@1cQ@Y?1*3R6&JcarmZb"+\S)aqD?O#ZnYE!@h.O=$1;#W`K5l^^,Gk!!!!"<r`4#h0Wejrr<$%b5_MA%=k^YEaa&g:i^,hAU.^#"(t\Us)Fp0r)(W:^fU%H='-ID'N`ZH*Jtj<63Daj&'@R1,X,;A8lp<ZB(o@-J;+)T@:O6[REB>^Ba0*XEb0<0=-$F)"b98e*7[Z6D7N`/J/tU0;cbgs+q@Za"FtG3AT2p:J-$ipF`1apH>I\@BVki]JD5(d@<?Pp*HQ@FLBYhBJ,uEHr7uAr*>MZIj,B-A=4=b&<`]=\=eSnDCchuRC*4W^43A[Fas.p\#_8")z$31&+?iU1u2#C?<`L-m[JG9-.4B3p8"5Hrf^jDFhs(MI4JH,ZLe_&LV*=H"OU#I*jH7X\4LPh^t;$C$<J-#7CF(&kqDJ<p/An>LaA7]Xm<rr%s&"s&G=%ekRr)\<24:ZnC4?ZY+2Dd-u83T."q7b!\*<GP/!!n*Yz=)e3?C`NP1Q<2l_!!&SkMP37"as`L8qH&<g=-4L(CKH#kJ=mna!!2Zsz!!n)Tzb4>W6O<)RD=0`jhc;t&\Fc'8R'&[)i"d<"f:!1j(!X)To<s8G&#_3)D@<Q^+B6%F$T`P9sAb1."=/l2A-s$KparDEV!J'Vm!IRt8J-$?bDerne+rt69!.:Pgs8W*!5`AeE=4RZ"!1j5s*Bq7==4/,.=]YXIiQoXI=2g-@\fH!a@lt<Q4tnfJ1biJ_A3=``e/^Y7%3<)%<s(onNu\7b!S.O,z?J#5XV]CU7*@MP%i9&0-<s78Z$@ihtA7T+F<+g)_$!2(aD?tb6G@bW"=*.ka7`kfj,W]#0AOd)XEb/0kARfFtb1PdtIoiMGRkVu!=3.YhO&l@O`$rh0,onYkJ,plrFCdrJDL$:h;?hY]De*`o@Ph/'F?pIg@VKk)6Y1@^B5V-k&qFM(BQRZZDaQoJDfTr;Bl?gar7H+/!*=pr3;7bjs8N'!gfOOUB+0:kASlO#@<>q"*G'%rRcMWhAQ'.jDJqmaCi=?9DJ=#c'?YB<a4"V<05Dt:8'4'>=1B9G#_2r+!!!$1z#?Te'!f^7^Ao8$-Ec5i+Bl%3p:Wd6p!BO<]*=bJ=!F&X$Zr\auf-JK>a;s.Y0k1K>4[(\Y;cc(\!M!3lScO^M5>9;GJAV6,F)Ok]H#l8n#Cp<%Blmp!=)V\gf#e&h!Dlk<1U."3TG])8!AmlON#h%$J;:pADJ<npAn>LaA7]Xm<u20Eq,[SoA(I>$#M;l,J,s([!!1g[z\fFiPb%gHJ$\7:2EcQ;4CijQ+J7WV4BigN"[0=]'<s?WG9$./KcGRfVFWFp3J4fonrDu\o!P_]'b"e"!#(Y]q@r>^bnf;OXaoVTF@ia]5J,oXO^bBL,#(ScN<_PeP'?WseAu&Lp<sAq3104K^O9L/S4igI2=(1l*eQ3;2*KM3L!I7a'="`lA2p)1L='coJf2i"c*Jke'/"9V)J85!`N/MWW<rli5MTRY]h%e)RJ,o[P=(Be_=B>O`!?YAD4D"hKC-6Ar!Ff+o=/3W65Z\!G!!&SkJBGTVcP"D!!%<SKs8W*62ZeO0=3hm2!*:_Yf*-\)qh_*c!"0'_z"FpIP03Ntd@u`R@70nE.8SrTfJ8Jk>;0dcs<X40SDffK#doS>G+:NdC4?[LC8j$i2=$1:A*6J:)!QA.1%9Gk:!!&Sl"Fr]r0oBC#@;Q-tUrm@m*MXX?!W?*D#_;.[!!!#>zAS26uDImF%!@LrlEQV?'B`rsJJ8]%;Ec5Oo*HY_,"b9\-=-*A_n&h'p!G5ElAOdA`F)OlsDeX<-6Z,\;ATi*:Dfc88Bl\<:!1mh@*BrB]dd'tW<t`h\[E:3C#*E!8!e=D*&:eC5A3N1@DEK%)8Nf0u+?VeBaoWbg!eB%6TcIf0<rpfP:<ESXb(UkWB32$]!P;D6*E\D)&d!U%%ju_Cs8N'!8fds3@8-uWH>-<&@Q7G#TihDH1`Eo;<rnCajN?egb1@ZIA]i-'=0EX@9-*VmrkJSc<riD)=*"BW^)[6bBL<#TAS5mhJ<M!a4?d3V5stg*X.,%Xe/aL_TnlXi%UER"*O.?A!@h0KAa!OE6%rE15I+gJ*<BVN*Gun(HluLMJ1otb.X$@G!O>cS;T&WeE^g@c@9.5`AS$"#A4iGu5NI6M=3^0U#2$#;DaOh]@qBOq=(Gla:0.I"ioA/^ASqU#+9@":=*%/=#_4XA4?c;!4B+F6<uTUjY?,cI!ZkDP=!RfsjAu?uEX.*qBl7g2"3P7o!=i3%<EF#XM?q?*<u=)%%"K)U@N[cr4Zkhj4_?lk*G'IsK9U`_s8NXP!6Y?A<uE%!ilV=.#/jT_`l$5u!!n)ezTr7qks.D99<rkNe0$8$L7;Q&q4?Wq"4Eru)r8^pk!eBJT'3D9CU$'Q!5#_]9J5eWn5&*7h4?RFD+?Vhu=-t2S"FpL[oM!((*F6]e=0N^YL0"E06jJ6WEccA6V,qq\!K:*7HhYG#!!#Lcs8W-!=%Na#_H0'o!KL4^b(Im[:fiUk4pZ[-4A%b"=!0Y"#Clj4DJ<HbJ9YX9AS>%<@V''mC`mA5@<,gkBcq\AATAo7EbTZ9D]iS%F\EoqE$0:3AoqHtF)>r9Ceu6,ATM9kAT2Q1+CQC1E,]r@+EVXBCL_(#="\T+Cf^W_V^S5O7TV#+*G-<jp'#tg4=OX,b0&>YM9=s6<6\LK="=e_LE-EnJ/3f>DJsV&AR]M!#+AV6AOd&WDIlL`*GBP-!YndSi#QPQ*P1[]-"p@p+CYV,4u$br#Zj,N4p6CF*BlVY!Aml>aoN\f2-8g8/;I:-=4p9i'NY>$$?B2LM-&FPI!A]nJ,ojU!!!!)z_B$eA*<B/A:'uOC:3:_lAR]M!PAA<]=,R*0!It<H!U!N'aoTplfiQM7@g7J,@:O1niWOdR='XAJXrRVQAo8$-Ec5i*Bl%3pRTF'HRu>Dk!e@[!"b?Hi83B(N:D$Yl!I>$%z#_2mT!!!"$zFE7Y:B5VF(hH(:0b,$*ZZlR_5X6p(?EsI4EAS-$q!J#?28M+"mT`NVDTKjU(=0]ojrZ)#k8YMas=9&;.#_3"PzPQ1[`'$AB<=+D=7#_2q)z0)ttP<rr;%#Zh&_^pD/a=!Wc,M]Dj!J-:1"!!!!)zCDg3d!!!:Tz"+WW;=1@DY1OoKWFCfM@G&Cl'@:LE-FDl&7@;'-n+D#2'Bm+B*D/O94+EVL4B-:f)DIn!*C1;*(J95:4PoUM=#_9i6CdW88FDbZ(=24p\boHht4WjrZ5!3@iJ,uKJ@:N4>>fpVoJ<\]M@V''RcW=b%?KG61<s"[h)9Ms`dfFuoJ-[H&*JIi%s(?]Fs8RTK#CujSEa`p)*HQ(+!if>_69GO(4ZmIM?roNS!=W$9,Ze4k)obrmBN,duASiQ$@<>q"+D#@uC`me5ASYdo!Vf`,[s]6T:C)K[!!!!"J,fQLP(i99lb%u=ZKnNSQCdEVb*om-V&e=F1!8Z"70S4$F)?&;!!!:TzOiiL]CmC]O!n\R[DaOb[@qBOq]_ooo=%24PXNCR]DS9,K<rm;B8lrqa=7Xub:WbIf=9;S%JAI&a0=SUs4_b7QA3D&E$@k9'@rl?PASuC(2V<+]<rrS-L<9P;b(:XoboP"I*<@`n\HC",D.a''BOc-m*<B_Qg)%nCq&Qd^=,MRO$[Vpdrr_CRJH,ZL!!,Clz+p`]!zaoDDAkZ=WoBa]FlASHF2@UWe`#_6K&z"TSN&A_(&-_:f4N5N&RJ`?"t!!$*\=s8W*!)"(K*!#c,nzH<1(HBZaBWJ@/=u69[L8#_5'Sz'EA+5*GbLQ*TeAJ!E*!ZT`QWD%B%8C*<GV1T`ou;:NFm4<rl#sI9-IY!OR1Ss8N,THrp@JDdc]LAQK%c*G&ko49g>18g$93eH17DQN_p+Vd/BPF%HXfA9Dum\lWfa!HV<C1m.rk!!n+kzJAV?e@<+g@M99CH3/L_Z^b;@SS-4B@=(I$'#_2qkzfDtsPaoPRF!J%0N2S<+<b-4(P#(ZJY@:aIh!1mbD=$Lp0YZE7Am/_`ISm0uO5L9B1=4q6/"]k^\J;,'nA78:DB5VEoFEDFfqH%NP\PgQO*<DU1=$n":<`a8cj&_oTF]U_LX$b#8A/k]%!D6E%!)Q^Cs8W*!!!&Vj$%TbRDfTc+DJ=38*J5ADb'k@ZX.Ga&=$LH"$%P>gATD9ZF[p=\!GY\MDc-jkBlmd*<#ojp+?fsZ=$8`^*`iCjLW%=9J6?)XnrQ*=F(#9'FE1r6=&%US*K1)QJGSsDQrcKQ1RD/D=!4qQ"+UNF=(6;ndT6Ya`!FL^$T["9e,b+"Ddis%@:a7n!!&U.f2l+*!?"r>eQ6)u!!&U=(s5)<oE0X*oub+'PjHPRT`KUD#QOi)aoMQF$\5eXA7T+F9P86WJ95C7JAhWm4?Pb9CclGr4D8UpF]U_<=1K=S8lp81!@CkL=$9Pb+j)5,!T$n5"b9t4@;KLc=1K>s%Y+Sa@QlY@4Zu>!4A'-ImT2S7!=;iL=#Y/$MH<43J3b1W!!!!)zi?l^2=7cND?<:-cOd4(;J,fS@*EF1D!N9(L*R)LF<<RjDb&(i\"G#!nSMq#u!+-"^z:fdVs*E!nnquVE-)P;@gs8N'!%Y4TZ2_eeb4ZjiH5&MK0%a#nnJ79PB+<WcR4?[@?*BdjS=2,cL:KIT.!!n,@zJ.M\\4Zkh1$<KB,!m=XT*??RLb!eKqjB%n3!?5)@=/'!C$%N&'2G$(T+?i+UBIm4-=)Ndp,?IU@!!n)Uz=.93jZlKBDF%HXfG&h.mL<=OJ!BjMrAPN_cDH1e'AQEneEc6&0=#3BKRN2q&4'+$T!Y/94<rk9^HccBn!V'6IbB*o<b&&&0!1oG$Tg"P<^]5Gqqc=CNe4%L\BO_0qg<+GE!HM8I(KW=3"%?8m!27OUaoDGB``N$F)\78rs8N3%P+hpU=&%V:"+WCmSoA7]5B$T&Ed%Y:T3#u?X(I;<4BJ1?!G>I7!e:7kNM/jEJ5gWI4\-\#2JG?;TN@a+4U-E;4a9+Q-Vmf7!!!"mb*F%K2HQ*_4:?[)4?d@@5!2##DHC]u=2>n&2HN7;g).s6=.Y8kITPF<=8!YFFB8KZ!!&SkA>).Ob%MEGYoSlGb&Z*8,?NftFOO:m@m(6N4uPDUGWd0`6HVGR!\%45Obs<mJ@WqmDeq`D!e>&r='*=RdgXA'*OaSB=kZs!J>#rb!!0A2z@jtIZE-MS;Ci!Ni8j*K29KkR&=(FK]]H%$^<rs^MP?03qEWpsok'm`Pl5faBJ,sdo8Nf6C4?RFCkS0^S"+Yh<N.=IR[f8SXb4,^<#Ct()2ebBf*Bm%X>>A6jk5qWAl0Y1!T2u[]J5.*c<';?14A$_[,K`>8!DHS/!&uKUs8W*!!>\c:!*QP"JEn5EFCB"iNE9e'=*P_d3?:pFY[u^cO\<js<epg-=*KX*"b6VQ31!n0!ZtK7*<F/]CZ8F#J?:;&X5#i?2??<L4?O"%4Wlp\+B0J.RO60@J;mpY!!!f@z=%+,06-96J*WpqU6!*O*!!n+uz*TmG'!b>AX*U;D%h?/:t/"m*Y<s(Zn[E8O'=1''oi)]q23Oi,nT`NeI^]8RG!-2Fns8W*!ao[+n*<:U%&-APG"BUN^=%"&0"FpOj8QGQp_]<#'"b8D]3Ak;0B*<`-*G'(rSph]J5EGjFm&tK()Vo``s8N'!'HR5RJ/SAg!!!!)zJ1Vd[F(.EHFEMD<F)OldDeX<-,kG)Tb"aNi:KO+F3[[uk=8kV1f2i!d8d9fR4A7j[9pSjpb-6lJ%is'T!,2^hz#_2mT!!!"2zJ,urW4Ztn5CclMs!>nm_!!!:Tz"+^%F*L9P!*@r53J@WhR$@pJD5&MJc+Co"HRE?Wpl[$_@4<Oo[+B0J$!J!@*FpNWVz*<6'>"92G$K]+h>Y_D%diOO^%L#J)GJ;<*YiK/`OL>f(bKnSEeiMD7eK]0Cp[>!RqiIQdCL#IoB^P:^S><N+>6s!Y]!!n)Uz=/,`q4')IE4:$Jl2)Sl,atcONI*2=b!VKOlb$F75)M!q:<-2\AAS5mhDGP@lG&h^m@rakHB5V9S`Z8`7HN>$d!!#p5s8W-!c1,MA!X`!k=%auD`)ct=b%Vjs$Wkt;rtJOV#_7CF!!!%Rzb!Lqd)]dn)8ls^e!!n)Yzb.n#X$%U`pCN=?;@ps=t!!&U%$%P4l@<>pGARo^R!=MtF<rib3k#Xkg!u"`:f#lehci\g"E69ao!QnJq<rp6@OB2Ish'C,D=-'#sA/t\Y`uR_lATA!*ASlR2J4%+RDg5^o!gZo.=$TVa"b6V?D.uC<=8!Xi*ENAn!a&M*+j-AslD)LX=)%#&!e:;ESU7Varr<%<b5_MA\/i#p=2lT0#_2t-zB)ho3mN(I2Bg)fQ66JHKe&ieN!?bI'HPbL>!!!cis8W-!aoVND2BB6b\Y6JQ*Hu9?n9rGc,Zjd^JE%XN!!+/Izd([X&J,pTj83B'@4uc+V4['+$4?Yf?!ZP2`JCLdF=,QnWGZPc-k5g*@+D:n.$%P0%Ec5W4EcYT0]**Xo*Nr8u!L'5L#_2pUFE;=kARfUdJ2Ns#lV8#qL0'HR!T7#[*hfk[=8!1Q/QVuS`K\M@<rqel"+X"9J9#R;4Ztt4JQG$%WF*dK*<A9(DV/$l8j3Q35"Ij[J3G)J%%dS'B3/F\!a8YD^K4e`X4YQ9!!!:Tzq]-d[=4TmaEf:%cJ>'(Z<+80#4[(tN%"LHLDf]ARATW'2AU8&h@3,1bF(ku3Derp"ATDp7*LOL^&D)9+s8N'!Cs)eX!GPWq*G=)-P66>TXW<K-J-#7C@qA[G13.;TaoO"oGZXaS"G0]I<rmMHPoU]:J@%G]!!'S9z;ZqUNJ7X%@!!)ZtzO82iW*BI8'RK:P\=!c-nfiJ\t!JFMWVk"Nq:BZ2kJAI.9=8F!?ML,CErr<$=JH,ZLa;m2?J,qT1!!)-ez"Kkf+aoVlNS'&qB:^DUIFD5f7*H#e0%&I%AJC\GWATMu"FCA^#2ccV\lrTK<n'oKX#(R+&BkVR(gLYJ=gWJ[%J3W<*pW@4QJ,sRi4_Qqc4_[&B+@846atX-&250(Iau,dcc5hKi<rnRfm8lg-@$=Xo=!?*q3EJRJ93t[#!.CYis8W*!2<@p>[`Y?c!!n+rz*C^&0!A7I&!6#4oz,K]ud@9Zh#!NcWXz!1j/jJA;!^G@>Lr=*/"d0NS9&@K_2^=(H2WLfZsVhN5k\rQ<5&!KL6c=$;ICf2i"RnF4S1!+[m4s8W*!!WH1#*<EQL6O&')D..HS'WbAIhU-26!NoK0ct`]56X'YC?k6=E=!Ec.%Y/gg4_?lA9Km2R4ZtqN#$2p^apT3jHWTo+*0d-#@*2(=(CjNnA8)U*Bln6(G\)/4FEM))!1n4L=$L'm104Z<b%2RpUK>"5@L@WM4ZuI]+B2<(i!=irzaoDDA--FiK!=Dngb,gfL[N1]gHT2%V!!!^Rs8W-!iDHYL,4&D2J,s%Zi#Po#!-:PTs8W*!IRI9;J,q?*6$#U"F(YW+!1mYB*Bp+r)$ka(zaoDDA0iu)F9a"P,<ucBbH<1,%?$'-MDFFh]GuSX'#_6K*!!!!Iz!!A.Q=&9p5hH'e,BTuR"$\5?"Dg>bbE_ge"b&V'(]:nRGJ99(9!!&>kz=5t;$"'5Mcpa'!eTrnKJ=-FZl"FpNs4Dl9(GXa0V=$I^>#_2q^FE1edAT2oo<ri;&Q-'-P<rpt9h4Xk6apKA0YT8s5*V'5]:-bL3NZJ0"ao`>ZSfQEUfXsbt"b0SS!Itn*Z969hO]KDo&Jod;s8N'!&V0o]<-2\AAS5mhDGP@lG&h^mBaTB%Ch$srEclGAXj,""4Zs($CcssU(!8Z^3i?&kW64lU*ASYf<=j\#H>-;LDJqmR@<-I2J95[C4Zkn85!<F>J3>h_!!(m^z#QIj*JV=/UGkD,gJ,fS@*N0uS=*G[4\Q8h-%c:?+o:lG=/BX(:F9I-n=)2kcCf^XVb`Ps/9ip^&i;nH4/N@*r'$=:/nY&#b*WO?==5Ft]H%9Tr>:hEL?#q;rATAo!DK9lAFCfM9G&Cl'DKTP>DeX<'/hSPiEZce`EclJ8F!VrH/hSb)DIjq>F!*#EASlO#@<>q"-tR4(,$Q1:>p=>9/g*;"I3:-p+F>4^DJ<Hb+F%I.AS3,KDImF%/gr,k.4Hl%.4KZfJ1hoc!!&;jz%;f/H!(!*JaI:8%J-!qsKL7p*DcqF;9H\@uAKYE(EbT]7ASl='A0>u3+EM+4+EVO>E,]r@+EVXBA79Cm+EDBCA79CmBl\<:+=q/CEb/p+Ec5Q$Dg<I:Ea^)5DKR(5ASbga+E)?E+D#V:@<-KaF!kX?:eW5Z:JP7f<_ue'79*#ID'13)DfT>rb-)g<V4k.d=7cK.UfRbS!RXsLZra7J=.:33U/sp4*GHMpb.SgcQrfg2!@V"uJ>=MnBjl2g![Uoir5pu>6Nr"cASuF&JA[RP+<YD$<rrb2pW>Mf!!&ViZ<'6jJ?Bo;EcP_-BcqG7Eb-A2+EDC@A8YghB5VF"*F,XH"%-.gJ2B\rEa_cKHZX.:!#R/Rs8W-!Z,m)u!dn'gH6%Og*=iNZ^)tL==!$O+ElnE#<!e)j9QYMjCh7'aEc_V<@V'%X=)2;S!`oCC=!o#&"'5N#E!1[m=)2;S!1j5F=$PUC%tI"J4Dm8F4Z$k8Cd&tP=$8`0-6:AQScNM+^H_c!!'0t(s8W*!4h=_pb%:[)!1pTI=23)^6_ON-SeI&o5"s2F#_:GG!!!#Rz<s8A$"'7-L!D$8m*<BDH4q`C:1bgaq1LiR14WlmCGW][_!In06b%>]r"FuP>ASkjN=&+TR8lpcjaK3N/<s+gk,$4F1RL"EF!!!!"<r`4#(0:Nh!!&T[0$6@CCXH5"J,tR09KbQJ69HARBOX+f#mc&DzaoDDAVH:bnar2:B9399:<=+1?A78;+B5VEoJ@_/k!!0\;z!A@LS<sglfH<1-FJBAl7DKShaG&h.m=(PlU3M$6SJ3DqQ!!!!)!<<*"&Q2^-F_1o0Blmj&W)mkT!mk"3*<A`5!!n,Az*DQV8!!n+Bz*Lm-1]LSYcXNLR1+:E^l4_>g#5!2#>"b8d/1N[>?!<H7W*<Cpsdi6H=r)`P3*]@)?YKFm+[1^WN*<@Hf-j"ql.(<7ZjUD9AolL7c<rq2[_P%"=*M<CQX.WPU*<C4_6OA:SF)tc+ASkjN=-12>!1j55TfrGVs8IdISrR!s^E<LVfN4jh)MNNCs8N'!diJJgao[8uP#mcU3>>Nq<rlu9"FsgP1(mk0fDuLaMD!$R8N[K5DE^6D4?am&4>]$-*Z^dl;Z-ZIBh\h_H>-;qIKb75M6c_[=8hL.$\0R+Bm:aa2b?+ieiY';)#sbm"9PUT"=R1O"HZOb!Ju^;"=,73_ZU*""FP/l!mjjKaAW3E=9M:u]`^_+$cE/K_eEYVbQ=_L"9Gq@-;t$M";q=^!m"N&"9]Ds"9HkJ!f0bXWr]"!"9\i.S,pP1"BYd-!W)nn!Q8b]CL@27#)`MPMuoJVV?E+a"9HFA"A_r!!NQ6s"9G"q!Ls9pb?tPOqZ3Jn!R"jO!i#ddN!A$EV?YNN"9HFA"@,lg"?o`e!Q5'C=9JYpRfUG1"/B6u#/^J3Muh[@`,>bZ;Zm4(;Zm58"9GG\"9a*E"9]fF?)ms(*"3H*,W$bL"9a&S"CP.2HuLUJBN#$:``!!C*!*tY!KN(Bo331c!S'"2qud.9/-2@O">(l%(/k>=2@q<i;Zm4;;Zm45,Qn.&"=+,"(5rAR!M9CWLslCc!Ps-aHjP^YGjB_WHi_'2PXGWFMbJL!!o%)eD[P8^"9]'rU]b%'"9GP(]`\A#!Ls8nU]ad&?j;Mi!L*cJ>@7Yn"oA=jN!$+gV?jO0"9HFA!WH"#zocO57"9\e,--LO36oGG*OAc8b>9$<=*)m%;>ViEb>,tj9OAc8b>9$<?*)m%;>QXe,DUVeu"FC8F&5r]7YYtZ-;Zm44irfJJX9#jI;Zm43"9\b8":Ve="L(f-U^Nt$@$:]o9EC@t!JR!G"9]EXe-EK^"BYd-Wr^uY!SdeYRpZ<hb5p+5')Q'a#-7jD!W2tq\5NM5;Zm4/$^:k2lN-qmHN["E6B_NT"9]EX":"'g!NQ7V"9I!T!Sdf[8b6=7Lm%kh#1Hr\DZg*Z"9\c'i!5oRgK#!o;Zm4)"9]+RMZcgS!OQeafM_nU;Zm41!Rq=PbQM#N!PJU:!Sde\g]RYY?ig-*!R+u1MdQS_irRY<!J=b]#g<=f!W2tq=Ao>*Dc6cA&kk`X,Qo(q,Qnfd,R'EC9M>K&";E*a"cuXcLJn<Y;Zm4(MZa*c!OQepYYtZ-;Zm4/;Zm4'"=sS(";FNT9H7"W"9\j*Rfl5[";Geo"c-([(k`'oRh!)>>Qg]&;Zm4;gh<a#4:Di,**a`l"Crb\"=-]8"FsDRE%(#T;Zm4;N!'9n"9GP(=9JYXMZL0f@J^?O!OMm7J1IB;[K3`@"9\i."9R.Q"mAkf"FC8FE*ne3;Zm4;"KMU<'O1auQr=+j"9H^Ne-#fc"BYd-!W)oAe,l+I!J^1H!K*@S%\*R<!W2tqTMksr;Zm4/!R([s"9H1=qu[')"9I!Q!W3(&MdQ_3irR@*!fLFi)9W'1`)-&5r,2]=;Zm4(X@rfm!P;P?PT4(p$nP'Q"9H,='Q>_[i)9a]!sA`-!Rq/Jqug+)?j4^S!Rt'&]3kl5!Q5"p!W6j=s&0%';Zm4)"9\e?Wr_B^&d6->":_.8%BNe[S9GA51^(/fKH+NPquf1l.g!'a";D(4*%YnO"ADKh"B7c7"9]Dag]S*c"9GP(=9JZSb5pB$"l!Dh?df&*`!38MV?s=)"9JE$!O,K*S,`[c;Zm42"9\jn"+UAM#.mnMk#2Bc=c3C`"9]EX"9^\_e,fIL"BYd-"R?*de.CYJ?ig-*!Rq\@dpPrBquO_<quNYs;Zm4(<YQs+"9\bK"9F<W!rl1%";q>)!Mr0e;Zm4+"K)=8"KPQ;Qr=+jkQ7df";G)AOD[u"Zq:H&;Zm4(!Rq7T"9_g0!W3$&",d3Xe-:h=?j!G1!Rq=3dpN42j8m2KquNZ*;Zm4(G=B,-"9]ED"9[db"1D,2qcb%6>9$TEgft)Z?GftT"FC8F$]G>/'Es4i#D5PgmSa5k!Sde[e-#fQ"BYd-#0R&&e-!m%?idS7!Q5#V!W6j=Q;[nh;Zm4(>FPcQ6oG+\^Jb7<^Nd?n";G)D!VfRrqcb%6>9$TE_ZU!u9O)OM"9a&S"L_53]E+%F!OMh4!OPh,!OMmD!K;2[!OMll6A#;lF9C9*!PE=Rmo'>lXrL+9<!3!ugeeR"*!uNO]E,AhD@G;+Muf+%"UCP'qZHrd9O)NQ/-L;&7)N4cqcb%6>9$TE"9\nW"9Iph!Obo0=9JZS!Sde\bQIsI!PJU:b5pB$"RBG""OdCq!JTQA$_maP_um>Rr,2]=;Zm4(#0-kE"IiF+N`-&`;Zm4("9\qT9EqXu"8c:BlWY?.@_2aF"9_tKmfMWMX&]o9;Zm4)!!!,az!il&>peq:u!sA`0!K7&dZijJ6fiZE+!J-F8!PAHGk[N"6[K4#B"9\i.A-Su2irQeD_uoW4#4-O>$BtnQlnhss#.-Q'!h9M.,Qc1?<+I6W,QrGs"@OL<!k;/3Wr_8a!Rq5Q"9H1==9JZ[qZ5a\!i'-(?s<Z]!SdaOgL(90_u\'bKE7qZ;Zm4)"9I"cg]RYk"BYd-#)`N3g]ukI?jDSj!R(Y0!ebIpcr1&M7Z.BN";Et;*!_^4"C*2T!T6lZ"<perE%KH@"9\b<"9S'k;us`:"dB%p]Mp^5!VB4o.P(mZ"QTuMj),BdU^uem$G6NI>U0FtA0_:O"FC8N<$VT'>U0G7E!k>&,QpMG;Zm5>"9\c#"9HM@"0b],*Rk;[":3Ke!LQdg<$VT'>U0G7E$3%$,QpMG;Zm5>"9\bW"?uqL":e?5!JXMU!)j"'=9JZ["9I!T"9\b=!e^XY"j6t#e-(\;MdT`iirRp<!omYk%&<pJ!e^TOB2\p9]Li<';Zm4(!sA`d!Sda0KEPB[?iu#_!Sd^FK4"`7U]J[FKE7qR;Zm4);Zm4e"9\am/-;DAUBFIo!!0_B+.E;D!PnfL!J:Ec!L*Vl!K7&l_dEW-":U4o"9HGZ!S:6Q";q>9<]gEV"9\n?g]GMp"BYd-KED>["9I!Re-#fc?j3k;!e^^*dpNC'K)sa10CrQP"Pa%%!e^TO^Jb7<"9I9Z"9\j0g]E-2gL+4d])mWe!o%)b!Q+rn!R*'%!ebIpQW""i;Zm4(lN@6D]Pmn3;Zm4(!!!+mz!ihLj#ZCj/(%_Ql";K?P)urn?"9]SF"<;AJ'ENk$!)j"',U<L4/0k?4"B$Kbzf,F\i"9\e+irm_-HiSOl_0g4>#KqJqHi]IR?j2H^]K?A(PQ@Wh;Zm4(!NZ=KU]ad&!PJU:!sA`0!Rq/"P@+ElMZKm[!L$mq!W)nnX98'%qd=IGquN;ke,cEM;Zm4(!o*hGHi\qj]F<;;#j_]u%T<K5!O;h28d#V4;Zm5N;Zm4^,THlq&$,fL;%1Yo#*]A*$f!3G"2k>\ZiT3)"UsGr/-H1L"9\iJ"9_4n#FmtV!Lt%7"9].7"=tZo*&Id",VuK*"9a&SQN<W["9G;!X98R;"BYd-e,ogVqZ3Jn#E)sj#FbbDU]Kdh?ig-*!NZ<sMdQ^p"9G"r"9I"j!PVJ8FE;g4E)=FT]*&.f!K:suV#cfs,Qn5N":VXp!N&cuWr]R1"9\i.X9$fQ"BYd-!W)o)e-!Tr_dF,YqZ3c#"2eLI!J:ESS-@YTe8GHj;Zm4(;Zm4'"AAjj"9\j0Hj"NnWrt8#!JGE-!P\a?HmZ1I"FL6R4ECOVE!P,#ZV1CYP]-YWKE7;<HitSn!JF9s[X8+Q"9\i."9J3p!QS+A!!!u>+ohTC"9PX."5$NTMus1c"9IQb!fR7aK4"oLgB$@;#J4@E?rI*eKE9SDMufd];Zm4)!TXI["9_g0!fR3a",d5>!T[`uRpZDh"9I!U"9OO#"5m)\>[U-];Zm4C"fqhd!NZ=:!N[F(dfHNM_#^VKdfHNN!L.s4_gDKd?c-8Yb\mW#;Zm4("9\e!"9ceE":.p/"n5FnkYhTeO9*N,"<:YI"=I+N49/:_!P;PE%K(1g4?NY/UB.b2,Q[fUo*`2>XU!W9j:.U[C]oD"oFAMr!Sg!G$)@UG":Fc)"isUFfM_nU!OMt1P6=!h!PE@TE.$CCZigEJ"9]kK!JXMU%T<K5b>oU-;Zm4(#F.Dr"T&=849:Zl]3>[X>7<Up(?5G-KE7;_1%PMP"9]]`qZ58H&j-2W,QoA$M$,q'"9\i."9`(1"9br-!k;/3%ZD%M"9O6>!pEPc>62Z)@%06Q49:ZlE*8)%;Zm4C!UKqBj9,La"BYd-!W)oaj9)_r!Jlp?e-,ANV?ran"9OM_"cuXc7T0EmEriWN/\;.-"9H/S`&7hkbRT:,"3b<W$LA2n":*-SZiRrf;Zm4(KffFNirgn7!L+i1>7<VV18=l^/-1t\4<t%D6mMmT"B%?%=9JZc"9I9\g]RYk?jD;b!TZh1?icGF"9I!["9OO#"8Gdt``!!CeiVUf">i";!QJ%@kYhTe*!+mt"9a?X!mjjK]`\Ak!TX@a"9_g0!fR3a!o!d8gj,)k?iop#!T\NiK4$4I"9I!Q"9OO#!Us"jWr_Pi!TX@ali^Dnj'X)4K)t$7"P[;g#1N\'!fR/WG#JMHmSa5k":MR<,W'$W"?\eH"9]Da"9O*P!l%Y:Mus1c!UKpjj9,La"BYd-"j6t+lii;T?j+pZ!TX=:RpZH$e,e&$MufdX;Zm4)UBCVc"<;A4"85XrMus1c"9IQb!TXAcCL@1t"R?,JMuoJV?j""B!TYrPj'Z63"9I!T"9OO#!ln4B";q=n!MqUU@$:]r"9]]`"9\?r"27\:"BYeSEri?F!OMu']EDbd"Di,[ZiRoEZk&B%.^KQb!OMpB"9\b6"O9pK1aE2l*$bY\"5dC:"9^P>L'#\"Zq:H%;Zm4(8rEfO*"3HB'MKbT`)K,-G7MP$$^:b+,[>gmUco=]U^=[7%cf,EQW""i!!!!$"onW'"9PTd*$A/_*!@,^'GMeq,U=W<"9^Rbe.,C[;?`!`!!!Q-z!isctkYhTeUC8+Cb[T$%G6bJY"OmsPA:Fo=4q<es#M]aKUal]*,Qnek,QoB/;Zm5F",I2lBY.;mi)9a]+%j]^":X?r#(TVT<dY+]"9\bC499t2%\t@<n5BGm(Be7R"9])$_ZB7*&nD$%,QpLD,Qpe_;ZqJqPQV-Q"9GP)=9J\aqZ;ub"S6"%#K$V%!W4`]!jlkKLf4EZbQPQ[$,d,lW)Eg%'20APE$GK*;Zm4s"9]'f:']]U$(FtC^f(@=;Zm4-<?*96$)D*B"Debt"9_+<UB](D>RA2[;Zm5N"9]%X"9a0P"9sZ\"9`KC'Q=S8Sl5ap;Zm4("9ON8PQV+k"9GP)]`\Ci!e^[WRpZ9oWre4_P^?dB?ig-+!fR<;lX0ag"9JF8"9PrK"CP.2#KTgH*+;N/;Zm9"A30#d"@NY2";Gr'"9a)t*!,5$UeqKS/.U_Oe.;1$D?fG4%(p&ue-,lc;Zm46!NZOa"9_g0!Rq2SErk&!_ZBZl!T\3E^B3a)"9I9Y4ECPaE!P,#"oJ^\oR&.CPQ^=R%*Skb+T^X,j8n$=!SeRoErk>)7cOVV"9Ik.j8m!uj8n$:!Sh/c!SfQ=dfJ5(_#`=:Wr^uVPQB8JX9%)W?qS<;!Ls>j!VC:5TMksr!gEfiN!'0^"BYd.Zi^F6b6#$P"05f5#D3)BN!$+g?j,Kk!W3=`!N$<r"9\e5*!4/ZUa--9,QoY/";Clq49:ZlA7S[cC`F]'"C*2T!Q\1B1aE2DYYtZ-;Zm4,"9\dtKE[`A!PJU;"9OMb!e^\YZX<h2Erq:(r(=k7V?m)#"9Pq2!qoOq!)j"'=9J\a!gEfjN!'0^?j=dU!gEodqd9I%P6-[I"iF_6DZg+="9\e5YQVI7HWCg]peq:u;Zm4(,Qpe#,QpM_">g.449:BdF9GKP]+cLn2?MfF;Zm5.!fR0+KEPB[!PJU;qZ;ER#K'pM$]>(Fr%-$!Zu6'J;Zm4)5YN/2;Zm4C"9\h"<!&+Z"9]SF"9G?(,T7XJJ5l^T`rqS,";G)A";k&?ZYi\E>Q`h`;Zm5N"9\f#<!2knj@gg%HigncHj._.":2@<"BSM)!j5H)=9J\aMZSh?#/agQ"lfZCquN9pZu6'J;Zm4).FSE+lNCa;"Di$gFDu8aM?Et4BY.dUHkca]Vc*^$"9OM_PQV+k"9GP)#)`PAN+C+>?j?K0!gJ2`dpN4RZN?)86'G[YDZg+="9\e5UB-BR!M0=I"9_sf"9Yi+"-ujg=9J\a!sA`0!ji$9dpN<rgB*<\j'VnAquQ]uZiR$*;Zm4)%"nYRKQdp5bRa=J1`UuUj?=(/r!i9$%YQ>@(fLP?!gX.^"9Z#9"@#ff!M33mf2DeTHihk""BMj0!p3Dab>s!<;Zm4q!!!.fz!j%e9Qr=+j(BdDB"9]7NoFBMP!PJU:"9JE'!V?Lsb?tAJP6(SKdpN3<KE:F^U]I=q;Zm4)"9]4mC^?t<!TRB(UK\^[,Qp4B;Zm5N"9\k;8)j_f">g`r"8j`U^f(@=;Zm4+!W2uN"9_g0!i,o$"j6tCr!)1h?io?hliE'/Ui-A:;Zm4)"=+&Y";Gr'">kKO"9F0$#09^G>U0FdA0_:7Rp-;;HN[Rl;Zm4+"C)B!"9^P,"9Yl,"@lAn#d@51=9J[&"9J,t"9\b=!NQ9TMZNGQ#*WEt!W)qOr!&?m?k0dL!UO.Q!N$"\"9\e%C^TB)Kp+&-Ce*LdC]nPe"9\iZ":U)b$J88[&o:+^,QqWd,Qo)D"9\aY"9PN#$0Y:j,Y`(X%T<K5=9J[&"9J,toE53.?jDkr!W6bt?ic(a!ULfd!N#t["9\e%ZNA3H2@&G%;Zm56]*&/##HVl?E,`u'"9GGpCch`UKp,^\>7>TSC]T1[49:so%T<K5U]U`&"9JE%!i,s$o3_[4qZ6Uh?c-8/DZg+-"9\e%6ji-V9MAG+<'2E/!q^X=E-n>_>4Vkj"9_\CKE[01P?T"-]OV%s!K895HrU:hCaB2e%T<K5a;4tA;Zm4+,Qn1PChs-fM_$+V2@'>?;Zm4S"9](a"9u)/!RF[I2G[,\;Zm5&"=+&G/-H(n1^!iU!P;PEE%C5W;Zm4cH_UYWA2X[SQr=+j%u_b8jCDL%!q]=l.LZED'EZc`X;[RG"UEfl"9\aq"C(uB!gZaf&o:=dZih?W"@RV<"9F0$"-?FaUK\^SJdc`6jA)`V7g.$BF99*k"-`hW3!I5g%.k"Ir$r;b;Zm4.*!jImF91E+Kp,^\>9&"k!JD)\!jc)>S,n:j"DiGd"9\jS"9]35%CBMAquMpj;Zm40!W3&@qug+)?j)Ag!W2uAP@,0,!UKiK!i0`;a&<*D(qXSc!r#r=9EC"RQW""i#,DA&":Eq"$j!X:&o8GL,Qo(qHN\/4;Zm4+"9\eAU]J[A"BYd-ErjbngBmd?#39_.)4M"uZiT68"Ts\ke-$2]UBD_@8HI=-Cl8>D!M0>A7G@jme,TO!e-aY*e,dAdbXm]ne,bd7Wr]!s:=ET5DZg**"9\bdlNQKN2?]X&;Zm5&+4C@+":e[U"AAiRC]V<s6mMnO%T<K5O&H/a"9JE'!V?Ls"9H1=?jd#5!V@"_MdQS_Wr`,2ln`#sUi-A:;Zm4)"9\n$"9PA$!NQ9T"9JE'!i,s$o3_[4qZ;F(0CrQPD>OA3llN38Ui-A:;Zm4)GFJVgA2XJ(i)9a];Zm4*%M>0?"9`6nquj0$"BYd-U]U`&])nc0"+st`"H*<Yqu_RZ?j+XR!UND$!N$C_"9\e%"9e^&!NQ9T"9JE'!e^\Y_dENBqZ6Ue9#G$;#)`N[!W6_@dpQ#D"9Iij"9PB;!N8p"=9J[&qZ6Tt"1)A9#(lsSlo_=VUi-A:;Zm4);Zm5H"9\asquWYr"BYd-"Hrn_!J^2RF5$`n!UMmU!i0`;?rI12<`9,(XoXTQ"CsCl!ME?o=9J[&!sA`0!i,mndpN@&gB%4c!L$n5DZg+-"9\e%9ENO=".g;3:/_8uQ;[nh?N^K:#4t"\dmO56$kc6(>U0G?A0_9tCa9-Gc;OiK;Zm4(>S2l:,SW'J!O,g/"9H/?[Sm;3;Zm4);Zm4E"9\r'MZa/u"AEc;<,``8mo'>l;Zm4-KnBW=2?AU7;Zm562<tLf4:Dj=*./t6!JD^$``!!C;Zm4*@']s%A2XOUmo'>lC_WWF"<7g_"DiH2"9\jS"9]!/2[>sR"C*kg"BSM)"4gBRmo'>l!K+c""CsD4#*)UbzclN/e"9\e+,Qk8L1^$]5UK\#jS2;cPRfju;'Q=),1aE2L!Jm3J"9^i+"9H;:!NQ7F!sA`0!Q5$*bQM#N?ig-*!UKi>K4"enirR(!"cHak"bZo`!UKiai)9a]PSO)t$%t_U]`\AKbQJ%L"9GP(=9JZC!sA`0!UKjRUL41^MZN/G]JEpt?j3;+!UKsDgL(3.b5ofi#KpKW"oA>=!OOpr!N$4b"9\bl"9]97"9HkJ!K^4_#ZCj/7T0Em"BYe;Mus1c!L*]fo)YA&Xq'5C"<3g2U_mP#B]B3r!NZ=3!Pfr`P\^Ab%IA9J#5ioHoDt1cB*"4ubR(Xu$1nB1!L,Kp!L*W$!K7,U!L*VL?ie_e"B5HW"9GTB`'@6("BYd-Wr^EI!R(ZI`(OJ_?j!G1!ON%-!N$:\"9\bl"9]K="9FN]!T-fY";q=n3>_gu;Zm4;lkBKg,Xb`=KEP10K4,/s*,W;?">g.D'Q>eu1aE2L!Mqm],Qnea;Zm4k!!!!/*WQ0?"9PU@":.p/"B\S*!q9+k=9JZC!R(ZL_up+A?jGuu!Q56/qd9H2qZ4nF"1)A9"1&$H_um>R?ic_t!OMls!UO_-\5NM5ZjH("oDsO]=9Mk9!K7-aRflE+%BOMU^C'T9":rEOFE7JIE's4"]*&/)"h\dT!NZCI]El/]"Tstp,QnP:!L*W#%a54FMuekaYQBaa]F2(IOo^dUe./hd,6['6BsRm5MuWm;N+.\GMug`q>R'3h!K7&D?j"k_"AAou"9GTB"CP.2"9;@',T]ke$B,i*U^Gl[`&%St#1QKT.LZ]\%eL+`bAIT]U^i?.%#b>uBEj/Q@5L(L,QoYL;Zm4KGDcS6"<8D#,R<Z]*&JoD_ursh"BYd-Wr^EI!R(ZIb?tR-qZ4V?"1qqA"cEE"!OPL-!UO_-^Jb7<!!!!")uos="9PUJ!LQdg]`\A;!OMt1X9;W.?ig-*!NZL[o3_`sP6&#m"3Y'S$HrOH!Sd^Qi)9a]"9GS*"9\b=!NQ76"9Gk4!OMu3MdQY1ZN7]B!LmHt!W)o!Zj"'L?j!_9!Mfnb!ShSr!)j"'=Ao>*%T<K5#ZCj/7T0Emg]IZ^"9Gk1!Sdf[4((dP#_N/bU^-3nV?QSm"9I9Y!T6lZ1aE2d=&T5)!PJV@=9N.;!L*]i"9F0sDul!b"=sST!L*W"%_O3j!L*VV",$jMisk'n%FbE/e,beCB*"4t%$UmRoE>Q^!Kkh8!Pnf$#3,`KPQ@"R"-[6r;us=5!M"'2Q;[nh,Qo@n>7<n^!W3.k6iifG">)_=0`)6j"=-*K4<-a7"9\j*">iYJ/6;rl"9I7X"=I+Nli[q`G7V%i%J1%h1dlgUr&tUtS.>/o#4sDT"B%?%49:,aK*3/,"AEc<"9]l1!T$`X($lX!!"I^?zWl,eU;Zm4)"B5EcKEME["C-!KN,W1RKFF(GoDu]:quk4R%[;/C!JCj1irSch-P(kE#Lid-!M]b@%)`;(<!<O)KE7%TKE8mi!J.QXKE)%+KPdajKE8mi<!&fq!JCK<4('jDN,Jhe;Zm4(!MfapS-2ps!PJU:!NZD,X98R)?ig-*!MfsQK4"o\qZ32l#D6Cb?m>]JKE7;nbQ4RK;Zm4(,QoA&,QoY4fEeMt";E`p"=R1O$ij3/'Ef9V"<;=_,QWK"5Z7dg,U<L4">p<-N`-&`,TbD8g^*6ZEs18*JclK=*$dWI"9]uM"9FQ^S,cIj!PJU:"9G;$X98Z."9GP(bQ@tNqZ3c!"S6"%"1nTXS-8Fko3`dDK)qbN"J]?1%?(=P!R(SA#ZCj/%)a"D";%),!M<9n!O;h2#mCA=zWid-<;Zm4)llMAs)tZE40N/)WGZ+_J";q=V_cmNh"61(_"9]]-":P=:KI-^&!PJU:"9FGa"9\j0ZiRN9?ifj"!JCQm_dENBP6$UE"2eLO#(lr8N!6Oq941BnV?,b*"9Gk1"<LJE4CeNs"9_g0!JGN1E&P$*"AB?-%'0Kn!mCbrX:L86j;;\?ge5NfoP>lZUC<(jPRGD1"V%7.<Kd^TgM?k+!PrSEA-U4n4DY%_dpN<:DZhTo;Zm5F!!!!g+ohTC"9PXc$*[>2]`\@h!K7-^"9_g04ECP9E!;F.!OMmGb]$@1]E[Et$/?[)%C?J,M[tJb]OD"`]EPqK$1):*$+'nilNsp%ScQJb])fPF!!0_W<:^.'!PnfL-IW".!L*V<!K7&lP@+I`DZkH5"9\bL._?g%U^Rl8!PJUGHN[;Y;Zm4+!L!en'K-33BN#$:'I3f\\5NM5&-]*:";CmT$_UE$n5BGm>;T:_"=sV<$ERJX"9^;U'Q?Wrcr1&M56pK["9]Ds"9bZ%!Q\1Bpeq:u>;T:a"<7K,<!6GO"9\iZ"9aNZ!NQ7f"9IQd!UKqkUL48#Wr_9nK&^6b"9I!Q"9OO#$,BIB=9JZc"9I9\g]RYk?ig-*!TX:9gL('ZqZ5IQ"f#H+'WV8qe-(tCN,Jh";Zm4)"iCN%'K-&L^f(@=!lS%?!g<ZEX'7Dc<!35T"9\iZg]a?L!PJU:!sA`0li[BK"9GP(=9JZcUB0]aJ(%d/"eu+RN!JZV?j""B!TXLOb?u*d;utJR!fR/Wi)9a]"9IQa"9\j0Munq??j4^T!TZSbgL,;j"9I"-"9OO#"LqA5<$VS\>U0Ft"B&2=!S;,I"9]DsU]Hc[V[*,)<!h=\!g?hF;$O+,$+pb,#eVWD&)7?\]OIXR"ULV.<!3N'ZNLC_";Gf9"isUFWr_Pi!TX@ag]U^^!PJU:qZ5IT:@hio"OdD<jA,;S?qJNB!RqXt!N$?c"9\db<!&FcP?S.e>;TRd"9F\G"9^;U'Q>l"a&<*D;Zm4("9\b7KEHs-P?TjS>;TRd<!3:"1fOT0>QU*n1TO_:">*RUVGdU#;%-D*#)!,<%?)bn$d9%'PQI%d"V7C31gC0B"9FEb"9^;U'Q@(,cVjrL;Zm4)!TXB>g]U^^!PJU:>63L^j=g+4X'd^a"9I!V"9OO#!k)#1o32VK1^E@o>QU*n!P;Pm">*RUE&+0k;Zm4;:SS'>'FYUR1h7j7r+mV]^^]'0"9_[)"9HM@"K56%E&4Nt;Zm4;"1nTt'K-'nLf4EZ;Zm4*"9\dl"9R.Q"B\S*'Fn%E#)c#R+B&CG";q>9]3>[h/F*E>"9]EX"9Yl,"A_r!"SPas"4dR4"9]Dsg]FZX!PJU:"9IQd!Sdf[=lWmo%`8>.e.erkV@1<C"9OM_!iJs"&la,9,Qnei,Qor7"9tZ</-L&?<)`n6";E*a"ccLa85fWoW)Eg%;Zm4(1fOO<6irQV"C*2T$Ht)$[o3D483[di"9\tq"9PK"jB#7_"BYd-]`\Ak!SdeYgL('Z])gsoJs0S0"9I!Q"9OO#<)6Eq!g?hF!S'#3o)pf><+Kr5"9a&S'Q@p$Vc*^$;Zm4(!TXFHj9/Qf?ig-*!T\E^_dES9!Rq.,!N$@n"9\db;utQKP?S3lj8u[i$]K9:$G6P,ge:t&!e``A$g\7k":X'9"9^;U'Q@lpVc*^$;Zm4)"9\dmj93J$"BYd-Wr_Pi"9\i.liN+J?j3;+!fR5VUL48KgB$@;b?t@6"9I">"9OO#"7K.kz^Dd.Q"9\e+UBDuD*#ro?X=OJW">p;`KLu@Y;Zm4("9\b@X9,n1!P\aJ$%r_Gr-&V*Uii^?A:.hqoF,A["Tn$#O4t,f!Ps-aP]TQG,><Ic49;cr!L.L*%T<K50N/)WErgps"d9'O]6mik!L.t,#4r/e":p_#"<df!-;t$M"BYe#F9;XKN,s@LZN5^[C;W.G[K=)g"9\i.Ws!'6!JGDq5#VRe*V9fJ";\og!Rq2SWr]R1!NZD)U]ad&!PJU:MZKm^"H-Xl!W)nnU]cT`?jD;b!ON!YX'c//ZN7-3#O>b"",d30X9\'!?j!_9!Ls7U!N#t;"9\bT,QWp('Ef9V1b9mTJC@^J/M%#*;Zm4+;Zm4'!!!%lz!ijll";q=f"OMD*"=+#d"7T4ln5BGm"9J9!"9FHRS-W$r8e.X2irg?l!K:t"fM_nUV(;`M"=+*N*&I]\/-Jj%"8c:B1aEJDP?SGX#*^Z*li[H<",KkVErh4&dg!`q!L.P9^BWHr"9FG^"=@%M"><[V>Y\3#"9_g0"9GQ6<8.G4N+:TKa9A@?-5khE!O`#f;Zm4+;Zm4n"9GT3ZigM6"9GP("1&$8!NZZ:@pfA-VIT^t"9I!Q!O,K*MueY0!K7!Z!K8Xh!K7&qP[jot>QKcaUL4;DDZi`9"9\ai!Mgc8"9H1==9JZ+!OMt4ZigE1?ig-*!Mftdb?tAJZN7-0!fLFi"lo]S!Rq.I^/G.;"9GS)ZigM6"9GP(!W)o)ZidXB?ig-*!ON(.K4"`W_Z?hC"Og`_$\SPN!Rq.IAlAg8mSa5k"9GS)"9\j0e,e&$?j""A!NZIbgL(/bKE7SFe,cEK;Zm4(;Zm4O1%PN4gB8d@,V3n#*&JoD"B#BP&hFpt,QoA$,Qo)L^a'%N"=u))"9]tq"9Gr0!VTFpzeKY%o"9\e+,QY\Z!P;PE]3>\3'Euqd"@N9TDukO];Zm4C!JCN9"9_g0N,o$,!PAO9ZNPAk!Q8qOGQE^*e-$;`"9G>"!Pfr`$i9t;!M0>)&"E[5!P]/($\SPfb]aGZKIuL!!OQ;<!ON#p#h1D<e--?#ZrGK]ZiRuDKEg03ZiQBlb5m7sF;&$`!N$?["9\bT"9H;:"?'0]!m":C,U<Ld*$bYd:]ZR1"9^hFj8t]I!PJU:"9IiloE5;!"9GP(#D3'<j9,!]P@.#aqZ6<i!L$ml#E&WLg][4VV@D#U"9Oeg!f0bX=&T5)&k#Hp,Qo(q,Qnf\,Qor/,QoB'<?sD;,QpM';Zm4c"=+#Wj:&[H9I'`O,QnO/;FDd0!sA`0!UKlP"9_g0!NQ7n"9IQdli[@&j'WN$MZT+H"litmEr,p&oEKqU?ig-*!TXHCMdQS__ZB*.#.%\>"G?g2!gE__``!!C;Zm4(;Zm5A*6\H8j9cTk)$DbtV*"k`$nMM^":(]+":e?5o1)^^2?JqM;Zm4c!!!!@$NL/,"9PTk,[aOR'MKbT"B6WL">!8(/9!YV1aE2T!)j"'">p<=";q=n&i:<_,Qo(q;Zm4kKF7Ve$N+`Z2cBh^zQj<Zl"9\e+"=,s**%V41"9IOe1^"gU49P]g@\[-Q"FC8&&5r]7%T<K5'pJci"9Z:M'Q>[W/0k?4">p<5!!!u>)uos="9PUe"8Gdt!L+"n!L*VV!L,aR"lo]^PQ?;uPQAT$N!HrqPQ@!L"+t+b<!\+a!N$"4"9\aq"9d(M!r,[sj@TOb;Zm4)"9\ma/-D8<L]eRuX&]o;;Zm4."9GkW"9\j0ZiSqa?idS7qZ5JFZqFd-?idS7b5ntS#NK1r"nVhk!Sd^Q:/_8u4<t%\6mMmL"B%'%!MqUU":;^DN!H^8G6kPYljCCA'L[EQN'7]HKF`_B"I(DB"B%'%4<t%\6mMmL"B%'%=9JZ3"9GS,X98R;?jD;b!ON'C]3kZoRfTl#"J]?,DZg*:"9\b\"9FQ^/4WVAK)s%%.C0-YgB8401iNJTIo?IQ=9JZ3!sA`0!Sd_2o3_ZYZN7E:UcVreV@2_k"9I9Y"9;@'"Ai#""@lAn!Sdb[=9JZ3b5pB$"4LW]#/^JKU^#"Mgi!;r;Zm4(;Zm58"9\at"9_M!"9_1m"9^DW"9GH"!K7*`"BYe;+4DUTJ,tmG`rVD*"9\i."9^Y^ZiSqa"BYd-=b?b1g]=0X?j+XR!ON!1gL('*quNSqg]=8X;Zm4(Y6+$&";G)B!M<9n&_%/P1`MYg"7'/"!Lttl*!OeJo)plM">j(g!PVJ8IT$@PE$srS"9\aiWrsMC!L.O4%T<K5+&`:FzSKe+7"9\e,"9QA;ZuZ8d!R(ZIj90:?!Q50K&$uG']E,YlYRg@,U^6l!Oo`K+Zj"AK,6u-r1oh.W]DquF]IT0H]E,hLN!8MJ]E+5tZN6!c"hS.Qe8GJ;;Zm4("9\tVP61MX2?^5b;Zm4K"9\kS*!ahh'Po#t1isuG#4tn8$D[aI"B6ot"9]tq"9]97"9b)j!mjjK9I'`lE'Lr;,Qp5/,Qo)l;Zm56"=+2]9JgQ2"9\j*bQ[3/HpR'/#il$!oE>W@;Zm4*44=4j*"3HRN*IV2A0_9f#ZCj/OAc8b>Qckb^aoV)%CAe0N->Z"]EaZ+9K[e3$.M-Y%"nht/-h[q"AC'D"HZObfM_nU;Zm4*oE5<4"9GP(=9JZk!sA`0!gEbNdpN4JqZ6<l"Og`Z?m>^=!Sg9<!gIU+%T<K5"bZu."9H/-!QJ%@=9JZk!sA`0!gEbNj'YTNlN->W#)cjj"oJDV!gE__fM_nU!V?Krj9,La!PJU:"9Iil!V?Lso3_Urb5pZ*!qTe(!ODgng]O$RV?`Ul"9Oeg!L?Xe]`\As"9\i.liNCR"BYd-"OdD<j9(<J?if!_!gEiZX'c("ZN9,4,cb;VGe4"Cg]l58P]$[*;Zm4)"=sT+<!5l?"?Zff"<:Yl"9`6\"9JL#!Q\1BErioV/;"(I"9HG[b]!Tp!P8I8"9I"k]E,en;Zm4(.J![E4B)?p**a`l,\//'1i+E?"9_Ur!gEci=9JZkMZT+G"fl#5?c)p2gct+4P]$[*;Zm4);Zm51"9\h('*=1m$cFrPSl5ap)$E>0Fp#>Z"9]u."9Xrg"F!cI!gEci=9JZk])n3""bU1b#Km/7g]YN&V?W7c"9Oeg!j5H)&G-G(";/R%,]GR2BEH-m;Zm4+!K7*+"9_g0>]TqYE*VE+"9\bD!PAHJ!PAs@=5*cI!PAGn"9\b6!gZafCa9-/"B%oM&kla",QoY,,QoAt;Zm56oE53?"9GP(=9JZkqZ6<l!J=b\"QKOLg]=`hV?jO0"9Oeg"6NMbzZPWZB"9\e+"9`sJ"9H#2"9;@''Hg<W'Ef9V23W4m,QlO1"<7fF!L*^E"9_g0!NQ6k9*(7[S,qAP?ig-*!L*W>dpN=-KE6`/]E+l2;Zm4(N#S96j8m4/;Zm4?"9FG]PQV$#"BYd-#)`MHPQHbN?j;Mi!K7)TUL4=Z,6=#1KEJPg]PdoR;Zm4(=9L_r!sA`0F)1tiF*%O9MlQtc$H-la!P\a?ItIlGC]o-)I_u:3C]V@g!,NpuCj34%UMKtI!L.*u"04P#_um&J]PdoS;Zm4*!!!!7"onW'"9PTd*$A/_*!@,^1TO^o,U<L4">p<-%T<K5%,;lY)"[ioz]c7"P"9\e+"9]!/"9]!/"9Pf+!NQ76"9Gk4"9\j0g]?14?ifj"!PAWsj'VobdfHf["05f6DZg*:"9\b\"9J9r!Sdb[]`\A;!OMt1ZijJ6?idS7qZ3c3g^@Kj?j2GhlN+@##1Hrb$'YId!Sd^Q!)j"'"BYe#N,s@L!JCRV"9Fa.4ECO^E!P,#o)o<r!M"+&!K7H2oE53gHiep-S7DYb%ZCQ!+T[6!^B=ZB#h45&e9;#%PTRLE4FCTA#kVbW$e,L,dfY7,!Ps.ZPY?.GdnG,i4A0&d!M"'2%T<K5'$LKC"<G-c"C>"0)urn?,Qntf!TRAu&hH])PQV2L/-5JTE)c];HNYTNZ31:5!!!E.z!ii^H+B&CG%2,EEKp*2Ro)r>"PRISL"9]D>":P=:PQ4Vb"BYd-]E89>MZK%C!qTe(",d2m]E7\4?ifj"!L*boUL4:Y"9F/Z"9H/R"9;@'"9;@'!N8p"#/h"i'&3MfA-2r;"BYdhN,re<F*%NcNU$^P$a]p8FArAG#cnHI:pV-cFCG[Nlt:DSbQbug"T/E1!P\a?"e6QKdg21^@KQHOC^fZHoEOr#"UF)t,jPnmC]V@gP[jls,<TcC/-M_U"FP+jPR^Up"BYd-]E89>])fPFPY5Bl?j2/`!JC[S!N$+?"9\b<"9\^'!<J3Z!!!!.W?M<B"9\e,/-Xs1"9_UjFE7Ji$hFJe]E,YtHj?DM!TX:"g][_3!R(ZQ"9\b%ZiRrf;Zm4("9\df!TX5Zj9/Qf?ig-*!TZVkP@+L1qZ5a\%JsN6-bBE?!Rt=]!N#t#"9\db":(Su"Q32]6mMmT9I'`lE":n2,QoAl;FE'@;Zm4+"=+616nDRg":s9c!n^ES*$bYdB*!UB"9^hF">iqR49Pd)kQCp_o2[+?;Zm4,&W6hF'H@`R?URm>"9Gr!Zq:HL;Zm4("9\gW"9dX]!L?Xe>6G&d;Zm4kFFs_3ZiC-6ZkM0pZiRuDX9ZoLZiQBlMZJJ343M"5b\mW+;Zm4(!Sd^J"9H1==9JZc!sA`0!Sda8dpN4RMZSh?"Og`\"02I`e-G#AN,Jh";Zm4)X9R`$!PE:`!K-1G"=-rc6nDRgll6.+%FcX1",mTRU^io=IfmUi$d:.qU^`8H.fuLO%`AXCoGhFAbQUBE,QoA";Zm5."9I9f"9\b=!fR3a=9JZc)Zks$N!8f\?j""BqZ5Ik"+st^",d5>j9($B?j))_U]JsQMufdb;Zm4)"9\e@#0[3c!TaiENs$FJ"=uqAlNBm,<,_kq`d%[i;Zm4("9\eI/-<Rb1i+E?6pt$#9KXR'"=,5q!T$`X:/_8uWr_Pi!TX@ali^Dn?ig-*!TXL'_dEV*K)t$<!OH/7DZg*j"9\db"9QVB,7mcV!Po8A*<ZKrZigE\"E\\c]Pr(I!P8I8"9R@tb]!T@^a'$`"9Gk1!j5H)"FC8>E"IX),Qo)4,QoYd;Zm4s"9\hQ"9J9r!NQ7f!sA`0!TX<@li^Dn?jD;b!fRB5dpNH6)Zks&j9FpX?j4.C!Rq8D!N#n9"9\db"9Olf!ln4B!knj0"9]u._Z@JM$kbs'<$VSl>U0FlA0_9lmo'>l"9F/W"9\j0"9GS+Huf=qErioV?crRW"9HG[]E,bM"T&<&"9HG[U`fcG!PAOC"9GTFCi]Wq!P\a?!PAHG!MTV%!j2R2!O`$9;Zm5&"9\f#'LX?J1]cW@<(nP?!jc)>!M!+/;Zm5&!TX=>j9/Qf?ig-*!TX?PX'c15quP:]Mufd\;Zm4)!!!/rz!iq&)^f(@=)$EnAL]YHs";G)C!JjYWTMksr;Zm4.!h9JYKHqfG!U9dp":);-!JE9T<$V^mK7aU)";GeU"5m)\W)Eg%,QpdE%/^L_&*.;4"^DD1,Qor7,Qq(_,Qng',QpM_"9\aY"9c55"6`Yd!J'bE"9IS&!O,K*=9JZ3"9GS,"9\b=4ECPaE!P,#"dB&Sb]"*A!TX@l":=uLFE7KL$KDVlU]L+,Hi^hh!MfbolidlhKF="K"RK\$$*4Q:":E'NliFmIliH/J!TY."ErkV1C<Ha%"9J.6r,;\K!e^[W"9\b%liFmIliH/J!TZHG!TX<L"9\b6]-^GZ!!2.P*nq+Y!Pnft!S[Y9!L*Vd!OMmg"f#HM&&\LE!e^TO%T<K5K3Km3,Qo)/+KGWU4</0V"C,23"CsV?"9_+<!gI:q"9H1==9J\qMZTCO#-2,5!W)q_S-H$%?ig-+!gEbEgL('ZZN?Wu"e/m)DZg-#"9\eE6ihg:!JD^$N$JNg,Qo@n>YG0_"9\j*"9`+2"AF;DqZL.L1h:P:<,<f_'QbT'"FMHtT4_(*j@TOV;Zm4()>jNDS/MOs;Zm4C"9\bP!gG<9"9H1==9J\qirY_R#(p:e!S[[?S87.m?jDks!fRAR!lT![DGpZ@,QnMA#.+Di]QXeFe-5a[!L/'?4pg!i#5eacr$r&C;Hum#"9Oej"9\b=!lP0DWrf("!h9AoPQY(k?j;Mj!gEo4j'VobK*%8@"H-Xl"1nWQU]cT`?ig-+UB6ri#ErO!!Rq10!lP,:2H'_]&mTn_,QoY,,Qp5G9j@gC;Zm4K"9\eP!h96hS-2ps?j=4E!h9JTMdQY)"9ONR"9QM[!QJ%@E%KH@"9\bd!!;%VzWqRM6;Zm4)"9\nt"9Z_D"h7J6]P@WQ3><G@!ON!YUj!%@e-;EN,W'uPgcc7e`!!.B%-/oD4<t%\6mMmTW)Eg%"9k.r"9Z#'"3=CDp_O&i;Zm4+MZa1(i'_N`!K%!\"9H.l_up3F"9GP(]`\AC!OMt1]3k`aqZ4>7"Og`Z!W)o9]EH\k?j;5a!NZLc!N$C/"9\bdS-3b/Ug.sAHpF_:#0[+DZiq!$^B=ZB"9G"n"L(f-X#Uk>56M)k"9H/C!PAP;_dE`8RfU/)!n1N[DZg*B"9\bdZiZn!!PJU:"9H.<!PAP;j'W+EqZ4&/#NK1m"fh[:X9.EiV@;el"9IQa"/o-$Q;[nh)$DJk7@OD_$nN*3"9H,="=,5q1iO)fE)GWu;Zm4c!PAGf]ED=>?j"RQ!PAZT]3k_noDu#rj8l+d;Zm4(S-/l&"C-!KUi8r,^B=Z?"9I!Q"F*iJ!RF[IWr^-A!PAO9_us0F?j"RQb5o7c#ErNt#/^JSX9?^SV?DhY"9IQa"D1R8lj-MmKc>[M":DdBDukZ^"9\aqS,oQeWE@=E(]g--!O`*;;Zm4+;Zm4=;Zm5Q!N6'S!LuabhGXO[!sA`-"De+'$D[f,X%!`N!LuY."9\b6PR^UpDuohF"9\jd"9RIZ"<LJE1ii\fE)3eC"9]7b!Ls2*G>eVI0N/)Wr_iq&;Zm4)";Cp'1b;<GRnNr_"E/Q[!Oku1LJn<YS8>e>!Ls,j!M!`]!Ls2,!L*c"!Ls1T?j3TI"C,1."9G<:!q0%jz`@h2k"9\e,UB@/f2@G$>;Zm5>"9]"7A-S]*!P;PEE,2c_;Zm5>!mCe'"9_g0!NQ:O!sA`0!n7;D'4:k<?lK1>_ZJ$qOeZ:dPQJJuoDtfn;Zm4),QpM+KR<gUj8mp?<BOLe!L*VL!JD^$,Qn.<"9G<7X9"8*F<gtiW)Eg%;Zm4,]EAGka8sZp,QoY'"De+GU]J+R`$>Hf,Qq'I!K7''!Rr@taAW3E"9QLHbQIs["BYd.#0R(db^@TA?j=LM!mH&8j'XRYPQJL#oDtfn;Zm4)($l1P!J2#e"9\ko/-><>!LtD<Ua-(Z,QqWYPUlj:"9_U'!NQ:O"9QdM!n7?TlX0b"MZV**&rU-%%#b8#!qZMjIT$@P!Ls1L!Ls1\/HM(=;Zm4+"9\amquXr<"BYd-U]U`&!iuM+g]<@TE*^WiKEM@`X9$'CX<5mmX9$-=X<Hm2!iuA'!j$CR!iuF=!i-!h!iuEe@!_qP!UL$V!jlkK^/G.;"9QdJ!lP4D"9H1=!W)r:!Jmda9q)4.]LBG?oPXj6;Zm4)"9\nl/-;JC!P8mO>7:Oc!K7&k])el>1TLWZ"9`O[C^'<,"9]SF"9G?@]3>\k;Zm4(!Ls2+Ui[jb,U<Kn2F&(Z;Zm5FP6;)WZiSBYliZ#H"/L,L!V?\_>QL(=&%k(g.sqSt!Ls\M#+Jg*hbsX\TR;@n"EZO(bU-6k"BYd.]`\DTe-#mT"9GP)!W)rJ_ulcB?ig-+!mC_8ZX=$e"9Q4="9S46"9;@'".)ph;ZmTc;Zm47"9\dV"9_7o"9a6R!oHoZoE,4!"9QdK!mCdLP@+WZMZWMT#*WEs?m>`s!k\c-!q^C6%T<K5=9J]L"9QLE_up+S?j3;,!mCk\P@+WbU]S13oDtfq;Zm4).anK\$k`u]#.+ZCoFLS<IfYcBll6&%$hQUn%E&PE>QNV1!N[OLZm5cj;Zm4("9\b8"9JL#!qZQt=9J]Lb6%;="l!Dg@!_t!!k\WQ!N$C'"9\eu"9[O[!kqS9oE,4!!n7>SbQIsI"BYd.!W)rJoE2F-?j""B!mCbQ8qULbDZg-S"9\eu"9HeHbQ(QE"BYd.".KA9!Ku2FMOO[kK&^5>"9Q4:"9S46!V]Lqk#2Bc"9F/W49<)?!Q65dbTm<:"9FG^9F&K]!L-S0,Qn.4;Zm5>PQV-`PQWQ=]3>[EPQpIoquN;g,QoA&"9\aiZi\6GHmAgq"3^q=N!eoqIfdgp_u[M%%J2gk#4)BWUBJ4[F>bOd*`E1E!L-p>"C)?JKE7koX<[oL;Zm4(,)ZT="EZOT>TcrJ!L+i4>7:P&S.l%:S,o,\;Zm4($mYqQ"9H,=CiDsu^Jb7<;Zm4)!!!!_*<6'>"9PU=!LQdg1aE2<">p<=!)j"'0N/)W!LEp?"T&<)lnfDq#4l%#>s&;_1^"6B"9\iZ!PAn@"9_g0!TX=c]`\AC!OMt1qd9I%lN+X%#.n7J",d3@!PAeJK4"lKliF0mj8l+d;Zm4(;Zm4/"B5E#"9\j0KEQZ)"B9FCHuf=IErhL.#MTAD"9G#CoPeZj!L*]tqZI$F!M"*3!K7<^%/^5OP^F1_$k']Ke-N,ZHr6@6#c%KkX9AdW^a'$jdfG+&!!.b"4c9>o!Pnei"eu*OKE7<b#D5tV6j1tH!MjW:/lMlU#ZCj/)l+=8Zk9Z(!PJU:"9H.<_up3F"9GP(?qUO-!PAW[b?tR-dfIAk"H-Xj?qUO5!NZHW!N$1Y"9\bd!!"'=z!ir">fM_nU,QnM\?N_?:liE>E"H4T0/6*ZH,U<LD*$bYDQPSU4"9],6])pV`2?pZ/;Zm5&"0_rjZiUU$!R(ZU"iOYee8R[j^B=Z?"9H^I!VfRr]E89>"9F_f_up3F!Mjc;2p4.tciM?d[K4SQ"9\i."9jT["gCo.8d#7C"9\bLK*'\(>Qq&3;Zm4s"9\amliP7,"BYd-PQM$k"9IQbj9,Ls?jD;b!gEl+_dE_]MZN/J5O2\])7oq9!SfJ=!gIU+n5BGm;Zm4+Ef1'%"9_\C'ElKU*!@,^"=.mg/-1>*&hG[$,QoAD;Zm4c"9\at"9l;6"h7J6!J1FW!J7pg/6ifm"Df=d"Fj>Q"Mdq==9JZk!V?KtoE52q?jD;b!UNhP"5@2sDZg*r"9\dj"9HeHque0BG6OcO%,:p6/:R\Z4p[ZX%,;>o`%(kY;Zm40;Zm4/(BcR5;Zm4>;Zm52"9Ij[oE5;!"9GP(]`\As!TX@adpN9YqZ6<l"Og`Z?s<Zu!UKs<#.n7f#L!5(!gE__%T<K5E(e@W"9\bL"9]97"9\jC":P=:@f_.E_up+jZihNQG7C&M1$\pp`*s7a`!<XM%?tK+%K$aLqZ_]W!Q5"p!Q5#TPQAEiPQA]'?j-'%!JCW_!Ru#j``!!CPQ\&h%,?%9$N(:U'J*L=KEL:!.gknY>Qb:j"9\jB/-2AA*)n0d,[;St"Crb\!p<JbAlAg8E,;i`!j`"dK*4;U"@R2]"C>"0!UiqiOAc8b;Zm4)!qu`b#O>Da+&`:F2GP$g;Zm5&":PBe<-/.m#)jf1*uka>N!&]W!M"?@"3^q]XB[<+#h2$B.gVA-"Cr"T"9_[L"9`(1"9Gr0!NQ7n!sA`0!UKlPPQY(k?n9+r!UL$._dEYCqZ6<n#/agL#3u<V!ShHuPQ@Wi;Zm4)"9\c""9PK"!gEci=9JZkMZT+Gll0=7?j3k;!Sdb"!gIU+^/G.;Muo=H"9Gq5[Sm;3"Jd"='V#2^=9JZk"9IQdj9,Ls?ig-*!UL#Co3_e"X9%*JPQ@Wj;Zm4)"Te^Z!!!!2e0b4r"9\e,TF:NnF&l6F\5NM5;Zm4->/LNB1^k"=!JD^$N$JN?,Qq'I"9\aigBslX$t45fKHp\",QpdA">g.<"9F`4!g$=`TMksr"9OMb"9\j0Zi[T:j'Wf-irY/N!lJCIDZg+="9\e5"9R4S":.p/!K^4_@%.2@lo0i1j%>dI"9_[)"9S?s"/&Qq=9J\a!gEfjPQV#f?j3;,!fRAjX'c-a"9JES"9PrKFEURcF9Hpn"8c:ZHmAhW">+]uF<gu7YYtZ-;Zm40#.+PqPTpdA!sA`?!fR2fZijJ6?j""B!fR6QZX=!\"9JE("9PrK"AVku#(TVTS0S5*o`Q6849;5YFECM.b]aDiS-XcMFDQF3"?m*M!pg5X"9R@/!k;/3]`\Ci"9\i.Mup?g"BYd.!W)qO!jiVK'4:p#<U0^Fr!pVPV?)VV"9Pq2"Ro=m*$bZ7,Qn.$*a4J$"9`O!MupLf"BYd.#-.faN!kPO?neV_!W4Ic!N$3g"9\e5"9cM=ZiF#-!PJU:"9H.<;4@\j:B?7""5!Y@!O`$q;Zm4+1irf?>Qak-KR>$Jj')om;Zm4(N-#*A"8c:5HmAi*>7:Oc"EXbC$mYt&"=_f("E79B!ji%4=9J\aZN@K:N*BZjdpOC%U]LArZiR$);Zm4);Zm45>;UGN"=sZP!JGhG!g?gs\5NM5HN\Eo6B_NT"9_\C$lg<e"9H,=DukZ^;Zm5&;Zm4E"9\b6F92/8"9a&S<,c`-[o3D4"9OM`!fR7aK4"n9_ZGc`Atr`a%,:m]!ji!*YYtZ-;Zm4("9\kcErkK'<*TI=J5ZRRG`r72"9Ik."F*iJ!ji%4=9J\a])o>B-IZ?)1ZJOqqulV!Zu6'J;Zm4)"9\e9ZNJ3GN<@K2"9_[)A-2a/"9]SF"9G?8mo'>l_uZ2,#.%>@J5ZRR;Zm4+"9\e?"9bT#"=@%M*Wa7`>QMlD;Zm5&<`C/2"9_>L"9GZ(!T$`Xlq.C?;Zm4("9\c*Mup?g"BYd."N(;JN)Ro-?k1'U!W3,=!N$0n"9\e5qZ4`9_#`n8dfIr!!!2Ep;o8Y&!Png'"2b0+!L*Vl!PAI"Rp\Uq"9GS-"9J.5!T6lZ=9J\a!gEfjN!'0^?j?K0!gE`Wo3_UrMZSh<B&d8&"I&rb!ji!*N`-&`>;UF'"=+*HKR<fX;$H:e%bq8Y[!X>3D@)O/%ub>2U]h+\;Zm42/-H+-"3^e]<$VTgc;OiK<!/Hi"9bK#!S10P"/ebD"9_\/PQW@4"9GP)=9J\a>6:#lN(M3#?phO-quMVcZu6'J;Zm4);Zm4n"9\bg"B7li]Gu;E!n8J!"B'=e&5r]7E)*_B"9]'bMuqU0"BYd.#-.faN">Mf?s2Lk!W6KO!jlkKY>YQ,;Zm4+!!!2Sz!iqk5Lf4EZ?te!n"9]uT"9`C:8-Sce8qU.i^f(@=,R!<6"9_Y(`!#R."BYd-Wr^EI!R(ZIX'bu*K)rmq#2<Mh"mc8s!UKiakYhTe;Zm4("9\e)"9]!/_Zd8Cj:X"fA.>%>Zj"*dIh0a6$`kU9bR9@n.g_^S";Cm<"9_+<"9Z/4#*;adB2\p9aAW3E!KX8aljOLX,R1%G,QnfD^a'%N"=u))"9]tq_ZY-]"=.qm"Em]H`-,&^"BYd-liR@nlN->Q"/B6.!W)o9_ulcB?ileu!ON*\liEu";Zm4(2?i\s"9]uT"<8I]"=,ND/0$Jl"9\j*8qTT3"=.4^".3!i!TX[%`#GLC"BYd-liR@nlN->Q9#G$@#*T)+Zj)Frlu*"-;Zm4(r@A!5]E+`3'JcEh"=sS<,]F<Ic;OiK"9H.9_up+S"BYd-#D3&i`+[V-P@.;i]E,ADliEsb;Zm4($nMLJg]>#k`!d=flne5A]E,,9]ER?uN%AcI634_("N1]GKEVVY,Qn5X>7<&&23S'Q/-1tLN`-&`;Zm4)%(mR/*%Xc/"=u*(">hAL"9]\i,Ru5$"9F-U!j>N*cVjrL!ln4?"9]uT"9I(P`-,&^"BYd-Wr^EI!PAO9"9H1=!W)oA]EYEE?j+pZ!Q52CX'dUPPQA-,liEsj;Zm4(;Zm5";Zm5",Qid&"9nBt!m":CVGdU#"9HFB!Q5+C!OH/Y"OdCiZidXBlu*"-;Zm4(;Zm4M!Q5#q"9_g0!UKmk]`\AK!Q5*Ab?tS@lN+pT%`;ZX!W)o1ljgp@?iu;f!Q5JcX'c%I"9Gk5"9Ik-!QJ%@"N:]F1\1`_/-1tL!JThB"9]uh"9P/n!K7*`"BYe;ErhL.S-/kg">"TpKQ&oOqZPCWF92@G+T\)9qZVWU!Mk)G!NZF2"9F_j"<df1!L-fPgB!N=_#]cSlN*4NPQ?_CA-%nq'4=T,XD\5@;Zm4()$D2b>7<%c/qX2:/-3O#VGdU#jD?FN23S.D/-1tLmSa5k!!!!##64`("9PTg,T'G_"9a&S$j!X:&A/@G)mfXX";q=^j'*3C*@q<o!X(%W>9#I&"9`SR*!$OJzWm2Ra;Zm4)"9\j`_u]@+Ba"&F"9]h=,Qc%c!TRAuE!Q7CJcl3-">hq9"=,fDP6;#8"H7:f;Zm-F!NZ=S"9H1==9JZ3qZ3c$"litk"OdCYU]e#3!N$8+"9\b\!OO1P"9_g0!Sdb[!V6?IZj+-M?j3k;!Mg!R!N$=-"9\b\"B5A"KEME["@R;31ii\VE*f":"9\ai"9FGoKE8gjKE6`,])ftRKE?ZS"9Gq3*`E1E";q=^<ZD.-,kGOC'FYU",W$bL"9a&S!Ou&2">p<-!JE,4P6$=:_#]4,>60BXKE7<:?mAVOoL&`'S,oJh;Zm4("9Gk>!NZE+"9H1=!W)o!ZiSW`?idS7!NZ?lRpZ9oK)r=\"Og`aVIT_'"9I9Y";"K7"C>"0!KL(]Ergps_Zeh;!K:u3"k*Lb":r.aS8\Le^a'$`"9F/V";"K7,]F:S">p<-8d#1@gB7P1!JGE(hbsX\;Zm4(!&4Lmz!ijWdW)Eg%;Zm4(S.*n$X9"n1;Zm4B"<7KY*$bY)/-GcR++mc;aAW3EF*n)kK(B+M!JGCm^C'<1"9a)Q"9X0Q!N8p"F9;XK"BYe#Y'`Oa!Km6[ErgpsN!'0g"Di,[KE8gjHi\m$*de!_e,d"*;Zm4-;Zm4/"9\eqU]T1I"BYd-bQ@tNWr]!s#_QLe",d3(U^2T\?iuSn!L*c"!N$"<"9\bLhuTcTN(O3R;Zm4/;Zm45"9G<"!Mfj#gL(5DP6%H\#ErO#%?(=P!R(SADGpZ@=9JZ#qZ3Jq"m]Os"5<jPPQ\$pb\mUb;Zm4("9\b0"9H^K!NQ7&"9G;$!NZE+j'VobqZ4nE!J=b\"oA=rPQ]HCV@Bm5"9H^I!O#E)P?SGP"=+#'"9\c)!Vp0I]JKu6$+tHb!mCkuX:uq0$D]ij"7-0G,Q`oTUBEFWHmj@[_0e,`"LEIVHi]IR?j+qP"?Z_."9FI""=@%M"D1R8HuL$_*`E1Es&0%'!!!!"#QOi)"9PTq"@uGo"=R1O$j!X:!O`[Z;Zm4+S.h\($N)jd85fWo6X(N]"DTIj(/k>=";q=f,YA1m*`E1ElWXcS%l>%?;Zm4S>9#1(";Cq7"9^P,"=sSg!'aBbzWk98N;Zm4)"=+$+"9G<C,]IFLP?S_P>7<=i1`S^&">g.L,Qo\M"=tf$!O,K*=9JZ+!sA`0!NZ=OX'bu*'*6SbX95M2?inLP!Ls4L!Ru#jJ5ZRR;Zm4)"9GS("9\j0"9I!S!NQ7."9G;$e-#fc?iu;f!NZOLUL4<'qZ3Jo!i'-(!W)o)X9,/)ZX>!YS,o,^e,cEQ;Zm4(Es+$(;Zm4+`"(Qt+63JF!)j"'HijKS"BYe+ErgpsN!'07"AEk;PWEO%^B=Z?ZiQ*d^BV=SN!7u;G7'998:q)IKOP4oKF>En`,oVm"TkJ'=S!')!Pnei#-.cXKE7<b#.mh86iu+N!N$%e"9\ai"9GE!!JXMUzfI?k$"9\e,U^H<aaVsLZ":=,i$BS0hWrf@*!i,r"S-2ps!PJU;!sA`0!h9>9P@+TIb6#lj@d@D*#(luIXCCL'lX3?eirZ#c,cb;aDZg-+"9\eMF9h;6F9Hpn"7'/2HmAi2KHp\*;Zm4("De8:"EZaO"FMI?!JE9TN(bK"/0k?!A8_TUi)9a]"9F/Z!W-+I49<97>9"$P"=+*8"9a)t!i-T1S-2ps!PJU;K*%PG#-2,9<U0^^P\-[ub\mUc;Zm4)":PLU'EeOV*!?;=1]`=6TMksr;Zm4-"=scHF9.%?"9a&S9Q2#I\5NM5\65j8";E`q#P_4#Wrf@*!h9Ao"9H1=bQ@tN"9PA#!mCdL_dESYqZ<i"!Q/:G"eu-hU]JA@!K_p8PX<8qV?aI0"9QdJ#O#(hWr^]Q!R(ZIZNOA5XpjYb"Ea591ii_Oi@*F`":t,*KE8gjj8o/["dDjc$bQtfPQC\N^'gG7U^[/%Oog:HX98(qUBmXr&&]^obQS'Dr!\bk!W2ou!W3;r!W2u7!RtDm!W2t_8':qW]EQ2\N,Jh";Zm4)`!cjC!MjZBX<[p2<CC'm,Qq@W,QqXG;Zm5&"@NKF1^:<4!L+i4S0S4_;Zm4(Y[-!b";E`u"8Gdt&*sdr9EDLm`,o!!G7Ki<"bZop'RpA[4p$sj!osBPZmuO>,QrK!;Zm4s"<7L:Muek_G7!%-Zj<0a!L/'>4p^4C%\*s'lmiR9,Qoq5"=sSD>QLWG!N[OLZm5cR;Zm4(%[7.d"7'/2%J0r(U^3c?IfZnb$-Zq-`!XFH.hA-X"B5EWF9.%?"9a&S"h7J6"FC8nF<guW">p=(el)\SJclJagBcj@C_CPmHmAi*KHp[_;Zm4(!i,kS"9_g0!mC`L"OdFJb]\nP?rP5M!i1!tlX4;1"9Off"9Qec!r,[s#ZCj/*`E1EWrf@*!i,r""9_g0!mC`L!W)r"!mG.^@pfDN"+pZNPZd$SV@3"t"9QdJ"4pHST2Pjq;Zm4)/5uYB"DhmS"E\0""FO/o"9_CD49=#3!LtD<Ua-(2,QoY!"9\b,"9\[&!iT$#=9J]$ZN?p*U`3\D?j;5b!i,kgdpR4nliNCUbQ4RB;Zm4)!TQiR"9\al,TI@P$rh-J>QKEZ&mTA@,QoZ';Zm5>!i,k<"9_g0!NQ:'!sA`0!iuIIK4"l[MZT[T"P[;f",d6)U]fF[?j>']X9+VZbQ4RJ;Zm4)"9\eW"9P`)!q0%j?rI12!N6,(q^`)m"9FhoQNQP1K008;"9FhjQNQ89"9\i.$j+^QF9-sr#cq"3"CuTe*!(^<!K89,PU$B*;Zm4("9\eX<!.kR%K%ISHmAhgKHp[?;Zm4("9\j_!i,fpU]ad&?jDksb6"J<&&VcWDZg-+"9\eM"9G)m!WH"##L!UP"7$!AHmAhoKHp\:;Zm4("X*qjzWk',L;Zm4)!sAa7ZigEZ"9GP(]`\A3!NZD)e-&kV?j4^S!Mfh(qd9Y]qZ4&.#)cji#O;DlS-P6cV?G*D"9I!QoLMm`Muf^W";A]S":e?5!O,K*)$Z$N":_^@$p6?l'F(%'49:s7">)G5\5NM5;Zm4(!sA`k"C(t\N!'8c"B9FCr+$@k^B=ZFbQ3Y'-4S`8#c%K[!It30I_uQcN'moPU]KNW&&]\'!K8Q+ZN6!b!K7&@!K7&qPQ?GY>QKcaj'W,XDZi`<"9\ai!N]m3"9_g0!Rq2S",d30!NZrB'4:jI?ul@M!Ls@H!Ru#j(fLP?lWY>S,QoB:rWG&7"9\i.!!06$zWmr3l;Zm4)"=+',/.D.rC]mWm"9_g0N,o#i!Mfi!irjIF!N^6'!K.*!"9GlK!Mp'l^a'$c*!)i9jED-1Zin;R!Mjl>!UOXG#il$/!ON!*r!WEE1'+0U#fHb.`!$;AU]U;m"9Gq3OAc8b!sA`/!R(TB"9H1==9JZSqZ4nD#_QLc!V6?ie-L\7?j*e:!Q5/R!W6j=i)9a];Zm4("9I"3!Rq6SX'c.T,6?9r_u\%hV?><K"9JE$":e?5"<LJE!JaSVqu[')!SdeYe-#fQ"BYd-]`\A[!R(ZIMdQS_ZN8ha#0UBX"j6rEbQIHE?j!G1!Rq5C$Xa%j!i,k8!W2tqDc6cAVc*^$</Uk["9G<;/:US$li\1/!Pf*P$lf;[,QYM]!P;PEE(u5n;Zm4S%?pmD!Ls>s"KW-pWt3^(@KMcW$D[]mKP(=U]E=)s%"ncp!LsSY!Ls2,P\^SoC]U%,MdQV0DZj;K"9\b<LB30/Ue1ak;Zm4("9\b'S,qJF*WksDP6;08!MjZF2cBh^1aE2<4<t%\Zm5bo;Zm43!!!!h)uos="9PU5!mjjK^f(@=)$Co[,Qo(i$nMn$X9-"<!Lt\F"2k<n"9\iZ":P=:!ROaJ"BYe#<-*EiErgpsK*.Wc!K:u1#4iAtljnbgHj?DL"0;NnPQ_3.^a'$bP6$=;_#]35"9F/VN,T>\+aaCnHogj%,EmKTHi_'2PY;5/X%[mA"4LW[S8SNm;Zm4("9GS6"9\b=!NQ76"9Gk4!NZE+UL42)dfI)b!S^ub"02I0U][Z*V?tHI"9I9YlkWM&!$ChG!NZs9"9H1==9JZ3qZ3c$#ErNr!W)o!Zj).j?idS7!ON&`b?tOtU]I7qg]=8^;Zm4(;Zm4u;Zm4'!!!!g*WQ0?"9PUS".3!i";q=n<\+95;Zm4Z!PAO("9H1=Wr^EI!Q5*A"9_g0!UKmk!W)o1bQRNF?j"RQ!UKs\1LL<C"hOfRZie3RV?ran"9Iii!ME?o85fWoWr^EI!Q5*AbQM#N?ig-*!Q5-$"Iie7$1n8*!UKiaJ5ZRR>Xr9*;Zm4S"9\go!PBaX"9H1=liR@n"9HFA!PAP;gL(8=])h7$"P[;d"H*<!]E7,$j'YL\K)rml#)cji#kS/)!UKiafM_nU!sA`-"De+'S-/ss!Mjc;!KN'@!MfbUE!#n>"oJD&"<e,2$/>rbN""3[(]g-;.)Q/2S0nfb]FX?0S,oApr!S_j!n7AW!M"VnUB-kb_#^&8dfGs>PQ@!LC]U%,"-[+;XD\5H;Zm4(;Zm45"9\b><8/3f/.<.J'LX2L*)%U\/6#=H1c/2P4=h`\"<8[D"Em]H"9G>Udf^&C$M6F],ZH#lbQLg#I1Nt!,W#k(*!?(B6p)^t0AB\>"FC8.E.7*U,QoYT,Qo)L;D]Xe;Zm4+!!!"J)ZTj<"9PUC!U*GbHijKS"BYe+Ergps%]]_;X9"9!KO=o`!K7-^"9GlNCi]WAN"cBtMueS4!JFq`Erh4&!L*^t"9`O^KG4I%;$4`;#,DOKKLH<>]E-dgliFg%N!JDKe,b^5r!_'[quNPoPR#D>"5F%h#NQ3PUC#.g@KNW.%tjt:lt6?PX:*ei%%IJ%!JEt<!JCKiP^ES.;uqXQX'c!uDZiH4"9\ai"9J!jU^g<+U'Ag[";HLi"F*iJ"9;@'!NQ7.!sA`0!NZ=Oe-&kV?j""A!OMmVdpN4Ro)Yon!o%)cDZg*2"9\bT"=*tG"geCM'RVpq"fr'\*!bg6'I4q,"=tf$XADgu"BYd-e,ogV"9G;!U]^_3?ig-*!Rq:JUL4,oo)[>E#0UBT"1&$0X9Xqs?j=4D!Ls>j!Ru#jk#2Bc#dbiX/0$Jb"9\j*!!26szWjs,M;Zm4);Zm4gr!i90%AYrjE)QlB=9JZ;Wr]j9#O>b"?qUO5!NZC(!N#sX"9\bd!ONnH"9H1==9JZ;!sA`0!OMmgqd9I%ZN7]B"oD[.9q)1E]EO4$?j"jY"9GSK"9IS%!SC<R!K@4-@e1iJ"2"ZF/7TA>!)j"'o/S?A,Qnfj,Qo)<;CieE!sA`0=9MTN!JCRYN!)gqXE8LaE%J<rdf]c[!M"*4%frI/^a'$cquM`WG73136^&%>N+*<^N!%!!$A<$m$`jc4"9bM(KE8gj!Jno"KE)%+KR3LrKE8miHiqOm!JCK<F'qX?Ui-B(;Zm4(;Zm45!!!%tz!ijH_aAW3E"9G;#!Ls9p"9H1=Wr]:)!Ls8nZX<h2ZN6j("g_S=#)`M`U]If0?ie^W!L*\]!R,Hbpeq:u;Zm4)"9\au"@Qp%9EYC0"9_g0!Mjda!JDbO,i\p."T&;>"9FI#"<e-=!.8%(I!b1,_gDL$!L,tW"/AP;49i-"&"IP@?;gt0)>k'<";ood!NQ7&"9G;$!NZE+gL(,aUB..n#/agN$-WF7!R(SAi)9a]"9G;!"9\j0bQ5oi?j4^S!MfjNdpN=-irPq["litl%D2_+!R(SAcr1&M#3@*2Nf+$R!L+9!n-gQfb5o3U!L+:;S0S3<]PLFKHn#O2"4RdUS,p6>"V8fe'O1dbo*(WmXUhKf`!+WkC^8_rZjh[6N+>6["UN<]$mYklRfU-*!L+:+>7;c&P2cST!L+9!,Qo)42$>0M;Zm4+;Zm5()$Coh>7;JS"nZ9Q"DA"1#)l$0"=+#4!S:6QAlAg8z[OqO["9\e,":E4K!NQ:G"9QLE!mCdLo3_UrZNA&M#P2=,!UBg*Ziu(ilu*".;Zm4)"9\hb9F/.,!Ls1DHisJ'$rd?]"9H,=Dul$C?HWJ!"9F0p".3!i]`\DL"9\i._uf9-"BYd.",d6I]E-2`?ig-+!lP,_UL4;L]E5GCliEsa;Zm4),Qq@I,Qq(o"<7Gq"9FH,"/o-$YYtZ-!JEiA!JCKD">,!(E'^N-;Zm5."9Q53"9\b=!pg!l=9J]D])onR$_q)3!W)r2ljKRr?iu;g_uY[X?ic_u_uY[X?s2ds!jlhA!pjh.Qr=+j;Zm4,;Zm45;Zm5P!lP;i_us0F?j;Mj!lR]`b?tS("9Pql"9Rq."/o-$O;A%I;Zm4+XBYmY!LtDFUa-'o^bc/p"9a)QoE)6q70i`2"lfm\>W)Yf7T0EmliR@n"9QLC!lP4D)di^D"HroR!lQ$clX0e[liOOYliEsi;Zm4)o6^W'!Q"kn!LEhGHi]*-,S.OE%I=;sKQds^oE^*W!Q9Hn4pT#B$cED5j=:7a,Qp43*'=8GS,o-[F<gti,Qn.D!'l09"9`g)"9I@X6nhOB!L+i4"B'UuPUlq?,Qp43$iu$/"9Q2>!Tm;`=9J]D!sA`0!lP0,MORuuZNBIoMORuSdfRGg#HM55DZg-K"9\em"9PK"!q&ti>U0H"O&H/a;Zm4(!sA`,!lP0,li^DnX'fE=Wrg4Y!n1Ol!i,n)!pfrbOAc8b)$FaV0Q[F#,Qp44!JCl_r)!n#$k:\ig^]i(D@;[8ga!)n$-WPU#ZCj/pJV1t!JD^!!JCKD">,!(E.<KC;Zm5."9\e0WrpsP&cnLA,Qq'T!L*Vd!OO*Tel)\SHkQ#P"69K\N$JN?,Qp41"9\ai"9]!/"9R^a,QXTdHmAhW>7:OcKM2HZKE7SD/UR[%>7>l^Ht4>rHpe"**4oD`!M"OR,Qp4L$iu$/"9t?"!o?iY=9J]D!mCcMbQIsI?ig-+P6/[<%HCguDZg-K"9\emo)kjg$kdq6GC0nE"69d<N.1us$J[`EbQ7W*.g^k<";Cm4"9F`4!K^4_Mus1c"9IQbPQV+k!Mjc<D'l"\K*0VN">"MA"<di2Erqj7P7=TU!i12I%f?LK":X>pDul$;S-/npPQW-2)?QE1J^X[b!!8Ac%,1iJ!Pni%LoUTAPQHdEj8tPH?jG-]!Rq5#!j$;Ck>MKd;Zm4+"9\d]!!7mRzWgF(m;Zm4))$CoZ>9"mk'I7Y@"=+#</-&TOE6DH*]3>\#@2(O!>9#1F"=-((/-IdT"9\iZKF@meV\$cP!!h!SzXHb@;;Zm4)B'Tl8*"3Hb/8QR7<-0Ag"FMHt#Co_U4/3,[":Mk]&"$8u<ZDJ1"9\gj":1r)!NQ:?"9Q4=!k\Y<j'W)/!lP,%j'Vob!k\PrgL(>W!iuEQ!p"8&Lf4EZ":pS#Uhg'hZWdh=&;pZbZiR7Idp!4]!PAGgLXTH9;Zm4("EXp2dfYOS2@fLR;Zm4s!Rq5@bQM#N!PJU:!e^[ZN!)gq!M"34E!cCES-/nXKJ[`OE"DgL^B=ZZ":a,e"<di*^B=YWKE?f-G6.=?)8cuLKOP;,KEB@!$+smP"cNQ5dfuTO_#f:9ZN>d\PQB!Je,k:(?k9jM!Q6Y_!i0`;Lf4EZ;Zm42!k\l5]ED=>P@,U:!k\Pq_dEtl"9PZ1"9RY&"Ro=m!L+%D"9FGl"h7J6Wrg3B!k\X:_us0F?ig-+,6GMVXEppTjDP/&;Zm4);Zm45"C)5bP6>E7"Di#YFDqbSE$rO+;Zm5N"CqOn"DgaW33sSM9K!!oW)Eg%;Zm42,W#Pc$.NKc/9_-=%+GWsr+&KN"S=k`!Rq7JC^JlI"C*2T!PVJ8n5BGmi!#kV"<:YR#l%=$BEtY=/3BU0"B5Dd#-_#/!Pfr`,Qq(G"Jc/?":D)+$D:<#TMksr;Zm41"9\u)!k\M3ZijJ6!PJU;qZ=,-"cHah"1nWIZiu@q?ig-+!k\WI]3kZ/P6/B#!io]3#cn*/!osBZ5Z7dgWrg3B!k\X:_us0F?ig-+!k\^.?ibf4!iuO*!p"8&\5NM5>QiCY"9\b6!g$=`el)\S"9Pq2]EA8K"BYd.?qUR6!ji!_gL('ZUB8(/XF"=YjDP/&;Zm4)huhFd"<:YI"Ai#""i+%>,S.7=,W#OT"C,23"9_[LlN>I3>QUj,"9\aY"Je7\r(%h"a@GP""AC]V"5ZrZ<ZD-j;Zm4r$rd>l"9H,="C,n5#Co_U\5NM5<?*7d$jGEcZjOHiIfm=a"-cb)oEV0U.grEa"C)H'"9^P,"9Z,3!k;/3[U]HD"9\i."9Z,3!l._;<ZD77"9\hUZj37&<)jn?$)A)rbR=&eIf\=4$^=UQKE;!7j=;2T,Qq?Z;Zm4C/-H0=!Ls2+>7:P.X9!t&]3>[E<?*Oj!K7&<P[#I:A0_9YTMksrKEdeJ!m=UFcVjrL<,%g(ZlBJe%%JRRCa9-?O&H/a%dX<"!q$)qG6AHSO9>sp!jlJ=`-29qN!Y^V**dt&%a7*^%K$@i1^16:"Crb\!LQdg=9J]<>6;G?]E?&Z?j)Ah!j"9V!p"8&7T0EmBEk;D;Zm4+"-WlW**`WETMksr;Zm4($rd<%"9H,=*,oEB=Ao>*]`\DD!k\X:ZijJ6?jD;c]E*WE?k)u7!j!c]!p"8&LJn<Y,Qp43,Qp5G;Htbp;Zm4+"9\eq"9O*P"0PQ*";q>1!MrHmE/Oi%"9]]`f)k_GUK/?<;Zm4,!K72:#4l%MPU$B",Qne^"9\aq]E+<s"BYd.]`\DD!ji(2b?tR=irZk;XE.bPjDP/&;Zm4)"9\hhN!/QIqcbTP,QqWZ"9\ai!K7&o>7:q1"9FS,".iEo2cBh^<`9,(&l]4=$G6cUU^P[rIfna4%^[ctj9r%Q.g_^O"<7ce"9`Nd"9kAq!NQ:?!sA`0!k\Tq_us0F?ig-+!ou/t1ZMj^*if@TXE'e<V?O=."9RWb"OC!L&l_;P,Qo(q,QoZ/,Qp5G;Zm5F8c&aJ"3_BgF<guoHmAh?KHp\",QoY!"9\aa"9c/3"0YW+mo'>l"9Q4=!ji)4"9H1=j9#MfqZ=,+L"fu9P60eGL"fu<irZjo#NK2JDZg-C"9\eequuOfee\Gl;Zm4.LoU]n>Qja$;Zm4C&c2UT9JupTY>YQ,!!!!%1]RLU"9PXt$G]RCWri2%"9\i.oE1Tc"BYd.!W)rrr"$\Q?j))`".X;Qb?tL3Rf`5#46']P#4quX".TChJ5ZRR"9S2u!pg%l"9H1=Wri2%!pg$j&E@.3!W)rroFU%j?r$:p!osO^".X94aAW3EF9C_3":*CV%)>dE"5"XK"9]-<"=,?n"9^P,Zj;Id&-;D;B&a]/FBf-Ni)9a]Oo#7c!N^5@E$']8">Bk`!MfaR<`9,(Lf4EZ'EO.!!K9BM!L+i4C&sP%;Zm4+"9]*o":*:P"9`KC#EVje>7:OkPQV$!"9G>">7:P&P6:ou!MjZ9O&H/a"9G"nPQC+roHXP?"9FG^]E.pUKHp[$<@gfF!Q5#W!LtD<Y>YQ,"9S2rqud.)"9GP)]`\E'!pg$jdpNB<gB.!K!n1NX!W)rroE*KLb?ttbe,n\7S,oJo;Zm4*#ESu3!OGgKi)9a];Zm4(IHq'`/2dOlTMksr!sA`2!pg#Z"9H1==9J]tqZ?*eO1Sd#P67<UO1Sd&Wrhno$_q*KDZg.&"9\gs"9Yl,#5D+"Qr=+jCBObF>801&UBEBR"C,n-A8lY>YYtZ-F9/QL"D6[p"JAZrS-&ls"9S2t".TKr]3knsdfT.O)O"QJDZg.&"9\gs^'Kg!HoD00Y#>H+;Zm4)"?Zb+">iLl<!5l?$HrOIi)9a]^a'$b%+KY*Zm5sJ;Zm41"@N@%"AF1g;uqXt!K89,TMksr"9G;""9b).!K^4_#db'%U^!W=Ih/%P$G7?8PR*L;.h93&"9]+foE+M\"BYd.]`\E'qud-'"9GP)!W)rrlmL7i?j+p[!q[khdpN4RgB.!pj'Vn<"9RWn"9Y04#1-9OHmAh_KHp[o,Qq'I!g`qH"9H/_n5BGm#Y<tX"9`gOa8u'7lW/*2;Zm5H"C)&e"9^@ob5pg*7g%m<"9\kgo*)?s$kdqVN$JN?,Qp41"9\ai"9QVB"><[V":e?5!N/j!]R0k7&&\SOPU$X<e,tX1!n;E"!h9IZ!RrZM<'C\S!Q55Eg]@='N$JN,;Zm4("?Zec">iLl<!5l?"9\b%"85Xr^f(@="9cXF"9\i4>RUY=!WEl<hGXO[;Zm4+!f$o="-Zc-[o3D4;Zm4("9S3c!pg%l"9H1=#5\Jg!K"^%"M4a-j9Nk9V?DhZ"9Y.p"92:&c;OiKF9/6A"<H5t!WQ($Qr=+j;Zm4('<;6($k`TZe0G/2,Qo(f!o*h3!TYL/k#2Bc^B`3h"E[lL!Obo0=9J]tK*(ZJ"m]P#*ifA7j9"(DV@C`N"9Y.p!JaSVE"@R("9It-"C(tb!l%Y:"D\,C``!!C;Zm4,"9\n["9\jCS-#<]"BYd.ErsPge-#f:"CuQTCi][5!P`FR1TLT,e4B_k$i:&."9R@t!L<i[r!N?)$1rEO@RO;0$2akKe7Sj,PRmBm&%i&K!mH.h!mC\]!h;?q!mC\0"j6t;N!,VXgi!;s;Zm4)!qZZQ"9_g0".TGr"N(>3oM`q@?j;5b!q]F7]3l,d_uf!-S,oJj;Zm4*"9\n3lNNSQ>QaG<;Zm5F"9\qKL'!]?Hl<+hVc*^$,Qn5PV+_"[<!3=)"9\b%"M[k<#*]G\":E'b"9G>M]3>\#>7<Up$q(-.9EDb0!P;PE]3>\C@\X&,ZNONP"CuHuCiCZsM?F*L!!$7)z!ihOj-rU6O";q=^UK\EXC=<;p"9^8p"=+#_";"K7U^g<+>Qp?+"=+kD"<8C,"=,6<!!!-Zz!ir":85fWo1aE2L"B$cjj'*3K*Adm"!X(=_>9#a."9\u,ZNHk!2?E:P;Zm4K"9]!\bQZp'"BYd-!W)oA!R*?-RpZBBZiRfAoDtg!;Zm4(#0R,D,W5gn5Z7dg0N/)Wj'*3KPR+>k#NQm1"9J]_5Z7dg1aE2L"B$cj?;gt0/-1^A";D7W"=-)n"<9fT"9_CD49V<UH_Xdb"FC8&7dC?P$+)72`!$Xp;Zm4.,QoA&;CieE"9\b$RfrLb2?_A-;Zm4K"9\kc"9Y#i!NQ7N"9HFDbQIs["BYd-!W)oI`!+=l?j+pZ!R(_jX'c-qPQAE4oDtfl;Zm4(bU`go!TRAnKH2lP!X(=d%^\>$X:2I5X=>1ne-+h8!rHjF"\]0n"=s`+"9\jS)8&L=S.H+IHNYl)#Q"W,$BufT/9!5r^/G.;)$D2cL'$*4"=,l+!Q\1Bi)9a]?]tTq"9]uhbQ?^$"BYd-Wr^]Q!Q5*A"9H1=!W)oA`!,I7?ig-*!Rq;=lX0mk])g+Z"iF^NDZg*R"9\btUB.l'&hF'E,QoA$";D"*"<9fT/-JWl/1^h;"=,5q/9!5rVGdU#^aoTi"=u))gB8cI4=kG(1aELr"B$cjhbsX\"9H^Je-#nV"9GP(!W)oIbQlU)?j)Ag!PAWc!VC:57T0Emel)\Sc3&\#"=,l,!hWBo;[2Rk"9\asbQ7><"BYd-]`\AS!R(ZIP@+Fg])hO+#.n7F!qQH:`*)D6?ig-*bQ3FX?j5isbQ3FXj'XYD"9H.="9J.5!k)#1!Mq=M,Qo@q;CieE;Zm4+"CqUiC]jlC"9\b+Huf=QErhd6!MfjG$1p?$gi*MQH*[VZ":(01"<dfA#Q"i"X9#DM"Tt8%S-0>_"9]kKUi6Bf!L*]f>K[-mPQ1`KP]O_CPQAT$C]T_#!L*VL?ioA!"B5Gt"9GlJ"GThX#ZCj/(K1G>=9JZKgB#M$bU['%?idS7!PBr#!N$/#"9\bt_uZ0&!PJU:"9H^L!Q5+CgL('Z9**6>]E.>+V@'+""9J,q!?P/B!!!!=W[7]G"9\e,"9O*P!ME?o"0_pW"9_+t6ikY59QVN_1jgPO!JD^$"B&Je!LO:#>WcH<lr4"UHlKs)X9[6C#cn18W)Eg%!fR6dqud&$!PJU:"9O5Z!fR7a'WYUd"lfX]KG:Ip?j4.D!VC2l!N$A)"9\e-"9`C:"9k`&!iuJ,]`\B6!e^[Wqug+)?jD;b!iuX5X'c*h)Zk\3oE2.%XD\4B;Zm4)"9\h*"9\^'"9J!j!J")Ocr1&M>7=aA*!(hY>QL@"PU%?'$s[$<*!2=.'EO_/]3>\K;Zm4(;Zm4/"9\nL"9ceE!Ug3@;Zm4koMpfW$j!=7Ca9-/F<guWkYhTe!sA`-!e^WVX9;W.?idS8!e`5uMdQ\RPQCC[X9#1&;Zm4)"9\k#1]aaX`*NJOQtiZ?"@QK!"/o-$9I'aG6mMnG02huV=9J\Y!sA`0!W3##"9H1=!W)oqX;SWX?j4^T!e^d$gL(/B"9J,r"9PZC"@c;m!iuJ,=9J\Y])mWg/&Pa!"j6tK!Jmda".K@FKL<pj?j))`oDt-0XD\4B;Zm4),Qn1P>[.<F"@OL<!QS+A!epg#"9_+tMunN.>U0FV;$3n1$/>^>KL@9uD?bb$"jD88j95b[>7><K"9^ZA"9P5p!NQ9\"9O5Z"9\j0Mup'_?j5QlZN@4LKQCN%j'XA=ZiTf%X9#1,;Zm4)"5Ep<$uf\)>U0GOA0_9lCa9-'-;t$M";q>A!Kdd1$oA!s"9H,=!o?iY79go*,QpLD,QpeW<?*9+;Zm5.!oO0a"OgC>%T<K5;Zm8o"9\hPquZ:b!PJU:"9O5Z!W3(&X'bu*MZSP8"fl#6%Jp3[oEBkTXD\4B;Zm4)6l#g5"9ZhJ"27\:DGpZ@";>#C*$bYl]3>\#;Zm4(;Zm4V!MfeC"9_g0!R(WKErjbng]RY2"AEk;A9.e4ErkV1^B=[U":DdBg]>.m^B=Z?gB#e)!!1SfK]<9l_#`$dUB/jFPQAu2U]JsG?jG-]!L*f;!N$@n"9\blZNB#_!L+jGljU7+!P;PH$mZ+sKW>TqXTnCu#G`%7>\jIp%-.WR#4)IZg]\4Q>7=aE,XVUE"C(tl"4pHS[Sm;36ir)G"9Y]*!UiqizWX/Y*"9\e+Wr^:?2?DGh;Zm4;g_7%+liFg;;Zm4936M>Q,Rb;:*'>JL"@OL<"=-\mo-dN?$kb*k4<t%T6mMmT,Y]fm+B&CGE'Nps2$>H]9e6DM;Zm4KV(;`L"=sZV%''Lg,Rb;:*'>JL"@OL<"@lAn,Z[hHUBDG;'K-FQ-;t$M2I@$];Zm4;!!!!X"onW'"9PTd*%4_g'Ef9V*#p4,,U=W<U]`OX!OY#s"9]g2!!!L-z!ij6\aAW3E;Zm4*E(^<V^aoUVH)i1k,QX,D!O;h2"9H.D!OMu3"9H1=!W)o)]E\7@?j"jY!NZC(!T\/%Lf4EZ)$Co\8d$+:$Guul%EpAB1iNK]E"\WC;Zm4cS/A=C%,<uK"BYe3KED>[!K7-^#IJSoPX6nL!P8I8"9G$3!Mp(W,QnV<!K7&pErhL.lNF"g!M"NW!UL<G":=](PQAN%`!(ep!K8?0%)`1*%J0\*!L+&#!TX9E!e_*.":4'54ECOfE!P,#o)o)a!Mj[.+T[f1PQ?^G!K:Lh!K7b_RfSHJ_#]K'K)po3PQ?FA>QKcaRpZ?IDZi`8"9\b$"9]35_us[N"9GP(=9JZ;"9Gk4"9\b=!TX=c#O;E/!PB(R'4:k<!W)o)j9;kt?iu;f!PATBUL4,O_uZqAj8l+c;Zm4(;Zm4'"9\as!!$q9z!ih^t&5r]70Gaj3=Ao>*";q=V*,m,*E!Q7CE$GK2M?FD?CXX7(1^k!Z'MKbT"B6WL"=-](PR^Up%hbZN"9]"K"9\jC!"8n6zWmi'i;Zm4)"FpT)#P:UkOAc8b@%.9$'I4Z;!KN(B\5NM5;Zm4(!Q5(r"9_g0!UKmk",d3H`!!DS?jGuu!Q5,IZo_YOV?Xs>"9Iii!PhV:+B&CGEri'>BT!!u"9GTCU]J45;Zm4("9HFNbQJ&N"9GP(]`\AK!PAO9b?tJ%qZ4nG#KpKU!S[Xn_umVZ?jGuu!Q5)@MdQdJ"9Gk6"9Ik-!n^ES!Mqm]9`u^E,Qo)T;Zm4s;Zm5B8d$\'L9h">"l+%t$A8`X"9_+<"9HSB!Ls5p"BYeKEri'>$N'pXXF(Z(bRUEL$g\$*!P\a?!Mfal]1W1#!Mg3I"9\b61jDq%/6!kt1^$]=Fp&Zc#-1cET2PjqliaBjS,p):FHZh;"9a*R"9_h*"9^ne_u]3,"BYd-"1nU#`!-$GgL*YTU]Ih'liEsk;Zm4(;Zm4E,Qo*9,Qoqt;EQL0UbRK)!Mf\r!MiVO!Mfb4!Ls1[!Mfa\?j4/agggYZX9#1';Zm4("9\dl!!/EbzWmMdd;Zm4)"9\gg#fKhDN("]X!PAOIX98R)!PJU:!sA`0!OMm_g]U^^?iu;f!NZC@_dENBqZ4>3#)cji"-WbmU]Zfggi!;r;Zm4("<7KQ'EeH],U<Z.Rp-:PS1GWa,QoY!"9\iZ":P=:9QU@>"9_g0"FP9<4ECOV#MTOVe,bLtHjJa;!h9:Ug]\1X!JCRZ!JCS!KHbl7KE?r1"9Gq3Lf4EZ"9Gk2"9\j0"9I9[!NQ76MZL0fgcJmJ?ig-*qZ4>k"S6"%"3U_PU]HZeV?E[q"9I9Y!M33m8dX9d"9\aY"9G/o>]Tq!E)D5j"9\aa!JCKgLf4EZ"9Gk1!OMu3gL(,iUB._("P[;c#-7j$!Sd^Q?W.(1Y>YQ,;Zm4(;Zm4E$i:&K"9FI#irgNQ!U"iZ;i:jMHi_'2P]R+^,><IcbWKZKS,oJs;Zm4(;Zm45;Zm47"9\al"9H89FE7J9E#58PMZa3J!L.O(E!Gn:,Qn.<!JCKhO&H/a!!!!"*<6'>"9PUQ!VfRrW)Eg%;Zm4*;Zm4'"9\d^"9ZG<!n^ES(X*EN"<FjL!K7*`"BYe;ErhL.S.C7"dfHTP)2eV1"9G<;"<df1"I(/&dfG[5_#]dGgB!N>PQ?^IA-%nq94.kNDZgUK"9\b$'Kd^@*&7%hbX<]Zo32n6/-H!24<uIPKFHp=S14pUPQo&/!P<4Q!pgHY"::k-/.PS]/-L;&1\4fbgKP(C;Zm59;Zm5AC(rcG!i,np6mN)o!P\a?;Zm4c"9Gl*]EA8K"BYd-Wr^-A!OMt1!OH0<!ODgF]EX!r?if!_!NZFQ!N$-e"9\bd"=-00'J'A)1]cW@O3:`9/d):X"9H.f!OMu3"9H1=#0R%S]E7\4?j2Gh!NZI"!N#ts"9\bd"9Gu1!TX=c=9JZ;])gsq#E)sl!M]\.X95M2V?-Sq"9IQaZqs[(!PJU:!sA`0!PAHo"9_g0!NQ7>b5pZ,"hS.G!W)o9ZiQY(Rp\kidfI)^#D6Cd"H3A_!TX9Yf2DeT[0.`U"=u))!!!-Zz!ihUm+B&CGP?SGPHNYU$#GVD)"9]EX"9^DW#.t4?!P];,"<7W9*$bY)/-GcR#4l%=%T<K5,U<L,">p<-zPm79h"9\e+(VC#P[!WXR;Zm4E)$CoZ>8/=c/-H"6"=sZr*&Id",^Z:j"9a&S$j!X:!!!u>*rl9@"9PUe"2Ih<`$>I*49g`LX9ZCL"UjZ!"=+An"9_+<"9\-l"Mdq=J5ZRR*:tK[bRqJk"BYd-Wr^]Q!Rq5Q_dENBMZM$)"Nt0W"ge<C!V?Di!)j"'<ZD4?"9\hM>QVE6"9H1="BYe;ErhL.S-/kW!OQnKEri'>g]b?,S,pA5!Mfi!gB9W[%ubH44i7<%"9GlK"A8ck+U=57"RHV_jED%!PRi]Y&+g\>quMDe!L+r9"fr'l#`JeZ#J:*0N!ZipG6s387_8niP[Xo_PQ@id"N4pR"[iNq$_%[F!Pnf$"j6q2PQ@"R!S_,c<!Sn#!OQbJ5#VReoE,4!"9HFA"9\b=!NQ7N"9H^L!V?Ls$Xa-r"mZ35!Q5XZRpZ9oqZ51K"g_S;!W)o9e-30d?idS7!R(b[]3k[:MZM$+CZAe-"2k5Q!V?DiJ5ZRR;Zm4(;Zm5B)$DL8*!)-("9F-Uo/9MM**bH,X'5uhS2:pT"<8Zfirh1a,Wp$Y,X`m\,Qq"%K*5(/**`sSW)Eg%;Zm4(;Zm51!R(S)bQM#N?j3;+!R(YHRpZ;e"9H.:"9J.5!N/j!:/_8uE"IX)>:_TN$p4TT'P*tC49:s7">)G5%T<K5UK\-pHNZ09;Zm4+?GcmU/2S>cN!&r]qcaaDKEM=+"@#fd!nL9QzK-gQu"9\e,39r7s,Rb<-!JD^$N$JNo;Zm4(bQtQm&$/MFpeq:u;Zm4)^a'&%$`%kFoQLCjbRN&)F@:Tc#Lkqb!iue-":;^k;ufi"">CVp!oQu["D\,C,Qn=)!g<aD"9]EX"9\^'"9`[B"9["L!iuJ,=9J\Yo)bur#4#Xt!W)qOX9?.C?iu;g!iuU\X'c$fb6!>4"H-XjDZg+5"9\e-Fp!7n#4#<+Qr=+j+"P51"9`OG!e`I1"9_g0!NQ9\!sA`0!iuI)RpZ?1qZ;]X!h3Qu!J:H,oEFPgXD\4B;Zm4)"@N9P9EYJ949P\]/2SUT!P;PEE#?1iWrr\"N*J=KHnqH'`!O(e%\s70!K%#'VG*1Q"AC]S!m":C6t%o'G#JMHF<gu'eIJBC,W'lL"9_\("9_7oZN8]Wg_*RRZj4MM"iPTl#L!@qX=Rn3$f!oR#)j"E1^VY^"Df=d".3!iG7V%`,Qq'VdKEeh"Ct1,"9^8$KE88T"BYd.X9/S.])o&8!Ma$)?onFC!VC'S!N#qB"9\e-"9H89!J")O=9J\Y!fR6b"9\b+!iuJ,?lK0K!fRBUo3_UrMZSP:!qTe'DZg+5"9\e-quVmW!PJU:"9O5Z!W3(&!OH0,?m>`+!e^frK4"o\liH_ZX9#1%;Zm4)"9\a[U]HQU"BYd-Erjbn!SdfGgB9W[j8k)BJXZcC!UOb++T^@$0@LBK!M0>I"9\b\!Rq.;$HrP+WsdF$@L\PW!TX:2]Oq8pN!fIh#,DD/!Rr^u!Rq.d!Mfe?!Rq.7"bQiOPR"6slu*"-;Zm4(<%J+-";Cu:">j('">!e'"@QcG"9`Nd"9^Y^!!<1!zWo"it;Zm4)"9\bP!PAD2"9H1==9JZC!sA`0!PAI"lX0bjWr_Pj"m]Os"3U_`]E,?HRp]G$])fhP"05f6",m8f!UKiaJ5ZRR=9N.8!sA`0PQV#G"B9FCN,o#i)N+_!"9G<;S,pA-FNXdj"9G<;XDh[m'I7c$#b(jZPQ1`KPRX)_PQAT$N!$ZmPQ@!L!o%5dX9P_5XD\4I;Zm4(;Zm4O"9\dV"9`=8ciVQm]2fUI;Zm4-"<7L,gB9>Y'Kg=r,X`m\"9F*2]`\AK!Q5*A]ED=>?j3;+!Q5,9o3_WXj8lUmliEsg;Zm4(;Zm59SI<(1N!*f!PRJf?oG6HgquNo&oE9gNbVX,B63?K^#1O1%KEVmV,Qo(l?%W8:"9^i+"M=_5,X`m\"9_UZ!Ou&2dp!5;S2;cJoF0LUHpX#)PQ]2E&+g#-%T<K5liR@n"9HFA!UKqkRp\s[9*)s6_u\=p?jH9(!ON'C!UO_-&5r]7)3c$""<Y9V!fp7_";q=n>TX*<;Zm4;"9\bn*!)C)">hA,"9F0<6mMmL"B%'%a&<*D"9H.9_up+S"BYd-"02I8!Q8b]K4"o4Mug9kliEso;Zm4(!!!)Oz!iigN?rI12";q=^>7:Y9"<9GVqZJGq">k&u4E(N%+Ue2NPRXE>S.nHt!M(JEPUm&m%*U[=%ZCJU":gA@$j!X:\5NM5;Zm4(KHBIc%J0oG=9JZ+!OMt4X98R)?ig-*!OMm^gL(8=b5n[F#(p:gDZg*2"9\bT"B9VE"AAr#"9\b=Huf=AErh4&gB7P9!L.P8^B=\`"9FG^P]1HFKEfX$]*'8X!!.b$KTcFi_#]2i9*'\HKE7<2?mAVO"@NKY"9F`^":e?5":.p/Uh3O.!PJU:"9GS,"9\j0e,e&$?ioWp!Mfac]3k[:qZ3Js!fLFe!qQGoS-R5F!N&Nk"9\bT!!0N,zWfmMb;Zm4)S-ANre,bgOZ31:5"9],6":P9/'EeOV'EeOZ"9\jB-ik)^zWqm_9;Zm4)"9\pb"9sZ\"7T4l]`\AC!PAO9ZijJ6?ig-*!PE4.o3_[D_Z@DA"P[;bVCVbL"9IQa"SbmukYhTe,Qp41MZe\a1jf=a$hOjt"9\i21rCtF9I(655g*@?"<fl17oKNnLf4EZ-F3gX"9G$3!PhV:";q>!>6N_4ZNL<@">k'!/65[P*(5)U49SPE"8c::;$_hC#5ehh"gf`f#)!,tr)VQi"U+H+6nAZ29LJoO<ngge"FC86E#FQ:,Qoq\;Zm4c"9\b0]E+?t"BYd-j9#Mf])gsn"nQ+(!M]\.X9IWlV?=a;"9IQa!Q\1Bj9#Mf"9H.9!PAP;K4"f)b5pZ0#_QMq"LA-AX9/!$V?kZP"9IQa":.p/!O,K*!Lu-=%D2_U!LuR,b5n+5_#^&p_Z?8.!L.[.UMKt$"fl#4Ui-B@;Zm4("9\b7"9QA;diMEj1gGJ7Qr=+jKG6NL,QZp+9LL-/!jc)>!LZV4"?Zn<"9\jS1]d)ERn*RP;Zm4*"?Z^Vdf]f#">k(,"BJG(!TX=c=9JZ;b5o6Y#P2=-$_ma`j9P9a?j4^S!PANhZX<pjX9#C*j8l+Z;Zm4("9\b/"<81U/3Esn9LL-/5g*@?LJn<Y=9NF@X)nIIS-/rqbZo2i!K>J8"9G<;S,pA-qZ32f!Lt>j[K2n3"9\i.#Q,'1!ML.5"9\kg"9Pc*S8];!;Zm4(;Zm4g"9\bf]E.'q"BYd-"1nTp!PAeJ$Xa*q".K>(X9ZXNjDP/%;Zm4(!NlIS!Sg9MVGdU#!!!!"*rl9@"9PUW"P?WU=9JZK!Rq5T"9\b+!V?Hs#0R%koE:Xk?j""A!Rq7ARpZ9oWr^EI]JEpuV@B=%"9J,q"5m)\9mi]m]FVqK%.n`L%J0k+lmth[%u`[V#4rFb/-GMpbQLg#"BYd-?m>]r!R(\Q#K'qbDZg*R"9\bt"9O*P!L*Zh"BYeCErhd6U]^^o!L.X+,b#7Ur!*(<Hmur=!TX9glidNf!Mfi"MZa/+!N^67+T\)9S6Ypo!Ls,j!Lt#(!Ls2,!L*bW!Ls1T?j*NH"C))i"9GlJ"9;@'`"#]K!PJU:"9H^L!Q5+CRpZ9olN,33".N[%"mZ35]E4R1V?=I3"9J,q!No?(oE,4!"9HFAbQIs["BYd-",d3P`!,1/?ig-*!R(`-K4"r%j8lmooDtfu;Zm4(1cDC*"<;4j"=uqd"9_CD"9_7oZiR('V]Di>";fPg"<UPF!JaSVL/S3X,Qp41,QoA<,Qnf<;Zm4c,QoAn<?*Ph,Qoq\;Zm4S>7;3I"=,e(";E[<MZc-f6ik#I1'*=b;D]q0)$DJn!KSc7"Dd$g!N/j!zR0Wcm"9\e+'KddB/-XL,"9a&S*,lOc/0k?<0N/)W!)j"'";q=fj'*c[*Adm"!X(=_;Zm4+2$>H?Zl6jcg]=2a!#u"Jz!iqtAW)Eg%,QnM\GP_M*"9_,3"9uqG!m":C=9J\a!sA`0!ji$9_dEMOWre4ir)6u;Zu6'J;Zm4)"9]"O"9d(M!U*Gb=9J\aqZ;]Z&$oXE#3u>L!W6_@ZiR$D;Zm4)!fR;eN!*5c?j<Y5!fR/L_dE\LKE:uSZiR$);Zm4)!gEgAN!'0^"BYd.!W)q_!fVJ6gL(3>"9JE("9PrK!r,[s]`\AC!PAO9"9_g0A9.e<Erkn9^B=[Uo)\1YScS1"]*"8uScS0ZlN->Q!!2Fl8XfbI!Png'8qR02!L*Vl!PAI"RpZK%!NZ<Z!VC:5YYtZ-#)"N/"?]Y2"AE&G"9`6\N!.4#"BYd.]`\Ci!e^[Wb?tJ%b6!Va#D6DUDZg+="9\e5"9k/k"E%-@!NQ9d!sA`0!fR2fPQY(k?ig-+!ji,`K4"en_ZGc#!n1N]VCVcG"9Pq2KP"-c!PJU;!sA`0!fR2fZijJ6?j""B!ebNnX'c+kqZ;Fi=mKGr"N(;"r!)IpZu6'J;Zm4)"@N9p%"&)qKE6Z-,Qp41"AAiT"9F`4!r,[s^/G.;!<a);",%p&"9_,2"AAiJ"+X;Q9N<o34<t&',RC2F;Zm4K!Pebl"C"npN)3FU"BYd.Zi^F6])o>@!Ma$)"KMT_r!(&HV?ECi"9Pq2!Oku1A0_9l,QnVT,Qor?;Zm5F;Zm50PQV'N"9GP)=9J\aqZ;ubN#Q.*?tu_D!W4akZiR%';Zm4)"9\ae>QWe]S2;Jo6mMm;/0k@7-;t$M*Rk.ddi8D/>QNFX;Zm4k,QqWf"DeJD"EZ1?"FNT_"9^h4"9^qf"9HkJ!L?Xe/lMlU"FC8N!O;h2;Zm43,QoYO!Mfad"9HLF<)l%s1aE3'iWK_?"9]tNL:_(s9M\=_>U0FtA0_:/Ca9-?F<guWHmAhW3)]q_!MrHm%,;&WXEP)ce-51H"B9OI!JLsS$H*.eX9A]Z<%".;"9_[:"9Q>:!r#Ur=9J\ab6!V*",gOk!p]oHr'0LTV?uSi"9Pq2!j>N*f2DeT#mCA5zX7J.J;Zm4)"9\ei"9k`&,]Fs6E(5`g;Zm4[!qZet"9_g0".TGr"nMhd!JlqI?u#i9!osI<".X94cr1&MKE9R(!L+5u!Ls2GX9"7n)?JUo"9\bT"9bZ%$Fj";"D\,C^f(@=;Zm4/"1nZf1gC(V(/k>=!M!+?;Zm5."9\h*lN?'D>QL3V"9\bL":Ll$S8^O$;Zm4("9\hBX9\N!R:>age,e&")?HW7!Rq/"\H.E5"9]tN"9Y#i"9`KC"gCo.)%6PA!NZ=6Zr$k2$j4uclj&1nD@4Sl%BKTBg]\1`/CO_*"9GlK]PpZY(?5Mu^]DAm!K%!]#J1#DbZk17;Zm4("9\b'"9FT_#KTgH"1WW?"9H_Or*E;)#8,Gl^]BX8">j?i#+/<l";q=^]3>[h>7<%`"9\b;ci_'^\cL"U"@)2Q$K+hc!R(W'":)P>6uQ!,"=tf$"kZ`V$.rLp":4p1!N8p"/lMlU$`#uH!JCjoj8l([bRCQR#eY?k",mTZU]Kh34q69J",%)Ae11c_"9FGl"9J-?e,d?9"9I!Q"9G;D!PVJ8\/,9Y;Zm4,!qZPS"9_g0".TGr"nMhdoE(Li?ie^X!osI,".X94hbsX\"9Gk1"9I*j#l%=$Lf4EZ!sA`1!qZSboE88!?j+p[".TGQZX<g?]*"RCK&^5DgB.!J"05f4#M]CA".TChLJn<Y;Zm4)!qZMJ"9_g0".TGr",d8OoGWp$!K<3D!K<4MDZg.&"9\gs49kRZ#/D#X:K%B!!R(W-"9`L@lN7&a&cmY4,QoA$KEM=?"9]kK!Q\1BE!WKIHfILV*$bR*"9_Ub1iP4F\5NM5;Zm4)">g:l">!e'*&M1O"?\eH"9^P,"9[gem!)G3!PJU;!sA`0!qZSb"9_g0!NQ;"UB:&jABS?^!W)rbS,r4h?j2Gj".TD`o3_UrUB:?(&+a01",d8OoH2gq?j;Mj!ot6B!N$=E"9\gs!JGo#"=,5qmo'A%!sA`/!qZSbS-2ps?j4^U!q^B"RpZB2!osB>!N#t;"9\gsHihVmOlJtB;Zm4("=+#H49<qWU]I>D"9G;!X9"8*S0S4<"9Gk1]E*[2PU$A4;Zm4(".0.]"hRelcr1&M1]s<O";:gi!M33mS-&ls"9S2t".TKr]3kfcWrhnq#-2,cDZg.&"9\gs])dsk1gEf[O&H/a!OmFY"9`L2>QM!+"=+[,"QiVc5Z7dg=9J]t!rN0("9\b+".TGr"1nZ*quQ+k?iul"!qZN:b?tFi"9RWc"9Y04!QJ%@=9J]t!rN0(qud&$?ig-+!q\S7dpPe#"9RX2"9Y04"Rf7l=9J\a!sA`0]EA;C!M"34Lc<3S"9QLB4ECSJE!;F._ZU%j!o.`.!mD,']EA@`lNA@4_#h8bgBR9NIKSY$9A9N\!PniMC9%EK!L*Ym!fR2nqd=H6liI"gg]=8Q;Zm4)4D0iX"<7g_";FNT"9_[L"9lP="d`-j<\sm8"9\h="9sW["I;sh!V-Y(df]]`"CuI&CiDmsE%/*r"9dk/"CqOj#)6%ZE"\oKiZeR_"=uY9$(OC'`(YP'"UrT\#+#^N49:<BDZg)o7e6YN$m#GF$023<ljEZ7Ifc,A!K7&d1d1u*!K78:S-o0E]HdU\"9F/VPQA]JbTm;l;Zm4("9\bf"9\jC"9djc!U`khz]cI.R"9\e+C]f2d"9_g0!L*ZhErhd6Uef_rb5naHKW>5r!N^5@+T\)9lqQ4;!Ls,j!M!`=!Ls2,!L*Z/!Ls1T?j>Y-&$,m)!NZ\4:f@K"liR@n!R(ZI_up+A"BYd-]`\AK!PAO9]3kkr])h7#!i'-*!W)oA_uc]A?j>Wl!OMsH!N#ni"9\bl"9H;:"CG(1"9;@'!NQ7F"9HFD"9\j0]E.@$!PJU:b5ofi"H-Xi"lfWrlit@8?ioWp!Q52[ZkHglV?,`Y"9IiioF=e&";q=E&i=ca,QoA$!JD.TZqLLoG6Ghh%/^1V<.>Cb4pAkE%($Q;]IO8H9f)tYCpO6q"=u*C">hq\"9\ib$ES/K!Q#JV"9]e4!!1)<zWmM^b;Zm4)F9D]-"9GTF"Di.,!P\`<"9].o*!5n6"9Ilm_cmNp#GW8+":*^F'Q=)bi)9a]FCi&c_fPpr!PrjcC^$SU7!&HoK4"rUDZhm#"9\aaU][8g"BYd-#5\Fs!Mg*2MdQbddfH6G"-[*sDZg**"9\bL"9G/o6u2r."9_g0!M"4Q4EGlQE!;F.P6;9#!K:tn"<i-qE,:F8$A8PhN-oBXZjaSJ"3^oY!Pfr`96>8t!JjC<"9GrQ5Z7dg=9JZ#!sA`0!R(Sgj'Vob>61N'PQ[ahV@C`M"9H^I"BJG(!O#E)7oKNn=Ao>*>]XuiB%%"7%K(U$Zipj8^B=ZK"9`fI"fspeKM3Df;Zm4<"BPVY"9`g=";FX1"=,6<X98Y`"9GP(=9JZ#K)qbN"Og`_!W)o!U]f.SdpOC$"9F_h"9H_bU^g<+"BYd-"OdCIU]cT`?jH9(!L*i\!N$-u"9\bL"9]!/"9^Y^!!"WMz!j's2i)9a];Zm4."9\b8KEJ:X"BYd/"3Ue"X>Tl_?iu;h",':qX'c$n"9S3:"9Y`D!n^ES=9J_Z",m?cN!'0^?j":KKE6mm?j*5,!qZQ;"0?DDkYhTe'EP!1U]a%h"9`H?&[51:,Qn.T"lo]K]QXV9g]Z+7!K;L7"N1>RbRLX;.gE']!Q50&"FMHt''N6s=9J_Z!sA`0"0;U+_dEN:P66I@"05f6DZg.6"9\h."9ZG<$-6$J$1L0k"9`6n9F09L!P;PE%AX0?!P8B:PS?3S"?^K$"AEVW"9`flX9F\aJdL3:Mh?BX&cmXd,Qqol"9\ai!Lt92'1`4uW)Eg%;Zm4*"9\pr"E[C;Hi]`_!MgtDKN09K;Zm4("9]:WN!'Vh"9GP*X9/S."9X;Z"0;W-lX0b"qZDdd.JmKR?&Jf<oIIgeXD\4C;Zm4*o)oQE!n;0bTMksr"9I!U!Sh32gH6_a2?of];Zm56"9]%h!g!HSE(5`g"9\aq":*"H"0;S-=9J_Z",m?cqud&$!PJU;b6+gK"1qqE?m>c4!rN/4]3kl-dfY7*1ZMkODZg.6"9\h.KFZX5"BYd/]`\E7!rN0%RpZEcgB3*r#Ld&qDZg.6"9\h.":UAj!ROaJ]`\D,!i,r""9_g01ii`JE,23O"9\e]!n77_8#l^@!n77<[K=rL"9\i.BF_7Fj&Q2N;Zm4);Zm51"9\d^"9a0P":C5hS8^?L;Zm4(;Zm4f"9\b?>RI]6"9]SF"9G?0Qr=+jk[i3D"CsD!!qoOq!Ls2C":*+N$0Y:j8d#=e"9\eUU^Xb3o32n0N""2?!L.d4"I'&]"9GTI!JLW_$]GLI!mCgQUfABK"9G;!!N^)_"EYml!Oku1HmAhO"B'%]r_iq&;Zm4)1!9iQ!N?Cl,Qoq4,Qng/"=sS,"9FH,$+Nn:=9J_Z!sA`0"0;U+P@+L)",$]:_dEk1"9S4&"9Y`D!JjYWY#>H+"9X;Z"9\j0X95O+?idS9",$]UUL4,g"9S3S"9Y`D"K#*#[X8,T"9\i.":M/,"GftZ!n8UpUB8pF_#i+]MZVB/PQI@fU]T$H?n(sS"9Og'"9Rq."e\cspeq:uoJ#k<g^Ff)G7O6R!pg)D!RuU@$+'`/liN,0.g<!`!L*i5!Seq',Qn.L";Cmt"9Ij7"Sbmu8d#0U"9\eU"9\'j";Xo="L_53Ershob5mQD!o.`XDukk"o)o-U!pjk1!Pfr`"9\eU"9OBX!JjYW`$>I""9F/VS,phZe0G.t"9FG^Hi`"J!TYL/W)Eg%r!hE`#Lk:7>7:PF%HIQ%S:!)e]Edd($etmer_iq&"9X;Y"9\j0X95O+lX1Y6b6*Cu!o%)`DZg.6"9\h.P6@IUoDuT[$LA0%b]a2[U]J+/!R-$#4q@L4"G@5sUalVM"9G;,S,q+bga!"'"9GS)KE:-Zlm)]7;Zm4(0rkH0!P/<-,Qqol!L*Vl!PBZ\s&0%';Zm4(g]R\u!N^>DErtD*^B=[Ue,nD+L]Z?5LB>s+[K=q\"9\i."9dX]"0;S-]`\E7N!'7a"9GP*=9J_ZP61Xb"G:(e!p]riN!+c@?ig-,",$f0j'Yg?!qZMF!N$+7"9\h."9FQ^"g:i-Vc*^$;Zm4-"9X;W!rN1'"9H1=Wrn:`",m?`MdQS_qZ?\$?&N(k4Ndh[oI&*qXD\4C;Zm4*1e\"UU]I8kS0S4<"9GS)"9F0$Q;[p^"9H.9_uZqbA0_9Y,Qn.l"9\b4"9_7o]E4BtoHXP?"9G"n49>@*KE6f1"9Gk2<!&"(!Q7th,Qn.d!R(SW!LtD<r_iq&":iWXg]=2rPU$A4L+2^)"CsCl!V]LqWrn:`"9\i.KEJ:X"BYd/!ODm0N,Yh*?jDkt",(WoP@+U\"9S43"9Y`D#0'RE>8.+V!OMmf!R)el,Qn.\!Q5#g"9a&SS8^:U;Zm4(43I^)S6Q>t;Zm4(",$d7qug+)!PJU;qZ?Zu-IZ?'!p]rAoEOVhV@LNG"9Y_+#6%O(,Qn.T";Cn/9EG&:!PDDhT2Pjq!K;7."9\b6#*r0jPU$B",Qq'I"<7H4>QLWG!N[OLQr=+j;Zm4(!n7?$gB9W[!o.MqE)Fd]e-#j6"9]kL#a\Hm;[&[B!ojNHS6Q6s;Zm4($j!.`ZiRdC]3>[RU]Ih'"2n%=.LZX=#daj'!P<5["_8)?"9\aq"9jib$,9CAE&PlB"9\eU,R1t]!OO*TCfMHSA0_:o1aE3GhGXO[;Zm4-"9\u'lNrnV#PJ1K"9`6n+N#R*A2XMgk>MKd"9F/Y!K:h?P]S/RHmAgq>7:OcN!'0n"9G>">7:Os]*&/H!M"+Nr_iq&;Zm4,"9\b7U]p`r6X(6*C&t+5;Zm4+"9\c)!==KZ!!!!2Qj<Zl"9\e+#..3*m!0)B>7<Ur"=u4\Rfik@,U@=m"=tf$,UcRo/-Hgn"8c:B1aE2<(/k>=02huV">p<5zLg^8`"9\e0Zkg/MYTDj?"PeA*PVWN^HlKC."C)?JF9.=G!L+i4S0S5R;Zm4(51:e0$k`WSbTm<J,Qo(g,Qn1u!k\QL,Qn1];Zm4[!PAi^",nK.,Qn1m!fR5G".UV>peq:u"9I:(j8m1E1aE2),Qn/7"9\bL":0NV#)!']=9Jf_]*<okESFk'8=Ke<b[8h,KPpts;Zm4-"9]XIga)Af'I3e`%bqPqljM<e`.(_g$cE_]"oN1#]IO;I"9ZRG!Q5*u!OO*T,Qn.l!Rq.7gb^8ZS0S4<"9IQaliFaEUa-'D"9J,q"9GSL%Cf=>bTm<Z,Qq'K,]j.<liQNR1aE2*Lf4EZ"9RWgKEJk4`$>He^e=k5KEHl.1aE2+cr1&M"9S2t_ZKaS&d*e$"9I9d"9Xl6"-?Falm)]j"9PA$liZl*r$2CH;Zm4*!ON`s!JD^$DZg**8&GA?$k`TZn5BGmUeelGoF)?6Zm5bT"9H^J1]k<8!lQ>ecr1&M"9O5[S-5W5X<[oN"9XkkU]e%M]HdU]"9Romg]YP@bTm;l;Zm4+!n84:",%p&G=2_$!W3JpN.2?0X9%qq$D]ig"QTiIC^L"i"-b&6,Qn1=!mCb:"/I1Fgf5=n"9R?["9^P,1`_*F",%p&N$JNG"9RWd"9Xl6%>[pc!Pg5h,Qq(GDZj$5Cil^g"C)?J"=/@?1]`7T!K89,PU$AO;Zm4("l'Z^e-&kV!PJU>ZN\h]P*98Sis"3=&@5bmDZg6f"9\p^r">AqS0S4="9S2tZid*LX<[oM;Zm4*KEN0k"9G>$",p1=">gN""9Y/>"mAkfpeq:u"9m9cg]RYk"BYd1KED>["lodjj9,LaP@.#e>6WN*KRT+m?iu;k"l),Mqd<-^"9m!n"9sNt(4]<d1aE3/!MrHm!J$pJ*"3HZ,\//'9PbsW"EYml!madJ,Qn1u!o*hK!Seq',Qn20!pfuY!W42GDZg-;"9\e51_\eG!mFXa,Qn1m!n7:i">hA,!MokAe1Tba":PnE!V]Lq,Qn2@!rN,T!otU0V#oudD;ta"$k`X6pJV1t"9J,squNlEZm5bT"9I!QgB$YZ&cqV;;Zm43&VCn8$k`Wslm)]R"9Q4;1]m:p!rO;HmSa5k;Zm4+&$uAG",%p&,Qn/G!h9@O"-b&6UfCZI"9PA#X9+>+PU$A5"9Pq3]E.(=lm)]8"9QLB!mEJH!e_g%n5BGm"9H.SA-ADJ"2n1b,Qn4f"3^kC"2#l^,Qn5!`*0c09FMO9"4SS!ga!"Z;Zm4*1fP4""FPSs!JE9T"Df=d".3!i";q=N!MpJ5U`9L?"=+*N<1>^_,Rb;J1e].t/6!kt**a`l1h7j74?QUh6mO#\9Je!t"=tf$$a<P4,Qn.L">g/OZiU(MKHp[$"9HFB*!2'E!gFr5,Qn.\4B)BPe,e'!]HdU\;Zm4("9\akgBI%E!!T0+3n"8.!Pnr8EU*e(!L*`Z"S;kngL(&7"9dd)"9l_^"7B(jV#n:4.%:>?$k`W[e0G/:"9Q4;"9R?c_u[Y!"9QLC"9Q4]!Mok9bS,U3`!d7[ga!"(,Qoq*"<7L(49Fjp!q[`@cVjrL<?uAa",$c0!q[`@,Qn4."9XlFZNC%M&d*e^,Qo(q!SddA".UV>OAc8b"9FG^!L-h7S7ElJF<gtiN,JiH;Zm4("FLH1*!<Pn"2#l^`$>IB,Qr2kA-<"Y!qZN/,Qn2@;Zm4[j9,gO"9GP,=9Jf_ZN]CmNN6FlK*C$29p8t"DZg6f"9\p^`"D33Ua-'D"9Oei1]sg)"10<VL/S3X"9HFCgB#N:&cpKh"9F/abQ6cMlm)]7;Zm4(".TLLUbj>"PU$A6"9Y.rlN=5,&d,KL,Qoq4!h9A2"3`"nkYhTe"9e>uU]^g&!K;('Es8WJ:V-a/"9l/O>]U(]*DGJr"9\nH"hXlNE+/VH,Qn:h"fqa?!P\a??(2"nU]:RoUc4bHU]J:8oKM"5U]H\_MZiYUORljc"9dcd"9l_^`'@6(1aE2+,Qn4n"4RCR"2#l^mSa5k"9Y.pKES(rX<[oN"9XSc"9c(W&s-#p,Qn.\",$cP"0<aN,Qn/G"<7NN9EVpQ"2lGfbTm<r;Zm4*!pg?j".UV>Ua-(Z,QpdC*(0n1oE+Yblm)]8"9SK&FRq=7$k`X6,Qn.L!TX?9",nK.,Qn1e!K7,F".UV>Ua-(R"9F_h"9Y_N"P6QT,Qn/7!rN/M"5G.)j<OjZ"9S2tPQU7toHXP@"9X;Z"9\QI)urn?"GA$',Qn.t"0;Wa"I(/7,Qn2("9\jte-*3Y!PJU>"9mQ`"9\j0g]iE6?j6-*#)#F__dES)qZYJ<7DiL6-bBQ;bV6Y:KPpts;Zm4-"S;u&"9_g0"e5YtEs8?B"fqi#&*-]2N&jJX^B=ZK"9kk-U]J45UiiF9"f),%U]H+KU]J:8S.<.7U]H\`MZiYU-ECMWDZg4("9\nH"E[+3"FOH"!JFDtCc!C?"E\PbUE3>:&cn4Q,Qoq4"EX[?Mug"*Zm5bT,Qo(f"9\b<":(l("+X;QS0S5J,Qq'I/49N7"DhmS"9`6\*!)+!"0<aNZm5c2<?*Ol"-`nP">hA,#cLZ)]`\Mg"l'4]e-&kV?j))c"l()]MdU;+"9m"@"9sNt%bO\_S,n03PRJ0,X<[oN"9HFC"9Z"V4=F,2dmS*W$kc6->U0FlA0_:7n5BGm,Qo(o">g4n1]tZA".W@2s&0%'<?*Op"l'@D`-2`Fg]NK:!mH-&$iC(Ulj!)G.g3Kg"9R@8e-%TR"9G>#hGXO[,Qoq1!NZ=O%/_@R,Qn.T"k3S6!UM'7!mD).e.)%oIg=I5!JCLGj?<m7quif!#dc)_r$2Cb"9G;!"9O6%!Q\1BOAc8b!K,nG$k`X6,Qn.t"<7Ms"9XT.e4<L@Zm5bT<A[AN!V?Eb!UM'7,Qn/G!e^U0N&2d_e0G.u"9OegoE""uS8SN2;Zm4)!Ls:Q"-b&6%b(fDr!N@GIgMn\Ubi1D#kU:c"QT`N`".MOUa-'D"9Oei"9Y_NoDu`q"9S2s"9^P,"9Yf*".3!i,Qn.<!PAJm!gFr5`)T31;Zm4(">g1OX95OLZm5bT,Qr2k!lP2R"2lGfbTm<2,QrJs!TX@4"5G.),Qn.4>Qb/i"-`i%,Qn46"-`pF"9\b%"OC!L,Qn1-!gEc1!n;2m,Qn/'"9\e]"9IX`"isUF]E++pZj[QKbTm;m"9PA#*!4V8!o,%(,Qn.\!iuIa!ph08,Qn.$">g2PS-&U6KHp[%"9Oei>Q]p1!k_Mq,Qn1]"9\djliurXS0S4<"9H^Jg]F8sX<[oL;Zm4)!OMs\"GA$',Qn46!n7@3"I(/7,Qn.l"9\jt":O*c%_#@>O&H/a;Zm44!L*ekS2;JoN$JN,"9G;!!N^Ag"FMHt!WQ($=9Jf_dfnM0O8E;h]*6sj6gJ,ADZg6f"9\p^ZifMjS0S4>"9Z:=_ule\X<[oN"9ZjMe,tp\1aE2+V$"(-K;/PM&d,cI"9Z">"9Zjn#d@51j<OjJ"9IQbliQN!oHXP?,Qo@o"9\f(S-k9TN$JN.!KObo$k`Z,Ua-(R;Zm4*"@NC%X9R`2<=.Fk",m>@PVaWgKHp[&",m?blN@6b&d+AG"9XSk"9YGF$+Eh9Zm5bo,QoY#!o*mj"2lGf,Qn/?">g5)liY`_ga!"'"9O5Y"9[^1%]3/-,Qn1m"<7O)X97f7oHXP@"9Z:=/-Geq"GA$'`)S?^;Zm4*">gXm*!1d=!fSB-,Qn//"9\djS-5H_e0G.t"9YG&Zio/0ZrJp`;Zm4*"=+)1Hi_/2!R)el,Qn.$1e[r""9F`e"G]nY=9Jd!!Jg7L!NlLJ3h&dcUiZd9"f)D-"9\b6N_!(OUe1b!;Zm4,"9\j`j:0..e0G.u"9R?[Wrh@#&d%D<"9JE/>QXgK",%p&G#JMHE+5RF"9\n(%GY;h4DYQ3,]k:74FACW9MAG3<(%u7"?[q4#PM(!,Qn4V$1n>\]QXU^KE^EA"71L>#E/`N"6;R.`%(tD,Qoq,"/H%k"8jDIKHp\""9Z:>Zil=5PU$A4;Zm4+!lPH.!jj3U,Qn1m!n7:Igb^8ZS0S4="9RWc"9PYM$,9CA<?)$m#IFTG$)Dc-!Se!o]E>Nj4pq2i"l'@4ga`g""9ZRG]EC&:"9G>$"2mib"<7g_j9*mWga!"(;Zm4*"=+$2U]I8:G6HD#%]fiH!N^cu4q?Xa#cnN#1b/pOZm5c:,Qoq)"<7HT"9HFd$a*D2=9Jf_"9m9X"9\b=#)!']"1nbje.K<#?j)Ak"l'^%K4&!&"9m!i"9sNt$dMZRj<OjJ":Fc&1]m"h!q[`@QW""i.#S3<"9kT?%?=?iVc*^$"9m9fg]RYk"BYd1!o!n.g^0HX?n[EA"j@1O#)$mtpJV1t,Qoq/!o*mR"0<aN,Qn20!R(YQ"2#l^`$>I*;Zm4*j9,P@%E*K2)oNB]U`#+#e0G.t"9Y_-*!=tA"6:^1c;OiK!!!!$*<6'>"9PU=".3!i"BYe;!PJV@!L*]i"9F0s1ii\fE,2KW"9\b$!Ls2*!M!/J"9G"m!P])f2<,%NPQ1`KPW/I?PQAT$>R&p`!L*VL?j$"2#*]>hUi-Bh;Zm4("9\e!!PAn@ZijJ6!PJU:MZLHn"2eLL"eu+*]E?&Z?j$!$!NZBe!N$?c"9\bdU]K+Hlm)]C&%#"3U][,aKIRB6!RtWigaC!W"U*ll"?[4U%%IHI,^_?<"Uifo"=+34"=uY\4<-a7$G6L>!J:RJ!ON`W"9H1=Wr^-A!PAO9_us0F?ig-*!ON&`#(p;f!W)o9]EZPe?idS7!PAW[CL@@)DZg*B"9\bd">kR+$p4Y1*&$&N/-28'>8.+>"9\i("9H58"?06^!JXMUQW""i!!!!""onW'"9PTdS1%;=9,4f?"<7X<!W*!;'EQ#i,U<L4">p<-(/k>=zfd?b""9\e,":L;i%(K4=E%CM_"9\b\A-@]eqcaK),Qq?S>7>Ui"CrU,9On9Q"9\O*%%'rr=9J\a!sA`0!ji$9lX0n>MZSiP$1hO,DZg+="9\e5X9O2R"BYd-Erk&!P6Br/PQAN&dg`)]!UP1S"2k5I":Cq."<dg$g]<#=!SdYUErk>)"d9'O"9Ik.oPed0!TX@a!Sdf$!Jgd;#(Qa0!O`$a;Zm4+>Or*p&&])kF<gu_"FC8^-;t$M$D7On"9_\/":DY;!VfRrTMksr"9OMd!fR7a"oD[P!fI,=r!&?mZu6'J;Zm4)!gEh+N!'0^"BYd.]`\Ci!e^[WgL('Zb6!n1#D6CgLq<_I"-[*nVGmTo"9Pq2#gcKQ:K%B!qcca)!j$2?j9*%loI<N9KEg34ItMVL%($ASF9U.t"@HB%#bY*!Zi^F6"9OM`!ji)4dpN@&;Z_nkquXcDZu6'J;Zm4)",m>d!ME?o>\F;9;Zm5&"9\d]lNMf;!!1k_6]2!#!PnflXCD:dg]<W?RfTSkS5WeuoPXj5;Zm4()$F1EKB!(;#2F.u+B&CGE!,t?;Zm5&!q6H)o)YC];Zm4+<!%h_":!=U!l._;W)Eg%;Zm4.;Zm4N"@N="FDLu^CpR=S"FC8^qcca),Qo(h>7>Ui"9\l)"9u)/"9;@'!j>N*WreLg!fR6_PQY(k?ig-+!fR/\X'bu*P6-[D@d@D(DZg+="9\e5/-DMC!JD^$"N1PHj94gnIgu#Olm)Uj#in/M%u^XE9FLJC!L+i4!Pgf#,QqXg;Zm5&9On=:bQI`HK3M"T>7>TT"D!"79On9Q"9\O*"7T4lL/S3X>>/Q."?Ze`%!6;2A/U;0"9a&S!r#UrJ5ZRR"9ZsP"9I:MQ53C%UK1=q;Zm4,!fR0LKEPB[!PJU;!sA`0!e^W^b?tAJMZU6f"3Y'S#.jqqN!%72?j4FL!W6Aa!jlkKVc*^$!OQA<'Ee5:"Df=dFDrh$"FC8^?rI12=9J\a!sA`0!ji$9.prPP"5<m9r-GDOV?>TS"9Pq2"I;sh]`\Ci!fR6_KEPB[gL+4e_ZGc=#P2>/DZg+="9\e5;uuJeA7Qqg"9^Rbgi-3P;Zm4("9\dm"9]!/"9a``!NQ9d"9OMb!gEgio3_dGo)akG0Z.9/"/Gtq!ji!*fM_nU!sA`-!fR2fZijJ6?j""B!fRBEo3_cdKE;!tZiR$/;Zm4)!fR;lKEPB[!PJU;P6-C?#,>Q2#I=Jjr)r>nV@B=%"9Pq2"f>3$T2Pjq`_:1NF9CP(H_XdR"FC8^E-]V0;Zm5&Dpnlmr!X3KF<gtuHmAhO[o3D4Q3`*H"B8V0!WQ($HOIc&b6/$>"B9>VdjS,t>QU2n;Zm5&"CqS:MZa00"B9=@"9;@'"4'mK(q]pg"<,3R#)6%Z<`9,(93,"F%T<K5^Jb7<!!!!#*rl9@"9PV$"3=CDWr^]Q!R(ZI"9_g0!V?Hs?qUOM!V?T6j'W&6])g+Z8qULTDZg*R"9\bt49<N%6j+A1qZ5q$#aA!b<-tBEe56@%$j)q.X:'\2D?7BN%dYqA]EJATHNZ_E>9$$6"9\i(//T4&"9]*5"9Y#i"e\csfM_nU6kJYb"?[)*"<:Ad"9_sTbQF52"BYd-oE,4!o)\Ia43M"4"mZ35bWF!U?ie.G!PAK'!N$7#"9\bt"9Z/4b>(t=!L+RL?@rAK"9^8pbQ3f("BYd-oE,4!qZ4nA!pa4p"N(94bQcg0?inLP!PAH.!N$"t"9\btWuMsTH-9T0ibjAO"9^7V#.$Qn/-4ZVY#>H+!sA`-!R(T:oE88!?j,cr!R(`%ZX=$-"9H.="9J.5!JjYW(fLP?hGXO[;Zm4(oED$,*Q1;N=9JZK!sA`0!Q5$2"9H1=Wr^]Q!Q5*A.prL<?m>^%MZNH##30(n"3U_h]E-JhV@U<?"9J,q!M33mO&H/a2$?;K;Zm4+,QoqGNXSl\6pH;)6j+k?!P;PESl5ap,Qne_9gf+pqurTA!P;P<$lfG82iA-0!NcT[&'PQK6u37l%bqB7"dD,9`!$1;L$JjC/1b`@"@OL<!LH^fU]U`&=9O!P!NZD,_ZX4c!OQfG!M0Ds#+Pb]Uj!@A!J?:9XC;?lX:+(i"l*_k%J1%Po*"[hScPo*RfTSk!!002-]8#,!Pnf<"IfFn!L*V\]6jX\"/B6-Zu6(`;Zm4(;Zm4'>9$$@"=+*H$rfnG"=pNW6i^-g"O)2qE,`u';Zm4S!!!,@z!il8E^f(@=p]Ro,"=uG7"cuXcP?S`#ItM!6Ua,u]>7'p*%@dOdXEOg6ljo$\,]%r7r&t;FU]IP)!R*&(!P\a?@9d>R;Zm5&$+'ktr&k1A;Zm4)"9\n$li]RP"9GP(]`\Ak!TX@ag]U^^?j=LL!UKubUL42)9*+)We-;+EN,Jh";Zm4)Gm"6kCs)qa"<8D#"=,6<!JCS5"9_g0<-&)IE+FS(_up+R"C-!Kg`R[(^B=ZB"9GS)"<dfQ!OR7?!OMmDZiQ5O!OMh-ZiQ08ZiRuDKETI!ZiQBldfG+&!n1N]b\mW+;Zm4(FJAs=%a6JC2iClSR1$&PgcRCo"GBVQlm`]c%.m4'KR(aY"V6P!"9]1Pj9!t4"BYd-]`\Ak!SdeYX'bu*@fbWqe2ti]N,Jh";Zm4)!TX9["9_g0!fR3a"HrnG!TXo%gL(5LMuhE2Mufd`;Zm4)"9\bH!MhqY2iClS<"gNV;$;h_&&\S:"k5"9%(leGS9`:qoE@>a)I-5D3kJ?j"=+#YjB#7_"BYd-"H*<A!TY2-o3_g0quP:NMufd^;Zm4))E]i93kI4*"KVX7;Zm0_qZHqU">k&u4E+;QKQ&.=;Zm4,"9\c#"9^AV"9`pI1]`>0";_jW*.Cfh"9]SF"9G>E!K*o\"9^8p"9]iG"9Rab"Em]H"DC^:!Tm;`2@^V:;Zm4S!sA`[!Sda8"9H1==9JZcMZSh?"cHaj?kWS%!TXEB]3k`YUB0-R"J]?.!lG'"e-:h=V@BU-"9OM_gi$*o!PJU:"9IQd!Sdf[!omZm"PWt<e,mNqN,Jh";Zm4)"1JB11]`I:zOp1md"9\e+";E7_$lfBf!JQ_A'EOBW"<7H,$j!X:#4rS)";S:C!"Mp1zWn&9m;Zm4)"?Zh.Kp)WW!L+Q)"9aB?$qs&t"<*b6!U*Gb"FC8>,U<Kq!P\a?,QoA,,QnfL6lZN/!Rq6Me-&kV?j=dT!Rq;5]3k`IX9$6AquNYr;Zm4(*!>7%!JQ_A+U$j/*"o"L1dhA/9LL-/&u/YNRp-;#;Zm4A!sA`b!R(TB"9H1==9JZSMZN_Yr&\9g?ifj"qZ4oVe8&Fm?jE/%!Q5#.!N$*l"9\c'"9QA;";k&?"CG(1Uh3O.CB]qE"9]NobQ7VD!PJU:!Sde\e-#fQ"BYd-"1nU3bQQC&?jD;b!Sdh,b?tI2>62qMe,cm`]3liaX9$6CquNZ";Zm4(!sA`:"De+'S-/ss">k0#Ui9Oj":=]$"9G$)FE7JYE+tL=]*&/9!ONI?!PAr-U^j23"UKb_,Qn8:!Mfb3%AXHOS,o-,YQh00e-gp1Oo_?Ze,oOK,6QF$U]_+]">k0#XDi6U^B=Z?S,oDd@f`A+CuYPdS,`S[S79A:S,pG,PQo;3S,niT?mBIg"C),""9H/R!fg1^f2DeT;Zm4(!!!(dz!ihRl:f@K"E&$qe,Qo),2$>0MZlcp`oDtKc)$Cou>8/=c'J'@`1bnT+,l:dS"FC7s%T<K5/lMlUzg)p@q"9\e+"9_7o":P=:"@,lgjA8bXJHqDT*!V&s!gFr5,QnFlHNZ`9[QG$&"9\i."9Rdc!T6lZW)Eg%;Zm4)"9\ea!Ru'ee-&kVb@"NTdfIr""Og`\%*Saj!W2tqcr1&M)$E&&hBYJl9EF/S1\4fZ<$VS\"FC8>j'*cs;Zm4(l3'Lm"9\i.!R)$P"9H1=qu[')"9I!Q!R([Kj'VobMZN_W!omYl"eu+BquPP[?iu;f!Rq84_dEQ;_ZA6l#(p:f$-WFg!W2tqAlAg8qu[')"9I!Q!W3(&lX0n>3s!h7`!,1/r,2]=;Zm4(>9lU="?Z_F">!4l"9aB'!P_P9qu[')"9I!Q!W3(&$Xa,'@!_q(!Q52[!N#n9"9\c'"9H#2";Xo=!M33m"BYeCErhd6_ZU"1Ui-9b!NZD)gB:c&"2&Rk!P\a?&(CW]"D7b*Eri'>iro:%!N^Z9!k\R#g]QU@Hj.t.j?s$U"LJ=7V#e43,Qn5N!Mfb3!MfadP6%1`!!/TO$Msjo!Pnf,"eu*gS,njj#D6gn>R-I#!PE=R/lMlU*`E1EzXWINC"9\e,"9X0Q"1V84"Fp]O"9_+t/-iCX";VdV$)gc*Qr=+j.g.1"<^\8c"9\edbQlKn"BYd-!W)oAbQ>sq?j2/`!PAR$!N$"\"9\bt"9IFZ!NQ7N"9H^L!Rq6SX'c.T!R(S#LoXo.MZM$&!UF+r"LJ3B!V?Di7T0Em,R2a<2$>H];Zm4+"9\pjHj#g8"9_g0!Mff#Eri?FG1-Rf"9GlKX9$'=X?=)q!N\3\!N\Z;!NZ<W!N^:a!NZ=<!MfjV!NZ<d?if#0%[7"K!JG@o5#VRe=9JZK9**6>bQahM@!K9a!PAeu!VC:5YYtZ->80a6<!36^"B5LE,[:HR9EimL!R,ln-;t$Mi)9a]'&s)uZNMgu">k(5DukZV;Zm4c^aoUH"=u))"9]\i"9m^^!V?Hs]`\AS!R(ZIbQM#N?iop#!Q55db?tR=qZ6<o"cHahABP#GbQ?O,?j$!$!PAN8!VC:5O&H/a;Zm4(!Rq7$"9\b+!V?Hs=9JZKMZNGQ/&P`s"02IPbYIb;?j4^S!PAHN!N$$R"9\btctdl)"<9<&!R=UHoE,4!"9H^Ie-#nV"9GP(!W)oAe:5qT?ig-*!R-&B43M"V#-.dsbSI6e?j59c!PEZh!N$6h"9\bt"9`@9"9G])!r,[s3)]q_!MBRb"9]]&7`-TP!lP^&4<t%T6mMmT9I'`Tk>MKd>8/Ui1^!j>X>C%s!Mfc#K3KT`HNYl$;Zm4+-%c6,X:c#mN"#Um"3brl%@dd<lkE]S%E(F8%b(d^,Qa2\"Crb\"=-]8"=@%M!hWBoE%KH@j=CDg$g^^k.MN/Q!ON6Aj)+qbS-ANc#LinY"<B<%"9J]_qcb=.;Zm42;Zm5*"9H_Ie-#nV"9GP(!W)oIbQY=\?imA0PQAE1oDtfr;Zm4(,Wl.C/-3@e"9a&S!JjYWmo'>lHNYl#;Zm4+6B_Ok"9]]`b623O/0#F6j'*%I*Adm"!X(=_;Zm4+)$D4'>8/Uk1^!j>">g6%,Wl22/:W:V"9a&SEt2+O*&[on&5r]72BN/#;Zm4C"9\bF]E5N?+:t%J"9]41'J'B&"9IOe1^"gU49P]g"7'/:"FC8&hbsX\!#u"?z!ijusfM_nU]GS!W"O%u+kYhTe=9NFB!Ls8qU]aY<">k0#lu6a@"lodh!Mfb2!MhN`":<k11ii]!3L^>Fj8lW8"V0#`"9\n@!NZ=:E-(mZ,Qn.T!Ls2+!Lu^HWr\^j_#^'DP6%0S!L.C$lYHTl"4LW]Zu6(P;Zm4()$DJj\-%?d/-3Zi(/k>=!Rh/s;D]Xe"9H^L"9\j0oE"Rd?j""A_Z@sp]Q7H_V?lMh"9J,q"@lAn!N8p"=9JZK!Rq5T_up+A!PJU:!sA`0!V?Eb"LDJT"eu+Be-DIN?ig-*!Q554"-[+c"7lQ;]E[D(V?Het"9J,q">EaW"E.3A!N/j!G>eVI4<t%\6mMm\"B%'%E!Q7C#IFc<4>\;dCU74RO<4T.!sA`-!R(T:"9_g0!NQ7NqZ6<l#0UCp#O;E7bQc6u?j5is!Rq/)MdQS_9**6>]EO4$V@TI'"9J,qUE3>:$kbBD6mMmd9I'`d<$VS\!Pg5h,Qoq\Ocoo!">k&u!RF[I!P_kB!R(_KN->]sIl%9=%*UORN!Ao<.gNuu1^!l5/-H!M"?[q4!hWBozS-f5r"9\e+"?\A:">g6=ZNLCK*$fJP"?[q4";"K7!QPb1"9]e$">glm$qs&74>Y_r49U!6!TRAu6mMmdo34%F"?Z^A"=++s"9^h4!!!L-z!ii10?rI12#+QC'";fR(9E7uo"@HB="9`I56uZ'-1i+E?'Eh<-9MAG+<'2E/5TD$P"9GqF(/k>=";q>1E"_16>9lm!"9\r#'N>*b9MAG+"@OL<1al9*/5.;l*)n0d4Bs-7"Crb\<&RYX9IqFl#4l%E!J1F_;Zm5&)&33BzWnS]t;Zm4)!SdhI"9H1==9JZc!sA`0!TX<@o3_[<qZ5IR#-2,4"cEG@N!?=j?ifj#!TXEj]3k`YqZ5a^#HM5:DZg*j"9\db"9]iG"9Y;q6uX9$9I'`l"B%W-!)j"'=9JYX]``]cZigL4!L.X+ErioVCT@Rp":gB0!PEmbErj2^!R([W"9`O^!Q5#R!Q5#O"9H/FN,USRZio_&]EE'PG7=BOM>IeL@L)N+%K$76ZtBEHZj`00UDsF>_#^o;irQLf!L.s9!JCK\ZX<p*VDNAs"9H^IP\*hs3!#6S"@NpA"ACp'M5)UI2?BHO;Zm4c#GVE>";ED+$qs&7PQJI$!Lugm/OT_8;Zm4+H.rHu"=ur[6l\lGHc#ta'FYUB/6!kt**a`l1h7j71i+E?"@Q60!N/j!V*kQI$,crI9I(+D;FC\q-UZVk"9^hF"9a3Qli_6*"9GP(=9JZc"9I9\g]RYk?jD;b!UKi>K4"`WqZ5IQ"QNkj?qUOU!TXL'P@+N_e,e&(MufdV;Zm4))$DbrV*"k`!hTSr#K'RnIo?IQ%T<K5zPQq0g"9\e+$(NtR!MC+5"<88s$lfBf!KN(BE%Rgf,Qo)$,Qnf,;C!55;Zm4+!!!!7*rl9@"9PUL!Q\1BX'6!+"?Z^<lN@=j'ENjh"4R^[lj9b;Ig4[0%u_2bZiQ+L.h1hP"9]+>"9QqK!JjYWaAW3E;Zm4)#K-_;qca,tHNZG4>;SGF"=sZP"9_+<quP/CT`h_2`"DnJ!PJU:!Rq5TbQIsI"BYd-#0R%ce-D1FP@,U9irR@/]F/*NoPXj5;Zm4(;Zm50!sAa&"CqOlPQV+k"@R;3XDf*$)rh&+"9G<;>]TqIG0:8p"9GlK!P\`L,Qn.L!L*W#!L,k8!L*VVPQ?ht!L.'p!L+hp!L*W$PQ?_9A-%nq<*N`T!N#s`"9\b4$qq.04=nrc49U!6Cf(VJ.PqL&%FbF.qecZ:r!V9^$,cuW6mMm\<`9,(">p<EWr^]Q!R(ZI"9_g0!V?Hs]`\AS!Rq5QRpZ9oMZNGN"Og`\!W)o9oEDj7?ig-*b5ogC"oD[0#0R%k]ER>'V?kBH"9J,q1epsP49QN)"8c:Z6mMmTAlAg8zOp(gc"9\e+(@3GJ!L=7t";D%#"9\iF";DOq"<8C,"9\ib!!!d5z!ij0WaAW3E;Zm4)"9\bP!Mg3("9_g0!NQ7&Wr]:)".N[#"g\6*PQTBBV?isu"9H^I<,bb=9E\H#"9H1=ErgpsCT@Rp"9FI#!P\\h=N^_u!PneiI-Ufd!Pnu!PD]Hp!!.`R3PtlN!Pnei9G7G[!JCK<?j3l9DZiI$"9\aa"9G`*!O,K*";q=V>7:bdU`9F4*!)Q7[N#=p"9\i.U]KCP"BYd-Wr]:)!NZD)qd9X*qZ3c&#(p:a#0R%CPQRsoV??_s"9H^I"AVku,QWK"&gT%*,Qo)4JclK=lj1N1`(_KfS.lA:"=,5n"9\ib'$M+i!N6(<"9]-t!Mgc8S-2ps!PJU:dfH6I"S6"(!W)nfU]g9s?if!_!MfdlZX<g'X9"OhbQ4RJ;Zm4(6R2]!":P<t"9`Hb$j!X:[Sm;3#mCA2zX.UX:;Zm4)4@fS<"9cnK"gCo.kYhTe"hZr""<:)\6mP_W/-H)R6pq'k"?[q46uYAs-;t$M#_3'$"9^gm"9lS>4E)au6mMmllWXck^B=Zj"@PWY"9]\iHig6F"9_g0!NQ6S!NZD,Zikbt"@R;3Duk[YirfCY!Q8pm+T\r$!PAO<gB9W[_u]N9<MKZt"9mk*ZloI_#4r$#%?(E5P]m;L!J0P@XC;4#!NZ\1qujB>"UsGuDkdN$!Pnf<H'891!L*V<X*arL!omZBV?j8>"9H^I!VfRr=9JZc!sA`0!fR2>_dEVbK)t$;Cm/7!"bZp+!fR/Wi)9a]^aoTj"@PWY"9^h4"9mFV!fR3a=9JZc_ZGc""I!3r!S[Y9j91ZS?neV^!Rq@4!N$-U"9\db"9lkF"di3k&k"&#"?Zss"=-ql"<:Yl"9`6\"9]cE"9Rdc"9;@'"6`YdWr_Pi!TX@ali^Dn?ig-*!TXK<dpN42oE!GEMufd_;Zm4);Zm4e$q(-2'EYUF"<:i<DukrN,Qp4t;Zm4s,Qn7SKL>jVG6O36!fRTL4F[io4p[ZH"Io\GbUWsh;Zm4.!TX@(j9/QfRp[HA_ZAg"!io^$"0;OQ!fR/W^f(@=;Zm4*;Zm4_)$E&d#SsHD"9^hlrrV[gb>p_+;Zm4)"9\b0qZ2LO$kbsN<$VS\>U0G'A0_:?p/;(s;Zm4)"9\ae"9]35B**ie!Q.r#DGpZ@='f7O"9\nH!TZ1<j9/Qf?j=dT!T[8HgL()`"9I!T"9OO#!P_P9&k%/c"?[(A";Ff\"9_sT_ZIkW>Q__A;Zm4c)QWu>UcTR'"9IQh!TXAc#,>QN>PeH^e-*BkN,Jh";Zm4)"9\c""9QSA!fR3a=9JZc!UKplg]RYY!PJU:MZSh?#.n7F!W)oQj9(lZX'cSAZN9+k"2eLM!W)oYliN)Q?j5is!TXF]ZX<mY"9I!V"9OO#!M33mVc*^$V*kFf"?Zef*!2o],ZH#l"9_Uj"3sgJ<]gDd"9`)L*!5;%,ZH#l"B#?'zPQq0g"9\e+"<9*o*!?B^lNA2K'GPKg*$cd4*%W?<"9_UJg^[6c(ELEt!!!jhz!ipqq#ZCj/cr1&M)$C?KV%a%8],UqS"9FhiE'^N-,b"o^K*3`E5W!Ej,QWc*cr1&M;Zm4,"9\hB6mr)="DASS".3!i"D\,C!O;h2j:7+W'SI)$#T!Uh02huV>UU-S;Zm4c"9\e!"9_Iu'Eu9N$iu\^AlAg85Z7dg!T5c/"9_sf!R+qM"9_g0!V?Hs",d3PbQd*8?qKqj!PAN8!N$(6"9\bt`!#!s!PJU:"9H^L!Q5+C"P[<W"iCAb]E=X2V@2/["9J,q"Ro=m,QnY5C1IHX;Zm4+"9\b0"9Pf+"BJG(6uZl;!KPn;X@rZ[!JThD!T[4-lidNfM?IMo2X<a34BqoI3)]q_,QnL6"O(0d"9\b6q[QO->W-2.^/G.;.Dli#":P<t!KL(]<]gDC"9\mt'EOP!Cd]NO"AC'D6ik%*Dc6cA"D\,C?;gt0!PJVX=9O!S!NZD,!n9nbb6`Qs"U"s'Gd@FPX8i:&X:C-hX9$-<P]U[AHi^;Lj'Vn?%BO@L"9GlJ";k&?6ik(Kgen8C;Zm43"9\ac"9^tgj$Wp"6kVm`%HI]2]EmSBIgF7*#HS>5'F;'0!j!o">U0Fl[Sm;3"9HFA"9\b=!V?HsWr^]Q!R(ZIoE88!_dFDaWr^]S"LDJ<"02I@bQNQ+?ibl\!PAMe!N$(>"9\bt"9Q>:!NQ7N!sA`0!Q5$2"9H1==9JZKo)\Id#E)sj!W)oI!Q8JUUL4/pUB/R>]N\bHoPXj5;Zm4("9\eg"9S!i!V?Hs=9JZK])hO,#HM57?qUOE!R(eL"g_T`%f?@?!V?Dia&<*D49LlN":t*)!No?(!!rf1z!ii[FW)Eg%"9FG_!K7.`o3_UrUB-;V"1qqEZu6(p;Zm4(eH?!T"9O)S/5u]S"9_g0!K;))4EG$9lj)8J"3bQ^FDrFV"<h:Y<b-]4^B=[M#b5-#XEOa$Zk;$qoNYi-]OtIOX::s3#h0"_>QKA-gKXcq!L-Oa"f!VR*!2mC!N$73;Zm5F"9FHX!JCSX"9H1=Zi^F6MZL0c#/agN#Fbb$KEd?B?ig-*!K78IRpZ9ODZkFg"9\b4"9^ne"9_e)*:s_>!PJg#"9\t"":P=:$nkN^!LF2kWtYVg$iu]/">(#b2cBh^!!O)=z!iq)*YYtZ-;Zm4,!L*]M*+U;t6u4+O"EYmlclc6ioL]5f;Zm4(;Zm4/"9\c#9Eh(f!Qkc)"=snU49:*\!K89,"B&bm=9J\qirY_R8b6<n#D3)JS41%t?j4.D!fR2=!lT![E)QlBpeq:u"9P(r!gEgi"9H1="OdF:!h;nkP@+Kne,kR3_uZ_<;Zm4):gfb."9_sf"9_1m"9`mH9EDq-"9\`."9G?(YYtZ-"9GS+g]RYtA5t_s*$bYtW)Eg%!Ka&Z>W)\?YYtZ-;Zm4(!h9>ePQY(k!PJU;qZ;ub"1qqA!W)qgS-SXn?io'a!h9;W#*WF>%%IBX!lP,:%T<K5!V@Y\lN-W\!V?DN!V?E/!UMK2!V?DW"hOfRZid@:V?jO0"9O5W!S:6Q,R<*M,Qpe/,Qp5?/S#!#>;T"VqZHr[">"L"!oQu[BN#$:liR@n"9HFAoE5;!!L.X+E-['=K*25Q#_[.=+T_3<!V?V]Rihb(oDtg'"9Gq3aAW3E,Qoq)"=+#4*!)QT!MgtD:f@K"_ug,F"9P(pU]^g&"9GP)!W)qo!h;>[j'W(LqZ<Ps"litk"1nWQS-@q\?il5f!fR9:!N$4""9\eE"9J3p!mX^Ii)9a]A4t)H";D7W">"X?#0_H?KHpeu,QpdA"9\aa"9Gu1oPblC;Zm4(!MfesN%>>.o)e8!!VCb>"I';L"9[uo!N&cu_ug,F"9P(p!lP4Do3_UrUB6qf"m]P"DZg-#"9\eE"9^V]C]U\;FA,=1#eVDcZm5d%g]lgK#aBNC$cE(I!JD_JUco%=X9@;[$`ki^,Qn.,;Zm4c!gE`B"9H1=Wrf("!h9AoU]ad&?ig-+!gEi*_dEN"qZ<8j#NK1qDZg-#"9\eE!!3'tzWk]YU;Zm4)"9\eQ"9`+2`!c[P"BYd-]`\AK!PAO9]3k[:ZN7uK#.n7D!W)o1]E=X2?ig-*ZN7uX"3Y'Q!W)o1_ufO<?j>Wl!ON!)!N$1A"9\bl<!%kS9E\H#"9H1=Ergps!K7.LqZL/F#)mME!P\a?PQV#GP]UsIE#?b'df]]A!MjZ<V#dY##0[2NPQAQFKFQ-+"9]kK>]Tq)E$+*C"9\h6!K7&o-3^ar!JCK,!O)lp$1nJ@!KmJBU^I#V"7.68"2"urgBH)N@KM3-#il#>]Oq7uj9)1a#j_^"!JF"E!JCKi!L-9!UJq8I"05f4XD\50;Zm4(;Zm47;Zm4W)$D3+('31n"=+##"><[VU^g<+!X,k=5gp:''FYU*/3G0\"9a&S!#AK9zWlZIc;Zm4)"=+#8"9^t+"9["Lli_),G6bb`%cdeh,_#lS4pLp)#g<=f]IO,t2$>02r#GV;!LsH%&k!n<,Qp4<,Qo)d":1N&/-KK/6pq'k"<8Zi!O,K*(fLP?E$*O3M?G:`"9]tN"9`[BliNCR"BYd-]`\AsoE59t"9GP(!W)oYliY^E?j":I!gEf9dpN99'*7G%PQK$9?ifj#!gEc0gL(&_dfK(F#2<Mg!ODgng]=`hV?aI/"9Oeg!KU.^";q=^E#k\VK@9rK">"Km!KL(]!PJVX=9O!S!NZD,"9G<><-&)IE!h4##F#8%`-lQV!R(ZTe-'<'"Di,[!UMlN!Knu:%f?@7]R4P%KF[VT%^ZBE+T\YIbRFCP%)d?"#aAr=S,o^#B*#(C"geX'oE>Qn!JnW&!Pnf<#(lrXX9"Q-?mC%""De1H"9I"j":e?5!$5&AzWjiuJ;Zm4)"9\bX"@R&.F9D_KP6=!h"FP.lKQ%47+`mhfF=+<sHj"NkK*6:;!JGDIDumQR!P8J^g]<XY!Pfrd@siBGKLFR:Mf\q(!PrkGP\_"To0d[$1^d[m!N$;'"9\ai"9]97"9`sJ"<84V$mYrn'EYUFbT(FE!O;h="9\kW%YP<j!O2f]"9\pn!Mf]o"9H1==9JZ+qZ3Jq".N[!?m>]R!NZBmX'c+s"9G"s"9I"jUjl;G!PJU:!OMt4X98R)"BYd-!W)nnZj2e&?j;5a!NZK`j'VtqRfTSo"m]Ou$If*H!Rq.IT2Pjq!!!!"#64`("9PTg*'dF**!@,^D7a!\E$*O3,Qo)$;Zm4K]E4l7"3_>d/0k?4"B$Kb%T<K5z_]AdX"9\e+#NT8km!K`,)$D2n,Qo@q%.#f%j8uqt!LttI/-HKj%>4j9'RUn4%b(s#'El&P/1`%L"9^Rb"@uGo";Xo=]Dtk5!PJU:"9HFD!PAP;"f#Hu"eu+:`!)oD?j5Qk!ON&`!UO_-=&T5)YYtZ-X'>c."B5L)KEME[!L.X+Erh4&PQV#?"E\\cb]$(Y!P8I?!Mfb$0a6#/$cE(I!PecD"9\ai!K7&o1%Pabg]<Xe"V(A;KEMJ>S-0u9G6IgGb^PHa!JFne!JCp[lj0+o"UMIG.D#u#!Pnei#D3&1KE7<B#/aC@6jCP:!N^2BAlAg8]`\AK"9\i._u]3,"BYd-Wr^EI!Q5*A]3k`aqZ4>6"oD[."OdCqlim8o?iu;f!UL#kMdQXFo)Zc2!qTe$%-.Gr!UKia[Sm;3!!!!",ldoF"9PUg!iT$#lW+^=;Zm4-#K-eU.Do?u&'P*f,QYLbKM`5\$j<X=bQG4%D?l[@#4)B&j95^G>7=I9$sWhFUB.u2!L,]n>7=bA1TLPg>QL'O>U0Ft0N/)W>Rj37;Zm4;"B5K%"@RV_*!(^<$Ig=(OAc8b,QoY#,Qnfl,QpeW;Zm5F`!t3d/-Hh!!P;PE]3>\;;Zm4(;Zm4W"9\aU"9]!/"9QA;S1%;=?k_$&;Zm4+lN@7(#eY+)%T<K5fM_nU!e^[Xqud&$"BYd-]`\B.!e^[W$Xa#4?s<[(RfWEp"hS.E!k\R#!i,joY>YQ,"9GS)g]Ra^!K;(#AW$TM"?3@fg^jt^N"*E#%GZ.9$hR`rPQBQKB*$ck"M>39KEV\3!JL%M!Pnfl#Km/'!L*Vd!NZ=Wqd9U)"9G"r"9IS%!Uiqi=9J[&!sA`0!V?Gh"9H1=WrdqW!V?Kq#D6DW"j6tCKEm-;K4#o*MZNGT"Og`]@!_qP!UKp#!N$<Z"9\e%"9^\_6irrYqufo&"BYd-"1&%+quuCoMdT0YX9%YkU]I>";Zm4)>7=aX>Vm=V9Ip47EhchqL/S3X!e^[Xqud&$"BYd-U]U`&o)b]h!L$ml!W)qOquN!h?il5e!UKl_!i0`;p/;(s>7=a;S6Rm<ItLu,>QL'OE#?1i;Zm4;!!!!/)#sX:"9PU7!J")O$IfFD6koP$"9_g0"De/C!L.YIE'9s!A(q-6"9F0a_ZV-)!M4B]FF99o#jZS/F904"!L.CV".M]#g]=`hKPptu;Zm4(;Zm4';Zm4?"9\b("9]N>S.#G("BYd-Wr]"!!Ls8n]3k[:qZ3Js#.n7D".K=]N!B/e`,>bZ;Zm4(;Zm4'$fh]rr!]A=G6,&W$-Wb3";H#)!JM!D%\*R<KEV[P'JZ'_"9]DO":P9/":QP$"=sS*"=-\U!L>bL=9JYp"9F_i"9\b=!Q5'C",d2uPQBNH?j3;+!Q51p>@7L/"02HmN!$CoV@JOc"9HFA!Z"];!!!<//-#YM"9PWY!glmh"D\,C;$c5n"QT[O#coKa#.+WZ*$>&qg][lBS7F/]"@Poa"9`6\Zifer"BYd.]`\D<!iuM*"1)B>"mZ5sZidXB?j?K0!i,jl!o.\s!)j"',QnCk!iud*gij(CS.)b4!OR=`4q@31!Q52<`%)&I^cV`(KE6`,>U0FQ"HY+n"9_sf."b>pqu?cqr)_nZquOV7oEFgequN#_ZN88N!io]6DZg*R"9\drliZHMC'V*Y"@jDa"9JEm"5$NT^f(@=;Zm4)"B5E[>Qb0I1^!iU"Crb\KJug4;[fH*!R(S["9_g0!V?HsErl1AGN/g2"9O5a!W4#BquMkRquOV7!e^[WqZM"^!fV))Dukk"S-/nX"9^F\KE8k6KE:uPquMTTquO8-"9Gq3Lf4EZ"9PY-"9\b=!NQ:7"9Pq5!iuN,K4"`WqZ=D5"G:(_#P/#(U^"/5V?t0B"9R?Z">EaW":e?5A62\4!U(=&%T<K5!K-IO-O99_A-%PjpJV1t;Zm4(,Qpe9!R+MZ,]j'^"9_V5!f0bX=9J]4!sA`0!o*k4dpN99K*&C^!UF+t9q)4>g]<UH?ifj#_ZI2d!LmHtDZg-;"9\e]$u@=j"A+5MA7SmI<$VV%>7:\*"9]hD"9a3QUB8_>!S7@3"9_sf"9Isi"?9<_r,=U4;Zm4(L[tPl&cmXd,QrK'";Cm$*!)QT!MgtDpJV1t"9Pq2!iuN,"9H1=Wrfp:!k\X:P@+Fg_ZHnD#NK1r#I=K=Uhf!uV@LNG"9R?Z!QS+AWrfp:!ji(2"9_g0!o*k\"1nWi]Eap6?ig-+!ji3%Rp\gGj8u+[g]=8_;Zm4)S7F_^ZNNYs"CuIeCiCBcY>YQ,lNX]u!W7<`&%i"W"9_s5!!7mRzWg!_g;Zm4))$Cp=,Qo(i>7<&.///;X"=sSD"9^;%$j!X:(pk"<!OMlt%T<K5ziZS:%"9\e+"9I.RKE7o3KEM,\#+TlA$A8Q;j;^R;#_YAB#-7uu'FU-U,YTHdg]UM;$PiRY"9\t:1]s[TqZIc>2?Me>;Zm4S4<oc'";D7W">idt*)ls)/6jG'Uc_Ws!K.'^>RnslbR3udIg(K+#a@^sPR->6.fn]9gB7]P*'A1V'LX2L,YTHd"9_Ub">EaW!U*Gb]3?OC>7<n#,YT-B"9m7Y"9;@'":.p/e3Hq8!PJU:"9I9\j9,Tf"9GP(!W)oYe-E<f?j!G1!Sdpd]3k_nX9$NKKE7q\;Zm4)j9,Oo"9GP(]`\Ac"9\i.g]E-2"BYd-!qQHJe,c=P?if!_!e^[!b?tFaqZ51K!R"jO#O;EOKEq*V?jE/&!SdqORpZHDbQ5ogKE7qV;Zm4)%L/Ct"9^86g]?hA"BYd-!W)oQg]OTbX'f-4"9H^N"9O6p"BJG(!Ls5p"BYeKEri'>WsePV!N^6U!P\a?60eQI!Or0CX98R""E\\cKQ&E9dg3#Z!PEd`#+PaR":NEW`,Ga8^a'$`U]IOt)?Ho?I)>u\U]:Fk!KE9D!Pnf4#5\Fs!L*VTPB6i$A6WFH!Q8mZDGpZ@qcc`fbRDDk"B6WV9EDm2"FC86%T<K5zO9GUa"9\e+"<7D?M=Uif!L+Q)Z31:E)8$@Y!N?e"!!!e1z!ijH`peq:uJBJ&s!K:supeq:ubR:3J&?HHJE"_16"9\aa>Q^'d"9_g0"9GQ6Erh4&PQV#gr+pET!P\aJF8Gus_uKgsMuek==N_ff!K7*,"9\b6!LQdg]`\A3!NZD)U]ad&?ig-*!NZIb_dESQUB.G#"7on(#D<,J!Rq.I2H'_]]3>[h":Be_"<8s<"=,fL/0m>'ZigM0"9GP(=9JZ+,6>.SX9A-&?jFjU!Ls>*!N#po"9\bT"9]iG"9^qf"9^&M"9]fF"=.ARX:tdT!P;P;>7UQN"9\b;"9G,n!Rq2S=9JZ+ZN7-1!L$mn!W)oIX9"Mm?j""A!LsAK!Ru#jB2\p97oKNnIT$@P!K:%-"S;`T!K:Qi!K7&qP[jij>QKcab?t@?",'>Q!L*V^&5r]7N(O4;;Zm4(;Zm45"9G:uX98R;"BYd-"02HuX96@J?ic_t!Ls7e!N$:D"9\bT!!2gmzX+VYs;Zm4)"9\auYQa5h]Li;2;Zm4(!JCTC"9H1==9JY`!PAO<X9#,<I!:JV"/Gt9]EJPq"7$'n"9H_c"<dfY!PAHG(1G*R!O`$A;Zm4+5GJAV'LWR%$reJTKNoc*W"]@D;Zm4-$`!omS,onu;Zm42"9\pZlikI/gf5m/e-Ps[#Lmr,Ig;bp!h;Y(S-O^2.fkS8,Qpe',Qq(',Qq@7;Zm4SG6k5L"9]u.">"Ii"@PX'lkBR[$tLUlC]T+j!X&Sk<@g7S,QpM',Qpe',Qq'l,Qq@/Sd;AJ"=,l+"IN*j]`\Akli[Fl"9GP(=9JZcUB0-Q8W-s[#(ls;lq*+C?ig-*!TZh1dpQk<"9I"c"9OO#"HZOb]`\Ak"9\i.j8t8B"BYd-!W)oQMug7mZX=^R.fn]3e,tV:V?_bT"9OM_!LQdg=9JZc"9I9\j9,Ls?j)Ag!SdjbZX<ggo)[nU"KPo3%&<pR!fR/W[Sm;3;Zm4(;Zm4ngB7S<!PE@fJ5ZRRJcl2XLAO@>6kVlg"7-B-`!relIg37\4u>B$!qZMX$&gAk>U0G/%T<K5";q=V4Dt?J!J1FW;Zm4klijb>#OE`D]`\Ak!TX@aj9/QflX1q<qZ5IW#O>au#FbbTe-!m%N,Jh";Zm4)Rfibi]Pmn*;Zm4("9IR!!Sdf["9H1=Wr_Pi"9\i.liN+J?ig-*!fR5n1LL<s?m>^-RfVS+"05f1$M4AK!fR/WSl5ap]K<G$!PAC5!PBJK!PAHL!JCZP!PAGtGe4!8Hto]i!R,Hb&5r]7[Sm;3;Zm4*$B,&D$tLUdC]T+j,Rh=Z"9\qa/-CZ+6pr:'"9^Rb!q&ti-;t$M!"fA9z!ik<#^f(@="9GS+!NZE+MdQdB1BFQ[S-#0fe8GHj;Zm4("9\dV*!;R,",nK.">p<5e,ogV"9GS)!NZE+_dENBK)sI,#K'qP"eu+"S-%_Y!N%+C"9\bT"9^V]Wrok1_#]KF_ZdCJ%@dHZWr\.Z_#]K7])dik!L-Oeqcj/\!S^ud!N'C$"9\ai">Crs"9FHR"6`Yd_un@*"9]tN"9Orh"-?Fa!Ka>b"9FI#"@#ff"Ai#"KENGL*$bXhE,O,-;Zm4K<[9j/"9\et";GKIq]#_V"9FhlE,3W";Zm4K!OMtgX98R)"BYd-"1&$8X96XR?j!_9!NZ=.gL(,i"9G"o"9I"j!KL(]e,ogV"9GS)ZigM6"9GP(!W)o)e-<6e?rP5L!NZL3o3_X[U]Hthe,cEI;Zm4(;Zm4_]`_:E"C)'1!K7.`!Lbe0!QHP*]P.D*;Zm4("9\bnr!Z>!/-1\9&hGrY,Qo)<,QoAT<?*8P,QoYL,QoqL;Zm4CU`9H5PUn'eG6j]D!fRBN1k,_:4pn(o#_W9'`%)4K,Qned;Zm4cZigGb"9GP(=9JZ+qZ4&,#Ff*%#5\G&S-H$%V?Zr!"9I!Q!JXMUY>YQ,]Ee?9e,ba8)QNuK"9FI#!WH"#!!Nr9z!ir=Ii)9a];H,1N$FF%@"A+5M;us`:*$bYdQr=+j;Zm40;Zm4g;Zm4/!W2uf"9_g0!i,o$",d5VquXcD!Ku1<li`5SV@'+""9PA"#k1aqMd$Th,QoZ;&t9#/gB;&+"Di#X"OL'M=9J[&"9J,t"9\b=!i,o$!W)oir-=K6?j;5a!i1+*P@+KNdfKAl!fLH"%I=,^!i,jofM_nU;Zm4,;Zm5)_up,)"?^`+b]!`L-^+Z6"9I"k"<dfa^f(@=@8pJ7)k-sM"9^Q#quZ@d"BYd-WrdqW!e^[Wj'VobdfKA^#0UBV"I&rR!i,jo!)j"'#3Z2j"9^Pd*!3WK/8QR7"9_V%!NQ9T!sA`0!V?Gh"9H1==9J[&qZ6<l"5@2a?kWS=!e^[1gL('Zo)b]i"5@2a!fI*Wlk54aV@:ZL"9PA"!VTFp=9JYh!Ls8q"9\b+/9:j1ErjJf9VV_IZiSZq49EG1!Rq5t#in*hgjB9h%BN5(":p_#jD\Jt!Rq5Q_up2do)p3;F90<t!g!H$!O`$I;Zm4+KEM>T"9GP)=9J[&irXl:8qULT#3u<flilugUi-A:;Zm4)"AAj+1e%Tc"9bc+"7T4l\5NM5;Zm4);Zm51">g2TWruBI>]9^pA0_:GCa9-'%T<K5;[/0`"9\bn"9G/oFDrk%:2m6:^aoV9".WTs*(L(cSQ#^8>R8OSr&=o!bQ[VB$03TE]3>\CS5`0%"9_*n1]`Y9"B6WL!Mp+h,QpL<;Zm56!Vc`q!Q7S5TMksr!K$CK!L*nDM[?a)4>_"["B6WLoG1@.!PJU:"9JE'!V?LsMdQS_.foPMloWBuUi-A:;Zm4)$rd;C//Z!'>U0RHE*:Wm;Zm56KEM=c"9GP)=9J[&,6EN$!W5Su]3n5%"9Iio"9PB;!N/j!Erj2^Dj(</"9H_c_u[UU;Zm4(!e^\1qud&$"BYd-!W)qO!K*@S"N(9<lirY]Ui-A:;Zm4)Gk2#m_uKhV`)XDM_u[[TS-&!W_uZ)'o)Y'V"oD\!%^Z7i!TX9YpJV1t;Zm4*MN\/kS8<-F!O*dYWrrR,"FP/e>QMVkVGdU#;Zm4)"9\gej92YbDZ\,p"MYrS!R"M#5#VRe"OBYt"9^Pd!!"oUz!j&:G-rU6O4E)MJ!Pfr`+=&3X,U`]j"9\b6!J")O";q=N,?kQjX'5uP;Zm4*q^_g<"9I'Y1aE2<E!*-D+Y3aY;Zm4+"C);4C]o,2Cb,]4jCE'@A-&2+4:u*d85fWon5BGm;Zm4.49P\@$+pCF"@RW1X9B*8*!?rV;Zm4s9nNV"*&\/nkYhTe2iD2LA-;q"Ch+21!LJ)T;Zm4+"9].+quWYr"BYd-OlHM="2eLI>f-U?lljhcUi-A:;Zm4)K.IJY"9Fhj1aE2<E!*-D"02Pe"9_,3"9R4S#j>1i]`\B.!W3'$"9_g0!i,o$9q)3[oPp(&?ig-*!W5fYK4&'8PQC+VU]I=u;Zm4)"9\q]"9_M!gBl5*2?DrE;Zm4C!W3"lqug+)?j5Qk!W2uAo3c-^"9Ik9"9PB;$b0+<<^ZuHE$GK1E$GKZSjXf&":"c)"E.3A'EOL6^f(@=CBObAj9hC[$f#q5#Liq<N'%f(!OP#l$)@Zn":;.[!g$=`]`\B.!W3'$"9_g0!NQ9TP6(:YM8N^+K*$],M8N^*P6(R^X'bs["9Ij:"9PB;"isUF8d#<R"9\bLA-1(U!P(8';Zm4S,Qn191b8[C!LGa''.bsC;Zm4[4;8*X"9]rR"9F$O'ENk$E)QlBSm2AuPAFb1"9FisQNDe]"Pa+\N->BbX98)#'RYB5`'+6]F9elK>RAn1!JD^$"<hjiF;/gJfM_nU;Zm40,6S&2"DCbR"@N9J"e\cs=9J[&!e^[ZKEM=V?ig-+quME0?nBJ%!UL!-!i0`;=Ao>*5>q[f,]HBZ/d&HhE(^<bM?GRh!k]cZZoJND(Bd,I"9\bg"9j<S!ME?o!M2t0;Zm4k"=+*K"9\uH4:ElA,=DR&49<8l!Lugl<!00p$p4R,;urLg!M!+W;Zm5."9\ssquWYr"BYd-]`\B.!i,r"]3l#YdfK(O&%c3P!W)oqr"$DI?u`LR!UMK2!i0`;fM_nU%+GC_"9\jCr!WV3"BYd-U]U`&])nc0"litu?m>^M!UKmZ!N#qr"9\e%<'1Xh,@ghF;usgO!M!sgKF``P$C!XRcr1&M"B7bl"9\dm"9Rdc#,kH'^/G.;*!?rVEq;+E"9F=(M^MF+!!1:P(P;b4!Pnf\"3U_h!L*V\!Ls27Rp[Vm"9FGf":`QT"/o-$OAc8b`!,c9C]U%74CMc:QT'h5/7\kabA:]&"9Fj7A/]8p[Sm;3,QoY%;Zm4;WrrRG"?^X=1dl:U"AC'Dpf)2W!K%!`!R([7Wrt8#!Ru((!P\a?"9\bL>QN/L!J:H7;Zm5&]*&3!b]!T7;Zm4("9\b?"9PA$!NQ9T"9JE'!e^\YdpN4R])ndAB[^>n"iCB=liQK\V@:BD"9PA""g:i-"ns%T"9]]&"9RL["4gBR!M!+O@8(3B_+Z(9"9_C!"9k]%!NQ9T"9J,t"9\b=!i,o$=9J[&_ZBB4Er05K#Eo4Br,V[B?j=LL!i0l6qd9N4o)\c0loSSUV@E.u"9PA"!V]Lq!eU`Z'FO2S"=tf$">k'B!No?(QXH"fK5:Yk"9FhjF<gu'IT$@Pp/;(s)Jipg3kJp5"=sSa",KkY4CLoo!PqGS<!00p"B5E<"27\:Q;[nh;Zm4)"9JF."9\j0quWYr?j=4D!i0]1qd9KkZN9u@Js0RI"9Iii"9PB;"f>3$"D\,C6lZ=lr_iq&V?-Pr";E`s!Oku1QW""i@8%@>Mn<5!"9Fhi!M!+oS6SHe9E\T$"9_t<49r#f!LJ)T)E]hZ3kI4*"=sSa#+nfsk#2Bc!Mfi$S-/kn"BYd-ErjJf'B94;X9$giDukk$j9,M="9_*nbQ5L)!Rq5Q!q\TrgjB@]S."BY#2B@iE#bVUe-#g5bQK'i)?J=ge-#fr"C-!Kgi+X9^B=Z?e,e&">li.M#4DT:!O`$Q;Zm4+"@NF>"9Z(K"L_53!!!`7*WQ0?"9PU\!k;/3Wr^EI!Q5*AbQM#N?ig-*UB/;S"cHal!i#e7Zil"hlu*"-;Zm4("9\c#"9X0Q"GftZ!RYsfM[m*VX@.F;"U+/r1^"3Q"9\iN"9G/oFE7JIE#>na"7-?\UjNC<"9ZRC":XW#!Mogu^a'$cMuf.D)?H''2i@]qMuWm;N&?LoMug`q<!(eT!K7&D?j4/I"AAsi"9GTB">EaW!jGT+";q=fE+do.$kLPr*#le"%#cG7<`9,(5>q[f,[i5\/0k?4">p<5#g=(6";''#":.p/>Rj[8<!6;+"9H1=Erh4&!L*^tS-3YLMugZrN#Seu!K9&?[K2=^"9\i."Fb#_"9FHR]LGg&!PJU:"9HFD!PAP;ZX<h2gB#4s"P[;e"k3R[!UKia0N/)WErh4&#MTAD"9Fa+S8]GE#4)Hn"9\i^"9a0PN!*clP[&81E"qU?"9\ai!K7&o:/_8u]`\AK!Q5*A"9_g0!UKmk",d3H]ER>'?ig-*!Q50%X'c.4KE8FaliEsm;Zm4("9\bn"9Iik!NQ7F"9HFD!Q5+CZX<mYMZN/H!J=b`"1&$P_uYKu?j>?dbQ5(TliEsb;Zm4(!!!(mz!ijE^:f@K"Qr=+j,Qo(h2$>0M"9G;$"9\j0bQ5oi?j+XR!Mfq3dpNH6_uZ)'bQ4RJ;Zm4("9\ei"9S'k!oQu[':]3T";]KqN,TR($&euf!NZ<P$+pD"ZN]uF@L'PaHj&e`!N\\%qumPbHq0(t]6jXq!L.[0!m=8b"?\bR"9FI"!PhV:"BYe#F9;XK<-*Ei-*nu:!JCL/[K2$e"9\i."9]351]cN5Jb*(SHNYSp1%PMN"9]\F"E"uR":*.C"BJG(!R(WK=9JZ#!NZD,S-/kn!PJU:MZM$)#)cjm!W)nnX9OSj?j;Mi!Ls@PZX<h2_Z?P9P\XY/V@K[."9H^I!QJ%@";q=^qcaa[>8/Uj"9],0"9G])!JaSV+c?ic"9F0p!RF[I-W:-N-;t$ME#Yh\"9\aY!MjU3U]ad&?j?K/!Mfh0qd9Go,QX,5!R(SAmo'>l!!!!")uos="9PUu"lN;^OAc8b"9Gk6"9\j0g]?14?iu;f!OMpGo3aZ'quNSrg]=8^;Zm4(N!'<goNZG<E%UYi"9]%4!K7&oYYtZ-"9Gk5!NZE+"9H1=!W)o!!N^?MdpNE5qZ3c#"J]?*"S2Z$Ue68IV?DhY"9I9Y!ME?oKED>[=9Mk0!K7-agB9?S!L,lT!P\a?!K7&<o,n'mN!-Xj"9Gq30N/)WWr]j9!OMt1]ED=>?ig-*!ON*\]3k`9"9G;#"9I:r!Q\1Bcr1&M;Zm4)/M%#p,Qo(i2$>H];Zm4+)$D3#/3hSdo)oa?4:D7N+Y3fp"9e&o$-XA7"F*iJ!NQ76"9Gk4!PAP;o3_UrK)r=a#P2=.!UBcnU^+eF!N'Z6"9\b\PQZ50">k0#S8`8E^B=Z?Muf.D566uL!P\Yo!O`#f;Zm4+!S@FN!K9VR%T<K5LJn<Y!sA`-!OMm_g]U^^?iu;f!OMsHX'c1u*!)i?!Sd^QVGdU#"LKET1_._T%CAtp.LZE\ZjXfO!kW=["LJKZ*"U6s1]a+'Rp-:`S3/W#"9^O^"9PH!KFh&baUPU!"<[OB!LH^f=9JZ3"9GS,X98R;?ig-*ZN7F;Zs-o=?j)Ag"9G<F"9I:rK18cB!!/$m+,^/Y!Pneq"bQi7!L*V<lWaIL43M"9S8SO(;Zm4(;Zm5*!K7/2o)r<>PQ?ho^B=Z?"9FG^!hN<n8d#4i"9\aaN!(h5!N^>CErhL.^MF$h"9FG^!KU.^!)j"'AlAg8!P8i#liE&m"UsGn"9\qY!!BB&zWgO7q;Zm4))$Dbr@EScV,WmVs1]cW@"@OL<P5nMa*"kpd>U0Fd9N;384=(+54<t%\!)j"'">p<E#a?/'!!A0.zWlQ7^;Zm4);Zm4?'\icBlpVK@;Zm4)!R(S#"9_g0!V?Hs#O;E7oE*cT?iu;f!V?HJRpZ8tP6&l.]H^eboPXj5;Zm4(#G_F2"fs:,;$srM#HS-b"cOo>$,d:kX9#qN"U1D*qZI&o/1b`J'Jq'<*'>JL/-Jj-1^"[!P6'#U":;^B"9^h4"9\^'>QN2M"9_g0!JCOXErh4&I&d:<!NlHfS-2R8"E\\c!O+$5df^#:!N^5DV#dq+,Qn5N"9G#Y"<df)%.jm[M[cb3@LohA%J0[[gh-YHKE\F_",$g^Muf*"Mug`qKE\[_Muf.D?qX`*"AAo]"9GlJ`"#]K!PJU:"9H^L!Q5+C"2eM>?qUOE!PAN8!N$7k"9\bt"9]cE"9I(P!NQ7N"9HFDbQIs["BYd-!W)oA`!;K6?ig-*!Rq@<P@+Qh_Z@sd".N[&#E/\r!V?DiAlAg8zO<FT("9\e,e,mEa!PJU:"9I9\!Rq6SlX0nVUB0.Q!L$mqDZg*b"9\dZg]lD0"BYd-Wr_8a!TX@a_dEN"K)sa2-bEag"T/;E!e^TOW)Eg%"9I9\!Rq6S"9H1=!W)oQe-)OS?ig-*!SdgQUL47XZiSATKE7qV;Zm4)4Bqos,Qa06"Cr>P"9^;]"K56%=9JZ[!sA`0!Rq1("9H1=!W)oIKESnp?iu;g!Si1RdpN7K])g[l#1Hr`DZg*b"9\dZ"9]!/"9^,O<!2>_>QboIP?SKl,QoY";Zm56!n[Y&"e/O4J5ZRR;Zm4)"9\alU]I>koIX;L><H-o4CeMWC]j!-!P;PE+B&CG!O)h#"9]]&"9J9r":e?5!Ou&2"FC8VE%@sl;Zm4C!Sd^2"9_g0!NQ7^"9I!Te-#fc?j!G1!TXKt]3k[:RfV:L#.%\<"2"ZY!e^TOk>MKd;Zm4(;Zm4/!sAa.!Sda0KEPB[?j""B!SdbJj'Vr3*!+7b!e^TO^Jb7<:BJE7"9]]&*!-(<^Ng(E;Zm4(!Sd_%"9_g0!NQ7^qZ5a\!io]0#NGj?bQF&:KPpto;Zm4);Zm4_"9\gg>QU!c!g?hN"k3qH>QeR_qZI$R"<;Ap!RF[IP?U.S"11`'>QeR_WrrPW"<;AH!fg1^>U0Fl">p<e)QX^=&qg:<Wr\.^!JCRV"9_g04ECP1E!P,#irfCq!Sd^,&**c0"<dfQ!OQp;#c%L;"G@<Pj8lV7J-!"[irbMH6mMec&+g5,Ua#u#Zq7S,!OMh-!OOT9!OMmD!K79,!OMll!Lj+CF9.k=!Q8mZO&H/a;Zm4*;Zm5@GG>:3"9]]`>Q_H6P?SO@,Qoq*/R/Eh><H-n"B5Gd>QeR_"9\iZ$IhjM!g?hN%bq*7oF@sHIg*1e5(#b/%u^p]Ual`C/R/Dd5D'(A"9]]`"9Q;9!'X<azWne`s;Zm4)2j4<!/.<.Z,ZH#l"C*2T"K56%9GgGK">*"EqcaIs$)BC"";Cm,"3=CD]`\ASe-#mT"9GP(=9JZKb5ofi"KPo7"02I@e-)g[?j)Ag!R(S>lX0bZU]J+/oDtfu;Zm4(6j*UJ"=s[-$qs&7"9t?"`,JWX!PJU:"9H^Le-#nV"9GP(oE,4!lN,31!h3R$#/^J[e-"H5?ig-*!V?KK_dENBP6&l4"-[*p#`Jes!V?DiOAc8b)$E&&49D/Y":)hF":e?5S2aFMQjVm\":sPo!jGT+!Luh'/OT_8,QoY$>7=1n"9\e<e-%C&"9GP(=9JZKMZM<1#0UBW!M]\>!PC3r!N$+W"9\bt"9G/o!PVJ8"BYeKS-&ls!Mfi!X9<ol">k0#Dul-f"9\b4"f)16E+#.<U]^_*irgM+_#^??P6%H[]E+gDK)qbK_#^?QUB..kPQ@9XF9/0<MdQ\Zg]>=u!OQbLhbsX\;Zm4(V*kGe"geC5&"FmJ;?_^n;Zm4+!il@*"?]pJ!hWBo,Y^Z0E+uoe,QnfL;FDKu,QoY$>7=1n9H4,G"AAid!M33mzOTb^b"9\e+*LmC6!N6Lp";DsU$lfBf'M=j!*'J,-!O;h2!!!!-)uos="9PU9!r,[s=9JZ3qZ4&,!fLFe#-.d3U^,(NV?`mt"9I9Y!Ou&2-rU6O(K1G>";q=^j'*3C"LJ:4"9\iJ9EDq-"9_g0"9GQ&<-*EiErgps!K7.TgB9W[!L.O.!Jd-I"9G$3"<df)!P\a?$]G+>N,U*7bQ5'OlNA@4!.4g(Hn(V5j*UmD!L-Oe"H,s$49=2E$aagT7T0EmquR!P&%"/%j9NV#N%,eQ1^;G5Zi^,B"V'5k"=+;\"9\jS":P=:KFUo`;BPfO!N['<"9H1==9JZ3!PAO<]EA89?j;Mi!NZI2ZX<h2b5nsR#.n7F!W)o!Zi]i,?if!_!MfqS!ShSr5#VRe?W.(1!!!u>,QIfE"9PWV"i+%>ErjJfqZZ%;!RuL1$\Sk_"9l^IbQ5H];Zm4("9\n<"9\Et"9`KC/9$'5-W:-NE$^,>"9\bLoDuI#"BYd-!W)oi!V@==1LLHgDZg+%"9\dr"9\Ete2ph)0q/:H"9I:s_u[Y!`&69M!Q4s=!Q5e\!Q5#T!PAMe!Q5#'#HIliKLtcCgi!;r;Zm4(;Zm5*"9\nDoE(Nb"BYd-?kWS5!h9JDdpN=%])hO.!io]tDZg+%"9\dr"9d@Ua>Qs"bXr!?;Zm4(;Zm45"9Fa!"9\j0"9H.;<-&)Y3Vt>%%J0[e[K4TB"9\i.";Fm8$^=U9oQLLuX:(O&/6mZ*lokTSljg*"#dc)f1fYMP*$bYD/0k?\T2Pjq,QpL9JclKu":TAQ*'ATo"9_Cu"9O*P9EB_J9EC6u"=-YR"<:Yl"9`6\"9_e)K/<U\&i9WC,Qo)DJclKM,QpdA1c,6K"<8Zi$j!X:=9JZs!sA`0!UKlX"9H1="OdD<!VB;u;d]gQ"1nW)!h<1slX0b"])hOg!S_",VF1IG"9P(o!f0bX";q=V^B(qd]-IL[Muf7GZNn\Ur%*52"Tb,%lN@9Z">k'J4E(D_M?Esi%@esMKPq.7;Zm41"AAjQ%#c/O!e^d]OAc8b;Zm4("9Ij[oE53."BYd-S-&ls>64'lS-6`;?j""B!V?N4_dEVrRfW-a!pa4q#lF_a!h9:gmo'>l"9J,r"9\j0S-#2_?iu;g!V?E!b?tFYe,eVlS,oJr;Zm4)"9\ac"9Q#1!KU.^(Dd3*5#VRe<\+?F"9\s^"9I(P1]`12,;aGq,Qo)D"9Y_n!UKjBk#2Bc#mCA3zWk]VT;Zm4)"B5Jb"9\j0KEQZ)"@R;3KQ@0Q!L*]fgB9W[!M"*6E-\2]PQV#_PQW-1!P\a@"9\aa!JCKg!i0n<!JCL3!JE[q!JCKiP^ET);uqXQ6u-1O!MjW:kYhTe!Q5*AZigE1!PJU:"9H.<"9\j0j8n<D?ig-*!Q52[_dE]GqZ4&.]N\bE?iuSn!NZ@W!N$(>"9\bd/-3gj/-H"W'GMeq"=tf$!LQdgIo?IQ+8d,Fj;kTP";q=L]3?O3/-al1"k*L'2cBh^]`\AC!PAO9"9_g0!TX=c"OdCYZj"'L?jD;b!TX?p]3kfcMZLHm"-[*r!L*Vd!TX9YDc6cA1aE2DP?SGX+Y3a`kl_+l/-3Kd"9^Rb"Fj>Q!"Mp1zWjEWD;Zm4)*4,d'!Kn"q*!@(J"9\iZ4:D7r"9_g0"CqT;!N^?YCia\$^BE$h(Xm1$C]U,D4EGTIE!;F.$1%urKQ&B0+`mhfF:?q-I^<i.ZYTVX!PrSiA-DL?4DY%_b?tRuDZhTr"9\aYPQ?;5!PJU:!sA`0!Ls2/"9_g0!NQ6sqZ2oa#ErNr#)`MPPQo$5?jDkr!Q52#MdQXVqZ3Js#0UBT!W)n^S-4IP?j""A!K7,m!Q8mZ&5r]7!)j"'Io?IQ-;t$M";q=VP?S_@A/$9j#h0*S!#AK9zWjEWD;Zm4);Zm5"!sA`,!Ls2/S-2ps?j;Mi!Q5#.]3o0mMZK=O"05f2DZg*""9\bD"9GH"S.8I#N?6RN"9F/V,R@<O"9^Rb!Q5'C=9JYp"9F_iPQV$#?j3;+!Q5)0$Xa,'"OdC9!LsO*_dE\l"9FGc"9HGZ*)9E8"9F8\qcb$c>9#0r"fu1.6*"2ug]S&(Rfiip'Q=),,U<L,AlAg8"BYe#F9;XKY'b5aX)[/#!J,V[Hk;KhK+#Tt!Ps.HF9T!u9RHl*>@7U*KPpuU;Zm4(;Zm4'!!!%lz!iidLi)9a];Zm4("<7Kq'I3f!"9IOe/-HtE1^!j_!K1/%"BYdPZ313@"9],6"AEn>HisRSKENiI"AEk;N,s@Cg]rK5KE8giK*gT>!K;DU"G@9'":<ieS-1!_G71JT.uOhSHt!D@B7'jK%`A\/j95_bHmt6bMgPQA!L.[/?mA?m"?Zmh"9FI"PR^Up\eqLT";RF-UeXhk"BYd-]`\A+X98Y,"9GP(bQ@tNMZM$&#(p:c!W)o!S-FmZ?ig-*!MfpX,@C_fDZg**"9\bL!Mj($S-2ps!PJU:qZ32i#0UBT"02Hu!L.Y5!N$","9\bL"9]K=*!&9&zX+;Jq;Zm4)#L!:k'QbT'"FMHt;usck4<t&/peq:u"9IQdli[@&"BYd-#0R&.lik"/j'XA<e,e>/PQ@Wi;Zm4)$rdA.'HN*9/-28?Md$ThS5^1C"9]tN"9HSB"@,lg!NQ7n"9Iil!V?LsdpN4R'*7G$lsIY<?ieFO!SddP!gIU+cr1&M;Zm4)]L2nd/'D--!KYD,6o7#F";Cm,<+o25"k-ZqUK^\s,Qnf:$LA/%<+I6W"9a&S!Ou&2'U0PqK+Q7?$kcNLA0_:?Ca9-W%T<K5YYtZ-;Zm4+6o4q2"AAid"HZOb\5NM5;Zm4(&Hkcc"@NF#";Gr'<'5OR"=s[R#M`9(>^$C*"T/JBCa<88%*TDL]IO,T,Qp4=;Zm56;Zm51$nMFFMugOp!UX\+#G_C44F@e%"oJbh"9PA&!N8p"!q6>N"9^hF"9FN]9P.3+"9]SF!mjjKWr_hq!UKpi"9_g0!gEci]`\As!TX@aK4"i2b6!n/!J=b`?m>^E!UKi>F'o'-%K$7^!gE__p/;(s;Zm4(;Zm4_!M]^o4>m8d+&`:F2@'BE;Zm4c*sMO#"9^hFliF:g"BYd-]`\As!TX@a"05g&8b2uLg]slfV@DSe"9Oeg!JjYW=9JYp!R(ZL!RseaUBt&G^FTM0K)s0s!!1:n,hij*!Pnf\"cEE*!L*VT!Ls27",gP;DZg*""9\bTliQlZ"BYd-PQM$kP6("O!m=sV"1nW!liP@<?icGl!SddH!gIU+Sl5ap;Zm4*"9\e/"9G,n!NQ7n"9Iil!V?LsljI2G?io?h!Sdn.!N$"l"9\dj!!B]/zWkTMR;Zm4))$D35,V08_*!2=.">hA,!ME?o%T<K5?rI12Wr]j9!OMt1"9_g0!Sdb[]`\A;!PAO9MdQS_qZ4&*"bU1`!W)o!g]P/r?j2Gh!SdaOK4"e>P6&#n".N[!DZg*:"9\b\ZiYbV"BYd-!W)o)Zid@:?jD;b!MfbN!ShSr/lMlU">p<55#VRe"?7q8!J]V;";DPhquePr"?06[9QU@>"9_g0!MjdaErgpsN!'0GN*LE)E(?*%"9\ai!K7&oE,;i`KEM=?"9GA#Erh4&"d9'O"9F`<S8_KO!K7-^":O96df^hAHiSOR_0g3cF:3Hs9RHl*P@+K^DZi0)"9\aqoE!!2L_ZEs":hL6!Oku1zPm@?i"9\e+%>6uF!N$@f"=+JAqZI$>*#*>sJWj:`;Zm4(,Qo(e,Qnf4;CieE;Zm4+!!!!7/-#YM"9P[/%cC7gOAc8b,Qneo!K7&46,Qo+>7:Os!K9X?!Ls1T"9\aa":FWs!ME?oJJRPS"9GS)Zu?2D<<OiR"9\ai>QfFS9EYC-9E]\F!P;PE]3>\C=n;as"9]]`/-XC!%D5[D"AWJ1Ca9-?F<guO!K",c"9a*kU^cNd)\r8Y"9\djP6ABo2?enQ;Zm4C!ji&["9_g0!o*k\",d69Zj+]]!K_p8U]cT`gi!;s;Zm4)"9]%0Zj4rV"BYd.]`\D<!iuM*gL('ZWrfXnABS@7DZg-;"9\e]"9uY?"cuXc]`\D<!ji(2ZijJ6?j;Mj!j#/GdpN42K*&DT9<2G&DZg-;"9\e]"9OBX!V?Hs=9JZK!W3''"9F0s1ii_OE,NPr%u^RK!P\Zr"9\dZ!W2u5Erq!t<q?H9"9OO$P]-l&#GVD'"9P*4KE8k6KE:uP!W6F/!W3DEP6(R]_#aII_ZBZ9PQCCZbQ7VB?p92D!PCMS!h=03i)9a]!W*!/"9FI#P]-[#!W*!#"9G$3#2iD_&mRZMN/Ifa"Di#X"9]lQ!m":CaAW3EOi%;&!L.O(P/@dJ!M"*0Duoh=irfCY!N^6"5#VReDun\rqZHqY!L.O(E"8??/-H!D4F@1F!JD^$Duoh=qZHqY!L.O(Duoh=WrrHn!MjZ:!Up4CC]jcl">g6V"9`fl":DqC"JAZrcr1&M"9Pq7!ji)4:@hj<(<ZcdU][)ogi!;s;Zm4)!ji9,X9;W.!PJU;qZ<i%$bKdI$d/UY!i0=6!o.\scr1&Med(dJ"<9<#!k2)2E!<!>_ZU47N,Sf[39(,B"9Fa+F900.HmAhWDuoh="9\aY>QU3i"B6WL$A_U`=9J]4qZ=,-!pa4u46$CLU`n2pgi!;s;Zm4)"9PZ<ZigEC"BYd.!W)r"ZinQ[dpQYe"9PA'"9R@s"0YW+=9J]4"9PY-X98R;?ig-+!jil0j'Zb_!i,jZ!o.\sn5BGm;Zm4+"9\gedfnB&&cmYq"=+HCHi]HW!LtD<Ua-(J,Qne^*&I\t"9F0U#,kH'Rp-;;S8;_.>QeR<$sWoe"9H,=#d@51C&8(X8a@@8"=+Ub>QMSB9I'aG>U0FdA0_:OW)Eg%!sA`-!ji$ag]U^^?id;0ZiPup?ifQp!i,jd!o.\sVGdU#;Zm4+"9\dmX9./Z!PJU;"9Pq5!iuN,]3k[:MZVZE-hC^J)Y4$;U]SGAgi!;s;Zm4)A/k]%A-<$5"CqWY"=u)L"<:qt"9`Nd>Qcua"9\iZ"9cbD"5$NT/HLM-;Zm4+/-H'b!K7&pPU$Ao!W*!#"9G$3DukTt"9\b$/-JF@4ELVR"FMHtKQ%^m;Zm4("9\k+X9+tl!PJU;!k\X=ZigE1"BYd.g]IZ^qZ=D3(V=&U"1nWiX;AKV?j?K0!jicU_dG"4!i,jY!o.\sO&H/aCBObC!JJo)"=+UjDukg%;Zm5FRfieZ"FP/VKQ$th7%4;["9FI#C]V=&F<guO!Kk8&"9a*koEN?7DuohC_ZU")S8\Lk!S[_X"9G<;KE8k>,Qp41"9\aa49Ef,!JD^$!W*&m"9FI#P]-[#!W*!#"9G$3Ui6A3^aoTh49:*9!K89,E#.aB"9\ai49;rj"9]SF"9G>e&kk3AL'1a,">h)!"?^3?_ZXd$FDq8CpJV1t;Zm4("CqbO"9Hda#)6%Z=9J]4MZU6g"3Y'V!ODj7Uh]4'gi!;s;Zm4)"9\akPQAQuWXISb!K9DIb?Q:q6oJB^?rI12doLi3;Zm4+"OdJ`!Ls2iDuoh=,6S%C/-2hk!K:"]"AX%AHmAhOKHp[_*kMOU"9FI##+&6kel)\S;Zm4)!L*]L%`BUq!K",c"9F0pN,V1SM6d<c!L.O(E!<!>/-H!D"FL6c"o_F']`\D<"9\i.Zi]"b"BYd.Wrfp:!o*nZo3_ZYqZ<j,#_QLc!W)r2Zj;:l?k9RF!i0C[!o.\s``!!C,Qnee>7>%IA5iWB"CqP'"m8ee#4iAdZNOfX"Di$'FDtmIM?F$Jiriln!JGDODuoh=RfibN!L-/Da&<*D;Zm4-!!!5$z!ii[LBN#$:)!hHs":^l6!NQ7>"9H.<"9\j0ZiT4i!PJU:qZ4&,#.n7D#O;E/j8t6I?iu;f!TX?Pqd9H*ZN7]B"oD[0"mZ3%X9OSjjDP/%;Zm4(;Zm4_)$Cop,Qo(i>8/V6"9F&%"9^;%]E,;@;Zm42;Zm4^=9M"lF*%NfHisJ?WruCCKE8\C!K7-^#-;ofP]/7U!K.']"9G$3!Mp!bD'T5eHisY\K*2<#!JGD&Erh4&KA-Mc!L.O(!P\a?,Qn.,]6"(hF9$DK_/pU-#O?I4F9.Uo?jH!c">g2O"9G<:!N&cuzOX'o,"9\e,MufkU"BYd-Wr\Ff]EA?<"B9FC`,If-!R(ZIqZJ`se,d0$"9R'R%dX52ErjbnP7=m(gjB-dX:(g)#*]8t!P\a?,Qn.t!PAHK!PD-bkQ/><[K4#D"9\i."9OBX!g$=`-rU6O";q>1])`=&>7=1+"9\b;"9`+2!UNW]"9H1==9JZsdfJe<%`;ZWB[["Sj8lSp!N$h;"9\dr6j;4A9oE3aG>eVI%.j^R"9I7X!JjYW^f(@=/.;=X6qdWG]3>Qr!eUUV"9]EXoE)O$"BYd-]`\B&"9\i.S-#2_?iu;g!V?EI"H-Y$!W)oali`5S?ig-*!V?JHK4"f!,6@E=j9(TRV@UlO"9P(o":e?5!Us"jfM_nU;Zm4+'Cu?N"9H/S!l._;kYhTe;Zm4)!sA`t!V?G`S-2ps?kfXCoDs[+?j=dToDs[+?j+pZoDsi=?j<Y4!TXHk!h=03mSa5k;Zm4(!W3'roE52q"BYd-"02J#oE*cT?j6E.ZiT5LS,oJi;Zm4)$qp^$1`q?I*!)R'ZWdi3S4kbUUBE[[";Geq^Aq18RoU4(;Zm4);Zm5Q]EA;'P]UsIE+4G*MZaI$!R,K`V#f'K,Qn5N!PAHK0N/)W=9JZs!sA`0!h9=^MdQ_3b5q6,/B_E(#fHc)!h9:gDc6cA]Li;4;Zm4(I'Wn+]DquF]QotI]E,hLPQSMu]E+5tZN6!c"1)A9V?cI8"9I9Y!L?Xe=9JZs!sA`0!h9=^MdQ_3UB0ul#_QLc%J0\^!h9:gT2Pjq!sA`.!V?G`S-2ps?j4^T!V?W_]3kj?"9IQe"9P*3!JXMU!iH*h"9]ED"9Z)2!k2)2!U:(e$i=D.9ECA/E"/iN;Zm4;;G8o#>7=1.6ihtAliEVM>7=15ItId6liGcj,Qnel;Zm4s>^n78;Zm4;!rN,O*)n0d4Bs-76t@PG"Df=d[!,FO7L#(c!!!S;z!ijckkYhTe"9H.;!OMu3"9H1=Wr^-A!OMt1o3_fUqZ4V<"S6"%!W)o9!PE2Uqd9K#"9GS."9IS%!U*Gb]3>\+#dbQQ"?Z^T"9^;5,]H,g#ZCj/%T<K51aE2L">p<=!)j"'!NT`6=9Mk3!K7-a]*(NC!L-)M0]N8"X9"i1!Je8o":Bg$Mug^>!L*]f#M_F_S9tRrN!dc0"f);)0Zt!&quNU@"Us/rPQVJLN!(:))?H'''XIh!MuWm;N'j?@Mug`qA-8"r!K7&D?ibmb"AAp@"9G<:!O,K*)$PtHZi]k&#)ma5"cNi-`"Y%X#ja_]$'YjO49Lfu!kVYF!Lu8'/MmSm;Zm4+,Qnf8>7<VN4=g]+"?Z^T">(%h1aFml<`9,(!)j"'=9JZ;!Q5*D_up+A?if!_!PAWSK4"c(X9#C.j8l+`;Zm4(;Zm5A;Zm5P"9Gk0]EA8K"BYd-j9#MfMZMl>"g_S=#O;E'!ONMJ'4:k<!W)o)]E?&Z?idS7!NZFY!T\/%Q;[nhlj!(__uYZ2!!!!2)uos="9PU6!PhV:=9JZ3!sA`0!NZ=W"9H1=Wr]j9!OMt1MdQS_qZ3c%"oD[."1&$8g]dR_?iu;f!PAU5ZX=#jWr]R0"1)A;"2b/HU][)ogi!;r;Zm4(blf"_*$bXfdfJK5&d/&)"9\eM"=sSg1iP@B"FC7s#ZCj/7oKNn!O;h2N!A&G#GbrD#ZCj/%T<K5"BYe#F9;XKS9'&\!JCRV$M7;=!T4NAUBCk(!L.PM+T[6!N!'LS">k0#Dul'd"9\ai!K7&oErhL.14o]d"9G$3PQAN%^a'$`N2q=,HiSNp_0g@j#)dj0Hi]IR?j5jiDZi09"9\aq!!06$zWh9\!;Zm4);EPp);Zm4+)2eW"";DPh">i4d"9_+<,WlQ849<&u"@HBU"9`I%q]8Z=!PpSn8d$1T;Zm4S)$Dc[8d$dM>9l<N4?NYV49S#U"9\jB$`m-&!JMGn!!!;Cz!ijEaW)Eg%@2os_,QoAD9ToT9";Et;1aGI7!PAP5"9_g0!NQ7>!sA`0!TX:BZX?LsgB#4p"1)A9#)`MpX9Gq<jDP/%;Zm4(;Zm4/"=+&),QoqL";CuT1aGI7"=s[R!m:]a,W5\m7oKNn2H'_]"BYe;ErhL.C"ibq!Ls1T^B=tXZN69kScP&W"9k:r>]Tq9E,D'I"9\b$!Ls2*!Ls1TP6$md!!/;uNfsL._#]c$gB!N>!L.+!b@CX<#_QLeUi-B8;Zm4(;Zm5J!PAG`ZijJ6!PJU:!Q5*D_up+Ao3`dDWr]R0"7on&"3U_XX9>k;jDP/%;Zm4(&GuR#bVpW>)=mt4r!AU,>7RG5"9\b;b5o%M2?C5h;Zm4K;Zm45;Zm5Q!PAHIZijJ6!PJU:!sA`0!OMmg$Xa#4",d3@]E=X2?idS7!PAWKUL452"9GS*"9IS%!*<)%zX6_J>;Zm4)!S\"'>W)uZOAc8b;Zm43!LsMlZUbFr;Zm46!JCf9"<SE_"2Ih<#lG7O"CqpiS,ouB]HdU\,Qne^"9\bD'F<Vq!JD^$>7:Ok"9`MH!JCKg!)j"',Qn.$%BBVJ"=.5k`!aXb!PJU;"9QdM!lP4DlX0bjP6/r5&rU-&DZg-S"9\eu!mGO\"9_g0!qZQt?lK1>!mF$D]3lP@"9Q5\"9S46$b0+<Lf4EZ"9QLKbQIs["BYd.!W)r:bXqD6!K*?J]HjOcoPXj6;Zm4)"9\mqj8t-9"BYd-Mus1c!gEfhMufGi=;-;t_ZUG8!i0cnErrEG*5_n9"9PrLX9$'=^a'$a"9Oeg4ECRoE!;F.irfFZ!j$>W+Te/:S-"oX!gI0r!gIl?WreLc_#fi]P6-sL!fR/=!gE_MHh.:!e0hk9Zu6'J;Zm4)=Q9^LKE7<R$iu"^<%XkL!K89,(fLP?\5NM5!r-70"9_sf"9m^^Dukg%ZNL;n!M"*0+T[N)KE7#74D\F,!P;PEJ5ZRR"9QLIbQIs["BYd."eu.;!JlqI"H*?*]EIh6oPXj6;Zm4)"9Qe:"9\j0"9S2t!NQ:OlN5Q=#0UBZ!ODk"bQc6u?j3;,!k]&]!q^C62H'_],Qn.D;Zm4K!mCki"9_g0!qZQtWrgcR!mCcJ@>eM<#5\JOoO3Yc?j*e;!mCkDo3_d/"9Q5_"9S46!fp7_=9J]L!sA`0!lP04"9H1=!W)r:oE:ps?iu;g!mCeBUL4+lUB:&jDMqm1,c_!j!J&p4DZg-S"9\eu"9H;:"7T4l^aoMFKE6`,>U0FQkYhTe;Zm4,#E&W6>QK]l*`E1E=9J]L"9QLE_up+SlX3ouWrgLF-duI<DZg-S"9\eu"9\^'is)G\&cmY+,Qq?\"@N9T,QXD\!MgtDQW""i,Qr2i"De+/>QLWG!N[OLaAW3E;Zm4,"9\dd"9QSA"<UPF!qZQt=9J]LqZ=tE@d@D+"1nX,b[TmG?k:-V!k\oQ!q^C6YYtZ-"9cpN"9F0$Dukg%P6:oF!L.O.+T[6!;Zm4+bQJ%1C]nMY!P;PEE$rO+;Zm5."9\h:PQ?hD0H9X$"9]@m*!)p8!R)el<?)I<!MfalXF)8r*$bXf!h`c0"9a*1"9HkJ!T-fY,Qn.$;Zm5."9\eY'EdPt!MgtD>7:P6"9^:A!Mfb2LJn<Y;Zm4,"9\e?b6.332?VQ$"9\aqbQF52"BYd.WrgcR!n7>Rj'Vob!mC[s]3l*F"9Q5)"9S46!WQ($,Qn.D8-B&Plra.0$(MV5PU$B",Qq?Q"=+#<"9G;DKE8k>;Zm4("9\bOF971q"9]SF"9G?HE%Rgfdf]])N,SfMCpO6F&-8#7KE6r5hZB8J"C*hd!nU?Rr_iq&2Fo>$;Zm5.UBCXjKNrI:ZWdh=!JFtb"9]uY"=,*g4:Jk+!K89,PU$Ag;Zm4("9\l%KE]Y"X'5u5"B5DZ"9FH,P].\U"H*B`"9G$3"<df)!JCK4!JG8t*4oSeScOKq"9`fIMZhX1&cne4,QpdL">g.d"9H.\U]J7V;Zm4("<7L#6ijY?"B#8Rk>MKd;Zm4*"9\pp!!`0rzX,/&$;Zm4)"9\h:6j<'Y.C34eisi(("::S!<,a1BkYhTe>7<n$6o4tO"=tO$"9_+<"9sBT6j.9.)oGkg9I'`TE!>P1;Zm5&;Zm5J"9Iih!TXAc"9H1=#0R&.ltbWh?j3;+!SdnV!gIU+2H'_]=9JZkirSKL#K'pQ?s<Zu!Sg;"!gIU+<`9,(,Qn7_,QoA\;FDKu;Zm4+"9\n,"9OBX"Mdq=J5ZRR!JT80"C,2NdiVKk$kd)oF;4ou,Qn20,QnXJ"CqPK"5m)\BN#$:=9JZk"9IQdli[@&?j;Mi!TX<WUL4=ZqZ6$bgcJmIP]$[*;Zm4)"@N9W"9YS=!M<9nE'!"^+\W#D@73cl;Zm4C;Zm5P)$E'G)oDd]UBEu("AEc!Duk`XM?IQkqZK:f$B/p)"<gGA*+;6/(/k>=aAW3E"9Iij!UKqk!n1O%?m>^=!Sdjj!gIU+%T<K5^Jb7<!sA`-!L*Vt"9_g0KQ@14!R(ZIgB9?S!Ru'l!P\a?"9\bL!Q5#R!Q6d`!Q5"hZiQ*6!Q8:L!Q7H[!Q5#TPQAEQPQA]'?j""A!JCO/!Ru#jVGdU#"9Iij!TXAc"9H1=?qUO]!UL$&P@+O2"9I9\"9Og+g]17Udp!4a^B=Z]"@PWY"9]tqlN,j@bS"G\,Qp4<,QorG9k4BS;Zm4K"CqQ-"9]\i!gXBrC9(B?c;OiK;Zm4)"9\b6"9G])!gEci=9JZk!V?KtoE52q?j":IqZ<!4PUg,B?ul,G!UL&lgL(8E"9I9["9Og+!p<JbPQM$k!V?Krli[?i"BYd-!W)oilibdF?j=dT!gEi:dpN9iK)t<A"oD[.DZg*r"9\djZif_pFqEF:!!!-!z!ihLj3)]q_";q=^,U<L,Rp-:PS1GWa,QoY!"9\iZ#,Df/S0AK^;Zm42Z31:?!!!E.z!ij!ROAc8b;Zm4*)$Cp->9"mk"-`ob"=tf$!iT$##ZCj/kYhTe=9M:uF*n)n!JCSDRfkQh!K:tn!P_;2bQIs"g]>.m]FCYC[!X20!J#Ou@abR8S4!mPr!p@D%+HL,!i-:\b7Er`@KZ74Hj\YVU^HI$"V:58!K!j6Hi_'2PY;;AX%[mA!S^uaN,Jh];Zm4("9G#.U]^_3"BYd-Wr]:)!NZD)P@+FgUB-ki!m=sT!W)o!U]uHZ?j;Mi!MfpP"-[+;DZg**"9\bL!LsWu"9H1==9JZ#Wr\^n#D6Cd"eu*oPQZnPV?`=d"9H^I1cA88KC`:UHNYSp>9"mk";Cp$]E6S.]3>[JHNYSpZ31:5*K1C-!Lt4L"9]FW!!1DEzWfdJb;Zm4)Jcl3!2ld>f":PnO"9^:b$j!X:%T<K5_[V8-!=FJ\!!!!&Pm79h"9\e+"=-62*%V41,Qa06">hA,"9^;-'Q>/C/0k?4">p<5#ilQp":jJr!"Mp1zX7[h?;Zm4)40&ji6js]E/:8]G!JD^$cr1&M;Zm42;Zm52#1E\$,[:D,cr1&M;Zm4,"9]%@K)qWD%!?B3HmAh?KHp[?^a'$`"DhlT"9]tq"9\^'N!ZF]"BYd.Zi^F6ZN@K8#/agL"PX!:qurj'Zu6'J;Zm4)!Lj/#!Q5(r;Zm4K">g=Eirj0D"E\Sd"FP/%lqUI^:(jWG"9\koa8splb>oko;Zm4,ZNLN3!JGDr"<hji9OVaZJ5ZRR;Zm4*P6;#="=.qn!K^4_>ZV*P;Zm4K$jrdg1b#b8"EYmlHuM*PDc6cACa9-7lWXd>^B=Zj"9`NA"9G`*!S10P9I'aW!@IC@;Zm4K$u?0!*!3GL'MMqO!P;PEVc*^$,QYmc"9Fum"LqA5a&<*D;Zm4(#_N>s,[:P`n5BGm"9OM_"9\j0Zi[T:?iu;g!fUQGgL(&W"9JE$"9PrKL&b-TdoI^q;Zm4-"9\t."9RL[#3\tg=Ao>*]`\Ci!fR6_"9_g0!ji%4!W)qOZkf]Mo3`L=o)ajS#J4AjDZg+="9\e5":*:P"A_r!5QTF=LJn<Y"9O5XN!'0p"BYd.!W)qON$PH3?k%_i!W3,U!jlkKW)Eg%;Zm4/;Zm5!"9\hR#P;>$P8%d8!l"bu"9`6n$d;XM,]EsWZWdiS@;JmE;Zm4C!fRDH"9_g0!ji%4",d5fN'$'-?j<Y5!fSYIUL5I]"9JE%"9PrK!Ou&2=9J\a!gEfjN!'0^?j;5b!gFUeP@+FgqZ<!#DMqm'DOU]dr!pVPZu6'J;Zm4)"9\nTMup?g"BYd.",d5fN!-Ip?iuSo!W3+j!jlkKVGdU#>7><M6ii1G"EYmlHuK,`aAW3E;Zm4+/-H!GFE@Q!N#Z8BQr=+q;Zm4)!NZI'"9_g0!Rq2SErk&!&DI>0!TX9TDukk"oE5W!"9G>"!Pfr`6DFS:!M0>Ij9,M="CuQSCi]XD!P\a?!Sd_:gg^BGgcLDp!SdYU!Sej9!Sd^l!RuMW!Sd^?G3]11S-Qr>oPXj5;Zm4(Cm+mu,[:A3r_iq&"9O5X"9\b=!ji%4=9J\aP6-C?"J]?0"j6tS!fT3Kqd9S["9JF)"9PrK!o?iY=9J\a!gEfjPQV#f?j=dU!fV/h>@958DZg+="9\e5V?-0bK2s6$VD%NH"=.4U".iEo,??';/lMlU&o:RK8d%Nj,Qng/C]jcl$u@1`6oj"+"EYml".rKpNHr\M$u@0i>]>U*"EYmlHuLcthGXO[!sA`0!fR2fZijJ6?j""BMuedQ?ibl]!W3(i!jlkKmSa5k;Zm4*,Qnfo"=+#,1]`gdCi!)sFCZX""=,5q#)6%Z"<hRag]<T0C]Tb%E*;c8;Zm4KUBC\m!JGCq"<hji'Obg"E*B:F;Zm4K,X)=e">B@I"n#:lE'C<*"lf`5"9F0pF9E+r4;;4?!P;PECa<g2,RU%e"?[+Z"AF1g/-1DL"9_V=!ji%4]`\Ci!fR6_ZijJ6?j""B!e^X(dpNB<,6Ef*r$T*aZu6'J;Zm4)!W*!0"9F0pDukg%gB7P9!L.O(Y>YQ,)$F1KV.9]3"9\i."9b&i"J8TqzOp1md"9\e+#5ea*lp;8J;Zm4@)$CoZ>7;b[,THll"9]EI!"8n6zWg!bh;Zm4)%ch^;,RTJ8"9]SF'QA?@ZWdhhS1Goe";DgV"<8s</0$Jl!!!."z!iimQQr=+j)$Co[%dY/</.I7X#+Jg*:f@K"OAc8b"9Gk2"9\j0"9I9[!NQ76UB0-Q!OH/A!W)o1!OPL-94.nO?m>]Z!Mfki!ShSr%T<K5!Lt\T>7<>>1b;7g,QoY4"9\iZ"9FT_">3UU!JhNpHijKS"BYe+Ergps!K7.L"9FI&1ii\^eO>B!"9kS%liFj(^B=ZL"9FG^P].#j!JCRVGEW.QKE)%+KR;GSKE8miHiim?!JCK<?j5jq"@NFZ"9G$2!KU.^!O;h2;Zm43!sA`b!OMm_ZijJ6?idS7!ON'3]3k`aMZMT;#.n7F!qQH"U]mN$gi!;r;Zm4("nVi(!LFc'!!!;kz!ijEfaAW3E;Zm4)!sAa'!TX<@j9/Qf?j":I!fR0/4(&/K?kWS%ZN9,K!h3R$!L!QFe,bb@N,Jh";Zm4)$N't@!Mg<\li[ET"9GP(Mus1c"9IQb!UKqk!qTeE"j6t+j9"p\X'c;9"9I!S"9OO#"?9<_9R'J=!LX2R!rE#19EC@t]3>\+>7=1+D7]h\9EC@t+B&CG";q>1j')pc9Jcd5"@N:R,[XIQ!P;PE]3>[pMXprO";GeU"@)qijD\$#"BYd-Mus1c)Zks"j8k`X?j5is!Rq;=!fV%#Y#>H+;Zm4(,QoYg,Qp5',Qnf\;Zm5.,QpL8,QoB';G8o`;Zm4+!sA`B!K7&d"9_g0KQ@1,!Q5*AWru+;$++>N!P\a?"9\bD$d8Xd!PB#>ZN7]=_#_2TMZLHkPQA,mMugQl]3l!IDZkFi"9\bL!!!L-z!ihFf+B&CG";q=N]3>[XO9?O("9]D>"9]97&B#&WbUsCDZ31:M!!!E.z!ih[r0N/)W?rR37">h1DqZI$>1b<SRJ_OBK>801#"9\bc"9]iG"=t<e">i4d4<-a7"<7PB,W%n74A5dG"9a&S!'aBbzWg3hh;Zm4)2$>0q)$Co^>9"mk*%V/T"9m7Y"9^;%'Q=\[,U<L,%T<K5)mgTL'>spC(/k>=zeft.p"9\e+'ElKU,YTHd"B#E1";q>!>R5Sd;Zm4;F8H!R,Rb;J*)%U\'N?=\1gD:/"Crb\!iT$#Wr\.^!JCRV"9_g0XE+EL!PAO9$1)JL]E,bM!PAO?ZNPAk`,Ga?"k*ST"9H_c!MohH,QnIm!PAGc!PAH?P6&$/!OMl_!OMmD!OPJ*P6&#j_#^nk9*)C#!L*VD!JCK\FE:h7!Ru#j%T<K5BN#$:PQM$k!V?Krli[?i"BYd-]`\As!gEfgRpZ?1])n2u"/B6+"1nW!oE4\m?ig-*!TX@So3_fU9*+A]g]X*SP]$[*;Zm4)e/H7H(;'qU=Ao>*AlAg89I'`T"B%?-GZ+_J#_WH<4DY&\4?QU`6kgmL">hA,4E+J^6mMml=&T5)&j.0*.0L=n]EBKR,Qq'I4?NY[";E*a4E+J^6mMmlLJn<Y"9Iii!TXAc"9H1=PQM$kqZ6$b"m]Os!qQHZj9)_r?ig-*!gEeno3_U"dfJe:#2<MfDZg*r"9\dj"9Isi!WH"#zdiADg"9\e+"9Flg!JCOX"BYe3Erh4&9>^m#"9Fa+XE+E4!Mfi!"9`O^%^Z80+T[N)!L*]i_ZX4c!Lsfo!P\a?!K7&DN+2mQN#)9k!K7!Z!K9:%!K7&q!JCRH!K7&D?j"k_"AApP"9G<:!ROaJ&ZcYQ*/"?[#ZCj/:f@K"]`\AC"9\i.]E.'q"BYd-!lG'"ZiQ@u?j3;+!TX?HCL@;2!W)o1!PE2UlX0hL"9GS-"9IS%!g$=`j9#Mf"9H.9!PAP;MdQY1o)[nT"H-Xg",d3@]ER>'o3`dD"9GS*"9IS%":e?5qf#I:/.sKTS,p5)RfkhS6uW0[YYtZ-)$Co[,Qo(i>7<&.1^#hf1^!iT!O"K;X#*B=!MogK%bsq!gL(AP7KatE,Qn=i"9\b$"Fj>Q!TX=c=9JZ;MZMlA"bU1b!J:EcX9=/`jDP/%;Zm4(>7<%_$oC#O"EKE)/-3Kga&<*D;Zm4("9\b."=+d^,QoYu,Qn.Z'GMeq,U=W<!!G.^zX-+e0;Zm4)!e^TA"9_g0!NQ9\,6Ef,KEJho?ic_u"9J.1"9PZC!T6lZ=9J\Y"9JE'qud&6?ig-*!e^TDX'c"`"9J-!"9PZC!LQdgWre4_!e^[WKEPB[j'Z'm9*1%RKEC1A?iul"!V?JH!j$;C0N/)W";q>9]3>\+CU4-E"9^8p]*@It>Q_c1;Zm4S!QtS4/6i:M?rI125#VRe#lG+LWt"D,>R%D8;Zm4S$qpio"E;Og/9"aM;Zm9:HlN?P9OO>o4B*R//6jG'"Crb\!oQu[^f(@="9O5[N!'8c"9GP)#D3):!e_M#;p/Pn"2b1noE1:bXD\4B;Zm4)'I3_!">-*I/9#!\OAc8b;Zm4,;Zm51/-P_X"9a?X!RF[IMd$Th6o1l5"B5Dd/9!$'cr1&M,Qo(i"=+8k">k3G"9a)tN$NXH&'S#[1aE3'/0k@'OAc8b"9O5Z!e^\Yj'W+UUB6)O#J4@GDZg+5"9\e-$rh.D">TLP;urLgPXKknRfl[k">"L2"2Ih<+B&CG"B&2]!N8SJ"9^8\"9H;:(N*.Sb>o.D;Zm4("9\boKE7E<"BYd.]`\B6!W3'$RpZ?!MZSP8E3!@ODZg+5"9\e-"9G,n!glmhX9/S."9O5X!iuN,MdT8KqZ;FB8W-sW?jd$h!iuU$]3k`!])mX'#4#YcDZg+5"9\e-"-5]G#,>3Mk#2Bc;Zm4(;Zm59<\,m?"9_0*49L=:Rp-/W;Zm4Y!Ls7h"9_g0!NQ6s!R(ZLe-(/?"E\\cP]0:U!P8I>"9IRSe1Ujh^a'$dUB/jFScR>-"9I!Qgi-_t!R(ZI<kAJXbQ%[fbVnJ^bQ5N\UbD<?bQ3q/b5n+6LoXne"9FG^"9Ik-!hWBof2DeTSd(qk">!d[!Oku1&l]P9"=sW@">jX7"9`NdScesjX&^bR;Zm4+!!!'"z!ik6%Lf4EZ!L*]i]*)A[!M"*L!P\a?"9\ai"9QA;/8tlqUa-'_$EPcb"=-)T/1a17MZa/\!L.O@\5NM5"9HFBbQIs["BYd-!ODgF!R)3bqd9T6"9H.="9J.5"=R1O!h`Hp!Mq=M,Qo(inH:*o/0m=Y"CqX5"nVq"!La[S!LQ"8!O`#n;Zm4+"9\bX"9H;:!N7K["9\eM"9XHY3+c(l!L-1Z2cBh^=9JZKZN88Q"S6"%"oA>E]E=@*oPXj5;Zm4(;Zm4fPSMYS!e^OS!L-99!L*W$P[jmfA-%nqb?tA:DZj#?"9\b4"9Ffe!Q\1B8d#3G"9\ai'I6aY"=+#<N,WFa;Zm4+"9\as"9G,nP].1d;Zm4(;Zm5Q!Rq5^_up+A!PJU:!sA`0!R(T:bQM#N?j3;+!V?EIo3_[4dfIAg"H-Xj!W)oIbQNi3?ifQo!PANX!VC:5&5r]7p/;(s;Zm4("=+#G#E&^&*!*u1-W:-NoE,4!"9H^I!V?LsX'c$fZN88S#-2,4?ul@m"9H/V"9J.5!f'\W#4*5O*i&grErhd69\T\l"9G<;XDe?l"k*ST"9GlKS,pDNPQ@9TPQ@rgPQIHX"9Gq3<`9,(zeeJ/b"9\e+'EXY#!OrpKOAc8b!sA`/=9L0SF'JhN4OXF<":tEL>QMSB"3`j-b7FM2!Pr"R>\*_:)Uhpk>QMZGPZ.^R_^o$n!omYnA8_Sjn5BGm'V,p>'EePPS-n%d!NH8/DZg1WDZga_E<HCa"eu2'$j6uX"9\aq!glmh"CWhi%T<K5U]U`&=9O!P]``E[qg8MI!OH/7!p]l_F9B]o"3Y's?j?LU"De5$"9G<:!JXMU0N/)W!K7]qN"cC''Ef*N"<7H$,QWi<!K7]q;Zm4SKEM=+"9GP("BYeSU]U`&"ljt2U^#"M?t@F]!JC[#b?tM6#/bfmHi_u0b?tJ-DZjk]"9\b$"9_P"":QDO'EeOV"9\b%"9FGaY;QLd;Zm4(;Zm46"9\b^)l+<L!L*fT"9]%4"9_M!"EY\`HisJ`F9G\KRpZ9o"KQnTC]T/r!MjW:!)j"'!Mg,,E$GJg"9QLU,6Su+":c\r"r%)q-mToT!!!EY)#sX:"9PU,"B\S*"9;@'!Q5'CWr]"!!Ls8nS-2ps?j;Mi!Q56/lX0gQMZLa$!qTe'#(lrPS-&:i?j;Mi!K7,]!N#qZ"9\bD"9]Q?(ZZ')]H%^alN@=s49:6="9_g0"CqT;"AElQ"FP94r,?c$"T&<*"9F0p">0hI!P\a?KFWZO%fCMWKE7&/P\ae2`+NleF9nZKisW3t!PrSHA-Rs.4DY%_P@+TIDZhTr"9\aY";H#X$krg^'H-LH*#p4,!!G.^zWfdMc;Zm4))$CWR>8/%["<;oDDM&&n*!)9<!O;h2r#::t(&T9jzXr79?"9\e+X9&)pWWC<b'Ha[_'Ef9VN#X)G">p;gbQ@tN"9G"nU]^_3"BYd-!W)nfU]p'l?j?K/!R(`5lX0gQMZKUW#O>b%#)`MXPQ@7]b\mUb;Zm4(=9L_d]`^.pC]jkAF9Hu4dfac6!o.a!!P8lt":M:k!MogU^a'$cirjH)"FP.jK*3?6!PrS^ChWEV-(A]NC]V@gPV`VtM`beV"cHalN,JhM;Zm4(;Zm4/;Zm4/;Zm4=!!!!O"onW'"9PTd*%4_g*!@,^@aeNq,U<L4">p<-&VLG>"<5j*!"Mp1zWk]YU;Zm4)"9H/C"9\b=!UKmk=9JZCb5oNa!i'-*!W)o1!Q6d%dpN4RlN->S"bU1a#/^J[Zj).jlu*"-;Zm4(;Zm4/;Zm4W"9\c#&%iBN'HCO4/1`%L"9^Rb`,JWX"BYd-]`\AK!PAO9MdQ^`UB/:;"oD[2?kWRZ!ON'K!N$=-"9\bl"=*tG]*'r9"?^X*6uYc9!KG8*"AAj"<,cfW!Pg5h"9]+F"Di6["9\j0"9F_hS9"_$Uas%XgB"GX@*8[!_uZrY+T\)=S-d@A$iBu*!Lt.Q!Ls2,!L*eh!Ls1TZX=G_nH<(t"9GS),[OCP%b)@!P2cl0X;$$_"Tm`clmrJ8%&?`,.LZO:!e^m(]5@uRX96rh$fhHuN`-&``";PAZiP[e!!!!;/cYkO"9PX="5m)\WrgKJ!k\X:"9H1=liR@n"9QLC!mCdLHXI#h!W)r2lj'S!?iu;g!k\]kgL('ZMZUg##K'qmDZg-K"9\em6jg.sCfLYO4<t&G*$bZ/'I3g/,Qn.$!,V6p"9^hF":)/0!Q\1B=9J]D!sA`0!pg!T]3kcJUB8A&0CrQRDZg-K"9\emqZ;RP$kdY8KHp[O,Qo@n"AAiT6iiMt!LtD<Ua-'W,Qo(f"9\b,Znqb]MugTm,Qqod1fOLg"E\`c"FNlg!JEQ\N"dN?*$bXf,Qn.4THp:#"?\RC"LqA55Z7dg=9J]D!sA`0!pg!T!h3R:/&MG,Zj5o)lu*".;Zm4)"B5Q7"9_O;"9RL["-dR(<$VS\!Ms$(;Zm4+"9\n$#+,Gk3)]q_SehN/;Zm4("9\ad"9]35irdq44>m0SG>eVIQr=+j"9QLF!lP4DZX<h2])onR"/B6ODZg-K"9\eme-#2="BYd-Erq!tN!'0O!M"34ErqR/P6S*N!h;(NE-JnsPQV&`"9]kY4ECRo#MTO^"9PB<XDgAh!h9ApN!'8,"9]kL>]Tt2E-8bq"9\dr!gE`#Erqj7:t#P("9PB<S,pA-^a'$aP6-C<!!7gE@@I=O!Pnhj"Hrn?!L*W7!Rq1(]3p-;"9HG."9PZC"=R1O"cuXc"D\,CE(PZb6DFZ_"9_tK1]lQ549QN)"@R/29Q4C/E+n87!rE+""Me8]KE6r5;Zm4)8V7&@"De8Y".3!i"IpBg">gN"";H5/*!(^<!K89,(fLP?T2Pjq(BdD4"9\b86j'Vk!L+iLS0S4g,QqWY"9\b$"9XHY!pg!lWrgKJ!lP3BbQM#N?ig-+!pfrWRpZ?1o)ci2!LmHu".KA1Zio,klu*".;Zm4)"<7Hn/-1\T"9_VEA8k+mM?EtC"9_[)j9*\+Eu:,B"9\jtdfS-"2?EhA;Zm5>;Zm4V,Qo(u;H+oP"9QLEbQJ&N"9GP)!W)rB!lS#Fb@!p5"9Pqt"9Rq.!l%Y:CCHF1'LW8O/0#X<9Ph%>!P;PEE*ne39WJ:qK*5FuSn)dN!K%!^,Qnf\#ce)M"<;f."9F0$!V]Lq*$bY\a&<*D!mCcL_up+A"BYd.!W)rB`!aar?ig-+!mD%qlX0s]MZUfu@>eMbDZg-K"9\em"9ZD;_uN^="BYd.WrgKJ!mCcJP@+WJ_ZIa]G3`N?DZg-K"9\em"9`=8"9cG;!KU.^zNZnH'"9\e,"9Q)385Ti7Mus1c"9IQb!TXAcRpZBJ!fR/;RpZ>V!TX9=UL45B"9I!T"9OO#"di3k<[7jI"9\jc*!+tr<(nP?!kVYF!M!+W/PH:H;Zm4+.,tO,1^k!j4Bs-7"Crb\9EDpS4<t&'9I'`d^f(@=;G8>>O9^sP"=.4Q"lN;^">*:MJ5ZRRj;*s\bQ4%2;Zm4<"8DqR#Er16L/S3X!sA`-!TX<@N!*5cb?u7jb5pZ*>Phe4DZg*j"9\db"9_Iu"9Z_D6pOZR]*&uS>Q^W%;Zm4K;Zm5A,QoA.V,RRk"?Zef"9_sTUB/)8>QXBq;Zm4K"60Ms"<8\+$rfnG<!JgrZiQ[r;Zm46li[@?"9GP(=9JZc!sA`0!UKlHX'bu*)Zks#j9)Gj?j":I!Rq1g!fV%#``!!C]``EX"FL=QX98Z."AEk;4ECP1#MT^C!PAH(E!a,ZKEMXXg]Sc-`=(0%MZ`;H_#^VVo)Yon!!00EAZGj5!Pnf<"LA-1X9"Q-!NZD)Zikbt"E\\c]Poig"k*ST"9HG[b]!a7^a'$`])f8>ScQ2!"9Gk1]Pmu=!NZD)8@o!JX8i:&X9dP]X9$-<Hj$bV!NZ<d?j4`$"De-t"9H_b":.p/!Us"jf2DeT,Qd*0"9G8u"=I+N!esVVcVjrL!UKpjg]RYY!PJU:!sA`0!TX<@N!*5c?iu;g!Sd_AlX0bjo)\1Y"KPo3!V6AOj8l#`?j5is!UKi^UL4-"qZ5IQ!Ma$'"2b0#j9P9a?j<Y4!Rq1G!fV%#mSa5kI"MP&"?]Y&9I*jg$rd@-'EYmN;urLg">*:Mk#2Bc;Zm4),Qp4>;G8?@1TLW]*!_F(<(nP?6,QnX">*:M9I'`\Dc6cA!KYD,"=,73Wru*A"B9=V!,#45zWg*eh;Zm4)N$#\<X9$$S;Zm4E)$CoZ>9"mk";Ct8$oBL\,Qm(2"9a&S"9;@'$j!X:zKd$Ks"9\e,"9uY?"9GQN"BYeKEri'>!NZDtMZcFhZt]Vo!PAO9gB9W[!Q8p^!J7W\"9H_cPT^(?!Q5*LRflu;!R,Ku9EVp1,Qn.d!NZ=;!P\a?CP)Y`U]:Fk!KHsW!Pnf4!h04dU]H^-?orH2DZjT4"9\bL"9Orh"fP?&^f(@='EZbf1^2?4P2fb',Qo(f^B=[%"=,f)$mYt&/-3@e!P;PE!JBD8"9^Q#49WGu])h^A,Qo@n,QoYdHNZH);Zm4+O<Xk[">i">"5$NT2BN.P;Zm4[!TX9S"9_g0!NQ7fWr_Pi#*WEs"nMcUe-2m\N,Jh";Zm4)!Sdad"9H1=Wr_Pi!TX@ag]U^^?j)Ag!UL&\RpZ9o_ZAg'LoXng"9I!Q"9OO#"?9<_!Obo0";q=^>7LKU$nMFk"CB8U!PVJ8mo'>l;Zm4(#_N/N1c>BTcr1&M!sA`.!TX<@j9/Qf?j=dT!fTR[]3k`QlN-'8#E)snDZg*j"9\db"9GZ(oLDg_,QmB=;Zm4K!N6%g"9GqnLJn<Y"9IQa!Sdf["9H1="eu+Rj9*;-?jMAc!Rs_o!fV%#hbsX\!P8I8$p6@c*!3HN/-28'=Ao>*>6p0M"=+#+"9_+<"?Z_"!VfRrMus1c"9IQb!fR7aMdQ_3RfVRRMORuW"9I!Q"9OO#!Oku1!O;h2;Zm43;Zm4W&sNIC!KJ)J"<8K$*%Y>?"?\eH"9^P,"9O?W!rc+$pJV1t;Zm4(/#*0D1^k!ZliF^$,QoA#;Zm5&!sAa6li[BK"9GP(=9JZcqZ5a\N*BZj?iu;g!fR;XP@+F_qZ6$g#ErNr?m>^5!Rq:Z!fV%#%T<K5LJn<Y!!!!#)uos="9PUO"FsDRqcaaS.h"6:S/`=91]a*Mo32VcHNYl8;Zm4+"9\hZ"9]Q?"9Flg"5m)\'tb9OX:FS\!PJU:!sA`0!OMm_g]U^^?j2Gh!OMs@RpZ?AMZKm[#1Hr_"bQi_U]cT`gi!;r;Zm4('J'9p1^!VZKSs%CS2;2d$p6?I!JHA8;Zm3p)$D3K%L(Si"9]uT"9_Iu9ECeb"9H1="BYe+Ergps!K7.TUBGsc!L.P!E+@W*!K7.4"9\j4!JCKg!JE7]qZ2?M_#]3Uo)XLF!L-7_lVmn<!UF+oS8SN=;Zm4("=sSp'J'B61^!VZ:&A-'!Lttd>7<VN"9_Hr"9FT_!Sdb[Wr]j9!OMt1X9;W.!PJU:K)r%V"05f7"eu+2g]Z)6?j4^S'*5I5U^!l-gi!;r;Zm4(!NZ=I"9H1==9JZ3qZ3c$ZkHgJ?j)Ag!MfhP!ShSr7T0Em5>q[f!O;h2;Zm43"AAja"9\jS"9^)N!!/rqzWk9>P;Zm4)"=+#h$p6?l"<Z)s1]b>o/0k?TE*KpW;Zm4[0S9GB/.<.J'LX2L"AC'D"=-\u"9;@'!VfRr!)j"']`\AC!PAO9"9_g0!TX=c#O;E'j9Nk9?iu;f!PAZ\RpZKeqZ4&)"1qqA!fI)lX9O;bjDP/%;Zm4(N!t@n"9^V#"E%-@//M4f*!@,^%XASk5#VRe!NU#>=9N.;!L*]iS-26$!K;(#!KiiSg^'-`!P\aGRfib^$iC$S+T[f1PVfuT!L*Qb!L-QI!L*W$P\^QaA-%nq".N[+Ui-B8;Zm4(1^!i?/-H!M*'>JL"B#cc4<t%\"B%&rzr$_UG"9\e,F:"U=HmBs?":QOY;uqRR;uqNm"9_[:S-\=W"BYd.#)`PQ!KXj#%_De4N"i=#`,>b[;Zm4)"9]0aS-$V2"BYd.?s<]&!lP8KZX=$Mo)bEc!NTT0DZg-#"9\eE%uVQ/<"]PFA0_:OCa9-'peq:u>qAYM"B5T4"C+VG"CsV?"9]tq":;#*$]n9i]`\D$!h9Ao"9_g0!NQ9tqZ<PrHE1ES!S[[?S9h5D?j*M3"9OO'"9QM[!g$=`A0_:OCa9-7F<guW!J1F_;Zm5N,WlHj"E\`c"FN<W"9]Da":CMp!LH^fLf4EZ,Qo(g,Qpeg"=+#$49:Bd!L+i4<)l=[fM_nUJclJb$(Q)<4FACW!JD^$N$JN_,QoY!"9\aiS-YcdQOhji/.8fc1gD:/1h7j74?QUp6mO#\9IqFl">hA,#aeNn!!/"a"9]Ds"9eKugE9Dt&dm,i%'1F2"=-Yd"9_[L!h=I5PQY(k!PJU;qZ;ub,5YaP"G6cGN!-1h`,>b[;Zm4)_up.V"9GP(=9JZ;!UKpl"9G<>4ECPqE!P,#$FC66KQ&`j!V?Kr:W!;Y!Png/K*25I!W6nd+T^p4loCgD!UKde!UO.a!UKj'!Q5#6!UKiO?jd"J!NZLc!ebIphGXO[;Zm4(#il#J$03?7/0k@/9I'aW!J1FW;Zm5&"9\akPQS-g!PJU;"9P(r!gEgiK4"i2b6"1>'@U?:DZg-#"9\eES-,uo"BYd."H*>OS3`?H?id;0MueXe`,>b[;Zm4)"9\ks"9m^^!lP0D=9J\q])onRG3`N<#3,cTMuqI9`,>b[;Zm4)"9\f*S-$V2"BYd."1&'!`+nUG?j""B!h=#k?ic(I!fVDg!lT![fM_nU,Qq'I,Qq@',QqX',Qqp?,Qr3O;Zm4k"9\e)"9\jC$k*0B'Ef9V">k$"49:$:mSa5k"9P(pU]^g&"9GP)!W)qoS-Os[?k9RF!fRkP!lT![=&T5)Dc6cA2H'_]k>MKd;Zm4("9\hj49_*N$e-F)KHp[g,QoY!"9\aa<!;\h"NVA^?W.(1Wrf("!h9AoU]ad&b@"NUdfQ$A#Ld&^DZg-#"9\eE,QsH4!L+i4<)kJC4<t&/O&H/a;Zm4+b6.q)"C,n*A8iL*M?Esp"FO/L!JDF\"AC'D;uqRR;uqW0"9_[:C]^J4/1`%L!LI9E7Z.BX"9_\C"?^<q"5Eq6PU$A_,Qo@n"De+/"9G;D"KkZ+]`\D$!h9AoPQY(k?j3;,!h:Xe]3mRm"9OMl"9QM[!e=2P?;gt0<)l%c/0k?t9I'aGA0_:g4<t&G%T<K5*$bYdD[_R-Jcl3M2hP'11fP)e/7^"/6u4+O"EYml#)6%ZT2Pjq;Zm4+&+g"VUEh)f2?]UJ;Zm4;!gEnM"9H1==9J\qqZ<8j#J4@I!W)q_S-ALlb@#Am"9OMi"9QM[!qoOqQW""i,QnMWJclKm"AEV4"9`fl$j=mT!JD^$,QnL."=+#,49:Zl!LtD<Ua-'_;Zm4("9\i$Mf\uOF:r[XKHp[g;Zm4("9\h1S-H]+"BYd.]`\D$!gEfg_dEZ.dfQ%H?c-7S$bHJ1N!m7*`,>b[;Zm4)"TekZ!!!!:Op:se"9\e+(&S>9!N[=&"9]%T"=*tG'H@5n"<8[#"=u)L!!!-Zz!ii[JQr=+j=9M"mX%WX!F9D^I"9G$6"?^aQKQ%*YlNNLRMuefQ]E6:XMZb1)8I2CB!JCT'P6=!h!K:t$E-'J2KEM=?"9]kK]*':!F9$E1_/s\?#1IYpF9.V"?j4/1">g1T"9Fa*"E79B"9;@'!Rq2S=9JZ+!OMt4U]^_!!PJU:qZ3Jq!S^u_",d30U]K4X?ig-*!OMufMdQaIMZL0f#0UBY?o%hb!Ls>Z!Ru#j-rU6O#j_lI$kV2L9*?+8$j"0YQQLi""9\i."9]!/";D>EirgVQ/8tWJ+V3W:2$=m%!!rZ/z!ij]iQr=+j$NqFM$A8Yc4F@2,U]ijpE;Kb>1^$3c"9\iN#P;D&oG%DF[Oa6A!L+9!!Vd/cM\JOr"=u\:"2Ih<j9#Mf"9H.9!TXAcX'c%AUB/"0"05f5?m>]b!NZNa!T\/%%T<K5#ZCj/J5ZRR"9Gk2]EA8K"BYd-!W)o)]EPoT?jGuu!PATJlX0kMliF0mj8l+^;Zm4("9\dn>QKK["9_g0FE7JAE%\I"]*&/!!M"*0!P8Mo"9as.Mug^>!L*]f"9GTFCi]WI!P\a?"Pa$B!K8@1$.K!7#.su@!L*kK&#95h"JcLFX9b=@G6cV.$hOIY]GL[.r)A:O!K8B2"QTTB%[7!h!Q5#/P6@rj!!/#nHJ8IZ!Pneq#0R%+!L*V<Md-:A!omYkUi-B0;Zm4("9H/)"9\j0"9IQc!NQ7>"9Gk4j9,Ls?j4^SK)r>``*6US>@8ZV"KMR9X9IotjDP/%;Zm4(;Zm4_"=+$1qZI$>/0o0;L$MqO;Zm4(,QoA02$>H];Zm4+;Zm4f!!!"2#ljr*"9PTie50'H[LqR;/..mJ1^"[!+8]7N!Lttl;Zm4;>7<=g1b9aG*#o!L'Jq'<*'>JL"9_UZ!#AK9zWjs&K;Zm4)":P@QUauOuG7;t,&&\U(1k,e44q,(<#D</c]IOHP,QnMV;Zm4c";Cp)oE53EG7UJS"lo^6*-MV3K`^$4qu_TQ"V$t'K:<"F*"j4l%T<K5"BYe+HijKSErgpsN!'0O"C-!KP]13g":qj?!K7&o!K:7S!K7&q!P\a?(:+7)KE)%+KIi;fKE8miHj7ap!JCK<?j<Z2$L@uGb\mWK;Zm4*;Zm4'!OMu!X98R)"BYd-]`\A3!Mfi!lX0bjqZ3c%"g_S@"H*;VZj+-M?ig-*!NZL;]3kZGK)r%X"bU1c$L@e`!Rq.I!)j"'IT$@PDc6cA/57)e!O;h2e/$7:*/n/8!!rf1z!ihFi#ZCj/94SO."=+/XZNLCK,SY36'HAA$*%W?<*&JoD!!H1NzWoP*!;Zm4)"9\k+$j,osUgjU^3BR]Y1_^%m"9^hs,Q`d#"=+m*!ROaJJ5ZRR)B:");Zm4K;Zm4=!NZBrX9;W.?jD;b!NZJ%MdQUE"9G"r"9I"jUhE[0!PJU:"9GS,"9\j0e,e&$?ul,F!NZ<cP@+L!ZN6j&"7on&?m>]R!Ls1c!Ru#j%T<K5";q=V*,m,*Duoh="9]#.,QWEo$G7Ve">p<5AlAg8kYhTe;Zm4)Wsf'6/-39`\HAlH1_qnK"9^7d'E[Js"04FER00K0"9]\F$st,UZiU&)\HAlA/70q/"9JC#?8b^b!W,n+OAc8b=9Mk1Rgnum?HWWh!K8o%$2agk!K:.0MZJb:!K7&5!K7&qP["En>QKcaX'c%!DZi`9"9\aiX9$mN"BYd-Wr]R1!OMt194/!W!S[XV!N\q%b?t@?"9G"s"9I"j!Uiqi]`\A3!NZD)U]ad&UL5;IUB.G!#/agLDZg*2"9\bT"9]!/pAp:Q'Jp4!N`-&`"9GS*!Mfj#"9H1=?m>]J!NZIrRpZK5"9G"n"9I"j'JNGg":QOY!l%Y:%FcH[?3nJ)!W,n37T0Em:/_8u@k8"`3A_.$WuM5B*!)H0el)\S!!!!#,QIfE"9PW]!q9+k\5NM5CBObDr!&Yo$j!:-!R)kMo)[&8_#_c$b5offPQA])S,ph7?iul!!K7,]!ShSrkYhTeU_(`O*:sm\,Qn4&;Zm4['%6l;<"'CE1i+E?/9E-?*.0"7!JD^$>W<][,Qn@*,QqX'#X%,u"9]u."9\Et!e=2PYYtZ-;Zm4,"?ZbL"9dX!!K^4_2@*48"9\tZ"9^AV"9X`alpjtW!PJU:!sA`0!V?G`li^Dn?j5Qk!h9M]!pa55".K>`!TZ=M!h=03G>eVIMd%/P;Zm4t!R([Z_ZX4c!Ru'A!P\a?"9\bL"9F$O"8Gdt";q=^!Mq%E>7<%c$oA!s"9H,=4E(MrE%J$m;Zm4k"9\h:"9\-l!QS+A=9JZs"9Iilli[@&?ig-*!V?VT_dE\\_u\p$S,oJt;Zm4)"==03"9H_=!m":CS-&ls"9J,r!h9BqK4"l+P6(:Y!Ma$,DZg+%"9\dr"9F<Wj?HQGp/;(u"9Iii"9\b=!h9>q=9JZsRfW-aCZAe)!W)oaS87.m?iu;g!VC0fo3_]bliH0=S,oJt;Zm4)!V?E>oE88!?j+pZ!V?Ss"oD[P&(CX@!h9:g%T<K5O&H/a<!(&@"9d1S!WH"#=9JYp!sA`0bQIsbe3%dQkQfiGoEU<U!K<KOliGmh"V-1ebQJ$LUBD_@8HI%Te-#fr!OQnKErk&!^B=[UbQ62o56977!lk>c!O`$Q;Zm4+!g`u>#Er1fDGpZ@E(u5n"9\bLqZJ6Ep.TE1!K%!\;Zm4c"9\e8liX[[!PJU:"9J,t!UKqk_dESIirScVj:bo)V@MA^"9P(ols<Tn!PJU:!sA`0qud(k"9GP(=9JZsqZ6Tt"Og`Z!W)oaS-7;K@!7G0!V?NDK4"e^e,eV9S,oJp;Zm4)!!!!7+ohTC"9PUX"FsDR:f@K""B%o=o*Mct"B6'9"9c@_!k;/3Ca9-?/58e@,RU%UUBCo$,ZJ_%"C*2TN##=p!PJU:"9F_i%J0d*_[0M9`,VP1g]>4l`*\E*!Q4s=!Q8`2!Q5#T!K70Q!Q5#'#290CKEJ8_b\mUb;Zm4("9\bX6ikq=*-<G/4FACW"ADf8".3!i=9JZc!sA`0li[BK"9GP("OdD4N!FuC?j""B!UKs<dpN4R])gsq!h3R"DZg*j"9\db:"')@,Rb;Z/6jG']OW8jCa9,nQW""i9FKk]"@NY2";G)d"9`6\'EPX@"AC'DbQ4.X,Qo@t;G8?@;Zm4+!UKqKj9,La"BYd-!W)oaj9Ee8?j=dT!TXI.ZX<s3"9I!U"9OO#"?'0]!T$`X]`\Ak!TX@ag]U^^?j":I!TXHCqd9ND,6?j0!RuI(!fV%#%T<K5";q>1!S9QZ"?Z_'j@E2P"BYd-Wr_Pi"9\i.liN+Jj'Z'lRf\NQ#30)c!W)oYj9FXPb@!sD"9I!T"9OO#"<LJE!N/j!?W.(1$+(E=$M4A'zpE0G9"9\e+F98sN"9_g0<-&)9E&Eg^_ZU"A!ONOnE%h(k,Qn.\!Mfb3Eri?FP73[<!OQeLE,POUX98R:U]_hA)?Ho?D3G!rU]:FkUh&clU]J:4F9^J#!Mfa\?j>Y5XCMC]]E+l2;Zm4(!R(\n"9H1==9JZS!Sde\bQIsI]3nhDqZ5IS"1qqA#."?[_uZW@V@3"s"9JE$!k;/3!J1FW4DX7FX9:Wu!jm.[%\sWRe1=:C#`LqK!JCgH1]l_g,ZH#l"C*2T!glmh$IfOO#cepj";Eb$"5$NT^f(@=]FWd!!ji@HaAW3EKId6.!R*(q1jg[g!Rq;6"::k-!M<9n/0k?,3+i?s";q=NP]$[=!P9T]"9\al!Mp*UdgM*;X>G;b"U`H^"9\b<"9_7oe,f&;"BYd-Wr^uY!SdeYP@+WJirRX1CZAe,DZg*Z"9\c'1^J;("9HD@!oQu[!SCbs"9^PdquP\R4B3p<'I3fD1aE2l,U<LdSl5ap;Zm4)!R(S1"9H1==9JZSqZ4nD>Phe/!J:F&`!!tcr,2]=;Zm4("<7Gt"?\dl!Rq60"9_g0!W3$&?lK.E!Rq>6UL42QX9$6@quNZ);Zm4(!R(Vc"9H1==9JZSK)s1!"5@2g"G6a)`!D!'r,2]=;Zm4("9\eO"9G])!k2)2!J-F[1^jDO1iOnmO&H/a;Zm4);Zm45!R(SJ"9H1==9JZS!sA`0!R(TBb?tAJMZN_[#D6Cd#O;E?e-D1F?in4H!Q5+n!W6j=?W.(1Io?IQ!$MLIz!ih=c!)j"'";q=^*!(of";Cm$$j!X:*4-NH!+Z,=zWp_&1;Zm4)RfibJ!MjZrJ5ZRR;Zm4("?Zjd7dD<F/2d[I:f@K"GZ+_J%T<K5Wr^uY!R(ZI"9H1==9JZSb5pB$#P2=*!W)oAe-GSQ?j5is!Q56/!W6j=+B&CGE)QlB#ZCj/:/_8uYYtZ-"9Rcf"9G;je/hNk"BYd-]`\A["9\i.bQ7VD?ig-*!W3+Z"cHb-"j6rEe-E<f?j+pZ!Q5,!!W6j=-;t$M#m:a6"=+)2/-H(n"9\b%,]FOZYYtZ-;Zm4)!Rq1Le-&kV?j)AgMZM=;`#E(fr,2]=;Zm4("9H_Je-#fc"BYd-qu[')qZ4nA!omYh!V6?ibQ?g4?ig-*!W3"gj'YTNCB;of`!,I7r,2]=;Zm4(X)nIE"De2AS-/ss"B9FCFE7JYE':fIMZa'^!OQeH\,j5F,Qn5N!Mfb3Eri?FZigE2S8<6I!O`+4!MfatXAAqnU]I%f"9Gq37T0EmE'9s!%u^Oj"<e$*!LuUEqZ32e_#^'/gB!fF!L.[0MeiEa"3Y'U]PdpX;Zm4(bU`9E*"3Gg%(%8_9I'`T<$VSl1fYMH/0k?T5#VRe[Sm;3?Q:m(49P]F"?Zf-'LW'*1i9j/"9a&S"?9<_4ECP!E!;F.P6:of!OQeg+T\AA;Zm4+0&$Ea/2dO,Y#>H+!eUUW"=,73">hq\%a5&5U^71j!#u"Qz!ik9&TMksr"9H^K!Q5+C"9H1=oE,4!gB#M!"bU1`"1nU+`!(d$?ig-*!Q5-$UL4-"9*)s5bQcO(?id#'!PAQA!VC:5fM_nUMPC:V*(4`H,YTHd_urt#!PJU:"9H^Le-#nV"9GP(!S[Xne-5GO?ig-*!R(`=_dEPh"9H.;"9J.5!Q\1B:K%B!!)j"'=9JZKlN,34"5@2g!oj=*!PB(R!VC:5OAc8b;EQ3+"9H^Le-#nV"9GP("3U_pbQODC?j3##!PAH.!VC:5W)Eg%,QoY"<LX+R"<9gK"9_CD%+JW_"DARi!QbHa">gV\$qs&74<)aR"9a&S/8tgb?W.(1Lf4EZDhA/o"9G$3!LQdg!)j"'#ZCj/%T<K5"BYeCPQM$k!Ls8n"9G$6Ui7XOq[9J+XDe2qS-?8#MZb1(3WYaf!K[>P!O`$!;Zm4+*6\H']P/G*!Ls8qP6>uK$d<Q]DumQRo)o)q!OQeM!Pfr`"9\aq"9_P"1]dSS/-HgndmsOq;Zm4+07s;?S,`YeS.>,kS,pG,PR"f$S,niT!m>B\"C,_M"9GlJ!PVJ8S4Wok;Zm4("<7K("=-)T$qs&7Zk&?AHO\1",QoY$;Zm4c!!!"2)uos="9PU6"9;@'!Sdb[=9JZ3MZMT9ZjU7D?idS7_ZAO#'4:it"mZ2r!MgrJ!ShSr?rI12g]IZ^"9Gk1!Sdf[!OH0L"S2Z$U]](Rgi!;r;Zm4(M=Ubh!L+i1;2YPk"=u*$/-H)\/-H!M"9^Rb":.p/";au><."cNiriHe!JCK.$f_9_Erh4&"d9'O":+9DS8]5/!K7-^!JCS!KGjlMKP'fV!JCFR!JG'K!JCKiP^ES>;uqXQlX0keDZiH3"9\aq8>AFK,Rb;:/3G0\"9a&S!L?Xe";q=f`-uS#"9]\F%K$c9S3@ds;Zm4-;Zm4u!!!"#"98E%"9PTc$m8IO!LGV60+7sl"9\hm`!c[PGQHS="9\h^%0@#<!!!!&V$[2&"9\e+,S2Y."9\b6!K^4_"B%&rE'3.`,QoAL;D]@U)$DJn%Kc5)"9]Ds">jLbgB8cI,W'I<"?[q4UE3>:$kbB[6mMmd9I'`d!Pfr`,Qoq\;Zm4KA-;`V";SRK,Y(c9*&JoD"?[q41]b>o<`9,(zdjb=t"9\e,":251"2Ih<#fpP_".TCiLf4EZ"9S3!KF*kg;$G_U$_.I'"5G@7DHm\$"MANVX9A`[^B=ZF!JGh$MQ9qi;Zm4(U]^q,"=-\B$b0+<PU$AO,Qne^'J'9T!h9Bk"9H1=Wrf@*!i,r"S-2ps?ig-+!j")VX'bu*;Z`aKPRk*.b\mUc;Zm4)"9\ntq[/E`$kdr##h0C7oF?h(IfctbU`9Do%%KKj.jP2W"C)7lA-%o?!LtD<Ua-'W,Qq'I*'=8'"9a*PN!bYF@0)#^$iu$/!JR"IN$JNg*kMOU"9Fa+S8\[j;Zm4("FLN;!JGP?KHps'!K5\7F>a0(J5ZRR;Zm4*;sO\PS2LGI;Zm4("9\e9"9Z_D*,p#3el)\SNf+#@!JGCmE$LhTMZa'>!L.PIM?F4CoDsUGC_*<L"9]6g"9QdL!NQ:'"9P(rU]^_3"BYd.#5\J'bQ7<C?indY!h9;_o3_[,dfQ<G"05f4DZg-+"9\eM0XE*)F>a0Nc;OiK;Zm4(ZNL<,P]-Y["3UfJ"9G$3"<df)!JCK4$m^4/6ijo(!P;PEcVjrL"9PA"!h9Bq"9H1=#0R(<U^)N[?j;Mj!i-'RMdQeMS-"ofbQ4RH;Zm4);Zm4?)oDc^S2LT@;Zm4(;Zm4o$js?ObQ>+T7g.$?U]^OBA-&5%3![)1%a5.DoIC?';Zm4*"9\hj"9ZG<"5$NT!Mj7Y"FLUj49;f7!PBZ\AlAg8,Qn.$U^R)?%ub]A$]G/:!K7_B>WrDZ"b[&LqZ`iHF>amocr1&M"9P(sU]^_3"BYd.bQ@tNb6#lhA[>bK!W)qgb]\nP?ifj#!i1!tP@+UT_uc/(bQ4RE;Zm4)Nf*u<2?S[7"9\aqC]T>j"9]SF"9G?@E&Eg^;Zm4C!h9:I"9H1==9J]$lN3RZ!io]6&rQgeP]+`Qb\mUc;Zm4)"9\b@"?^p-"9FH,P].\U!ODn0"9G$3"<df)Y#>H+;Zm4)>U0?1UhnLa]3>[E!MhOl"@N9\"3=CD&puXU,QpdL";Clq49:Zl!LtD<".T_*!i1'>"9_g0!mC`L#(luQ!mF;F94.n/J("IpPZ,b5b\mUc;Zm4)"9\h!KEU12Y87<B;Zm4)"9\dV"9c/3,Qqlc!JD^$N$JNo;Zm4("De1+*!)i\!N[OLZm5c*<?ss5,QrLB;Zm5F!i,n$"9_g0!NQ:'qZ<i%"4LWY?qUQs!i,qIX'c*`"9Og6"9Qec!o?iYWr^uY!Rq5Q"9_g0N,o&RUB6AT!U9]A$hOM4KE7YIr"$FA$ab*c%u_mrbQ<H,B**_o",m?;]EJJWKGrkXKE8mjg]OkaKE7;<K)sI'!m=sUDZg*Z"9\db"9`mH"9mse!S10P+T[N)e,f1EKR@21;$5k[#/giG$g]>O$`!s%oIZhU"UUCp"?[$E"9FH,"MRe;hbsX\;Zm4+"9\eh!!8KczWg!\f;Zm4)/L1H1Z31:5"9],6#G_W(N!0^8)$Com>8/=c"<7K,"9^8$!!!L-z!ihFh!)j"'";q=^E'qMGE$GK",Qnf$,Qo)4;C!55e/!uG'>-[EzcQ3&d"9\e+"BZ46"9G#b"8Gdt\5NM5,Qp41,Qneq,QoAL,Qo)L;D]Xe`WS[4*!?BF$H+cM"=-G>"=@%MPQAN%!JJVsPQ1`KPWk!+PQAT$N!85BPQ@!L!qTq';uqVZ!N^2BaAW3Er!JYi(Y!C-YYtZ-!<aYLFJAsA"=+t+";E[<"9^h4"9_Iu"9Iik!NQ7F"9H.<_up+S"BYd-!W)oA_u\=p?jGuu!PAH^dpN4Ro)\1Y!RkEW"3U_`liaY&?ifj"!Q5,IdpN@F"9Gk4"9Ik-!M<9n=9JZC!sA`0!PAI""9H1="1nU#]EZ8]?j3;+!Q52[_dEQ;"9Gk7"9Ik-!Obo0"BYe;Mus1c!L*]f"9F0sZuZ8<!Mfi!"9`O^#fHb[Eri'>D;,1ue,cXiSe&IDU^VnWU&gbb%KW(#!O`$!;Zm4+;Zm47;Zm5AS-/l%!N^>CEri'>^B=[U"9G"n":e?5S8_6H;Zm4(!!!":,ldoF"9PX*"LqA5#ODQ""9[.j#/F.?WrdqW"9\i.quWYr"BYd-]`\B.!i,r"ZX<mIdfK(E!qTe&!W)qOquaiE?j3S3!UMK2!N#na"9\e%"9l#.!i,o$=9J[&ZN?p*#Ld&]"LA0*qujoF?j+(BliE0ZUi-A:;Zm4)1ReQ0`!d8P>U0FU!S@N+$,csW"9c55!K^4_U]U`&"9JE%!i,s$_dES)_ZBZc<U4#n&**cX!i,jocr1&M!e^[Yqud&$"BYd-#0R&FKEnhk?ig-+irT&s"M8&'%%I@b!i,joQr=+j,Qo@s#ce)E">"Y6"?_&W"9F0$"3=CD=9J[&"9J,toE53.?j+pZ!W3Y4?ibl>_u]3<U]I=n;Zm4)"De:($D]L(Uj!#rj:%giF=_nMoKEK?N!9+^#a?hA4<t&WQr=+j"9J,r"9\b=!i,o$=9J[&9*+YfU]JYH?j""B!W2uAMdR"k"9Iio"9PB;"cuXcE"@R(;Zm4k#35f`,QWT%]3>\;>qAYM;Zm4K"9\k;"9]97"9F9V"e\cs]`\B.!W3'$oE88!?ig-*!VC--MdQS_qZ6=\r)6u(?j!G1!UKi^!N#sX"9\e%"ABS0"9bY>"D\4CKHp[GV,RR#"=sZV9I*jgB[[)^6oG10Qr=+j[ObM]"9\i.Ws"5W1gs_s[Sm;3!QIe7"9PVp!k;/3!Pfr`,Qpe7/-=HT"9\b6!U!Aa=Ao>*"B'%er_iq&CdI@f/.;R?A:,X*!JD^$CfM`+N`-&`;Zm4*L$Jj_*(4`H"=,5q!QS+A=9JZ#!sA`0e-#fr!Mjc;Erk&!gBGN#!T\2d!P\a?qZHrT!T\2)!RqFOg]Ra'`&)N9!JZL7"9IS&g]>.me,e&"#E2L`#c%g']E-MN^'0H)j9"ZKOoa>?`"%G$UB8pMoENeG"U``f<O3$ke,TO!!J$X?!PnfdK&Zm]PQAu/U]JsG?jGuu!L+A#!T\/%VGdU#>7<%`RfkP=9Q1#dk>MKd-M%?AP6=Qq"B9>->];lrM?F%E"9_C!_ZA%]$kdA)HmAhG"<hRa"B&2M!UU!m"?ZgQWruBI/6m-""Crb\"A_r!"E%-@9Q2Z>mo'>l"K,0#"9_+N"9c/3/2'p)1^"[!/3IhR.Do@(L/S3X!!!!%-ia5I"9PWm"DC^:",KkYE!uOG"9srmUJ(]G6kVmcBFEWq6jSGKdf]ds"AEbpDuk[Y;Zm5&;Zm4="9\aU"9\jCquqUL\d4f7":i?N!q9+k]`\Cq!gEfgN!*5c?ig-+PQ?T@?j>ou!ea_:!k`FSQr=+j=9c)8"9]Ds6j3!X23V5QPT0ek6jg!r6H`Ri-rU6On5BGm>=:j`#)!*UbY08bMd$St;Zm4D"9\n4K*I]A2?AV+;Zm4;;Zm4/!gEbb"9_g0!k\U<"02Kf]E?nr?iu;g!gEfARpZH,"9O5W"9Q5S!O,K*Wredo!gEfgS-2ps?ig-+!gF24_dHX5"9O5X"9Q5S"Q32]"/#qC"9^hF;Zuko'K,up<`9,(Qr=+j8t,qc6jN't"k-ZqqccHV,QoY#>7=J)"@O8g"9\jS">gTe49Pd)6j*Oe"k-ZqB2\p9RpL^M6k$F'"k-ZqUK^,S,QoAJ,QoYl;Zm5&HNZ_:;Zm4+!Ls2""9H1==9JZ#!Rq5T"9G$6gi-re!TX@a$e09>Dul'\df]^<oE!hQ!W3'$C]jd8!QGW)e-#g5"9]kKXE+Et!TX@a"9`O^!Sd^j!Sd_*o)[?N!!1SN5iVmp!Pnfd!fI*/!L*VT!MfbG]3kiT"9F_h"9JF=!Tm;`6mMmL">p<MhGXO["9Oeh!gEgi'4:s$"g\8pKESnp]PdoS;Zm4)"9\b>"ACaQ"9_42#_ZM_"C>"0!NQ9l"9Oej!fR7a"9H1=]E89>MZUNm#HM57?s<\k!fR<[K4"`WWrfp9"+st^"OdFBN!"]??ig-+!gEi2ZX<g'"9O5Z"9Q5S!hN<n"FC8>!JThB"9]EX"9Y5oC]V=&4<t&GNWFa\"?\REdkF]'$kdArHmAi*KHp[g%]gWN"9FH,"A_r!"Fa8P!V]Lq]`\Cq!gEfgN!*5c?ig-+!gE`?MdQ\:"9O5["9Q5SPU9<3"BYd."02KfPR)nL?j*e;!e^ci!k`FS[Sm;3!!!!$*<6'>"9PU="-?Fa=9JZ;!sA`0!OMmg"9H1=!W)o)j8k`X?iu;f!PAH&]3k`IWr_8`"1qqA"3U_XX94YojDP/%;Zm4(g^phX*UIM\";q=fE%ZbG&'QR=!JR"I"0;U;"9^P,'ERDr/1`%L"9^RbZq+*u!PJU:!Q5*D]EA89"BYd-!W)o9Zj-D8?j+pZ!PAX6CL@@aDZg*B"9\bd"9`=8"9H#2"9GQ6"BYe3Erh4&8&GI/"9Fa+S8]SIqZG%CU]I&?8gFN?PQVNp!N^>CErhd6^B=[UMuf.D@f_ep48T&;MuWm;N*NCaMug`qA-Rqm!K7&D?j=5J"AB'd"9G<:!LH^f4E)MJE!F2_+Z'<i@4X5<;Zm4C"9\ac"9]35!!/rqzWg*eh;Zm4),QnfH;C!55]E4#p+7'RS";q=^o32V;BS-FD"<8D#"9]tq"9]35!!"?Ez!irjJ0N/)Wj'+'6-sQlU!X)a2>9m_^"B8*R"9\jS":1)f$@l%X"D\,C1aE2L4<t%D"B%&r=9JY`!L*]iPQV#fb@"NTgB!66!Q/:IZu6(p;Zm4(A'4t),Rb;b/7^"/"Df=d"=-]@#4POo";q=n>6grL$kr`S"9H,=1iQ'VE&Xg#;Zm4c"9]"WMug9f"BYd-#-.d3N(odL@!p,u"FL@D"9GlJ#_5hV(&Sg-_]8#(>QVDk;Zm4s"9\eY":!d_"CG(1peqI*KUW)G,]mu+"C+q0"9H)5'I3f\7oKNn"D\,C>:^9N49P]F"?Zf-,X_b:1]ucB"9a&S"F!cI#-_#/UK]!3HNZ07?GcmK"9^Q#KE:jH!PJU:"9FGa!JCSXb?tLKb5mP'L"g!,DZkFg"9\b4"9c55!RF[I+B&CG&'TF%"=sro"=.M'"9`NdMugFe"BYd-Zi^F6Wr]R.N([O_?iu;f"FL=+"9GlJ!h`Hp<_NV2"9\u$"9Ffe;usc[,U<LlOAc8b<$LW2"=sro"=.M'<!7"_"9]uE_ZKU32?D`B;Zm4s"9\bGo)rZ(49=eR!JIKV!jG(31]`I:%T<K5,Y_5@Qr=+j<+4eg"=+Bg"<:qt"9`NdKE88T!PJU:"9FGa"9\j0Mug9f?ig-*!JDu@_dENBP6&$@/&P`t",d2eMup%f?j*e:"FM*!"9GlJ"1D,22Lg%R;Zm4s"9\h0:9,dA9JusF[o3D4;Zm4(!kSJg"AC^mKLf#E!PJU:"9FGaPQV+k"9GP(?s<YrKE77j?ig-*Muf*r?ig-*Muf*r?q%[."FL<0"9GlJ!KU.^&l^-G,QoY,,QoB'9iM73(BcQ?"9\jf"9^,O1]b<h!i?b:7T0EmE-/\pM?HaD"?\LA1^0+`!TRB8"<BT-"9J]gP?T;#">g.1qZI%K">k(34E*BOE'^N-M?J,k">hq9"9PbC!qoOq!)j"'Wr\Ff!K7-^PQY(k?ig-*!K7/6b?tMFDZkFq"9\b4Zimj:U]Htd>R.&*GGA@NqcaJ>^B=[`*rB1C"C)RECiBEec;OiK>:_T449P]F49P]="9\c/"0YW+el)\S!L*]hN!'0^"BYd-?m>]:Wr\.m"H-Y5Zu6(p;Zm4(*!$,mzWmM^b;Zm4)"9\dn"9Z/4!R(WK=9JZ#"9G"qbQIs[?j""A!Ls;!ZX<pbirPq[P\XY.b\mUb;Zm4("9\h2J$UP%",n0EPT1R!V'I;e_ZXW_!L+QQ;Zm4K"9\e)"9H^K!NQ7&"9G;$!NZE+P@+FgirR@+b?t@5b5nC?"litkDZg**"9\bL"9R4S9QU@>"9_g0!M"4Y2T#QK":pCsN,VY[#)!*[MZLa>HiSP9_0cm%"bV1'Hi]IR?ieGE"?Zq4"9FI""BJG(U^g<+"BYd-!W)nnU^"_E?j5Qk!L*fK!R,Hb?;gt0Y$_CM"9]D>RfkuT";GfP"=I+N"BSM)ZNPFs!L+R?>7;c&KWA,M!L+Q)$FBp]"9_4n";DVM,U<DogB9A:'K1.>=&T5)=9JZ#!NZD,X98R)?j;Mi!MfdTMdQS__Z?P7"05f3DZg**"9\bLU]JJ6BF0q+PT3$n"9]tN*!*6A"9]SF!T-fY&YooL!!KBQzWg*bg;Zm4)S/0=6"8!!@">p<-";q=^E#J6M>7;bklPpFf'I5ga"=,5q";Xo=!$5&AzWg*eh;Zm4)g_%1A*Q1J_E-Bt=HNYTNZ31:5"9],6"<7D?*$bY)'EXJ&"=tf$!#AK9zWgF%l)$CWTE$GJg,Qnf$E$GK2M?FbI"9]\F"9\jCj9u'pEt#u."<7NV"9\uH49R9849Pd-"9\jB*!%]kzWg*eh;Zm4))$CpEE$GJg.C0-s"9]EX"<7D?";E+,,TJ?\'?gSW!NcUf"9\qY!!!L-z!ihUn0N/)W"<B<%"9J]_qcaasHNYl$,Qo@q2$>H];Zm4+`#,!MKE7hi)$D2dMQ6j_/0o08!TRB(%T<K5!!!u>)uos="9PUc!Q\1B"<fT)R6%r:/.VRY#*^#_^f(@="9Gk2!OMu394.pu#D3&aZinic?jDSj!Mfh@!ShSrkYhTe"9Gk3"9\j0ZiSqa?j3;+!SdpLRp]1<K)r=a".N[!DZg*:"9\b\"9R4S">3UU!NQ76"9Gk4!PAP;F'o%G?m>]Z!Mfjn!ShSr%T<K5?;gt0cr1&M=9Mk2!sA`0N!'07"@R;3P].5@^B=Z?"9FG^A9.d9Erhd6^B=[Ur!f.s@f_f)*Ld(gMuWm;N,7e\Mug`qKEU$1Muf.D?t3FB"AApH"9G$2!glmh5Z7dgSl5ap;Zm4(e._qM1]`134<t%<E!2(%+Z'<i)DiuJ2$>H]"9GS,"9\b=!Sdb[=9JZ3MZMT9#HM57"1&$0ZidpJ?idS7!OMlsK4"hW"9G;%"9I:r!JaSV-rU6OE!"bs>;QIN@e2DZ/2RBq"=tHJ!L?XeJd93s":P\>";Clg"<;A*,]En8$rni(pJV1tm0"+('F<b#"?[q46uWA-O&H/aKER58#P8];!J1Fg,QoAD!ojD?"?Z_Y/-I+I!L[JfJclc="<96!"9^h4ZiSHN"BYd-Wr]j9!PAO9b?tAJirQLfU^LQ5gi!;r;Zm4("Tnf*!!!`G!WW3#"9PTcll]40.g#>^UC7pf"9Fj9"DS>J!O;h2;Zm43!!rZAz!ijKcGZ+_J<ZD.U;Zm4R_up+F"9GP(j9#Mf"9H.9!Q5+Co3_U*dfIAi"1qqD"3U_Xj9</'?qm*k!PAH&]3kfK"9GS."9IS%/5T7J6c3+:!K.,O"9^8="=-fB#I=ON"<:YV/3m,:L$MqO%0RpWE$GKB%bt;O"9J!j]I6\]^DrIA":<9Q!N8p"!O;h2;Zm43;Zm4E=9Ml1!sA`0N!'07"E\\cP]1NX!P8I8"9H/S!V$2d"lodh!K7&pErhL.CT@Rp"9G$3PQAN%liE%G!K:Lo!K;HU!K7&q!K7kb])dij_#]K_lN)qFPQ?F@>QKca_dE\\DZi`9"9\b$!PD6-ZijJ6!PJU:Wr]R1#)cjk#Eo2$X94r"jDP/%;Zm4(!W*";1^$3c/2RJQ"9]EI"9I(P"9;@'!NQ7>"9H.<!OMu3"9H1=!W)o9Zj!dD?ig-*!PATBRpZH4"9GS*"9IS%!Tm;`zP6Cpd"9\e+*!?gO"9\jB'FY#J*!@,^!P;PM6X(NM%T<K5'%@K*!Ls1az]G^bM"9\e+"B7oj;7cs5KMR!]#/h>Z%?(=rE$P5_"9\aY"9]!/":P=:!glmhKLuA,;Zm4("9\b("9G`*1ii\NE(fd*"9\aa!JCKg#ZCj/%T<K5!JG-U$(M$f!JGZtMZJJ2_#]3MRfS0C!L-OcZW$sY#5_d3N,Jhe;Zm4()$CoZ>7;b[";EG_":tDUj>:g#E!*EN/-HKj,V0'A"9]]Q"9^V]&H#j5`+'47!NZD6S-/kn!PJU:"9G;$!Mfj#dpN4RqZ3c$"Og`_!S[XNS-HT5?ig-*!Mfq3j'Vr3"9F_j"9H_bUaT.E"BYd-#5\FsU][r2?j)Ag!L*_F!R,Hb7T0EmIT$@Pzh&-1m"9\e+S-6o3"BYd-_ug,F"9F_fPQV$#?ig-*!Q5'2o3_UjZN6Qt"5@2cDZg*""9\bD]*(At"FP/c!VfRrWr]"!!Ls8nU]ad&?j;MigB!gS"bU1dDZg*""9\bD9EWpG"9_g0"EX_K!K;)IE*e/"&+fmUHi\d$!Q]Y9QiVu+!Od@V;Zm4+)$Cq(_A"6u"9IN`$LAca"9J]Wqcb$s"9k;#'I3g+"9IOe/-HtE1^!j_"63T*i)9a]HNYSp>8/=c/-H"6"9\bd"=R1O"@uGo!KRru?;gt0HqFMX:/_8u"9J]WUK\]p!LtEE"9\jSS.#G(Fr1&WHit&ZKEPh,"Di,[Hi^tb?W.(1]`\A#!Ls8n"9_g0!Q5'C"j6qb!LsO*]3k[:lN+p."oD[1"OdC9S-Adt?j)r"!K7/N!Q8mZ=Ao>*#ZCj/%T<K5=9JYp!Mfi$"9\b+!Q5'C!W)nn_ue+i?j<Y4!Ls4dZX<mI"9FGc"9HGZ!iAm!Y>YQ,;Zm4(Zr6L&]6jS^!Ps.jF9^3A9RHl*gL(/:DZi0+"9\aY!<UPF!!!!=clE)d"9\e+$iu/_*!?9F!LHN=,QnMY^B=Zb*,$;m"9\b6"40sLBG/Q0@%/DE$2agj,R0JA"<7rj"?\Ld"9\bF1aH'@QN<,)"=+*N"9^h4"9R4S!O,K*&5r]7cr1&MZ31:2"C)?9"9\j0"9F/XUiQQq!L*]firiV.KQ$sQ^B=Z?PQ@!L!J-F="9G$3PT^8'!L*]gP6=!h!M"*4E+&PGPQV#_N!(:)@f_ep@C#unMuWm;N&f&^Mug`qKEU$1Muf.D!S^i[9EDJ-!MjW:5#VReWr^-A!PAO9_us0F?ig-*!PAKoZX<mA"9GS+"9IS%!KL(]]`\AC_up2D"9GP(=9JZ;qZ4&,`!]rR?ig-*K)rVh]N\bK?j"RQZN7uX#.n7F!W)o1]EYuU?ig-*!PAW["3Y'sDZg*B"9\bd"9]35"9F6U1^#Be!LGR:,QoY$M9?#a6ik%';[e<^X9=b!"Cuul1e1II"9a&S"9GSDSl5ap!!rZ,z!ij-[OAc8b"9H^K!Q5+C"9H1="mZ35bQmHA?ig-*!Q5/JZX<h2ZN88N"2eLI!W)o9bQ[<??j))_!PAGs!VC:5n5BGm;Zm4("C(t`A-;qH"9_g0Huf=QErhd6irfC9Ui6?e"9k"j!Ls2*Eri'>#MTADF9AU`ZuBaN!Mfi!PQV+4%"oc)!L+P8P68Gt_#]dCgB!N>!L-gnK4G"I#_QLjZu6(H;Zm4("9\bP"9J,s!NQ7N"9HFDbQIs["BYd-!W)oI_uuiCUL6^q])hO,"J]?,"bQj"]EZ8]oPXj5;Zm4(;Zm4GoG`I&)rq#82I7p";Zm4Kj9YB*'Kg+@*(2%T*!B/%"T)CS?;gt0,Qn1-;Zm4;;Zm50)$Dc++)A1c"9]u."9_4n"9`=8!!#Mfz!irX^YYtZ-;Zm40";CpQ_u[4jG6cn-!rNAK]RL1!%@fN]liuN7.gP,A"EXjT"9HFd"CP.2!n^ES^f(@="9R'Ug]RYk"BYd.KED>[UB8pIC9(_G"1nYgg]I(T?te!j!mCi6",(RqW)Eg%QimNr"9GG%CfaO<!R+jQ;?;GU!JCRYKEM=O?p_1#!K:aA1\4fZaAW3E;Zm4+"9\tV9oE(OKE8VO>7;2He,bK>o32V-!JCK2"8c:2S,n9_$nPoi1glMO!P;PE]3>\c$iu"^UB.u2!L,u]"=sS,"9F0$!N&cuYYtZ-"9R?`!o*o\]3ki$lN5jd"05f2&"E^F",$]PJ5ZRR;Zm4+'tX[c$k`SoPU$AW,QpL9"9\aq"9H;:#)H1\=9JZk!sA`0S-/nX!L.X,Err-?!iuMUWs!Nc!jloK!P8K1j8uu5DumQP,Qn1e!pfs'"T&Z#X9,bV"UjZ#U]^kN"9]kL4ECS*E!;F.lN@9r!k`JO+Te_J!h9Ar%&3qKS,`V\S-cM'S,pG-PUjWQS,niUirSKJgfn/J`,>bZ;Zm4)%#b;P!Mj<1X<[og<?sC%!JCK,N'&?gHmAgq%T<K5^f(@=;Zm4+"9\b^g]N33"BYd.]`\Dd!n7>R@pf>l"1nYg!o.9no3`95"9Qe="9X<q"2Ih<#Q/o6"AB4e>QL'7!LtD<Ua-'g,QpL9,W#P'KE6a+,U<Kn^f(@=$iuRpZo+%O7g](q#-7iY!M'7M!L*hZUc8DAS-@CK&(E*;6ihk&!JCK<$ag"g"9\j@oE"AY]OY7e;Zm4;"9\bWPQRd],U<KnVu_^D"T1.Z<`9,(=9J]\!sA`0",$c0#O>b:8]q1jbR;$jV?3Op"9X;Xb]m%hN$JN8,QpdA"B5Dd,QXD\!MgtDX<[pZ;Zm4("9R'g"9\b=",$aZ=9J]\Wrn"X!fLG##Eo5=KEBn9?ji_3!o+0AUL4;dZi\GZKE7qZ;Zm4*h]r:&!i&9ek#2BcHj"NlV0iCK"9\i.!n:%F"9H1==9J]\qZ>7M"QNkj!W)rJg]<%8?jFjV!o+$u]3kid!mC\+",(Rq:/_8u8-=Sl"9\js"9bW$!j>N*B2\p9>7:OcKH($Q;urfr^/G.;;Zm4(!K7'RP^F_Z9I'`A2GZYt;Zm5Nj9,RO"9GP)=9J]\!sA`0",$c0j'VnoqZ>hoCZAe,"N(;rbQcO(V@!/%"9X;X"Qr\dzeft.p"9\e,irS(:_ukeu"9^gf9Epk_"9a&S4E(A6peq:u9NI&U"?[)*'Ec9!"Crb\$`Hu,TMksr4:%;T"9Yu2#_5hV!PCP4!PAH)!PEpBgB"qe_#_2DZN7]>PQA,rMugQl?jDSj"FLC5!Rq.]!)j"'Qr=+j&).3m"9H/S$@l%X=9JZkirSKL"H-Xk"/>n`!Si$0!gIU+peq:u;Zm4("@NF_"9\iF"9l#.!OMq3=9JY`]NG%6MZJS6]Et68"9Gq3Io?IQ9EC!&"9^Oo9M>JD"<8Zi4E(@ci)9a]"9Iil!UKqk_dEN"irSL="M8%FDZg*r"9\djHq[jF"=,6<"<:)\"?]X/"9_sT":;#*#Co_UPQM$k"9Iij!gEgib?tD;b5pr3F1Yf`DZg*r"9\dj"9OBX"40sL8-R@&;Zm5M!UL'4li^Dn?jD;bliDpC?jG-]!SeHk!gIU+W)Eg%;Zm4)K*2Cg9K[9-!L4/M&>K9d">g`j#09^GBN#$:j'*3k<(k[@"I'l="B6->>]>%r2cBh^^/G.;8`KpS,Qqq&"B5E;>]>#,"FC8F9EC!&"9^7g"AAj#!l%Y:]`\As!UKpij9/Qf?ig-*!UM2GMdQ[O"9I9_"9Og+!J")O]Li<E;Zm4(!UKjE"9_g0!NQ7nqZ6<l#30(l@!_q@!SfKK!gIU+Y>YQ,;Zm4(N&1UN(R,O>c;OiK;Zm4)>80aY&>K9d$LAC)!KF\o"9`7S9Ei41"9GY.>6q<(&>K9d">g`j!N8p"=9JZk!sA`0!gEbN1LL7TH'89q!KlDMDZg*r"9\djNrji1j&S8C;Zm4+df]a("Di$=;usc[E+[i-"9\tJ"9]cE"9Oei!NQ7n"9Iil!V?Lso3_[$b6!n5#P2=,#/^K.lt*M2?ieFO!Sdm[!gIU+O&H/aireWN"CuHsCiD,@!Pfr`Ll2C89O)N;9E]\F!TRAu&l]F;0"V6;"9`7S"9]!/"9]35"9XuhjDZ6:,QpLC<eCNK"9_\C9M>K%">hA,!f'\WVGdU#jp/L""?\RC"B\S*!gEciWr_hq!UKpij9/Qf!PJU:qZ5a\"Iid"!V6AWPQ[I`?j,cs!VA&:]3k`AMZN05"m]P$DZg*r"9\dj"9c_C"0YW+=9JZkUB0]a?,L%R"lfXM!K*@SF1VJ>g]NaJP]$[*;Zm4)!PAPSb62p.`,Ga3!P8I8"9H_ce8PH#^a'$`"9H.9"E%-@`,H0d'Vbd?,Qqq&"B5E;>]:bU"FC8FO&H/a;Zm4+;Zm4]M1Yo-e.PFU^B=ZG"ADJi'ML&'UB0CZ1_Nb!E-08+;Zm56">g8%/-Kc79M>K&"?[q4"4gBRE"92W^a'&!MZcu[9O)O3"9a&S1fdNX/7^"/1i+E?!!H1nzWl,hV;Zm4)";Clu":E(o$j!X:fM_nU!sA`-!NZ=Oe-&kV?t@F]!Rq>6F'o00?qUO%!LsD\!Ru#j*`E1E=9JZ+"9G;$"9\b=!Rq2S"j6qrU]\MB?j3;+lN+(#"m]P"%.""b!Rq.I&5r]7-;t$M=&T5)";q=^>8.UD$nMG>!JBD8>8.6o"5EtTS9G0j_ucG;*'A]QHp.Y>&$uDf"::SK1]b>o#ZCj/5Z7dg!)j"'=9JZ+"9G;$U]^_3?j+pZ!NZC(X'bu*,6=kJS-=gYV?lep"9I!Q<";h09E\H#"9H1=ErgpsFRoW_"9FI#P]-d&!JCRVZNL<q\cIIlbQ3@tG6mgM:u_fQKOP;$KELQA!n:i`"H3A_P68`,!JCK.!JCKiPY;7e;uqXQgL(3NDZiH0"9\aiZiR%&R2GQ#!!7fSzWf[Gb;Zm4))$CWj,Qnea2$=m=;Zm4+]GQkC'9mM?zXsX2L"9\e,"9YT$"/o-$Y&%:2#fI,PHohD*KHp[?,Qo@n"CqOl6iiMt!LtD<CfMH;!)j"'1aE3?6mMnW"3<1n"9^P>lNG"%!!2.a0^Ac#!Pnft!il@_!L*Vl!OMmgo3_cd":O9c"9J.5"IN*j&o;-;,QpLD,QoB?"CqOd"9FH,C]V=&W)Eg%;Zm4.!fR<(KEPB[!PJU;!gEfjPQV#f?ig-+!ea/:o3_^MK*%!'8b6<o"5<m9r%-$!Zu6'J;Zm4)"9\bpA-VO%o1/nK;Zm4."9\d^'F2]X;urLg">*:M9I'`T">p<U"8iPNFrS([!TZiUfM_nU/.=oL6nADO"@N9\49R5u!P;PEE,O,-B9NHd"9_D;"9k`&!h`HpWreLg!e^[W"9H1==9J\a!sA`0!e^W^dpN42])o>B"Og`\!W)q_Zinic?idS8Wre5Q"05f3DZg+="9\e5DUTA">W)c$n5BGmMn9)p!T\2#cVjrL(BdD4"9\dm"9PH!":e?5#F'!,6mMm\]3>\;S4l$H6j-0a$q(4M"9H,=9Q1&cJ5ZRR"9OM`!fR7aRpZ9ob6!V+MOS!@"9JE$"9PrK"1V84O&H/a)$DJkV)/;X"=+*N":M"N!p<Jb=9J\a!gEfjKEM=V!PJU;!sA`0!e^W^X'bu*])n3B-BhgA#O;GEZieKZ?iu;g!jiO!b?tLs_ZGbu#_QM8DZg+="9\e5_uc<)CBW]"!JJo)"<8%J>]:7D"<gGALf4EZA9b-W%AXCFX<[r@,QoY$9k4BS;Zm4K>Oqt_UBFP8pKVZd!K%!]!JJoq"<8%bFDr)_"<h:Y4<t&?3)]q_cVjrL!TX@bP6=!h!UOb/E%[=Wj9,MU"9]kK"Em]H!T$`Xa&<*D"9Gk3j9,TfN').^E!P,!qZHrd!VC=F+U+)5!KObpj8]5Aj8n<Bb5oZbj9"a$"9Gq3VGdU#;Zm4+Cs)r_Vc3\m!K%!\(Bd,o;Zm5Q"De.R37B]01c>KFJ5ZRR;Zm4(!e^Wi"9H1=WreLg!fR6_KEPB[?ig-+!gEoTlX0bjdfPI4#KpK[DZg+="9\e5Wro7u2?KLG;Zm5."AAjI"=+[,$rfnG"9Q2>!le.Ac;OiK;Zm4+!!!(tz!ir.@W)Eg%2$?#C"oAE*,QpMS$nMFp1]`12W)Eg%;Zm4+"C)29A-;qH"9_g06urBnErhd6U]^^g"?^`+XDeF!ZO2?dZu?&+!Mfi!X98YL">k0#ZuBf]"9Pq2"De,'4ECP1E!;F._ZU"Q!Q8q$+T\qQ^a'$c"9G"n1ii\nE+cK["9\b,!Mfb2+T[f1P^f_:!L*Qb!L+J&!L*W$P["EfA-%nqHXM*1`,>cX;Zm4(DVG<X49;$)$O5rs4?N_H,XaI&"C'nH"HZOb\5NM5;Zm4)!Sdn+g]U^^?jD;b!SdaG#4#YYDZg*b"9\dZe0J-pqZ4bD49XRC"9\b6!J")OJ5ZRR!TX@fg]RYY"BYd-!S[Y9!Sha(@pfDfDZg*b"9\dZ"9_e),QcUs$mZ`",QWK"1aE2<E!>P1;Zm4c;Zm4=!W)o5,W5_^+&`:F^f(@=!sA`/!Sda0e-&kV!PJU:qZ51L#(p:a!W)oIg]=`h?j5is!e^T\ZX<h*@fb?cbQZa/KPpto;Zm4);Zm47;Zm51"9\bg"9^neg]E-2"BYd-!NQ9TgcN\e?ig-*!e_'$b@"8lUB0.$!i'-,DZg*b"9\dZ!SfS3g]U^^?if!_!Sdgi_dIuC"9H^O"9O6p"Ai#"">k'B4E(Pk,V^PI!JSuJ"=+#91cSD:!LWuc#cp-N"9JB[":e?5!k2)2)Z0a91`Fk=!LWuc"?[(a"9\ib6itA,4<,8-4?O9F"9^Rb">"L:*,krUN`-&`;Zm4)Kt@BD2?Jm>;Zm4S$D[a,"?[q46uW4^">Ve:,7?=b^/G.;Q8A^G!W+\S"=uH,"27\:!LY/h3BTDd":bJ0"9^hZ"9XBW$itq_"9J]7'H[G\quR!8E$GJhJclK%";E*^"9^8$"9R1R!NQ7^"9I9\!TXAc_dEN"_ZAP"%JsN7DZg*b"9\dZg]HA3"BYd-KED>[MZSP58W-s[Ge4"3bQ@*<KPpto;Zm4)"9\d]j90C""9GP(]`\Ac!SdeYe-&kV?if!_!TX9NRpZ9O_ZANn"S6")DZg*b"9\dZ!Wo8u!!!lW!rr<$"9PTb$lDnG"9]SF$j!X:*7Q"i*/"?f%T<K5z\/#&E"9\e+"9_h*A-?"5"9GTF"Di-qA-'Fb>T.-X!*jB9!JJ'i>QMZGPZ.k!M_&*6"05f2Ci9FrOAc8b;Zm4("=sSP"9\j0>Qe".P6=!hUh"EJSQF8I":9_^b6/tn>]a4$!Oc5=;Zm4+8d#n`;Zm5.oEa53liF$m)$C?_0+7sd"9\dYo)oJD>]9^o7oKNn2cBh^0Dc:0!OQ*Z"EXeu";Xo=!NQ6[!sA`0"FL6OKEM=h"BYd-#Eo1AX9#Y8?iu;fqg8FN!OH/7!W)nVKEm-;P@,U9%A\(N!NZ=!%T<K5!!!T3"onW'"9PTd'IZl_*!@,^!P;PEPSA"f"9]\Fr!WV32&r,)"9]C^!!!L-z!ikZ.fM_nU;Zm4)K=_/g_#]c$o)Y'VoDiEJP]XeQPQAT$Muq`7PQ@!L!fLRi"B8T5"9G$2!N8p"Lf4EZ=9N.<!sA`0PQV#G]NfLY"uDGD"9\aq!L*W"!L,CPL]N`6[K2Tq"9\i.e-!cjGnS%#"9]_**!5V."ABg=/-3O;*$bY<W)Eg%!sA`/!OMm_g]U^^?j""A!ON$rX'c1u"9G;#"9I:r"BSM)Duks9<s0Ko;CieE"9GS,"9\b=!Sdb[=9JZ3!PAO<X98R)?ig-*!Sdm3K4"e>ZN7]C"Og`Z!ODg6Zinic?j=dT"9G<F"9I:r,Yh8@Wrs:C2?Lr8;Zm4C"9\as!OOOZ"9_g0!NQ76UB/"1!omYl#K$SLU]nqLgi!;r;Zm4(!sA`l!NZ=W"9H1==9JZ3b5pB$!Ma$+!S[XVZiQq0?j+@J!Mfe?!ShSrn5BGm>9ka#ZigEi1^"g'"9\c/RikW4$kb*94<t%D6mMm\%T<K5-56[."=sfTMZa00*%Z%T">hA,"E79B!!.tp"9\ai"9^,O"9OT^A9.d9Erhd6^B=[U"9F_f()BgO!L-1Z2cBh^!Mq=M,Qo(i;CieE-Q0N!"9]]&*!4_j"9_UR!oHoZ#ZCj/+&`:Fg]IZ^"9Gk1!Sdf[gL(,A>62)7U]eSCgi!;r;Zm4(!#u#?z!ijZhi)9a]!sA`-"C(t\N!'8c!K;(#ErhL._ZU"1!M"*R8](Y3":1N:"<df1!P\a?0_5=`MuWm;N#(.KMug`qKEJgeMuf.D!fL:a9EVV/!MjW:GZ+_J!U;3U;Zm4+;Zm45;Zm4/!OMpd"9H1==9JZ;qZ4&,!i'-(?o%hr!NZ=.!T\/%BN#$:,U<LDE*Je7,QoAD;Zm4[;Zm5I)$D3mYQr&K"=,l+!U*Gb&hHP*,QoA$^]YW>,QpL9"=sSh!L?Xe9e6OV--HE:"=,O;/0$Jl!PAP5ZijJ6!PJU:lN+X$!S^ue!W)o)]E-bp?j!_9!PAW[MdQe]"9GS*"9IS%!LQdg$S3g?,Qo(qZ31k("9_*n"9FN]"9;@'!TX=c=9JZ;ZN9+i!L$ml"1nTp!PE2UK4"fQ"9GS0"9IS%"D:X9!V]Lq=9JZ;!sA`0!TX:Bqd9MY'*5`MX96XRjDP/%;Zm4("9\bNoDs\FPnD4Y!"Pe*zX,AM/;Zm4)"9\dn!jhr+ZijJ6?ig-+!ji04X'c1u"9PA$"9R@s"DC^:!NQ:7!sA`0!ji$aX9;W.!PJU;Wrf@*#I@e?"3UbQ]EbcN?ig-+!iuKVHXI$;"1nWi!jm;^RpZDh]E4l6g]=8T;Zm4)"9\h:"<7nM">"(/"AEVW"9`fl9EEL=!P;PE]3>\#>7<Up"9\b;49FG>#`MYl]`\D<!ji(2X9;W.?ig-+!iuWbUL4=ZRf]qt#KpK[DZg-;"9\e]"9PN#"@lAn"1V84<$VT_"1/9nr!Me7Igsm2"iPL>_ufQp.gbhY"FLHM!JEQ\N*IV2*$bXf,Qn.4"9G#,&Gn"(<&Od0Sl5ap,Qne^,QorO"?Z^<"9FH,!S:6Q#ZCj/%J1V;X<+/m!PJU;!sA`0!ji$aX9;W.?ig-+!ji3]dpN?;MZV[`J(%d-!W)r"Zj,i(?j4.D!ji*BK4"r-j8u+_g]=8T;Zm4)"AAjj<!3=A*!?;=!Mg4L#.suK!P;PE;ZmW$"9\bF"9^ne"9GE!>]=n^!)j"'&nEoD"9b5'"@R?)">"pG"9F0$,QLaGN$Ji0,Qoq)%bq)L%.#5B$\SkgS-=jqIgM>CKH(#g%FdQH%ZCnq9F(JG!N[OLZm5c:<D6Wu,QqXg;Zm4s"9\e7bQ7><"BYd-Wr^]Qqud-'"AEk;KQ'50^B=Z@"9JE$FE7M:+;3uCo)o-=&(GP&#4i/F]E4UB!Pfre#Q+XVr$DWd_u]c:ZiRB8KF[VbU]HV[U]ubZ%[81C%)`25lO&;h#Q+UXMuiicB*%o7"4RRo$iC/R!W4Uo!W2u7!Rq7Q!W2t_Erl1AFK5Ol"9O6qN,SmZ!W3'%KEME$"C-!LN,W[H^B=Z@quVNP)?PQmKBiR9!!2uu@f$3(!Png7"KMS$!L*WW!R(TB1LL7,DZg*R"9\dr!!D[gzWkBAP;Zm4)"9\eqlNBaW!L.OYfM_nUHNZ/+!kSR<"<8D#">hq\6NdNLVu`-%PY)&Z;Zm4(=9MkE!sA`0N!'07M_&oMLB3V?5A7(u"<.a(7T0Em";q=n]3?O;G6BGt":X?R":3KsZmJ]S"BYd-g]IZ^!PAO9g]RYY?s/*_!PAX6qd9H2b5nsS!o%)b?m>]Z!Mfe?!ShSr%T<K5E!,D/N!'?Tdf^fp!!/%+?BYDK!Pneq#O;DL!L*V<b?P(,"05f2S8SO(;Zm4("9GT#ZigEC"BYd-"02I(Zj#c'?j)Ag!ON$ro3_XC"9G;#"9I:rKFh&b`Y".I":9_^!Obo0N`-&`;Zm4(!!!"+*WQ0?"9PUf">EaW"GftZ1aE2<4<t%L6mMm\"B%'%\5NM5;Zm4)"9\eY"9H;:!UKmk=9JZC"9H.<li[@&P@,=1qZ4>1!L$ml"eu+:Zibqglu*"-;Zm4(;Zm4]_ZU"e!L.O]^f(@==9N.9!L*]ilNCI6$Ij$E!P\a?S-/kW"?^`+Ui6Rno*i84XDe3"!Ls8n!Ls99!NuNg!T4!C!O`#n;Zm4+;Zm45;Zm5I!Q5)M"9_g0!UKmk",d3H_ucuI?im)(!ON'S!UO_-!)j"'!L*VL&AnOi!L*W+"9\b6Lf[LXPY)&Z;Zm4(;Zm5A*:s9q!KS)Q"=t:`$mYrn"9H,=Dukis,QoY<%)`7L('3"i]`\AK!Q5*A_us0F?j"RQ!PATB$Xa#4"1&$HZil:plu*"-;Zm4("@`EP"9F`Z_dHCG!!/<p(t/MM!Pnf$"7lPXPQ@"Z"f#T/;us=5!N]6'GZ+_JGZ+_JErhL.gBFZ@"b^h"E(p-3PQV#_"9]kK"F!cIP]/UO;Zm4("9HG1!PAP;"9H1=!W)o1`!>mA?j"RQ!Q567dpNFH"9Gk3"9Ik-!N&cu:/_8uliR@n"9HFA!UKqkZX<k#dfIAk!R"jTDZg*J"9\bl"9R.QFE7JI!Kbb5!Ls1VDumQRX98R""9G>"!Pfr`"9\ai!!27]zWo"`q;Zm4)1h5irUDs<!!L,EW1d^LRM^/=f!L,DW"9\k/df[*Y!L,DmP\7$2,QX,7PVd$b0U!a_'EOFT;Zt#A"=sS01^!q!qZHqq!L,Dn1a)Z@"=+#4":e?5!JjYWLf4EZ1`H5lP9^0n!L,E=1cU[EZP3G)!L,E_*h*Di!L+)L1b#1Fj!4Yi!L,EZ1`k[&1`QO\"=tf$!jGT+^f(@="9GS)!NZE+K4"i2irQ4d!LmI#DZg*2"9\bT"9`%0"B7<Y>Qb13"9\b+UiQQi"T&<&"9FI#!V-;EKEMXhliGf@KM.dBKE8miKLkt@!JCFR!JEPP!JCKiP["?L;uqXQZX=!lDZiH/"9\ai"9]!/K)q?<!L,Da1_@8E"iLG+PVb,D"9]tN!N[qQ"9_g0!NQ7.dfHNQ!qTe&"eu+*X9Gq<?idS7!Ls@p!Ru#jQ;[nhbQRP=oE!#81^^i1lQcLq!L,ER1a^Bk";Cm$"9;@'/3m,:1c-H\"9^Rb!NQ7."9GS,!OMu3j'VobUB.G"#2<MhDZg*2"9\bT!N\1X"9_g0!Rq2S",d30X9A-&?idS7!NZFqK4"`WMZM<1"G:(c"OdCQX9"Mm?j!_9!Ls8H!Ru#jN`-&`!!!!")?9a;"9PUJ"CP.2!R(WK=9JZ#!NZD,S-/kn!PJU:UB-kf!omYl!W)o!bQmHA?ifj"!R(f7?ic,%!R(YhK4"l+UB..n#(p:dDZg**"9\bL"9J9r":e?5!m":C!PJV0=9MS+!JCRYMShi'1]`O9U]aQ,!JDg'!JFO\P6$=:_#]3Io)XLF!L-7[b>\Lq"4LWZN,Jhe;Zm4($)@U+,]I5A=Ao>*P?T"X%GWcA"9O3["9^;-"Em]H"9;@'!NQ7&"9G;$!NZE+!fLGZ#.jo3PQctQb\mUb;Zm4(<[;'[*%V2]1]ijG"63T*">)/-OAc8b;Zm4(,QoBA,Qnf4;CieE)$D2f$jPJi"AtXmDukuW;Zm4KG6Zf?"9]uT%b(b_j?=%.;Zm4F!Ls22"9H1==9JZ#qZ32iU^LQ2?iul!!L*eH!R,Hbel)\S>9#0p%a5!<"63T*">)/-Y>YQ,!!!!"*WQ0?"9PV""o)"!JclDHNnZ)c/.sK74<t%L0N/)W^f(@=>,qc0'Ef\#";Cli"fP?&i)9a];Zm4(!fR84!KRPg2$>H5!o"t'"9^W.#I?'^,[:A3^f(@==9N.;!sA`0PQV#Gj$[qhXpjB4"D?Hi>]TqAE$3=,%\s-,!J:R"PQV#_qZJ&C!!/<KJti@2_#]c$P6$mKPQ?^GA-%nq>@7]"XD\5@;Zm4(!oP>A"9Fu_"JAZr-rU6O,Qm*I/qX98*!@O+"<7Gq">3UU`&LZu"BYd-liR@n])h7!0CrQR"1nU#`!3PU?imA0!ON$B!UO_-i)9a]"9HFB!PAP;"9H1=liR@n!R(ZIbQIsI?ig-*!UKp+_dEN:qZ4>3"2eLI"3U_h`!,I7?j!_9!OMp'!UO_-N`-&`;Zm4(Jcl2V:7Ed8,V0QZ*'>JL$q)?D9EB_JYYtZ-E<J*";Zm4K!Q5#s"9_g0!UKmkWr^EI!UKpiRpZW!9*)s3bQ42@?j!G1!Q5#.@pfM!DZg*J"9\bl"9a0P"9OT^gg<t_:*'67"9]'b"9Iik!NQ7F"9HFD!PAP;"9H1=!W)o1bQbsm?jD;b!UL$._dEY+qZ4>6"05f1?m>]j!ON!A!UO_-%T<K5O&H/aJcl2XIFB_J'J'kJ"?[q4,[aORgIMAE;Zm4))$C@C!P9$K*!?;/!LEi!(?5N#"9]uh"9^qf/-3di/1ad@1`RbD"=,5q$tiKA6ikL79JQ_r/6*Z@'I3f4s&0%'%0Ze7zWo+is;Zm4)lN@9f!L.OUQr=+j"9Gk3!NZE+"9H1=!W)o!Zj4c^?ig-*K)r>8#J4@GDZg*:"9\b\/-Nae#GYKKlWYVk/M%#,Gm"6Q"9\eQ"9[:TS1nfl"O$uLO4+4T!!/#Z$HiL0!Pneq#(lr8!L*V<>?h2f9F%%p!M"'2<`9,(o33Ik>7<=m1`TWP">g.L"9^;-N'L;EM]'GR"9]\FOh2*%$kb)l4<t%L6mMm\,Y]fmE!XVi;Zm4S#0[/4"9G>MZo%t;)$D2li#gDN";E`q!k;/3=9JZ3!PAO<"9\b+!Sdb[",d38]E\7@?j!_9!OMs8ZX<mARfV:F#_QLg!ODg6]Ej-t?ig-*!ON,bMdQ\J"9G;'"9I:r"?9<_IWeWm!O</n"9\eMdf^4\/8tWA">p<5E'9s!"9\ai"C-CS"9\j0"9F/XHuf=IErhL.+o;C!"9G$3PQAN%UB-S[PQ@e+!L.d/"9\i9dfJl82?K4*;Zm4;"9\al"9JO$";au>!PVJ8g]IZ^"9Gk1!Sdf[lX3kJMZL0c#)cjoDZg*:"9\b\"9_4n/-5HCRfkSO'K1.>?W.(1*`E1EzO9GUa"9\e+%]fq7j>d8%)$Cp!!K$CN*!)9<!O;h2!!!!-,ldoF"9PY!"?9<_#bY*!Duoh=K+FJO"C(t-\7BP'!K%!`(BcQo"9\bh"9cM=":T5o'ENdg"9J]?Lf4EZ"9JE/"9\j0U]R=o?rP5M!W3>;]3kiL"9Iio"9PB;!r,[sOAc8b;Zm4+/-H6_qZI$I">k&u4E+;Q6uX@RM?F-^"9^O^$jt'S;uqRR>T*_J"9J^2!J1FW<<N_@:/h@,JclJb"9_s1A7P^m"9\c/"kZ`Vcr1&M!e^[Yqud&$"BYd-]`\B.!V?Kq4(&*d!W)qOquP8S?icGl!UND$!i0`;0N/)W=9J[&!sA`0!i,mn]3nR\UB18sE3!@MDZg+-"9\e%"9^V]U]J[A"BYd-Erjbn!SdfO!OQ*QjD\DR#eU9@!Sd^j!Shhp!Sd^I!P\a?OP9fc!!1RMKS'<T_#`$dgB#e)PQB!LU]JsGX'ej,"9F_h"9IS%!R=UH8d#Ii;Zm5N"9JESKEME["9GP)!W)qOr!T9-?j"RQ"9Ijf"9PB;!M33mi)9a]Jcl2Z$iu"^!JFGU"AX%A!JU`)Jclbr"9F/V"+X;QW)Eg%Jclbl"FPRtg]R`]#l%=)AlAg8=9J[&"9J,toE53.?ig-*!W3)<b?tLs"9Iik"9PB;MuZcZ"D\,IVGdU#(Bd\<"9\b`qurHd"BYd-WrdqW!e^[WdpN4RRfWEl#KpKWDZg+-"9\e%A-(7["9\c/!J1X=<<N_H:0[p<@8pJ7;Zm4S%\*Qe">!u'F9-sr"9J^J!J1Fg;Zm5N!e^[dqud&$"BYd-!W)qOr(=k7?o,\$!UMA\!i0`;aAW3E;Zm4("FL<L#1*JS"9GrYn5BGmJclbl"E\_d#2fUc"9GrQOAc8b;Zm4+"9\eoKE6j,"9J],!J1FW":P<i"9FH]"9H)]/7EXJcVjrL;Zm4)#_W8^>QO9r"9J^2!J1FW<<N_@:/h@,JclJb"9_s1"CqOb!nU?RJdpK<":T)I>QekC<*TQ$":Qhi"B5DR"9;@'"40sL!N6,0Jcld8KE6`,"9J],BN#$:"D\,CJe#^-";D7F'GLS""9\c/*!(Wo**!+M";M=J=9J[&!sA`0!i,mn?icDM!W3,elX2*h"9Ik("9PB;"40sL!J1Fg":P<i"9FH]"9_JI"/o-$[o3D4"9JE&!V?Ls"9H1=#)`NSr%IYL?j)Yo!UM2_!i0`;^Jb7<CBObC;Zm4+;Zm4/"9\b'"9OZ`"9`KC">k'B49:$:(fLP?()I*1Qr=+jbQR85$A;7m"9J]g6uX@R!K%"eJcl35"E\_d"9\i/"9Pf+!NQ9T"9JE'!V?Ls"9H1=U]U`&)Zlf:!J^2R!W)oi!J^2R!W)qOr!0Q9Rp].q"9Iik"9PB;"h.D5*,m,*M?Et;"9],6"9Ffe!i,o$=9J[&"9J,toE53.?ig-*!i-@5ZX?_Tb5qMO$d2pLDZg+-"9\e%oEC:S!PJU:!sA`0!W3"poE88!?ig-*!i,tJdpN99UB18qK4"_B"9Ijl"9PB;!k2)2Y>YQ,(Bb-K"9\b&HiqDf*%YN?F9-sr!J1Fg@g%1,":=,l"9d:n"ccLa!J1Fg!X*muS9ujj"9a)Q"9kZ$)'K_8zWjEZE;Zm4)"9\e96ijer"9H1="BYe#P]M3T!JCRV#J<`ON,V&J^B=Z?"9F/VN,Sps+aaCn!K"DkUO3&h!Ps.h6iid)9RHl*MdQ^HDZi0+"9\aa!M"C5"9H1=bQ@tN"9G;!!R([K]3k`!Wr]!u"1qqC!W)nfU]\5:?j2Gh!L*Z?!R,Hb5Z7dg=9JZ#"9G"qS-/l+?ig-*!MfbNX'c%1"9F_h"9H_b";Xo=!JXMU%T<K5";q=^>7:l2%'49gHlrXb,U<L4/0k?4"B$Kb%?(GF"9a*0!!#enz!ikH+Lf4EZ!sA`-!R(T:oE88!?iu;f!R(Y`X'c'gqZ4nDbS+@b?io?h!PANX!VC:5\5NM5$\UVEoF7m!9I_:p$`!jB]E,W^"U0hp4?O#L49S#U"9\jB\,rU-'M8K/E)QlB%T<K5"BYeCPQM$k!Ls8n"9Fa.Ui891D7]oO!NZ<Z+T\)9U]^tA"?^`+XDeF!%f6A0"9GlK"<dfA!MfadO9(k9[K2m""9\i."9_P""9\^':?,GTS,`S[S3X[eS,pG,PR$d\S,niT!R#9[>R%NB!N$1I"9\b4?ienY">i^R"AVku"9;@'Dukj6"9\aq49;*R!P;P]M?:.I49S"P"9\jBh,I0K"9`BI,Q[X%E&lAM;Zm4C,Qo)X2$?$("9H^L"9\j0oE"RdP@.l$gB#M!#K'pRDZg*R"9\bt"9`@9"9^qf"9G`*"E79BLDNklS4Wnc;Zm4()$Dce&gTRB"=seQ9Ei'SKM`5D$js?CU^5a*D?RTR%?*Z<oE>MR;Zm4/N!/cs#HUE/.DlJ9":);Q!gZaf]`\AS!R(ZIbQM#N?j"RQqZ4WFb[Y#]?j"RQ!PAKooDtgW;Zm4(e-#fD"9GP(oE,4!"9H^I!V?Lsj'W&6gB#e.#30(l#5\GF]EHtsV??_s"9J,q!JXMUzbom&e"9\e+quP/CJ-_YW1]l/-'Ef9V!P;PE]3>[`$D\pJ"9H,="3=CD"BYeSWr[kVX98Y,"B9FCDukU']EA8B"C-!Kj<?Oh^B=ZA"9H.9"<dfIEriWN!PAPG"9`O^!OMmB"5EpYK)r&`!!\BD@&j=0!Pnf<"eu+"!L*V<X*arL".N[#`,>cp;Zm4(;Zm4=;EQd";Zm4+!sA`,j9,O;"9GP(=9JZ[MZSP7#ErNt"2b/pj9LlV?iop#!TX@+lX0n^ZN8hd#.n7IDZg*b"9\dZ"9I.R!e^XY]`\Ac!SdeYe-&kV?ig-*!Sdn6gL(8=b6!>$!m=sT#3,a>bQbC]V@V_g"9O5W1]UGW])gUodgqZD"cRCLG6ub5#lFhT4F[O!4q#:c"LJZ'S1=u[quhZY!M"?8!L*W/]G*b`j>9%+.g2@Q"/H+5lur]i%Fbdjga#RC"e7ae.r5=;"=t#;"<:Ad"9_sT"9I(P!T-fYc;OiK!!!!"*<6'>"9PU5!n^ES0N/)W";q=fBFjb]8t,qd%]g@`]IY<2,Q[NF/0#,+!PAP5ZijJ6!PJU:!Q5*D]EA89?j3;+!OMm^gL(05qZ4V9!S^u_"1&$@X95M2jDP/%;Zm4(;Zm4'+1)'1bZ,JW]`_"@"B5L)KEME[">"TpFE7JA)bn3Q]*&/!!LtkFDumQR,Qn.D!K7&p!K9h/"9FHQP].^s!JCRVG*<%PKE)%+KJ^jQKE8mi9Eh0l!JCK<?j!H/"@N9s"9G<:";Xo="9;@'!TX=c=9JZ;MZMlA"2eLK",d3@!PB(Rb?tFq"9GS/"9IS%!M33m%T<K5zaVb'Y"9\e+e-"W-X94+e";e-?HuL[4OAc8b"9XG^"9a*E"9]K="9]!/"9G`*!k;/3]`\A#!Ls8nPQY(k?j;Mi!Ls4d_dESQ"9FGd"9HGZ";"K7HuOK!-;t$MOAc8b!Rr@q//"^^!jc)>!Lt\d/K=m=Z31:5=c3[hHi]gd!.6h[8ZN6cHi_'2PZ.^RUJ-%9!OH/;!Ug.R"9\aY!Lu&H"9_g0!NQ6sWr]"!"3Y'S!ODfsN!,&H`,>bZ;Zm4(<!35f9EYBs_us0FBjJmaHmUPB"9\b6"Fa8P!Q5'C=9JYplN+p,#-2,5#)`MP!Lsg2K4"kh"9FGe"9HGZ!PVJ8=9JYp!sA`0!Q5#WUL42QK)qJE#0UB[DZg*""9\bD"9]!/";H&Y'H@5nitA+k&cndu0H:38>8/%["9FO@"?o`e!)?GqzWo5-%;Zm4);Zm5J"9\b`"9G`*lu5l+,R;g),QpdT,Qq(';Zm4c)$DKEV)/;X$mYrV'EPgM!P;PEE+-om;Zm4c;Zm4="9\gW"9_1m"9OBX"DC^:!NQ7f"9IQd!UKqkgL('ZMZMlC"Og`_DZg*j"9\db"9_M!j9(KB"BYd-"H*<Aj9;#\?j"jY"9I"F"9OO#"F*iJ!T6lZ=9JY`!PAO<"9Fa.1ii]9E*o@C"9]4Y!Q5#R$e/P<U]JC6E(5`o]EA8ZWrsRH!!0`00Ui*U!PnfL!m:VW!L*VD!K7&lZX<uqDZkFg"9\bL?^i*8,Rb;R'N?=\"On\"A0ahg``!!C"9I9Yj9,Ls"BYd-Wr_Pi!TX@a!LmI1!W)oQ!UMUMb?tFiZN9+l"1)A;DZg*j"9\dbU]HKS6o+rV9I'`d"B%W-<=[5p!TXaO"9_g0!fR3a]`\Ak!fR6_j'Vu$Wr^uY"QNkl?lK.-!Rq=3!fV%#?rI12Ca9-7F<guOKN0Qc;Zm44!UKq9g]RYY!PJU:"9IQd!UKqkK4"`WMZMT<#D6Ce!M]\V!Rqcj!fV%#B2\p9,U<Lt2ATZc;Zm4[!!!!/)uos="9PUD!SC<R&hI,-,Qo(q";Cli/-J?d"9]uE"=+g_ABP)n,W5\5TMksr37A!2"=u*C"C)'eN!'8c"C-!K!VdE,"9\ai#IFNH!K8\\!K7&NErhL.!Ls:'&*.PJ!K7)M!K7&DN#D_]N&gJ1!K7!Z!K9>)!K7&q!L-h^UKdhY#-2,8S8SO(;Zm4(2$>H9;Zm4+"9\b0"9G/obRRPS3<Hi*"N21R/56?(]3>\#S2:o]/-Id1/-H)-"9\b%"CG(1!Sdb[]`\A;!OMt1"9_g0!NQ76ZN7E9#)cjk!W)o1g]P`-?ifj"!NZCHb?tAJMZMT8#(p:c"lfWjU]^3rgi!;r;Zm4(;Zm50!sAaF]EA8j"9GP(=9JZ3"9GS,g]RYk?j""A!NZ@W!o%*U!W)o1Zi\ui?j3;+!Mfq3!ShSr2H'_]zQO!Qk"9\e+Ug,<H'!,IA";q=fqcaac,Qo(h;Zm4[;Zm4/>7<V0"=t"_Rfik@,]Ed</0k?D">p<5zpE0G9"9\e+"9dpe"c-([>9""J"9_2P49gU?@aeO$,QnIm,QpM/":+!e"=.4t9Is^""9\j*"9_h*"9]!/!R)?Y"9H1==9JZSK)s1!"KPo8"02IP`!4+er,2]=;Zm4(,QdHN":+6n":e?5"@uGo"K56%qu[')"9I!Q!W3(&CL@7V#FbbD_ubj)r,2]=;Zm4("9\ea"9^qf"9ceEb=GP7,W8[-E)QlBqu[')"9I!Q!W3(&ZX@OKb5p)t#Ff*'DZg*Z"9\c']E+U&"W<7-!R(bL"9H1==9JZSK)s1!"f#H1!S[Y!e-(\;?j+pZ!Q5&o!W6j=-;t$M4CKd/E*B:F;Zm4K<?*PjYlm`o"B6WI"9_+<KE6m-"BYd-!PJV`!OMt4]E*t4$!E/e!PBDa!P\i?/>E6)ZiC-6Zm,)BZiRuDP^H+)KE8F\?j+(B"EXh-"9H/R!h`Hp!LuP/3jSr?"9]uh#ilh$@aeO$E,q-F;Zm4K;Zm4',PqP.,Rb;Z6sLu?'P&Hl"Df=d!T-fY";q>1/0k?To32Vk#Q"W["9]uhX!C_EmK(`>;Zm4(!Rq/DbQM#N!PJU:b5p)qLoXnfgB#M!LoXnao)[>A"M8%HDZg*Z"9\c'bQ5IW!PJU:"9I!Tg]Ra^"9GP(!qQHBg]ZYF?ig-*!R(],j'VobK)sI)"g_SBDZg*Z"9\c'"9S<r!KU.^!eprd"9]u.#D?\f"e6h@<$VSt">*:MY#>H+!!!!""onW'"9PTgoJfbP[h"E2*#4tE"9]SF'Q=iJ_cmNp!P9==";E+E"9]tq"9]!/"=+a]!!!-Zz!ir@GaAW3E;Zm4)"FLIDKEM=h"BYd-!OR=Q8V7&?!OMlp"9\b6#1uiWkYhTe^a'$e"ADJi"9^h4irg`.!OQf<?rI12=9JZc'*7.sj<Ud6?j,Kj!Rq4@!fV%#cr1&M;Zm4)"nMeW6sKk^YYtZ-6j/;M"9QbIb9p3k6sMnV\5NM5;Zm4+;G8WZ;Zm4+!Sdj/"9H1=Mus1c"9IQb!fR7aj'W&^])morH';V<!S[Y1jEZqs?kS@u!Rq=[!fV%#TMksr"9IQg!TXAcb?tOl_ZAg[Cm/6-DZg*j"9\db"9S?s"<^VG#,kH'";q>1<^ZtU"9F5:"+X;Q=9JZc!UKplli[?i?j)Ag!TXWHK4"hW"9I!U"9OO#jA/\W"BYd-]`\Ak!TX@alX0h4qZ5IV#4#Xt8W*W1e-!m%N,Jh";Zm4)!ltJZ!OPH%%T<K5/0k?D5#VRek#2Bc!JmcW"@QK2!f0bXTMksr!OMt4gB9W[!PE@VE&P<2ZigEJ"9]kK"L(f-])W6j;Zm4(KNPQE!OMh2!OP\8!OMmDP^EYXKE8F\?ie.G"EZlo"9H_b!oQu[Wr_Pi!TX@ali^Dn?iop#!TXF=MdQ[W"9I"D"9OO#^1U@Io6!G%;Zm4,4=gQt!K8jD1e].t"B6WL>]>,W`$>IJ;G8VG;Zm4+&"<Tc'FYUJ4Bs-7"Crb\Y=;Fnb>q"4;Zm4(]EA;V`*@?aE)u!0"9\nX!PAHJ!OMm7TE2]%[K3`:"9\i."9QVB!fR3a=9JZcb6!V*#D6DU"02I`e-<NmN,Jh";Zm4);Zm4=;Zm50"9\dug]?81!PJU:"9IQd!Sdf[UL4=ZP6'_PMdQRA"9I!T"9OO#!e=2P1aE2D5#VReY#>H+-Gorf"9GlK"E.3AFE7JiE+SVDo)o*,!Q8p]E!N-@,QnL^!OMmCLJn<Y!JTP86sKc,?rI12Mus1c"9IQb!fR7aRpZECRfVRR!UF+uDZg*j"9\db"9bo,"J/Np8d#1`"9\b4_Z?B.>QLu`;Zm4kr"mj9&`e$:mfWg,">!4I"9_[L9M>K%"?[q4Y!,be<XR=W"9F=Z!o?iY,QnY5,QoqtV-F.&"?Zef"9`6\!!1YLzWhKn%;Zm4)CU4%l*&[hb(fLP?/5850E!=\n2$?$(>:_l>1]`91,X`m\4A7"'"9a&S"Ai#"ZN*o,$kbZf9I'`l<$VSl>U0Fd*`E1E";q>!2@^:N;Zm4ClkeGQ#D@7&!Mqm]2$?#E!!!!%)uos="9PU0!ROaJ%b))\*!tC:!TY+$,U<L,Rp-:PS1GWa,QoY!"9\iZ":P=:9QU@>"9_g0e225oE,2K\"9],1X*as)e,XkP!JCRd_ZY(&N,SfO!P8I8"9Fa+S8\Y\^a'$`Hi\m$Ht*21!.78ZHr,HCX*ara!L.[1#.mQV"?['""9G$2";"K7"@c;m":.p/('1Q@]`\A;"9\i.ZiSqa"BYd-!V6?IZj2e&?j;Mi!ON&`_dE]GqZ3c&#/agL!W)o)!OPL-]3k`1"9G;&"9I:r!-_?EzWmVdc;Zm4)"<7Jn*$bY)"9IOe"9]_r!jGT+=9JZ#qZ3Jq"g_S@!qQGg!L+7*!R,Hb?rI12ErgpsA@htL!K7'7!P\a?"9\aYU]ZEO"BYd-Wr]:)!NZD)F'o%G?m>]J!L*VS!R,Hb%T<K5"Pa(*"9F0J!ROaJE$iI*"9]7r"9^)N*fM^M!K%]K"ABkq"9\j0Hj"Nnb5nD[:MnQeKO4b5"9Gq3YYtZ-;Zm4);Zm5B;Zm4>"9G$9U]^_3"BYd-!W)nfS-/@j?ig-*!Mfa[j'W)G"9F_g"9H_b"?9<_$j!X:"9J]WUM^c&"2#la"9\jS"9^AV"9F$Or'40`E!#nF#*].IK*3?FHiSO%_0gae"4MVuHi]IRMdRc'DZi0+"9\aa"9H89!R(WK=9JZ#MZM$)#/agN?s<Z-!L*fC!R,Hb<`9,(mo'>l!NZD)U]^_!"BYd-!W)o!U]p'l?iul!!L*Z/!R,Hbel)\S;Zm4(*!$)[zX.C40;Zm4);Zm4/;Zm5*;Zm4_!Mg"RS-2ps!PJU:9*(OcU]g9s?im)(!L*VK!R,HbkYhTe)$En>TEO9X"=uG3!K^4_Wr]:)!Mfi!S-2ps!PJU:qZ3c$#.n7D#/^J3U^"G=]3nhDirPYSU^LQ6?jG]m!L*\e!R,HbLf4EZ;Zm4+"B5WQ*%ZI_!o.$\oIM6j,RD$a"<7]s">!e'"9`6\":!4O!JjYWi)9a]^aoTh"C,14"9^8$"B9VE"=/@?49:*\g]UM[>U0F\A0_:/Ca9-OE,_QT;Zm5F"9G;g!Mfj#_dE_5b5nC?K&^6#"9F_f"9H_b!pEPcYYtZ-;Zm4+,Qo)6,QoZ',QpMG;Zm5>V/uh?"B5L)"=/@?49:*\MZcp_2?A=2;Zm4S!Ls=L"9H1=bQ@tN"9G;!!Mfj#"M8&7"1nTXS-PNk?j5Qk!Mk4oMdTo0"9F_j"9H_b!T6lZkYhTe!K-aV'FYUZC]XP=F<gu?HmAh7N`-&`%KW=+"9^866ijMj"Df=dFDrF^HmAho5Z7dg]`\A+!Mfi!S-2ps?ig-*!Mh*T_dEVJ"9F`C"9H_b!LH^f2Ac[_;Zm4S!ji!B!JD^$"B&Jef)^bu"=uG4!f0bX>QKl."?[)*/.&C'"EYml!QJ%@!lkDL"9^86!W4!;+8]7N!M!CW";D$X$tNTg<!'[9A-&32">*j]E%C5W;Zm4S!Ls7`"9H1==9JZ#dfGsA"j:9V@!_pM!L.9H!R,HbVc*^$>7=a<>VmQ"*!;^T/6jG'"Crb\"9;@'"D:X9!R(WK=9JZ#UB/RA8W-sa"H*;VUe-JP?j<A,!L*]X!R,HbDc6cA>U0FdRp-;3S7GS'>QeR<"9\iZ#5hk-Dul$C>7=af>YH7:"=+#<"-ujg!e_/u6k.X/"Df=dFDu2oHmAhoKHp[G;Hu<b;Zm4+"9\hq"9cG;/9"=ASl5ap;Zm4*!!!)_z!ijQe^f(@=>7;JPMZa'm1iNJI4<t%D,QnCc&d/>*;Zm4/1aE.D"9\j*]E7k,"BYd-j9#Mf!Q5*Aj9,La?ig-*!Q5+nK4"_db5o6Y!i'-*!ODg>]EIh6?j*e:!NZBm!T\/%Qr=+jL$JjC";GeU"@c;m!PhV:";q=n!Q5IH;Zm4;;Zm47S.M2c*TU$95>q[f!MqUU,Qnea,Qo)L;Zm4k"CqPC"C)(3"9\b=KQ@0Y!Ls8nWru[K!MjZZ!P\a?4.?8@!Pnf,"9](M%($&M#_Z@(qZ2ot_#]d%K)q2;!L-goo4.ld#_QLdUi-B8;Zm4(!M1i#"9]r?]E*O]"BYd-j9#Mf)Zf"#]EP'<?iop#!NZ=V!T\/%[Sm;3;Zm4(!TX9r"9ImH]`\AC!PAO9"9_g0!TX=c"+pX8!OOpr4(&3?#.joKX9QjUjDP/%;Zm4(+e&Mp,Rb;B1diSl"9a&S!M33mzcS,>!"9\e,ZjZA%'I3e^#1.(r"9F06$h.'tOAc8bX;B=eF:8c_!PBZ\`$>Ij;Zm4(#c%g[P]0@o1%PMKL]O#b!K%!a!n770"9_g0!NQ:WqZ>OU!n1NX8':t``)Z,2r,2]>;Zm4)UBCnm>\%f#!K89,>7:Os"9\pu"9^DWoEXkaFodO2>7;2kUBCV0!K:uH:/_8uQr=+jPQR]`PQ@9T!K7-^"9\iZdg4#n&cmq',QoA$"C(tt"9G;DlYf])2@,rY;Zm56!K7&P"Crb\#`)C^"T/Mc":<^Z!NQ:W"9R'U!mCdL"9H1=!W)rRbQRNF?ig-+!n7AE_dEVr"9QLP"9SL>RjM&:A2\W8cr1&M;Zm4*#/^Y\"CsD<#bY*!PU$AO,Qne^$g[na!MgtD;?;_-;Zm4+"AB!G>QLoO!OO*T!PgMp"9\aaoE!9:!PJU:"9JE'X98Z."B9FDA9.gZErruW^B=[U"9Pq2X9#R/!ji(3Wrt8#!k`Jf!P\a?!iuI1XCD==r(Y?9!j#oA!j$"'!iuF=PQCD<quWr#!Ku1<lik:7]PdoR;Zm4)!mCf:"9H1==9J]TlN595+5:0,=lTS5`!3h]r,2]>;Zm4)g]R]J"9GP)=9J]T!sA`0!mC`D"9H1=!V6BjbQm`I?ig-+!rQg!RpZ9ob6$H&"e/m)%H@N>`'KSpr,2]>;Zm4)!MfkFj<Op,<?+C-!NZ='!JD^$%T<K5]`\D\!n7>R"9_g0!rN-'?t099!mCba_dENBqZ>7LH';V>DZg-["9\f("9JL#!T6lZ(Babt"9\b8bQXY<!PJU;"9R'U!mCdLX'bt_UB8pL?,L%XDZg-["9\f("9Q)3"34=C!)j"'qu[')!o*n[e-#fQ"BYd.#D3*5r%-$!?id;0!n8dE;db!rDZg-["9\f("9P5pN"6<?"9FG^"9`6\"9Pf+do]NO2?T$_"9\b$RfesT&co(_,Qnei"De+O"9HFddi_Ql&cmr.,Qp4<"CqP'"9G;D"4gBRAlAg8=9J]T!o*n]g]RYY?j!_:e,b]l?icGm!lS7%!rQs>Sl5ap;Zm4*!mCb-"9H1==9J]TqZ=tEe6?;]?j3k<!lP8K!rQs>^/G.;;Zm4("9\bp"9FfeN!*o!]3>[E!K8QLA/kW?!K89,Y#>H+bR+1L'EP?;%"ogg"CqoR,QXD\!MgtDX<[pR;Zm4("cEH.A2XM(E)QlB"D\,C]3>\3!P8I8"9FI#P]._n3SOZ;0EI\_Muee=,Qoq)"C(uO;utJo!Seq'Vc*^$X:+(m"=-\BMuZcZ0GaimT2Pjq;Zm4+"9\kZg]XNR]3>[H!N^Yg"@N9\]0B3s2?DY8"9\b$"FMh#KEMDq"9G>"f2DeT;Zm4("9\eG!!TN(zWq.83;Zm4)"9\j`_Zd8C,W7UcTMksrU]`4O!pBaf"bTi$J5ZRR;Zm4-1^!iX1^!iUZNN,g&eE2k,QneiHNZ/n;Zm4+@5L)S"9\t*]*(T%"jB&Q!Pg5h@5L)/C7>>?">hrS"9\ib"9c559Q1/n!Kk8&b61d`"C,mH!r,[si[_??">hq9)pAFB!OWDr!Q5K'"9_g0!UKmk"lfX%liXS%?iu;f!Q5)HMdQ\:"9Gk4"9Ik-"=@%M!Ls5p"BYeKEri'>9"P42"9GTC!P]*9DUT']!M0=fL%>>@_#^>4gB")N!!/m/1p[4Y!Pnf4#D3&Q!L*VTdrYVd!L$moXD\5P;Zm4(;Zm4e;Zm4_>7<?<"=tD%MZc-f6uW0X9Q4bM!K6OP"9_\C_uYTk"BYd-liR@n"9H.9_up+S?j=dT!PAQ9gL(2[dfJe="Iid#!qQH2Zifo-lu*"-;Zm4("9\b6"<;AZ]*(5A"@R3YKQ&!E+Zol4;Zm4+;Zm5H^aoU21d!l$$fi!\L$MqO;Zm4(>7<=u">"MM_ZW(I"@R2F!f'\WWr^EI!Q5*AbQM#N?ig-*!Q5+nK4"rMo)Zc4!R"jQDZg*J"9\bl_udDH"BYd-"02I@`!2--?ieFO!OMs0!UO_-f2DeT!R(ZI_up+A"BYd-]`\AK"9\i.bQ7&4?j3;+!UL!M$Xa'p!W)o1!Q5@Ro3_[$"9Gk2"9Ik-";Xo=!No?(ziYqjt"9\e+/-4*r"9a&S!k;/3W)Eg%llOXZ%HIs-cr1&M)$D2eW$ps7"=,l,"Ai#"!NQ7."9G;$X98R;"BYd-!W)o!U^#R]?j3;+!ON'cgL('ZUB._+!m=sT#O;Dl!M"4=!Ru#j#ZCj/YYtZ-W&pIN"=,l+!O,K*=9JZ+ZN7-1!LmI!"NphIS->Bie8GHj;Zm4("9\h"<!/dl9E\H#"9H1=Ergps!K7.LZNONS!L.O@!P\a?(Y\tLN(F&/^B=ZH_Z>Dk!!.b&=G$X-!Pnei!h04DKE7<2?uo9J"@NKq"9Fa*"<^VG"/HJZ">p<5/lMlU:/_8uj'*3K%BK[5!gEg.e,fln>9#a-">#%T'J'B6"9IOe1^"gU49P]g"k-Zq"FC8&!)j"'>8.7RF9DX)1_9LK49P]g1TO_""FC8&E&iOR2$>H]"9GS,"9\j0"9I!S!NQ7.qZ3c$"/B6)"eu+*e,uIR?j<Y4!NZBu"f#HuDZg*2"9\bT"9]cE/-31X!TRAu"<B<%"9J]_UK\^#;Zm4.;Zm45"9\bfX9$fQ"BYd-9q)15X9F5a?ig-*!NZHW]3kf;"9G"s"9I"j!B*jZ!!!!=PQq0g"9\e+"<8O_"=,fL"9\jSg^F4h0H.#'"<7Q_'I3f!/-4d85+>ab%T<K5znf@c2"9\e+_uYBe"BYd-Wr^EI!R(ZIP@+WJqZ4V9`,f;e?j$!$!ON'K!UO_-cr1&MV(;`N"I'#iS0SU:;Cidi;Zm4+;Zm45;Zm5J"=+,3TIU-_"<:YI`%P$l"BYd-]`\AKbQJ%L"9GP(?qUO=!Q5-$>@7W0!W)oA!PDWE`*6VB?j;5a"9GkS"9Ik-S8V=/Z4cdN3#[GN!S^WpLf4EZ!R(ZJ_up+A"BYd-!W)oA_unb%?io?h!ON'k!N$42"9\blRfVGG>QfQY>8/V.1^!j>">g6%"9\i/,QWEo"AC'D/-3O;*$bY<&5r]7XAUSh;Zm40lN@6L*%Z&%*&JoDUBFIG$kdAW4<t%D6mMm\,Y]fmE*f:B,Qo)<;Zm4[>9l=D">!9*UBC^H&(GP=7T0Em0N/)W?;gt0+&`:F&hI^cj:hgb*'>JV"@OL<!T-fYliR@n"9HFA!PAP;"9H1=!W)o1!Q5pb)dick",d3H`!2E5?jGuu!PAW#ZX<h2lN+p/#I@eC#Eo2,Zj4KVV?Vt["9IiiA8Y<K"9_g04ECOfE!P,[lO<D*$1)U[+T[f1!Ls8qP6=!hoDuu9%atOc"9GTC"<df9!Ls1T"9F`*4ECOnE!P,#_ZU"9!N^6W+T\)9S,niW!L+K'!L.u$gB!N=_#]ctZN69k!L.+!j(&1T#(p:bXD\5@;Zm4(*(C#'"9P&n!madJ!!!u>#QOi)"9PTg,WJ^*/-Hgn!rH11!Lt\T<SIX%"<8D#"=,ND/0$Jl"9\j**0^q3!QYB0!!!/gz!iko6YYtZ-"9H.>_up3F"9GP(j9#MfqZ4V9"G:(_"02I8j91*C?j3k;!PAZ$lX0ms"9GS."9IS%"isUF`'=LD"9c@<!mjjK!PnmQ"9\df"9jlc"1V84!J1F_9f)uH;Zm4Ke-,D&oDuWEJcl2XGOmWl$oASR6ihlBJ5ZRR!Q5*B]EA89"BYd-j9#Mf])gsn`&h?/?ig-*!PAO+j'W+E>62A?X9?FKjDP/%;Zm4(#4jZP4:D7WQN;c?":P\>]1bU<"9Fhi,Y^)ucr1&M;Zm4*b6.n!&%$;$M@-FsZk!!7!PJU:"9H.<!OMu3_dENB_Z@CTX=I[cjDP/%;Zm4(Ft<`_"9l\6!mjjKJdLK@FNZKA$oASR"@OL<"Fa8P"><[V$l;hF9EEfL,Y^)uAlAg8"BYe;ErhL.S-/kOoMfl4E*A_7"9\b$!Ls2*!P\a?@"SKEPQ1`KPS;4@PQAT$A-DK)!L*VL?im*6"B5Q*"9G<:!WQ($j9#Mf"9H.9!TXAc"j:9m#3u<&X9OSjjDP/%;Zm4($e,489EB\I!P\a?HNZ/n;Zm4+;Zm58"9\eH"9Q#1!TX=c=9JZ;"9Gk4ZigEC@pgM^"1nTp!PDoMUL4/("9GS*"9IS%"9;@'#Qa;q^/G.;!TQ!;4:D7W!LEi!!P:`&":P<t!N/j!"D\,C!O;h2;Zm43":P@XWrrPC";Gf+*,n-;^Jb7<;Zm4(L+pLT"=uG4!RF[I!"B)5z!iqh:fM_nU;Zm4/"9\u)is)_d$kc6@,Qn1m>RKh&g]Q&MIgi+_"mddNU^*tb.h/!W"=+Gp"<;5'"9`fl"9k`&!N8p"K3K=#HN["D?/#Jb"9_D;oEP(h"BYd-?s<[(!VClj_dF7\liH/WS,oJl;Zm4)!V?Na"9_g0!NQ8!qZ6Tt=mKGr?jd#-!VBO\_dEVZKE:-8S,oJr;Zm4)"AAs>%-.P<9RL!D%#bMb,RMBm*)n0d"9_Ur]PpmB;Zm4(!K7-5KEPB[!PJU:!PAO<o)pUc!Q8ppErjJfP60N%!Ru&lE*r3)bQJEg"9]kK"<dfYErj2^]*->_!R,p*$EOB3":r-K_u[UU_u[LO]E*fh]E7!l"9Gq3AlAg8";q>1,W6,_YYtZ-2i@eBj@gh<lN*4V,QoY#;Zm5&BEFZ@"9]u.liNPQ!PJU:!W3''oE52q"BYd-#0R&6r!091UL6^qUB0ukLoXnc"9IQa"9P*3"BSM)"IN*jE*_3$,QoAd;G8'0;Zm4+"9J,p!V?Ls_dEVrirScQ"e/m)DZg+%"9\dr$hQtg"7'/2!lPDp"/J>/<.>764pSGW!k\X-r$r9<,QpL?HN[#I%BBU7"9]uhK)q<;2?Tl]"9\qqoE0nJ"BYd-!W)oioJ=Bm?iuSn!TXF%!h=03hbsX\;Zm4)"9\b6"9Fif9EDpc,U<Ldcr1&M,Qo@o9H45;!JgkV!PD#-T2Pjq;Zm4)!UKmN"9H1==9JZs$N]l&lii#L?ig-*!UKuBdpN4R])hO.j@`k_S8SN2;Zm4)]M&C("7'/%<$VT'>U0FdmSa5k;Zm4(L#W3s,W:,Q3)]q_!PCMcMZLHj!PAGp!PAHL!JC]1!PAGt"-WbEHpc(br,2al;Zm4.PRlhN)SBkr^/G.;;Zm4*"9\acoE(Nb"BYd-Wr`,$!W3'$!RkFL"j6t;oE!EK?j4FK!TX?`!N#qr"9\dr"9G,n]PnC>;Zm4("9\at"9ICY";Xo="<LJEquNWf,QoA';G8'0!!!!%.f]PL"9P\%'@9Y\8/DDVpeq:u$iuS%<#E5O!LtD<E'4"#"9\b$%"'a->RuHkHp&d>n5BGm;Zm46"9]FC":Fp&$KtCkDuuL3qZHr$!OQeHE,5%J/-H!d!Ls2+!L*VT"9]uY`!E#7fM_nU:]pn3!iuj8"9_g0!n7;T"LA0ZX:Oo1?p*0F!h=Go!n;,k\5NM5"9PA5X98R;"BYd.!W)qoX9\'!?o@f_!h9J$!n;,kfM_nUHi\m0"9_t<X9.<Y"BYd.e,ogVb6$/p55S^k?&JccS3Q=Ie8GHk;Zm4)"9]8!"9G)m!e^XY=9JZ[!fR6bS,o.$:_:MK"9\dj!fR/p!fS.`!fR/O!fV;tgB*<6!fR/8!fR/r!ebTH!fR/EN3`Q?6b?_,DZg*b"9\dj":XKm!J")O>X2iC"9\ai"9]97"9J9r&`?Rj!Lu*l"AB4:/-2gt!OO*T!Pfr`!Ls1\"AC'D!T$`XE*g-ZgB7PI!MjZ=!Pg5h"9\aYK*%'3"7Q>N"9`O!X:)O:"BYd.]`\D4!i,r"]3k[:K*&,8#_QLeDZg-3"9\eU!P^$]lW+%N;Zm4+"9]%XK*^C66oGhdOAc8b,QoY!"@N9l6ijY?I!ep>KPVn:6mMm9,Qn.,;Zm5F!i-"H"9H1==9J],b6"IBLm)3K@fi_4S-#0fe8GHk;Zm4)&EEkYj=1Fg!JCRY!JCS!"C,A_6uWC+Y>YQ,;Zm4("9\e)X9-lR"BYd.?lK0s!iuRkb?tS@"9P)B"9R(k!N&cuPU$A_$iuk!"=reBPQAN%"9F_f"9]tq"9Q)3KE8k>Hi\m$Wru+)"FP.t%bO\_Sl5ap;Zm4)"9\pjlO2?Dfa[j4"=+BV;urd?!N[OL9`^I];Zm4K!MfbK9ORslLf4EZ"9PY2ZigM6"9GP)!W)r*X:>&7?neV_!h9Y1!n;,kBN#$:&q!?AiWLM8F:PAQ!L+i4S0S4W,QqWY"9\b$b6,1OPS/@W,QpL@"C(td"9F`4$^aiqaAW3E%@@M1"9_+N"9[jd!P\nn*MWab"9F0pN,W%nKpr2G!L.O(Qr=+j;Zm42"9\bOgBj6G2?em<;Zm4k$kD&V<#E5O!MgtDE)N/._ZU"A!OQeaE#O?3Rfic)!Q8qB!Pg5h"9\b$qZ=6*&cndb,Qq?\!Ls1t!PBZ\`$>J5^aoThU]I7lCa9,a$%Pm2"9`O!"::/g!n7;TWrfX2!iuM*ZijJ6?idS8!n:o4dpN3_lN4/$F1YgpDZg-3"9\eU"9]Q?ZNA]V2?^0I;Zm5>\7pk5!K8o?aAW3E;Zm40!L*_2"9]uE"9P2o"2@b;=9J],!sA`0!n7;$MdQY!o)c"2#/ah8DZg-3"9\eUlN*AO!T[T9"9\aaS-=FAlWXc(^B=Zi"FPRtK*5F)"@R3H"TD=&";q>Q!MsT8>7>TVWt\0q,]l0O!P;PEpeq:uI\R#MHpe!uE/Rp/KHp\"&aKQ#"9FI#P]/kQ;Zm4(NT1/%&cnL'1^$J\!L*Vd!OO*Tpeq:uCBObB>7>TVP6:ou"@R21"ijOEe,ogV"9PY+!n7?TMdQXF])o&K#HM6?DZg-3"9\eU"9Z_DHj"3f%te'p4YtP\;Zm5N!L*l"6c3+:4TUHd"9\ai"9FQ^"c$"Z?rI12"D\,CKHp[O$iu:f">&kCKE8gj"9F/V!JE9T)oGkgN$JNG#297]"9Fa+!m":C"ctXc"9FH>"<LJE#Hgu.=9J],,6FqLXA8@p?jE_6!h<r9!n;,kL/S3X(Bf*h"9\hP9ENL<!P;PE*4lI2UBGs`!JGE?E#Y8L"9\aa"9H#2N,UPq%`8DM"9Fa+S8\N+"LA43"9G<;#DQ.[ZWdic@=1`M,QoZ'$iu$/"<Z)s#JX1?!S9,c"9FH>#2W8]"D\,CMd$U;,Qq(c"9\aYo)mQB&cn5B,Qp4<";Cm4"9GSL"ohL(]HdV"!Ls8n"9^8M"GRCbHi]*-#k%nk"9_+N":4^"!M"*:+T[N)KE7#7>Voji!JD^$N$JO",QpL9"9\aiF96tk#,`7?LJn<Y7LXYH*!(cZ!JD^$N,U!E(W-@V"9Fa+#)6%Ze,ogV"9PY+!n7?TP@+L)ZN@3T-Bhg>8E0cQ!KXj#DZg-3"9\eU!j$TE"9_g0!NQ:/K*&C_5l4po=i1<B!h<1s!n;,kOAc8b;Zm4(!JC]d$-*hbLJn<Y;Zm4,"9\b."9u#-FDrYoE)53k-c6(7^&`n+!K%!d^a'&)"FPRt"9_+<1^*eV!LtD<Ua-'g!JE91'rqI8N&D!V;Zm4(!KRGWKE6r5Hq3c/"@NY2;uqq'!L+i4\5NM5`WsB^"@P-S#GtE&^/G.;"9PY0!i,s$"9H1=#5\ItX?i%X?lR8j!h9GS!n;,kOAc8b"9PA""9\b=!n7;T=9J],MZVB2UiToG?ig-+MZTu$"/B7IDZg-3"9\eU":FTrKPXhm!K.']%KVN-Hi]*-hbsX\[g'/F"@P-K>ZOc+!LtD<^]DX^"FPRt"9_+<Hj'FI!jc)>9OW;oHmAhGf2DeT>7=aDK*24e"@R38"TD=&z\fCbN"9\e+!PAD2"9_g0!TX=c?lK.-!PAWS,@C_nDZg*B"9\bd"9^,O*!*iR,Qntf"8c::Zm5bo*!?BR"9\dV9EFW]"9_g0"B9GiXE+Dq!K7-^Zik2dliFj&!K7-f%ch_QP]1c7"k*ST!Ls1qV#d@p,Qn5N!K7&p"<i-q_0e/a*W(3bgO'!K!Ps.i9EjI(9RHl*UL44_DZi0*"9\b$!LuVX#,HHRWr^-A!OMt1"9H1=j9#Mf"9H.9!TXAclX0gQqZ4V=!OH/7#5\G6ZiRL@?ig-*!PA['MdQdR"9GS,"9IS%"E%-@"?o`e1iPYM"FC7s!O;h2!!!!-*rl9@"9PX2$-6$J!LuZ\";D7W*!*,d!OO*T9`^ae;Zm4K"AB#M;uqq'!L+i4S0S4O;Zm4(?/l3`$k`g+!W3E!!mCdkN.27h$M7!m]FLGq.g:S9";D*J*!)9L!LtD<Ua-(*;Zm4("De=APXGQBG7C&Nj9j[IF=_nFgcbo6g^gIe"3`8%9I'ag,Qn.$>9$mI"9\bcYQX/g!OaNa;Zm4+>9$mmqZHr[6tC6;"Ip_?OAc8bCBObB;Zm4+;Zm4g!Ls>'!TRB(>7:P.!N\/BD7a!l,R3lT";CmD"9GT(!LtG=cr1&M;Zm4*"9\hrbQ4)0"BYd-Wr^]Q!Rq5Qj'W(LK)s1"I*5n"DZg*R"9\bt"9J!j!NQ7N"9H^L!Rq6SK4"`Wb5ofi1ZMjJ%^Z8L!V?DiY>YQ,"9H^I!R([KMdQdR_Z@sb8qUL]DZg*R"9\bt"9afb"lN;^$_.O9"<+?c!NQ7N"9H^L"9\j0bQ7><?j3;+!Rq:rb?tR-Wr_hr"j:9S"PWt$!PEJ]!N$A!"9\bt!R+nL_us0F!PJU:!Rq5T_up+Aj'Z'lqZ52.46']L?s<ZU!PE]A!VC:5<`9,("b6j,"9`gO>QhQ8"9a&S>]9_%E!`QJEf1'2"9`O["9`sJ"9[:TltQR^$.O>5oF(#0Ig>TV%_OVLe.0tl.gi'_">gRP.^N)m/.<.r1i+E?*-<G/4FACW!JD^$+B&CGJ/8?9;Zm4+!gj"U>QK]bLJn<Y;Zm4*CBObO;Zm4+"9\e1bQ7><"BYd-"1nU+bQmHA?jGuu!VA1c_dESYUB/Rp"I!3sDZg*R"9\bt!R*H#bQM#N?ig-*!R+^4P@+L)!PAGh!VC:5VGdU#"9G\-"FL6-!gZafPSjTL>9#1%";FRg"9^P,"=sSg!Tm;`!J@]]#NTE7jECsLbRB.01i.XFX?Ha9N"#Ue#/i"m"FC8Vp/;(sj:C#H!N[OVZm5c"9md'E;Zm4k(BdtC"9\b(6iruZU]JpI<BO4i,Qq@W,QqX7;Zm4c"9\as":P=:"P-KSE%L;XM["i^!JGh=$]GLY":Y23N,VCY;Zm4("9\d]"9Q&2"@lAn"9G>M&i<Fk,Qo(q,QnfL,QoYl;Zm5&"9\kJHij"?)2h]=[X8/="9\i."9e0l"/]!"`!um-"9F_f!$>,BzYGGY-;Zm4)X99fqU]I:m!K4i%$k`TJ,Qn.,!Ls2/!R)el,Qn.D!NZ=O!Seq'j<OkE,Qr2i"9\bln06L`Ue1aq;Zm4,".ULl"I(/7,Qn4f!Ls:_"Jd:Gi)9a]"9F`2/-46G!Seq'j<OkM;Zm4(!K79)!L.L*!M!Sn!L+!*!N[OLkYhTe!K7-i"9]uEg]rp>`$>He"9RWcliPBVe0G.u"9R?[o)e8s&d%\^,QpLD!lP1o",nK.cr1&M"9ZjalibNXe0G.u<?uA`"7u]f!LtD<J5ZRR1_T!U"9Yu2)<b!%=9Jf_K*C$546']P(6\pWb\H`WKPpts;Zm4-"9]g&S-sjGXD\4DZlnrBr!X2?`$>He"9S2tU]\gde0G/!"9Y.rbQHWGj<Oj/"9Rol"9\!9,f!=]S0S5*,Qq'J!UKl`!j!XMZm5bo"9I9Z_udRs`$>Hd,Qr2j/7\h+oE"Saj<Oj/"9JE$KE7Sglm)]8;Zm4(!gF>M!q[`@r$2De"9P(pe,t@LN$JN,<A\Lo!iuI)!h:M=,Qn1U!k\T!!LtD<,Qn1e!mC_A!fSB-V#m_$"9\i.HlAq^!Ls1\!K7&L"9a&S1iRK!N$JN?;Zm4(,Qoq(N#Vk__ZWj<&cne$"9F_q/-3+'!PBZ\,Qn.</-H!l!Mfb3TMksr"9I!hN!%QTga!")"9Xkj"9[^1+0\ZH=9Jd!"f)8("9G<>4EC\-E!P,#P6;&r"h\dn+U+qME6A@e"9l/O"<drEEs8WJ;j.?+"9l/O]Pn&'"iLNI"9\b%X9$*^X9GC'"f,W3"f+cVZN[-)_$-WD_Zch:PQ^VNoED#k?j?K2"QU2r"iP<^L/S3XW)];f!JE?SkYhTe"9\Q+KEL9\lm)]:oJudN":PnF*2ld=n5BGm,Qq'K!ji'j"7.99KN0RF"9X;ZMurVsr$2CI"9XkiS,o-*lm)]9"9X;Yo)k4q&d+Y""9HFL"9Y_N!Us"je0G/b"9PA#oF8GYj<Oj/"9G"o"9Rp8"K#*#i)9a]"9G;8S,qt%oHXP?<@h)M!NZO%!LtD<,Qn.T!PAH/!K89,,Qn.d"9\aiN#(&E1aE2),Qn.4!Ls1D";E*a!iJs""f)EfMZomV_$-WUdflNJPQ^mloED#k?uPoF"QX9l"iP<^W)Eg%"9FGhK)qcd&co(5,QpLD!K7&l!Q65dbTm=-;Zm4("B5][F9Alq"2#l^,Qn15"@N@1"9Zjn"Rf7l!Mg1Z!K7F"!OO*T,Qn.<"=sSdPQA]JbTm;l;Zm4("l'=7g]U^^?j4.G"l*1;OeZ;G"9m!M"9sNt"3+7B`$>I:^aoThU]I7lS0S4<;Zm4("9\nB"9_e)"9sM]!NQCb"9mQ`"loegP@+Fg#)!#8qd9N<qZZ$d#lA!1C>/pI!JTQADZg6f"9\p^1_Hrj!M!.0,Qn.<!MfaT!L+i4V#d(h4S&[V$k`T:Zm5c*;Zm4(!PAo0!TYL/,Qn.T!R(T2!V@W?r$2D5"9G"n_ubT;N$JN,"9FG_U]Qc+S0S4<"9F_g"9PAE$J88[HNXA.>7;2K_ZU"P">k':!qoOq,Qn1U"2k>$"I(/7,Qn20"4RID"Jd:G,Qn4V!iuO+"LKEWW)Eg%!J9VE$k`T"S0S4g,Qne^"FL6G"9GSL'VJA-W)Eg%,Qq?j!K7&d!PBZ\`$>I:;Zm4("2"]E"6:^1,Qn2H",m?K"8!iAYYtZ-"9OMb*!<i!"2lGf,Qn.<!ji'R"4SS!,Qn2("9\h^M[n*4&cneB"9F_qS,ouB]HdU\;Zm4(!Mfjb!Rr@t,Qn.,!NZ=W!TYL/i)9a];Zm4)",$lW"Pb7*<@e0("69RF!LtD<,Qn59"7u]N"3`"n,Qn5I"69R6"70q/"8$Gg"69k'"GA$'YYtZ-"9F_p/-3+'!PBZ\,Qn.<"9\bDA-eQ$!L+i4U]Htg%GV'edpPYGK)qJe>5M\phbsX\"9I!S*!<Pn"2#l^,Qn2H"9\hFquZ@dlm)]8"9X;YMuq3Kj<Oj1"9XkiS-%IkS0S4>"9YG#oE)rVr,2]>;Zm4)1^">F!Mfb3,Qn.DC!-OI$k`T:cVjrL"9I!Qg]E]cS0S4<"9H.:"9PAE"40sL,Qn//"l'04!fSB-,Qn.<"9\dj":"U!]E,f)"9H.9]E,Abb\mUbe7-T%":PnD#+&6kc;OiK"f)8&ZNPAk"fuYkE!=\n]EADF"9G>&!Pfr`"9\n(!mF\D"8jDI,Qn.,"1/2a"H4T/AlAg8=9Jf_]*6sm1?2aI)qtPObSZOOKPpts;Zm4-!lPAs!n;,k!o//"!mD&c!ph08OAc8b;Zm44"@NHSF9B`4"4SS!,Qn.l"9\h^S-S1TbTm;l"9JE%>QWD#!eaQ),Qn1%!fR0H!W42GYYtZ-"9m9eg]RYk"BYd1KED>[M["h=,`?%4#J1/pe0Kr[?ig-."l(A]dpQ"Q"9m!h"9sNt'Tc5rn5BGm!K*?T1gC*r^f(@="9G#+F9J*Z"12&Z,Qn4V"2"`3".UV>,Qn4f"9\aqS-.,:X<[oL<A[YV!TX:B!Seq'^f(@=!sA`0"S;kf"9_g0S9"k0"fqh-!lQp:Zu@Gb^B=ZCo*)2r8Hl1""9\n0"f)16"f*W3dflNI_$-VW]*4u2PQdQdoED#k?p)U8"QVH;"iP<^LJn<Y"9OMcoE!_mr,2]=KJp.;<"'B@"M>u_,Qn/?!UKlX!i.(E,Qn.t"9\e-Zj5Gdj<Oj0,Qr2j!gEcQ!q[`@,Qn1]!Ls5h",%p&N$JNo<?tNG"9\eE>Rd'!!Rt+#,Qn.t!Sd^G!Q65d,Qn//"9\b<N!@@%]HdU\"9G"q]EH.ubTm;n"9Y_."9d4"#k([p>7:P&!K8\d"9a&S1iOu2a&<*D^aoTjU]I7lS0S4<UiW"+PRJ0*Zm5bT;Zm4(,QoXu!Ls2'!Q65d!Pg5h!Mfal!LtD<Vc*^$"9ZjTZidBT`,>b\b[&Bo]F5DTga!"(;Zm4*!n7UM"-b&6,Qn15!mCb:"/I1F,Qn28"B5K)"9Z"V$a3J3Vc*^$"9mQh"k3ZW"9H1=!W*&Mgcrti?tYB$"jA<o#)$mtpJV1t"9IiroDulU!M]bu!W2uB!LtD<OAc8b"9G"rMugR:`$>Hd^aoThU]I7lS0S4<;Zm4(!LsMJ_dG-u!K7&3>QfBV!K89,k>MKdZiYmfX9%2g,QpL:!V?H#!k]c],Qn.d*(0kH"9ON^$i!X',Qn4&!K7/?"I(/7,Qn4F!Ls:_"Jd:G,Qn5)"7-/l"LKEW,Qn4N!ji*C"N2PgQ;[nh;Zm4)"9\hZliEt^!PJU="9e?"U]^g&"E\\goPbVi!P8IE"9l/O!Mot4^a'$c"9kS%>]U(ME!qj4"9\n8"fqa>"fqm'K*A%hSctorb6=[B!!T/rOg>4e_$-V8_Zch:"RH/N"f)0`7[!uIjF-W-`,>b];Zm4,X@*>e!jj3Y]HdW%"9IQb"9QLe$-,sI,Qn207!o*toE+Ybe0G.u;Zm4)!Mg.u!LtD<!Mikf"=sroPQA-:]HdU\!Mfi!"9]uEbR+8Igi!;tjC[-KbR>*doHXPA"9[E]PQUh/KHp[&;Zm4+!UL98!R)elDZg*j(Y\uG$k`U%,Qn.l"@N:__u]c]KHp[$,Qr2j"9\dbb6*i)&d#ES"9PA-<!'u`!mDnme0G/:,QpL:"EX_#S-%aslm)]8"9PY+"9S3@ZiRs9;Zm4)"9\sc"9l#.#.RS7Ws&>'"S;ft"9_g0FE7V]E)rG2]*&;="gi4LE!Gn:,Qn:`"f)17"f-L?"f)18"f)<t<Y(ru!O`0-;Zm4+'rqfD$k`Yq,Qn28!Ls7V".UV>,Qn2@!o*mR"0<aNT2Pjq"9QLQe,o7fr$2CH"9Pq3_ukZ<N$JN,<?s[/"9\e]"9I(P%/3['=9Jf_"9m9Xe-#fc?j"RU"l+*]b@#D7"9m":"9sNtKP49e]HdU],Qq'J!fR3!!mDnm^/G.;/-1\89EF0X!L+i4#a>@["9Po6"boqYY>YQ,,Qoq0"AAj'49<)?!K:#(Y#>H+,Qq?Y"?Z^D"9F`4!Mfad])eE))s^m\AYT9rS7BHE?pVs:!M"AgMdU%Y;Zm4X"9]!s6j;4A!OPiH,QnJ0!PAfq!LtD<V#dq+$A/H^$k`TR,Qn.T"9\bLN"<X$X<[oM"9P(rF9Jrr"3aarYYtZ-"9G"pU]c>rN$JN."9[-VN!,@jS0S4<"9[]flia+0X<[oN"9H.<"9c(WoDua$"9\8u"9G#<1iQ0I[o3D4)$G<t!JCRYN!'0XqcbTP,Qo(h"9\aiKFGUoLChrQbSnt3AIF_5!lPV6!k]c],Qn1m!n77@!jj3Uf2DeT;Zm48",%;B"7.99S5gh>"9Y.rU]ZQ$PU$A6"9Y_-"9X<&!rc+$,Qn1%!TX:2!UO_-!VBdC"9],GPS0QdS0S4="9P(o"9J-?!MojN!KF\o$k`W#S0S5:"9JE%"9PAE"/f'#]`\Mg"l'4]g]U^^?ig-."l'3\lX0n^o**V])=(Z3?m>j1"jD.Z#)$mt%T<K5,Qn1U!ji$1!k`FS_uYM&oF)?6e0G.t"9PY+"9R@(&-#Q2,Qn4n"4R@A"2lGf,Qn5)"69Qs"10<VVc*^$"9cpTPQC\-KHp[%"9OM`dfQ=`&d#.#;Zm43!V@#e"8!iA,Qn1M!Q5*<"GA$',Qn.,"0;Wa"I(/7s&0%'N-_fC>RV5G!LtD<Ua-'g;Zm4("9\bFUCPUK%K6Bc"9F06%*)9L*h3>.bTDd'Y9/]+"9d3TgfIDW"BYd1]`\Mg"k3YUMdQ^H"l'-9?icAd"j@ga#)$mtLJn<Y"f)82$H+cBgg<@:^B=ZD"9kS%$-lHPzPQq0g"9\e+"=+7O"<7P%$mYrnUMb]g!L+:-++j\A"<8D#"9]tq&r[<!!QGo!!!!Ckz!ihOl#ZCj/$*4m6,R1VN/-Hgn!TRB0"<B<%"9J]_o32nkHNYl(JWg3>*#rnu/1`%L!<b7_!!!!=p`oh>"9\e+>R%]:JWj:HS6RTG#Q%a,>QL'_YYtZ-"9IinoE53."BYd-"OdD<oEVF)HXM1$DZg+%"9\dr9E^_]"9]SF!Mp0W>7;b[UBCV0"@R2A!Us"jTMksr!sA`/qud(k"9GP(=9JZs])nK*!R"jQ!W)oqoE!-C?ie^W!TX?P!h=03J5ZRR;Zm4)"9G#gU]^g&"9GP(ErjJf!Rq6G"H6T,!NCFh#c%LVe,d;ee6^<!!Rq)M!P\a?M:2LL!!1:E2PU;s!Pnf\#Eo24!L*V\!Ls27K4"lC"9FHR"9I:r"C>"0*$A/_]+51C,QpL9,QoAt;Zm56"9\gW[fMRhP?('P;Zm4(!V?DI"9_g0!h9>q]`\B&!UKpigL('ZqZ6$b"oD[.",d5NoEG,"!JmcW!JmdaDZg+%"9\drMZ\K.$kcf$Ca9-OF<gu'+B&CGGZ+_J!KVMa"9_[^"9QqK!M<9n>ZDah0FHlG,QqWl;Zm4kqud&8"9GP(=9JZs"9Iilqud&6?jD;b!UO12_dEYCK)tUO"1)A9DZg+%"9\dr"9F9Vo.ErE$kcfM,QnL.,Qp5G,QorG,QpM_"9\aY!o.Hf"F1EOS-&ls!W3'%oE52q"BYd-"j6t;r!(VXdpOC$K)tTK0CrQSDZg+%"9\dr'EZQY1i+E?*-<G/"FMHtoN5#p<<]0/,Qq@W,QqX7,Qqp/,Qr3gc[;KU"B78\!le.AL/S3X;Zm4*"9\bV"9]351]b?i!!H2)zX03cK;Zm4)"=s`?$rfnG49h9Z;urLgkYhTe"9J,q!V?Ls]3ki$b5q5<"l!DiDZg+%"9\drS,q8@"BYd-ErjJf>akjQoE6^aj8m!s!Rq5["9GTFCi]X4!P\a?!R(SoFAWP7"oJPBS,pi&^(6G<r!/_mOoa&@!rN`5!M]^d#,DEm`!$C)!Rq5[UBEDp!ShWZ!P\a?!R(Sob[U\'bRhqu!R(NE!R+3K!R(S\!Ls=o!R(S/"PWsIMuh+0gi!;r;Zm4(&*s@JhuU%b/PH9K;Zm4+"9\kKA-_U&n9KG_;Zm4*"9\t^oE!TC"BYd-Wr`,$!W3'$46']n&$l</!T[0e!h=03cr1&M":a]$"9lS>A/A/IgIM@l;Zm4*"=s]&%!6;2#+GX\!M"6W/SkQ3;Zm4+"9\a\liN[Z!PJU:"9J,t!UKqk]3k[:)ZlN5oEDj7?j,3b!TX@;!N$1Q"9\drO:)%e";E`q!Uiqi?W.(1<`9,(=9JZs!W3''li[?i!PJU:qZ6TtB[^>i!W)oaoEO>`?in4H!TXCT!h=03W)Eg%;Zm4(;Zm4U"9\ggPQJQt9J$AW;$,6H$jHPCS-,92D@O5Z#a>O_qumFtS5^I2"9_[)libC.!PJU:!W3''oE52q"BYd-!W)oar'SY8?ig-*!VAb&ZX=@)>QNmr!h9:gpeq:uoE"jkPQA-*)$E>2;Zm4+"AAip"9XAp!rc+$!K[GZ"9t)K!QS+A&o;RJ,Qoq4%J0e9P]m2aX9=Ii!JGq'4p\eP!Ls5hZmuNS;Zm4-";Clu"ADK7"=s[5$rfnG,QbS^;urLg">*:ME'B`oJF`n;"B9=@Duk[Y"9Q;B"AAiR!ROaJ``!!C$D]3S%!6;21^9FRF9.nR">+Ems&0%';Zm4)C]jdk"9]uEliOn"!PJU:"9J,t"9\j0S-#2_?j""B!UKs4b?tR-MZNGQjC;R$V@Mqn"9P(o!fg1^T2Pjq>9m/M<'15o"B5Dl"9^;M!P_P9$Hrps8)j_f"@Nkr"9^;M!j>N*Wr`,$!V?KqoE88!?iul!!V?V\#(p:s!W)oqoEKqU?j#-a!TXF%!h=03Q;[nh"9J,t"9\j0S-#2_?j4^T!V?JXlX0hdX9%BbS,oJm;Zm4)9EYH`b6.r"//3&B"AC'D!p<Jbk>MKd;Zm4)!!!!/(]XO9"9PU*"B\S*!PAL;Wr\^n!L*]f]ED=>?ul,F!Ls7]]3khqK)q2@#.n7I#(lr@!L*t"P@+TI"9F/\"9H/R";k&?"@,lg":e?5$j!X:-W:-N";q=^Md%/H,QnfN",m@6"9\iZ"@PIQ9EYK#"9\b+"C-"iDukZn^B=[e.'%Fjj)esV!M4C/&X*=h_uKgsFDADlbB*d$!L-7[#)blk1^:j*"FP+jS:4B>5TBV(!!"+Rz!ik3!W)Eg%X9%qpe,c]k;Zm4A"9\mY"9]97"9F<W!f0bX"BYe;ErhL.M3A'I!M"*0!K.'`&**cH"2&hW#2F(UZiQD#B*"5'%ZCM>oE>DoP[V`EPQAT$PS:A(!L*Qb!L-LJ!L*W$P[k!IA-%nqdpNBlDZj#B"9\aq"9^&MZiR[8"BYd-Wr]j9!PAO9@pf?7#.joCU^)N[V@(fR"9I9Y/-&TO'Ef9Vo1/o7;Zm4)"9GS>ZigEC"BYd-!W)o)X9F5a?ig-*!ON#_RpZMS_uZY8g]=8Q;Zm4("9\a]"9FlgDukdd,Qo)$,QoAL%'0rO!q\'$E"VsM;Zm4["9\c#"9I9[!NQ76"9Gk4!PAP;gL(8=gB"Y`!R"jO"1nTh]E-2`?ig-*!OMmNo3_d/liEm`g]=8T;Zm4(Y$('e";E`p">3UU!T-fY=9JZ3!sA`0!OMm_>@7K<!V6?I!OQ'=!i'-rDZg*:"9\b\`&&N6KWA;`%\+dF6jMLDS5B`[$k'ua]F'lQD@PY5$'YJ&S-9+mHNZ/,8^deF";E\3"=-)T1aGI7oFqF+,Wm=Y,X`m\"9_UZ"9G>U4<t%D6mMm\"B%'%E"A-84!XqC;Zm4+!!!!`#64`("9PTmRikW4&gRL7,QneiHNYTN;Zm4+)$Cp->8/=c":tWe"9]uB"=,Bo'I3f=qZ;CS!Po`V,Qo)4;Zm4K;Zm4Ve-t+B(RtU4zPUHM3"9\e,"9lS>!NQ9l"9Oej!h9BqP@+Fg_ZH&,#*WF!/B\*ZKIk;SV@Bm6"9Q4:#Ja7@3)]q_=9J\i!h9ArS-/kn?ig-+!gElSdpN99PQHL=]E+l7;Zm4)"9\pb":"X"!l._;"S`,C"9_D'HihAf!MgtD,QWid1^!i\!JCKhJ5ZRR"9H.9_up+S"BYd-Erkn9ZNfc$!W6nD^BFH;Wr_hnX9%s8Rff_mG7UcI!V?EbXEP-7bRa"?!VBh&!V?_`U^a\D"UL%oG`*#i!Png/#I=I'!L*Vt!Q5$2_dH^G_u[5PquNYu;Zm4(!JCQjRp73A2?LC';Zm5."9ONOPQV$#"BYd.Wredo"9\i.S-$>*?ig-+!fR>q$Xa#4!fI,M]E4"!?ul,G!gEbEX'c!eqZ=D7#-2-P"g\8pKEot6]PdoS;Zm4)"9\b>"9`+2"9_IuA-;=""<SE_!T6lZi)9a]MUM\0"Di#XA-'FJ*$bYtE&W[X-%c>2P6>]@?Z^6RA-%PjWredo"9\i.PQJK""BYd."1nWIS5[U=?ig-+!gHX,4(&,j%eKgU!k\Q2E)QlBA5sU3,U<M'9I'aWn5BGma"+It"C*hc!iT$#&nE0?":3ck">"X?A-@9*bVUS>!gFr:hbsX\;Zm4(;Zm5BCBOc*>7>$FK,bDSA3BsW]3>\C;Zm4(!KI5C!m=V<IT$@P+B&CG";q>A!Ms$(!g<`i"9_D;"9FN]!nL9QO&H/aKG(Wo+67hX&nEbU,QoY,,QorG,QoB?"@N9D9EC(t!L+i4Vc*^$KFk0cN!p="PU$AB`!W"8!j$SM%-.c6'EO_RZp"`mbQ3A(!LtYMSl5ap;Zm4(!fR5q"9H1==9J\i9*1%TPQmmj?ilf!!e^WE!k`FSel)\S;Zm4*"9\ac"9]35,Qe!E!TOLYr!M4ibX?XUIgqVI"GB`jZjXN1.gG>@"AB31"<;M/A1W*R!!!."z!ij?afM_nU;Zm4()$D35!eUUY$nNB;'Ig@m">hA,!O,K*Wr^]Q!Q5*A"9H1==9JZKUB/:9"cHal#D3',e-1b<?j3;+!R(W"X'c%1KE8^foDtfl;Zm4(;Zm4=!Q5#C"9H1==9JZK!sA`0!R(T:F'o(@#O;E7oE:ps?iu;f!Q5,9UL4-"MZNGQ#1Hr^!J:Es]EYEEV?rIf"9J,q!f0bXB2\p9E('R+L>)hn!UOb++Ue2NKF$?9]HgnqG7Wa9%+GFP/:Ree`'+;DKEg3;#,EaW">p<5'_E/o>S?CD"9_g0S9"^iJb'!F!L*lkErhd6q[^VeKE8A>"k*SY"9GTCKQ%.e^a'$gX9"glHmss[$d8XI"1/5Z!Pfr`PQV#G"?^`+S8\Xq9="a%"9G<;"<df1!L*VDirP*K!!/$/E9dO`!Pneq"oA=ZMuf/J"05Z-9EVV/!OQbJ%T<K5L/S3X!!!!"+ohTC"9PUQ!m":C=9JZc!UKplli[?i?j=dT!TX@So3_UrqZ6$c!L$ml?u#f(!Rq/!!fV%#i)9a]!sA`.!K7&d"9_g0UiQRL!Q5*AbQMHt"Di,[]E,bMKW>4Z!R,K`+T]4Y]Gg)=!PEXX%bs,"UB/"-_#_1nUB/".PQA,lMugQl?jH9("FL9?":Y3H!VfRr>U0Ft"B%o=]`\Ak!TX@ag]U^^?j!G1!TXKD4(&<bDZg*j"9\dbj8u8Y"BYd-Wr_Pi"9\i.liN+J?j3k;!TX@+"g_SM"2b0#N!>2J?ul,G!TX9fUL42Q"9I!S"9OO#6l8i*1^"[!(V<4WE)QlB9I'a'Rp-;#S5^I4"9_[)$j8go%b(NU,RMC',QoAl;G8?@,Qq'L;Zm4K;Zm4^"9\bV"9]35"9_IuK)sk.$kc6">U0FtA0_9l#ZCj/#)jD[/.86l6u4+O1isuG9MAG+";E*a"E.3A"9^;M!QQO>":M;)"9_[L!!1)<zWf[Da;Zm4)N">gl+7sRl";q=V6X(6E"DSnZ!O;h2!!!!-+92BA"9PUC"3=CD"BYeC!PJVH!Ls8q"9G$6N,o#qlO:E,!Lj+MS-/koU]J4@!NZD)qZL/F"LM`U!P\a?ZigE2">k0#]PqYe^B=Z?"9Gk1S,pDNS/L&^!Ls,j!M"0,!Ls2,P[k!!C]U%,]3km0DZj;L"9\b<"9\^'!MiOje4Bi1<<OQN\hjOP">g5^o)pTi"=.qB":.p/S.8I#1aE254<t%\"B%&r!)j"'=9JZS!Sde\e-#fQ?ig-*!Sdd@P@+FgP6'/8!o%)`DZg*Z"9\c'!R+qM"9H1==9JZS!Sde\"9\b+!W3$&!W)oQquPP[?iu;f!Rq=sb?tDCqZ4nF"f#H+",d3Xe-2UTUL4H1"9HFC"9JF=!QS+A)$ml+1^"8h49P\\!eX\k6mMmT9Q23Z!J@]]"9_\C"9Gr0!N/j!zQjE`m"9\e+"=u6*UBC];,TLb9/2SUT"?[q4lk!(u('h2g"9\n8"9]351c,6J'GMeq*&JoD*'>JL!!H1VzWmDXa;Zm4)HisJs"4TGSKQ%1NNO&`g!K:su"<i-qg3b6b;hKGubBs;;!Ps.);uqW!9RHl*b?tC@DZi0-"9\aa9ENjF"9_g0"9GQ&!KF^=;<n7O;g\\?;Zm4+!Mfe4U]ad&?j?K/!Mfh8F'o3iDZg**"9\bLHj!MLP6=!h%[:o9E"/!6HisJ/"9\iN"9QYC!ROaJHqFMo%T<K5bQ@tN"9G;!!R([KUL7WU])e]2#P2=-DZg**"9\bL"9_4nX9:de"9GP(]`\A+!Mfi!X9;W.?jD;b!LsD4gL('ZRfT;fPWN7Sb\mUb;Zm4(;Zm5:!Ls1N"9H1==9JZ#!sA`0!Ls2794.et=b?b!U^$^(?j""A!L*kB!R,HbQW""i;Zm4(;Zm5!'\!/U!O`Z+"9]@u*!*KH'Ef9V/0lJD]3>WL!pgm.e1:Wj">(l%,U<L,Rp-:PS1GWa,QoY!"9\iZ":P=:!VTFpzV',g="9\e,n-6s4UK/'3;Zm4-K*2LR!OQfZcr1&M;Zm4/"9\j`WsOS\>QhhC;Zm4;@6?q";Zm4S"9\hJ1]b*bTEH,8X&]o:;Zm4(F5$f,'O1a5J5ZRR"9I9[!Sdf[b?tFiK)sa8?c-7WDZg*b"9\dZg]E:1"BYd-Wr_8a!TX@ao3_URMZMTd!Q/:LDZg*b"9\dZ"9`XAg]E-2"BYd-!W)oQKEoD&?s/*`!Sdb:P@.b8"9H^L"9O6p"8Gdt=9JZ[b5pB$CZAe,&rQeGbQbsmKPpto;Zm4)/-H36N'm]^!Lu7]>7<VF,QWVb"@OL<">EaWZuALP;Zm4(Lnb+B$kbZ'!Ug.2!V@p:"9_[L"9IFZ9Q1%0E"\WC+[cH4;Zm4+!sAa%"FL6GX98Z."FP7k4ECP1E!P,#o)o*,!Q8r,+T\qQ!ON69Zjdf2ZifLm"9HXGOAc8b;Zm4)&rQh4";G)n"C>"0"9G>]">p<E3)]q_]`\Ac!SdeYg]U^^?j)AgUB/kCgf%Sa?if!_!R(_B!ebIp5#VReW)Eg%;Zm4(<YTH`"9]?qg]Gi$"BYd-]`\Ac!Rq5Qb?tAJWr_!,#HM6ODZg*b"9\dZ"9Q)3!Obo0fM_nU>7<Up">gt-MZcEn%tnn,E!M:(I?Oe5MZd:("CuIJ!J")ON`-&`;Zm4(;Zm4>j9,PP"9GP(=9JZ[qZ5a\"7on$#3,a>bQQ*sKPpto;Zm4)"9\f*ZN92e&dQ'$,QoY,HNZH).cUX7"?\ec"9\ib"9F<W]E,f!@6?pY;Zm4S(R,#WXBQCG>7<V2"S?Yk#G`UJ9Q23ZE(Prj*kMPSRflu8"CuHP!le.AY>YQ,"9F;["9Gl%X<(:C,Y^B%!KEiW"?\ec!Sdf8g]U^^?j)Ag!SdmS]3k]@"9H_k"9O6p!q0%j=9JZ[!sA`0!Rq1("9H1="H*<1KEfn5?indY!Sdn.&rU-BDZg*b"9\dZqZIC-!PE@Q+T\YIXD$o&!NZ8%!NZc`!NZ=<!MfqS!NZ<d?j=Mr"De7B"9RY&"D1R8"92:&QW""i;Zm4(!!!)Pz!ij0Y=Ao>*g]IZ^"9GS)ZigEC"BYd-"1nTh!OQoUo3_U*o)[VJ!qTe#!W)o!g]d"O?iu;f!ON$rP@+Ul"9G;'"9I:r"<^VG*"GmM`)6f(;Zm44"9\au"9OZ`>Q@\*"9_g0P]Hka!L*]f#jaBh!MsS4"9\aq#_W5mE!Gn:N!'0O]*'8XScOd"Wr\.[!K7&<ZN6!b_#]L3dfGC.!L-gkK3SG9"1)A<S8SO(;Zm4(,QoYp0=q?,"<8t3"9^P,)iK/D*"3H2/3G0\"9a&S/8u971aE2D"B$cj";q=fH!J6$;Zm4//8qS4*!)!2,Wmda"@OL</-3O3QW""ie-Z$RliG'3"9GkN]EA@>"9GP(!W)o)]EX!r?jD;b!ON&`qd9Ym"9G;&"9I:r!,b^<zWlH+[;Zm4)"C)&5N!'8cPXKQn#q:K-_ZVUX!M"*?E#XE4,Qn.D!K7&p!K:]eRfSHV_#]KWqZ2WV!L-gmo3;<T#1Hr^Ui-B0;Zm4(_up.?"9GP(]`\AC"9\i.]E.'q"BYd-!W)o)_ue\$?j3;+!PAKggL('ZdfJM2!o%)b"G6`fX9>k;V@Jgk"9IQa!JjYW/HOW0q[A,\ZlFGu"U=l7UBCt+1iNJP4<t%L"B%&r&i<,="69g-!T+%XgDg`WA2J[$PQ_,YZiZa!#HW+O$If6dN#Xs0$cG40!L*Vt*!q9K"9_UZXB/='!ud+0"9]IX_upQK"9GP(=9JZ;!sA`0!TX:BMdQS_UB/:9]G"ZV?j*e:"9GSc"9IS%/0IjoK*3%p!Q6)_;Zm4C;Zm5I;Zm5@;Zm4>,Qng*>7<VN4=gQG"?Z^T!QJ%@zZl8uF"9\e+!N[\JX9;W.?j!G1!NZ?tb?tOt"9G"s"9I"j";k&?"<^VG"DC^:":e?5!Ou&2'_EEA"9cY#!NQ7.!sA`0!MfbG"9H1==9JZ+qZ3JqZjU7B?j?K/!Rq=c]3k[:gB"A[!S^u_DZg*2"9\bT"B7Q`KEME["AEk;KQ@0Q#GVD&"9Fa+MugZr":G&-!JCKg$N(Y1!JCK/!JD`Q!JCKi!L-P>b>\Lq"H-XlP]$[m;Zm4()$CpK,S6^Rb6/dt">k(/DukO5^a'%F,QsV<!P**#";D<`"=,6<!!!-Zz!iq5&W)Eg%>9mGYA-;qn"CqWU/8PFj>QXe,"9a&S"5$NT=9JZ[!sA`0!Sda0RpZ<hZN8hb#Ff*)!W)qOg]X*S?j>ot"9H_F"9O6p"isUF]P@WQ>9l<56j*PN"@NA5"9\i/"9[jd"6`Ydj'*ck*CL#2":Beb9F/!,!eX]."FC86E)E)-:W!;tUBEu(TM0;[!K%!]4EAV-";D7W"<:)\"=-ql"9_sT"9FT_gc&.7"BYd-]`\Ac!SdeYb?tAJqZ51J!m=sP"bQj2bQEK*KPpto;Zm4)>:`GJ"?ZeH,Wl3V"9IOequBXuS/k!&!X(n$>:`GN"?^.g"9\jS"9OZ`"IN*j<?)7N"?Zau"@P'l"9]\iNPdGK2?DtA;Zm4["=sSoKEMDq"9G>,E,pj>;Zm4C-&Vft">i#$!N&cu!ULDg"9_,*"9IFZ!NQ6["9F/YZigM6!JGLpErioVWrrH^!Q8qF!P\a?"9\kO"iLGV!OQ[D!OMmH!OO0%!OMmD!K7&3!OMll"/>mM!Jmda`,>d#;Zm4(;Zm4?"9\e1"9PH!!ME?ofM_nU%KsZM"B5E?!gcgg4<t%L">p<E=9JZ["9I!Te-#fc?j)Ag!Sddp_dENBlN,cC#4#Y#DZg*b"9\dZg]=QV"BYd-!W)oQg]mX`?q%[.!R(Sf!ebIp85fWoqcbUfHN[RY;Zm4+;Zm5P"9\a\>QVB5j"C^t*Fo9R!X*$:;Zm4+(Bcir"9\bWe,fSJ!PJU:"9I9\!Rq6SZX=#jgB$(4"LDJ:"/>nPbQkI^KPpto;Zm4)"9\h`"9^ne"9a0Pg]E-2"BYd-Wr_8a!e^[WK4"l+dfJN%8qULSLoUR3b\LSeKPpto;Zm4)*!$)TzWl?([;Zm4)"9\am">iYJo)o164>_!pZN9%o&3LX.,Qo)<"9]4q%KcE(!LuabLf4EZ;Zm4)bQJ!/"9GP(=9JZCqZ4nD`!]rR?j5isZN7uP"g_S;"mZ3-Zid@:lu*"-;Zm4(KFk3r*/lBZBN#$:!P\a?35Yc]oDeoVPTm^@PQAT$N!Ft9PQ@!L!fLRi<!D;ie8GB[;Zm4-2j4@U"9G$3"@c;m,Sj;]1d!#d*(2%T_urt#"BYd-liR@ndfJe9"f#H,"mZ3-_uZ'0?ig-*!Q5)(gL(':>62YCZj#c'lu*"-;Zm4(=n;bs"9G$3A.DN@"9_g0!K7*`ErhL.!Ls9dP6=!h!MjZ<E%o`DS-/r<#a?J5!Ls1\#eL,Y[K2mf"9\i.6il1D+4FF&!P\a?,Qp4l;Zm4K!!!&_z!ihIh3)]q_">p<-";q=^]3>[hS0Sdg"<8B^"9]tq(u,U"`*jI@;Zm4.!!!!7*rl9@"9PU["c-([!pBj\1^13V!TRB0qcb=.,Qne_^B=[-$q*2Y"Bk>#!O,K*!V?Kt>7<n^">jl2";Cuc">hq\!R([("9_g0!NQ7NdfIr$#O>b#!m:Vg]ES1?oPXj5;Zm4(N&1S!!TRAfj'*ck";Cm""9_+<bQ6?p"BYd-]`\AS!R(ZI!o%*-!W)o9bQd*8?j6E.!PAKW!VC:5#ZCj/DGpZ@&i:]r"=s_8"<9fT";FNT*%Y&7">hr8"9]Da"9^\_bQ7><"BYd-!V6?abQc6u?j)Ag!PAGs!VC:57T0Em$a^Go*2EUr/0k?\;ZmK@;Zm45">g.n"9\jS"9G)mA8bBL"9H1="BYeCErhd6!MfiLP6?8SX9$m9M[\)9!OQf8!Mg%GUBGZS!N^6L+T\)9S."Wc!Ls,j!M"Xt!Ls2,P[jlsC]U%,>T7't!OQbJ?rI12!)j"']`\AS"9\i.bQ7><"BYd-",d3P!Q7'-dpN4RqZ4V9!h3Qu!W)oAoE(Li?j2Gh!R(V7b?t@7"9H.9"9J.5!T-fY";q=f]3>[X.Dl8h"9^8p"9]35!!/-ZzWjs,M;Zm4)"9H/3!OMu3"9H1=Wr^-A!OMt1X'bu*qZ4V>"hS.H!qQH*X9/!$jDP/%;Zm4(;Zm5:;Zm5*"9\bh!PAD2"9_g0!NQ7>!sA`0!Q5$"UL4-"])gsq"J]?,"eu+2]E?Vj?j=dT!NZLC!T\/%:/_8u%T<K5"BYe+HijKSErgpsN!'0?!L.X+ErhL."d9'OKE7T^E%g5YPQV#_"9]kKS8_l*!K7-^"9\iN!JCKg",&%SP6$=:_#]37K)pW+!L.s8>>tWV"@QI%"9G<:ZrU*.RL[7L,T<HZ*!@,^";E*a!S1VA",mp>"=,Nq*"VB]!!H1NzWkKMS;Zm4)irfI?#jcL41aE2<,R<*M,Qo)L;Zm4k;Zm4g"=sT#$mYrn/-3@e!P;PE>6DMX"9\b;"9\^'"9J!j/2gE0/5.;lg]UM3AfH[H"Df-LF9D_K"9\b+XE+E4!Mfi!oE8uOe,d;fS/R:hbQ37q!Mfi'K*5G#!N^6_!P\a?!Ls1dS7;SqS.*:9!Ls,j!LtY2!Ls2,P]R)hC]U%,K4"`7DZj;L"9\b,!Q70#"9_g0!NQ7F!sA`0!Q5$*ZX<mYb5pr5"g_TI"3U_`bQ@BD?ig-*!Q5'2gL(,i"9Gk1"9Ik-!KL(]Wr^EI!Q5*A_us0F?j!G1!R(YHdpN4R,6>^cZj2e&lu*"-;Zm4(;Zm45!!!":+92BA"9PUR!O,K*J5ZRR!sA`/!Rq/Jqug+)ZX=^QlN,K="e/m'DZg*Z"9\c'!Rtd]"9_g0!W3$&Wr^uY!R(ZI"9H1="OdD,quYnd?iu;f!W2tNZX<s;lN,cF#.%\B"eu+BquaQ=]3oCTWr^]P"2eLNDZg*Z"9\c'1^$'B"9]uE"BY\o_a[Q-e.OSp.f0>W1^$3c%."*?"<8Zi!Ou&2\5NM5)$DJkJ25j^,QYd`%T<K5:f@K"1aE2D/HcR]"9I!T!R([K"9H1=#D3',!R)3b]3kf;_ZA6k"J]?,DZg*Z"9\c'"9G,nX%-(k$kbC+6mMmT9I'`TaAW3E<[<.q"9\tY"9FQ^N(6eLWX[`%":LFp!M<9nMus1c=9N.8!L*]iS-1Ba!N^>CEri'>^B=[U"9G"nFE7JYZ#RYa"9GS)Zu?&X!K.']"9H/S!Pf&D!Ls1d!Vd,2MZa'N!Mj[(+T[f1P\@B+!L*Qb!L-L"!L*W$!K7*7!L*VL?il6s"B5G\"9H/R!VTFp(/k>=zm4//:"9\e,"9Y#i#09^G8d#FX;Zm56"9\u)":'`]CiDGAE$srSLQ_j_TR:\Z!K%!c;Zm5>!RM(MX&]7S;Zm4,"9\h*U]g0c!PJU;"9PY-"9\j0e,n,%?j)Yp!i,jtX'bu*Rf]Yl6d&j[DZg-3"9\eU_[N2:>QMWI;Zm4K!i--Q"9H1=e,ogV"9PY+!iuN,j'Vu4])pIe#NK1o"02L!X9[cn?kW><!h9ME!n;,k^f(@=X9"7f!P:/h!K7&<9F%=s!L+i4>7:P&"9_)U\-(Yf<WRjW"9`8Y"9k`&$]n9i]`\D4!iuM*U]ad&?j!_:!j##3lX0eS"9P)r"9R(k!K^4_b>olY;Zm4+;Zm4O$0)&IKNn]5;Zm4(;J\`C;Zm4+HHQN.$sa/2HmAh_KHp[W^a'$`"9`NA"?\#0,QWiL!L+i4S0S4O;Zm4(<Xnq5"9F0\"=R1Ob8+"Z>QO;("9](uN!?4Z4<t%1^f(@=;Zm4+!ji(qX98R)"BYd.e,ogVqZ=,+OeZ:b)ZnLi!Kj-bOFmV9M8N^%"9P(o"9R(k#09^G>:]f6!K7&kM\Q8O,QpdA!Ls1T6^(^_+T[N)"9FGa"9_+</-E[d!K89,j<Ok%"9F_h":Ts.C]V=6,U<M/fM_nU!sA`1!iuIQe-&kV?ul,G!j#t>P@+F_"9P(u"9R(k"n5FnN)^i;"9FG^!L-h7^gn\n>Y5,#TMksr;Zm4,"De+Q"9^P_">h)D"9`Nd"9IFZ!NQ:/!sA`0!iuIQe-&kV?j4^T!ji,hMdQdBgB+G["05f6DZg-3"9\eU1]rb:!P;PEE#J6M;Zm4K"9\e?X9-lR"BYd."1nWaX9Ruu?jG-^!h9LJ!n;,kY>YQ,;Zm4(KQmR<%Js0,%T<K5";q>A>7;%,$kr`S"9H,="c-([!K8eO"=sroMufFo"FC7P5Z7dgF<gu/HmAhoKHp[g;Zm4("9\hX"9_7o"DhsS"9]e_%BLXM"k-[,PU$B*!LtA8,?t8cU]I&t^a'$`"9FG^"J/Npe,ogV"9PY+!iuN,gL(6_b6$/q#HM59#K$VES.O^ge8GHk;Zm4)"9\i#!j"(SU]ad&!PJU;MZT[W%`;ZW#0R(L!h=%6!n;,k:/_8u&o7l,,QpLD,QoB?"9\aY"9acaZY*2>&cmqi,Qnei"AAid/-2Ol!N[OL!)j"'[Sm;3,QpdD!JD\F,?t8cMueZD<<OQJ:2C&T,Qqod/-:H'"9\ai"J8Tq^/G.;^aoTiMuek<'I3e^EWiHH!K7*K!P;Pe!K7&<N!)LP"9`H?"-6@`"cO+Z'oW0UGm"0G>:aRn/9CoN":"I%!O#E)=9JZC!V?Ktqufu?"C-!KKQ%an^B=Z@"9JE$4ECRWE!P,#]*&1o!gIY9+Td<"!V?Kt5*H*m!M0>a/`Qm(oDepaoIZ7-oDuc/`!2D+oDt0W])fhN+IcaDDZg*J"9\dj"9kr,"9G?(]3>\S>7<Up"9\b;"9^>U"9Gu1XCbB6"BYd.WrfX2"9\i.Zi\_Z?jDks!n7@ZZX<g?lN4-j"S6")DZg-3"9\eU!!06$zWn&!e;Zm4)"9\b(PQJp)"BYd-#(lr@PQe[,?jE/%!JC]9!N$%e"9\b<j91QC!u-t%"9],)"9Yl,4CeNs"9_g0!M"4IE"^=sq[]KE"FP/+"<du6>]Xui&`XAn"8mOo!Rq8U!P\a?:i'riC]fc@"9\b6"@c;m!U*GbWr\^n!L*]fN!*5c!PJU:Wr\.^!UF+q?qUNb!Ls2VlX0bjUB-S[!Ma$)"e5UH!PAH1fM_nUF)1s[#MTAD"9QedHuOLl"<hRa!,O3uCi?q%Rqr,A!L.+"#E(]\/-N"]"FP,E!Us"j?W.(1Wr\^n!L*]fN!*5c!PJU:P6%0V#)cjo!W)nfN!+c@?ig-*!L*e@X'c.TKE6`.]E+l7;Zm4("9F`^"9\j0PQAE!?j;5a!PAWC"QNl'#P.t\KE\\i]PdoR;Zm4(d0(.[gCsbk*!)IM!JSuB";CmI"<^VG">k19lu7Es^B=ZE"9`NA&&]ShN$JY(2$=m);Zm4+;Zm45"9\b>"9]K=!i@&Z"Dg[5!fp7_ze0+el"9\e+e,t5"E"_1>$nMn,*,pg?">hA,!O,K*cr1&M!sA`-"De+'S-/ss"AEk;/9:ifJ>3JL!N^5@EriWN"d9'O"9H/S`,H-kZjs_L"9]kK!UTo`^B=ZBquN;gG6l+o$aUA&S72haS-Y&S%(p3R"0;XL]+*6n_#^&LdfGs>PQ@!LC]U%,$Xa6mV?*c'"9HFA">3UU"?'0]e3%[pHj%n./.K6[":*-S9Q4LBOAc8b"9I9Y!Rq6S"9H1="02IXe,uaZ?ig-*!SddXUL4@["9H^M"9O6p!J")O!Mq=M,Qnea;CieE>7<%cUEgA&"=u\<'Q@io5>q[f1aE2<"B$cj;Zm.!;Zm45"5<rDbZ%P\1]bB#,[i5\E-]%u;Zm4S)$D3\h%Y>A"9nZ'e7_b`!PJU:"9I9\"9\j0"9O5Y!NQ7^K)t$9"-[*t!W)oIe,tnB?ig-*!Rq>.MdQS_qZ51N"litk"cEG8g]mX`?iul!!R(Z;KE7rt;Zm4)"9\bVg]>Go`<N[P!"7!OzWr!n=;Zm4)"9\qMe-"&r"BYd-]`\A["9\i.bQ7VD?ig-*!W3,5MdQXFgB#e-"7on%DZg*Z"9\c'9ED@r23T[E<$VT7!P\a?S4jnr"Ahbm"9_Cj"9J9r!k;/36IQ.?"9GlK"6`Yd+&`:F"B%?%E)bQp"9\b4"9HkJ!J")OkYhTe)GDCX_%\+>'FkfX"9\6r6uQ!,9H4JZ>Rh#);Zm4s!K.(]!PAH/!NZKiOb3c[!!0/%;=agi!Pnf<!Q+r>!L*V<@se<YC^7"K!PE=RW)Eg%"9I!Rg]Ra^"9GP(!W)oQe,kP9?iu#^!Q5)X!W6j=TMksr;Zm4)!W*!j"9_D;"9HPAr"`36B-*ic">g=I">g6!"?\dl"@N@o4:Y&'"9\b<,Qqlc'KdWD"@OL<!N&cuWr^uY!Rq5QbQM#N!PJU:qZ5IT"j:9S!W)oAe,n*,?iop#!Rq2"X'c(R"9HFC"9JF="Ai#"!Us"j=9JZS"9H^LbQIs[?ig-*!Rq.V'4;!eDZg*Z"9\c'"9`sJ:BBl^"?\UG!fp7_``!!C"9O>Z"9Gl%!No?(!P\a?"b["`9F_1K"9\b69NP-q"T)CSE(trf#h3*Y6j!6i"Crb\^/G*G!JCRVHisJN"9_g0P]Hl,!OMt1"9GTFCi]Wi^B>"QZk(Xe%8iSq!M9D"!O`$9;Zm4+!Rq.A"9_g0!W3$&"j6rEe-4l??j6-&!Q5,A!W6j=Vc*^$"9I!Qg]Ra^"9GP(#0R&&e-E<f?icGl"9HFc"9JF=".iEoz\L@LY"9\e-":g5d$^aiqi)9a]!sA`6!gEc)"9H1==9J\qqZ;ub$]ABn"Hro*S-t6_?kSA!!fRS@!lT![n5BGm,Qq'P"=sSD9ECq7A7S[s"C*2T!U*GbKHp\*9k4A-;Zm4SqZI%`%chS(!Pfr`K*24>!M"*ZOAc8b;Zm46"<7f"":`!h6ik(S4<t%tpeq:u;Zm4-'$C<k$k`T",Qn.$"CqP'6ij)/!N[OLi)9a]>9%/Y9@Eq%"ABGEC]V9RE'pZ/HN[l$;Zm4+"9]%@":_#&$M[O&OAc8b>Qpc'"9mO\$d_fT,QnA=,Qr3_,QrKo"9F0<]*(MI"CuInCiEe*E%/*r":WY!S7DYX"BYd.]`\D$!gEfgRpZ9ob6"1V#-2-ZDZg-#"9\eE"9uY?!NQ9t"9P(r!i,s$MdQS_irY_Q&rU-$DZg-#"9\eEGgftt$k`SoPU$AO,Qp41"@N9\"9G;D!Tm;`!K%#!!sA`p!h9>1S-2ps?j5it!lP?0<J+Zu+56jeN(rnO`,>b[;Zm4)!h9JY"9_g0!NQ9tqZ<Pr#J4@E#I=K%!J6MCDZg-#"9\eES-/gj$*[>/hA6;_;Zm4)$()$d"A;cp!PVJ8=9JZC!sA`0oE53]">k0#r,>`$":L_#!V?E-Erl1A/W0`g"9O6qquOP8quQEj!V@92Erl1ACT@Rp"9O6qquOP8quQEj!V@92!V@E(irScP_#a1B_ZBB1!UKiD!V?DW<T=+uZm!n+KPpto;Zm4)"9\tV":9l_"9`KC$j!X:CBjD64/2o]"9_\CK*TIr!QbH[,Qnei,QoYl,Qo)d,Qor/<?sD3,Qp4l,QpL\,Qpdt=+9Hd"9]u.":K`YFDt^4E$rO+":+.<dqf&B$kd)(F<gu/HmAhWL/S3XpB-T["B8V-#-_#/&nH48,Qo(q,Qp5O,QqA""9\aY"9X`aDukjfA>98qP6=Qu"B9=t"L_53#3Z`4"9]u.S-%8?"BYd.#/^M4!h9p3K4#M-"9ONK"9QM[#)H1\/59XX:BUd4"9\k"j9+7;"9J]5<,Vn%&mQ^B,Qp4<;Zm5>*%V9/Muel;,U<Kn,Qn.4;Zm56"9\mqHi_ku!N[OL!PgMp!JCK,M^0PN2@$HP;Zm4K"9\c#"De+RFDsUJ"FC8^!)j"'p/;(s+TqoN"9\maPQCMW!PJU;"9P(r!gEgiF'o6:EK^Ho!fTc[!lT![^f(@="9P(s!gEgi"9H1=!W)q_S3+o%?n(sS!fR5^!lT![OAc8b(BeOV"9\i%"9jibHuN!e!le.Aj'*L6CeN4X"9_C2"De+RFDsX#"FC8^]3>\S(qTnO"9`O["9d=T`"#]KDukk(*+T>FdfJK54;)I'Vc*^$"9OehS-/l+"BYd._ug,F)ZmqZ!KXj#!W)q_!KXj#$d/UAN'bEi`,>b[;Zm4)!K7-T!TRB(!L+.jiriU"!MjZPSl5ap":a,eS-ISD"BYd._ug,F!i,r#_up+A?idS8!i-^G]3kZoirY_g#1Hs"DZg-#"9\eE"9QqK*$/#]"9]SF"9G>E]3>[p;Zm4("9\eO"9[7S#+&6k"kPE>"9]u."9cbD"BSM)";"K7!gZafc;OiK"9P(s!gEgi"9H1=!W)q_S7\O(UL7:-Wref':toA'DZg-#"9\eE":'ud!f0bX:f@K"&k#@h,Qp4<,QoYt;Zm5.!JCKnlUV'E;Zm4-"9\eP"9cG;mK'j$(Be7Q"9\jfS-Jsk"BYd.]`\D$"9\i.PQJc*?jDks!lRO6ZX<mIMZTD;(V='\DZg-#"9\eEMui-@"FC7PG>eVI!K4Pm"9^Q#oEU[\6m)U59I'a_!Ms$(A9P9^"<7g_"AEn_"C-="6ihrd!K89,PU$Ao;Zm4(!gEri"9H1==9J\qqZ;ub!V9\"L@YJ:AV4@kDZg-#"9\eEWroP(2?Eh%;Zm4K#E/f#r-8s?>9#a@"=sV<9E[a/49P\\"9a&S"9G>]a&<*D,QpL?,Qpe_,Qq(o/2RB\"C,23"CsV?"9_[L"9]K=!!%4Az!ij*WOAc8b;Zm4)"B5Ga"9\j0KEQZ)!M"33Erh4&!L*^<#)lf.S8^Xg+9VfJWrrHfS6l;M!K7-^PQV+4"C-!KS8`!0"oJK(!L*W"+T[6!KG0gX!JCFR!JDK"!JCKiP^ERs;uqXQRpZ?iDZiH/"9\aq"9I^b!Sdb[=9JZ3!PAO<X98R)!PJU:o)[VL#0UBT",d38!Sgmeb?tF1dfHfW!m=sS!W)o1X9O;b?ig-*!OMuf]3kfS"9G;#"9I:r"9;@'";Xo=[!u!W"BYd-]`\A;!NZD)CL@C"!L!PkU][Z*gi!;r;Zm4(Zl##u*i):>!Ltt\:Wikt"=uZS"9\jSqZHmt&+fi0/0k?D">p<5%T<K5!LX'9*!Mi81^!VZ2Z$\eB2\p9z\/G>I"<7KC!T4(u"9GqFkYhTe,S-XN#cnFI`&&_BbTm;s^a'$d"=,5n"9]Da"9GH";ufi"9E\H#"9H1=ErgpsN!'0g"Di,[!JDKs!JDQd!JCKiKE6i)KE8miKL`WT!JFVW!JD0Y!JCKiPY;=7;uqXQ>@7T/DZgRB"9\aaS,oQe!PJU:"9G;$!Ls9pUL42)gB")R"f#H+?qUNr!L*c"!R,Hb*`E1E,U<L,">p<-&5r]7?W.(1"3_gVU^OgI"BYd-bQ@tN"9G"nbQIs[?ifj"!Ls@Po3_]ZqZ4nB!OH/7#0R%CPQctQb\mUb;Zm4(;Zm4u!!!"3)uos="9PUr"2Ih<"BYe3!NT`6!K7-aPQ@S$pE/u-"APot!Q/F%N!'IR_ZV+`!!/$11@kO*!PneqA8;4)!K7&D?u+e-"AF<o"9G$2!U*GbQNDdb"9\i."9X0Q"P?WUg]IZ^"9Gk1!Sdf[K4"o,b5nsT"f#H-",d38Zj!44?iul!!Mfdd!ShSr&5r]7QNm%,"9\i."9F<W"NXLE3)]q_QO!CM/-H(V"I'$41fje>"<f#nQNs9:"9\i.oE2<r#9THS!PAP'ZigE1"BYd-!S[Xf!OQoUZu]V"?j"jY!Mfq3!ShSr(fLP?YYtZ-"9Fkk"9]uBHBW5FPS+"U/Na.@;Zm4+>7<>blT?Q<"9Fhk!P\a?#GXC<1^!iG4AZ=%!Oag=;Zm4+;Zm4W"9\ei"9G`*!JXMUhA6;7;Zm4("9\e9"9^,O"9a0PqZ4]8,QK)Y/8ug:!K%"M!sA`H!OMm_X9;W.!PJU:qZ3c$"oD[.",d38Zj$>7?j3##!MfaK!ShSr!)j"'8d#1W;Zm4["9\b'";CuS"<8C,]/0XJ"9Fhik#2Bc"9Gk1"9\j0ZiSqa?j!G1!SgoVdpN@&irQLg"bU2uDZg*:"9\b\,V1?B#LidX[Nkq2"9\i.1]d&D!LF&g;Zm4+";CouqZI$>%BOM_*,m,*!RV<$/-1QZ.>(h5k>MKd;Zm4)"9\bG!ON>8ZijJ6?j+pZ!OMmF4(&-5DZg*:"9\b\!<\'T!!!!RjXL61"9\e,KE@N>!P8ICDo2sq"ABGMDukoUF9DVt%"&1$"9H,=1iRo=OAc8b;Zm4-"9\nTq[9W,`!)M4"9F/V!m":C#1,/q"9FH>$cl6L=9J]$qZ<Pr&+a00#0R(DPR#B>b\mUc;Zm4);Zm4u"@NWRS,nj"]3>[E!M!s-!Ls1\>7:P."9_>d":(l(UgR+("BYd."1&')U]ekKb@#Yu"9OfL"9Qec!r,[s7T0EmE"C+pN!'0ON!(:)A0_9YaAW3E;Zm4*&%!m2!h9Bk"9H1=Wrf@*!i,r"S-2ps?j!_:!h=bhlX0bJ,6FqNU^$-m?neV_!gEeV!mGQcOAc8b!iuM/U]^_!"BYd.#O;GmUbfnr?jH!!!gE_d!mGQcVGdU#;Zm4(PQV6T%@f!NQr=+j;Zm4)"9\t.dfZOI&cmY`,QrK'">g.D"9G#<K0W?<2?MMR;Zm5.;Zm5:">gA!$iu#,N$JZ+,Qne^"=+#4"9G#<!fp7_Ua-(2,QpdA"EX[G49;f7!JFGm,Qn.$"9FH<"9a)t"9J9r!T6lZPU$B"A-%o!!J&X'>7:P&!L-3G!Ls1\N!'0G"9^:W!M33m+8cS,"4R@kPU$B"$iuk!C^-A5!Ls1\!Mfad8t0#n!Mfad!Ls1\Y>YQ,(Beg]"9\e("9F<W!S10PMuegRA.0(OS0S?H,QpL9N!'0W"=-\B#*;adKHp[O$k8-r"B::`KE8gj"9F/V$FCKm]3>WT>7;bX"9\b;Nrmp3gK$-5;Zm4);Zm4/;Zm4F"9\e)S-G'R!PJU;"9PA%X98Z."9GP)!W)r"S,pf@?if!`!i,k?RpZH,"9Oeh"9Qec"1M23!UiU4"9FH>"L(f-r_iq&!sA`-X98UK"9GP)=9J]$qZ<i%!lJCH"j6tkUh]4'b@"NU"9OfZ"9Qec"BJG(FDsg(E&3sd6c0%ShZ8CL!K%!];Zm5F"9PB;"9\j0bQ>uj?j)Yp!i0G'UL4-"Wrf)/Hh1WkDZg-+"9\eMS-.,:S--\1"9G"n">'Y=[o3D4p3GBp"C*he!S:6QKE6h&6js\/!L+i4S0S5:,Qr2i">g.THi^;o!OO*TKN0!S"9F/V!K:8/">hA,!R=UH!)j"'Wr^]Q!R(ZI"9_g0XE+F?!e^[WX9<?\quOP=r%mpFquOV7!e^[W"9GlNCi]Z:!P\a?!W3"Pr*oe]r,B7K!W2ou!W4;)!W2u7PQB8ibQ7VB?j<q<!PEIM!fV%#c;OiK"9PA$!i,s$K4"`W_ZHV>!RkE\DZg-+"9\eM"@Qj#PQ?^gRfs3$!L+Q.!L*VT/HLe5N#8;m"ABF/!esVVWrf@*!i,r"X9;W.?ig-+!i14e?icGF!gEnq!mGQcQW""i;Zm4)"B5I%>Qb0I"T/:s]3>\S!P8I8"9`O["DgV-"9aJr">EaW"g1c,"=jTX&o8D[2q%n'C]o-)"9\iN"9dU\"M[k<!J-F;]**4pB7+Z8C]TCr]`\D,"9\i.U]SaB"BYd."Hro2U][Z*?ig-+!h9@nX'bu*,6FYCPQL/Yb\mUc;Zm4)!!!!/+TMKB"9PUK!g$=`Wr_8a!SdeYe-&kV!PJU:qZ5a\"1)A9!S[Y1e-!$b?ig-*!Sd^^j'W+U"9H^L"9O6p1`0-oEs*?`1c>GlTMksr/CO_&"=,gC"9]Da`#JbU"2#l]V*kE]">g5^";FNT"9_[L"9Q)3!e^XY=9JZ["9I!Te-#fc?ig-*!SdgQdpN@Fo)aRI"4LWY!W)oIg][4V?j5is!SdhLMdQUU"9H^M"9O6p!ROaJB2\p9aAW3EN"_EV);G?4-W:-N!NUSN=9N^K!Mfi$$'[PnUi6L$(uk`0"9GlK"<dfAEri?F]*Isb!OQfK!NcJ-!Mg+aUgjG,!NZD)]**4s!OQegDumQR_up+R"9G>"!Pfr`!MfatU`'98U`uQ7!Mf\r!MiZC!Mfb4P^EMTF9/0<"/B7.`,>ch;Zm4(;Zm5("9\b?4=gt@"=s[R"<8C,lNB<q1dl:i'MKbT/6!kt"B#W?z\K1_N"9\e+"9OZ`C]IB:"9_g0!L*Zh!Lsb.=Si-%Eri'>KX1e<!N^5@^J"d[S,oDd@f`A+ACCRLS,`S[S4\tGS,pG,!L*rm!Ls1T?j";_"C)&0"9GTB]LYs(!PJU:"9HFD"9\j0_u]3,?j)Ag!PAW;MdQ\:])h7"!fLFg?m>]j!OMsX!UO_-%T<K5]3>[`>7;2H$mYkc*!*ZA'KdWD%cel<B`nId;EQ3u)$Dc!>7<Us4>[,G"9^8a!PCs%"9H1==9JZC!R(ZLbQIsI?ig-*!PAPnMdQS_K)rmnZm/r^lu*"-;Zm4(;Zm4';Zm5AoEt5>ZiRlW!!!!?*WQ0?"9PU9!O,K*";q=n1aE2T!WEKi"9\pu"9G/o!PhV:KED>[=9Mk0!K7-a$g^Q.P].SZ/Hc1WPQV#G"E\\cS8^LS!P8I8"9G<;P]-Z8^a'$aMuf.D'FW+cP,eVB.fkS0B!VMs!Pneq"OdC1!L*V<,?t8.9Ek<$!N^2B%T<K53)]q_"oK"G,Qiu\49:s7">)G5Dunu%,QoY<;Zm4[;Zm5B!R([)"9\b+!UKmk]`\AK!Q5*A]ED=>?ig-*o)\2^"litk!W)oa_u[2P?j5is!R(b+ZX<g?RfVjX"1)A;#D3&qZie3Rlu*"-;Zm4(>7<VH4;7k/"?Z^T*!@iM1c-H\!!G.^zWq.#,;Zm4)itM^%"9Fhi!JcjY"9\al,]EmEpeq:u;Zm4*"9FI#"9\j0ZiRN9!J9>4Mugh(?jDSj"FLF>"9GlJ"5m)\fM_nU9G%+&";%pJ*!*eW!J1F_";D:"itMWC"9Fhicr1&M;Zm4*"9FH0!K7.`RpZBJMZJb>"f#H,Zu6(p;Zm4("9FH0!K7.`#P2=r?m>]2"FLI?"9GlJ":e?5,]Ejd^B=hLo->:V"9I$W"FC7cQN?+\P8j]+!LEhB#5e_]"=.qZ'R!CX"9HLF"BP^?"BYdhA-2r;XE/1\F*%Nc^B=[UJFdRXCe8FD_/(RLP6lmCC]J9u_/(Hf"P[_nC]Tc2P@//gDZhTr;Zm5FJclbf";E*^itMWC"9Fhi!JcjY"9\al,]F!@!P\a?@%/D]'EeH''Eiac!LEiILQ`\\"9^@Y,]Ee=$g[oL,THj"!LF#^HNY#c;Zm4+"9\as$_.74QNE?r";Ct>"9\jS"9Oog*,ngZQN;l*df]dS&#=.I!P\a?;Zm4C;Zm58!L*]eKEM=V!PJU:"9FGa!JCSXZX<h2qZ2oc#.%\<#Eo1IN!A<M?jE/%DZkH7"9\b4"9`pI"9]iG'EeH)!LEiILQ`\\"9Fhi/lMlUZi^F6"9F/VN!'0p"BYd-!W)nVKEJho?ig-*!K79,qd9QUqZ2?S!o%)`$bHGHN!5,I?jG]m"FLI7"9GlJ"Fj>Q"#a'\!!Nf5z!ij]h\5NM5"9GS)"9\b=!NQ76"9Gk4!NZE+CL@2?!W)o1!OQWMMdQR<"9G;&"9I:r"/&Qq"9J]_P?T:p"=sS)"9\jS"9ZG<KQ(i#;Zm4(;Zm45"9\bHZiSqa"BYd-Wr]j9!SdeY"oD[H!W)o1Zj$>7K4#>n"9G;$"9I:r":.p/">EaW,QLaG"9]SF*,l@f>6O:D1^!j>ZigLPXA2Cq!PJU:"9Gk4"9\j0X9%)Y?ig-*!Sde+dpN99ZN7E8"4LW[#)`Mh!MgB:!ShSrIT$@PL/S3X=9MS(X'>c1KEMDY`&r)A)?l<6irfGE!L.O>+T[6!KE6`/7tXG8[K2&)"9\i.N!+#s"CuQSCi]WA#Lijg!K7&o!K7&4_Z>F#!!.`o.Z4=\!Pnei#-.cXKE7<B?kZK?"@NIk"9G$2!N/j!)71%K&**c"KLuA[;Zm4(!JCS@gB;V>!K:t3DumQR]*&/!!M"*0!Pfr`"9\aY*!)[1/1`%L"9^Rb!DcVs!!!!=YSmKA"9\e+liMuA1]rs^"@NFk"?Zfh"9\b="@R<Q"?^aQKQ%1N<6GCF":4@5"9]lq1ii\NCT@Vl!K7&P!P\a?KR<fR"FM*gF90\jF9-s)Gb]?\F904"PWT&c]0p`A!LmI!N,JhU;Zm4("<7Gm'H@5n*&Wpaga"-J">p;m]`\A+!Mfi!"9_g0!R(WK!W)nfbQ[$7?iu;f!R(`-K4"`OZN6j+"H-Xi"02HuPQSO*b\mUb;Zm4(;Zm4=;Zm4';Zm59!!!%\z!iu/ITMksr'FO%3"9ki,#EVjeE#[7/)k-tH%_-V"A-%PjQr=+j;Zm419D]+$$k`TjF<guoHmAh7n5BGm*!(]q6jE6e!K89,>7:Os"9^TG9FKKO1isuG"FMHt;usck'I3f\!J'J=";FgS<#f-g"9\j*"9n9n!NQ7F"9HFDoE5;!!L.X+Erl1A+8Z0l"9u5PN,WXG!W3'%"9\b<KQ$t(U^t*>%@eRLoDsKS!V??m!V?uI!V?E/!R(bk!V?DWA[;EU["$P4N,Jh";Zm4)L\hA(&cmXd,Qq?\"<7H,;urL7!MgtDYYtZ-V,RR*$sWo9"9H,=A8l5B*`E1EA0_:/Ca9-',Y_5@E&4Nt;Zm4;'Fk<A":+6n$HQ-K>TX4:;Zm4;#c%[7>QMkJE!,,';Zm4;"9](IYQgb!P?&A%;Zm4.!sA`K!h9>9"9H1==9J]$])p1Z!h3R"#(luIU]R#n?ut'(!gFJ$!mGQcJ5ZRR,Qneg^bc1A"B8>$"9]Da":"'g!mC`L=9J]$qZ<Pr)9ZCl#J1&]U`%?`?j=LM!gH:J!mGQcAlAg8HmAh/$+(,2"B8>JlN@nI<,_kg>U0Fd"B&2=YUfnS":L_#!p3DaKHp\"^aoTh"Cu$D0:Q2l":PoB!rl1%"D\,CE+RK$,Qnf\;H+W@;Zm4+"9\e0;ut!;*.0"7ga!5[<?*Or,QqXg,Qqpg;Zm5&;Zm4m"9\e!"9`sJZN?at$kcM_A0_:7Ca9-WF<gu/O&H/aaCsT8"FN*4"@lAn"n5Fn=9J]$!iuM-X98R)?ig-+!i/Za_dEP@"9Oei"9Qec!kqS9bQ@tN"9PA#X98Z."9GP)]`\D,!mCcJZX<g7UB7M%#I@eA!W)qgU^+56?ibl]!gH-c!mGQcmSa5k;Zm4*"9\hjF9B6U"8!iA>U0H",Qn.$"9FHtCPu.;4:DjE!JD^$N$JO2;Zm4("B5Hk9S7/"<"'C]!JD^$(fLP?!J'J=";FgS<#f-g"De3=A-%W7!L+i4S0S5B<@fs-;Zm5F"0M[&"H-:p^Jb7<W!'^5";G)D">EaW!PhV:Vc*^$LL/.+"FN*0!PVJ8>WrCV;Zm4;3hliH'FYUR*+U;t"Df=d!JXMU=9J]$,6FYDUi)Z0?knS$!gE`?!mGQcJ5ZRR'Eb!0":(Ds!M<9n>]0aE&nF,j,Qq?\;Zm5F"AAms#Fbi6'O1[2k>MKd;Zm4+!i,nMU]ad&?j=LM!i.p<dpN<B"9Ofp"9Qec"eS]rbQ@tN"9PA#!mCdLMdT8K!i,jZMdQpf"9Oej"9Qec!ln4B=9J]$!iuM-X98R)?ig-+!i-(MdpNCWdfQ<M8]tLkDZg-+"9\eM*!WQE%?,'B,Qn.$"9FH\"9_sTgB$eBr";s\,Qo(g,QoB',QpeW;Zm5F!i,t5S-2ps!PJU;!sA`0X98UK"9GP)!o!dPbQb+U?j2Gi!iuS&MdQUEqZ<8k"cHah!W)qoU]lZa?l#dE!gEl+!mGQcVGdU#%L&m;"9]EDKEO23">!7Jr_j*XVGm[%";Ct><#f-g"De3=;ur4/!LtD<Ua-(R,Qo(f6j*Ol"EX[["3sgJk8+83;Zm4+!!!3%z!ij-[YYtZ-KE\^b'pN5:#ZCj/!O;h2=9M;+X&K3)HisQQ"9F0s6urB^E*ne3RfihX!L.O-Erhd6MLu%R!Mj$&3<?_pdf]]Q!OQeL!Pfr`li[?Zj8m%'^B=ZK%`E_q<-JSC!TX]rHpi?kZidsR"UXf+,+A_BHi_'2!L-Q!?o(K(DZi0q"9\b4!R+qM"9_g0!V?HsWr^]Q!V?KqP@+KNdfIr'#5_d2#5\GFbQdrP?j!_9!V?T>_dES)Wr^EK]K9L'!N'*&"9\bt"9]K="9]!/"9]N>_u]K4!PJU:"9H^L!Q5+CZX<pblN-V\"LDJ=!W)oAbQP7[?inLPj8lnLoDtft;Zm4()$CoZ>8/=c/-H"6"=sZr`&%Su!eX\ddf]s3"9Pq2"<LJE!S10P!!!u>,6.]D"9PW`!glmhfM_nU;Zm4*"S2i]"AE&9"OL'MGZ+_J";q>!6uN2j]3>\#>7;bXqZHr3"AEb:!Us"j[PS3@"9\i.O9UM>o2\Nf;Zm4+!UL!Zli^Dn_dH[Lb5pr7#I@eC#-7j\!gE__J5ZRR"9F_f"9\j0"9H.;UiQRTZN88NC[2:3I=HkP_upCjg]Sc$G7Cnb(kW?X`*rqp`!k]-$-[#_"RH;fgB4ed_#_IoirR(!PQAE%PQA]'?jF"=!JCWO!Ru#jJ5ZRR;Zm4*,QqX9,Qqp?J-`2D"?\RG"JAZr3)]q_(/k>=,U<L4r=4K[;usT3"=.80*bJ=R".N=bLf4EZ!sA`/!UKlPj9/Qf!PJU:MZT+G".N[#".K>XPQRC_?ifj#!TX:!_dENBUB0]^!io]4#D3'Dg]l58!N$h;"9\dj)pBp5j9#UF#ce(E1^&bV,[;St6t@PG/8QR7li^3c"BYd-PQM$kZN??m"N+UJL#W4#",gOf"OmJ-!gE__TMksr;Zm4*!UKo]"9_g0!NQ7nqZ6<l#Ld&]"j6r5gdSh_P]$[*;Zm4)[PVT("9\i.dfR!W9O&VD?W.(1L/S3XNf+#@*)(;P1aF=L,ZH#l>QOR%.g-$G,Qq(G"9\tr;sP2t$iuhs#5ePpPR<q)Iggu@"b\F;S-GcQ.h'&m";D9W"9`Nd"9]iGZNL8,%?tf5_cnZK;Zm4P#Lk"7">k3G/2V`""B8?#"C*2t"9^h4"9HhI!iJs"%T<K5c;OiK;Zm4)!UKm^"9_g0!NQ7n!sA`0!V?GX"4LX&"j6t3liY^E?j;5aoE!`?PQ@Wb;Zm4)V,RS@">g5^"=.4t<$Z!""9\j*liE/G"BYd-#0R&6lkZX0?j>Wl!SdpL!gIU+r_iq&!!!!#"onW'"9PTg,Tp"g!jc)>'O`7,!O;h2j;s6g%bt>*!)j"'";q=^Rp-:H=HaFk"9]u5!!!L-z!itf6YYtZ-L]N\B"<:YN#+/<l*$bYL"P@%U"9^86"9a6R"/o-$<ZDJ!"9\ah6k$"mH_XdZ!U0_D,Qo(i2$>`m;Zm4+"9]%X1^*SP1^&..j')c\*BXH*!X(Ug>80I.">kU\"9\jS"9uA7!P]*9*4#[Y]DquF]OCC4]E,hL!L,YH!PAGt"e,OOHj542!Q8mZkYhTeHNZ/,<SIWZ"9]]`"::Go",KkYE"M=<>,qcg"@,@oe2.2`!PJU:!sA`0!Sda0KEPB[?j,cs!Rq/!dpN?SK)sa.%>/$oDZg*b"9\dZ"9_h*":DA3#e3e9rt!Tn/-_%61c/2P"=tf$"<LJE"6`YdE-K2&"9\bD"9Gr0#G=uui)9a]>BE78$1nGn"9]A@1iP%Af2DeT;Zm4(!sAaV!Sda0KEPB[?j<Y5!SgHA!S_"/DZg*b"9\dZ2nNHr%D3<QA0_:OCa9,tn5BGm;Zm4+)$D3tV(;`P"9\i.1]adY!TRB0"<BT-"9J]gQr=+jQijr,"<:YK$%PqW!U!,A"9^86g^/L0"BYd-KED>[b6!=u9q,MoI*2QGbQWo4KPpto;Zm4)!Sdh1"9_g0!NQ7^qZ5a\"g_S;E74jCbU1eHKPpto;Zm4)"9\tf,W#X>!TO4Y"<BT-"9J]gW)Eg%*!Q*="Dd$u!mjjKL/S3X;Zm4)'LW%b1c)1:"9a&S"NXLEKED>["9I9Z!e^\Yj'W#Ub5pB%46']QDZg*b"9\dZMZcdR!Q8q5BN#$:G#JMHWr_8a"9\i.e,k:*!PJU:"9I9\!e^\Y;p/Pf!W)oIjAX60?ig-*!SgVsK4#t*"9H^P"9O6p"?9<_*,m_*TMksr"9Gq5"9HG5".iEo#-7p>",I!;<ZD0r"9\hE"=+IU/-Jot1c,6K"<8Zi"@#ff!WQ($j'*cc)*A$&!X(Ug>80I.">gM`"9\jS,W'C;"9IOe49QZe6j*Po"7'/*mSa5k,Qo@n^aoV1"B8>$5P$EO"=uG2!p3Da&i:iN,Qnei,Qo)T;Zm4s"?Zdp'LW'*1]b3m"9a&S!K^4_]2fn0;Zm4*df]dI1`UHV!TO8-"<BT-"9J]gO&H/a;Zm4+*i&t#]O(uh!sA`6j9,O;"9GP(=9JZ[qZ5a\#30(l?s<Ze!e^d<j'Vu$lN,cF"LDKFDZg*b"9\dZirQYg**bC;Vc*^$"9I9Yj9,Tf"9GP("OdD4g]Olj?o$13"9H_f"9O6p"Ai#"!e^XY=9JZ["9I!TKEM=h?j4^T!Rr=jqd9T&MZMTW'oQH7DZg*b"9\dZ"iF_H**`N*5#VRej'*cc*BXH*!X(Ug>80I."9\t)7'h>@,Rb;B*(2%T"AC'D!qoOqVc*^$.Dl8h%[7rP!TRZ8"<BT-[o3D4"9I9["9\j0g]E-2b?uOqb6!=t!lJCLFP?iObQH=%KPpto;Zm4)"9FHPPQV+k"9GP(ErioV+e&Lk!J^]o#)@W%!O`$I;Zm4+"9\gm"9lhE!iAm!Y#>H+(BcPs"9\jn!=+oh!!!!=boQib"9\e+"9]!/"9`sJ!Q4t:]ED=>!PJU:!sA`0!Q5$*o3_Urb5oN_"m]Ou",d3H]EGQK?ig-*!UKrqZX<g7ZN7uJ"g_S=#5\G>!OPL-!UO_-#ZCj/%u_(D"9I"">Rj[8"9_g0FE7JAE,(R>df]]9%`E;iV#d@p,Qq?Q#Lie<ErhL.:U:1G"9G$3Ui6@H!P8I8"9GTCPQAQFPQ?^D!K7ot!K9dS!K7&N!K:?co)XdM_#]K3b5mP&!L-gjdp)p4"05f1XD\58;Zm4("9\b(_u]3,"BYd-Wr^EI!PAO9"9H1=#D3&iliu3PgL+dtqZ4nF#2<Md?ul@e!OMs`!UO_-!)j"',[i5\lm)]Jg]snf"9Is#E(c)l5a)=51^$3c"9\iN%A[B1!OQm*>7<%s"<8ks"9^P,"=-K9$nMN!*#le"">hA,4E(J9E!4Vm+Z'<i@4X5<;Zm4K;Zm59!!!&oz!ij-Zn5BGm=9N.8!sA`0PQV#G"B9FCS8^Qj+km,#":(01Zu?5=KEAdoS,pD1!Ls8n"9GlNCi]WQ!P\a?!L*VT]MSa31^NFPj8kK6^'sW@S-H>$Oo_'^oECH[UBA.3`"&jL"TnT+:s0!;PQ1`KPXkTOPQAT$N!?lpPQ@!L?jgKG"B5G\"9GTB/0Ijo!RM,-qZHr\'GPL3"=tf$";k&?O9)lpliXm$"oM(9%T<K5">p<5liR@n!R(ZI]EA89!PJU:"9HFD!Q5+CUL4>mlN+p-!S^uc!W)o9liY.5?j,cr!R(Y`_dENBqZ4>3"H-Xg!ODgFbQNi3?j+pZ!Q5,!,@C_V%\s-4!UKiaO&H/a)$D2c>9#0s&>K9d"=+U:6u[1Y!)j"'!J[WX,Qpe[j>6nQ!J1+Q!Q7*Je-->p;Zm4+!!!&6z!ihLi&5r]7&Y'Dk(RtMr">p<-!)j"'";q=^E$*O3>7;bsM\JOr*$dZJ"=,5q!#AK9zWp1l1;Zm4)U]^h)"9GP(=9JYp!R(ZL"9G<>/9:jAFuYroMZa(9jDY-[!Rq5Qdf]ds!ShVt+UIE;bTE#O!Rq)M!R)d@!R(S\!MfnB!R(S/!Q+r.N!A$EjDP/%;Zm4("9\dfquOl;"BYd-?s<[0!W3+jqd9K#"9Ijn"9PB;!JjYW=9J[&!sA`0!W3"pUjHJo?id;0!W3)lP@+F/"9Iii"9PB;"5m)\!QkNr,QpMG;H,2`<?++(":OQq"C*K'"9_CD"9HSB!r,[s8-+Gr"9\n7,QpqB"B8>Z"9_+<oE(+Q!PJU:"9JE'!V?Ls"hS/H?t068!UKop!i0`;kYhTe;Zm4(;Zm45;Zm4/<iZ80,Rb;b6t@PG".UV>\5NM5"9JE%"9\j0U]R=o?j""B!W3"W@pfP"DZg+-"9\e%"9_h*quPDJ"BYd-U]U`&!e^[Xqud&$j'WN$MZT[X"f#H-?kWTpb5qNF#E)skDZg+-"9\e%"9H89qc?]!!PoHN,QnfD"AB)c"9_sT"9Iph!Oku1&l_&i"=s`S">jX7"=.e/"<;M/"AF1g"9F0$!esVV=9J[&P6(Ra"LDJ@#Km/Glj(^AUi-A:;Zm4)"AAm"oL&g"!P;PHE%/[-;Zm4S)6<n:!Oi3E"9\e=!!/*YzX/IHI;Zm4)"9]$ePQCPX!PJU;"9P(r!gEgi$_q*&&rQg]N!JZV`,>b[;Zm4)"9]$e"9j<S!lP0DWrf("!h9Ao_us0F?j""B!i.Wi_dENBP6.71LoXo1"9OM_"9QM[#H1Q(KHp[G;Hu<b;Zm4+C]nPi"EXdb"FNT_Di5S\"B78h!f0bX!)j"'>U0G?#/gb2X:>)OIgt07"jAN.g^N7-.g!Wn"<7U3"9`NdS-?],"BYd.]`\D$U]^f$"9GP)!W)qoS-Q*&?j5Ql!gEqjX'c'gb6"1="05f4DZg-#"9\eE"9PN#"@c;mS,cIj"BYd._ug,F])onP"m]Ou!S[[GS-A4d?jH!!!fR8W_uZ`W;Zm4)!h9:g"9_g0!lP0D!ODjGS-G`rUL5;J])nK,K&^6-"9OM_"9QM[".3!ikYhTe!sA`1!OMm_"9_g04ECPajp0WD"9t(k!Mjhtj9,MU"9]kKFE7KL%I4P3PQCE(>QnpQDumQRKEM>R"9G>#!Pfr`!TX:Jj;J'cj:J?mj8m'tjD^Rh!TX4]!TXoP!TX9t!Sg&c!TX9GLoUQ`"bU1`DZg*:"9\dZg]>c#,R<ZG#)!>b,^0Wt%]g/1e1>-[%u`[W"M>&2*"9J1"Df=d"9G?@HmAhWN`-&`;Zm4("9\hBS-$V2"BYd.",d6!S-7SS?j<Y5!lP5rj'VtIUB6qe#0UBV",$`7!lP,:[o3D4!sA`.!h9>1S-2ps?j;Mj!lR[Rb?tFadfQ%2-bEaj!W3"X!lP,:el)\S;Zm4)>]\q#">gN""<;5'"9`fl"@OnA<!3=)*!?;="LCW)cVjrL>WS>T/.UG='Po#t1isuG*.0"7!JD^$N$JNo,Qp41"9\ai"9HkJDul&q,Qp5O,QoB?>W`%?Rfijle9#Y;G67[E$EOT!I")7b4pU.2!K7K[lmiLg,Qo@n>W`%?"9\j*MuonUN#B8G//,Ak7!q*"!JD^$N$JNO;Zm4(<@g64,Qq@Wi<3[j"DfUiKQJ1Z,QWH$%KV<j"9_[^"9HeH"F!cI".iEo`WQ=41^!p^"C,23"Cs&/"9_[L"9RFY!M33m>U0G?A0_:/,QnV<;Zm5>!!!(Uz!ii^JTMksr;Zm4)8':q+*#)Wf"@HB=9Fau("9_g0"EX_K"?^aQKQ%*Y;M,)Q"9FI#"A&jJ8UPL#PS8[s#J<M/$H*+4gB"C"@KD-5Hk4GKoE`rZg]\)oHmmGFRsY7Q!L.[,"hRHU49s&;!N$=m"9\aaX9;p0"9GP(bQ@tN"9G;!!NZE+j'W(LMZM$*"lito!W)o!bQGIb?t@F]!NZNiP@+TQMZKUY#ErO""1nT0PQRsoV?blW"9H^I*"Z$O/-4K.2%%PY;Zm4+)$D3;<YQ;P"9\dq",$qY!Lt!s"<7o1/-ILL"9\jB!!!L-z!ihLf+B&CG'Vlbf'F*&T!LI6</IVabZ31:5UC7P3"9Fj9QYahZ$j6\6UC78W"9Fj9(/k>=!!!T3*WQ0?"9PUB`%Y*m"BYd-liR@nK)t<>#ErNt"g\6JZj!dDlu*"-;Zm4("9\aU"9G`*!f0bX(fLP?=Ao>*!P/CR!B_>i!sA`0!Q5$*li^Dn?iu;f!Q53&j'W,XRfVj["7on*"H*<!!OQ'=!UO_-7T0Em);GV<";6Z/1_*Fe49QN)!g?h&6mMml]3>\;HNZG3>7<Us"9`hY"9^tg]E.@$!PJU:"9HFD!PAP;UL45RUB0]_!i'-2?s<ZM!OMuf!UO_-<`9,(Iln1iB]B48"=u*C"9^h4"Ct8+"9\j0"9FG`Huf=QErhd6#MTAD#4)AuE*n5#S-/kob6/sh!Ls1P"9G$>Dul-^PQV#_WrsRH!L*V?_Z>u%_#]c9_Z>u&PQ?^IA-%nqb?tM6DZj#D"9\b,!!$>(z!ir7=Lf4EZ;Zm40"9\n4X9jte"BYd-]`\A3!NZD)lX0q?Wr]!s!UF+q"hOf:S-?f<e8GHj;Zm4("9\b@ZN@p@2@.)%;Zm4C;Zm45ZigTK"9GP(=9JZ+MZL0f"-[*q?kWRB!Ls5/!Ru#j-rU6O!Mr0e!j`"4RflE(#,H2dE!!WS":'`fHV=Ht*&[nd<`9,(kYhTe%Ko0&,X_s79ELD^<nggeQr=+j"6`qj"9]]&6j2^P"8c:Jb?GBKS4jV\$rfn$"?t"5oNtN"E"1;+ZigF-"9GP(=9JZ+qZ4&,!h3Qu#5\G&ZiZ_)?j5Qk!N\nGo3_an"9G#f"9I"j!jGT+!q6>V"9]]&"9]K=P67IV&e;!O^B=ZR"cu+Q"9Gr!VGdU#Ce;MF">gN"gdHN8$_/IEN$JO:,QoY!1^!iDChs-f"@OL<"P?WUJ5ZRR^aoTj"@PWY"9]\iquqmT!Luge6j*gl,X_be9ELD^2Z$\e!Lugt/OT_8;Zm4+"EX[bMX+4e4>m`O(fLP?W)Eg%cjo(<"?\RC"2Ih<fM_nU!JU+J'O28=,ZH#l**a`l"Crb\!Oku1LDL(e;Zm4)"9\bO!N\diX9;W.j'X)4o)Yp($d2pQDZg*2"9\bT"9Rdc!VfRrG#JMHe,ogV"9GS)!Rq6SX'c(rqZ3c&#-2,4!o!aWS9^<+e8GHj;Zm4(]*&1i"<;@^!U!Aa%CC5@"=+Bg"@R&O"B9Ig"AF1g"9F0$!k;/3+B&CG"D\,CDuoh=?Gcn>"9_\C"9`(1"9\^'ZihFK"9GP(e,ogV"9GS)!OMu3gL('Z!Rq.5P1s@`RfTSk#(p:eDZg*2"9\bTX95A!"BYd-?m>]R!NZBUqd9Tf"9G#s"9I"jXBng."BYd-?s<Z5!NZI2HXHouDZg*2"9\bT*!:po6pr:'"9^Rb!le.A&k"FK"=+N5";Ff\"<:Yl/-KK/6pq'k"<8Zi"Kt`,";q>!!Mqm];Zm4+"9\h1/-G?>!K89,>ZE=;6mMn?9I'aO4<t&GDGpZ@m0eRM!!1pWzXGS;(;Zm4)%%IUU";E*a%?OKk]`\B.!W3'$oE88!X'f-4@fcK0lrA[GUi-A:;Zm4)UBC^m"AEbI%#@gb=9JYh!Q5*DbQLU\"E\\ce8RUXM[]4\!ShVpE!Gn:,Qn//!R(S[!R*(+!R(S\!P\a?P+)Kj!!1"=7[jFs!PnfT!L!Q&!L*VL!L*W'_dHN/"9F0J"9IS%$`Hu,cr1&M!W*!/K*5_(gh^q<DuohCAr?e6"9a*k9EVLt$A9Z-!Pg5h,Qq(G;Zm4s!W3=]"9_g0!i,o$!NQ9tqu`-j?riHl!UO]n!N$$Z"9\e%":W(E"8GdtOAc8bN!ccs#*T)q+&`:F<_NO]"9\mtRfiFa$kcNPA0_9lUa-(:<$VSL;Zm5&"cEDc9O%dPn5BGmL]WJ<"AE&%"kZ`VU]U`&"9JE%!i,s$9q,N0$(Ctn!K`LQDZg+-"9\e%"9t5l>QMVk"5F08"9]EI"di%`#/aJ8Io?IQMd$Th,QoZ;E$GKj"cELoirj1;"E\TIHuK4XB2\p99I'a?peq:u*4l=Y$cG_Xb]a0M]Ek#9*)qChe34,5S-Jm#%brQ>lWXd&^B=Zf"9_[)"9]35"9Q&2>QMVk,[jYWi)9a];Zm4."9\b`r!1SI"BYd-#0R&Fr#hJ:?kW>;!UKoH!i0`;^f(@=<+V6u$G6c['R'cR!K7*Hge;7.!OP#o!rNG%'FCQc/8QR7"EYml;uscc9I'a?LJn<Y"9JE$!W3(&%`;[Y9q)1]lii#LUi-A:;Zm4)"9\h2"9G])!ME?o!N?2A>7=b9"9_;K<)`n5">hA,!nL9QWrdqW!W3'$"9_g0!i,o$"nMekKEK\2?j=dU!W3&KX'c(*"9Iij"9PB;!p3Da]3>\+KB!(84A9\p%f@RT>U0FtBN#$:2HU.#;Zm4s"9\miqu`Tj"BYd-U]U`&])nc0#,>Q.=lTP\lr2YHUi-A:;Zm4))$EW/5D'(A"9_D;"9br-"0b],A1n'"Ca9-WF<guG"B&2UaAW3E;Zm4-"7Q?$"cHDTel)\S!KiiP,Rb;b6t@PG"Df=d!esVV=9J[&"9J,toE53.?ig-*!W3"WgL+d^"9Ij2"9PB;!LQdgZWdi;@8nKRlN@>)<!0$!(qWu\G8ps[KF>FD/6mZ,X?I$!bR1uc&)8Z;Duoh=E"`@b;Zm5>!W2uF"9_g0!NQ9T"9J,tKEM=hZX?u=irScV#.%\@$0)'aljM!EV??_s"9PA""5$NTDunu%>7=J)"=tD%"cQ\3A:+FTYYtZ-;Zm4)!W2uu"9_g0!i,o$"1nW1r%P0Z?u2#-!UNjN!i0`;T2Pjq"9JE'!W3(&MdQaA])hg5o3_T["9Ij`"9PB;!r#UrOAc8bOi%;'"E\S`HuK;=!Pg5h@8pK:;Zm4["9\e)P6AX!9O'O]s&0%';Zm4,"9\e'Rf_MH>Q_\D;Zm4sQ3?Lq"AE&'!qoOq<_NV0"9\da"9^Y^"9IFZlu57k,Qo(o>7=b9"9_;K<)`n5"=,5q"A_r!#)6%Z&rZsp(%_ODE,C41q[C\bS90,ZU]kQ=+l`\2/-L?>>[.<F<$YmOE/Rp/>U0G'hGXO["9JE$!V?Ls"9H1=".K>hoEL4]?ig-*!W30!RpZE[e,eoVU]I=u;Zm4);Zm50"9\k)P68Qu2?LVo;Zm4s"9\n2qub5C"BYd-U]U`&"9J,roE53.?ig-*!i0,>_dES)gB%4XljI3"!N'r>"9\e%"9XEX"7K.k*`E1Ez^_d%O"9\e+N!"T/!PJU:"9F_i"9\j0]E,YI?j""A!K73J!qTem"3U_0KEg1=]PdoR;Zm4(;Zm5"S-/nL"9GP(]E89>"9F_f!PAP;_dI#uqZ4>3S.f92?j;5a!L*_>RpZ8d"9F/V"9H/R!J")O!U0^i!<aYn":g))"=,6<%BBUhF919@P&saJ'"`5dF904"P\^Tjo0d[$"7on&HuB-ETMksr)$Co[,Qo(i,Qnf,;Zm4S;Zm5B=9M#m!sA`0F*%P$B;5T7"9a*klZ<0BF:$/"[WG&^"9\i.P6=WZ"E\T,">EaWFDqb[^/G.;g^TbS(7[Dq%T<K5LJn<Y;Zm4(!PST<"E[6=!(TrjzWm;Xb;Zm4);Zm4?j9"s5(\AmR(fLP?#ZCj/Lf4EZ;Zm4(P6:or!JGE)YYtZ-=9MS)X'>c1KEMDY!K;(#Erh4&gC0T7!L.O.E-f,!N!'0O$J]V%!P\a?N!'07">k0#P].q\^B=Z?Muek<Y5s:W^]B)h[K2$^"9\i.Zi[1)"BYd-]`\A;!OMt1"QNl7#D3&YZid(2?jMAc!Mfmo!ShSraAW3E!sA`-!NZ=W"9H1==9JZ3qZ4&,#5_d/"cEE:X9SQ0?ig-*!ON&`gL(9("9G;!"9I:r!Ou&2]`\A;!OMt1ZijJ6?j"RQ!NZBeP@+NOCB:dEU^#jegi!;r;Zm4(;Zm4_KQ3JO!JCFR!JF@O!JCKiP["9Z;uqXQX'c3c"9R'T":Km$5;#k;!JF&J*`E1Eqcb$k,Qo@p",o?!!KuJIHNXi&Z31:5"9F_fKQ%j1;Zm4("=+#'*%V41'Ee5:4>\;d@EVj`"FC8&%T<K5z^a9$]"9\e6"=TX9b]!ga;Zm4((5s^3b]"BR`"&R[PQAlAg^q[:$1&!:'AN_D$JYZFP]Ru<.&2.jP6;hP!L.\6$b^q8"9\j@M\Mg_!L.[:!hF^d,b"pMHi]IR)glVrFA\M1I!bsZ"DA&%P]VADdr]s<KC`IV"3#Wg"9\j@HqW*j"DA=ZP]T[<UNCkaBS0\@cr1&MFA&)3FF4+Rb@#JQ#E=+;"9\j@Hrc>-"DAOPP]UEaUNCka$*.GkBG7LqFA'd["FL67:Y8SKP]S^V[=!?&UBG6D!L.[L;Zm5N:7Fi-Hi]IR!J(&hHt9!["DAUZ$d;S&I!bsZ"DAM:P]V&+c$Xm>Ws!)H!L.[;($0gj"9\j@HnN35"DA&-P]THkeU2`F"9`BC0UPcAP]S(Tja;FVK*5ih!L.[A!KZPoHitC9H`L@uF9.2MI!bsZ"D@msP]SJR"9a)QUJ[+OP]QqVrHrtn]EDm_KFDr'XD<_&]E,,9KF*kQXF+ge64BXj%)`IZlidNF)6J8g5gojLHi]IRBFgqeF>oBd"FL67.e$@>8d$cN"9\bL">eD'!iuJ,=9J\YlN4-jGl(kQ!W)qOKR!B%?uk9/oDsp*XD\4B;Zm4)"9_'DHo0b["DA=bP]UNlgN7fDEg'm&?ja5^"9]a?MbJq*!L.[,$AEkT2ld'pHi]IRBF+9YF>WRlI!bsZ"DAS<P]T$GNI6*S]*)dY!L.[V(YsId%-n%0Hi]IRpeq:u&B0#9FNXf#Hi]IRBG._#;Zm4+!Lum:"9_g0Huf>4!JQ./"9I"kgi*Mq!R(ZI7IpX*!Pnf\OimdL!!1:E>0?rj!Pnf\0p;X^!L*VT!Ls27UL4^e"9FHc"9Ik-0;)5HP]Ro:qfI2d8t03a?rEbA"9]a'F:F%)b@!li(sRGQ-*m_fHi]IRBF:;X!KPn;Hi]IRBFUM[!KbJ-Hi]IRTMksr2j4A."9H_c5j2,L?t5sRV0jA;_ZXWb!L.\Q%,H;Y"9\j@HmP^i"DAXkP]Rh%c$Xm>"9`BD!iAm!P]V>k]mP2.b62JqP]Qqdh0aSN_ZXW[!L.[;;Zm5NdrYWS46p9TBEYGbFA]XQI!bsZ"D@hDP]S[Eh0aSNK*5ij!L.\O".ageK:<!W!L.[,!f_ST'Z1&eHi]IRLf4EZFEaJ`I!bsZ"DA8+P]V#r"9a)QQ$`R1o)r_>P]Qq[eU2`Fb62Jr!L.[?;Zm5Ndr[q'*4oTpBG]3HFDK>."FL679up69BE\9]FE@<^I!bsZ"DA"!el)\S(PR5;Mu*Wj!L.[,;u:ZaF9Ci:?ibh2bB/*+LXTWl;Zm4($)N#n@*8[dHi]IRBG?/J;Zm4+&u.sqHi]IR!K,?JK.H7q)[af6F=r1KX*ar4"<2_;W)Eg%&?U=0_ZU"c!L.[q+nKf'!J0iMhbsX\F;Em=I!bsZ"DAP#P]U9m"9a)QlQVEh!L.[J#lT-uNOo=,!L.[,'D6a#DY"!EHi]IRQr=+j2sYPlHuuu."D@u3P]Uimc$Xm>"9`BC!h`Hp?o4X#Hi\kP"DA1FP]S#=ja;FVdfa=l!L.[=$cRL@F.3;GHi]IRBFLGZF=*acFF4+R?ic&+"9`G>o0\%,!!1;%7B6I5!Pnf\<l4s^!L*W'!Ls27?ic;:!K7bG!UO_-YYtZ-&=n1tK;/Q_!L.[,I!qK3D7]oiHi]IRBFjKX;Zm4+K6/#^ZX<fjdrYVHGPbcFBER@DFB?WgI!bsZ"9`Bi4,?f<BEl_/F>JgXFF4+R?ibi5V0jTd"9`BC25jFV&p.X<A-<$WFE+'tFF4+R?ic1D_fQ%Y?@uX.?s9=I]6"R9"8cJ3BEPqqF>pf7"FL67(!ok^BFXW^F@*#2K7!]a"<2^sgKT&Q;Zm4]c$T`!dfa=e!L.[I"P%mI"9\j@_]H$\P]QqW:m68-b6/c3!L.\O+d7"qHnk5#"DAJ1P]RK&`I*%6MZd]*!L.\1;Zm5N!e`29qug+)!PJU:MZN_Y>jGc%-JJTToG5n`XD\4B;Zm4)"9^UGHjB.>"DAVMP]SmSNI6*SRfmC;!L.[Z;Zm5Nja8bDUBG69!L.[i'r?;*6DFZsHi]IRBG[4e;Zm4+:ZE&&Hi]IRBO(]#F=GrI$`!fffM_nUF>gHhFF4+Rb@"bBHo8f*<SIWqHi]IRHi];oI!c&9b:S?N!L.[R(o;V-7=t_VHi]IRBGf9IF>q)?I!bsZ"DA>-YYtZ-!J83XHi]IR)gkiLFE#D+"FL67.`bNkP]S@lgN7fDP@+EK2=knk"DHh'(ALf2BF2Y*F;!=2I!bsZ"DA=2W)Eg%;Zm4ONI2-/]*)dSP]QqhKm\7KK*5j*!L.\-$/KuV:SS&+Hi]IR?k_jJNI3.TlNCl0!L.\);Zm5NQ$agDdfa=b!L.\"!QBG6"9\j@":(;m$.)TRF9.2mFF4+RX'dcJja7)d"9`BJ(T:78BGB9MFCNu-I!bsZ"DAX+P]S>6"9a)Qb8Q18!L.\$C"%0OHo7*q"DA%RP]S7iQ$dr[irj$!P]Qq`Km\7K"9`BA+FmAnBG''JF?YlkI!bsZ"DAP+P]Rf'omD,f"9`BR&b&^%YYtZ-F@uE[I!bsZ"DAAFP]UQ%`I*%6Ws!)C!L.\>'uP-@Hk:p<"DAC,P]Rdq"9a)QHmHL+"DA1fF9.!ZI!bsZ"DARYP]RW""9a)QHp+-$"DAVEP]Re,[=!?&"9`BP#`)C^P]U-qc$Xm>lNCl8P]Qqd"9a)Q">,.&"R]1kP]V/N[=!?&RfmCB!L.[e%$c3f$2Xj=Hi]IRBG%q*F>AaWI!bsZ"DA4GP]U?/K62JA)XCd*BGnL2;Zm4+:"(<-Hi]IRBGHe[!K!9KHi]IR?tK4W"9_'?"=hJk!NQ9\"9O5Z!fR7a]3ki$!e^T1lX1%J"9J-s"9PZC&Vs?g]`\A#!Ls8n"9_g06urCQErjbnP5>B(!ShVpDukk"li[@M"9G>"!Pfr`/*d5ce4B\jBS-Eg"9I:sDukO],Qn//!R(S[bQ37#!R(NE!R)&>!R(S\!L.-L!R(S/J!0o'N"t)Tlu*"-;Zm4(eU0NIlNCl1!L.[R)#\i0'(Z6>Hi]IR?n[^c&sF9(Rfj[X!L.[?'nq$_"9\j@Hp5nU"DA+lP]U<>Q$dr["9`BD%A6W&P]TEJ210cP'8$F$Hi]IRBEONIFBZ9Z"FL674kN[9BEH_3F<olLI!bsZ"D@l0P]Sm[h0aSN]*)dPP]Qqd"9a)Qo.A<f!L.[p!r[Lo.%:?QHi]IRkYhTe!Mfi(S-/kn"BYd-ErjJf!Rq6'Wrt8#!ShX0!P\a?Ggc]C!M0>AMZa(1!ShWg+T]dibZ)1W!R(NE!R+L6!R(S\U]H4fbQ3q/ZN6Qs5HA0:DZg*""9\blHnj8P"DA=RP]U6\j)fYLEf4=C)gi'H>C:f$"9_E1iusdg!L.[Y!R6">@J^1@Hi]IR?kSZFUNC=Y:&A<0?t6Nb2=k8"df^V;!L.[0Hu+F_Nf+#Z!L.[,;Zm5N[<r(BqZLR>P]Qq\=ke<)"9]Zk23:`>=9J\Y"9JE'qud&6?j;Mi!e`;7ZX<h2ZN>e73.kTDDZg+5"9\e-o*)!i!L.\%"JpKnHBSJFHi]IR)gjj@F;aZQFF4+Rqd<7d"5S?=F5mC:Hi]IRBEA'Z;Zm4+D2U0bHi]IRBG$e_F:ub"I!bsZ"DAF=i)9a]"9O5o"9\j0X9,I*?j>ou!eb+-X'dmXe,f1SX9#1.;Zm4)2#@UCHi]IRBGe.)FCM9R"FL67*4SoMBGgDiF<^#RFF4+Rqd<.1>H;ik!J-GBBFNF=F?IGDI!bsZ"DA(kP]S5ComD,firj$'!L.[FN:V.=:9.b'BG^&`!K=o!Hi]IRBFpGVFE*3AFF4+Rqd=*T$LN3K"9\j@">u9>1ii]AE'g#s"9\bT!R(SZhGXO["9O5Z!e^\YMdQaIo)aSNJqIH="9J,q"9PZC&=6;u?s;T4rHo'TWs!)D!L.[o%D@.:.)Q1$Hi]IRBF4WbFDL1F"FL67*O&HFBFL_bF?8^jI!bsZ"DAO@P]S.."9a)QUGS?:!L.[j:TJSbFD'?9?ic)D#h16>"DA>EP]Tm2m<j9^Ws!)D!L.[@&bUO!"9\j@b:eBE!L.[bP4NdC)oH%aBFaEWF=uk^FF4+RdpNX."9\aXHi`/(irj$1!L.\C#K;(<-F3hgHi]IR?j`ZNc$Wj8"9`B?'A-4dBEkklF:7+3FF4+RRpZQg;Zm4A"9]gfKEA4W"BYd.#3u>l!KERV!W)qO!KERV*QnM;oPiPmXD\4B;Zm4)V0jSVK*5ih!L.[O"LWW)>k8)3Hi]IR?r+sf"9^X[F>14'UL5D6"I4?i8rEgcHi]IRfM_nU>*F%[HrQ#3"DAV5P]TRq"9a)QM[Qsl"<2^qP]R-$X)r^iI\U9_?qB$oV0k4[UBG62P]Qqe]mP2."9`B>F@]=5P@,!o(X7=<#i#Pr#G_cM#g=3f!Sd^X#L!7V#5!:ZX?m'6U]L)m%'0U;BFqS!;Zm4+0V]SkHi]IR)gji]FE`WG"FL67)PC"3BGm(_F:j-.I!bsZ"DA8CP]SC]I]Ihs"9]Zk&[51:?mbbmc$VLOe-'Fkj:$,>!Jp%L!Ncn)"S;kVHu&kS",$]F`!D#_"Upn.;Zm4+"9]1*dj(eiP]Qq^h0aSNqZLRC!L.\T;Zm5N"9]=VX!b,M!L.[a(SuM,60eYeHi]IR?o>!,c$X9DgB;0s!L.[:'\.SY"9\j@GLHOjHi]IRBF^#LF<@OdFF4+RZX>`P;Zm48PB7\hb?t@'#OHOa"ge<P)tO*3Cl8=`?sM0&j)clJb?t@2;Zm4gSU:L"lNCl2!L.\R(Ti(4"9\j@p'er>bXr!I;Zm4(/[HSPHi]IRBFs9QFBJDC"FL67%#.[`BFV(kFEXtnI!bsZ"DA(C``!!C7AFr9V0kX<o)r_@P]QqeomD,f"9`BP-b*(XP]SFN`I*%6irj$/!L.[u/=Ua/M_*=b"<2_&P]TBQc$Xm>b62Jn!L.\?(%ls%7e6arHi]IRfM_nU5FZa0HirD:o)r_I!L.[["8.%h"9\j@M\+cE!L.[L(R9Aq>Oqu2Hi]IRQr=+j!VLgE+S,_LHi]IRBEddNF;+6K"FL67'<"h4P]U33`,pA-_u[sbZOHI,dfGq834j8iHm#1l"DAD/P]TL7rHrtnK*5it!L.[F=Gq9K"<!,*"6WSc=9JYp"9F_ibQIs[#s=+H8V7&%!Pnf\(RkHLbQ%[fbW"8WbQ5N\!Kb2"!L*VL!Ls27ZX@24"9FH'"9Ik-"9;@'$hmR&P]S.>Q$dr[ZNOqW!L.\P'@hJX"9\j@F<A"kX'eoeKmWoSlNCl+!L.\##-E9#-^t6PHi]IRBE<g7;Zm4+om@P=UBG6A!L.[?&qt^\"9\j@gD6D[!L.[X"MK21,JsXtHi]IR?rs+Fh0_eHP6>P"!L.\J"oWgr99TKlHi]IRBEFHH;Zm4+%(m2@!L4M?"9]XmHkt=4"DA=*P]UT^X)r^iKB$>g%>B01<N?79Hi]IR?mVjq"9F5B!Obo0BF'TFF=Om*I!bsZ"DAX;P]S%SB$5Q&UBDN`!L.[f$0?P^%bh,"Hi]IRfM_nU;>YG]F>2`_j'X.=Hqf4o"9\iHZN\oY!L.\2!Te]V2Tl5:Hi]IRBEG;`;Zm4+(Y]2'ZiQD5'T7&9Hs3RY"DAR1P]T%R_fU8,#+K!d?o>Q<"9^6uWse,iP]QqeQ$dr[o)r_=P]Qq]XaGKsgB;0r!L.[L;Zm5Ne8,ks):W%"P]Ta.SU>ecK*5ij!L.\:BK^`jF=<%M"FL67(?\U!BF`:7F:!R&I!bsZ"DAUbP]SSU]mP2.qZLRD!L.[d)9mPV<8.OhHi]IRBFV@sFEd<Z"FL67'TQ)pbQ3=5bQ5N\b[BH3!R(NE!R+fD!R(S\!M!p%!R(S/H0YL$!Kr(CDZg*""9\blo,<-XP]QqV*fGCHo)p"[P]Qq`XaGKso)r_/!L.[V!mQ+?I_u;%Hi]IR\5NM5(=ddP=5*jkHi]IRBF0ZGF>`@e"FL67!VTFpBEX$:F?I/<I!bsZ"DA%JP]Rr+h0aSNirj#s!L.\G"l4QR0rkFjHi]IR@!dNJ_fT&Q0#M';?j`BFF9.?DP@,Gi;Zm4i!Ls_Y"9_g0!Q5'CErjJfFiso0"9I"kgi*:P#4hru"9IS&bQ5L)!KH+?!Pnf\e-#fr">k0#gi-kX^B=Z?bQ62o56977$i^7O!O`$Q;Zm4+FF)+?FF4+Ro3ank#2OY_"9\j@UB[r$!L.[2%(1J1519XJHi]IRBF_Ft;Zm4+_fQQhCWg*?)gjNDF9h[GFF4+RMdUh2LPp7n9XA+-)gjg7!K4PmHi]IRpeq:u"4_cB,kD.PHi]IRBEX<B;Zm4+Hm/)n@\X&FHi]IR?nCnk"9`Vkb8u14!L.\8$^H*eqZHrV!L.[N;Zm5NV0j<!RfmC4!L.[\HjkXT3R\*MHi]IRi)9a]F>)q]I!bsZ"DA")P]UW/"9a)Q"9acaDukZ^"9\bL]*5rJP]Qq\dr]s<5+>r/?m=WQP6$L2"<2_$P]SA'K62JA1YZ:WBFUecFAKdW"FL67&a*'qP]UB`Km\7K]*)dR!L.[m+PV!c"@JA\&\_0H@MIpO8+Qi,Hi]IRBG:>lF<R+V"FL67)n/`KF9.)JI!bsZ"DAJ)P]S^NNI6*S"9`BQ"9)4%=9JYp!Mfi$"9\b+N,o$D!Rq5Qb62'k!ShW/!P\a?8](SYe,TO!^B=Z?gB#M!!!1;5NiN3)_#_a\irR@)PQ@RhS,ph7!K<cSN!Ht&lu*"-;Zm4(Q$a:uMZd],!L.\,(7fi#En^_1Hi]IRVGdU#FERHdI!bsZ"DAI.P]S5+`I*%6"9`BJHp1I3"DA[DP]T"9`I*%6K*5is!L.[5'?toP:?r$rHi]IRTMksr"9O5m!e^\Yqd9Vd!e^T,K4&]""9J-O"9PZC$^XcpP]RS>rHrtnlNCl8!L.\''ubQJ>/LJVHi]IR[Sm;3F@X4bI!bsZ"DA"YP]V3B5MLPdK*3-@!L.\D;Zm5N(]+]nP6;hPP]Qq[m<j9^b62Jf!L.\HHn=l:"9\iHF:>$Fj'ZcjUN?Nk3SRpVBF(/VFB5.>FF4+RlX2'O;Zm4OPB7h;LQc+1!k!CVL\h3f!L.[,;Zm5Nm<fH=e-'Fs`!g_oKQ$/_]E,,AKF!eEUjQtZ64;!B!iu^@]EJYdCTDOYHkPII"DACtP]V?&gN7fD6*"BX?lo2eSU>p>"9`BO"0b],P]Ssmh0aSNRfmCAP]Qqg]mP2._ZXWf!L.\!%/#!qNT1.T!L.[,(B&W.Oh1a0!L.[,;Zm5NO6[eC"<2^hZWhg)F=DijFF4+R?ibf,9tLJ="9]Zk$eA5ZBE>eoF:5,PI!bsZ"D@o)O&H/aX94+c_u[OR'YSl5#HS&A%ce%?#III"$1n8#&$-95%buGJN'[c&e-q!9!L*`mBF*FAF=PH:I!bsZ"DA7(P]Tps"9a)QKGq$m"BYd.X9/S."9JE%X98R;?in4I!W3DUdpNB4UB6)XUL4+U!V?DU!j$;CaAW3E!KZO^HitC9EjJttP]SIo"9a)QHl)KT"D@i'P]TTOKm\7Kb62J\!L.\3;Zm5NMf]8sG`uMIBGleWFEZ+9FF4+RlX3Yd;Zm4gB:B<kHi]IRBFq"fFB+5%"FL67%-UUmP]RkNm<j9^irj$%!L.\7;Zm5NLV"S0!L.[,"SI.iA(q-"Hi]IRBEb5[;Zm4+XaCGZbQMSpe-pF#Zrrk,e,cZYU^50Tb^=4664E2k!osL.bQS@'''4KG"9\j@F;M/[MdSQ/(<q508#lc+Hi]IRBGTEOFF*6UI!bsZ"DAU2P]T[,V0mXklNCl6!L.\H(nH&%"9\j@KGXVd9,5)C7=5]3K8TkG!L.[,*g:\nHssp#"D@thpJV1tF>LN0I!bsZ"D@r*P]U$N"9a)QHi`_8"DAC$P]U@"]mP2."9`BH#jtUoBF_.lFE,b4FF4+RdpNUUNh^\<CU7CLmo'>l!K-agHi]IR!JR:jHn=SkRfmD9!L.\0BFT?:;Zm4+@G:t$Hi]IRBF:S`F?&RhI!bsZ"DA.mP]SS-V0mXk]*)d_P]QqYX)r^iRpZ8Z;Zm48O6["Y"<2^h_cqM9!K#QSHi]IRBFiX@F=E+N"FL67&%>I?@!^jT_fQa-0ABl&BE=ZO;Zm4+UN?UH=PI4OBF=]cF<-PJ"FL67)TG\Y"hb)X?/l'$Hi]IR!J6e_HpbeZ"D@r"P]TQNFaSQ;"9\j@";^H)>]TqiE$OBG"9\bT!R(SZJ5ZRR$(ZGQGiJp?Hi]IR_$[l']FO!'U^V>LX=D[)U]IS)qu_TVjEtbFKL-pj`!E^Y&%i&SBGS:/F;q7`I!bsZ"DAF]P]V9LrHrtn_ZXW]!L.[]Hud\`I!c&9o0gK#!L.[Q;Zm5N(5j,lbQ%[fbR'I6bQ5N\U]dFnbQ3q/qZ32f?2J"<DZg*""9\blUCd3!!L.\SI!+Is1TLWtHi]IRBF2(o;Zm4+"9]e/_Zn[jP]Qqa?L)t>HitC97)N5V``!!CF<uPQI!bsZ"DA#<P]Tg8m<j9^"9`BB+-'8&?n2%qNI4U`UBG6I!L.[:'Wlb1Ggce/Hi]IRBG/:3FD]J0"FL67&\h6IErjJfb64ng!RuKF#Q,(%"9IQegi*GG!TX@a"9\b%bQ5L);Zm4(8BVJ9Hi]IRBEcA&F?K-tFF4+R?ic,U"9\e4S0X+n"BYd-ErjJf4duRr"9I"kgi*;+!TX@a"9\b%bQ5L)bYRg2!R*S*!R(]'"9\b6+m)]+BG18kF>/=MI!bsZ"DADG^Jb7<!Km7%Hi]IR"DCMWP]V)$L7<Pk"<2^hJ5ZRR%c)L6GJaPsHi]IR?rm/H`I(_@"9`BH"4pHSs&0%'HlMZ!4.??lHi]IRBG/jCFD.-HFF4+RK4$I(%[DE+"9\j@";fWf":.p/&`6Li!L!Wh[01:KF9E9YHisJG"D@o9P]V;RHihLm"DA"iP]S+5omD,fb62J`!L.[cBN9G-;Zm4+om?qqMZd]'!L.\;I!FCnCs)r#Hi]IRBF)S);Zm4+@%.qGHi]IRBEarSF:,&O"FL67-B;"-P]R_j$C#o=!W#KZKmWt!RfmC5!L.[V;Zm5NKmX6cdfa=q!L.[l(p/15#eL4QHi]IRpeq:uF>]NjjEpumBF:jNFCgXEgO'$d"<2_[P]QtZ"9a)Q"<7A>!NQ6s"9G"qbQJ&N!JGLpE&a<i"9\bT!R(SZ!R(Sg8t,k&!R(\^"9\b6#k([pBEbekF@DAr]6jXD!L.[,"1<LZOK/Lt!L.[,;Zm5NKmY2=K*5it!L.\F'!6P/"9\j@HjK4?"DA'p%!3!7bYti!Mug$cbR1-Nr-W;j648_]$iC%lX9B*PBRP7=FAq3&"FL67'DGE.BFN.5F;p,@I!bsZ"DA(SQW""i6*kY=HmuC0"DA0sP]T3D"9a)QK+";M!L.\9"m(,ZL8+lb!L.[,;Zm5N)Ts)'Hi]IRBFgY]FCiVu"FL67&$Ah6P]S8<Mfa=Ib?t@3h0]6a"9`BL'#%9IP]T0sm<j9^ZNOqI!L.[n&^>]N"9\j@F;Dkp]3meV$,(^^MSfR1!L.[,;Zm5NXaCB)dfa=f!L.[r"/UBm"9\j@M\XN9!L.\#'8:g]Bo<+-Hi]IRBG74i;Zm4+'tXsRHi]IRBEl.tF?QB%"FL67Rn-H\!L.\5'&@q_&"<]8Hi]IRY#>H+;Zm4,Mf^6,?^"kKBF4?ZN*k<BHi]H9QW""i;Zm4/$i^g!!R+.=Q;[nh"c[m8FRoWKHi]IRBE>5_FA8e="FL67&>iA/@""Mddr[.A(@tp,?s)H2"9F4G&aiR#BG\X8!K=VnHi]IRBFffE!J&>rHi]IR?ojKn"9F\G&,oK1BE=*?F<$2AI!bsZ"DA#4P]RMd"9a)QHn(1U"DAOX%!2a8K"D<4XUg?kS-n$PC^,Oo/-u0$!phI)g]\,)&[cuf%GM#!Hi]IRk#2BcF?\^uI!bsZ"DA(;P]Tj9Q$dr[Ws!)M!L.\J$C-!d"9\j@HkcQY"DAL/P]Sj:K62JA)q/27BFE@<;Zm4+&H!ZZe567j'((&_%''MEHi]IRBG0uc;Zm4+"9]s8K,h<uP]QqalZ@LT+8]GiBEIRKF>E.b"FL67%/*U&BGmXoFD(IRI!bsZ"DA@sP]Ts,"9a)QZRF-u!L.[o&FFjm:YQ"cHi]IRBG%@oFDn2_FF4+RX'ftC;Zm4Rc$Uu.Ws!)>!L.[f-%#sI2T#Z2Hi]IRk#2Bc@B4JW!JHA=)gijiFB/2@I!bsZ"DAY6L/S3XFDldGI!bsZ"DA@kP]TLoeU2`F"9`BJ+hpqYpJV1t'ZGGF;UYb^Hi]IRHi\oTFJAsXHi]IRN`-&`F;arlI!bsZ"DAR)%!2NG3hlqE!Ncar%?(V3Hu&rH$-We,]FU5n"V&Za[<r:n"9`BD!le.AP]SY'XaGKsb62Jh!L.\9(%$BrB'TS5Hi]IRT2Pjq!!!!7*<6'>"9PU?!Ou&2"<B<%!X&k[>9#a.">"np";Cuc"9^8$Zi[I1!PJU:!Q5*D]EA89"BYd-!W)o)Ziu@q?ig-*!PANH]3k`aZN7uH]JEpr?ig-*RfU/X"3Y'SDZg*B"9\bd"9^tg!Q70#e/0.3)$D2oCU4-H,V0XK"9IOe":.p/"@#ff!ME?o"BYe+!PJV0!JCRYN!)Oi"AEk;>]Tq1!Ktn7S,o.!!P\a>"9\ai!K7&oErhL.gBHY#"gi4RE#I+-X98R"%*Tk#+T[6!KOg8L!JCFR!JDi,!JCKi!L-8NZW$sY6k`r2!MjW:85fWo%g36@"9Gk4"9\b=!TX=c=9JZ;K)r=^jE"]6F'rba?m>]b!NZBm!T\/%%T<K5VGdU#!#u"?z!ihCd+B&CG";q=V6X(6E"DSnZ!O;h2;Zm43X9=ate,bR1!!!!@#QOi)"9PTflj-Mm3WdMF"9]CN"=*tG'J'A)!JILX1aE2L4<t%L"FC8&!O;h2!!!!-,ldoF"9PX!#2iD_=9J[&"9J,toE53.?ig-*!W5Bu_dHih"9Ijr"9PB;"kZ`VS/MN(,Qq'Q;Zm4;!W2uVqug+)?j3;+!W5s`]3n"L"9Ij,"9PB;#OkXp%D4I^">gN"">!e'";GAl*%YnO"9_Cu"9^ne"9Orh!K^4_&kk]o,Qoq4,Qo)l<?*8p,Qpe7,Qq(';Zm4C4Mq?T1^k!j,[;St,\//'"ADf8lX3Wo1c>n0W)Eg%;Zm4+;Zm4n#290F">i"i"NXLE9I'`l"9J^"!T=/TliN\.lR5[B2?UGj;Zm4["AAm$<!Ku\">hA,4D.Rq1\4fZE.<KC;Zm4[;Zm5Q"9\b>U]TaYN<f@p";QRj"h7J6U]U`&"9JE%!V?Ls"9H1=!W)oioPgj=?ig-*!W4Llb?tOdMZT\*%`;ZXMOOYE!qTe#DZg+-"9\e%quaH-"BYd-U]U`&K*%hMB[^>k"M4^4ltWS/Ui-A:;Zm4),SU:C"=t6s"9]tqo)diK2?_)m;Zm4["9\bGquWYr"BYd-"1nW1quhpc?j3;+!W3(YdpNB<"9Ik="9PB;"Fa8P_f&HV1cA/5[Sm;3"9J,q"9\b=!NQ9T"9JE'!W3(&b?tJ%qZ6<j"4LWY!W)qOqubDU?j6-&!UKs$!i0`;?W.(1%T<K5!oF6`"9^P>"9P`)!P_P9G>eVI9I'`\<$VT/>U0Fd85fWo!J0hFWrt7u`'eP[[Sm;0)$E>/>7<n&$mYkc"9H,=1iQpQ[Sm;3;Zm4),QpM9,QoB',QoZ7,QorG]M(_@"9\i."9Z,3!k)#1=9JYp!sA`0bQIsb!Mjc;ErjbnP61A=!ShVtC823=":"L;!V?EB!Sde\"9GTFCi]X<!P\a?!Rq/*e7/O7!P8I8"9I:s"<dfi!R*+To)[&8_#_c"UB/R>PQA]*S,ph7?j"jY!K7)T!T\/%mSa5k;4@[i"9Og,"9]_r!k)#1WrdqW!W3'$KEPB[?j=dU!W30!dpN@6"9Iii"9PB;"P6QT!kniu"9^P>!<]K'!!!!EPT^#,"9\e,kQg<Mq[b"X;Zm4,"?Zgc$p4Y1!P8AlE!6%@;Zm4K"9\t6"9j<S"n5FnTMksr;Zm4)!T417!N\lr02huVKED>["9I9Z!e^\Yb?tIj,6?RNb\WJNKPpto;Zm4)!sA`:!Rq1("9H1==9JZ[MZSP7"P[;d!W)oIKEU=C?iu;g!Sdb:X'bst"9H_c"9O6pe2UA0!PJU:"9I9\!Rq6Se72lZ?j)Ag!SdjJX'c1%"9H^^"9O6p!jGT+TMksr6nF5s#4hs:6iiN'c>0`h"9]tNF-C99X9&F(X?ON&X9$-<U^)MQX9"Od?qYkJXDA!N_uZ_D;Zm4(!sAa-!Sda0KEPB[?ji_2!ea_:UL41^_ZANobZeHbV?4C2"9O5W"Q32]\5NM5"3`"n/-O0BHj!>8"9_g0!Mff#Eri?FlN6EX!OQfe!P\a?ZigE2"?^`+!T"!DP6:p!_u]fQ!OMt1%EnquX<n"-g]=JWX9#O9Zk(@_oDt*U"-b>@X9.H-+9APEX?M*."9Gq3i)9a];Zm4(".TCr@_5haPUlq&$q*JaS:?/q!LuOc$nQco!eUoG!NcU&ljV)`bX?7O63EGR"2kT>ZipT^>7<n.6l^QKj$Wp<!L,,;>7;36$oA!s"9H,="E79B!e^XY=9JZ[qZ;ER"G:(_"lfX=bQNi3KPpto;Zm4)Zk2#!liE4[>9$$;#GVX$6iiN'qcaIk;Zm4.;Zm4'RficS!N^685#VRe+B&CGEri?F>-e?:"9GlKX9$'=;Zm4(j9,P("9GP(=9JZ[irRp<#_QLg!W)oYg^&O??j<A,!R(et!ebIp!)j"'6mMml9I'`T<$VT/[Sm;3!sA`/!Sda0KEPB[?j6-'!SddX"liu`!ji!P!e^TO*`E1E:/_8uDGpZ@Sl5ap*sSJ@"9]u)$q)aI*"2XJ6ik=r$nMMY!K.-2!NcIB"mcPS6u3%&63m-V%@dk)j95pE;Zm4/!!!(tz!ijcmQr=+j,QpdD&%i%8$H-[Y0N/*:)\c#!>8.bS";G@@b60(9">"L[!glmh+/BqT";LbN!N8p"=9JZK!Rq5T"9\b+!V?Hs"cEERoE!EK?ioWp!Rq@lRpZ?AqZ6<j!h3Qu"OdCq]EOd4oPXj5;Zm4(;Zm4M;Zm45"9H^H!Q5+C"9H1=Wr^]Q!Rq5QlX0bjqZ4V9!UF+o?m>]r!R(T1ZX<gW"9H.="9J.5!glmh]`\AS!R(ZI_us0F?ig-*!Q5,i94.et!W)oA!R+2Ej'W#E"9H.="9J.5!Ou&285fWoBFW3S%_YO="9\j@MZd'Z">k'#/-I+A"DA16BGg+n%-9SS"9\j@"Dh.<S-/ssUf;C9#rg$.X9;;!!OQnKEriWN^B=[U"9GS)"9egrbQ3==S,pkAS1UcBS,pG,C]g^=!Ls1T?j)*u"C)(^"9Gkj!Oku1<$VT?"9J^*[T!:9"9\i.oDu*nZ3C.:":a\u"9;@'"9F\h)[oGn>7:oC"9]eC"9\^'!!$>(z!ii@@J5ZRR=9M"nF*%Nf4G*cYMZeEH!JGCmDukk",QnO?#h/mj#J<9r]6"(e_/o^:Mkb@pF9$C`_/q0-#-2hHF9.Uo?j;NWDZhm)"9\aa"9\^'X9;X("9GP(bQ@tN"9G;!!Mfj#gL(5<K)r%S"H-XlEr,m]U]cT`?j!_9!Mfmo]3k`1"9F_j"9H_b"9;@'*"GmM'Ef9V*+U;t"=tf$"9^;%$j!X:&'P<<";C\F!JXMUziZA.#"9\e+"9F<W!iT$#=9JZK9**6>!R*'%b?tIr"9H.<"9J.5"Mdq=&i;)],QoA$,QnfL;Zm4s">g1YMZa001c0/;"9^Rb!e=2PH$84!;Zm4e;Zm4F;Zm5:"9H^_!Q5+C"9H1=Wr^]Q"9\i._u]K4?j!G1!V?MqX'c%AqZ51L"KPo2!UBd1]E68aoPXj5;Zm4("9\e9#.+k=N(G)O"9HFJbQIs["BYd-!qQH:`!#+.?ig-*!R(Y@UL48kP6&l0!OH/7DZg*R"9\bt!R+qM_us0F!PJU:!sA`0!V?Eb!L$o,"eu+:bQ3o8?j;Mi!PAN8!VC:5IT$@PSl5ap9f)tR6&Pjk!e`CL"9a)T!L*Zh"BYeCErhd6U]^_*"Di,[S,pA-S6a;=S,pG,!Mfi!&,\P2KQ%1N+/8r?":_/G"<dfA!MfadZN6R7!!/TfF0bn;!Pnf,#P.td!L*VLRqr+q"3Y'UZu6(P;Zm4(1h$88U^R:%]`a9%"=-A91^$JtWrs\B">k'A//V:g&-NjR43LYUmSa5k2$>`:;Zm4+>8/n0&>K9d&$-C+E*T^P;Zm4s@#G-f,Qq(c"?Z_#6uY'5?;gt0zUFlNH"9\e,"9Y;q"3=CD!)j"'i)9a]!mCcQ_up+A"BYd."OdFr_u[2P?j"RR!lP,G.prCIDZg-K"9\em6ik)%!P;PEDUSjGMZeEH!JGDIE*ne3"-<PBHi]*-ga!#5"2mk6S,o-[Ca9,a,Qn.D"9GSl"9]Da`!".["BYd.liR@n@fkuu`!)',?rcLo!ji.&!pjh.OAc8b$iuk'<$2!A!Ls1\;Zm5F!ji#r!PBZ\\cJ#u"9^O^"9Z/4!PhV:"kWj?"AP@V".3!i!V?Kt,Qo@qF9.&B!J&X'">,!(HmAh?>7:Oc"9\pu`!+dl"BYd.WrgKJ!mCcJX'c%A])ondJ(%d-"1nWY`.-6D?j+XS!ji$0!pjh.fM_nU;Zm4(;Zm4_)$FIMV/-8;qZI$&"E\T)HuN$MfM_nU;Zm4*"9QMT"9\j0liQMU?j)Yp!lP1nCL@7FDZg-K"9\em"FLt`"9`BSK*%?;&cn4u"9FGi>QLWG!N[OLZm5c";Zm4("9\c)_uf9-"BYd."HroR!lQm&j'W,8"9Pq5"9Rq.!j5H)Lf4EZ;Zm4(E<HCkV/uhC$krgF"9H,="C>"0!Obo0(fLP?Qr=+j;Zm4(;Zm4>#35jJj<P5"$j!.)49E-!!Ls1dS-/kg"9^:W!Uiqi!V[pn"9`O!!V?k#li^Dn!PJU:X:X\#dfHTS-c5t@!M0A2.`2LeU]:IlU_iV(U]J:5liPoCU]H\\lN-VZ#HM64DZg+%"9\e-]E,K?!PJU;"9QLEbQJ&N"9GP)"OdFb`!+=l?j"RR!mChkb?tAJlN5!.#NK2pDZg-K"9\em%$X:]S1>9N;Zm43Rfihj!JGDhM?Et[K*68s1c0/h'RV//!JD^$N$JNo;LB_jk"V<J!L,JCcVjrLS57l@6js\/!N[OLZm5c:,Qne^"<7HTPQA]JbTm;l,Qo@n"9\bTPQ?M;S,n9E":E?R,Qo]HKR>$J]3>[E!JE!*!JCKD">,!([o3D4(Beg\"9\k)_u\ao"BYd.]`\DL!k\X:P@+FgK*&[j&$oXJ#5\J?`"01^dpO[-"9Pq5"9Rq."M[k<zn/VK/"9\e+O9EX'PY)&Z;Zm4("9\hb]E<[_"BYd-!ODg>]E-JhlX2dT"9GS-"9IS%!r,[sMus1c=9N.8!L*]io)pmk!LtAG!P\a?!L*VLPTj_o!L+&p"9\b6"<LJE"-?Fa8-IQb"9\bC"9_P"(98c\*&[qeTMksr"9H.;"9\j0]E.'qP@.#aMZMl>!L$mn"mZ3%XBYR0jDP/%;Zm4(;Zm5!"9H.8!OMu3"9H1=j9#MfWr_8^Zu]Uh?ig-*!PAWsqd9Q%"9GS-"9IS%9INgBbSM#L>7;b_df]]`"<;A0!L?XeJ5ZRR>7<=i!P8Na1]`=^Ef11h"9]]`"9\^''EOLu!K1.j!K*o\"9`6o"9FfeXE+E,!Ls8n"9`O^"9F`V_[]TJScP'.b6a+.!!/<l&$#_q!Pnf$!M][[!L*VDZXa*$"J]?,Ui-B8;Zm4(!L*^`P6=!h!M"*4E))T"PQV#_"Jd1AVGdU#)$DJk>7<=k!P8BE'Jr$*!P;Q0O&H/a;Zm4)"9\b("9]97"9ICY"?9<_!TX=c=9JZ;MZMlA#ErNt!V6?Q]Ej-t?j2/`!NZEn!T\/%cVjrL"9H.:!PAP;b?tAJb5o6VXCGWBjDP/%;Zm4(>7;cP";D(3"<96D"=-)T1aGI7"9\j*"9H58!NQ7>"9H.<!Q5+C#E)t7"1&$@X9G)$jDP/%;Zm4(!!!%[z!ii4,:f@K"&Bl6/":j31"9^;=*,l\RYYtZ->,qc,"=+t+$q*3''F(%26iifG">)_=J5ZRR)$Dbs<ZDAJ"9\s^"=,*g$q*3'1^9FR6iifG(/k>=>R1Dc;Zm4C4E&+idf_37"AEbt"9]l149/:_";E*a*,o8K!)j"'4<t%L6mMmL"B%?%zllc?/"9\e+"9eKu!L*Zh"BYeCErhd6U]^^O!M"33Eri?F"d9'O"4RA,E#,2OX98R:%%JIAEriWNgBtk]!PE@VE,Ni%ZigEJ"9]kK1ii]1E#@=4"9\bD!PAHJ!Pfr`"9\b$!Ls2*S,ncD!Ls,j!Lu`V!Ls2,!L,[h!Ls1T?j4_i"C),b"9HGZ"IN*j";q=f!Mh7LUc\b_"9\i.g]OKR"BYd-KED>["9I!RKEM=h?iu;g!Sd_1gL(*SqZ51I"litk!W)oQg]kr0?j)r"!R(Vo!ebIpW)Eg%!sA`.!Rq1("9H1=Wr_8a!SdeYKEPB[qd:?EqZ5b^>Phe/"H*<1!TZ=Mj?$`oZX>!Yo)[VL"+st`DZg*b"9\dZ$q((o9HBm4L>uJH@73ci%Eq4&4<UD'4TU2AKF``(&;+0rUK\.#@73e<>7<n^9EBcu''!1)4CLWOK3JaP>7=236qfe6$q*3d"BgXe*#MTW'J(L4*&JoD49SP54TU2A>7<nf$qtH[9Jc9E6p+mGC&;*CW)Eg%;Zm4(":1M-MXqO-!L+i1?Gcms"9]]`"9`pI"9HM@!k)#1"f*6Y":Kl^!e^XY]`\Ac!SdeYKEPB[?j""BgB#f6gga^m?j59c!R(V_!ebIpIo?IQ4TYFB>7<nfZTK1r6rX2>?Oh_l;Zm4';Zm5A!!!&^z!ij?]i)9a]`":]+"LJdPGZ+_Je,ogV"9GS)!Mfj#"9H1=Wr]R1!Rq5QdpN99qZ4&."bU1`!W)nnX9F5a?jFjU!Ls>*!Ru#j^f(@=r"L[_1^!UU$Cb6>b?GB;"=sS4"9\jS"9FT_4;_!"LpL:oHNYl#;Zm4+"9GTC!Mfj#"9H1=!W)nnU]lZa?j3;+!NZJ%b?tOT"9G"p"9I"j6i^-g"8c::>7:u5*!(l%1]a+';Zm?t;Zm5I;Zm4E;Zm4="9\aU<"&f59E\H#"9H1=ErgpsN!'0G">k0#PUC>>g]@$JMug[("7$'j"9Fa+"<df!!JDr/!JCKiKE6kg!JCFR!JDQ<!JCKiPY;.:;uqXQ_dEP8DZiH5"9\ai"9^DWX9$fQ"BYd-"j6qrX9O;b?jDkr!Ls8(!Ru#jDGpZ@";q=fGmhe@"9\bO"9ICY!Uiqizh\lIp"9\e+"9OBX!R(WK=9JZ#qZ3Jq#Ff**"e,P:U^2T\?j*e:!L*f3!R,Hbn5BGm;Zm4);Zm45"9\eqU]J[A"BYd-Wr]:)!Ls8n"9H1="j6qj!N^?MK4"`WMZM$*"bU3+!W)nfU]lBY?j=dT"9F`#"9H_be4rpF*sCX1!g!Y?"FNfE"@,lg"BJG(HuNlecr1&M"9G;!!Mfj#P@+Ulo)YWf"LDJ;DZg**"9\bL"9_e)"9F$O!iT$#?W.(1FF51r!It]V"9GrYDc6cAE*gEb;Zm5N<<O"*,m4?%]EA'O'FZl)j9->'j'*3-aUBEq!JBD5qcaacJcl2X"9^O^Hj!5DgB9?SS8\L\^B=ZI"9a)Q"9]iGVZGXQ!V?Kq;Zm5N"9\b?MZKJLHiSPA_0g0j"4MVuHi]I"?j20VDZi1,"9\aa9ED%i6j-Tp"9H1=1in$IE"'>]"9\aYI!bt0!NB)R[sUYm"9\i.HitirgB9W[#39_.E&dFlHisJ/"9\iN"9P/n!k)#1=9JZ#!sA`0!Mfb?]3ki$K)s0u"KPp5"PWsQPQB6@b\mUb;Zm4(0`_<YzWk0;P;Zm4)!sAaG!Q5$*_us0F?if!_!UKlGMdQXF_ZB**1LL6?"3U_`litpH?j3S3!Q52ko3_`["9Gk2"9Ik-!O,K*";q=fE,`u'$nMRP";naT">EaW"?9<_<,_o^!Pg5h@4X5l,Qnf,2$>H];Zm4+`#bEYoE!)U"9HFC!Q5+CP@+Kn])fhT#5_d3DZg*J"9\bl"<9*o">g.uX9"6K":a\u6uW[;E#uUo;Zm4s"9\a["9]!/"9`%0C]Tb&K*59ZiW5P]"?4L)>]TqAE(/di"9\b,!Mfb2!MfadK*oOR!Ls1Gb5n+5!Ls1C!Ls2,!L*eh!Ls1T?j=5Z"C),B"9GTB!N/j!zP61db"9\e+":QDO'EeOV'EeOZ"9\jB"9]!/"9]35U^R:0MZJbK!<T%t!!!!Eb8UE]"9\e+,QiQq"9_U*,]G:"dp!eC>:_</";Ct8UBED!"?^X%"/o-$fM_nU"9GS)ZigM6"9GP(#5\G.X9/!$?j!_9!NZOlb?tPO"9G"t"9I"j9E7uo"9H1="BYe+Ergps"d9'O":tELP]0]n!h9AoC[2*HKLl2tKE6`,"k-*F!JCL+"9\b6!Q\1Bi)9a]!OMt1X98R)"BYd-e,ogVo)[>A#1Hr\#5\G.X9>;+?j?K/!NZF!o3_]Z"9G"p"9I"j"@c;m"AVkuKQ%fe;Zm4(!JCRuUBFhC!K:tD!K[Ee"9\aY7-dBB]Dr&@KNs]IKE8mi9Ea)N!JCK<?j*f8"@NI;"9Fa*!P_P9^Jb7<`!Xupj8kAQ;Zm4D8d&46"9\aY"9FQ^":e?5!Rq2S=9JZ+'*6ScX95M2?j*e:"9G##"9I"j/3d&9N!+J1/0k?#">p<5zc6*)e"9\e+F9-nj"9_g0<-&)9Eri?Fo)o)Y!OQf`!KuIG_u[Mi+T\YL!OMt4"9GlNCi]Wi!N#u&U]^_*Rfjl8!"#Gt+H$8r!Pnf4"-Wb]U]H^%#O?I4A-2@1!PE=R(fLP?";q>!!Peln"=sSl":.p/!Ou&2#ZCj/#/h(K":4?6!U*GbWr^uY!Rq5Q"9_g0!W3$&]`\A[!Rq5Qo3_]ZqZ5IT"S6"%",d3XquWX$?iu;f9**6mr!(VX?j""A!Rq>&UL4>M"9HFD"9JF="9;@',\^lf0k\B,#b3/&1_,0aX@slB!KmQh;EQL0;Zm4+326MP*"3HB1e].t'N?=\/6jG'4?QU`6l[HT">hA,Ui7?T;Zm40"9H_C"9\b=!W3$&Wr^uY!Rq5Qqug+)?ifj"lN,dF#/agR!W)oAe,e<3_dF\i"9HFC"9JF=,S!`U1diSl*)%U\/6!kt!!H1^zWjj#K;Zm4)$bQP.Zjd,E!sA`8!OMm_X9;W.!PJU:!PAO<X98R)?ig-*!NZIjZX<h2MZMT6!OH/9"02I8g]W7;?j4^S!OMu^dpNF(ZiQs)g]=8V;Zm4("AAj+"@NAp"9\b=bZ&Y2:KF4rN!'07"?^`+P]-l^_ZPPm!M"+.+T[N)+aaCqZja;EP^Fe_!J#P&AW$iDlpMAkKEIGG!mDl"%/^C,ZNKQ<@LSb^Hj\ANU^!o5KEW>&HkZA]o6^ST!L,tT?o(K(DZi0Y"9\aq"9]97"9^\_"<;S`!UKq,"8c:B*"@iX$oB#h,[nSp"9a&S$j!X:(/k>=z_]&RU"9\e+"9OZ`X8l0%"BYd-#D3&YX96XR?j""A!Ls7m!Ru#jkYhTe;Zm4("9GT;!Mfj#"9H1=#D3&Y!MjL=CL@:o"7lPpS-/@je8GHj;Zm4($nMIIMZLFo!L+9!!lQW@o)ZI-!L+9&"9\qI/-4s5"9^Rb"9GQ."BYe+ErgpsN!'0W!K;(#:YQ$5":2Y:MugZr.Dl8h"9Fa+"<df!!JEW-b5m7r!JCK:!JCKiP["6q;uqXQMdQ[oDZiH2"9\ai"9Flg,Tp"g/-Hgn"63So!Lt\\;Zm4K!sAaU!MfbG"9H1==9JZ+ZN7-1".N[!",d30U][)o?ig-*!NZBm]3kZo"9G"p"9I"j"?o`e/4NP@!P;PEPS=@t!L,,9%\t?QVGdU#;Zm4(]G'?9#/jaMz^)$bL"9\e+MuqX1"BYd-]`\@h!JCRVK4"`WUB-;W#-2,5Zu6(p;Zm4(1n+PsC]FUf_/)?R"G:LkC]TbW?im)cDZhU!;Zm5FItIlK"9`O["?\qJ">g6`df]]b!Np64*K+s%S2pkm[VQ3M"9\i.":-\["9`O5"9_e)e,cLHW!BCB";Hdq$j!X:85fWo85fWo%T<K5Wr\Ff!K7-^PQY(k?jDkr!K7-(b?tR=MZJb=#KpKZZu6(p;Zm4(;Zm5P.#S3u"9`O['EOP!Zih6L]3>sY>9"U`C)dXL;Zm4+"9\at"9G,n!NQ6c"9FGa!L*^hMdQdRgB!69"2eLIZu6(p;Zm4(!!!!_#QOi)"9PTh*'dF*,QXDd/0k?41aE2L"B$cj";q=fo331K$nMF<"AZ"%":e?5gb)M.64JSL!!!_oz!ihOk0N/)W(&SsI1_m*&B]E;*"FC7sE"@R(,Qo),2$>0M)$Co^>8/=c'J'@`"9H,=!#AK9zWmVmf;Zm4)"9\eQ]E,68"BYd-Wr^-A"9\i._u\p$?j"RQ!PAGsP@+L9b5pZ+"-[,'!V6?Q]E@b5?j-'%!NZF!!N$4b"9\bd"9IFZ!e=2P$N(2-";\(!"9G>U4<t%T"B%&rE)QlB>6X(U6p+)2"?Z^T"9^;51iNrJ4<t%T"B%&r&i:rA,Qnei,QoA\,QoYl^aoUf">hq9"9]tq"9`C:]E3mf"BYd-j9#Mf!Q5*A_up+A?if!_!TX=B#.%\V!J:EcX9#Y8V?krX"9IQa!N8p"";q=n2I?XB;Zm4C;Zm45;Zm4==9NG`X)nIIS-/rq"CuQSCi]WQS/MM5oI&r*S,pG5!K,n<!N?*i$)@U?[!)Y+U`Jb+!M!U+!LsJ7bQHX5PQc.0S20sNS,pG,F9L>!!Ls1T?ibmr"C)1q"9G<:!KL(]1aE2T>6359lm)e)49:rT!T!q^!PAH!"9_g0!NQ7>,6>^c]E?>b?j=LL!NZ@W!N#qZ"9\bd!!$V0z!iiCBpeq:u=9MS(!JCRY"9G$6A9.d1ErhL."9H__dfGCa!!/$q$)@T\ZiRoEKP^Mf!JCFR!JE=_!JCKiPZ.h`;uqXQ"cHb%P]$[m;Zm4(S.(Wa"4Rei=9JZ+!sA`0!MfbG"9H1=!V6?AU]mN$?ig-*!MfmoMdQS_qZ3c$"H-Xl?m>]R!Ls1[!Ru#j%T<K5!)j"'";q=f6X(NE!K*o\";E,#"=,ND"9SKH":.p/*!fIG"9_UR!.IiLzX3r'i;Zm4)"9]%h*%V5."9IOe"9]`%!LQdg\5NM5HN["J;Zm4+"9\eQ"9G/o"cuXcj'*KsE`</B"B5iS'O1bB"AOeYbViB&"BYd-oE,4!Wr_hn#/agQ!W)oAbQbsm?j+XR!PCk5!VC:5aAW3E;Zm4*"9]"?1^8b749P]g#GYK;"FC8&aAW3E;Zm41e-#r*"9GP(=9JZKUB/jI&&VcYB&`p9]EZPeoPXj5;Zm4('Kc]C/.;>Z,QrGs/1`%L49RMED7a!dHO%bGirfYC/8tWEE&PlB-c6'D"=QBOj=C=h!$(>0U]_%C!N^>CEri?F%>4k#!Mfb2Lf4EZ(Bc8m"9\hJ"9]35"9Flg#G=uu<[7n5"9\r+,Q[%+/-Hgn!TRB("<B<%"9J]_[o3D4!sA`-!Q5$2"9H1==9JZKWr_hq6b?_1!W)o9oL$5udpO*qWr^Fo#,>QADZg*R"9\btP6(/O>S$pp;Zm4k"9\at#1Q[P!TQur"<CGE"9J^*Md$m#HN["C;Zm4+85;P_"9\h%"9Isi!NQ7N"9H^L!Rq6S_dESIirR@S0CrR5DZg*R"9\bt"9X`a4ECP!E!;F.MZa'^!OQfP+T\AA;Zm4+!R(])_us0F!PJU:!sA`0!V?EbRpZECb5oNb"e/m("KMRI!PDWE!VC:5pJV1tlN@=k/-Ol3/-L;&!TRB("<B<%"9J]_lWY&c;Zm4*"9\hZ"9ICY/:LM#j')Q6*Adm"!X(=_;Zm4+;Zm4^e-#lW"9GP(=9JZKqZ51L"G:(_!W)oAbQNQ+?ji_1!PEIM!VC:5Qr=+j"9HFB"9\b=!NQ7N"9H^L!Rq6SX'bu*qZ4VL'WYUB!W)oI`!4t(?ig-*bQ3=U?jD;b!PANP!VC:5/lMlU!Mg(g])e]-_#^>eo)YWf!L.C2drYVd"f#ITZu6(X;Zm4(j?*LAItLr5"FC8&!J-F;"9]uh"9H#2"9GQN"BYeK!PJVP!Mfi$X9;LD1e_rkZuA""Zj6L0X9$'B^B=Z?MZKUS!!/ldFIN<,!Pnf4&+]gtU]H^-UbJPEZN730!MfaPRnEdX!MjCM"9\b6"Kt`,``!!C;Zm4*!R(W."9_g0!NQ7N9**NFbXqD6?j*e:!PATB!VC:5[Sm;3!OcbG"9]uT/-E(S"9a&S[mj:!Ue1ak;Zm4(*)$G-"9IOe<!44@>Qb*2JWj:P;Zm4(HN["B;Zm4+*%V2X_u\n&"@t?S"9J]_dp!MKHNYl';Zm4+>9#0o1^!j>">g6%'KcL"">d)_!PVJ8j'*KS*Adm"!X(=_>801&"=sSc&!R3Dj')f%%($-<">g6%"9\i/"9P/n,]G<`T2Pjq!#u"@z!ijQdn5BGm)$D2dIhXF:"<7O@$p6?l">Z`V!mjjK8d#6p"9\aY"9G`*S8^7L;Zm4-"9\bp"9I9[!NQ76"9Gk4!Sdf[94.qH!W)o1Zj4c^?io'`!MfkY!ShSrE)QlB7T0EmErgps<pKm1"9FI#P]-fT!Ls8n"9\b%KE7)Y;Zm4.!OMoqZijJ6?j?K/!ON'SCL@=(DZg*:"9\b\"9]Q?"9`@9"9GH"!LQdg"BYe+Ergps=6fuG"9FI#!P]*1!JCK,!QY:pKMD`@"9Gq3Q;[nh"9Gk1"9\j0g]?14?id;/!OMsH_dE]GUB._(Ug%41gi!;r;Zm4(;Zm4]HNYm%?@r@`,R1Vp/1_kG"9^Rb!R=UH=9JZ3!sA`0!Sd_2P@+L),6>.PU]T:Ygi!;r;Zm4(;Zm45KK..UKE8miKO'cB!JCFRKE6tRKE8mi<!2^m!JCK<MdRc/DZiH3"9\aq]E/"1"U!6Z!!!Ftz!it#uOAc8b;Zm42">g86lN@?;">i.f4E*HYfM_nU;Zm41"9\s[K*\,K2@Q5];Zm4Kj9,_W"9GP(=9JZ[!sA`0!TX<8]3kZo)Zk[]ge%*F?if!_!R*pC!ebIp5#VRej'*L&*F&^J!X)a2;Zm4+"?Zd:'LW'*1]i;6,QrGs1c-H\g]TJ;"BYd-"OdD,giL)8?nfJ!bQ3TjKPpto;Zm4)"9]!\g]E-2"BYd-",d56g]Z)6?in4H!R+-Y!ebIpcr1&M"9I9["9\j0KE?f/?iu;g!Sd^Vo3b/]"9H^K"9O6p"HZObE)QlBckcgA;Zm4+"M4iQ9O%bJQ;[nh;Zm4(<!^*K%D2_*A0_9lCa9-',Y_5@=&T5)jA[Rd"<7gN";GAl"9`Nd"9uqGb[49OKG0:NM[SSH2?p*O;Zm4KDY".t,ReHF6mN+u9I'`T<$VSd!Pg5h,Qoq\;Zm4K'P%C2<"&S-"9a&S!U!AaE%Rgf;Zm4K">g:t"9\jS"9l#.!e^XYWr_8a!SdeYKEPB[?idS8qZ5b>!pa4pLq<]C"05f1DZg*b"9\dZ"9uY?"HZOb=9JZ[!sA`0j9,O;"9GP(]`\Ac!e^[Wj'VnoUB/jG"RBG!!W)oYg]k)m?j)AgbQ3jdKPpto;Zm4)*!i?0"9IOe49QZe6j*PoJWj:PHNZ/+>9#I&49P]F"?Zf-'LW'*"9FEb";Xo=/-K_k!TRB(*=:d03!9?eU]^_,1^%S!!TRB("<BT-"9J]glWY&kHNZ/-;Zm4+!ilIN9O%Y7OAc8b;Zm4("9\ge"9d@U!T$`X>9!pe49P]F"?Zf-'LW'*1eim4"9a&S"2@b;]`\Ac!SdeYe-&kV?j3;+!Sdb*gL(E$"9H_F"9O6p!JjYWL/S3X;Zm4)"9\eQ"9a3QmK8bRX&_mq;Zm4)!JCQi"9H1==9JY`!PAO<!Q7rY#m$'E"9^gP!PAHJ!PE`JMZLHj_#_2/o)ZK)PQ?FjMugQl?qQ%P"FL?1"9HGZ!q0%jQW""i>9$TC>Qb)f"C)'M'P%=J<!Mqu"9a&SY96aHHWEf@r_iq&mKTEf"=,l-!m":CGZ+_JpJV1t,QpdD^aoV1"B8>$3J/k."=uG@lo%cFE&+0kM?FDW!SfL4e-&kV!PJU:qZ51L%HCgs-IW"Nb]\nPKPpto;Zm4);Zm4n;Zm4f)$D3cV(;`PqZI$&"=.ph!N/j!E+"k4*&J&)"9IOe49QZe6j*PoD7a!dhGXO[(BcPt"9\h@"9R^a1fS.@E)4(KH_U^+!q&Hq1]`I:Dc6cA=9JZ[!sA`0!e^W.P@+Et,6?R#g]<UH?pErX!R,;Z!ebIp[o3D4;Zm4,;Zm5!"oAGk,W5h0r_iq&!#u"Az!ijE`kYhTe;Zm4*"=sZ=/2RJI'EdZ**'>JL1diSlg]U4P;Zt#A+8Z0@"=,73">hq\!OMteX9;W.!PJU:!PAO<]EA89?ig-*!NZE^MdQS_o)Z3$#K'pODZg*:"9\b\ZiTr#"BYd-Wr]j9!PAO9qd9H2,6>.TU]fF[gi!;r;Zm4(;Zm45=9MlJ!sA`0N!'07P=0Hm:L8Yk!T4!C"9Gr!5>q[f*L%Jd"<!FWXADgu!PJU:"9Gk4!NZE+P@+FgRfTku!omYjDZg*:"9\b\6NhU3"9Fa+!JjYW>O)@?"9Fa+X>j,]!PJU:"9Gk4!NZE+K4"`WdfHfZ"hS.HDZg*:"9\b\"9_4n&)7q!S8]%W!K7-^K_klq!!/#ZG,kY&!Pneq!S[X6!L*V<o3;<T"05f3S8SO(;Zm4(8d%p$"9\ai"9I[a"C>"0!M33mpJV1t!!!!"+92BA"9PWS"HZOb#ZCj/aAW3E;Zm4,!Rq4U"9_g0!W3$&Wr^uY!R(ZI"9H1="mZ3=g]`UD?j+pZ!W3"oUL4,'UB/jG"5@2e!W)oAe-"H5lX1q<"9HFA"9JF=":e?5"9G>U">p<=8d#9Y"9\aq/-M&5lNA(.2?iSK;Zm4;)rgt/";Ea"!k;/3o2f)d":=]$!q9+kMus1c=9N.8!L*]i"9F0s4ECOnE!P,#ZNL<)"gi5f+T\)9!Mfi$b62p.!N^5bDumQRo)o*$!PE@Uq$tUOU]I7lU&gbbQ3!KV[K2m!"9\i.S-3e0">k0#Ui8?S^B=Z?"9G"n!L?XeW)Eg%9;;Uj">hrS"9\ibe,fIL"BYd-"LA.,e,u1J?j!G1!Rq4@lX0n&"9HG*"9JF=!PVJ8Io?IQ\5NM5!sA`/!Rq/Jqug+)?iu;f!Rq.f"Og`dDZg*Z"9\c'"9I@X!f0bX7FMP71^hNH"9^Rb*%"Se4>\;d"DAS4">)G55CN_<#.tAg"e5V2&i=^Z,QoA$HNZ/n;Zm4+"9\a[bQ7VD!PJU:"9I!T!R([KP@+Fgo)\al"I!3o8qR/o`!,a?r,2]=;Zm4("9\b(S-2Vd"E\\cUi8B4#GVD&!NZ<YV#dq+,Qn5N!Ls2+5>q[fqu[')"9I!Q!W3(&UL48KdfIr&`(OJ=r,2]=;Zm4(,W#SK4=S0P#4l%E6mMmdK3KTp+ZomF^B=ZB!rb"W"9Gqf(/k>=PR.IDPX2&F!L*Qb!L-(&!L*W$!K78A!L*VL?jH"."B5K("9H/R!N&cu!W=9#C,?&\;Zm4+"9\f*!!A6[zWjE`G;Zm4)"AAjK"9\j0Hj"Nn"9GTFCi]W1Hmf+##D=2b"FL7;FE7J9E(9^-]*&.n!L.O(DumQR,Qn.<!JCKh)?GM=!K+L:bBs;;!Ps/3F9h,Z9RHl*'4:pcS8SNm;Zm4(*!@5]$cF:nK63k$!L+QV%tb!1"9]EX"9]97"9]35";DYN"=,6<"9\ib]EA45"9GP(=9JZ3!sA`0!Sd_2UL4,o,6>F\g]d"O?j4^S!SdkEgL+R8MZLHk!S^ud?kWRJ!Mfq#!ShSrIo?IQ$D\)`!#jWNzX+__t;Zm4)"9\b(j9LJY"BYd-Mus1c)Zks"j9)Gj?j"jY!Rq@4!fV%#W)Eg%"9F/WZigM6"E\\c]Pr#b#GVD&"9IS&bWQ3+^a'$`K)r=[8HH19%bh#k!M0>!-,TbjZiC-6Zj?7(ZiRuDKES%NZiQBlMZJJ3"oD[0b\mW+;Zm4("9\hZZNTJj$kc5V>V@'bA0_9tCa9-//58e@OAc8b;Zm4*"9\eY";F=("9\ae'QA#LkYhTeTEFcf";E`q"><[V/5T7J1c/2P4;9%D"=,5q,QLaG">hA,4E*gVbTm<*1^9`VLoUYV2?Sa9;Zm4;.GFrt*"3H:!Rh(V";Cp-"=-Yd"9_[LqZ4H12?BFS;Zm4;li[@I"9GP(=9JZcUB0]a5O2\\8W*W1e4GR+N,Jh";Zm4)&rZq.!NQCB"9](]j8t8B"BYd-Wr_Pi!fR6_'4:pS!W)oa!TXo%RpZE+"9I!W"9OO#!PVJ8"B%'%T2Pjq;Zm4);Zm4="9I:jj9,Ls"BYd-"OdD,j9*k=?jFjU!Rq1/!fV%#Y#>H+2ZuVP;Zm4[;Zm4G,QoYPDZi0Z]JMQ8"9\i.P6;#('Q=),3)]q_=9JZc"9I9\g]RYk?j+pZ!TX="_dEYCMZMl?"+st`DZg*j"9\dbZiPt]bTm;uV*"kb";Ct>"9_+<"9`+2"9]35"9OMa!NQ7f"9IQd!TXAc_dESaMZShA#ErNt"H*<AN!A$E?j""B!UL$FgL('ZMZMlC"g_S<DZg*j"9\db,Q[U;/-Jj-qZIc>2?TfW;Zm4;"9\eplN=Ro%eKdX1^"4""=++%ZNN*1'Kg=o"@OL<"0YW+zo-XM<"9\e+,Qs3-/6!kt/6jG'"9_Uj!ji%4]`\Ci!fR6_"9_g0!NQ9dqZ;ub#Ff*%#/^LqZj3(.?j""B!ji3%MdQe%UB6AZr&\9eZu6'J;Zm4)"9\hBMup?g"BYd.]`\Ci!e^[Wb?tAJMZU7ICZAe)"g\8hquQ+kZu6'J;Zm4);Zm4'!fR84"9_g0!NQ9dqZ;ub#P2=(!oj?@quP8SZu6'J;Zm4)"EX^,"FMaGB>YE/4>m5MaAW3E"9OM`!e^\Y"9H1=WreLg!gEfgP@+FgqZ;EO!L$ml!m:Y(r!&?mZu6'J;Zm4)"9ON9PQV+k"9GP)!W)q_MueQ=?j59d!W2uA!jlkKi)9a](Bd,,;Zm4g%.jXp*!C%F!P;PE6mMmL9I'`\%T<K5-;t$M``!!CA5VXn">gN"";Gr'"=/@?>QKL'!K89,PU$A_;Zm4(W#_p7"?\RC";k&?!RF[IIT$@P;[iR,"9\atb]FY"oDuc56nCG*g^]QZ49:6K,U<M/p/;(s;Zm4(WrrIU"@R2[DukZF!j`#'">Eeo1dhA%"9]SF"9G>]]3>[h$j;4a/-3@e!P;PEVc*^$;Zm4("9\dl!Mi4a"9H1==9JZ+!Sde\"9F0sHuf>LVC7o:ZiTLoE#FQAj9,MU"9]kKg]>.mgb-bN!SdYU!Sgha!Sd^l!Mft,!Sd^?#*T(hS--Z:oPXj5;Zm4(;Zm5Q"9\gm!!/EbzWphP>;Zm4)*0^W:!Q,VY"?Z__6j*W19EYBm!P;PEaAW3E,Qo(f"AAid/-2Ol!N[OLaAW3E!sA`.]EA;k"9GP)=9J]4"9PY-]EA8K?j2Gi!iuNoRpZ9oMZVZ:"Iid&!W)r*X9>##?ig-+gB,#tZt!JF?ifQp"9PA4"9R@s!pEPcLf4EZ;Zm4+F9CH%"Eo](!Ou&2\5NM5CBObB,Qo(i2$@/h>7=I6WrrI8"C,mrA8kV&E%frK"9[:mZs3Wh"BYd.]`\D<!ji(2dpN:$K*&+V"4LW_"JZ%*U]dH#gi!;s;Zm4);Zm4/":4Wi9EL_0!MgtD!PgMp,QrLB;Zm4s"9\eq"9HM@!q9+k!)j"'=9J]4!sA`0]EA;k"9GP)?qUR.!k\QWb?tAJ)ZndqZiTK#?j>?e!i,p^!o.\sB2\p9Zm5crMZc-C9EDd,I!ep>KN'3"6mMm9%C?.p"9Y/>!J!B;qu[')"9I!QKEME["@R;4Huf@JE'9s!qZHtb!h=32]gND'":iWVP]0<KU^trVlNA@5!e^T/o)aRF_#f9!gB*$/PQC[be,k:(?ibl\!Q5*3!h=03[o3D4;Zm4()l!Gr"@P.E!T$`XH$5*f;Zm4G"9\b>qZI[5"B9=@lQB+/$kdqlN$JNO,Qoq)"9\ai>QWb\!R;Jak#2BcHlqq\"B5dB'EO.<!L+i42H'_]zj<4L'"9\e+,R!m@"EYml6ik(c4<t%tMd%/X*'=7^6jE6eG`u>?BN#$:OAc8b!TX@ag]RYY"BYd-"g\6bj91r[?j3k;!SdgI_dEY;"9H^I"9O6p"40sLE)X@O"9\b<"9br-e-JtU,7h-k"9\hN/-Fg/6iifG!P\a?/MmSm;Zm4+"7QB5!PD#-?W.(1=9JZ[!sA`0!Sda0j'W%cZN>d]#.%\<"1nVfg]ZA>?if!_!Sdh4b?tIR"9H^N"9O6p!g$=`0N/)W=9JY`!sA`0!PAH?is?6c!K#Q,!T!ji!KR8o!O`$A"9].7o)q9V!PEAUVc*^$"9I9Y!Rq6S"9H1="eu+Jg]NaJX'e!i"9H^L"9O6pZm\iU<$VSI>U0G7A0_9tCa9-7%T<K5<$VSd>U0FtA0_:/Ca9-?F<guO!L4WekQF:A9F&K:"N2Pg$:IYT;Zm438V7.q";DPh">hq\"9\ib/-4'q1^"[!]0(!7$kbs*02huV$M8W(Rgtqg_#_2q_Z@CNPQA,rMugQl?j*M2"FL<p"9HGZ"@c;m!L?Xe=9JZ[!sA`0!e^W.K4"bMqZ5IT#1Hr\#Km/'bQ[<?KPpto;Zm4)"9\e/!!#bmz!irF=kYhTeU]R%h)O(:3cr1&MCBObA>9l$.,Wl+f*!6"A"@OL<#.RS7Lf4EZ8/Fr'"9\q`":;#*,[aOR/-Hgn!P;VG]3>[`@abG\"9^Q#<!JF_!TRB0dp!5c>9m`:"=sSc"9Zjn"R&be('G)R1`QVA!JCSR"9_g0!NZA+!V6>n!JEOB_dEYcDZk.d"9\b,"9lS>"kZ`Vo32W6HN[;N;Zm4+";Cn3"9`78ZrC!N%^](?.LZB[$D\4)bAIj_#L#"V/.1/9;urLg&l]p9>7>%A<!5P:"9\iNKEBe)"BYd-#Eo1AKE^[L?jMAc$f#hs!NZ=!-rU6O>9jWI,[:B1/->]Q"Crb\>QMSBa&<*D*WuTH>7>%I"B7)8"9\jSg]<F6lWXc&+]JS+>7=a>>Z<$H"B5Dl"=R1O1hKYh"ATa9"lN;^*$bYd-W:-N&l_6qo*EiFKOfH7"Up%j<!3T)"9\iN$sZ"qN$\@*!J=V\<$%6&"9_[:"9G,n"Mdq==9JYX]``]c"9\i.KE8.V?if!_97-oLX9Gq<?j""A!JCW__dEQ;"f-5M!NZ=![Sm;3;Zm4("9\eA"FNI5KEM=h"BYd-Wr\.^!K7-^X'bu*!W.6JKE\Da!Ku1<F9]or!N#n9"9\b,g]Q2-;[T<0;Zm50,W#ST49=JHKM`'J,QWi2j9^JhD?Gh*liE:0"Ug7r"<7`$"9_+<6p(Lb:V0g>"FC8.j'*cc;Zm4("9\b@6p(Lb=n>i+"FC8.Io?IQE-08+Ef1&_"0Y+31]`I:j'*d.>9mGS/-1po"Crb\HkoW`"9H1==9JYX?sA!]!JCK;qd9NtDZk.c"9\b,"9Xrg".)ph!PJV`"9F/Y_gDSh"QNko"e,OGF909e!N$8&"9\b,49P%N2:Gb<]3?OK,Qo(f<<O"0,m4?=>7;3&";CmK"9^P,"9a3QHi^;N"9H1==9JYX?sA!]!NZIZgL(Da])dQg(9:gHXD\5`;Zm4("9\dlKE8.V"BYd-"j6qJKEd':?io?h"EXdi"9GTB"GThXGuUP4"9\c!"9c24/07^m4.BF_N`-&`!!!!%)ZTj<"9PU:!iT$#@"4Y&,QWjV"9a&S$j!X:";q=^,U<L,oHXPZUbi2\UGN)SBCdKRaT\b&N!,(?!JJ>nL=60m;Zm4(X<*$)S,p_P;Zm4+"B5D`KEME[">"TpDul!B!rN5o!L.OjEX_RC!K7-a$a_a3P^I!$S-@CC",mBj!P\a?!JCK4KOY%AKR8UX!JCFR!JE;q!JCKiPZ.\<;uqXQUL49&DZiH0"9\ai"9]!/"9^tg"9`U@X9$fQ"BYd-!lG&gX9QjU?j+pZ!Ls@H!Ru#j-;t$M:K%B!=9JZ+!sA`0ZigEZ"9GP(]`\A3!OMt1b?tPOMZM<0"3Y'U"1&$0U][r2?ig-*!NZ=.qd9V\X9"gpe,cET;Zm4(!!!"B)ZTj<"9PUF!SC<RfM_nU;Zm4*"C)"Y"9\j0"9F/XS9"^i=3C^I!L*WL^C0**j8k2?-3qa""OmI2!It30!K-use3jS,PR=2h"7.6@!K8Y+o)XdM_#]K\dfGC.PQ?FA>QKcaX'bt7DZi`9"9\ai"9\^']E,68<=$eN"9\kGX9$fQ"BYd-Wr]R1!OMt1MdQS_MZM<1!S^ua?qUO%!LsD4!N$2$"9\bT"9]cE'EOk*`&&_BG7;t'"7-QR4F[J"4p.T3$+pM5]IOBN;D]?s"9GS,"9\j0e,e&$?j2Gh!NZ?l94.eLDZg*2"9\bT/-19"'Eh581aE=%,Qn.T_um)'"funY",$sPga#:;%%KKa.g341"9]'r!MgK0"9H1==9JZ+!OMt4ZigE1?ig-*!MfmO"J]?t?m>]R!Ls@p!Ru#j%T<K5":$ad'I3f<E!N-@;Zm4S"9\bn!!/rqzWp_>9;Zm4)"k*TnMuiiq+T^p2lscFe!UKde!UMW>!UKj'!Q5/b!UKiO#NGitX94Yor,2]=;Zm4(oE5<l"CuQSCi]XT!P\a?"9\btWr_-W!jD]V"9_[^"9j<SoIs2HNuu"=]*RHu$kcf$!h9Po"=.e/"<;M/"9a)tPQRj_"BYd.]`\Cq"9\i."9Q4<!NQ9lqZ;]ZN([OZ?j3;,!h9A9b?tAJqZ;ua"KPo6!W)qW]EG9C?j4^T!gEi*qd9Gg"9O5\"9Q5S!J")O]E89>"9Oeh!k\Y<j'W&6UB6Y_>Phe1DZg,p"9\e=%KVYi!VAtepeq:u"9Oeg"9\j0MupWo!PJU;K*$u7"l!Di"1nWIPQ]0;?j!_:"9O6l"9Q5S!KL(]BN#$:=&T5)=9J\i"9OMbN!'0p?ig-+!gI'0RpZ<8"9O5Z"9Q5S!iT$#!R2$Xj!7"04Bt#O6sLu?,\//',]"_/]ED,;"BYd-Wr^-Ali[Fl!L.X+Erkn9Wri2U%D6Xq!P\a?!V?Eb!NI[9!f$gK!O`%$;Zm4+;Zm4u$%r>g!JD^$N$JNo,QpdA"?Z^L!Ls2jUa-'W<@h)M,Qq@W;Zm4k,QqWX,Qqp_,Qr3O;Zm4K;Zm5@)$EVeV,RR#>U0FQ49<&u])euA/Y`FL"9_,3"9R1R!hN<n:K%B!Erkn9ZO5JE!W6nZ!P\a?"9\bt!!!L-z!iidMW)Eg%"9GS)ZigM6"9GP(!W)o)Zj#c'?ig-*!NZ@o'4:pKDZg*2"9\bT"9_7oU]I,e!PJU:"9GS,!NZE+b?t@WqZ3Jt#KpKU!W)nnX9"eu?j)Ag!Ls>"!Ru#j7T0Em";q=^>8.F7/-H"6Hn5C@e-#mU"<^VRe4rpF;?Ep<"9]+N"9]35*&JI1,R3jE"9a&S$j!X:"BYe#!PJV(F*n)nKEM=7"C-!KN,W[0":N][!JCKgErh4&Wt48J#4-;E!P\a?!JCK4KGjlM^B=Z?*eSh@MgPMP!Ps-h6j(V[9RHl*#0UBfP]$[e;Zm4(*!$)DzWph/3;Zm4)"9\go!SdZRe-&kV!PJU:MZM<1#2<Mg"PWt4bQFnRKPpto;Zm4)">g4j,[:B6/7^"/"Df=d"+X;Q!)j"'ZiPro*"60a'MKbT"B6WL!m":C!LuP/-Mmp649YS$"9a&S!jGT+#Fl+]"B5Do!n^ES!)j"'=9JYX!OMt4"9Fa.6urCAE(>N`"9\bD!PAHJ.Dl5RU]JDQ+T\qS:4ikSZiC-6Zq.M(ZiRuDKEKBuZiQBlRfS0C"2eLL`,>d#;Zm4(!Sda\"9_g0!e^XY"1nVfg]kr0?j)Ag!R(Y@!ebIp7T0EmMd%/`8d')N;Zm4cZ31:?*'=W1Zig20X'5u9S4"n7"9_*n"9H#2,Yq>A_ZUh[,SDXbgKP(K+Y3aPJb'!I">k&u">EaW!Oku1G>eVI!Pgf#,Qp4l;Zm4[;Zm4/!p]lJ1c>B-Io?IQ=9JZ[!TX@d"9\b+!e^XY!ODi\j9C6E?if!_!Sdm3ZX=!T"9H^M"9O6p"D1R89OLd%$*.8=HNM\Z*!X=aU]^KuZP<lVS4"n?$qs%i4;"o(49U!6"8c:BX'6!#;Zm4_#HIlc1c>BD[Sm;3"9I9Y"9\j0e,k:*!PJU:!TX@de-#fQ?if!_qZ5c)e72ke?ig-*!Rq1/qd9I%qZ5IU"oD[."H*<1KETJ+?j4^T!Sdh$RpZE+"9H^L"9O6p!PVJ8zaWUWa"9\e+"9]!/"9]!/!Se/`e-&kV!PJU:!sA`0!Rq1(K4"`Wo)[VM"bU1a",d56g]Q#5?im)(!R(YH!ebIpfM_nU"9I!Q"9\b=!e^XY=9JZ[!TX@dKEM=V?idS8!e^X0j'VtIqZ51L"QNkj"1nVfj9</'?ig-*!Sdjj'4;$VDZg*b"9\dZ"9]iG49T7p'EeH5*(2%T1^$]=UBDG;*&\''^f(@=4FY0K,Ra^T/5.;l<-J]!>U0FdA0_:7!PgMp,Qp4l;Zm4;!sAaN"FL6GX98Z.KQM89E'iRgMZaBo!PE@P3<>$@,Qn.d!NZ=;!N[fpdfHOAScPp;_Z?h>!!0/CB?L=W!Pnf<!Rh(N!L*V\]6jX\CeJ.?!Q8mZ``!!Ce.MTZ"T1@o4<t%d]-7YOS4"V(49S%Q!n7?)!Ur@,,QnfD;EPpe!!!!%.f]PL"9P[!$]n9i>U0G_Lf4EZ>9ka1dkh*;U]Hf>>9l<;"9\nW":O-d!n7;T=9J],lN5Q=J;[e:irZ:_CZAf<DZg-3"9\eU$jD/[Hi\g%&q!Th,Qpeg"B5D\"9F`4$HQ-Ke,ogV"9PA#X98R;"BYd.",d61U]T:Y?ig-+!iuIXo3bDd"9P)@"9R(k%+%oU=9J],,6FqLX9XAcdpPfM"9P),"9R(kbT9[c/0L\s;Zm5.#LEpI>QK]b=9J],"9PA%U]^_3?if!`!iuX5#I@e_"NpkJS1q!Oe8GHk;Zm4)"9\e1A.7Bp!J1@59KnY6"@Por"?]p7">"(/">jp?"9`fl"9R4S/0kcX!P;P]QW`o:"9],6"9`@9X:2=3"BYd.]`\D4!i,r"lX0s]irZ<*Atr`CDZg-3"9\eU`!5^0XphBM"9G;!"@uGo"K56%=9J],!sA`0!n7;$P@+R;gB+Hm+IcaCDZg-3"9\eU/-2YI%/:VAOAc8b"9PY+ZigM6"9GP)!W)r*!K=?m#0R(L!K=?m>f-WES-Qr>e8GHk;Zm4)"9]+*":3pa/-K_k!P;P]1aE2<!)j"'&Xs5g"2"Z$!Lu7\HNYl^DZhTo;Zm4kKHpTM!LtD=Ua-(b,QnMV"9\b,"9^\_/2TOh"ADKh"B7c7"C*K'"9^h4":DA3"jg0NHmp='*$bZ7,Qn.$"9FH\CthW/"<9<""NXLEYYtZ-,Qr2j,QrKW"9F0,":R+4qcj/R>S:9JCa9-OF<gu7HmAhgKHp\",QnMV49P\D>[.<F"@OL<O9+DF!P;#1<"&eo!LEi!"T&<1Rflu8"CuHUCiCc>N`-&`M^1Cd49a17!rH1a6mMmD!P\a?HNYl^Kpr2J">"Km#M;rXWrfX2!iuM*U]ad&!PJU;qZ=,-"bU1`?m>`K!iuQXgL(67"9P(r"9R(k!nL9QQVEB#MaR[K"9FiY!KN(3"9\al"Mdq=Q;[nh;Zm4)"9\g^MZa/u"C,n?"o)"!HmAi",RDmF"AAiL"9FH,A-'J&%T<K5!)j"'5Z7dgDANF\B2\p9Y#>H+<BO4`,Qq@W$I!$S"Dh$V"9_+<"9[7S!NQ:/"9PY-!ji)4]3k[:dfQTY$_q)CDZg-3"9\eUA-@E]!P;P]>9jWaChs:($t>u9"EYmlC]V9RF<gu_"FC8^QW""i;Zm4)";CmO*!?B^,Qn.E/-1J.QN?+t"9\i.">g.2!q0%j"4.17"9_sf"9`C:"9X`aXC+s0"BYd.WrfX2!ji(2_dENB;Za$$S->s$e8GHk;Zm4)4?Nc0$j!tE'LX2L"?]Ze"=ti%$j!X:[Sm;3!sA`/!Q5$*UBF[%Xo\/V"?aR&FE7K\E#u=gUBCXO"B9=FP]-l&^a'$aoE"jj)?Ka:8tuFZoDepaoLe]UoDuc/!UN_c!V?DWA,?;F!Jn?qDZg*J"9\dj"9ZtK"9)4%<^[(n"9`t]X9@-R"BYd.e,ogV!ji(3e-#fQ?j""B!ji9'RpZ9oMZTsd'oQH'B&`roS-7#Ce8GHk;Zm4),\-ts9EDb0<,<f_A99(""9a&S!WH"#el)\SJclJ_E._[%<+HVP"EYml"j^*Me,ogV"9PY+!n7?TX'c1EirZ:tB&d8(DZg-3"9\eUZN\?I>W+hLY#>H+!sA`/!iuIQe-&kV?iu;g!j"MbdpQ>E"9P(t"9R(k#OYLnQ;[nhY6<kd"C*hf#-Ur.!K,n?MZbkU49<->M?F'bg^G_7liD\=9Foke"=-YR":SN\9E\lO"9]uEA-UXa9Je!t$reGS>QKEZ&mSAI,Qor/,QoB/,Qq(g,Qpeg":P<a6ii5l!L+i4S0S4g,Qp41"9\b$RfrF`>QaG4;Zm4k#m(4s!!!!&[i,5H"9\e+"<8gge0G/7!TRAmE'gl6>9#IN"9^?0"9`sJ"9\^')iS`7!OrPk"B6&aKEME[!N^>CErh4&oEVa>KE8:XKON%)!JF#F!JGXF!JCKi!JD/>UB-#J!JCK)!JCKiPZ.[Q;uqXQ6o/3q!K:q"%T<K5J5ZRR"9G;!"9\j0"9H^K!NQ7&"9G"qX98R;941Bn!W)o!S-P6c?ig-*!R(e4P@+F_b5nCD"H-XmDZg**"9\bL";DtW";EsD":p_s"=,8r":PS>"AVku!R(WK=9JZ#MZM$)#KpLu"cEDWPQLGab\mUb;Zm4(!!!"+*WQ0?"9PUE!LQdgQr=+j"9HFA"9\j0"9Iik!NQ7F'*7G&bQ>sqgL)6,dfIAk#30(n#daW>!UKiaQr=+j!R(ZJ_up+A"BYd-]`\AK!PAO9X'bu*lN+p.#.n7H!W)o1bQb[e?ig-*,6>^jZj#c'lu*"-;Zm4(;Zm45=9NG@!sA`0S-/kW!Mjc;Eri'>#dXY="9GTC!P\`L"Jc'oDul-^!Mfkj"<df9Eri'>Rf_)E!N^Yg$g[r]"9e&pU]J45]E+N'$C"Bp70;gd&*s=e!PT)G$a^2p!KmJZ$iC1`!M]\F"fqk)g][rTS7\f3!Ls,j!Lsgu!Ls2,PQ@"iC]U%,X'c%YDZj;I"9\b,"9]!/":,%F//D.e'Egu1]3>]&#c&F@S.>0g1b&n@D?L<J$B,"tg]\"c,Qn5X,Qn5q,Qo)<,QoAL,QoY\,QnfL;D]pubT,sP"b^A,z`uY3\"9\e+A-.9["9_g0!K7*`ErhL.S-/kW!M"33!Km6^"9G<;lu5hf%.jZ2ZNLCS"@R3F!Q5#'PS(e9!L*Qb!L+;I!L*W$!K7/f!L*VLP@/HBDZj#?"9\b,/-56=,Qntf]1<!Z;Zm4-"=+#pMZbj^'Kg>$"@OL<!ME?oliR@n!R(ZI_up+A"BYd-"mZ3-liGjK?j2Ghb5ogk"H-Xi#O;E/`!4Cm?j$!$!OMrm!UO_-Lf4EZ!sA`-!Q5$*"9_g0!NQ7FWr_Pi!m=sc"eu+:bQ>sq?jD;b!Q5&_,@C`QDZg*J"9\bl]E*ac[0YOp,RKD1"9_UZ"B\S*1`''n(?8U-#LihP":VAM,]GEk&5r]7%T<K5^/G.;,Qo@n6Akt''KcE@,X`m\1^$]5"T)C3!Lttd6B_Nd"9]uh!!/ZizWg!Vd;Zm4)oGjY4oDs^J;Zm4(Jcl2V24G!T$k*aW*!(Wo!)j"'"FC7[!O;h2&Hr4EzWpCc,;Zm4)"9\gg"9[jd"SbmuLf4EZ;EQ3.^i>88">i"=!f0bX(fLP?*`E1E8d#0^"9\b$!Q5aP"9_g0!UKmk=b?bA_uoU=?j"jY!OMuf!UO_-i)9a];Zm4(!Q5-1"9_g0!NQ7FqZ4nD#KpKU"/>n8Zio,klu*"-;Zm4(";Cp)"<8C,ZNNB96uW0b9I'`l-;t$M!P\a?Dt=""S,`S[!Kant!Pnf,>PeGk!L*VLqeQ;'!n1O]DZgN."9\b,PT103"?[q5"9G>e9I'`l"B%?-,[hZD4<t%LE)<;4,QoYd;EQ3u=9NFC!sA`0S-/kWUeGh17OljfU`aHZ"9\`+1e(CHMZan#1c?sUn5BGm;Zm4(U]^^K"C-!KXBfrF^B=ZA":i'Fb:ccs2?CiM;Zm4[&_mDIUal_X;Zm46!Q5#)"9_g0!UKmk]`\AK!PAO9K4"`W)Zf:-_ukX"?sEL/!OMs0!UO_-^f(@="9HFA!PAP;"9H1="3U_`]ES1??j5Qk!Q5#.K4"o,"9Gk8"9Ik-/5B+H!P;PE4<t%L!K48e$N*;2=968AE,s,)"9\b$"9Iph!QJ%@=9JZC!sA`0!Q5$*dpN@FMZN/F!RkEY#O;E/_ucE9?jMAc!ON!Y!UO_-[o3D4,QoY"1HZpV;Zm4+"9\al!!#2]z!iipS0N/)W=9JZ;gB"qi#.n7D?kWRR!NZC@!T\/%Qr=+jj9jZC!TY+,#ZCj/\5NM5!sA`-!PAHoZijJ6!PJU:!Q5*Dj9,La?ifj"!Q5&7UL4-"UB/:7#30(p!W)o1j9FXP?iu;f!OMlsRpZ9oMZLHk"H-XjDZg*B"9\bd"9_1m"9\^'">gTe"=s[5"=sZn,RD=6"7.99E%dsh>80b!+Zolp;Zm4+=9N/R!L*]iliE&d,sp&]"9\aq!L*W"Erhd6?i't2"9G<;!Or96!L*VTP[a`aPYCBD!L*Qb!L/#e!L*W$!L.+&o4.ld#0UBUUi-B8;Zm4(e-#f\!rOVQE,;i`,Qo),;Zm4[!!!&>z!ikH*GZ+_Jdp!eKOu,!!,Qa/1"H4T/]3>\3HNZ/+;Zm4+"9\b8_u]3,"BYd-]`\AK!Q5*Ao3_`sdfI)b"nQ+)"1nU#`!,a??ic_t!ON%-!UO_-Qr=+j;Zm4()Tr2T,Rb;B*(2%T/5.;l"B6WL"/&QqD:8]r":a.**+2\J,Qntf!P;PEE!,,';Zm4SMOO^X/-KSd#ZCj/5#VRe%T<K5kYhTe@tOmb"9G<;"@,lg",KkYUe1bD;Zm4(oGakb$1)75lWXcSS2:pFb60'k/8tWN5Z7dgE+@W*S-/ko_ZV+`!!/U1MR*>R_#^&,Wr\^kPQ@!QC]U%,CL@7^XD\5H;Zm4("9\bF"9J9r!PhV:]`\AKbQJ%L"9GP(=9JZClN,34"+std#O;E/]EPWL?ig-*!Q5/JZX<m!"9Gk3"9Ik-"BSM)!NQ7F"9H.<"9\b=!UKmk=9JZC])h7$"l!De"eu+2bQZa/?ig-*!Q5/rdpN42b5pr4`(OJA?j=4D!ON#g!UO_-k#2Bc^aoTh#P9hR/1V"M0N/)W"BYeCPQM$k!Ls8n!Mh8f!LcgEV?)F`[K<6+"9\i.^&bZ@McMA1;Zm4+"Jc*RPQBbH,Qnel/MmSm>9#I&$p4ci'Nj*o49:s7">)G5!O;h2!!!!-+TMKB"9PWa"1V8485fWoOAc8b%BBU9Wrt7u49<rRE&+0kM?F\_"=,f)$nMO*!P8B>PU((g"9^7Vg]j]U"BYd-]`\Ac!Rq5Q"Nt1WGe4"3bQFnRKPpto;Zm4),\.+0<+3sS"9a&SU_Zl36k.?B!SeaG"9_g0!e^XY!W)oQKEQp8?j>ou!Sdg1b?tCH"9H^O"9O6p"B\S*"L(f-?nV$rq]p"$@EW&((/k>=j'*d.,QoY!"LME="9\i/"9FN]!JaSVQr=+j;Zm4(";CpI]j+M^"j@es!P\a?,Qq(G;Zm4S;Zm5*j9,P2"9GP(=9JZ[qZ5a\!LmHtCZ>HNbQ>[iKPpto;Zm4)">g2,"9R3l!JaSV!VdPE"9_D'"9I+Q";Xo="IN*j"D\,CDukk"",n3>/.AU*"9^Rb"?o`ehZ9b\!sA`-"FL6GX98Z.!JGLpEriWN"d9'Og]>',E%o`EX98RB!PBQ]!P\a?MSfIr_#^V<Wr]:&!!00.3i`:_!Pnf<#D3&Y!L*V\o6^S?!n1O1`,>cp;Zm4("RH0Y!TRB0>U0G'"9J^2b?H6&HN[;a;Zm4+;Zm4=9GR\a"<"gP":e?5!e^XY=9JZ[)ZkZqg]ZA>?indX!R(Yp!ebIp+B&CG<_NSW"9a"6"9`(1"9S!i!gcgg<_NS`;Zm4RH'89k9O%Z!^Jb7<!TX@bg]RYY"BYd-!W)oYg]ZYF?jD;b!Sdh<94.daDZg*b"9\dZ/-DJB!P;PEPU'\\$nNq1"9H,="<LJEK+Lra>S[@%;Zm4s!Rq1Z"9H1=Wr_8a!SdeYg]U^^?ig-*!TXBaX'c##qZ51L#P2=(!lG&ob]pa-KPpto;Zm4)"9\bgg]E-2"BYd-"j6t#KEfV-MdR2"K)sa1!RkEWDZg*b"9\dZ!!DXfzX1fq];Zm4)"9\q=":1r)"=-]@"HZOb!K.@cDM%u%;ur3tE*;c8,PqUCgB:c#OCW;`!K%!`;Zm5&!OMmC"9_g0!NQ76!TX@dli]^t!JGLpE+5RF"9\bt$hOJ>!J'bE"9J.6"<dg,!TY`rqZ5aX_#`Up_ZAg!PQAENZiT4g?ul,F!Mg:e!VC:5W)Eg%CBObG;Zm4+"fha`1gC?CW)Eg%$M@@(LQ_jSPR6[WPuL]`P6>P.!L+9"3jSrg"9^Q#P6fN6>QNIZ;Zm4["9]"/oEXSY:C6q#7FN<R"AC]R".3!i/Q<2?>7=I6LQ_bN!L+9!>7=J1"9\b;"9G/o!NQ9d!sA`0!fR2fPQY(k?ig-+!jkS;_dESYK*%!(9#G$@6A#>ur!&?mZu6'J;Zm4)!fRB"KEPB[!PJU;!gEfjPQV#f?ig-+!e^r>MdQdB])mp!!omZ9DZg+="9\e5"9br-<)6Eq1aE6XfM_nU'EXI&"B5Dd1iRK!^f(@=;Zm4-">g/#"B8>G)<1iW$j!#CKHp\:%tko''EO.<!L+i4S0S4_^bc/p"9`fI"9[jd!Us"j=9J\a!gEfjPQV#f?j!G2!fR<[]3kiD!W2tZ!jlkKmSa5k;Zm4("=+&p*)lsNA6^A_"DA52!P\a?;Zm5.Zr@+P"EtXc!Us"j:f@K"i)9a]!sA`-!fR2fN!*5c?j<Y5!ji'9ZX<h*b6#$Q#D6Cf:@eOG!JmdaDZg+="9\e5"9OrhN)*@T"BYd.?m>`3!fRYrqd9f,"9JF)"9PrK!q9+kWreLg!fR6_"9_g0!ji%4!ODj7PR![c?ig-+!fR8OX'c0j"9JE*"9PrK!r#Ur]`\Ci!fR6_KEPB[?ig-+!fR?4=mKH/DZg+="9\e5"9HeHN'C5D"BYd.WreLg"9\i.Zi[T:?j""B!gErMj'VobdfPJDD>R]DDZg+="9\e5!hL`;"A;cP!g$=`&la:S,Qp4d,Qnfl;Zm5>;Zm4=,Qr3q^.Y4p"AC]T"KkZ+,n@:M"=+2A1^&1O"B5E;!j5H)F<gu'!Pg5h,Qq(G;Zm4[;Zm5(Mu*Xt$kcM?#)!NB">jX7"9`Nd1iQ5h":(Ds6k3,u"9]SF!MogU4/2o]"9^Q#"9P/n"Rf7lWreLg!fR6_PQY(k?ig-+!fR>i1LL:EDZg+="9\e5"9aHX!LH^fpJV1t<\t'`"9\tqRfVAE>Qolf;Zm4[LslCF$kcM?A0_9lCa9-?Vc*^$!!!!#"onW'"9PTfX9_`-`>tH`"<3R+'ED&7*!@,^"8c::qcaa[>7<%f*!(VS"9a&S$j!X:zWYb^9"9\e+"9I^b!PAL;=9JYh!Ls8q]EA89?ul,F!PANP'4:k<#(lrHPQeC$?idS7!JCK[!PE=R5Z7dg";q=^,U<L4lWXcK^B=Zi"=,5n"RHgJ,U=W<"9^Rb":e?5X9_`-%g/=2"?[Le6j*P(qZL"(".TCML8+dPFDL1C]6")0FE)CNF9.0'qfDkT!L,\N?s?$@">g5("9a*j"9_b(!!%4Az!ijE_n5BGm,R^XT%?(].">hA,,Qo89";E*a!l._;J5ZRR"9GS+"9\j0X9$fQ?j!_9!Rq4@o3_ZYZN7-/!qTe%"7lPpS-I_Ue8GHj;Zm4(U]^ad'EeFA*%W?<9E\6="9H1="BYe+Ergps;k!np%$UeD!P\a?N!'07"C-!KDukXX"9\ai!fR/p!K7&4o)XL__#]3DlN)Y>!!.a/J,98"!Pnei9M5D>!JCK<P@,V7DZiH/"9\ai"<7nM"j7#d"<9=E"Ai#"!NQ7."9GS,!Mfj#"9H1="OdCIZj;:l?ig-*qZ3L."-[*n"hOf:S-%_Ye8GHj;Zm4(;Zm59;Zm4];Zm4'oEU==bQ4UW;Zm47"OmI<,]F$i,R)C+,Qnf4,QWQT!NZE%"9_g0!Rq2SWr]R1!Rq5Qqd<-fdfHf[#5_d2#)`M`S,qAPe8GHj;Zm4(;Zm5P!!!&Wz!iiUH\5NM5e/Eu@&B&u./0k?D1aE2<"BR,o3)]q_";q=fE#FQ:,Qo)$K)5[%">k&u/-3Kg,U<LD(/k>==9JZ+!sA`0!Rq/"RpZ>fqZ3c!"1qqF!ODg.X9FMi?j!_9!Rq=SX'c$f'*50=S->Zqe8GHj;Zm4(;Zm47;Zm4U!sA`C=9MTN!JCRYK*3`H'EO(mE(5`gKEM=?"9]kK1ii\VE-o2""9])0!K7&o!K7&4])dS+!!.ag0r#22!Pnei#D3&1KE7<b"f##t6j(>7!L.L*2H'_]zTcF+5"9\e,]E5lI"BYd-Wr^-A!Q5*Aj'VobqZ4>5"litp#0R%[X9+l!jDP/%;Zm4(;Zm4/%"&,44;b\7oHXa5!W*!+"9FI#P]-[#!W*!#"9G$3Ui6A3^aoThKE6`,<+1.Tcr1&M!K+bsF>a6J=Ao>*2BPGi>7>n$Hn5?*";FgDZNPY$!JGD1!P\a?,QrLB;Zm4k;Zm4/"C))^"9_dBHifs>!jc)>6t(IBLf4EZ"9Gk2]EA8K"BYd-!W)o1Zio]&?j=dT!PAR$dpNBl"9GS."9IS%"E.3A"@lAn!K^4_Wr^-A!PAO9ZijJ6!PJU:dfHfY#NK1p!W)o9]EdJ)!K*?I!JmdaDZg*B"9\bd(^.?I!Lm+`OAc8bHi\m&"B5EJ!S:6Q!Jgs'"AAj7!U*Gb%T<K5!Ub2r"9`g)"9_1m"9O*P!TX=c=9JZ;dfJM4"LDJ;&E<f(X9F5ajDP/%;Zm4("9\kK"AAr6"@QK?"<:qt">"@7>V'tBWrrQ'*)(<T"DA/(cVjrL;Zm4(5+;T@"EZO]!Oku1>6F4k"=+*H$tNTg<%m!1"9a&S9Q2V:QW""i;Zm4)1fOLC"9Ock>U0^4]3>\S;Zm4(HN[:JMn9)p"AEb8!nU?R]`\AC"9\i."9IQc!NQ7>"9H.<!TXAcb?tLsMZL1V8]tKE?m>]j!PD"IK4"cH"9GS)"9IS%"@,lg"CP.2!o?iYWr^-A!PAO9_us0Fb?uOqRfU/h"nQ+'DZg*B"9\bd'EbO;>Z;sO</Xrh!P\a?,Qq(G;Zm4S"9H/[_up3F"9GP("eu+:]EbKF?kfXB!NZLk!T\/%cr1&M"9RWb":Mj["9G;tPVcju"9_[)"9]!/*!>>%!P;PE]3>[p#Q"W)"9_D;'Eaq*>Z;sO8V:4U!P\a?#F'U8!P8BRE'B`o:\+]oMZdR0mVHi_!K%!\ZkMM*"2nLH>7#t1"?^X]"9F0$N,Sgp&&SMN"9Fa+S8\N+6Gip,"9G<;KE8k>;Zm4(#I=N89O%_0a&<*D!!!!"(]XO9"9PX-"gCo.Qr=+j%I?1Y">"@7<&A\B"9\j*"9m^^"NXLEWr\^n!L*]fPQY(k?j3;+!Lt%>]3k[:_Z>u>7Cur"DZg)o"9\b<]EjTt,QY7UV-F.&">g5^"9`6\/-=I&,WoKl"B6WL>]:s`A0_:7Ca9-GF<gu?fM_nU<(iDZ/-r$a"Crb\"9]lI#OkXpcr1&M,Qoq+!R)&GUiuq=`!`XI4D]KXe33uibRKdE#L"\$F<gu?"B&2U=9JYh!Ls8qN!'0^!PJU:!sA`0!PAHG_dEVRb5mh`1W*T)"1nTHN!lCg?j+pZ!Ls@PMdQS_HNB?8KEJ8_V?><K"9H.9!U*Gb%tk/Z,]'ek"B6WL>]:G<n5BGm"9F_i!K7.`"9H1=Wr\^n!K7-^o3_URWr\^m"7on&8b2tIKGLUr]PdoR;Zm4("?ZdB">"@7<&A\B!L*^b"9_g0!NQ6k"9FGaS-/l+?ig-*dfGD#!Q/:J#3u;SKEpOF]PdoR;Zm4(Em"N7"AC^s",KkY"IN$_"9_CV"=uH0<&A\B1#iC7"AC^,6nVC@">hA,P]ft."BYd-#/^J+PQgql?il5e!JD`!!PE=Rp/;(s;Zm4(#h/mq23V5Q$,d%THj\qY<.>FK4p[AubQJ(@"T0b[E#%C9,Qor/,Qp5?,QoZ7;H,Jp;Zm4+"9\g_49GO]/8QR71isuG"9_V%9MeXjgB8As2@onL;Zm4s"7-'V!R=UH5#VRe(;'^%)T2ZRN`-&`^a'$b"B8>$"9]tqS/c]N$&g,=%.""bKF,kHIflbY#i$\)1^`#%PUd($(#oE"">jA&"9`6\"9]K=49;?Y49:s/$_.=KX96[jIf\%'#IGaUj:C$0.gaE#irfCq1gFu7"Crb\!WQ($QW""i;H,ITpOC?h"AC]U!iJs"&l^9;U^tBP!fV=,Ifp5!"cO^;PRF!F.gk&?,Qp4L;Zm5>=+^PR%+JH^:K%B!2@*ZR;Zm4s9Z$nO"AC]`!L?Xe=9JYh"9FGaPQV$#Rp[HAqZ2WX0CrQP"HrkNKE\Da]PdoR;Zm4("B5JY*%V,j`-2IAr!.l^,ZK7&PWf/UKFOFT"N2etE#%C9,Qor/,Qp5?;Zm5>!!!/az!ii[KaAW3E!sA`.]EA8j"9GP(=9JZ3qZ4&,"cHam#5\G6Ziu@q?j"RQ!Sdq''4:p#?o%hj!MfmO!ShSrfM_nU)$D2c>8/Uk1^!j>">g6%,Wl22"60Eg"FC8&E*B:F;Zm4C"9\au"9_M!"B9aNKEME["@R;3P]Hka*n(5m!L*WDE!,,'N!'0O"9]kKA9.d9Erhd6^B=[U"9F_fS8][9^a'$`P6$=;!!e0?$/5s&!Pnei#5\FSKE7<b"3XXE6is,k%^^-WSl5ap;Zm4("<7H7"=u)L!Rq60PR.te;Zm4:!#u"Lz!itN43)]q_YYtZ-;Zm4(!PAHK"9_g0KQ@1\dfK(A!La%A#LH32!Mohh"9]#."9n!f"HZOb5Z7dg=9J\a!gEfjN!'0^b?uOrqZ<!L6d&jA&E<hNr*Ro\Zu6'J;Zm4)"9\t^M[8NF&cmY*,Qnei"C(tl"9G#<#OkXp!Vc_k"9^hF"9Rdc"5$NT$K-0@"9^hF":1r)!ji%4=9J\alN4Er!V9\%Egm,h!W5Su!jlkKYYtZ-"9OMhPQV+k"9GP)!W)q_N"<g6?iop$!W3#b!jlkKO&H/a;Zm4(;Zm4E!K7AIgH6_aF>b4,N`-&`;Zm4("U&X#V/uhC"=sZV"DiH2"9F0$Hiu$K!P;PE>QK`R"FL67"9G?HLf4EZ^]s*0"?\RF$2@F%HNXA&0A?U4"9^i+K)qTC&cmY),Qq?\"=+#449:rt#D=?*#ZCj/Qr=+j^aoTkKE6`,4<t%1G>eVIOAc8b;Zm4+P.Lh[&cmXd,QpdL'EeH$!JCS!"AC'D"@#ff!ji%4=9J\aqZ;]Z+5:0-?kWUKdfPJL#0UBVDZg+="9\e5(':[<#.mnuVc*^$;Zm4("9\ae"9QSA"OL'M!P\a?CRY@kli7(Q!K?=F!Png'"PWtD!L*Vt!PAI"o3_Zq"9GS,"9J.5!hWBo=9J\a"9O5ZKEM=h?if!`!fVDgP@+X]b6!WJ-bEajDZg+="9\e5b61R=!VC=]cr1&M"9OM_PQV+k"9GP)?m>`3!gF=UMdQbd])mp(]3kZ#"9JE*"9PrK!mjjKN`-&`Zj>._qZ4YA>QKcc"CR^'P]16X"9F/V"9\jS"9Z_D!NQ9d!sA`0!fR2fKEPB[!PJU;b6#$R",gOj#5\ITPQQhO?j5Ql!fR5>X'cJ0"9JEG"9PrK"JAZrcVjrLc3Cl^"?\RCh]Gc"oL]5f;Zm4(;Zm47"9\a\"9Q>:oPe-c;Zm4(UBC[S4?RS3!JD^$N$JNo,QpdA"9\ai-GqfAN"Q<\,Qq?T"?Z^L"9G#<KE8k6;Zm4("9F/U"9^h4,QkJR"B#8R,QnG?*%V0@KE6a+F<gtic;OiKoHggF%#bf'PU$Ao,QrJq"C(tt"9G;D!U*Gb"P6e?"9`g)"9F$O"Q*,\<`9,(WreLg!fR6_PQY(k?j?K0!fRARP@+No"9JE)"9PrK"L_53>7:Oc"8`,2KE7<B++j[s"9^i+Ws,A!2?W[T;Zm4cgB7T?"?^WV"1D,2>?h2^"CqW3PQ?^gP?SFr;Zm5D!fR6$"9_g0!ji%4!W)qWZiSoh?s/*`!fR07Rp^+1"9JF@"9PrK/:US$KJZ[SF<gti,Qn.,;Zm4c!JCKXKEN+p_cmNM!JFE""@N9\":.p/Vc*WO>7=1/]*&/H"?^W?"1D,2Vc*^$>QKKYHis7MN$JOr$iuRn">$TXKPscl!PJU;"9OMbPQV+k"9GP)?qUQS!gI;lUL4-"K*%!D"G:(aDZg+="9\e5X9FngBH5e2!L+\=gO(7L"4%"("9`g)!JCq]"8c;-N$JN_$iuRnKP6!B"FC7P!K-IO"9^i+!!BZ.zWk98N;Zm4)"9\eq"B9aNKEME[!K;(#Erh4&%cdY\P]/DD":XVt"4R@d!P\a?)P[=dKE)%+KOD[uKE8miHj8U3!JCK<b@#BjDZiH1"9\ai"9\^''EQ9R">j+8"=,8r$j!X:%T<K5";q=^!OEak$nMG>1bQ[M!rH1A"EHU==&T5)5Z7dg=9JZ+"9G;$X98R;?j!_9!MfbNgL('ZqZ3Jn"f#H+!ODg.S-$lAe8GHj;Zm4(ZigDb"9GP(=9JZ+qZ4&,#5_d/"3U_HS-,6ge8GHj;Zm4(!NZ<n"9_g0!Rq2S"j6qrX9IotMdUT,"9G"s"9I"j"9;@'[fQI2;Zm4(#lF_4gbBDb!&4Knz!j%M=Lf4EZ;Zm4,!OMsU!g?hf,R9iEZigEB"9^:W&$St8"Q0I<"9]EDX9?%3";q=CaAW3E;us?/F97Y1!PBZ\/HN3]GP_LG"9]EXb6mH3&coXI"9F_q;ut2g!Rr@tga!":;Zm4("9].["9F<W"8GdtWrh>b!o*nZj9/Qf?j!G2!o*skUL6pQ"9QeZ"9X<q%=h@[peq:u;Zm42;Zm5B#3-2\'O1d>aAW3EKEI#:"C"n/J2U=/doI.a;Zm4(;Zm4n!o+6`"9_g0!NQ:_qZ>g]"Og`Z"02LYbQ[<?KPptp;Zm4*`(K&*<")n:!R)el,Qn.T!K7'/!Seq'j<OjB"9F_f49=do!PDDP,Qn.\;Zm4;"9\eA"5>e6bZk1h;Zm4-"9\at"9Yl,#-_#/<YPi'"9^g0"9J3pgjXDL"BYd.KED>[)Zt`qg]<%8?paGd!mCeR",(RqLf4EZ;Zm40'Q4*;":"a(!KU.^]`\Dd!o*nZe-&kV?ig-+gB-/W&$oXIDZg-c"9\g[!OMi*!P;PEJWgGJ";GeU"CG(1!N&cuE%J$m;Zm4;"9\qUUBSG3>QNFY;Zm4;!ON!6!g?hf>>tX9ZihJ'Zihr]P?Uue,Qoq*"9\b<NX499gK#!i;Zm4,!Q5>$!OO*ThbsX\"9R?Zj9,Tf"9GP)!W)rZg]bT'?q%[/!mEP!",(Rq5Z7dgYYtZ-;Zm4-j9,UQ"9GP)=9J]\o)dtUF5(((!NQ:Wb\d5bKPptp;Zm4*!WE7i#3/_ui)9a];Zm4-$tKCkI!:KQ!PBZ\,Qn.L"9\bD]ENgaqcd##e,b4)!Q65m>7:PV!PC)?]EEQaqcd##,QpdC!R(S_0AB\>HNXA^;Zm4+;us@E!g<YC]HdV*!OMt1"9\iZ"9_b(g]N33"BYd."j7"$ggnT9?j+(C!mC]2",(RqO&H/a;Zm4)!PAQ%X<7Q)"9HFA"9]Dae-)XI!PJU;!sA`0!o*m2g]U^^?j-'&",(gGdpN99qZ>8iFjj_!+k$MJbQEc2KPptp;Zm4*J\qZ<&co??,Qnei"@N:/;ut2g!Rr@t!Pg5h!OMm7";E*a"b9MS>>tX1!Mfd\!PBZ\/HN3]GP_LG"9]EX"9e0l!NQ:_"9R?]"9\j0j9(&;?ig-+",&brj'Vu$dfS;d!h3RFDZg-c"9\g["9Z_D,Y\<Hmo'>l;Zm4)!o*pV"9_g0",$aZ]`\Dd",$dXP@+R;9*3UZghXf8?j?K0",(I-_dEkIMZV[LbSspmKPptp;Zm4*;us?qC]]f)!PBZ\U]JC:!OMt1"9a&S"boqYc;OiK;Zm4*!n.=E";G)H"J/NpgK#"1;Zm4,;us@549C]T!PBZ\/HN3];Zm4+"CqP9KE9:Be0G.t,Qne^]JKZE"9_U'!Obo0*5hrldg)BS>QToe;Zm4;j9,YC"9GP)=9J]\!sA`0!osH:dpN?cZNGj_"4LWY!Lj/GbQPOcKPptp;Zm4*!Rh+A'O1a[%T<K5>>tX9"=sZPbQ5X-gKP'e"9H.g"9\jS"9uV>T/T[OUK/'0;Zm4*/-H+-!PAHK,Qn.\;Zm4;31C&J$k`TR,Qn.L";Cm\,QZC?!PDDPpJV1t%-.Np!OMt]<SL^d>62*Y!N\],!P;PEVc*^$;Zm4-43If!'O1^3k#2Bc"9O5WZigM6"FP7lN,o'5#Q"W)"9QM\]E,bMUBmq&oDt\5!ji(8M;n^^!!9M.$,ZhO!PniE#_N2c!L*Y=!e^W^dpN<b"9J,q"9QM["1D,2r_iq&FLqYZ"9]EXiru#Q&co?Y,Qq'T!Ls2/!R)elf2DeT$j!^=ZnL0<Oo_osWs!eN";Gf+"Q*,\zM^/9&"9\e-"9]!/"9Rdc$(t3"TMksr$g9DV"9`d:"9O*P#(TVT=9JZs!sA`0!h9=^b?tLsdfK)Z"/B6ZDZg+%"9\dr":N"D"9^;M1iP2@-;t$M>ZCnH9I0fELf4EZ>9$<@"=+$.6i0h.4@Bfe"Df=d7fenY#bV<i">g.t"?'0]"=-]X$Lgss!Pf++4<u>U6p(L?!TRB(TMksr&d1l98V7-Kiri%p"B9>9>]=&6cr1&M;Zm42"9\pZ"9IFZ$g:Llpeq:u,QpL;^B=[E$sZa4"Dj!#"E.3A#`qsfW)Eg%9OP1.]Gq=m,[;Ss'P&Hl"Df=d"40sL:f@K"=9JZs,6@E>oQ'h:?j":I!TXd/!h=03``!!C;Zm4(,QpM!";Cli"9a*P"9`Ne":M/,1iPdFP?T##>=;El"9_*h":=9j!h9>q=9JZs"9Iilli[@&P@,%)o)bEd!io]0?kWS-!h9G;b?tLS'*7_/oEEEGUL8-D"9IQb"9P*3!f'\WWr`,$!V?Kqqug+)?ig-*!V?TNgL*Ur"9IS*"9P*3".3!i_ug,F"9G"n"5F#]#m#S"e-$EE!N^>CErk&!56M+*$`jBYKREmNbZL>>!R(NE!R,c2!R(S\!Q5)X!R(S/DOUZsN!A<Mgi!;r;Zm4($rdH+6lPA96j.i>!TRB(\5NM5n8l2J"CtaC#Im\8pJV1t"9IijoE53."BYd-"H*<IoEM'u?iu;f!TXB9!h=03&5r]7^f(@=":1Y'#IFMh_cmOK"9J-I$q(5F"9H,="n5Fn9I'`T">p<U4B3X`1aE2d/0k?dfM_nU":E'K7!&If4FACW"ADf8"GftZ";q=f!Mq=M++j\!"9^Q#*,HZp"9IOeFDt*`]3?8&;Zm4("9\h`"g]%E1c>Ds%T<K5mSa5k"9J,r"9\j0oE(Nb?j?K/!h;T0K4"enlN-WE8]tLbDZg+%"9\dr"9I.R!h9>q=9JZslN3RZ"cHak+k$Ja!K_qADZg+%"9\dr"9l;6!h9>q=9JZsZN?X"(V=&UCm+nl!TZm]!h=03s&0%'9Q?g.'F<J,6sLu?*+U;t1i+E?,]k:7"FMHt9EDpk(fLP?'I3fT2BHMk;Zm4S"AAjr"9^P,\6C:Y">i"=!kqS9&o;K=,QpLDPlr(S":CY"!S10PS-&ls"9J,r!h9Bq_dEYk])hP2jE"]5S8SN2;Zm4)"9\bf"9Q&2!h9>q=9JZs"9IilS-/l+?j""B!UKsTlX0mkRfW-alX0aN"9IQb"9P*3"Kt`,1aE2t6mMn7J5ZRR;Zm4)"oe\-"M7]FY#>H+ko<@u<!&6a@Dc:X!M!+W;Zm5&oEVI8X9"1_CBOb^>9$<>6rX9c"@N&j>]<(-"FC8FQr=+j!M2+K"9uJ/"/]!"E#FQ:;Zm4[>9$=U";Cq7"9_[L"AAj2#*)Ub=9JZs!sA`0!h9=^X'c+SK)tTK"OgaiDZg+%"9\dr"9H;:"n,@m85fWo">*:M-;t$Mp/;(sKpr2J">k&u9I<[@!TRB(qcb%>,QpL:;Zm5.!V?JdoE88!?j=dT!V?JPgL(*K!TX93!h=03r_iq&^B=ZD$sZa49Ngsk9E]\F!TRB(j'*L&"9\ag9ENL<".'f,k>MKd4?U4W,Ra_/1e].t'N?=\**a`l"Crb\#I[P6qcb%6,Qp42^B=[="9_C!!!:/=zWo"lu;Zm4);Zm5B4<ss;"9\j*#1O,]!UpTC"Pa?SoQLFslliD<!M!U+!Ls:oN!K8n"U<H_I/=/u!Pnf,!o!aG!L*VLqeQ;'"Og`_V?5g`"9Gk1";"K7!J")O&5r]7!O-7d"9^P>">hK)Qr=,*,W%C]@aeO44<t%T!JdEQ">iMc4=!TG"9\j*bQ7><"BYd-"e,PbbQ>sq?jDSj!PAN8!N$=="9\bt"9QYC'EAmO"=.CqDuk[Y,QoAL@ClY)"9_,3df_p7!Mj[V-;t$M%1;GI!OMrf%YSC]"Y9\=">gY-"9_CD"9]K=">h6"4=!TG"==7L!MfbIB2\p9Eri'>4L5/IZiR7I!P\a="9\b$*S`SP!NQWf!Q5r<"9H1=Wr^]Q!R(ZI"9_g0!V?Hs!W)oI`!:p&?ig-*!V?VLK4"`Ob5ofl#D6Cd"1nU+bQRNF?if!_!Rq8Do3_Uro)\Id`-Ykm?ig-*!Rq48.prDT?qUOE!PAYq!N$?["9\bt"9]cE"9Fif!L*Zh"BYeCErhd6!MfitUBEDp!N^6dUacKM!NZD)Zijo\"Di,[!P])>!NZ='!MTUj!iH'p!O`$);Zm4+!!!)@z!iigMOAc8b"9G"oU]^_3"BYd-"1&$(S-Hl=?ig-*!Mfq;]3km0"9F_h"9H_b<+&W-"9_g0"FL:SN,o#QWsP!k&&`EC!P\a?.FS<N!Pnei-eeZTKE)%+KG]UJKE8miP^G7f;uqXQlX0hDDZiH3"9\aa"9`[B"9_1m"9H^K!NQ7&"9G"qU]^_3"BYd-$_maHU]c<X?j+pZ!NZEV"bU2-"eu*gU]lBY?j"jY!L*VS!R,HbBN#$:"FC7k!O;h2;Zm43;Zm5I)$CW`,nq=%'I3_>//"^^!jc)>!Q-H6'J':/`"JhL>7%Y<1b8^7"=sSD"E.3AFB;BDS/r9$!!!!8)?9a;"9PU0!jGT+bQ@tN!NZD)S-/kn!PJU:"9G;$!NZE+lX0kEb5oflS-r_8?ig-*!R(Y`#)ck&!W)nfU]QH^?jDkr!L*`Y!R,Hb!)j"'0N/)W"A&_9]3>[XLQ_iA'HD&m*$cd4*%W?<"B#<n"BYe#F9;XK4EGlQ"d9;#"9F0pN,T3K+aaCnHm?N3"FL6_A9.d)Erh4&"9IS"!JCKg)?GM=!KNXsbBs;;!Ps.,P]S^/b=m9a#(p:gN,Jh];Zm4(<!3=(1`?47#h/m_%T<K5zPQh*f"9\e+"=,s*"<7P%$mYrn'HF_h*!)QT,U<L4%T<K5?QR^E"9]LA!!!d5z!ij<]:f@K"!mh1q"?Z_'!k;/36mMmTC'q<N;Zm4+_?9uA"<7OF"=,6<"9\ib"9RL[!LQdg#ZCj/2H'_]=9JZ3!sA`0!NZ=W"9H1=Wr]j9!NZD)o3_UrqZ3c#"cHah",d38]EO4$?ig-*!OMlk#/ahQDZg*:"9\b\"9_b(ZiSqa"BYd-"HrlAZiSoh?iuSn!Mfg]!ShSrYYtZ-=9Mk0!K7-a_uZZT@mdR2MZa'F!M"*H+T[N)!JU+J!M0=NN8jqt!!/#Z9ZmHq!Pneq#290;Muf/J"QN_f9EjHa!M"'2OAc8b;Zm4(j:gl$&(D+06X(6E-rU6O";q=^E&Eg^L:[R6#NTh)*4l61j8_#U,QWc/``!!C(Bbua;Zm4u"9GlA]EA@>"9GP("H*;nZj24k>@8ZVDZg*:"9\b\"9]35!!%LIz!il&EJ5ZRR;Zm4-">g=5"=-ql9Ei'S"9a&S!M0jTCU4.;"9_\C",Jp@!UND]fM_nU49><]9M>JO$i=-BPXGQL*)'$,!JILXn5BGm/CO_*!k;KS9EC"R!Pgf#"De4j"k,"J"=uG2!glmh"D\,C!O;h2!sA`8!OMm_"9_g0N,o$\!UKpiiriV.!VC>!!K7-aoE53]e6I%qE+Fk."9\c'!V?E-!V?EZ!UKiC[K5_a"9\i.Munf6!PJU;!h9ArPQV#f"BYd.#0R(,S-Q*&?j3;,!fR9*.prDT#E&YJKE\Da]PdoS;Zm4)"9\b`PQJK""BYd."1nWIPWR&r?u+d(!ea"S!k`FSfM_nU"9Oeh!gEgiZX=$%WreLd8b6<lDZg,p"9\e="9]K=9EF?U!PfKSBN#$:!P\a?OIH:3!!2-]C$Pf\!Pnftgj9(_j8kJG,6>.PUgM#Ir,2]=;Zm4(;Zm4'RfieK!UObY7T0Em+&`:FE(e@W"9\bl"9`XA,QY&H"9]SF"9G>MUK\Eh>801)'LW/s9EKiN!P9ls$*41)KM2E2Md$l#":VX<A]n+Q4:Dj=A:,X*!JD^$\5NM5"9Oeg"9\j0MupWo!PJU;o)cQ-#-2,4!W)qWPQgql?j3k<"9O6<"9Q5S!PVJ8!K[F0"<7H$6iiMt!LtD<N`-&`;Zm4("9\e`PQIFT"BYd.]E89>MZUNm"f#H-?lK0[!gEhGdpN@>,6F)4KEKt:]PdoS;Zm4)KFj@X%[8s]k#2Bc;Zm4)!!!+ez!ijE_:f@K"8d#7S;Zm5N(<cgK!QY\F"9\b,"9QYC!T6lZE&3CT;Zm4;/0"br"=sSD"9^;%$j!X:E)QlBe,ogV"9GS)!Rq6So3c+PUB.G!"P[;cDZg*2"9\bTX9#7u"BYd-e,ogV!OMt1ZigE1?ig-*!Rq4`X>=6'?jD;b!Ls4d!Ru#j/lMlU=9JZ+"9G;$X98R;?j?K/!Mg!R4(&*d"PWsYS-Hl=e8GHj;Zm4("9\bp"<9<ue.`$=/0lJJ#+Jg*!KmQg;Zm4m2i@^&UO3c'HiSOr_0e*"!LnH;Hi]IR?jD<X"?ZbG"9Fa*X@H1l"BYd-#)`M`X9%'`K4#o)"9G"t"9I"j":e?59QU@>"9_g0"E\^4Duk[9]-ILF!K:suV#ce`,Qn5Nj*UmCHus`]!OdA&*/aq&"9a*k"9^&M"9`=8!!$q9z!it3%n5BGm(Bci&"9\qeg]l,("BYd-?m>^-g]<8L?j3##!R+og!N$1q"9\dZ"9afbZik.IHs-%Dj9_&-"CqZ=P@.;l>R&hs;Zm4["=+&A/-H(n"9\b%1iOnME%$VI.Dl9N#N/!h1]`I:!Jg7L"9GlK$A_U`9Q23ZM?F3@"9^gf":F?k;usc[/0k?t$)g7U"9^86a9Up-Zq:H-;Zm4(;D]A#S-dsR'9$33i"lMY;Zm4*"9]"Og]E-2"BYd-$bHIngdB7m?kD?!!R(bC!N$1A"9\dZ"9t5lDukWm"9\b4"9`pI":2M9KE+pR"BYd-!PJV`Wr]R1CpQSQ%#b4b"9]]B"9_M!*)oF,"@e;R>QKEZ">*RUaAW3E"9I9]!Rq6S"9H1=Wr_8a!Rq5Qj'W%cqZ5b>&$oXE-bBE7!J6MC!i,k@!e^TOYYtZ-;Zm4+"9\b("9eKulUFeUQ2uaB"9],6":+Ep6p,E5-d,^&gKP([$*4/a!LEhF"63Vh"9\ipOA&JL8]sX/W)Eg%4EB`m%ZCf/Uiuk+]Emj/1e`B%Ucnj5N!/2F"RIWB"<fl11aE2dJ5ZRR;Zm4*j9,SK"9GP(KED>["9I9Z!e^\Yb@!W"b5pB!!R"jT!W)oYgb>d:?j;5a!R(W*!ebIpG#JMH$lrRU"DV0EN`-&`;Zm4)#GYNFA-;q"!LEu=^a'$cMc<@N"9Fhi9Oh$qQNbi;<(mDqqc$7!"9Fho"<g/9!(:=T;Zm4k"9\b6Fc.A@*"3Hb"9^;]!l._;Sl5ap;Zm4)+\W"u"-`ok$'YJ*!(7(hE$GKR"9OTW`]O9Zo2[[K;Zm4."9\f#"9O5Y!NQ7^"9I9\!e^\YRpZW9K*$]2#2<Ng!qQHRg]lM@?ig-*!Sdn6]3kc:X9$N_KE7qX;Zm4)"9\eg"9HM@"9`KC1_^re"9K+P,Qn77F#4"F*,s(8">g.D!N8p"4pLUX#GYN,<!35g"B6:E!r#Ur(C,UM"9\g^j9.qN"9GP(=9JZ[MZMT95O2\[!W)oYgct+4@!hJG!R(e\!ebIpW)Eg%;Zm4*;Zm4/!Sdg4e-&kV!PJU:qZ51L",gOf?m>^-!R(q0!N#q:"9\dZMZaMg,SY1u'Jq'<"?[q4!WH"#QN=^'#J:0?<$hmhYQE<Rj9"ZK!Kp[r%@daSoHOb1"7'1s"9\al"4'mK^/G.;<$[(u*!j1i9OoCO"Df=d!R=UH!gaGX"9^86"9a``6p,E5!VH]Q9EC")/Ak[#[o3D4!PAO<]*)A[!Q8pm!P\a?!OMm?Zss-LZs]X0!OMh-!OQ+T!OMmDP^E^oKE8F\?o$I;"EXap"9HGZ!JjYWQ;[nh<+=Sb"<7g_"B8nW"9\jSg]P#a"BYd-Wr_8a"9\i.j8su:lX1q<b6!?3C?o72#/^Js!R)3b!ebIpAlAg8<#T"@QN<"L>Z:h,"9_[B"9S$j"9`KC"K#*#$lgu(zWg3ki;Zm4))$CpM>9"mk/-H"6"=sZr'Jopo"9H,=,QLaG"9a&S$j!X:#g<LS#ODJQ%T<K5!!!u>#64`("9PTf,S3lW"9a&S$j!X:";q=^,U<L4/0k?4j')pK;Zm5#PRRI")Pf1ozYT*WC"9\e+liN8Ir!$sE":3Kl"=,ND/0$Jl"B5M%KEME[!M"33Erh4&gB,;U#_[.%!J7W\]Ek<P+T[N(!J-F;MuWm;^B=Z?gAus.!!.`s62L\9!Pnei"hOegKE7<:!fL"Y6ir9S!M"'2=Ao>*=9JZ3"9GS,ZigEC?j"RQZN7F;#0UBT!W)o!X9QjU941Bn!W)o!Zj#Jt?j<Y4!MftD!ShSr!)j"'/lMlU";q=fE!,,'>7<&&//0)9"0;Nn(/k>=!)j"'QW""i!!!!"+TMKB"9PUW!m":C";q>)X&_?%;Zm4-j9,L>"9GP(]`\Ac!SdeYg]U^^?j5Qk!Rq>Nqd9Y]qZ5a^#5_d/#(ls3bQ`]-V@B=%"9O5W":.p/*%"Segf,O%,RoD/6nAQ'$nMNZ">fXR4CD(jK1H$9;Zm4,;Zm4g"9I!Pg]RYk"BYd-"02IPg]W7;?j"RQ!R(W:!N$:D"9\dZ%YRVV`'P5u;Zm4*"9\dV"9Flg"9G>e$Bt_T!gHA(Uiuuqj9)If*)qCtKK]jhKF$WE%_O;$>U0G'"B%W=%T<K5,QnXj;Zm4C!TXAje-#fQ!PJU:"9I9\!Rq6SMdQ\:qZ5a]"cHah!i#eO!R)cr!ebIp?W.(1?rI12Wr_8a!SdeYj9/Qf?iop#!SdgYX'bu*MZMT9"P[;c%#b52!e^TOk>MKd>;RT+o)rm9,XcTf"AC'D"E%-@HtQ@\F9G\K"9H1=Eri?FZigE*!L.X+E']*ZgB7Pi!Q8qe+U#F\"1/9^]R0kZg^So;#Lin\+T\YIXBO'U!NZ8%!N\-,!NZ=<P]R+fHi^;LP@+H]DZjkW"9\bD!!09%zX+hYq;Zm4)!Q55Q"9_g0!UKmkWr^EI!R(ZIo3_^Mb5pr5"nQ+*"j6r5`!<n^?jF"=!ON`V!UO_-cr1&MOD*)G'ERG&i)9a]BEdu0"9]ED"<;AZ/0m>'`@M-iqZLRM!L+i3&;(*:"9]EX"9lkF!NQ7F"9HFD!R([KUL4=Z1BGDq!K*@SDZg*J"9\bl"9`+2oE(siQr=+j;Zm4+'IO(B"9ZhJ/21!*";E*aDukdL,Qnf4;Zm4[;Zm5H$`!q#!Oj/`"9]";6DJ-k$k`os4<t%T6mMmL!Pfr`;Zm4S!sAa>"CqOlPQV+k"@R;39QL6)Eri'>:[8-g!NZ=s!P\a?"9\b$!Ls2*99TU^"9GlK"<df1!L/"bP6$mJ_#]c1irPAFPQ?^EA-%nqUL45bDZj#D"9\b,"9]!/,Qij$n,sU3o2ZP,;Zm4,"9\c#"-<Q<liR@n"9H.9_up+S"BYd-!W)o1lit(0?j+@J!Q50%$Xa+TDZg*J"9\blTE1]aK2rZf;Zm4("=+#&*%W'T"=u*(">gf<"9]\i_uZc7"BYd-!S[Xn_ukp*?j<Y4!OP;-!UO_-mSa5k_B^Z51^!UUKWBH)>7<Up/-1Ru"9a&S/9"aU1aE2<4<t%L"B$cr>ZLlX;Zm4;"9\b`lN2i?&hF'D,Qo(q,QnfD;Zm4k!PAHZ"9H1==9JZC!sA`0!UKjRgL(,AqZ4>6"-[*n#O;E/_ul32@!K9a!OQUB!UO_--rU6OpJV1tV(;`M";Ct>"<96D,RDU>"9_UR!o?iY%T<K5=9JZCb5oNa"Iid'?jd"R!OMs@!UO_-hGXO[;Zm4("9\b7"9GAu!hN<nzM]Vp!"9\e,"9n!f6lfgE%`Agpe-V@`9Rf_C4pKLn$'Ysj$/@%1<$VSd-rU6OBN#$:W)Eg%quX5-g]>J$Vukur">i"@#*;ad"B%W5E"R^*U]^_*_ZV+`!!/l4%>t7_!Pnf4Cm+mqU]H^%8qV3dA-1Ln!OQbJW)Eg%;Zm4-"9H_Q!Q5+C"9H1="H*<!bQl=!?j)Ag!Q5/"MdQXfgB#M%>Phe4DZg*R"9\bt"9FT_PYP-[j<Oj5>7=17"9_;K"@N:*PQ4Vb*$bXlE&d^t,Qoql,Qo)\;FDd0!sA`0!R(T:oE88!?iu;f!R(YHB[^?6DZg*R"9\bt"Ek8R"9GSr"JAZr";q>)<\siL"9\o*"9_1mbQ7><"BYd-"cEERbQ?7$?sEL/!PEZh!N$.H"9\btbQ=_A"BYd-!W)oAb]'Uj?j6E.!PE0J!N$:T"9\btbQ7]A"BYd-oE,4!!Rq5Q_up+A!PJU:qZ4V<bSspj?iop#qZ4n[#I@e=#O;E?oEV^1?j2Gh!R(eT>@7T'"/Gt1!V?Di!)j"'!PJVP=9N^K!Mfi$"9G$6XE+ED!OMt1"9`O^!NZ=:X9"$-!N\inDhA)G":=^>KQda@ljh5J"f->C$f!Snj8l&cB*"e9%@d[qKEVaRUaZ*MU]J:4Ci#:9!Mfa\Eri'>Wr]:i36Ock!NZ@s"9\b6!f0bX^/G.;#/^QE9E\U>9EYCX"?^*\1iO)fQr=+j"9HFAbQIs["BYd-"H*<!bV/Qq?qQ%P]E*`HV?Zr!"9J,q"9;@'1iNTp>7;%<6nADGZNNC!"@R3>"DC^:"@,lg"/]!"gKP(S,QoAQ(W-AL"9_\C]*'cc!N^6&G#JMHc;OiK;Zm4)qZI#P!N^5Cr_iq&;Zm4)">g/"!R+4_,Qo@q"Dgt(!'aBbzWid3>;Zm4)"9\b`"@N5g9EYC0"9_g0">k1I!N7X""9\aY&Y"/THi]gd_0g^$EiXQggO'!K!Ps.6PXGn,qb2A<"05f5DZg0l"9\k7PQ?;5!PJU:"9G"q"9\j0S,pP1?j?K/!L*e@K4"`7MZLa#"f#H-!V6?1S,qAPMdRb1"9FG_"9HGZ,S!`U]EB)TZWdhI@4WB";Zm4;;Zm4?lkumRMueJ=;Zm4AH_U^."=,73"=u)L!!!-Zz!ihCe#ZCj/+7'3m#cn'H!)j"'";q=V_cmNh"k+/Q"9]]-!"8n6zWok?%;Zm4)"9\l&"9^DW!OR)MZijJ6?j+pZ!OMr]"cHb=DZg*:"9\b\ZinHK"BYd-]`\A;"9\i.X9%)Y?jD;b!Sdpt_dEYK3ru\nU][Z*gi!;r;Zm4(qZHu9">"Km"LqA5=9JZ3!PAO<]EA89?jD;bgB"ZkUe>)!gi!;r;Zm4("9\h"/0mJZ"=u*6"9\ib"9]35*!>D'#Qu"J"9GqN02huV*`E1E"BYe+ErgpsN!'07!Mjc;ErhL.P7+0C!M"*BeH?-L"9F_fS8\Q,!K7-^"9\iN!JCKg!JG]eqZ2?M_#]3DK)pW+!L-OaX&K+Q6k`r4!M"'2T2Pjq`#kcUU]Ib+!PAO>ZigE1"BYd-!W)o1Zilk+?jD;b!ON!!RpZEk"9G;%"9I:r!Us"j!M0uM$R?uC,U<Jm*$Yl!,:ike"9G).GVfTZ_(6f^"9^7V!ONV@"9_g0!Sdb[]`\A;!NZD)UL4-"o)[VJ!i'-(!W)o!!OOXj.prIsDZg*:"9\b\"9HM@!RF[I8d:f)"9\n8/-1K(Ws]C/ZQq((,:"N8"=sSa!R=UHO&H/aSeNCM,RX/E"02eT,T7pZ!OF=.;Zm43Y:Lr;/9`WG"9\b6!Tm;`">p<5/8ug:QW""i!!!!")uos="9PUHZqs[("BYd-]`\A;!OMt1ZX<h2qZ3c#"1)A9#(lr`U]oddV?-;i"9I9Y">EaW!Q\1B!)j"'%T<K5?rI12"FC7s!O;h2)$Cof%AY6PMuhsC]H&O)!X(%\!j"3]PQ]3->Ug^$D@2=J&&\L,`!$VB;Zm41KF!6<bQ4^Z"9GkO"9\j0ZiSqa?idS7!SdhLo3_ZYMZMT9"J]?,",d38g]Q#5?iu;f!OMpO_dEV*"9G;&"9I:r"@c;m"9GQ&"BYe#7!!_YErgpsCYJu6"9FI#!O)e"S-/ue"9G>"!Pfr`N!'07"?^`+PY_OIO0\riS,qOK!K7-^PQV+4">k0#!L"/6"9\aq!L*W"!Pfr`U]nti$`nOY(jl[l`(g+CoR&"jUC*e"U^>NO"UOH*'GLq._ZR8i@Lgn5HjK@l]E=+*"Ur<Y>JgX"Hi_'2PZ.kab=m9a#0UBYS8SNm;Zm4(!#u#7z!ijE_J5ZRR!sA`-=9M<>F*n)n!JCT'Wrt8#N,SfJ^B=Z?"9XS`N,Sjq%cd`nKEME$oK70qE!P,%%,:sOP^IlMe-GUH#P80&+T[6!Hi\m'\9n=O!Od@W;Zm4+;Zm4?36MFi"9a*kPQJ'fHoHrcoEE`l"?Zhg!e=2P&(Cfb"iLG3">(l%!O;h2"9G;,X98R;"BYd-Wr]R1!NZD)gL(6_qZ3Jn"litk"1&$0Zj#Jt?j;Mi!NZLKZX<g_"9G"n"9I"j!N8p"";q=^#+Q3_g^]iuIg<=j!JDF<bRB.g.g:k7$nMXJ"9t?"!N/j!(uuI>":U5"!NQ7."9G;$X98R;"BYd-#D3&aU]\MB?j!G1!NZC@_dE_%])eu8"LDJ<$]G+V!Rq.IO&H/a;Zm4((^'tC8d#\A;Zm5N"9\akFmBN9X*anp!Ps.bF9mMH9RHl*RpZB*DZi0("9\ai!!$)!z!ih^s";q=n2CK481`:o["=+Bg"<9fT"9_CD'W`]]oL]7n1d\ei"=+Bg"=uqd"9_CD1^"@g"9]uE1^"@g"9]uE"9\^'!"8n6zWim6>;Zm4)"9\bp"@R&.F9D_Kb5mQC!Npf0&"FQ]S,pA-!Kl[XF;YPK_/pEu#.nsXF9.VB?j=M:">g.K"9a*j"<7D?"<7O^$nNYL">&kCN*'!]!PJU:!sA`0!L*Vt"9_g0!NQ6kqZ4>4!S^u_#(lrHPQBNH?j;5a!K72WUL4-",6=#4KE[9A]PdoR;Zm4(^B=ZL"=,5n";DOq"9]tq"9]97"9]97,QWWu"9^RbbTBadaVa@b!"PM"zX+_bu;Zm4)O7NGB$kcM?A0_:OCa]E+,Y_5@#ZCj/OAc8b;Zm4)#1s.$#.%>U5Z7dg/ma/5"9](=j9ECu//5H%!ULBqli^Dn?j+pZ!UL!]]3klU]E-f4PQ@Wl;Zm4)"9\jplic6F"BYd-PQM$k])n2uPWN7T?iu;g!UL!Mj'W#=K)t<B#_QLjDZg*r"9\dj"9IFZ!gEci=9JZkMZT+G"N+UL"S2Z\g]GZ,P]$[*;Zm4)"9IjK"9\j0PQI'O?j"jZ])n3q"Og`\CZ>H^!ShHu!N$Cg"9\dj"9YT$!n^ES!MiZt!P;;6<!T1+K4#)a!K0nY]*@k7PS=.V"9_[)"9d(M!O#E)BFBeN,QpdD,Qp5/;Zm5."9\jh"9GE!"?06^!M33m<"fC.#4)ZgZiQ,0Igt`O%)au-g]>V_.g4W6<!3;^RfijG"=.qY"/o-$Wr\.^!JCRV"9_g0UiQRD!PAO9"e9[UDuka3MZa(!bQ4pK!K.']U]Jta!OX0]%%I@2r-&L,KGNSV!PDkO!PAf1bQNl;"UFr7$2b"/`-a<2r"%9X%FbOj+T\qQ!J&&jZiC-6Zok)aZiRuDMup$\ZiQBlP6$=;"G:(de8GJ3;Zm4(;Zm4?!p]lCr&+VC;Zm4."AAl`$nMN!;usU8]3>B-!K4Pj;ur3t!%G5W;Zm4K"02LL,W5[b2H'_]<$VT?"1/*i_u]LSIg"7."jBA>qual$.hCtV<!3TQ"9\iZ!T[9["9H1==9JZk!sA`0!TX<HUL4-"WreLd!Ma$'",d5Fj9P9a?ig-*!UKjQ]3kcr"9I9_"9Og+"-6@`DGpZ@<$VSl>U0G'"B&2=>Xh><;Zm4K_,LOIdf]dS"=.pi"/]!"[Sm;3!!!!$#64`("9PTh`!B9EA.FP""9]CF"=*tG";CtV"=,ND"9^P,"=sSg/-&TO*#p4,/1`%L!!G.^zX-+\-;Zm4)fG"P"43L.skYhTe!sA`-!TX<H"9H1=Wr_hq!UKpij9/Qf?ig-*!gIMbCm/6G!W)oilthkn?s2dr!SdnV!gIU+J5ZRR;Zm4."9\dV"9]97"9]cE"9Flg"JAZr!Kl+>1B_6-/-Kd."AAj3"A_r!"R&be";q>!!Mqm]83djl"9\tQ*%WdB"@PXX9KW@R]+cLn2?oOo"9\e="9I.R#,"ltG#JMH8-+GZ"9\ed!UP#/"9_g0!gEciWr_hq!TX@a"9H1="j6t3oEW9A_dF\iMZMlD#K'pP?m>^=!Sdd`!gIU+%T<K5PQM$k"9Iij!UKqkZX=#jdfPa:"LDJ;?u#f0!Sdm3!gIU+!)j"'bWJ9e23S.Q"9]EX"9d(M6uXid9I'`T"B%W--W:-N"B%W-&,ZdA!j_pk/7Cpd!K5\8";F7C"9_CD"9^Y^KE8.V"BYd-EriWN!PAP'_ZY(&"KZQDE!=]QMZa()!Ru&h^]pS;"9H.9ZiRoE!PAO9P6=!h!Q8p\E,<Dp]EA8ZZihNQ@fa4CL4]N6!!0G-IY.[.!PnfD#-.d3!L*Vd!JCK\b@##4DZk/R"9\bTliFn#"BYd-Wr_hq!TX@a"9H1="2b0+oDt^p?j+pZ!TXERMdQS_P6("T!OH/\DZg*r"9\djliO[q"BYd-!S[YAlim8o?te!i!SdbB!gIU+TMksr6lhHl"=sro"=-ql"9_sT"9G`*6o\*J(qWu\9I'`t<,a&bDuuL3;Zm5."9\akoDs_GU^#lt"<=cL!gEciWr_hq!UKpioE88!?ig-*!gEiRlX0h,ZN9CqLoXne"9I9Y"9Og+!PVJ8&k!n$,Qnei"oL2V">!e*"9`6\S,qJF\d"Z5";DsZ/-KK/6pq'k";E*a"Fa8P"9G>e9I'`T"B%W-mo'>l;Zm4(!!!.fz!ih@c!)j"'";q=V6X(6E"DSnZ!O;h2r!;Wt]E,VT!!!!3+TMKB"9PWZ#*;adCa9-7"B%oMLf4EZ,Qoq,`WUC",Qn5N"ADKh"B7K/"9^P,"9Rdc#1uiWE,UX;"T1A]">j@/"9`6\"9]35(9:81/2dOuLf4EZ!sA`2j9,O;"9GP(=9JZ[qZ5a\#2<Md"1nVfg]lM@?j"jY!R(c.!ebIpQr=+j"9I!Qg]RYk"BYd-"eu+Jg]NaJ?icGl!R(cF!ebIpQr=+jKH$]f*K0t6"B%oMZi^F6"9FG^]EA@>b=lsX.07A-N!()X]E,bO]JPNI!PAC5!PA`6!PAHLPQA.<MugQl?j"jY"FLuc"9HGZ":.p/!VfRrQ;[nh9IlS5oK3Np>QKusA0_:/-;t$M>9jWaMZa7U'J+3D"AC'D"5$NT/0k@'9I'`TE,UX;,Qp5/,Qor/,QoZ/;Zm5>"9\bog]E-2"BYd-",d56ge%*Fo3bc'o)[W<"iF_$DZg*b"9\dZ"9Q)3!e^XYWr_8a!SdeYKEPB[?idS8b5pZSgacb:?j?K/!R(\q!ebIpL/S3XW<><a*\7Ep"9HD2X+!tMM$8PS"?[(n">!e'";GAl"<;5',W'Tg"ADKh"B7K/"9^8$"C+u+-gMHl$ka)P">*:M^f(@="9I9Yj9,Tf"9GP(!W)oYg]s$N?j5Qk!R)Fn!ebIp?;gt0J5ZRR!sA`-j9,O;"9GP(=9JZ[_ZGJo1LL6?!W)oYg]F6Y?j4.C!R*do!ebIpQ;[nh,Qne_Di4`l4:9#51gD://7^"/1i+E?"9_Ur!Oku1Vc*^$;Zm4)"9\ad"9Z\C!NQ7^"9I9\!TXAcb?tOt_ZANr"litkDZg*b"9\dZ!!8ckzWk'2N;Zm4)"9\ei9EDY%6j-Tp"9H1=7!!_YErgpsK*V<r!K:uDDukk"S-/kW]E+i0^a'$n])dQc!JCK+"9F0B>]Tq)E(?B#_up+*!R)JmErhL."d9'O"9G$3Ui8f0!L*]f,Qn5nMgPQ@!.4g,Ht;8bdsM24!L,tS?mA?mDZi1D"9\b$"=+IUM=Uif!L+9!3R\*N"9]uh!pjl)!N7*I!PB>HZijJ6!PJU:!sA`0_up,%"9GP(!W)o1Zj+]]?ig-*!Q5#nK4"`Wo)[nV#(p:a"1&$@j9C6E?ig-*!PATrj'Vu<"9GS."9IS%,S3lWoIM6j">p;k(/k>=O&H/a!!!!")?9a;"9PU3"E79B!Ou&2HijKS"BYe+Ergps!K7&<#m$.2X9<7\KE8gkKLGD4#E/W`!JD`1!JCKi!L.sfb>\Lq"cHanN,Jhe;Zm4(#.+EHr"]M7;Zm4<"9\ae"9\^'U]J[A"BYd-]`\A+!Mfi!o3_UR@fadVS-4IP?ig-*!MftDqd9V\"9F_k"9H_b"CG(1!NQ7&"9G;$!NZE+gL('ZqZ3Jn"H-Xl!o!aOPQRsob\mUb;Zm4(;Zm4')$CWhJcl2ZEJke;e/T)@%T<K?/-H(a!J1F_,Qnf<*!?PC"9^8."9\^'!Xo+8!!!T7)ZTj<"9PU8!m":Ce,ogV"9GS)!Mfj#"9H1="1nT`U^*)k?j+pZ!NZNiP@+QhirQ4d!LmI#"3^e9!Rq.I#ZCj/%eL.IZkD.B/0k?+_#sqk*!N,="9_UR;ufi"9E\H#"9H1=Ergps!K7//MZbkX!L.PL^B=B:`!1kqHir[<!NZ<dU]h:Q!JCR_$a^$[KI-p$KEJjfU]GuHe9UWo!pi;Y"H3Mk]*sWC!!.a_=Mk/m!Pnei#/^IpKE7<2"liP_6jAQW!L.L*!)j"'%T<K5=9JZ+!OMt4X98R)?j!_9!ON$rlX0bjK)r%W!m=sUDZg*2"9\bT"=/.h$nMN!*&$&N,QXDdE$rO+;Zm4;;Zm4'!!!";,ldoF"9PXX%&d)-J5ZRRM6d<i"CuHPCiBT:"<h"Q9OUn*E#.I:!kSS7iriV+\7BPl!K%!];Zm5&%!2NK,WXU`"FMHtKQ&!E;Zm4(qZI,MKOf$&E!*EW+^>.d@8pJ7>7=J),QWUg"C*2T#O#(h=9J[&!sA`0!V?Gh"9H1=!W)oir-"!+?j!_9!i1!tMdQXFgB%4qDp)MlDZg+-"9\e%"9Rdc"?9<_#3\tg]`\B.!W3'$oE88!?ig-*!W3&+?ic@A!UMV[!i0`;J5ZRR;Zm40P["9W<"raB/YcMY>U0Ft(/k>="D\,C<$VStlWXd&;Zm4R"9\pj<!L-:"m?a*Vc*^$;Zm4("9\q5"9I.Rr-2-C"BYd-U]U`&"9J,roE53.?ig-*!i,t:_dES)MZT[W"j:9U#*T)clil-OUi-A:;Zm4)"9\b@quWYr"BYd-"Hrn_r,]JX?neV^!ULBX!i0`;i)9a],QoY$>7>n$"9`MHFE@Pu"AC'D"9;@'"IN*j[o3D4>7>TS"<8ksUBGri!JGD]Lf4EZ"9JE)"9\j0U]R=o?iu;g!W3(aCL@A4DZg+-"9\e%_uYruTFoZeU_]a,"BYd-bQ@tN!Rq5QP6=!h!SfC5Nr'!uj8k/>!Rq5Q-DL\e!M0>Ag]RZ-"C-!KjDYC"^B=Z?e,e>*@fb?c4Hffqe,TO!e8""Ee,dAdbZWs,e,bd7UB..k"S6"(DZg**"9\bd"@N_u$qpdA"9H,=lN)h5o)r"n>]9_)E,<]#;Zm56$rd8k6pnjr<':E6<$VT7^f(@=!sA`-!W3"pqug+)?j5Qk!i0XrP@+KNUB1:/"05f4DZg+-"9\e%_uf("P].iK+aaD'@<?l";Zm4sqZI&K%tlV;E(Y`cMou66"Di#X!iT$#!P\a?Zij?-">iLI"9_[LK#:)W$kdX_KHp[o,Qp41F9DW'"9]uE<!'d4"9^Rb"9)4%n,\@:"Dfst"1V84N`-&`3#:NU"9`O!fE6k,!K%!];Zm5&ZNLB/A8hR+Dum9J+^>.d;Zm4+.FS@<Cc2BUVc*^$;Zm4(>7>TjF?BW2"9]EIoE'PA!PJU:"9JE'!V?LsRpZ9o!W2tURpZ?)!W2tUMdQ_K"9Iis"9PB;<*iK+!RDPb<`9,(?*am./-HB#j&?&p!L,uu,Qor'AX`g%iriV+"CuHUCiEjIE!OPh^aoV1H)jmF;ur4OT2Pjqb6[_CS,o<(+aaD#@<?l";Zm4;3%`<="9`O!"9Yf*<!4*BMQ9qi,Qo@n;Zm5.5?*Pi"9`O!"9Y5oquBXu"BYd-WrdqW!e^[W"G:)d#0R&FquhX[!KlCClpATtUi-A:;Zm4)"9\de"9Gr0"/]!"N`-&`"9J,squd&6"BYd-!W)oir%mA@?j;5a!W4b6j'WA7!UKi=!i0`;pJV1t!!!!%!keR6Wk>-^]=.'jL$Z7?mHj0(L#Io@M7\MEOPtqoiIll<iSiamL960gL8p*BKS>NHiMPReL#M"LM7\MEOPtqoiIll<iSiam!!$\c!!!!Es8W,r!!!!;s8W,r!!!"0!!"Il!!!!i!!"(gs8VQas8V(Ps8V:)!!!$N!!!!=s8W,r!!!!F!!!!G!!!kE!!!#cs8VY&s8U^Hs8PuYs8N/Y!!:g:!!7HD!!FfDs8T-(!!;9+!!+jTs8Q>'s8QP`!!4@I!!,<qs8LjVs8)@%!!/cI!!(I!s8Sj>s8P[V!!"B!!!!0Fs8M3Ms8Qo$!!#;"!!!`Ns8M/Qs8Q@%!!#]X!!!f<s8KuOs8R/G!!!aJ!!!^Bs8CM<!!-`N!!//5!!'H@!!ambs8I1J!!;=g!!,)M!!Ml_s7qH]!!<Eb!!')N2&.TEepNC'V@bV:)6D!".@MJ^Amq1laHkWH[B"Ba6Yp<H<U_hr!RqP]Ma)PGgHR^n1d;5^lTP`nn398R:-CpW[QbAZ8j?a_hEND0bQmlsOTQq$9$;m?&l?!"`arh^?6CLudaPo*5M1_Dg)rH&(+mA9UBJ-SJ,fS@_@1t@H1s]/YH/WIJA9/CAB-2-[fruSA^R',2BVu"_;iQ(IUWY7[8k>V\A:?(f`$`M8csSrbG"]jf`1tKip"T6fm3gPTniSd$icFfN,AlN?^ee$Y6]YkE[^/=f[oR"fQGhQfO*8AfLje(3sL3c@/E_%fI>H2fEKnCfK.YB:^DRSh(.4dfG*No3"pfI*>^Hj=P^Dfk2'u$?keDf#(ZE^\SQ-Ag=V;GJH!O1<u*+g/q@2R\c[If#Cq$sQX)W;J<^cH(Dl?DLX?_`fP2&"4\h\=#_;sTr77/7c_^]^#Cn&O%c0BMJ82BQ/uHhp(3'P/JmE7j+4rU+4X1,\fUG11fF?IGFp!7+-J3hn$@iK9jt\<M@cjnO#_6aa#7]^;bdpgTFpJD)4`(O(J2uji=Bn,rTk7kts8RB["+Um6f^XtEJ-":dp"\=.F5Z1%fE0_$KEH`@#Ct+TQFNo*f\:tjfXocU;[IuUe'E9-NGT9Wf_cT/fK@dunHsdKDgLhZed+)gfJ2$CfEg-'J1fIYs)[H76`",V,(X<s#(ZHOZ8q7#/_If&#_4hcTW3+=1UYL.TE"t'i$4Gq!!&_/"PEbSUY$dCS;@K$/14^W`!Lse^IkpmY:5<U-eJj[("e,jUt@WYB\4T_s#$(8fPoLC]*3^.j2J-o0err`K*pF4#(T_+o7pG!>M,n$i-l#`VX`SB(K$3k%JC!VkJI=C9\@,4$.q>lHpJ<o7@HH)XkF%%jYbR*=P+9Xf`(rofDlqHoEKgRbdMP(rb]e_f_ejo-O,)g`rSO:[0V<GorUSufN*6M=/jh%%Y/?lA0'$]5-VpN"<&DOP1[BK&qFuSW$06&d_8q*@J'd8!$a?`8lpo*J<&8?mho.34?/b&J@X<aJ1W)O)V?P54kP#3f`%D`%g[]46li,ob%r?J$@r-:^QD"Cl`_6Jd)qUlJ@X>3q[9qAfBagKb-,cM%Y4PLTM:MGA\p?M=AVWDC=rB5fI)GUb'DWc6J29%J=I!t>1a*!/hkE$f_!g$<!n.GL!%I%d<7ImfML46fQPn_Z!PSXREBF"J8*[8+7p'Gof<2*fM^?WfHo0IM^lk6J5?_W<-QUm]l,%Ej;J5QI?Wip:>!/1prWkm%UfmA*nW#ibr>fU=3B0\H<2#?J?[[LGBCS&rhdgo1CjhCK`+5Y`6"&.DqJLNin-`Qb/c<[Wn>EOO4]BC&Nq.bUoO%[1/gksl\+Gkb<1<g=dc@#f?jlcb%;4/;qQYu"+W/ZfR7W2J.pR.Z[5gYeCa.-&%MdmQNhs^BEsVX6k=gLk^%aU*(2gH"/:G\ACqLTf]Cl1Rg=OFKUQqU=1X#M&qCuG5,SJ+7B+kP[i2UR&^c,up=RYfJ:8/5InJr4A6gD.ash4(5hQ'I=4h!72)#Af3fD?^k%D=anYuFt:h!/IT!R(a^461`T)P,"^An66i*utAS9R[?"+\MGfRB78fTFf)?OMC@C!XMIQM`Z"8D*Q7RFn@gQe32.%p+_BrWC;&!!@ho!ihFf#ZCj/'^Q.]":sQt"9;@'$itq_E!kn6#jWHE,Qn.7!LF(M_[Idn#lt/0!!!!(z!!!#%z!!!"^!!!"^!!!"^!!!"^X2?(\;Zm4)"9]&+"9e3m!e^XY=9JZ[MZSP7$i=<>"N(8qbR&o0*X)BAloY?^!e`0-Qr=+j;Zm41":PS2'GLS"kQCqi'M8K2^f(@=%HJ30":a]0/-3Kg!J1Fo49D97"9\iHgB8!b!OQeSpeq:u!sA`0j9,O;"9H+8=9JZ[qZ;ER!J=ba"ks(=KE6^5?j>ou!SdpLRpZ9oqZ5IW#KpKZDZg*b"9\dZg]QJ5"BYd-KED>[RfV:G!S^ub#Eo4Bg]b;t?ieFO!Sdjj_dEWEquP"E%"oZ/%\sKf"9O6/X%6.l"</$XE"(b0/JJ=-;Zm4+"9\dn,U<E*"Of@V'HJ_-!J=,u;Zm4K!JCWT"9_g0!NZA+EriWN#l=a("9kT?#Q.-rErioV$B#$l"9HG[]E,bM]E,A?!OP&l!ON"!"9\b6!k;/3(/k>=j?*\-!TXXi"lrWV%)`7d%HIP@!J1G*9F\%%gJe3<!L-7c9FgA6gGAqq"<1;Gb?IqF>QTfk>[.CN":a*iA8h[8G>eVIP;smV7g'M01^"#I%>+dY1]a4*G#JMH\5NM5"9I9Z"9\j0e,k:*!PJU:P6-C?"8cI.#L`_'g^^r(?jadP!R(\1e/f*YliXm%!e`06^f(@=;Zm4,"9\eGdfGh7!Po`c,Q`lDr$2Cao)ZQ0j:(Ya$']$&1Ch>3#h0hF#)iT%N=G6%":_.-!p3DaJ5ZRRZjk1\!OMh-!ON7#!OMmD!NZQr!OMll$/5K6F9R;)!Q8mZ!)j"'!J1FW!X&o?"9J6""9]-*"9G])!e^XY])gsq!SdeYKEPB[?iuSo!TXFMlX0k]K)sa2#5_d3!R(SgbR1-e/dD4\"9\dZg]Gi$"BYd-]`\Ac!Rq5Qb?tS(])g[q$EIP:*_ZUY$KMDUKJ!G0;Zm4)^B=[?"04fj6iioJ4:stDT0*4V4=iSq"9^h!">g.o"7B(jY#>H+*@q<o,S%-p"=sSi[n]j)Zq:H&;Zm4(,Qn.>ZkNP"Ad=h4#J:8j!OrZ1&*+]]"OmIkN>rA>o*EhH"<00#)a"1[><G"N"9\o""9d:S4ECP1]Pq?`$DR_)"9HG["<dfQLJn<Y"9I9Yj9,Tf"9H+8"d8uJg]<UH?j2_p!Sd^>]3l&r"9H^K"9O6p!O#E):f@K")]TBHe.(^H*!*)I!P\a?"Oe>1"<7H1!fp7_)]T!]#f?cJ*!@O+qud%ZLJn<YKGiPK'AOK1r_iq&!W*!#"<;5s"9_t0"9_\("9^hb4:D7r!V9MX$aToa"=-BS49S>'"=+*n/49Mj9EB_Jf2DeT"p+u2"VM:P!!!!Xz!!!#9!!!!(!!!!*!!!".!!!#5!!!#-!!!#-!!!#-!!!#-!!!#7!!!#7!!!#9!!!#9!!!#9!!!#+!!!#+!!!!N!!!!@!!!"(!!!!b!!!!M!!!"&!!!#1!!!#1!!!#3!!!#3!!!#3!!!"1!!!!]!!!"&!!!"G!!!!k!!!".!!!"c!!!!p!!!",!!!#-!!!"o!!!"%!!!"-!!!#+!!!#/!!!#/!!!#2!!!"/!!!")!!!#@!!!":!!!"&!!!#V!!!"C!!!"(!!!#h!!!"J!!!"'!!!$!!!!"Q!!!"-!!!#/!!!#3!!!#3!!!#3!!!#+!!!#+!!!#5!!!$=!!!"`!!!",!!!$M!!!"e!!!"&!!!$W!!!"l!!!"+!!!#+!!!$g!!!"r!!!"(!!!#-!!!#-!!!#-!!!#-!!!#q!!!#+!!!%(!!!#(!!!".!!!%2!!!#.!!!"-X+;2i;Zm4)"9\d^"9G/o!h`HpaAW3E!sA`/=9M<>F*n)n!JCSd!N^*YU_![aHk+=,"42F;"9GrYaAW3E"9GS-"9\j0U]JsI!PJU:])gCa!TRPl"ks'RX9%?h?jG-]!NZ=^qd9c[PQ@9V"nWiF!osfd"9I")"i+%>]`\A3!NZD)"9_g0!P8B>!sA`0!NZ=OX'bslP6'/<#HM5;#L`^\U^*r.?jG-]!NZO,P@+[.quN;j$+q;h%($K1"9I")"Sbmu"<@mR!O`CH;Zm4+*!?Ab*!?;!"9^Rb"E\^4]PnA8!UBjj"9FI#P]-Zh^a'$`"9a)Q"9X0Q!Q\1B!Oa6Z;Zm4+*@q=)2$>H5bR]p@"9G.t$G6esj9kf#Ym%35N";EZ6O(1/,RhV-":4(:ZU[ps!Tk@'%1eC#%YOlB**!sm!O`t\;Zm4+;Zm5Q;Zm58!NZ=RX9;W.?icGl!NZZ]K4#+Wg]<oG%C@/c#_WNN"9I")!T6lZ8d#1@;Zm5N"9\dVX9$fQ"BYd-#0R%se-ETn?id;/!NZd#_dESAdfHNN"e/m/"hXl+Zin#_/dqR]"9\bT%(e2l"N1:f_0cd2!rI?GHi]IR?jrf("?[*f"9Fa*!Q\1BErgpsk@4WW"9FG^P].,5!JCRV!JCS!Hi]sh!Od@];Zm4+;Zm4=$j6V2":PDR&**jNe5Qb0"9Fi$"FL7&"9;@'HuKD8Y>YQ,E&.Ut;Zm5NHisM;$EQ@2P\(6W@g8_9S,n9MN<6`q"9dcdN,T8Z+aaCn;Zm4+"9\eo"3)Zd";FH2".rKp)[leSBI+>q<?)\U$j*R?"9\b6!Zk8C!#l(az!0.$Z!!`K(!#>P7!([(i!&"<P!$VCC!(R"h!/pmX!/pmX!/pmX!)3Fn!%n6O!([(i!0dH`!0dH`!1!Tb!1!Tb!+u93!&srY!(m4k!0R<^!0R<^!0R<^!0dH`!0dH`!.=hI!+#X*!([(i!/pmX!/pmX!!iQ)!6"p<!-%u=!([(i!0.$Z!0.$Z!0.$Z!0@0\(]XO9"9PU/N!N>b:Ct__"9]U,49<f-"9_g0"FP9,!JGN9E"C+pKF[p-F90,W%eC(PC]o-)%u^W7C^pZV.1Y-K"PaEEX9"Aug]Yh2bQ5Q]X:MrQ]E*utC^?dCX)%gQ!L,\W#+I_k/-_#?e/eXD,R"#T"9a*)"9\^'"oA9u"9]YP'ENdg&ekVPRfj&i"=.pm)urn?";Fi=N!'k(!PJU:"9F_iS-/ss"9H+8#L`^4S-=gY?jG-]!K72?X'c1]ZN69q"RBFtDZg)o"9\b<"9\^'"p#cD!!!!&z!!!""!!!!(!!!!7z!!!!P!!!!>!!!!h!!!!^!!!!GzWj`cE#Qt83"=+&Q*!?;-"9H1=/9=bn1iln)NX_H\F<"flUKdi7>QA"84EG$9CiEkePmOJo":au("9]lY]EBBW%Kl&*X9\>r#G`dRO&QL?bR<J4_@#W5Zj-F/N<SAEis`R$!Pq_A*!*BF,ZFf/MdQS'#.,'K9Foo"F=mUdL^4+d"9F/V"9\b=!OMq3])e-!!K7-^"9Fbj"7#uHZj5>n?j=dT!JC^4qd9ZXdfG[6!W-70#0R%SN!5DQ;d`N)*W_LQ%^ZGYZn;g3#Qt82X9FP""-cCn%T<K5LJn<Y;Zm4(P6;"1!W3'$$j:64!!I-A!!!!*z!!!!&!!!!9!!!!"!!!!T!!!!Fz!!!!]!!!!#zz!!!!#!!!!GWlc1Z;Zm4)#1N^Q!e;'i=Ao>*])e]1!Ls8nPQY(k!PJU:UB-kf"g_S=!L!PSU]m5q?jG-]!L*bWP@+NGqZ32i#)cjkDZg*""9\bD"9XHY"?9<_"9`KC$j!X:+&`:FE!1dr"QKUnK*2m-%NKEj$iu4g])e]1!L*]f"9H1==9JYpdfH6IPZ(rj?jG-]!Ls>RlX1+L$iu:hj9)2!/ck;?"9\bD!qQCj/-HnC%C97iE"9bg":s9E"9^,O/1^gR"9G%r!OaOs;Zm4+"9\a[S-0m3"9^:`9Fau("9_g0"EX_K">k1Ilu3Ac%K$>6$02-%$FC9/oE0bY!N:AQKEM."bQ5']ZiZ^#quMf]KEB@+&%j:o<."cF$e,7EKEheD]FCA@Hi^,H$iC.>_[*&\HiSO&_0cO3#.&[XHi]IR?j,4X"?['U"9F0o!KL(]@gim<"9]Bk!<KZ.!!!*Mz!!!0&!!#.^!!#^n!!%*@QNR9g"9\e+$j7DG":P<i'FYur"9^Rb"9;@'$itq_&e#)q$M+B/$j7Ph$l/sh"9\b6`"#]KErsPp#m([&!!!BPz!!&_n!!&ep!!&epz!!&Yl!!&Yl!!&Yl!!&Yl!!&_n!!&_nPTg)-"9\e,"9tMt#FJEmE!!WS!P8J.gB:Jpe6HqsE!M"!&2XN#9ag#=6j*PM`#]BKbRUEV"ACEY"+UX[])e-!!K7-^"9Fbj$&]+rO9*!i[K4#D"9\i."9^Cais(SN"<.aR$k`s^DutXp#Qt8M"9\nT"9[R\]Pn/:#Qt82#h/stPSO\o"9IQeg]RYC!PJU:dfJ5,!rH@1#Km//e-c(\N,Jh"#Qt83*E36Q!qQP."<.Z[>?h3Q2.R)q>Qb1C":)"[>Q>$4bQMTBE!OhoX9HOQ"0?)E#NGuh"Oq5p!K@5p"9]*k"9a5\!PEA-^^(&G]F)gc!o*bV!PAf8!PAHL!L*f;!PAGt"HrkFHih2ne/emK/h@D9"9\bL"9]JG"9\u9]EA^C"?^`+`,Gg:_Zthq!R,Kh+T]4Y#Qt85"9\kk"9a6R,]En0+Tdl2>8.bS"9\n'$1f8F]Q=1e]E3li"9Gq3L'Rnb;Zm4(U`9MD>pKORALmst"9\j@!TYYV"9Fbj"IfGQj9;#\?j3k;!Rq@t!fV%#LBn"c=TgP_#E&^A)[&9B"9_,3"9GY2!R=UHPlq-K"9\i.g]EE:!PJU:dfJ5,"d<=!#.jqqg]`UD?ig-*!TXEBb?tSPS,q+?#Flh<$-WOj"9ON7!RD#SPlq-K"9\i.Munq??id;0!TX^-K4#1QKE9R5#5fMC"3_)L"9ON7!hT`$49P_A"9\b<j9"0D!L3cg!sA`0!fR2>P@+gjgB$@G"G:(_DZg*j"9\dbF9AZOF9H8W*#rC'Cht@""9^RbirgM6"</$Z'G;)n^BarF%Z:Gl"9H/S!LF&p])h7$!TX@a"9Fbj"HrlQj9,9e?j,3b!Rq79PTC@jN"#Uf!fS`6N`-&`"9IQag]RYC!PJU:gB$(4"litq#L`_/j9CNM?jG-]!TXHkj'VtAe,e&%!otC2"S<5#"9ON7!WH"#pJV1t8d#D%"9\b<"9YN"!q0%j!!#%[z!!">G!!!6(!!!6(!!"_R!!$U2!!%fT!!%fT!!%fT!!!l:!!!T2!!"_R!!">G!!">G!!">G!!">G!!$I.!!$I.!!$I.!!)'[!!"kV!!")@!!"_R!!%rX!!#@d!!";F!!#^n!!&Yl!!'/%!!'5'!!'5'!!'5'!!'5'!!$.%!!"kV!!"_Rz!!$p;!!#(\!!"_R!!%rX!!"DI!!"DI!!"DI!!"DI!!$I.!!$I.!!$I.!!$I.!!"PM!!"hU!!$7(!!$7(!!&2_!!$R1!!"_R!!(7D!!$d7z!!';)!!'5'!!(4C!!(4C!!">G!!"DI!!"DI!!"DI!!$I.!!$I.!!)Bd!!%BH!!!Z4!!)lr!!%]Q!!#Ig!!$I.!!$I.!!$I.Sfn(6"9\e,"9]iG":(l(Qr=@Q;Zm4,;Zm4'":PL%'EeOVHNXAF"9]Y`,QWK"**"6u!PBBP"9uXE"9]]'"9m.N"NXLEQr=+j;Zm4)";D*>%I>>cKOtChWt'dcX=O\[N<>[O*!`8?"9HC[LBX1^"G9AK9EDt'T0reQ<%LuL"9_[9"9Q)3Es-7]*!@3#"H-J(G>eVIJ5ZRRa90Tg"?\RC>]*ICUK\"of/."@S8:OnZiRW>]FEp1&$-!B!Kf34#j_ullNRKf^aoTi"ADJi"9_+<!i$6(%.kK4o34m^#I=O6"9_\C"4M0e"?\A]!LH^f>;Q`#"De1pj9,rk"9H+8Plq-C!TX@a]3klEK)sa4!L$mn!UKj2g^',cKJ$L;;Zm4)"S2ZG!gFWt#)!9+r!TlD1CO*g$A:68%E&:d"RHTi">g.=9EDm26mMn/%T<K5'Oa[7;Zm?$;Zm50"9I:c!Sdf[dpN4"P6'GE!LmHtDZg*b"9\dZ"9a0PPQBB7J-r@\_[sH]"<0H,6mMml4:`DG0ER:c;Zm4c"9I:B!Sdf[j'W,@lN,cA!lJCK$'YJ7lj91'/e.F^"9\dZ"9]cEUB7Yu"<.aNo34m^#4hru">j(s9E\TG"AAqA"9_+<"9]35g]?;2"BYd-])gsq!SdeYZX=$edfJM1"RBG#"HrlAbQEK**X)*9$iCI8KJ!_0;Zm4);Zm4=j9,M7"9H+8KED>["9I9Z!Rq6S"9H1=#L`_'e-u4^?j2Gh!e^^Rb?tIZdfJM1!R"jU%>t8BbQ61#*Wu<@$HrV%KJ!GH;Zm4)/.;U+"C<oN"9^Ole,dlo!PJU:"9I9\!Rq6Sqd9ZXRfV:L"I!3tDZg*b"9\dZ"9GZ(!e^XY])gsq!SdeYj9/Qf?j2_p!e^a;gL(6_P6'G?%\mD;DZg*b"9\dZKEB_'"BYd-X9/S.!OMt1MZc.`!PE@RE"%p5ZigEJgB8Z#8HH1*%J'V-!PnfD$_%1(li7'nZjZI,ZiRuDX:)oHZiQBllN)Y>"/B6,`,>d#;Zm4()$'l3!!!!Qz!!!"D!!!">!!!"8!!!":!!!!#!!!"2!!!!2!!!!.!!!!U!!!"@!!!"@!!!"8!!!!D!!!!6!!!!`!!!!N!!!!;!!!!]!!!"4!!!"J!!!"J!!!"J!!!">!!!"@!!!"@!!!!f!!!!Q!!!!Z!!!"<!!!"<!!!"3!!!!Z!!!![!!!"A!!!!b!!!!\!!!"D!!!"D!!!"U!!!!j!!!!W!!!"<!!!#Q!!!":!!!":!!!":!!!"<!!!"<!!!"o!!!""!!!!W!!!">!!!#(!!!"*!!!![!!!"8!!!#8!!!"3!!!!Z!!!"4!!!#J!!!"@!!!!X!!!"6!!!"8!!!"8!!!#h!!!"I!!!!]!!!#t!!!"Q!!!!Z!!!$/!!!"^!!!!WWfdJb;Zm4))$C?r'EYTD'c[>q"9\j@'<DmY!Q,b-"9]dQ.0U2[*>L7[!!!!'z!!!!#!!!#)!!!#+!!!#)!!!!CX7dh>;Zm4)+Tqor!ojC4,Qo&3!n1@!J5ZRR;Zm4+";Cm@$PW^]"<7HQ,]Em=/0"d$E!1dr":+-Ir$2<#!L3cg"9J,toE53.?j#]q!W31tP@+Ti"9Iiq"9PB;!iT$#peq:u6iuBTKL>q^]E,JKU]eU:$.K1hO[KSQbQHW$"p;dP"<7TG!i&F7"9]ZC#09^GW)Eg%!sA`-!W3"p"9Fbj&#03%r"$DI?j<Y4!UKuR!i0`;OAc8b>>.]rgdD4m"B6WU>]9e7\5NM5)Jipe"k.!mA7P_O!LX,?;Zm56"9]),quWYr!L3cgdfK@L"I!3u$F9f0qui3k?j))_!UL-Y!i0`;%T<K5]`\B.!W3'$"9Fbj#L`_Gr"$,A?k3&7!UKrq!i0`;cr1&M)K]d!$OaU`j(nb,"<2Fa>BC&0"De.g"9a)t"9\-l!i,o$Plq-c!i,r"P@+[fgB%3R!g@!s"1&%+liES`*Y&#J"Om\CUb3#(;Zm4)"9\c*":*RXr'40`!L3cg!sA`0!V?Gh"9H1=#3u>doDt^p?j,cr!W2tnX'bst"9Iin"9PB;!J")O])mWg!W3'$"9Fbj]`\B.!e^[Wj'W,@dfK(J%c^q%#(lsSr!VOm?js@B!UL/_!i0`;cr1&M#O>%h9O%Ud!LX21#O>?""De+,";"K7!T6lZn5BGm;Zm4.%>4eL;ut;J"AV>f\HUGM!fK_Q<!4.>"nPqtdlBg$^B=ZCdo99I;usN5LJn<Y!K9DI"AE&G<!6_Wdo6Gn>QMA=Qr=+j+\W">S.!gL!h<j4Ti;*RKF>EnZj`0/]EO5pN=:aO<!D%X"fkj,!)j"'\5NM5Ft>0H"<7TG"=,fL"9^h4"9^>U"9R.Q"D1R8KQ%$g+`mhfHii=2I!c&9"9ki1!hWBo)e9#.#)$LiC^'E7"k,J2TMksr>?"Q)":PQg"?]p7"9`6\ZiSfX#79`("=+er"9G)1!rl1%&dH61"624+4A5dD!LX/0IT0!?"k-.="AAj,"L_53!)j"']`\A+!Mfi!"9FbjErjbn!SdfG%"q;qjDYNc^B=Z?"9I9Ye,d;eN!bdM!RqSb.1N(W"LJB?!KR92&(CX0!Q#<4"cNl&!K@KJ%H@\H!Pnfd!rE#J!L*VT!MfbGZX=!4"9F_m"9IS%!madJ^/G.;!i,r%djtVF1]b,j)a"1[><G"N/49[5"9m7749<2"\HUGE"9^gfquVpX!L3cg!e^[ZKEM=f?j;5b!W3.cMdQb$"9Iii"9PB;"P6QT])mWg!W3'$"9Fbj#L`a-KEebj?ie^X!W3ItP@+EL"9Iiu"9PB;"K,0$!M9L2!o*g0oO\-2#0\=pF9.=V!Q>>g!UL!N!K@-8HisqL$[`(#I!bt*quek[!L3cg!sA`0!i,mn]3kj?UB19"%'*bF%#b5RX:=53/d71<"9\e%%ZFdoA-'FJ\HUGmU^!n$b[rC,#5h^4S884a$o(Bb%"nf^>Q]q0!LX#4R7h(4Hus`:dr]\\F9/oUR0D&]"9`fI*!+np"=tf$1iNPl"<f#n)_;'N;Zm4+A6]/$!V?Dh!P&SC;Zm4C"9\n#quWYr!L3cgZN?p*$bKdN$+g69liD`HUi-A:;Zm4)dnBhh9ECOb#E0&g6j]Z$`%2,RquOG8PXJge>Zsf0%-.`E6j2"c6ijh+)b^=n;Zm4+A,l[sz2?3^W63$uc63$uc63$uc6i[2e!WW3#1]RLU2?3^W2?3^W2?3^W2?3^W)ZTj<&c_n3.KBGK6i[2e.0'>J)ZTj<)uos=;ucmu3rf6\+ohTC+ohTC9E5%m9E5%m9E5%m9E5%m4obQ_4obQ_4obQ_4obQ_<r`4#0`V1R)ZTj<AH2]13<0$Z.KBGK<WE+"<WE+"<WE+"<WE+"I/j6I70!;f*rl9@63$uc8cShkOT5@]:B1@p)uos=T`>&m=9&=$,ldoF4obQ_4obQ_4obQ_4obQ_2?3^W=9&=$4obQ_2uipY2uipY3WK-[`rH)>BE/#4*WQ0?:&k7o:&k7o:&k7o:]LIq:]LIq9E5%mhZ*WVFT;CA-NF,H6i[2e6i[2e6i[2e6i[2e2?3^W;ucmu<WE+"<WE+"=9&=$=9&=$=9&=$;?-[s;?-[s;?-[s;?-[s2uipY2uipY2uipY2uipYH2mpF2?3^W2?3^W)#sX:OT5@^,ldoF,ldoFUAt8p.KBGK2uipY6i[2e7K<Dg:B1@pX8i5$,QIfE>6"X'Z2ak*-NF,HB)ho3\GuU1+ohTCFT;CA_#OH9/-#YMK`D)Qa8c2@+TMKB;?-[s;?-[sQN.!ce,TIL.KBGK63$uc63$uc63$uc6i[2e6i[2e4obQ_4obQ_4obQ_])Vg2iW&rZ/-#YM`rH)>kl:\a,ldoF9E5%mz!ijQeJ5ZRR"9Gk4"9\b=!P8BN"9H.<]EA8#?j!/)!Q5#^b?tM.dfHfV!R"jU#L`^\ZicM"?jG-]!PAW+UL41nbQ4dM#.tu_"RHNW"9IR9;ufi""9_g0"FL:S<-&(nE!cCE$B,"EP]-tn!Ls8n]*)A[!MjZD^B=c%MufFL^]_"Ge-!&YAdl<W"oJo'!N6$P%I=+K!ON9*X?-j?KE7)9".X`GlN3k1!!.`]%Jp0Z!Pnei"QKN9KE7<b$A2:Y6jeQS!MjW:Lf4EZ_Z\0b"<;@_!TXX$#35r@Uh0_Yj9+`X$nO1@!Q>Gb$&er`!K@ALb6/"H">k'$"9]kn/-1>*1aE244E)MJOAc8b"9H.9"9\aj!P8BN"9Gk4"9\b=!TX=c#L`^\`!,1/?jG-]!TX=:gL(5LgB"qg!o%)d#1EUcX9-:I*X_fG#Q+i)!TYjIa&<*De.LI:$H*Vt%T<K5"Bkp:)\`@K>8.bS"9\bs"<8O_'Efse"9\iB"9_4n"9_4n!<Kr6!!!9:!!!*$!!"/Bz!!#Ff!!#"Z!!"VO!!"bSz!!!'#!!%?G!!#:b!!"VOzz!!!0&]=],_='r\101\97\du3\50',S=bit32.bnot,Q_=function(M,M,m,U,x)local S=(M[0X21][m]);M=#S;for m=122,288,60 do if m==242 then S[M+3]=0x7;break;elseif m==0B1111010 then S[M+1]=x;continue;else if m~=0X00b6 then else S[M+0B10]=(U);continue;end;end;end;end,Z_=function(M,M,m,U)(U[0X2D][M])[U[0X2d][M+0X1]]=m[U[0X2d][M+2]];end,II=function(M,M)local m=M[15](M[0B100101],M[0X1]);(M)[1]=M[0X1]+4;return m;end,vI=function(M,M,m)m=M[0X671C];return m;end,K_=function(M,m,U)m=(-4294967062+((M.CS((M.TS((M.TS(U[14762],(U[8642])))-U[24503],(U[4044])))+U[8357]))-U[0X33A9]));(U)[7425]=m;return m;end,m=pcall,xI=function(M,m,U,x)(U)[0x2a]=(function()local S,O;S,O=M:PI(U);if S==-0b10 then return O;end;end);if not(not m[0x14e__D])then x=(m[5357]);else x=3149767680+((x-m[0X52b3__]==m[0X68F4]and m[21785]or m[2235])+m[0X68F2]-M.X[9]-m[0X52__b3]+m[0x20A5]);(m)[0X14Ed]=(x);end;return x;end,W_=function(M,m,U,x,S)local O,j=#U[0X2D],58;while true do if j==0X7C then M:p_(O,U,x);break;elseif j==58 then j=M:c_(S,U,O,j);continue;else if j==0B1010001 then j=0X7c;U[0B101101_][O+0X2]=m;end;end;end;end,d_=function(M,M,m,U)M=U[53]();m=(0X1);return m,M;end,cI=function(M,m,U,x)if m>25 and m<0x70 then m=M:GI(U,x,m);else if m>34 then m=M:mI(x,m,U);else if m<0X19 then m=M:OI(x,U,m);return 54612,m;else if not(m<0x22 and m>15)then else M:pI(x);return 0x040A3,m;end;end;end;end;return nil,m;end,zS=bit32.bxor,Q=unpack,z_=function(M,M,m,U)M=U[0B1011__00](m);return M;end,h_=function(M,m,U,x,S,O,j,K,f,N,B,G,T,e,z,u,p,i,d,V,A,W,w)local s,h;while true do if K==63 then z=(T-m)/0B100__0;break;elseif K==0X60 then N=(u-S)/0X8;K=(0X3f);continue;else if K==126 then K=0B1000101;x=(j%0X8);elseif K==0B101010 then K,A=M:d_(A,K,V);continue;elseif K==0B110111 then K=(0x2a);T=V[0x0__35]();elseif K==1 then K=(108);m=(T%8);else if K==69 then K=(0X60);w=(j-x)/8;elseif K==0X5b then S=u%0x8;K=126;elseif K==108 then K=(91);j=V[0X35]();else if K~=0X38 then else K=0X37;u=V[0X3__5]();continue;end;end;end;end;end;if V[53]==x then else s,h=M:x_(f,d,w,V,S,N,B,m,z,G,p,U,A,e,i,O,x,W);if s==-2 then return j,A,-0X2,N,x,S,m,w,z,T,K,u,h;else if s==-0B1 then return j,A,-1,N,x,S,m,w,z,T,K,u;end;end;end;return j,A,nil,N,x,S,m,w,z,T,K,u;end,GS=function(M,M,m)m=(M[0x7660]);return m;end,PS=bit32.rrotate,DI=function(M,m,U)U=(-0x2+(M._S((M.TS((M.CS((M.CS(M.X[0B101]))-m[0X1718])),(m[0X80a])))<=m[0X68f2]and M.X[0X1]or m[0X3ba4])));(m)[26868]=(U);return U;end,A=function(M,M,m)M=(m[0X2f97]);return M;end,lS=function(M,m)m[0X20][0B1010]=M.QS;end,e=string.packsize,kI=function(M,M)M=1;return M;end,PI=function(M,m)local U,x,S;for O=29,0X66,0X1d__ do U,S,x=M:RI(O,m,S);if U~=-0X2_ then else return-2,x;end;end;return nil;end,N=function(M,m,U,x,S)(S)[0B10111]=nil;(S)[0X18]=(nil);U=(0B1100001);while true do if U==97 then U=M:K(S,x,U);continue;else if U~=76 then else(S)[23]=(m[M.T]);S[0X18]=m.copy;break;end;end;end;(S)[0X0019]=(9007199254740992);S[0B11010]=M.R;return U;end,N_=function(M,m,U,x)(m[0B100000_])[0X6]=M.I;if not x[7425]then U=M:K_(U,x);else U=x[7425];end;return U;end,WI=function(M,m,U,x)local S;(U)[0x22]=nil;(U)[35]=nil;x=(112);while true do S,x=M:cI(x,m,U);if S==16547 then break;else if S==54612 then continue;end;end;end;U[36]=(function(M)local m=0;M=U[0X1_B](M,"z",'\x21!!\z\33!');local S,O=#M-0X4,{};local j=U[0Xa__]((S/0b101)*0b100);for K=0X5,S,5 do local S=U[0x8](M,K,K+0B100);K=(O[S]);if not(not K)then else local M,f,N,B,G=U[0X16](S,0X1_,0X5);local T=((G-33)+(B-0X21__)*0X55+(N-0b100001)*0X1c39+(f-0B100001)*0x95e_ed+(M-0B0100001)*52200625);K=(T);(O)[S]=K;end;U[0x17](j,m,K);m+=0B100;end;return j;end);U[0B100101]=nil;(U)[0B100110]=nil;return x;end,T="wri\116\101\11732",u_=function(M,m,U,x,S,O)local j;if not(O>0Xc)then U=m[0X2A]()~=0X0;(m)[0X5]=(U);else j,S=M:w_(O,S,m,U,x);if j~=-0X1 then else return-0X1,S,U;end;end;return nil,S,U;end,P_=function(M,m,U,x,S,O,j)if S>0X59 then j[0x2D][m+3]=(x);return m,40538,S;else if S<0b1100100 then m,S=M:R_(j,U,O,m,S);return m,0XD9f1,S;end;end;return m,nil,S;end,jI=function(M,M,m)M=(m[29032]);return M;end,RS=string.char,_S=bit32.countlz,z=coroutine.wrap,f_=function(M,m,U,x,S)local O;U[0B100111]={};local j;x=nil;m=(nil);for K=0X6,0B1__0010,3 do O,m,x,j=M:M_(x,j,m,U,K);if O==53192 then continue;else if O==-0x1 then return-0X1,S,x,m;end;end;end;S=(nil);return nil,S,x,m;end,L=function(M,m,U,x)local S;x[0x1__5]=(nil);m=0B1100_001;repeat S,m=M:i(x,U,m);if S~=0X5cF_9 then else break;end;until false;x[0X16]=(nil);return m;end,iI=function(M,M,m,U)m=(0x3E_);M[0x5]=U;return m;end,n_=function(M,M,m,U)(U)[m]=M-M%0X1;end,x=coroutine,g=function(M,m,U)m=(-4294967038+((M.CS((M.QS((M.CS(M.X[0X7])),U[21171],U[0x3bA4]))-U[21785]+U[0X970]))-U[0X1718]));U[2235]=m;return m;end,mI=function(M,m,U,x)m[33]=nil;if not x[0x68F2]then U=(0B010011011+((M.QS((M.hS((M.xS(M.X[0B1],(x[15268]))),x[2416]))==x[0X3dAB]and x[543]or x[3599],x[15268]))-x[0X52b3__]-x[0xe0f]));x[26866]=(U);else U=(x[26866]);end;return U;end,m_=function(M,M,m,U,x)local S,O;for j=0b111110,0B1100111,0B101001 do if j<0X67 then S=(U[0x21][x]);else if j>0X3e then O=(#S);end;end;end;if U[0X3B]==U[0B100010]then U[0X28__]=(0X4E);end;(S)[O+1]=m;(S)[O+0X2]=(M);S[O+0X03]=(0B100);end,P=error,v=math,pS=function(M,m)local U;m[0X20][0X16_]=M.v.floor;(m[0X20])[0X1_0]=M.S;for x=0B00100111,0x12__4,0B1011101 do U=M:OS(x,m);if U==15113 then break;end;end;U=0B1110110;while true do if U==0X76 then U=(93);m[32][7]=M.oS;elseif U==24 then(m[0X20])[0XB]=M.e;break;else if U==0x5d then m[32][0X8]=M.zS;U=(0X18);end;end;end;end,V=string.byte,j_=function(M,M,m,U,x)if U<0XB4 then if not(m>=0x7B)then x=(true);else x=M[0x33]();end;else if not(U>0X64)then else return 8804,x;end;end;return nil,x;end,FS=bit32.lshift,oI=function(M,M,m,U)M=m[0X10](m[0B100101],m[1]);U=(0B110100__1);return U,M;end,VI=function(M,M,m)M=(m[0X2246]);return M;end,r=unpack,XS=function(M,m,U,x)m[0X20][0B1010__1]=M.sS;if not(not U[32660])then x=(U[32660]);else x=M:aS(U,x);end;return x;end,s_=function(M,M,m,U,x)(M)[m]=(x[39][U]);end,G_=function(M,m,U,x,S)local O,j;for K=0X33,172,25 do O,j=M:D_(m,S,j,U,K);if O==29954 then continue;else if O==51823 then break;end;end;end;(m[0B101_101])[j+3]=(x);end,U_=function(M,M,m)m=(0X1A);if M[0B111]==M[0B101000]then return-0X1,m;end;return 57636,m;end,M_=function(M,m,U,x,S,O)local j;if O<=0B1001 then j,U=M:v_(S,O,U);if j~=0XE_5Ac then else return 53192,x,m,U;end;else j,x,m=M:u_(S,m,U,x,O);if j~=-0X1 then else return-0B1,x,m,U;end;end;return nil,x,m,U;end,hI=function(M,m,U,x)if U==0X18 then(m)[41]=M.z;if not(not x[0x2246])then U=M:VI(U,x);else U=(-0B10101110+((((M._S(M.X[0X6]-M.X[0X9]+M.X[0B1000]))>=x[0X57E1__]and M.X[0b1]or M.X[0B10])>=x[30838]and x[0X1718]or x[0X21__F])+x[0X5__7E1]));x[0X2246]=U;end;return 18202,U;else if U==0b1010 then(m)[0B1010__11]=(function()local S,O=(0X0049);while true do if S>20 and S<0B1100011 then O=m[0XE](m[0B10010__1],m[1]);S=(0B10100);continue;else if S>0X49 then return O;else if not(S<0x49)then else S=M:TI(S,m);end;end;end;end;end);m[0X2c]=M.s.create;return 60337,U;else if U==0X17__ then U=M:xI(x,m,U);return 18202,U;end;end;end;return nil,U;end,I=string.len,y_=function(M,M,m,U)if not(M>0XA1)then if m[36]~=m[0X14]then U=m[0B110010]();end;else for x=0X52,0X5B,0b1__001 do if x>82 then else if x<91 then if not(M>=0X00D8)then U=m[0X30]();else U=(-m[0X2_A]());end;end;end;end;end;return U;end,i_=function(M,m,U,x)(x)[0X38]=(function()local S;S=M:J_(S,x);return S;end);if not m[0X3_A2F]then(m)[8642]=(-4294967267+(M.hS((M.CS((M.xS((M.QS((M.zS(m[8774]~=m[0X68F2]and m[0X33A9]or m[4044])),m[543])),(m[9639]))))))));U=(0B101+((M.VS((M.hS(M.X[0x1],m[0X80A],m[2161]))-m[3599]-m[543]-m[21269]))<=M.X[0B110__]and m[15268]or M.X[0X7]));(m)[0X03A2F]=U;else U=M:b_(m,U);end;return U;end,yI=function(M,m,U)U=nil;local x=0X55;repeat if x==0X30 then U=m[0X2A]();break;else if x==0B1010101 then x=M:eI(x);continue;end;end;until false;return U;end,JI=function(M,M,m,U)m=U[0X2c](M);return m;end,t=function(M,m,U,x)(m)[2]=type;if not(not U[0X3Dab])then x=(U[0x3DAB]);else(U)[0X370E]=3661296801+((M.CS((M.CS((M._S(M.X[0x9]+M.X[0X2__]))))))-M.X[0X3]-M.X[9]);(U)[0X5__3__15]=-3221217246+(M.CS((M.QS((M.FS((M.QS(M.X[3],M.X[0X6])),(15)))+M.X[0x6__]-M.X[0B11],M.X[0X4],M.X[2]))));x=-296283191+((M.VS(M.X[5]+M.X[0x1]))+M.X[2]+M.X[0X7]-M.X[0X2]-M.X[0X2]);(U)[0X3DaB]=x;end;return x;end,SI=function(M,m,U,x)(U)[0x2e]=(4503599627370496);if not x[0X7168]then(x)[0X25A7]=(-0X9+((M._S((M.CS((M.zS(M.X[2]>=M.X[0X7__]and x[32707]or x[4044]))>=m and M.X[5]or x[0X59c0]))))+x[0X2F97]));m=-2319903750+(M.CS(((M.VS(x[0x2F97]-M.X[0x8]-x[21269]))>=M.X[9]and m or x[0X370E])~=x[0X006__8f4]and M.X[0x7]or x[0x2422]));x[0x7168]=m;else m=M:jI(m,x);end;return m;end,b_=function(M,M,m)m=M[0X3A2_f__];return m;end,D=string,cS=function(M,m,U)m[0x4e92]=0x24+((M._S((M.FS((M.CS((m[0x66da]<=m[10820]and m[10971]or m[0X0171_8])+m[0x3__9aa])),(m[0X3BA4])))))>m[26866]and m[0x57E1]or m[14461]);(m)[7369]=0X9+((M.VS(m[22497]+m[0XFcC]-m[0X2__5a7]-m[8642]+m[0X4AaE]))+m[9639]);U=(-2486592318+((M.QS((M.hS((m[5357]>U and m[22976]or m[19118])>=m[0X7__876]and m[2161]or M.X[0x3],M.X[0B11],m[30304]))+m[0x2f97]))+M.X[0X7]));(m)[0x363f]=(U);return U;end,Z=function(M,m,U,x,S)(S)[0X7]=(function(...)return(M:M(...));end);x=nil;(S)[0X8]=nil;S[0X9]=(nil);U=8;repeat if U==0X7a then S[0X9]=M.m;break;else if U==8 then x=buffer;if not m[0X52B3]then U=(-1975063368+((M._S((M.CS((M.FS((M.PS(m[0X5315],(m[15268])))>=M.X[0x1]and M.X[0X5]or m[3599],(U)))))))>=U and m[0X551_9]or M.X[0B111]));(m)[0x5_2B3]=U;else U=M:f(U,m);end;continue;else if U==0B1000111 then S[0X8]=M.G;if not m[30838]then m[0X155D]=(-9852629139+(((M.QS(M.X[0X1],m[0X5519]))==m[14094]and m[21269]or M.X[0X4])+M.X[0B11]+M.X[8]+m[15787]+M.X[0X9]));m[5912]=-4294967123+((M.CS((M._S((M.xS((M.TS(M.X[0X5],(m[21269])))+M.X[0X8],(m[0x5315])))))))-m[0X3DAb]);U=(0XDEc4+(((M.hS(((M.CS(U))>=U and m[0X52b_3]or M.X[8])>=m[0X3Ba4]and m[0x52b3]or M.X[1],m[15268],m[0X5519]))<=M.X[0B111]and m[0X002422]or m[0x242__2])-M.X[0X1]));m[30838]=(U);else U=(m[30838]);end;continue;end;end;end;until false;(S)[10]=(x[M.l]);S[0Xb]=(x[M.O]);(S)[0XC]=nil;S[0Xd]=(nil);return x,U;end,E_=function(M,M)M[0X27]=nil;end,L_=function(M,m,U)(m)[0x11e6]=-0x45067926+(M.PS((M.CS((M.PS((M.QS(M.X[0X4]))-M.X[0X9]-m[0X52_6c],(m[32272]))))),(m[0X1Cc9])));U=-3200778126+(M.PS((M.hS((M.hS(m[10971]+m[0x3dAb]-m[0X7639],m[0X57E1])),M.X[0X1],m[30265]))+m[0X39aa_],(m[0X68f2])));m[26083]=U;return U;end,QI=function(M,M,m)M[38]=(m.readstring);(M)[39]=nil;end,H_=function(M,m,U,x)local S;for O=0Xc,0b0011_011001,0X69 do if O~=0X7_5 then else S=m[0B11000_1]();break;end;end;local O,j=S/0X2,(37);repeat if j<0X40 then if S%2==0 then M:n_(O,U,x);else U=m[0X31]();local M=m[0b110001]();for m=O-O%1,U,0x1 do(x)[m]=M;end;end;j=64;else if not(j>0B100101)then else U+=0X1;break;end;end;until false;return U;end,H=bit32,i=function(M,m,U,x)if x==0X61 then(m)[0x13]=M.Q;m[0X1__4]=({});if not U[0x57e__1]then x=M:b(U,x);else x=(U[0X5__7e1]);end;else if x==76 then(m)[0B10101]=M.F;return 0X5cf9,x;end;end;return nil,x;end,DS=function(M,m,U,x,S)m={};if m==S[0B1110_10]then else(S[32])[18]=M.PS;end;if not(not x[10971])then U=(x[0X2aDb]);else U=M:dS(U,x);(x)[0X2aDB]=(U);end;return m,U;end,q_=function(M,m,U,x,S,O)local j;for K=0B1010100,284,0b1_100100 do if K==184 then(O)[0B101101]=O[0X2c](S*0X3);continue;else if K==0B1010100 then U=O[0X2c__](S);else if K~=0x011C then else for K=1,S,0B1 do U[K]=O[0B111101]();end;end;end;end;end;for S=1,#O[0b101101],0X3_ do M:Z_(S,U,O);end;m=nil;for S=0B1001000,0x8A,47 do j,m=M:A_(S,m,U,x,O);if j==0x724a then continue;else if j==0X72D7 then break;end;end;end;return m,U;end,J_=function(M,M,m)local U=m[0B110100]();M=nil;for x=0X3B,0X0060_,0X1 do if x==0X3B then M=m[38](m[37],m[0X1__],U);continue;else if x==0b111100 then m[0x001]=m[1]+U;break;end;end;end;return M;end,CS=bit32.bnot,hS=bit32.bor,I_=function(M,m,U,x,S)if not(U<0B1111000)then U=(119);S=M.o;else m=x[42]();U=106;return U,0X3e7C,m,S;end;return U,nil,m,S;end,F_=function(M,m,U,x,S,O)if O[0X1C]==m then else if O[0X5]then M:Q_(O,m,U,x);else S[U]=O[0X21][m];end;end;end,OS=function(M,m,U)local x;if not(m>0X27)then M:lS(U);else x=M:mS(m,U);if x~=0XC4F_c then else return 15113;end;end;return nil;end,A_=function(M,m,U,x,S,O)if m==0X77 then(O)[0X021]=M.o;return 0X72D7,U;else if m~=0X48 then else if not(S)then else local m=(0X3E);repeat if m>0X5 then m=0b101;(O[32])[2]=(O[33]);continue;else if m<0b111110 then M:k_(O,x);break;end;end;until false;end;U=x[O[0x34]()];return 0x724a,U;end;end;return nil,U;end,uI=function(M,M,m)m[0x3b]=nil;(m)[0x3C]=nil;(m)[0X3d]=nil;M=(nil);return M;end,VS=bit32.countrz,q=function(M,m,U)U=(-0x13+(M._S((M.PS((M.zS(M.X[0X2]+m[5469]-m[30838],m[0X5315]))>=M.X[0X4]and m[0x2422]or m[2416],(m[0X05315_]))))));m[2058]=(U);return U;end,O="\u{0072}ea\u{64}\u{075}8",dS=function(M,m,U)(U)[25214]=(-1678780202+(M.hS((M.zS((M.FS(U[0x763_9]+U[4044]+U[19118],(U[24503])))<=M.X[0X8]and U[0X970]or U[26334],U[0X3daB])),M.X[0B10])));U[0X27C5]=(99+(M.FS((M.PS((M._S((M.VS((M.hS((M.VS(U[15787])),U[543],U[0X80A__])))))),(U[15268]))),(U[8642]))));m=(-0X16+((M.hS((M.CS((M.hS(U[8120],M.X[0X7],U[32272]))))))+U[14094]+U[14895]~=M.X[0X2]and U[14762]or U[13225]));return m;end,k_=function(M,M,m)(M[0B100000])[0X3]=m;end,o=nil,YI=function(M,M,m,U,x)if m==0X0 then return-2,m,U,x;else if m>=M[0B101000]then m-=M[6];end;end;U=(0X6);return 0XA2F9,m,U;end,s=table,LI=function(M,M)return M;end,GI=function(M,m,U,x)U[0X23]=(setfenv);if not(not m[0X68F4])then x=(m[0X68f4]);else x=M:DI(m,x);end;return x;end,X={56987,1678780198,511528886,4018895989,2776298295,3658562135,1975063439,2172436501,3149767801},C="re\u{061}\100i3\z 2",B_=function(M,m,U,x)local S;if U~=0x67 then m=x[0X38]();return 0x2Ad9,m,U;else S,U=M:U_(x,U);if S==0Xe1_24 then return 36303,m,U;else if S==-0X0_1 then return-0x1,m,U;end;end;end;return nil,m,U;end,f=function(M,M,m)M=(m[21171]);return M;end,o_=function(M,m,U,x,S,O,j,K,f,N,B,G,T)local e;e=(nil);local z;for u=87,0X60,3 do if u==0X5d then m=M:JI(K,m,U);elseif u==96 then f=U[44](K);S=({});if U[6]==U[0x32__]then else(j)[0x1]=(T);end;else if u==0B1__011010 then T=M:bI(U,K,T);else if u==0b1010111 then G=U[0X2C](K);continue;end;end;end;end;(j)[0B111]=(m);B=(0X2C);while true do e,B,z=M:NI(x,K,j,U,N,f,G,B,O);if e==42192 then break;else if e==13166 then continue;else if e==-0x1 then return G,m,T,-1,B,S,f;else if e~=-2 then else return G,m,T,-2,B,S,f,z;end;end;end;end;end;for u=0X1,K do local p,i,d,V,A,W,w;W,A,w,V,d,p,i=M:a_(i,p,W,V,d,A,w);local s,h,g,E;s,g,E,h=M:X_(s,E,h,g);A,d,e,h,w,W,V,s,g,i,E,p,z=M:h_(V,O,w,W,S,A,E,N,h,x,f,i,m,g,p,G,T,j,U,d,u,s);if e==-0x2 then return G,m,T,-0x02,B,S,f,z;else if e~=-1 then else return G,m,T,-0b1,B,S,f;end;end;end;N=U[0x34]();z=(nil);for x=19,0X86,0B11__011 do if x==0x13 then z=M:z_(z,N,U);else if x~=46 then else j[8]=(z);for x=0B1,N do O=U[52]();if U[0X27][O]then M:s_(z,x,O,U);else e=O/0X4;K={[0B10]=O%0X4,[0B1]=e-e%1};(U[39])[O]=K;(z)[x]=K;end;end;break;end;end;end;return G,m,T,nil,B,S,f;end,gI=function(M,m,U)while U[20]do local x=0X54;repeat if x==0X54 then U[54]=U[0X3b];x=0x2_3;else if x~=0B100__011 then else return-0X1;end;end;until false;end;repeat return-0x2,(M:LI(m));until false;return nil;end,O_=function(M,M,m,U)U[m]=(m+M);end,D_=function(M,M,m,U,x,S)if S<0X4C then U=(#M[0X2_D]);else if S>0X4c then M[0X2d][U+0X2]=m;return 51823,U;else if not(S>0x33 and S<101)then else M[0X2_D][U+0x1]=(x);return 0X7502,U;end;end;end;return nil,U;end,rI=function(M,m,U,x,S)if x<30 then m=(0);elseif x>0X1E then return m,-0x2,S,m;else if not(x>5 and x<0X37)then else S=0X1;repeat local x;x=M:yI(U,x);m+=((x>127 and x-0X80 or x)*S);S*=128;until x<128;end;end;return m,nil,S;end,ZI=function(M,m)m={M.o,nil,M.o,M.o,nil,nil,nil,nil,nil,nil,M.o};return m;end,B=function(M,M)M[6]=(4294967296);end,__=function(M,m,U)if m>0XE then return-2,-0B1001101;else if m<0X8C then while U[42]do return-0B10,(M:C_());end;end;end;return nil;end,lI=function(M,M,m)M=m[0X33a9];return M;end,d=function(...)(...)[...]=nil;end,b=function(M,m,U)(m)[4044]=(0x19+(M._S((M.FS((M.PS(m[14094]-M.X[3]+m[5912]-m[30838],(m[15268]))),(m[21269]))))));U=(0B0010010__11+((M.xS((M.PS((M.hS(m[5469]==m[0X3BA4]and m[0X1718]or m[0X24_22],m[0X370e])),(m[0X2__F97]))),(m[0X2f97])))+m[21171]<m[0X970]and m[3599]or m[0x5315]));m[0X57E1]=(U);return U;end,NI=function(M,m,U,x,S,O,j,K,f,N)local B,G;if f<0x0052 and f>44 then(x)[0b110]=(N);f=0x5;elseif f<32 and f>0b101 then f=M:iI(x,f,j);return 0x336E,f;else if f>32 and f<0X3e then if S[0X3c]~=S[0X6]then else B,G=M:gI(U,S);if B==-0b1 then return-1,f;else if B==-0X2 then return-0B10,f,G;end;end;end;f=0b11011;return 13166,f;else if f>0X3E then x[0XA]=m;return 42192,f;else if f<0X2c and f>27 then f=M:KI(f,x,O);return 0X336e,f;else if not(f<0X1b)then else f=(0B100000);x[3]=(K);end;end;end;end;end;return nil,f;end,c='\114e\97\z  d\105\049\54',sI=function(M,M,m,U)if m~=5 then M=U[0Xd](U[37],U[1]);m=(0B1__01);U[0X1]=U[1]+0X2;else return M,-0X2__,m,M;end;return M,nil,m;end,T_=function(M,M,m,U)(U)[M]=(M-m);end,S_=function(M,m,U,x,S)local O;if x<0B1110111__ then M:Y_();return x,0x50__5_0,U;else if not(x>0X6A)then else x=(0X6a);if not(S<=101)then for j=0B110__0100,268,0x50 do O,U=M:j_(m,S,j,U);if O~=0x2264 then else break;end;end;else U=m[0x37]();end;return x,0Xe76F,U;end;end;return x,nil,U;end,W="re\97\u{064}\u{075}\x31\u{36}",E=function(M,m,U,x,S)if not(m>0X7)then(S)[0b10001]=U.readf32;return 0X51De,m;else(S)[16]=(U[M._]);if not x[2058]then m=M:q(x,m);else m=x[0x80A];end;return 24507,m;end;return nil,m;end,QS=bit32.band,R=tostring,C_=function(M)return 178-0x8e<-0B1101_0001;end,c_=function(M,M,m,U,x)x=(0x51);m[0X002d][U+1]=(M);return x;end,pI=function(M,M)for m=0X0,0B11111_111_,0X1 do M[0X14][m]=M[0X3](m);end;end,F=bit32.bxor,bI=function(M,M,m,U)U=M[44](m);return U;end,k=function(M,m,U)m=(-511528881+((M.TS((M.CS((M.CS((M._S((M._S(m)))))))),(U[21269])))+M.X[0b11]));U[12183]=(m);return m;end,tI=function(M,M)return M;end,x_=function(M,m,U,x,S,O,j,K,f,N,B,G,T,e,z,u,p,i,d)local V,A;G[d]=x;(K)[d]=(N);(u)[d]=j;for W=0X007C,0X125,0x50 do if not(W>0X7c)then(T)[d]=(e);if S[0X2]==p then for T=14,0B11001100,0X7e do V,A=M:__(T,S);if V==-0X2 then return-0X2,A;end;end;elseif f==0X3 then M:F_(N,d,U,z,S);elseif f==0B11__0 then K[d]=N;elseif f==0X0 then if j==S[55]then M:V_();return-0B1;end;(K)[d]=d+N;elseif j==S[0x3B]then(S)[54],S[0b110111]=-0x2C/S[40],S[0X2];(S)[0X2]=(0b1011101);elseif f==0b111__ then M:T_(d,N,K);elseif f==0X5 then local K,f=0B1__011001__;while true do f,V,K=M:P_(f,d,N,K,z,S);if V==0Xd9F1 then continue;elseif V==0x9__e5a then break;end;end;end;continue;else if W==0x1_1C then if i==3 then M:l_(x,m,S,U,d);elseif i==6 then G[d]=(x);elseif i==0B0 then M:O_(x,d,G);elseif i==0b111 then G[d]=d-x;elseif i==0X5 then M:W_(d,S,x,m);end;break;else if O==3 then if not(S[0X5])then B[d]=S[0X21__][j];else local m,x;for K=63,0xEE,0x36 do if K==0X75 then x=#m;break;else m=S[0B100001][j];continue;end;end;if S[0X30]~=S[0X6]then m[x+0x1]=(U);end;for U=0X37,0XA__d,118 do if U>0b11__01_11 then(m)[x+0X3]=5;elseif U<0B10101101 then(m)[x+0b10]=d;continue;end;end;end;elseif O==6 then(u)[d]=j;elseif O==0x0 then(u)[d]=(d+j);elseif O==0x7 then(u)[d]=d-j;elseif O~=0B101 then else M:G_(S,B,j,d);end;end;end;end;return nil;end,WS=function(M,m,U)m=(0X1e+(M.TS((M.zS((U[0X21C2]-U[21785]+U[22976]==U[12499]and U[0x21F]or U[22976])-U[32272],U[0x00671c])),(U[0x7E10]))));U[0X5__26__c]=m;return m;end,l="\z cr\z eate",n=getfenv,y=bit32.rshift,V_=function(M)return;end,a_=function(M,M,m,U,x,S,O,j)m=(nil);M=nil;S=(nil);x=nil;O=(nil);U=nil;j=(nil);return U,O,j,x,S,m,M;end,U=function(M,M,m)m={};M[1]=0X0;(M)[2]=nil;(M)[0X3]=(nil);(M)[0X4]=nil;return m;end,_I=function(M,M,m)m=M[32707];return m;end,eI=function(M,M)M=0X30;return M;end,Y=bit32.countrz,BI=function(M,M,m)M=nil;local U=(0x34);while true do if U<0B11__0100 then(m)[0B1]=(m[0X1]+0b100);break;else if U>3 then M=m[0X11](m[0X25],m[1]);U=(0B11);end;end;end;return M;end,RI=function(M,M,m,U)if M==29 then U=m[0x0B](m[0x25],m[0B1]);(m)[0X1]=m[0B1]+0X001;else return-0X2,U,U;end;return nil,U;end,J=function(M,m,U,x,S)local O;(S)[0X00E]=(nil);x=0B111111;repeat if not(x>=0X3f)then(S)[0XD]=(U[M.c]);S[0XE]=U[M.W];break;else S[0XC__]=M.p;if not m[0X2f97]then x=M:k(x,m);else x=M:A(x,m);end;continue;end;until false;S[0XF]=(U[M.C]);(S)[16]=(nil);S[0X11]=(nil);x=0X48;while true do O,x=M:E(x,U,m,S);if O==20958 then break;else if O==24507 then continue;end;end;end;(S)[0B1001_0]=(U.readf64);(S)[0B10011]=(nil);S[0X1_4]=(nil);return x;end,KI=function(M,M,m,U)M=(82);m[0b100]=U;return M;end,wI=function(M,m)m[0x36]=function()local U;U=M:BI(U,m);return(M:tI(U));end;m[0B110111]=(nil);(m)[56]=nil;(m)[57]=(nil);m[0B111010]=(nil);end,FI=function(M,m,U,x,S)(S)[0X2_7]=(nil);x=(0B10110);repeat if x<0X7d then(S)[0b00100101]=S[0X24_](M.h);if not(not m[0X7FC3])then x=M:_I(m,x);else x=M:CI(m,x);end;continue;else if not(x>22)then else M:QI(S,U);break;end;end;until false;S[0X28]=2147483648;S[0X29]=nil;S[0x2a]=(nil);S[43]=nil;S[0X2C]=(nil);x=0X1__8;return x;end,dI=function(M,m,U,x)(x)[0X1b]=nil;(x)[0x1c]=(nil);x[0X01d]=(nil);(x)[0B11110]=nil;x[0X1f]=nil;m=32;while true do if m<0X20 then x[0x1D_]=(function(S,O,j)j=j or 0B1;O=O or#S;if not((O-j+0X1)>7997)then return x[19](S,j,O);else return x[0X1C](O,j,S);end;end);if not U[543]then m=-0X63e18210+((M.xS((M._S(U[5469]))+M.X[0x8]-M.X[3]-M.X[8],(U[15268])))-U[0X8bB]);U[0x21f]=m;else m=(U[543]);end;elseif m>0x52 then(x)[0X1E]=M.P;(x)[31]=M.x.yield;break;elseif m>0X20 and m<0B1010__100 then x[28]=function(S,O,j)if not(O>S)then else return;end;local K=(S-O+1);if K>=8 then return j[O],j[O+0X1],j[O+2],j[O+0B1__1],j[O+0X4],j[O+0X05],j[O+0B110],j[O+0x7],x[28](S,O+0X8,j);elseif K>=0x7 then return j[O],j[O+0X1],j[O+0x2],j[O+0X3],j[O+0X4],j[O+5],j[O+0X6],x[28](S,O+0X7,j);elseif K>=0x6 then return j[O],j[O+1],j[O+0X2],j[O+0X03],j[O+0X4],j[O+0b101],x[0B11100](S,O+0x6,j);else if K>=5 then return j[O],j[O+1],j[O+2],j[O+0X3],j[O+0X4],x[0X1C](S,O+5,j);elseif K>=0X4 then return j[O],j[O+0B1],j[O+2],j[O+0B11],x[0X1C](S,O+0x4,j);elseif K>=0B11 then return j[O],j[O+1],j[O+0X2],x[0X1_C](S,O+0X3,j);else if K>=0B10 then return j[O],j[O+0x1],x[0X1C](S,O+0x2,j);else return j[O],x[0X1C](S,O+1,j);end;end;end;end;if not U[22976]then m=M:aI(U,m);else m=U[22976];end;else if m<0X0__052 and m>0b1001 then x[0X1B]=M.D.gsub;if not U[0x66DE]then m=M:XI(U,m);else m=U[0X66de];end;end;end;end;x[0B100000]={};x[0X21]=(nil);return m;end,OI=function(M,m,U,x)m[0X2__2]=({});if not(not U[13225])then x=M:lI(x,U);else x=(-28492+(M.PS((M.hS((M.zS((M.QS(U[0X5_519]))))+M.X[0X1],U[0x59C0]))-U[21269],(U[21269]))));U[0X33A9]=x;end;return x;end,TS=bit32.rshift,sS=math.modf,K=function(M,m,U,x)(m)[0X0016]=M.V;if not(not U[2235])then x=(U[2235]);else x=M:g(x,U);end;return x;end,oS=string.unpack,CI=function(M,m,U)U=(-3152207533+(M.CS((M.TS((M.PS((M.CS(M.X[4]+m[0X057E1]-m[0X68f4])),(m[0x5315_]))),(m[21269]))))));(m)[32707]=(U);return U;end,XI=function(M,m,U)(m)[8357]=-3149767690+((M.FS((M.hS(M.X[0B111__]>=M.X[0x9]and M.X[8]or M.X[6]))+m[0X97_0__]-M.X[0X9],(m[4044])))+M.X[0b1__001]);U=-5337342238+((m[12183]==m[2058]and m[2058]or m[0Xf_CC])+m[14094]+M.X[0b10]-m[0X52B3]-m[0x155d]+M.X[0B110]);m[26334]=(U);return U;end,v_=function(M,M,m,U)if m==0B100__1 then(M)[0x21]=M[0x2c](U);return 58796,U;else U=(M[0X34]()-72663);end;return nil,U;end,X_=function(M,M,m,U,x)M=nil;U=(nil);x=(nil);m=(0x38);return M,x,m,U;end,MI=function(M,M)local m=M[0x012__](M[0X25__],M[0x1]);(M)[0b1]=(M[0X1]+8);return m;end,u=function(M,m,U,x)U[0X5]=nil;(U)[0x6]=nil;x=(36);repeat if x==0b011000 then M:B(U);break;elseif x==0x33 then(U)[0x3]=M.RS;if not m[0X970]then x=(67+((M._S((M.VS((M.X[0B111]<=M.X[1]and M.X[0X7]or M.X[0x09])-M.X[0x009]))))-m[0x370e_]>m[14094]and M.X[0x1]or x));(m)[2416]=x;else x=m[2416];end;elseif x==0X24 then x=M:t(U,m,x);continue;else if x==118 then U[4]=(M.D.match);if not m[3599]then x=M:w(x,m);else x=m[3599];end;else if x==0B1011101 then(U)[0x5]=(nil);if not m[15268]then x=(-3149768013+((m[0Xe0F]-M.X[0X3]+m[0X005315]+m[0X3dab]>=M.X[0B1001]and m[14094]or M.X[0x9])+m[2416]+m[0X970]));(m)[15268]=(x);else x=m[0X3BA4];end;continue;end;end;end;until false;return x;end,HI=function(M,m,U)U[0x57cB]=(0b1011001+(M._S((M.FS(U[12183]+U[4044]-U[26866],(U[22976])))+U[2058]-U[2058])));U[19118]=-0B10001_00+((M.PS((M.CS((M.zS(U[0X970],U[0X00871]))-M.X[0X1]<U[0x57E__1]and U[0X370E]or U[2161])),(U[26866])))>=U[0x7fC3]and U[0X57e_1]or U[0X20a5]);m=(0x2A__+(M.VS((M.hS((M.FS((M.zS(M.X[3]>U[21269]and U[0X2422]or M.X[0B10],U[0x2246],M.X[0X4]))-U[32707],(U[4044]))),U[0X0_021F])))));U[26396]=m;return m;end,AI=function(M,M,m,U,x)U=M[44](m);x=M[0X2C](m);return x,U;end,UI=function(M,m,U,x)(m)[50]=nil;(m)[0X33]=nil;x=0x77__;repeat if x>0x2c and x<0b1101010 then m[0B110000]=function()local S,O,j,K=(0B111110);while true do K,O,S,j=M:sI(K,S,m);if O==-2 then return j;end;end;end;(m)[0x0031]=(function()local S,O;S,O=M:nI(m);if S==-0B10 then return O;end;end);if not(not U[26396])then x=M:vI(U,x);else x=M:HI(x,U);end;continue;elseif x<0X41 then(m)[0B1100__10]=(function()return(M:II(m));end);m[51]=function()local S,O,j,K,f=(52);repeat if S<0X034 and S>6 then return f*m[0B11__0]+K;elseif S>0b11 and S<0B10110__1 then S=0X2d;elseif S>0x2d then S=(3);K,f=m[49](),m[0B110__001]();else if S<6 then O,f,S,j=M:YI(m,f,S,K);if O==41721 then continue;else if O==-2 then return j;end;end;end;end;until false;end;break;elseif x>0B1000001 and x<0X77 then(m)[47]=M.n;if not U[0X66da]then(U)[0X871]=-4844+((M.FS((M.zS((U[26866]>=U[0X33A9]and U[0X1__718]or U[0X20a5_])-U[26334],U[0x2246])),(U[0X25a_7])))-U[22497]-U[0x1718]);x=(-4294955215+(M.CS((M.hS((M.TS((M.zS((M.VS((M.zS(U[14094],U[0x68F2],M.X[0X6])))),M.X[0X9])),(U[0x2F9_7]))),U[29032])))));U[26330]=x;else x=(U[0X66Da]);end;continue;else if x>106 then x=M:SI(x,m,U);continue;end;end;until false;m[0x034]=(function()local U,S,O,j;for K=0B101,0b1110101,0X19 do O,U,j,S=M:rI(O,m,K,j);if U==-0x2 then return S;end;end;end);m[0B110101]=function()local M=m[0B00110100]();if not(M>=m[46])then else return M-m[0X19];end;return M;end;return x;end,fI=function(M,m,U,x,S)S=function(...)if m[0b111000]~=m[0x6]then else return-m[0X1C];end;return(...)();end;if not(not x[8120])then U=x[8120];else U=(123+(M.TS((M.QS((M._S(x[0x671__C_]+M.X[0B10]>x[10820]and x[0X59C0]or M.X[0X9]))>x[26330]and x[0X2a44]or M.X[0X9],x[8357],x[8357])),(x[0X2F97]))));x[0X1Fb8]=U;end;return S,U;end,r_=function(M,M,m)m=M[0X31_]();return m;end,p=table.move,p_=function(M,M,m,U)(m[0x2d])[M+0B11]=U;end,M=function(M,...)return(...)[...];end,j=math.pi,TI=function(M,M,m)(m)[0x1]=m[0X1]+0B10;M=99;return M;end,g_=function(M,m,U,x)U[32][0X14]=M.y;if not m[0x65e3]then x=M:L_(m,x);else x=(m[26083]);end;return x;end,w_=function(M,m,U,x,S,O)local j;if m~=0Xf then U=(x[52]()-0XC13C);else for m=1,O do local O,K,f=0x78;repeat if O>106 then O,j,f,K=M:I_(f,O,x,K);if j~=0X3e7C then else continue;end;else if O<0B110101_0 then if S then(x[0x21])[m]=({K,(x[0x002](K))});else(x[33])[m]=(K);end;break;else if f<=0X7B then local m=0X074;repeat if m==0b100001__1 then break;else if m==116 then m=(0X43);if not(f>87)then if not(f>0X1d)then K=x[0X2a]();else for m=0B101001,0b111001,0X10 do if m<0B111001__ then if f~=0X36 then K=x[0B101011]();else K=M:e_(K);end;else if m>0X0029 then end;end;end;end;else local m=0X77;while true do m,j,K=M:S_(x,K,m,f);if j==59247 then continue;else if j==20560 then break;end;end;end;end;end;end;until false;else local m=0X2A;while true do if m==0B1 then M:t_();break;else if not(f>0X9e)then for S=43,210,0X64 do if S~=0x8F then if not(f>0X80)then local S=0B11001_11;repeat j,K,S=M:B_(K,S,x);if j==0X02AD9 then break;else if j==36303 then continue;else if j==-0x1 then return-0X1,U;end;end;end;until false;else for S=0B001__1__1,224,0B1101001 do if S>0X7 then break;else if not(S<0X70)then else if f==158 then K=x[0X036]();else K=M:r_(x,K);end;continue;end;end;end;end;continue;else break;end;end;else K=M:y_(f,x,K);end;m=(1);end;end;end;O=(0x41);continue;end;end;until false;end;end;return nil,U;end,EI=function(M,M,m,U,x)M=nil;U=(nil);m=(nil);x=(nil);return U,m,M,x;end,qI=function(M,m,U,x,S,O,j,K,f)x=nil;U=(nil);j=(nil);O=(nil);m=nil;f=nil;for N=0x5f,0xA1_,11 do if N<=0X6A then if N>95 then if S[0B110110]==S[0B10100]then else(x)[2]=S[52]();x[0Xb_]=S[0x34]();end;U=(S[0x34]()-0X95__0B);continue;else x=M:ZI(x);continue;end;elseif N>0X75 then if N~=0X8B then m=S[0X002C](U);else f=M:kI(f);break;end;else O,j=M:AI(S,U,j,O);end;end;K=nil;return U,O,m,j,K,x,f;end,w=function(M,m,U)U[0X2422]=(-987531638+(M.TS(U[0X370e__]-M.X[0X8]+M.X[0X6]+m+M.X[0x5]<=M.X[0x08]and M.X[0x5]or M.X[0X7],(U[0X5315]))));(U)[0X5__519]=-0X641026Ec+((M.TS((M.CS((M.QS(U[14094]+M.X[0X7],M.X[9],M.X[7]))))+U[0X3dAB],(U[0X5315])))>=M.X[0X4]and M.X[0x1]or M.X[2]);m=(-6559736208+((M.CS(M.X[0B11]+U[0X970]+U[0x0370e]))+M.X[0X5]-U[14094]-U[0X3dab]));U[3599]=(m);return m;end}):a()(...);
]=====]

local Net
do
    local built = NET_CORE_BLOB:find("@@PASTE_LURAPHED", 1, true) == nil
    if built then
        local ok, mod = pcall(function() return (loadstring or load)(NET_CORE_BLOB)() end)
        if ok and type(mod) == "table" and type(mod.Fire) == "function" then
            Net = mod
        end
    end
    if not Net then
        -- Core not built (or failed to load): keep the suite alive but combat off,
        -- and nag so it's obvious this build wasn't finished.
        Net = { Fire = function() return false, "core-not-built" end }
        task.spawn(function()
            for _ = 1, 3 do
                pcall(function()
                    game:GetService("StarterGui"):SetCore("SendNotification", {
                        Title = "Velorix",
                        Text = "Combat core not built — paste the Luraph'd net_core.lua blob.",
                        Duration = 6,
                    })
                end)
                task.wait(5)
            end
        end)
    end
end

----------------------------------------------------------------------
-- Character / target helpers
----------------------------------------------------------------------
local function myChar()
    if LP.Character then return LP.Character end
    local live = Workspace:FindFirstChild("Live")
    return live and live:FindFirstChild(LP.Name)
end
local function myHum()
    local c = myChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function myHRP()
    local c = myChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function playerChar(plr)
    if plr.Character then return plr.Character end
    local live = Workspace:FindFirstChild("Live")
    return live and live:FindFirstChild(plr.Name)
end

-- The striking limb the server expects on our own body (R6 arms/hands).
local LIMB_ORDER = { "Right Arm", "Left Arm", "RightHand", "LeftHand", "Torso" }
local function myLimb()
    local c = LP.Character; if not c then return end
    for _, n in ipairs(LIMB_ORDER) do
        local p = c:FindFirstChild(n)
        if p and p:IsA("BasePart") then return p end
    end
    return c:FindFirstChild("HumanoidRootPart")
end

local function targetPart(char)
    -- Never default to Head â€” server angle check uses torso/HRP bearing.
    return char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("LowerTorso") or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChildWhichIsA("BasePart")
end

-- Part we face + measure angle against (center mass, not Head).
local function aimPart(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
        or char:FindFirstChild("UpperTorso") or char:FindFirstChild("LowerTorso")
        or targetPart(char)
end

-- RaycastHitboxV4 resolves against enemy limb parts â€” torso/arms, not Head.
local function pickHitPart(char, fallback)
    if not char then return fallback end
    return char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("LowerTorso") or char:FindFirstChild("Right Arm")
        or char:FindFirstChild("Left Arm") or fallback or aimPart(char)
end

local function isStunned(char)
    if not char then return true end
    return char:FindFirstChild("Stun") ~= nil
        or char:GetAttribute("HitStun") ~= nil
        or char:GetAttribute("WeaveStun") ~= nil
        or (char:FindFirstChild("Knocked") and char.Knocked.Value)
end

-- True while a character is in a weave i-frame window.
-- FOAB uses BoolValue (Value=true) OR a Highlight named "Weave" while dodging.
-- Is a character ACTIVELY weaving (i-framing) right now? Live-profiled: the precise
-- window is while the weave ANIMATION plays (~0.06â€“0.24s) plus the brief dash
-- BodyPosition. The game's "Weave" CHILD is unreliable â€” it appears late and lingers
-- for seconds, so keying off it would make us skip a target long after they're
-- vulnerable. So we detect by the weave animation set (+ BodyPosition for the start).
local isTargetWeaving
do
    local WEAVE_ANIM = nil
    local function weaveAnimSet()
        if WEAVE_ANIM and next(WEAVE_ANIM) then return WEAVE_ANIM end
        local set = {}
        local function scan(anims)
            local w = anims and anims:FindFirstChild("Weave")
            if w then for _, a in ipairs(w:GetDescendants()) do
                if a:IsA("Animation") and a.AnimationId ~= "" then set[a.AnimationId] = true end
            end end
        end
        pcall(function()
            local live = workspace:FindFirstChild("Live")
            local lc = live and live:FindFirstChild(LP.Name)
            scan(lc and lc:FindFirstChild("Combat") and lc.Combat:FindFirstChild("Animations"))
        end)
        pcall(function()
            local sc = game:GetService("StarterPlayer"):FindFirstChild("StarterCharacterScripts")
            local cb = sc and sc:FindFirstChild("Combat")
            scan(cb and cb:FindFirstChild("Animations"))
        end)
        if next(set) then WEAVE_ANIM = set end
        return set
    end
    function isTargetWeaving(char)
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:FindFirstChildOfClass("BodyPosition") then return true end   -- weave dash (start)
        local hum = char:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if animator then
            local set = weaveAnimSet()
            for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
                if tr.Animation and set[tr.Animation.AnimationId] then return true end
            end
        end
        return false
    end
end

-- FORWARD-DECLARED here, assigned further below. Helpers defined ABOVE their real
-- assignment (auraInterval â†’ S/jit; ensureFists/etc â†’ notify) reference
-- these as upvalues; without the forward decl they'd bind to nil globals and error
-- the instant they run (that was silently crashing the aura loop, and any notify
-- call from a function defined before line ~2634).
local S, jit, notify

-- Live Data Ping (ms). Falls back to 60 if the stats item isn't ready yet.
local function getPingMs()
    local ok, v = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and typeof(v) == "number" then return v end
    return 60
end

-- Aura spacing. DoPunch is gated by the game's OWN client debounce, so calls
-- sent early just no-op — our floor only needs to cover input dispatch. Firing
-- near the floor means the aura re-punches the instant the game's M1 debounce
-- clears, i.e. as fast as the game can actually swing.
local function auraInterval(fast)
    local base = math.max(S.auraDelay, 0.08)
    if fast then base = math.max(0.08, base * 0.5) end
    return jit(base, 0.08)
end

-- Fists equipped? The "Fist" tool sits in Character when equipped, Backpack when not.
local function fistsEquipped()
    local c = myChar()
    if not c then return false end
    local fist = c:FindFirstChild("Fist")
    if fist and fist:IsA("Tool") then return true end
    for _, ch in ipairs(c:GetChildren()) do
        if ch:IsA("Tool") and ch.Name == "Fist" then return true end
    end
    return false
end

local lastFistNotify = 0
local function ensureFists()
    if fistsEquipped() then return true end
    -- Auto-equip is OPT-IN. When off (default), we NEVER force-equip â€” we just report
    -- whether the Fist is already out, so the script never yanks the tool back into
    -- your hand while you're trying to unequip it.
    if not S.autoEquip then
        if os.clock() - lastFistNotify > 8 then
            lastFistNotify = os.clock()
            notify("Velorix", "Equip your Fist (or turn on Auto-Equip) for aura damage")
        end
        return false
    end
    local bp = LP:FindFirstChild("Backpack")
    local fist = bp and bp:FindFirstChild("Fist")
    if fist and fist:IsA("Tool") then
        local hum = myHum()
        if hum then pcall(function() hum:EquipTool(fist) end) end
    end
    return fistsEquipped()
end

-- Whitelist set (lowercased names never targeted)
local whitelist = {}
local function whitelisted(name)
    return name ~= nil and whitelist[string.lower(name)] == true
end

-- Display rigs that look like players but take no damage â€” skip for aura/farm/NPC scan.
local NPC_EXCLUDE = { Rig1 = true, R6_2 = true, R6_Animations = true, VisualizerNpcLol = true }

local function isNPCTarget(m)
    if not (m and m:IsA("Model")) then return false end
    if m == myChar() then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    if NPC_EXCLUDE[m.Name] then return false end
    if whitelisted(m.Name) then return false end
    local hum = m:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    if not m:FindFirstChild("HumanoidRootPart") then return false end
    return true
end

local function appendNPCTargets(seen, out)
    local roots = { Workspace, Workspace:FindFirstChild("Live") }
    for _, root in ipairs(roots) do
        if root then
            for _, m in ipairs(root:GetChildren()) do
                if isNPCTarget(m) and not seen[m] then
                    seen[m] = true
                    local hum = m:FindFirstChildOfClass("Humanoid")
                    local prt = pickHitPart(m, targetPart(m))
                    if hum and prt then
                        out[#out + 1] = { char = m, hum = hum, part = prt, plr = nil }
                    end
                elseif m:IsA("Folder") or (m:IsA("Model") and not m:FindFirstChildOfClass("Humanoid")) then
                    for _, sub in ipairs(m:GetChildren()) do
                        if isNPCTarget(sub) and not seen[sub] then
                            seen[sub] = true
                            local hum = sub:FindFirstChildOfClass("Humanoid")
                            local prt = pickHitPart(sub, targetPart(sub))
                            if hum and prt then
                                out[#out + 1] = { char = sub, hum = hum, part = prt, plr = nil }
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Gather candidate targets (players + optional workspace NPCs).
local function gatherTargets(includeNPCs)
    local out, seen = {}, {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local ch  = playerChar(p)
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            local prt = ch and pickHitPart(ch, targetPart(ch))
            if hum and prt and hum.Health > 0 and not whitelisted(p.Name) then
                seen[ch] = true
                out[#out + 1] = { char = ch, hum = hum, part = prt, plr = p }
            end
        end
    end
    if includeNPCs then appendNPCTargets(seen, out) end
    return out
end

-- Line-of-sight test from our root to a target part (ignores both chars).
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local function hasLOS(fromPart, toPart, tChar)
    local hrp = myHRP(); if not hrp then return true end
    losParams.FilterDescendantsInstances = { myChar(), tChar }
    local dir = (toPart.Position - fromPart.Position)
    local hit = Workspace:Raycast(fromPart.Position, dir, losParams)
    return hit == nil
end

----------------------------------------------------------------------
-- Settings + engine state
----------------------------------------------------------------------
S = {
    -- Smart Punch Aura
    auraPunch = false, auraRange = 12, auraDelay = 0.12, auraAll = false,
    auraMax = 4, auraLOS = false, auraNPC = true, auraSwing = true, punchAnim = false, auraLockOn = false, auraLockStr = 70,
    walkToNearest = false,      -- auto-chase: walk to the nearest player, stay locked until they die, then switch
    autoEquip = false,          -- OPT-IN: only equip the Fist for you if you turn this on
    auraHitWeave = false,       -- OFF: skip enemies mid-weave (i-frames), hit right after they finish
    noShake = false,            -- kill the game's camera shake (aura spam over-shakes it)
    -- Weave (Auto Weave + Perfect Weave)
    autoWeave = false, weaveRange = 18, weaveAnim = false, noWeaveCd = false,
    weaveCd = 0.45,             -- gap between auto-weaves (s); 0.45 = server WEAVE cd (always ready, no wasted fires)
    weaveFacing = false,        -- only weave if attacker is facing me (off = dodge everything)
    -- Automation
    autoGrab = false, grabRange = 10,
    autoStomp = false, stompRange = 12,
    autoPush = false, pushRange = 12,
    -- Movement
    walkEnabled = false, walkSpeed = 20,
    infJump = false,
    fly = false, flySpeed = 60,
    noclip = false,
    freecam = false, freecamSpeed = 1,
    -- Teleport
    tpTarget = "", tpSpeed = 60,
    -- Visuals
    esp = false, espColor = Color3.fromRGB(214, 31, 58),
    espNames = true, espHealth = true, espTracers = false,
    fov = 70,
    -- Utility
    antiAFK = false,
    -- Player: style / finisher unlocker (client-side forced equip)
    styleForce = false, styleName = "Katana",
    finisherForce = false, finisherName = "Neck Slam",
    -- Free gamepasses (client-side perk flags)
    freeGamepasses = false,
    -- Anti-fling
    antiFling = false,
    -- Fling
    flingTarget = "", flingPower = 120000, touchFling = false,
    -- Anti-Cheat bypass
    acBypass = true,            -- strip the server's "Exploiter" shame tag + neutralise client-read flags
    safeTP = true,              -- glide script teleports in bounded steps so the position AC never sees a big jump
}

-- Max studs the character may be MOVED by the script in a single replication
-- step before the server's position check would flag it. Legit sprint+fly tops
-- out well under this; the 1500-stud test jump that got flagged did not. All
-- script-driven teleports route through safeTeleport() and stay under it.
local SAFE_TP_STEP = 24

local E = {} -- engine control (start/stop hooks + transient state)

----------------------------------------------------------------------
-- Combat actions
--
-- This game runs BEHAVIORAL server anti-cheat ("abnormal combat activity"):
-- the signature makes packets authentic, but the server still flags inhuman
-- *timing*. So every action is jittered, spaced by the real cooldowns, and
-- the swingâ†’contact gap is modelled â€” never fire two related packets <1ms apart.
----------------------------------------------------------------------
jit = function(base, pct) pct = pct or 0.3; return base * (1 + (math.random() * 2 - 1) * pct) end

----------------------------------------------------------------------
-- Animation engine â€” plays the game's REAL M1 combo + weave animations on
-- our Animator so aura/weave look identical to legit play (and the animation
-- replicates alongside the combat packet, which also helps vs the AC).
----------------------------------------------------------------------
local Anim = {}
do
    local function animFolder()
        local live = workspace:FindFirstChild("Live")
        local lc = live and live:FindFirstChild(LP.Name)
        local comb = lc and lc:FindFirstChild("Combat")
        local f = comb and comb:FindFirstChild("Animations")
        if f then return f end
        local combat = game:GetService("StarterPlayer").StarterCharacterScripts:FindFirstChild("Combat")
        return combat and combat:FindFirstChild("Animations")
    end
    local folder = animFolder()

    -- The game keeps per-style animation folders (M1s.<Style>, Weave.<Style>) plus
    -- a Default, and drives combat from the one named by Server.Style.Value. Mirror
    -- that so the aura/weave plays the EXACT moveset of whatever style you have
    -- equipped (Katana, etc.) instead of always the fist combo.
    local function currentStyle()
        local ok, v = pcall(function()
            local sv = LP:FindFirstChild("Server") and LP.Server:FindFirstChild("Style")
            return sv and sv.Value
        end)
        if ok and type(v) == "string" and v ~= "" then return v end
        return "Default"
    end
    local function collect(sub, style, ordered)
        local out = {}
        folder = animFolder()
        local root = folder and folder:FindFirstChild(sub)
        local def = root and (root:FindFirstChild(style) or root:FindFirstChild("Default") or root)
        if def then for _, a in ipairs(def:GetChildren()) do
            if a:IsA("Animation") then if ordered then out[#out + 1] = a else out[a.Name] = a end end
        end end
        if ordered then table.sort(out, function(x, y) return x.Name < y.Name end) end
        return out
    end
    -- Per-style caches, built on first use for each equipped style.
    local m1sByStyle, weaveByStyle = {}, {}
    local function m1sFor(style)
        if not m1sByStyle[style] then m1sByStyle[style] = collect("M1s", style, true) end
        return m1sByStyle[style]
    end
    local function weavesFor(style)
        if not weaveByStyle[style] then weaveByStyle[style] = collect("Weave", style, false) end
        return weaveByStyle[style]
    end
    local cache  = setmetatable({}, { __mode = "k" })  -- animator -> {anim -> track}
    local function track(anim)
        local hum = myHum(); local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not (animator and anim) then return end
        local a2 = cache[animator]; if not a2 then a2 = {}; cache[animator] = a2 end
        if not a2[anim] then a2[anim] = animator:LoadAnimation(anim) end
        return a2[anim]
    end
    -- Play one track per category, stopping the previous one first and forcing
    -- it NON-looped. Without this the weave anims (which are looped) stacked and
    -- permanently froze the character. Auto-stops after its length as a failsafe.
    local playing = {}   -- category -> track
    local function playOne(cat, anim, speed, fade)
        local tr = track(anim); if not tr then return end
        local prev = playing[cat]
        if prev and prev ~= tr then pcall(function() prev:Stop(0.08) end) end
        playing[cat] = tr
        pcall(function()
            tr.Looped = false
            if tr.IsPlaying then tr:Stop(0) end
            tr:Play(fade or 0.1)
            if speed then tr:AdjustSpeed(speed) end
        end)
        local len = (tr.Length and tr.Length > 0) and tr.Length or 0.7
        task.delay(len / (speed or 1) + 0.05, function()
            if playing[cat] == tr then pcall(function() tr:Stop(0.1) end) end
        end)
    end
    local idx = 0
    local lastStyle = nil
    function Anim.punch(speed)
        local style = currentStyle()
        local m1s = m1sFor(style)
        if #m1s == 0 and style ~= "Default" then style = "Default"; m1s = m1sFor(style) end
        if #m1s == 0 then return end
        if style ~= lastStyle then idx = 0; lastStyle = style end   -- restart combo on style swap
        idx = idx % #m1s + 1
        playOne("m1", m1s[idx], speed or 1.5, 0.1)
    end
    function Anim.weave(dir)
        local weaves = weavesFor(currentStyle())
        local a = weaves[dir]; if not a then local _, v = next(weaves); a = v end
        if not a then return end
        playOne("weave", a, 1, 0.12)
    end
    -- Panic stop: kill any lingering aura/weave tracks (used on toggle-off/unload)
    function Anim.stopAll()
        for cat, tr in pairs(playing) do pcall(function() tr:Stop(0.1) end); playing[cat] = nil end
    end
    -- On (re)load, stop any of OUR anims a previous session left playing, so a
    -- prior stuck-weave freeze clears immediately without needing a respawn.
    task.spawn(function()
        local ids = {}
        local fRoot = animFolder()
        for _, sub in ipairs({ "M1s", "Weave" }) do
            local f = fRoot and fRoot:FindFirstChild(sub)
            if f then for _, a in ipairs(f:GetDescendants()) do
                if a:IsA("Animation") and a.AnimationId ~= "" then ids[a.AnimationId] = true end
            end end
        end
        local hum = myHum(); local animator = hum and hum:FindFirstChildOfClass("Animator")
        if animator then for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
            if tr.Animation and ids[tr.Animation.AnimationId] then pcall(function() tr:Stop(0) end) end
        end end
    end)
end

----------------------------------------------------------------------
-- Real-input combat driver
--
-- FOAB damage is server-side authoritative. Forged packets accept on wire but
-- deal zero damage. Trigger the game's OWN Combat handlers (Mobile UI / DoPunch)
-- â†’ animation â†’ RaycastHitboxV4 â†’ SecureFire. VIM does NOT reach UIS on this
-- executor (Rspy-verified); Mobile.Punch getconnections DOES fire Packet.A.
----------------------------------------------------------------------
local function mobileRoot()
    local gui = LP.PlayerGui:FindFirstChild("ScreenGui")
    return gui and gui:FindFirstChild("Mobile")
end

local function invokeMobile(btn, evt)
    if not btn then return false end
    local signal = btn[evt]
    if not signal then return false end
    if typeof(firesignal) == "function" then
        local ok = pcall(function() firesignal(signal) end)
        if ok then return true end
    end
    if typeof(getconnections) == "function" then
        local fired = false
        for _, c in ipairs(safeGetConnections(signal)) do
            if c.Function then pcall(c.Function); fired = true end
        end
        return fired
    end
    return false
end


-- REAL-INPUT driver (VirtualInputManager). Live-verified on this executor: VIM
-- reaches UserInputService, so simulated mouse/key/touch fires the game's OWN
-- InputBegan â†’ DoPunch/DoGrab/DoStomp/DoPush and the Movingâ†’PlayWeaveAnimation
-- weave (spy-confirmed genuine Packet.A, not forged). This is the primary combat
-- path â€” MOBILE included: touch devices tap the on-screen combat buttons (VIM
-- mouse/keys don't map to a touch device's binds), PC/console use VIM mouse/key.
local VIM = game:GetService("VirtualInputManager")
local WEAVE_KEY = { Forward = Enum.KeyCode.W, Backward = Enum.KeyCode.S,
                    Left = Enum.KeyCode.A, Right = Enum.KeyCode.D }
-- Only these three escape the block below (used by fireWeave/pressAction/realAttack);
-- the rest stay block-local to keep the main chunk under Luau's 200-register cap.
local deviceIsMobile, actionBind, fireInput
do
    local ACTION_DEFAULT = {
        Attack = Enum.UserInputType.MouseButton1,
        Grab   = Enum.KeyCode.G, Push = Enum.KeyCode.Q,
        Stomp  = Enum.KeyCode.F, Dodge = Enum.KeyCode.Space,
    }
    local MOBILE_BTN = { Attack = "Punch", Grab = "Grab", Push = "Push", Stomp = "Stomp" }
    function deviceIsMobile()
        return UserInputService.TouchEnabled
            and not UserInputService.MouseEnabled
            and not UserInputService.KeyboardEnabled
    end
    -- The real bind for an action (respects the player's own rebind in Server.<action>).
    function actionBind(action)
        local inp = ACTION_DEFAULT[action]
        local srv = LP:FindFirstChild("Server")
        local v = srv and srv:FindFirstChild(action)
        if v and v:IsA("StringValue") and v.Value ~= "" then
            inp = Enum.KeyCode:FromName(v.Value) or Enum.UserInputType:FromName(v.Value) or inp
        end
        return inp
    end
    local function vimTapKey(kc)
        VIM:SendKeyEvent(true, kc, false, game)
        VIM:SendKeyEvent(false, kc, false, game)
    end
    local function vimTapMouse()
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(960, 540)
        VIM:SendMouseButtonEvent(vp.X * 0.5, vp.Y * 0.5, 0, true, game, 0)
        VIM:SendMouseButtonEvent(vp.X * 0.5, vp.Y * 0.5, 0, false, game, 0)
    end
    local touchId = 0
    local function vimTapButton(btn)
        if not btn then return false end
        local abs, sz = btn.AbsolutePosition, btn.AbsoluteSize
        local x, y = abs.X + sz.X * 0.5, abs.Y + sz.Y * 0.5 + 36  -- + GUI inset
        touchId = touchId + 1
        local id = touchId
        pcall(function() VIM:SendTouchEvent(id, x, y, Enum.UserInputState.Begin) end)
        task.wait()
        pcall(function() VIM:SendTouchEvent(id, x, y, Enum.UserInputState.End) end)
        return true
    end
    -- Fire a combat action as REAL input. Mobile â†’ touch the button + fire its
    -- handler directly (never misses on touch); PC/console â†’ VIM the real bind.
    function fireInput(action)
        if deviceIsMobile() then
            local btn = mobileRoot() and mobileRoot():FindFirstChild(MOBILE_BTN[action] or "")
            if btn then
                task.spawn(function() vimTapButton(btn) end)
                invokeMobile(btn, "MouseButton1Up")
                return true
            end
            return false
        end
        local bind = actionBind(action)
        if typeof(bind) == "EnumItem" and bind.EnumType == Enum.KeyCode then
            vimTapKey(bind)
        else
            vimTapMouse()
        end
        return true
    end
end

-- Combat handlers pulled straight out of the game's Combat LocalScript.
-- Each mobile button's MouseButton1Up has TWO connections: the real handler
-- closure (which calls DoPunch/DoGrab/DoStomp/DoPush and holds that Do* function
-- as an upvalue) AND a cosmetic ButtonTweens size-tween closure (upvalues are a
-- GuiObject + TweenService, NO function). The old code grabbed the FIRST
-- connection, which was often the useless tween â€” so combatHook.Attack was
-- frequently the tween, not the punch. We now identify the handler by its
-- function upvalue and extract the RAW Do* function, so calling combatHook.Attack
-- IS a genuine attack (spy-verified byte-identical to a real click â†’ real damage).
local combatHook = {}
-- Extract the raw Do* function a button closure calls (its function upvalue).
local function rawHandlerFrom(sig)
    if typeof(getconnections) ~= "function" then return nil end
    local haveDbg = typeof(debug) == "table" and typeof(debug.getupvalues) == "function"
    local firstClosure = nil
    for _, c in ipairs(safeGetConnections(sig)) do
        local f = c.Function
        if f then
            firstClosure = firstClosure or f
            if haveDbg then
                local ok, ups = pcall(debug.getupvalues, f)
                if ok and ups then
                    for _, v in pairs(ups) do
                        if typeof(v) == "function" then return v end  -- the Do* handler itself
                    end
                end
            end
        end
    end
    -- No debug lib: return the first closure. It may be the tween, so callers
    -- also fall back to invokeMobile (which fires ALL connections incl. the real one).
    return firstClosure
end
local function captureCombatHooks()
    if typeof(getconnections) ~= "function" then return end
    local mobile = mobileRoot()
    if not mobile then return end
    local BTN = { Attack = "Punch", Grab = "Grab", Push = "Push", Stomp = "Stomp" }
    for action, btnName in pairs(BTN) do
        if not combatHook[action] then
            local btn = mobile:FindFirstChild(btnName)
            local sig = btn and btn.MouseButton1Up
            if sig then combatHook[action] = rawHandlerFrom(sig) end
        end
    end
    -- Weave button closures set the game's CanWeave state (identified by a table
    -- upvalue holding "CanWeave"); tween closures don't have it.
    local weave = mobile:FindFirstChild("Weave")
    if weave then
        local haveDbg = typeof(debug) == "table" and typeof(debug.getupvalues) == "function"
        local function weaveClosure(sig)
            if not sig then return nil end
            local first = nil
            for _, c in ipairs(safeGetConnections(sig)) do
                local f = c.Function
                if f then
                    first = first or f
                    if haveDbg then
                        local ok, ups = pcall(debug.getupvalues, f)
                        if ok and ups then
                            for _, v in pairs(ups) do
                                if typeof(v) == "table" and v.CanWeave ~= nil then return f end
                            end
                        end
                    end
                end
            end
            return first
        end
        combatHook.weaveDown = combatHook.weaveDown or weaveClosure(weave.MouseButton1Down)
        combatHook.weaveUp   = combatHook.weaveUp   or weaveClosure(weave.MouseButton1Up)
    end
    -- The genuine weave routine PlayWeaveAnimation(dir, dashCFrame): plays the weave
    -- anim, spawns the BodyPosition dash, and fires SecureFire{Type="Weave"} + the
    -- 0.45s cooldown. It lives in the Combat script's u83 table, held as an upvalue
    -- by the "Moving" RenderStepped closure. Calling it directly = a real,
    -- server-honored dodge (spy-verified Weave packet) â€” far more reliable than
    -- faking the dodge key + a movement direction the Fist controller zeroes.
    if (not combatHook.playWeave or not combatHook.state)
        and typeof(getconnections) == "function"
        and typeof(debug) == "table" and typeof(debug.getupvalues) == "function" then
        for _, c in ipairs(safeGetConnections(RunService.RenderStepped)) do
            local f = c.Function
            if f then
                local ok, ups = pcall(debug.getupvalues, f)
                if ok and ups then
                    for _, v in pairs(ups) do
                        if typeof(v) == "table" then
                            if typeof(rawget(v, "PlayWeaveAnimation")) == "function" then
                                combatHook.playWeave = v.PlayWeaveAnimation
                            end
                            if v.CanWeave ~= nil and v.CanAttack ~= nil then
                                combatHook.state = v
                            end
                        end
                    end
                end
            end
            if combatHook.playWeave and combatHook.state then break end
        end
    end
end
task.defer(captureCombatHooks)
local function onCharForHooks(char)
    task.delay(1.5, captureCombatHooks)
    Maid:Give(char.ChildAdded:Connect(function(ch)
        if ch:IsA("Tool") and ch.Name == "Fist" then task.delay(0.4, captureCombatHooks) end
    end))
end
if LP.Character then onCharForHooks(LP.Character) end
Maid:Give(LP.CharacterAdded:Connect(onCharForHooks))
task.spawn(function()
    while isCurrent() do
        if fistsEquipped() and (not combatHook.Attack or not combatHook.playWeave) then captureCombatHooks() end
        task.wait(4)
    end
end)

local function pressAction(action)
    -- PRIMARY: real simulated input (VIM on PC, touch/button on mobile).
    local ok = false
    pcall(function() ok = fireInput(action) end)
    if ok then return true end
    -- Fallback: call the game's captured handler directly.
    local fn = combatHook[action]
    if fn then pcall(fn); return true end
    return false
end

-- Direct M1 fallback: game M1 anim â†’ Swing on Start marker â†’ RaycastHitboxV4 â†’ Input on hit.
local RaycastHB = nil
pcall(function() RaycastHB = require(ReplicatedStorage:WaitForChild("RaycastHitboxV4")) end)
local punchBusy, punchCombo = false, 1
local PUNCH_LIMBS = { "Right Arm", "Left Arm" }

local function startHitbox(limbPart)
    if not RaycastHB or not limbPart then return end
    local hb = RaycastHB.new(limbPart)
    local hit = false
    local conn
    conn = hb.OnHit:Connect(function(hitPart, humanoid)
        if hit then return end
        hit = true
        Net.Fire({
            Type = "Input",
            Hit = hitPart,
            Humanoid = humanoid,
            Position = hitPart.Position,
            Limb = limbPart,
        })
        pcall(function() conn:Disconnect() end)
        pcall(function() hb:HitStop() end)
    end)
    pcall(function() hb:HitStart() end)
    task.delay(0.35, function()
        pcall(function() if conn then conn:Disconnect() end end)
        pcall(function() hb:HitStop() end)
    end)
end

local function directPunch()
    if punchBusy or not fistsEquipped() then return false end
    local char = myChar()
    if not char or isStunned(char) then return false end
    punchCombo = punchCombo % #PUNCH_LIMBS + 1
    local limb = char:FindFirstChild(PUNCH_LIMBS[punchCombo]) or myLimb()
    if not limb then return false end
    punchBusy = true
    -- Just long enough for the swing marker (~0.18s) + hitbox window to land.
    task.delay(0.25, function() punchBusy = false end)

    local swung = false
    local function swing(limbPart)
        if swung then return end
        swung = true
        Net.Fire({ Type = "Swing", Limb = limbPart })
        startHitbox(limbPart)
    end

    local playedAnim = false
    -- Only play the M1 anim when Punch Animation is enabled.
    if S.punchAnim then
        pcall(function()
            local combat = char:FindFirstChild("Combat")
            local m1root = combat and combat:FindFirstChild("Animations") and combat.Animations:FindFirstChild("M1s")
            local style = "Default"
            pcall(function()
                local sv = LP:FindFirstChild("Server") and LP.Server:FindFirstChild("Style")
                if sv and sv.Value ~= "" then style = sv.Value end
            end)
            local folder = m1root and (m1root:FindFirstChild(style) or m1root:FindFirstChild("Default") or m1root)
            local anim = folder and folder:FindFirstChild(tostring(punchCombo))
            local animator = myHum() and myHum():FindFirstChildOfClass("Animator")
            if anim and animator then
                playedAnim = true
                local tr = animator:LoadAnimation(anim)
                tr:Play()
                tr:GetMarkerReachedSignal("Start"):Once(function(limbName)
                    swing(char:FindFirstChild(limbName) or limb)
                end)
                task.delay(0.18, function() swing(limb) end)
            end
        end)
    end
    if not playedAnim then swing(limb) end
    return true
end

-- Attack priority: Punch Animation ON -> VIM / DoPunch (real M1 anim).
-- Punch Animation OFF -> silent Swing + hitbox only (no M1 / DoPunch anim).
local function realAttack()
    if punchBusy then return false end
    if S.punchAnim then
        local ok = false
        pcall(function() ok = fireInput("Attack") end)
        if ok then
            punchBusy = true
            task.delay(0.08, function() punchBusy = false end)
            return true
        end
        if combatHook.Attack then
            punchBusy = true
            task.delay(0.15, function() punchBusy = false end)
            pcall(combatHook.Attack)
            return true
        end
    end
    return directPunch()
end

-- Yaw to face a target. Server validates attack angle in RADIANS between your
-- flat LookVector and the vector to the victim's body â€” not their Head.
local MAX_ATTACK_ANGLE = math.rad(50)
local lastFace = 0

local function flatAngleTo(part)
    local hrp = myHRP()
    if not (hrp and part and part.Parent) then return math.huge end
    local flat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
    local to = Vector3.new(part.Position.X - hrp.Position.X, 0, part.Position.Z - hrp.Position.Z)
    if flat.Magnitude < 0.05 or to.Magnitude < 0.05 then return 0 end
    return math.acos(math.clamp(flat.Unit:Dot(to.Unit), -1, 1))
end

local function isFacingTarget(part, maxRad)
    return flatAngleTo(part) <= (maxRad or MAX_ATTACK_ANGLE)
end

-- Smooth aim lock: sticky character tracking + yaw lerp (scaled by Lock On Strength).
local auraLockPart = nil
local auraLockChar = nil
local auraLockUntil = 0
local auraLockRestore = false

local function setAuraLock(part, holdSec, char)
    if char and char.Parent then auraLockChar = char end
    if part and part.Parent then
        auraLockPart = part
    elseif auraLockChar then
        auraLockPart = aimPart(auraLockChar)
    end
    if not auraLockPart then return end
    auraLockUntil = os.clock() + (holdSec or 1.0)
end

local function clearAuraLock()
    auraLockPart, auraLockChar, auraLockUntil = nil, nil, 0
    if auraLockRestore then
        auraLockRestore = false
        local hum = myHum()
        if hum then pcall(function() hum.AutoRotate = true end) end
    end
end

local function faceTarget(part, force)
    if not (part and part.Parent) then return false end
    local ch = part.Parent
    if ch and not ch:IsA("Model") then ch = ch.Parent end
    setAuraLock(part, force and 0.8 or 0.5, ch)
    return isFacingTarget(part, MAX_ATTACK_ANGLE)
end

-- Apply yaw LATE in the frame so Fist/Combat scripts cannot overwrite it.
local AURA_LOCK_BIND = "FOAB_AuraLockYaw"
local function applyAuraLockYaw(dt)
    if not isCurrent() then return end
    if not S.auraLockOn then
        if auraLockPart or auraLockChar then clearAuraLock() end
        return
    end

    local hrp = myHRP()
    local hum = myHum()
    if not hrp then return end

    -- Sticky follow: re-resolve aim from the locked character every frame.
    if auraLockChar and auraLockChar.Parent then
        local aim = aimPart(auraLockChar)
        if aim then auraLockPart = aim; auraLockUntil = os.clock() + 0.75 end
    elseif os.clock() > auraLockUntil then
        clearAuraLock()
        return
    end

    local part = auraLockPart
    if not part or not part.Parent then
        clearAuraLock()
        return
    end

    local to = Vector3.new(part.Position.X - hrp.Position.X, 0, part.Position.Z - hrp.Position.Z)
    if to.Magnitude < 0.05 then return end
    local goalLook = to.Unit

    local flat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
    if flat.Magnitude < 0.05 then flat = goalLook else flat = flat.Unit end

    local ang = math.acos(math.clamp(flat:Dot(goalLook), -1, 1))
    if ang < math.rad(0.5) then
        -- Still pin AutoRotate off so Fist combat cannot drift us off target.
        if hum then
            if hum.AutoRotate then auraLockRestore = true end
            hum.AutoRotate = false
        end
        return
    end

    local str = math.clamp((S.auraLockStr or 70) / 50, 0.2, 2.5)
    local turnRate = (20 + ang * 12) * str
    local alpha = math.clamp(1 - math.exp(-turnRate * math.max(dt or 1/60, 1/240)), 0, 1)
    if str >= 1.4 then alpha = math.max(alpha, math.clamp((dt or 1/60) * 26 * str, 0, 1)) end

    local pos = hrp.Position
    local curCF = CFrame.lookAt(pos, pos + flat)
    local goalCF = CFrame.lookAt(pos, pos + goalLook)
    local newCF = curCF:Lerp(goalCF, alpha)
    local look = Vector3.new(newCF.LookVector.X, 0, newCF.LookVector.Z)
    if look.Magnitude < 0.05 then return end

    pcall(function()
        if hum then
            if hum.AutoRotate then auraLockRestore = true end
            hum.AutoRotate = false
        end
        local v = hrp.AssemblyLinearVelocity
        hrp.CFrame = CFrame.lookAt(pos, pos + look.Unit)
        hrp.AssemblyLinearVelocity = v
    end)
end

pcall(function()
    RunService:UnbindFromRenderStep(AURA_LOCK_BIND)
end)
pcall(function()
    RunService:BindToRenderStep(AURA_LOCK_BIND, Enum.RenderPriority.Last.Value, applyAuraLockYaw)
end)
-- Fist Combat often overwrites yaw on Stepped/Heartbeat after RenderStepped — re-apply.
Maid:Give(RunService.Stepped:Connect(function(_, dt)
    if S.auraLockOn and (auraLockChar or auraLockPart) then
        applyAuraLockYaw(dt)
    end
end))

-- Melee reach of a real swing (arm hitbox). Beyond this, damage can't land no
-- matter what, because it's the server's own hitbox â€” so we must be this close.
local MELEE_REACH = 7

local function firePunch(t)
    if not (t and t.char and t.char.Parent) then return false end
    local aim = aimPart(t.char) or t.part
    if not (aim and aim.Parent) then return false end
    if S.auraLockOn then setAuraLock(aim, 1.0, t.char) end
    return realAttack()
end

local function fireGrab(t)
    if not (t and t.char) then return end
    local aim = aimPart(t.char) or t.part
    if aim then faceTarget(aim, true) end
    pressAction("Grab")
end

local function fireStomp(t)
    if not (t and t.char) then return end
    local aim = aimPart(t.char) or t.part
    if aim then faceTarget(aim, true) end
    pressAction("Stomp")
end

local function firePush(t)
    if not (t and t.char) then return end
    local aim = aimPart(t.char) or t.part
    if aim then faceTarget(aim, true) end
    pressAction("Push")
end

-- Weave: fire the i-frame packet (that's what actually dodges the hit) and,
-- optionally, play the real weave animation. NO BodyPosition/position-lock â€”
-- that was what froze you; the dodge is from the server i-frames, not movement.
-- Shared weave state so Smart Punch Aura pauses the instant a weave starts (ours OR a
-- manual dodge) and fires again the moment it ends â€” punching mid-weave cancels
-- the dodge, so the aura must hold off for exactly the weave window.
local weaveUntil = 0     -- os.clock() when our last weave's window ends
local dodgeHeld  = false -- player is holding the dodge/weave key right now
local function isWeaving()
    if os.clock() < weaveUntil then return true end       -- inside a weave we triggered
    if dodgeHeld then return true end                     -- manual weave held down
    local hrp = myHRP()                                   -- game parents a BodyPosition to
    if hrp and hrp:FindFirstChildOfClass("BodyPosition") then return true end  -- HRP during any weave
    return false
end

local function dodgeInput()
    local srv = LP:FindFirstChild("Server")
    local v = srv and srv:FindFirstChild("Dodge")
    if v and v:IsA("StringValue") and v.Value ~= "" then
        return Enum.KeyCode:FromName(v.Value) or Enum.UserInputType:FromName(v.Value)
    end
    return Enum.KeyCode.Space
end

local function weaveDirFrom(attackerChar)
    local myH = myHRP()
    local aHRP = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart")
    if not (myH and aHRP) then return "Forward" end
    local rel = myH.CFrame:VectorToObjectSpace((myH.Position - aHRP.Position).Unit)
    if math.abs(rel.Z) >= math.abs(rel.X) then
        return rel.Z < 0 and "Forward" or "Backward"
    end
    return rel.X > 0 and "Left" or "Right"
end

local weaveLock = false

local function weaveIFrame()
    return S.noWeaveCd and 0.06 or 0.45
end

-- Per-direction dash target the game's own weave uses (Moving loop, PlayWeaveAnimation).
local WEAVE_DASH = {
    Forward  = CFrame.new(0, 0, -1.15),
    Backward = CFrame.new(0, 0,  1.15),
    Left     = CFrame.new(-2.15, 0, 0),
    Right    = CFrame.new(2.15, 0, 0),
}

-- Release a stuck weave pose. Auto-weave used to leave CanWeave / the game's
-- CurrentWeaveAnimation / WalkSpeed=0 latched on both mobile and PC because we
-- never simulated the dodge-key release the Combat script expects.
local function stopWeaveVisual()
    dodgeHeld = false
    local ch, hrp = myChar(), myHRP()
    local hum = myHum()
    if combatHook.state then
        pcall(function()
            combatHook.state.CanWeave = false
            local tr = combatHook.state.CurrentWeaveAnimation
            if tr and tr.IsPlaying then
                tr:Stop(0.08)
                combatHook.state.CurrentWeaveAnimation = nil
            end
        end)
    end
    pcall(function()
        if combatHook.weaveUp then
            combatHook.weaveUp()
        else
            local w = mobileRoot() and mobileRoot():FindFirstChild("Weave")
            if w then invokeMobile(w, "MouseButton1Up") end
        end
    end)
    if hum then
        pcall(function()
            hum.WalkSpeed = game:GetService("StarterPlayer").CharacterWalkSpeed
        end)
    end
    if hrp then
        local bp = hrp:FindFirstChildOfClass("BodyPosition")
        if bp then pcall(function() bp:Destroy() end) end
    end
    if ch and ch:GetAttribute("WeaveStun") and S.noWeaveCd then
        pcall(function() ch:SetAttribute("WeaveStun", nil) end)
    end
    Anim.stopAll()
end

-- Fire a genuine dodge. PRIMARY: PlayWeaveAnimation on every platform (one signed
-- Weave packet + dash, no held dodge key). VIM / mobile-button paths are fallbacks
-- only when the captured routine isn't available yet.
local function fireWeave(dir)
    dir = dir or "Forward"
    local ch, hrp = myChar(), myHRP()
    if not (ch and hrp) then return false end
    if weaveLock or os.clock() < weaveUntil then return false end
    weaveLock = true
    weaveUntil = os.clock() + weaveIFrame()

    if S.noWeaveCd then
        if ch:GetAttribute("WeaveStun") then pcall(function() ch:SetAttribute("WeaveStun", nil) end) end
        if combatHook.state then pcall(function() combatHook.state.WEAVE_MOVE_DEBOUNCE = false end) end
    end

    task.spawn(function()
        local usedGameWeave = false
        if S.weaveAnim then
            -- Animation ON: use the game's PlayWeaveAnimation (anim + dash + Weave packet).
            if combatHook.playWeave then
                local dash = WEAVE_DASH[dir] or WEAVE_DASH.Forward
                pcall(function() combatHook.playWeave(dir, hrp.CFrame * dash) end)
                usedGameWeave = true
            elseif not deviceIsMobile() then
                local dodge = actionBind("Dodge")
                local moveKey = WEAVE_KEY[dir] or Enum.KeyCode.W
                if typeof(dodge) == "EnumItem" and dodge.EnumType == Enum.KeyCode then
                    dodgeHeld = true
                    VIM:SendKeyEvent(true, dodge, false, game)
                    VIM:SendKeyEvent(true, moveKey, false, game)
                    task.wait(0.07)
                    VIM:SendKeyEvent(false, moveKey, false, game)
                    VIM:SendKeyEvent(false, dodge, false, game)
                    dodgeHeld = false
                end
            else
                dodgeHeld = true
                local weaveBtn = mobileRoot() and mobileRoot():FindFirstChild("Weave")
                pcall(function()
                    if combatHook.weaveDown then combatHook.weaveDown()
                    elseif weaveBtn then invokeMobile(weaveBtn, "MouseButton1Down") end
                end)
                task.wait(0.06)
                pcall(function() Net.Fire({ Type = "Weave" }) end)
                task.wait(0.04)
            end
            -- Custom Anim.weave only when the game routine wasn't used
            if not usedGameWeave then Anim.weave(dir) end
        else
            -- Animation OFF: i-frame Weave packet only — never call PlayWeaveAnimation
            -- (that always plays the weave anim) and never play Anim.weave.
            pcall(function() Net.Fire({ Type = "Weave" }) end)
            -- Kill any weave track the game may have already started this frame
            pcall(function()
                if combatHook.state then
                    local tr = combatHook.state.CurrentWeaveAnimation
                    if tr and tr.IsPlaying then
                        tr:Stop(0)
                        combatHook.state.CurrentWeaveAnimation = nil
                    end
                end
                local hum = myHum()
                local animator = hum and hum:FindFirstChildOfClass("Animator")
                if animator then
                    for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
                        local n = tr.Name or ""
                        local id = tr.Animation and tr.Animation.AnimationId or ""
                        if n:lower():find("weave") or id:lower():find("weave") then
                            pcall(function() tr:Stop(0) end)
                        end
                    end
                end
            end)
            Anim.stopAll()
        end
        task.delay(weaveIFrame() + 0.08, stopWeaveVisual)
        if S.noWeaveCd then
            if ch:GetAttribute("WeaveStun") then pcall(function() ch:SetAttribute("WeaveStun", nil) end) end
            if combatHook.state then pcall(function() combatHook.state.WEAVE_MOVE_DEBOUNCE = false end) end
            pcall(function()
                local ui = ReplicatedStorage:FindFirstChild("GetUI") and ReplicatedStorage.GetUI:Invoke()
                local cell = ui and ui:FindFirstChild("Cooldowns") and ui.Cooldowns:FindFirstChild("WEAVE")
                if cell then cell:Destroy() end
            end)
        end
    end)

    task.delay(weaveIFrame(), function() weaveLock = false end)
    return true
end

-- Track the dodge key so a MANUAL weave pauses the aura too.
do
    Maid:Give(UserInputService.InputBegan:Connect(function(i, gp)
        if gp then return end
        local d = dodgeInput()
        if i.KeyCode == d or i.UserInputType == d then dodgeHeld = true end
    end))
    Maid:Give(UserInputService.InputEnded:Connect(function(i)
        local d = dodgeInput()
        if i.KeyCode == d or i.UserInputType == d then dodgeHeld = false end
    end))
end

-- Sorted-by-distance target list within a range.
local function targetsInRange(range, includeNPCs)
    local hrp = myHRP(); if not hrp then return {} end
    local list = {}
    for _, t in ipairs(gatherTargets(includeNPCs)) do
        local d = (t.part.Position - hrp.Position).Magnitude
        if d <= range then t.dist = d; list[#list + 1] = t end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

----------------------------------------------------------------------
-- Engine loops (persistent; gated by the S flags)
----------------------------------------------------------------------
-- Smart Punch Aura â€” SMART TRIGGERBOT. Real M1 is the only thing that damages, and
-- the server only credits a swing whose target is inside the melee reach (~7 studs)
-- AND the attack cone (Â±50Â° of our LookVector). So it behaves like a triggerbot: it
-- only fires when a target is actually in that hit zone (never swings at air), picks
-- the target closest to our crosshair for a guaranteed connect, and lets the arm
-- hitbox clip everyone else in the cone (natural AoE). WEAVE-AWARE: an enemy that is
-- mid-weave has i-frames (punches whiff and just feed their combo), so we SKIP any
-- weaving enemy â€” but because the loop re-checks every tick, the instant their weave
-- ends they become a valid target again and get hit immediately. STATIONARY: never
-- walks, so it can't jitter and can't flag the position AC.
local function pickHitTarget()
    local hrp = myHRP(); if not hrp then return nil end
    local best, bestScore = nil, math.huge
    for _, t in ipairs(targetsInRange(S.auraRange, S.auraNPC)) do
        if not (S.auraLOS and not hasLOS(hrp, t.part, t.char)) then
            local weaving = isTargetWeaving(t.char) and not S.auraHitWeave
            if not weaving and t.dist <= MELEE_REACH + 0.5 then  -- inside the hit zone, not weaving
                local aim = aimPart(t.char) or t.part
                local ang = flatAngleTo(aim)              -- angle to our crosshair
                -- prefer smallest angle (cleanest connect); on a tie, lower HP secures kills
                local hp = (t.hum and t.hum.Health) or 100
                local score = ang + t.dist * 0.02 + hp * 0.0008
                if score < bestScore then best, bestScore = t, score end
            end
        end
    end
    return best
end

-- Lock-on target picker: full aura range (not just melee), sticky to current char.
local function pickLockTarget()
    local hrp = myHRP(); if not hrp then return nil end
    local range = (S.auraRange or 12) + 1.5

    -- Stick to current lock while they stay in range / alive.
    if auraLockChar and auraLockChar.Parent then
        local aim = aimPart(auraLockChar)
        local hum = auraLockChar:FindFirstChildOfClass("Humanoid")
        if aim and hum and hum.Health > 0 then
            local d = (aim.Position - hrp.Position).Magnitude
            local weaving = isTargetWeaving(auraLockChar) and not S.auraHitWeave
            if d <= range and not weaving then
                if not (S.auraLOS and not hasLOS(hrp, aim, auraLockChar)) then
                    return { char = auraLockChar, part = aim, dist = d, hum = hum }
                end
            end
        end
    end

    -- Otherwise pick nearest valid enemy in aura range.
    local best, bestDist = nil, math.huge
    for _, t in ipairs(targetsInRange(S.auraRange or 12, S.auraNPC)) do
        if not (S.auraLOS and not hasLOS(hrp, t.part, t.char)) then
            local weaving = isTargetWeaving(t.char) and not S.auraHitWeave
            if not weaving and t.dist < bestDist then
                best, bestDist = t, t.dist
            end
        end
    end
    return best
end

-- Continuously refresh lock onto the best / sticky aura target.
Maid:Give(RunService.Heartbeat:Connect(function()
    if not isCurrent() then return end
    if not S.auraLockOn then
        if auraLockPart or auraLockChar then clearAuraLock() end
        return
    end
    -- Do NOT pause on isWeaving(): Fist combat BodyPosition falsely trips it and drops lock.
    if isStunned(myChar()) or not myHRP() then return end
    local hit = pickLockTarget()
    if hit then
        setAuraLock(hit.part, 1.25, hit.char)
    end
end))


task.spawn(function()
    while isCurrent() do
        if S.auraPunch and ensureFists() and not isStunned(myChar()) and myHRP() then
            -- Never punch while WE are weaving â€” a punch cancels our dodge/i-frames.
            -- Poll fast during the weave so we resume the instant our weave window ends.
            if isWeaving() and not S.auraHitWeave then
                task.wait(0.015)
            else
                -- STATIONARY triggerbot â€” no walking, ever. We only punch enemies who are
                -- already inside the hit zone (reach + cone). Never moves the character, so
                -- there is nothing to jitter and it never flags the position AC.
                local hit = pickHitTarget()
                if hit then
                    -- Only re-face when actually off-angle (>35Â°). Snapping the CFrame EVERY


                    local aim = aimPart(hit.char) or hit.part
                    if S.auraLockOn then setAuraLock(aim, 1.0, hit.char) end
                    firePunch(hit)
                    task.wait(auraInterval(false))
                else
                    task.wait(0.03)   -- nobody in the hit zone â†’ poll for one to enter
                end
            end
        else
            task.wait(0.1)
        end
    end
end)

-- Walk To Target â€” auto-chase follow-bot. Locks onto the NEAREST living target at ANY
-- range and walks the character to them, staying on that SAME target until it dies or
-- leaves, then switches to the next-nearest. Pairs with Smart Punch Aura: this closes
-- the distance, the aura swings the instant they enter melee reach.
--
-- Locomotion is driven with Humanoid:Move (re-issued every frame in WORLD space), NOT
-- Humanoid:MoveTo. MoveTo was the glitch: it silently times out after 8s and stops, it
-- gets cancelled whenever the combat controller issues its own MoveTo, and it fights the
-- aura-lock CFrame yaw. Move sets MoveDirection directly, can't time out, and â€” because
-- it's world-relative â€” is unaffected by the facing lock, so aura + chase coexist. We
-- run on Stepped (AFTER the control script's RenderStepped pass, BEFORE physics) so our
-- MoveDirection wins the frame even with fists out. Real locomotion, no teleport, so it
-- never trips the position AC.
do
    local walkLockChar = nil

    local function walkPickNearest()
        local hrp = myHRP(); if not hrp then return nil end
        local best, bestDist
        for _, t in ipairs(gatherTargets(S.auraNPC)) do
            if t.hum and t.hum.Health > 0 then
                local d = (t.part.Position - hrp.Position).Magnitude
                if not bestDist or d < bestDist then best, bestDist = t.char, d end
            end
        end
        return best
    end

    Maid:Give(RunService.Stepped:Connect(function()
        if not isCurrent() then return end
        if not S.walkToNearest then
            walkLockChar = nil
            return
        end
        local hum, hrp = myHum(), myHRP()
        if not (hum and hrp and hum.Health > 0) then return end
        if isStunned(myChar()) then return end        -- don't fight a knockdown/weave-stun

        -- Keep the SAME target until it dies or despawns, then re-pick the nearest.
        local lockHum = walkLockChar and walkLockChar.Parent and walkLockChar:FindFirstChildOfClass("Humanoid")
        if not (lockHum and lockHum.Health > 0) then
            walkLockChar = walkPickNearest()
        end
        if not walkLockChar then hum:Move(Vector3.zero, false); return end

        local aim = aimPart(walkLockChar); if not aim then return end
        -- Aim/lock at them too so facing + Punch Aura stay on this target while chasing.
        if S.auraLockOn then setAuraLock(aim, 0.5, walkLockChar) end

        -- World-space flat vector to the target. Walk right up against them (~3.5 studs
        -- center-to-center = bodies almost touching) then stop dead so the (separate)
        -- Punch Aura loop lands clean swings. MELEE_REACH-1 left too big a gap.
        local WALK_STOP = 3.5
        local myPos, tgtPos = hrp.Position, aim.Position
        local flat = Vector3.new(tgtPos.X - myPos.X, 0, tgtPos.Z - myPos.Z)
        if flat.Magnitude > WALK_STOP then
            -- Fist combat / weave scripts pin WalkSpeed to 0 while fists are out â€” that's
            -- the "won't walk with fists equipped" bug. Force it back up so we move.
            local wsTarget = game:GetService("StarterPlayer").CharacterWalkSpeed
            if wsTarget <= 0 then wsTarget = 16 end
            if hum.WalkSpeed < wsTarget then pcall(function() hum.WalkSpeed = wsTarget end) end
            hum:Move(flat.Unit, false)     -- world-relative MoveDirection, re-issued each frame
        else
            hum:Move(Vector3.zero, false)  -- in reach: hold still, let the aura swing
        end
    end))
end

-- Automation: grab / stomp / push. Each honours its REAL server cooldown
-- (Push 6.2s, Stomp 2s, Grab/SLAM 18s â€” live-verified) AND only ONE ability
-- fires per window (>=0.55s apart, jittered) â€” so all three can be enabled at
-- once without the "everything at the same instant" pattern tripping the AC.
task.spawn(function()
    local last, lastAny = { grab = 0, stomp = 0, push = 0 }, 0
    local CD = { grab = 18.0, stomp = 2.0, push = 6.2 }
    while isCurrent() do
        if (S.autoGrab or S.autoStomp or S.autoPush) and fistsEquipped() and myHRP() and not isStunned(myChar()) then
            local now = os.clock()
            local anyGap = jit(0.55, 0.25)
            local function ready(kind, base) return now - last[kind] >= jit(base, 0.15) end
            if now - lastAny >= anyGap then
                local acted = false
                if S.autoStomp and ready("stomp", CD.stomp) then
                    for _, t in ipairs(targetsInRange(S.stompRange, S.auraNPC)) do
                        local downed = t.char:FindFirstChild("Knocked")
                        if (downed and downed.Value) or t.hum:GetState() == Enum.HumanoidStateType.Physics then
                            fireStomp(t); last.stomp = now; lastAny = now; acted = true; break
                        end
                    end
                end
                if not acted and S.autoGrab and ready("grab", CD.grab) then
                    local l = targetsInRange(S.grabRange, S.auraNPC)
                    if l[1] then fireGrab(l[1]); last.grab = now; lastAny = now; acted = true end
                end
                if not acted and S.autoPush and ready("push", CD.push) then
                    local l = targetsInRange(S.pushRange, S.auraNPC)
                    if l[1] then firePush(l[1]); last.push = now; lastAny = now end
                end
            end
            task.wait(0.12)
        else
            task.wait(0.15)
        end
    end
end)

-- No Weave Cooldown: strip the WEAVE cooldown cell + weave-stun attribute
do
    local gameUI
    -- Resolve GetUI OFF the main load thread. WaitForChild is capped at 5s but the
    -- :Invoke() that follows is NOT — if the server ever stalls, running it inline
    -- here would yield (freeze) the entire script load. Resolve it in its own thread;
    -- the consumer loop below already null-checks gameUI and picks it up once set.
    task.spawn(function()
        pcall(function() gameUI = ReplicatedStorage:WaitForChild("GetUI", 5):Invoke() end)
    end)
    task.spawn(function()
        while isCurrent() do
            if S.noWeaveCd then
                local ch = myChar()
                if ch and ch:GetAttribute("WeaveStun") then pcall(function() ch:SetAttribute("WeaveStun", nil) end) end
                local cds = gameUI and gameUI:FindFirstChild("Cooldowns")
                if cds then
                    local cell = cds:FindFirstChild("WEAVE")
                    if cell then pcall(function() cell:Destroy() end) end
                end
                task.wait(0.02)
            else
                task.wait(0.2)
            end
        end
    end)
end

-- Auto Weave: reacts to enemies' replicated attack animations AND to kill-aura
-- style packet spam (no anim) via Combo/HitCombo attribute ticks + close-range
-- limb proximity. (This IS the old "Perfect Weave" â€” merged in.)
do
    -- Gather offensive animation ids so we only dodge real attacks.
    local attackIds = {}
    local function scanAnims(anims)
        if not anims then return end
        for _, folderName in ipairs({ "M1s", "Stomps", "Grabs", "Shoves", "Misc" }) do
            local f = anims:FindFirstChild(folderName)
            if f then
                for _, d in ipairs(f:GetDescendants()) do
                    if d:IsA("Animation") and d.AnimationId ~= "" then attackIds[d.AnimationId] = true end
                end
            end
        end
    end
    pcall(function()
        local live = workspace:FindFirstChild("Live")
        local lc = live and live:FindFirstChild(LP.Name)
        scanAnims(lc and lc:FindFirstChild("Combat") and lc.Combat:FindFirstChild("Animations"))
        local combat = game:GetService("StarterPlayer").StarterCharacterScripts:FindFirstChild("Combat")
        scanAnims(combat and combat:FindFirstChild("Animations"))
    end)
    local lastWeave = 0
    local lastCombo = setmetatable({}, { __mode = "k" })  -- char -> {combo, hitCombo}
    local lastHp = 100

    local function tryWeave(attackerChar, force)
        if not S.autoWeave then return end
        local mc = myChar()
        if mc and mc:GetAttribute("WeaveStun") then
            if S.noWeaveCd then pcall(function() mc:SetAttribute("WeaveStun", nil) end)
            else return end
        end
        local myH = myHRP()
        local aHRP = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart")
        if not myH then return end
        if aHRP then
            local toMe = myH.Position - aHRP.Position
            if toMe.Magnitude > S.weaveRange then return end
            if not force and S.weaveFacing and toMe.Magnitude > 0.1
                and aHRP.CFrame.LookVector:Dot(toMe.Unit) < 0.15 then
                return
            end
        end
        -- Even with No-Cooldown ON, keep a small floor (~0.28s). The server's real
        -- weave cd is 0.45s, so firing faster just spams rejected packets AND â€” when
        -- Smart Punch Aura is also on â€” leaves it no gap to punch in (the aura pauses
        -- while we weave). 0.28 still reacts faster than the server cd.
        local cd = S.noWeaveCd and 0.28 or S.weaveCd
        if cd > 0 and os.clock() - lastWeave < cd then return end
        lastWeave = os.clock()
        fireWeave(weaveDirFrom(attackerChar))
    end

    -- React the instant an enemy's attack animation replicates.
    local function onEnemyAnim(track, attackerChar)
        if not (track.Animation and attackIds[track.Animation.AnimationId]) then return end
        tryWeave(attackerChar, false)
    end

    local bound = {}
    local function bindChar(plr, char)
        local hum = char:FindFirstChildOfClass("Humanoid")
        local animtr = hum and hum:FindFirstChildOfClass("Animator")
        if not animtr then
            char.ChildAdded:Connect(function()
                local h = char:FindFirstChildOfClass("Humanoid")
                local a = h and h:FindFirstChildOfClass("Animator")
                if a and not bound[a] then
                    bound[a] = true
                    Maid:Give(a.AnimationPlayed:Connect(function(tr) onEnemyAnim(tr, char) end))
                end
            end)
            return
        end
        if bound[animtr] then return end
        bound[animtr] = true
        Maid:Give(animtr.AnimationPlayed:Connect(function(tr) onEnemyAnim(tr, char) end))
    end
    local function watch(plr)
        if plr == LP then return end
        if plr.Character then bindChar(plr, plr.Character) end
        Maid:Give(plr.CharacterAdded:Connect(function(ch) task.wait(0.2); bindChar(plr, ch) end))
    end
    for _, p in ipairs(Players:GetPlayers()) do watch(p) end
    Maid:Give(Players.PlayerAdded:Connect(watch))
    local function watchNPCs()
        local function tryBind(m)
            if isNPCTarget(m) then bindChar(nil, m) end
        end
        local live = Workspace:FindFirstChild("Live")
        if live then
            for _, m in ipairs(live:GetChildren()) do tryBind(m) end
            Maid:Give(live.ChildAdded:Connect(function(m) task.wait(0.2); tryBind(m) end))
        end
        Maid:Give(Workspace.ChildAdded:Connect(function(m) task.wait(0.2); tryBind(m) end))
    end
    watchNPCs()

    -- Kill-aura / silent punch detector: Combo & HitCombo attributes still tick
    -- on the attacker's character even when they never replicate an M1 animation.
    -- Also weave on close limb overlap and when our HP suddenly drops near someone.
    task.spawn(function()
        while isCurrent() do
            if S.autoWeave then
                local myH = myHRP()
                local mc = myChar()
                local hum = myHum()
                if myH and mc and hum then
                    local hp = hum.Health
                    local tookHit = hp < lastHp - 0.5
                    lastHp = hp

                    for _, t in ipairs(gatherTargets(true)) do
                        local ch = t.char
                        if ch and ch ~= mc then
                            local aHRP = ch:FindFirstChild("HumanoidRootPart")
                            if aHRP then
                                local dist = (aHRP.Position - myH.Position).Magnitude
                                if dist <= S.weaveRange then
                                    local combo = ch:GetAttribute("Combo")
                                    local hitCombo = ch:GetAttribute("HitCombo")
                                    local prev = lastCombo[ch]
                                    local swung = false
                                    if prev then
                                        if typeof(combo) == "number" and typeof(prev.combo) == "number" and combo > prev.combo then swung = true end
                                        if typeof(hitCombo) == "number" and typeof(prev.hitCombo) == "number" and hitCombo > prev.hitCombo then swung = true end
                                        -- Combo reset then climb again (aura loops)
                                        if typeof(combo) == "number" and typeof(prev.combo) == "number" and prev.combo >= 3 and combo == 1 then swung = true end
                                    end
                                    lastCombo[ch] = { combo = combo, hitCombo = hitCombo }

                                    local limbThreat = false
                                    if dist <= 7 then
                                        for _, n in ipairs({ "Right Arm", "Left Arm", "RightHand", "LeftHand", "Torso" }) do
                                            local limb = ch:FindFirstChild(n)
                                            if limb and limb:IsA("BasePart") and (limb.Position - myH.Position).Magnitude < 5.2 then
                                                limbThreat = true; break
                                            end
                                        end
                                    end

                                    if swung
                                        or (limbThreat and dist <= 6 and (ch:FindFirstChildOfClass("Tool") or (typeof(combo) == "number" and combo > 0)))
                                        or (tookHit and dist <= S.weaveRange) then
                                        tryWeave(ch, swung or limbThreat or tookHit)
                                    end
                                end
                            end
                        end
                    end

                    -- Emergency weave the moment HitStun lands (preps for the next aura tick)
                    if mc:GetAttribute("HitStun") then
                        tryWeave(nil, true)
                    end
                end
                task.wait(S.noWeaveCd and 0.01 or 0.025)
            else
                local hum = myHum()
                if hum then lastHp = hum.Health end
                task.wait(0.12)
            end
        end
    end)
end

-- Movement bypasses. The game's Combat loop rewrites Humanoid.WalkSpeed every
-- frame from StarterPlayer.CharacterWalkSpeed (=13), and ships jump disabled
-- (JumpHeight=0, UseJumpPower=false). So we override CharacterWalkSpeed itself
-- (the game's own loop then applies OUR value â€” no frame race) and force-enable
-- the jump properties. Both verified working live.
local StarterPlayerSvc = game:GetService("StarterPlayer")
local BASE_WS = StarterPlayerSvc.CharacterWalkSpeed
E.applyWalk = function()
    pcall(function() StarterPlayerSvc.CharacterWalkSpeed = S.walkEnabled and S.walkSpeed or BASE_WS end)
end
E.applyJump = function()
    local hum = myHum(); if not hum then return end
    if S.infJump then pcall(function() hum.UseJumpPower = true; hum.JumpPower = 50; hum.JumpHeight = 7.2 end)
    else pcall(function() hum.UseJumpPower = false; hum.JumpHeight = 0 end) end
end
Maid:Give(UserInputService.JumpRequest:Connect(function()
    if S.infJump then local h = myHum(); if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end end
end))
Maid:Give(LP.CharacterAdded:Connect(function()
    task.wait(1)
    if S.walkEnabled then E.applyWalk() end
    if S.infJump then E.applyJump() end
end))

-- Fly. Flight is a NATIVE, ungated mechanic in this game (every player has a
-- FlyLoader), so driving the HumanoidRootPart velocity is normal movement and
-- isn't fling-flagged. Camera-relative WASD, Space = up, LeftShift/Ctrl = down,
-- hovers in place when nothing is held. Combat/aura still work while flying.
do
    local UP = Vector3.new(0, 1, 0)
    Maid:Give(RunService.Heartbeat:Connect(function()
        if not S.fly then return end
        local hrp = myHRP(); local hum = myHum()
        if not (hrp and hum and hum.Health > 0) then return end
        local cam = Workspace.CurrentCamera
        local dir = Vector3.zero
        if UserInputService:GetFocusedTextBox() == nil then
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + UP end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - UP end
        end
        hrp.AssemblyLinearVelocity = (dir.Magnitude > 0.05) and (dir.Unit * S.flySpeed) or Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end))
end

-- Noclip. Your own character's collision is client-owned, so forcing CanCollide
-- off phases you through players/parts. We snapshot the parts we change and put
-- them back exactly on toggle-off (and clear the snapshot on respawn).
do
    local snap = {}
    E.restoreNoclip = function()
        for p, v in pairs(snap) do if p and p.Parent then pcall(function() p.CanCollide = v end) end end
        snap = {}
    end
    Maid:Give(RunService.Stepped:Connect(function()
        if not S.noclip then return end
        local c = myChar(); if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                if snap[p] == nil then snap[p] = true end
                p.CanCollide = false
            end
        end
    end))
    Maid:Give(LP.CharacterAdded:Connect(function() snap = {} end))
end

-- Freecam. Detaches the camera so you can scout the map; hold RIGHT-MOUSE to look,
-- WASD to move (E/Q up-down, Shift = faster). Your character stays put. Toggle off
-- to restore the normal camera. 100% client-side.
do
    local cf
    E.setFreecam = function(on)
        local cam = Workspace.CurrentCamera
        if on then
            cf = cam.CFrame
            cam.CameraType = Enum.CameraType.Scriptable
        else
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            cam.CameraType = Enum.CameraType.Custom
        end
    end
    Maid:Give(RunService.RenderStepped:Connect(function(dt)
        if not S.freecam or not cf then return end
        local cam = Workspace.CurrentCamera
        if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            local d = UserInputService:GetMouseDelta()
            local rx, ry = cf:ToOrientation()
            rx = math.clamp(rx - math.rad(d.Y * 0.35), math.rad(-89), math.rad(89))
            ry = ry - math.rad(d.X * 0.35)
            cf = CFrame.new(cf.Position) * CFrame.fromOrientation(rx, ry, 0)
        else
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
        local sp = 60 * math.max(0.1, S.freecamSpeed) * dt
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then sp = sp * 3 end
        local mv = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then mv = mv + cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then mv = mv - cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then mv = mv + cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then mv = mv - cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.E) then mv = mv + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.Q) then mv = mv - Vector3.new(0, 1, 0) end
        if mv.Magnitude > 0 then cf = cf + mv.Unit * sp end
        cam.CFrame = cf
    end))
end

-- FOV + No Camera Shake. Both client-side; re-asserted so the game can't reset them.
-- The game's CameraShake module reads Settings["Camera Shake"] â€” flipping it off
-- stops the shake stacking that heavy Aura spam causes.
do
    local shakeWasOn = nil
    Maid:Give(RunService.Heartbeat:Connect(function()
        if not S.freecam then
            local cam = Workspace.CurrentCamera
            if cam and math.abs(cam.FieldOfView - S.fov) > 0.5 then pcall(function() cam.FieldOfView = S.fov end) end
        end
        local cs = LP:FindFirstChild("Settings") and LP.Settings:FindFirstChild("Camera Shake")
        if cs and cs:IsA("BoolValue") then
            if S.noShake then
                if shakeWasOn == nil then shakeWasOn = cs.Value end
                if cs.Value ~= false then cs.Value = false end
            elseif shakeWasOn ~= nil then
                cs.Value = shakeWasOn; shakeWasOn = nil
            end
        end
    end))
end

-- Anti-AFK: defeat the 20-minute idle disconnect. VirtualUser input on the Idled
-- signal â€” the standard, always-works method.
do
    local VirtualUser = game:GetService("VirtualUser")
    Maid:Give(LP.Idled:Connect(function()
        if not S.antiAFK then return end
        pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
    end))
end

-- Teleport: smoothly GLIDE to a chosen player (customisable studs/sec). Uses
-- per-frame CFrame steps (not an instant TP), which is far less flag-prone.
E.tpToken = 0
E.slideTo = function(name)
    if not name or name == "" then notify("Velorix", "Pick a player first"); return end
    local token = E.tpToken + 1; E.tpToken = token
    task.spawn(function()
        while isCurrent() and E.tpToken == token do
            local dt = RunService.Heartbeat:Wait()
            local myH = myHRP(); if not myH then break end
            local tp; for _, p in ipairs(Players:GetPlayers()) do if p ~= LP and p.Name == name then tp = p; break end end
            local tH = tp and tp.Character and tp.Character:FindFirstChild("HumanoidRootPart")
            if not tH then break end
            local delta = tH.Position - myH.Position
            local dist = delta.Magnitude
            if dist <= 4 then break end
            local step = math.min(dist - 3, math.max(1, S.tpSpeed) * dt)
            myH.CFrame = CFrame.lookAt(myH.Position + delta.Unit * step, tH.Position)
        end
    end)
end
E.slideStop = function() E.tpToken = E.tpToken + 1 end

----------------------------------------------------------------------
-- Player: Style / Finisher unlocker  (client-side forced equip)
--
-- Styles live at LocalPlayer.Server.Style (StringValue); finishers at
-- LocalPlayer.Server.GrabType. The game gates equipping locked styles by Level
-- SERVER-side (a legit equip of a style above your level is rejected), but the
-- client's Combat controller is authoritative for animations, combo count and
-- the attack-speed/buff math â€” and it reads Style.Value / GrabType.Value live.
-- Writing those values on the client persists (the server doesn't resync them),
-- so forcing them here makes you actually USE any style's moveset + finisher
-- regardless of your level. (Server-side DAMAGE tier still follows your real
-- unlocked style â€” that part can't be faked from the client.)
----------------------------------------------------------------------
local function serverFolder() return LP:FindFirstChild("Server") end

-- Ask the SERVER to really equip via the game's own dispatcher
-- (MiscRemote:InvokeServer). This is the true server-sided equip: everyone sees
-- it and the damage tier changes. The catch is the server enforces the level
-- gate â€” a style/finisher above your Level is rejected (verified live), so this
-- only "sticks" server-side for ones you've unlocked. Fired once on selection
-- (never in the maintain loop) so we don't spam the RemoteFunction.
local function miscRemote() return LP:FindFirstChild("MiscRemote") end
E.equipStyleServer = function(name)
    if not name or name == "" then return end
    task.spawn(function()
        local mr = miscRemote(); if mr then pcall(function() mr:InvokeServer("EquipStyle", name) end) end
    end)
end
E.equipFinisherServer = function(name)
    if not name or name == "" then return end
    task.spawn(function()
        local mr = miscRemote(); if mr then pcall(function() mr:InvokeServer("EquipGrab", name) end) end
    end)
end

-- Maintain the CLIENT-side value so the Combat controller drives this style's
-- moveset regardless of the server gate: it live-reads Style.Value / GrabType.Value
-- to pick which M1 / weave / finisher animations to load, and those animations
-- replicate â€” so other players DO see the moveset you're using. Server DAMAGE
-- tier still follows your real unlocked style for locked ones (that's the part
-- the server won't let us fake). Together: fully real when you're high enough
-- level, visual + your own combos when you aren't.
-- Changing Style.Value live makes the game's Combat controller StopAllAnimations
-- and reload that style's tracks â€” but it doesn't replay the IDLE, so the rig
-- freezes on the last frame. After any style change we re-play the correct idle
-- once the reload has happened, so the unlocker never leaves you frozen.
local function replayIdle()
    task.spawn(function()
        task.wait(0.15)
        pcall(function()
            local char = myChar(); if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            local animator = hum and hum:FindFirstChildOfClass("Animator")
            local anims = char:FindFirstChild("Combat") and char.Combat:FindFirstChild("Animations")
            local idles = anims and anims:FindFirstChild("Idles")
            if not (animator and idles) then return end
            local styleName = (serverFolder() and serverFolder():FindFirstChild("Style") and serverFolder().Style.Value) or "Default"
            local folder = idles:FindFirstChild(styleName) or idles:FindFirstChild("Default")
            local idleAnim = folder and folder:FindFirstChild("Anim")
            if not idleAnim then return end
            for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
                if tr.Animation == idleAnim and tr.IsPlaying then return end  -- already idling
            end
            local tr = animator:LoadAnimation(idleAnim); tr.Looped = true; tr:Play(0.2)
        end)
    end)
end

-- Katana-specific WeaponWeld offset (game default for fist mesh differs from katana).
local KATANA_WEAPON_WELD = CFrame.new(0, 0.035, -1.781) * CFrame.Angles(math.pi, 0, 0)
local DEFAULT_FIST_MESH = "http://www.roblox.com/asset/?id=1699715537"

local function styleHasWeapon(name)
    local sw = ReplicatedStorage:FindFirstChild("StyleWeapons")
    return sw and sw:FindFirstChild(name or "") ~= nil
end

local function bindStyleWeaponWatchers(char)
    if not char then return end
    local rt = char:FindFirstChild("RightTool")
    if not (rt and rt:IsA("MeshPart")) then return end
    local function reapply()
        if S.styleForce then task.defer(E.applyStyleWeapon) end
    end
    Maid:Give(rt:GetPropertyChangedSignal("MeshId"):Connect(reapply))
    Maid:Give(rt:GetPropertyChangedSignal("Transparency"):Connect(reapply))
    Maid:Give(rt:GetPropertyChangedSignal("Size"):Connect(reapply))
    Maid:Give(char.ChildAdded:Connect(function(ch)
        if ch.Name == "Fist" or ch:IsA("Tool") then task.delay(0.08, reapply) end
    end))
    Maid:Give(char.ChildRemoved:Connect(function(ch)
        if ch.Name == "Fist" or ch:IsA("Tool") then task.delay(0.08, reapply) end
    end))
end

-- Weapon styles (Katana) hang a MeshPart called "RightTool" off the hand (welded
-- by WeaponWeld) and the game swaps its mesh to ReplicatedStorage.StyleWeapons.<style>
-- only on a real server equip. We own our character's parts client-side, so we
-- drive that mesh ourselves â€” keep OriginalSize (0.5Â³), clone SurfaceAppearance,
-- and re-assert when the game resets RightTool on fist unequip.
local KATANA_GRIP = CFrame.new(-0.00452876091, -1.85319746, -1.38840115,
    -0.999994695, -0.00168839097, -0.00274801254,
    2.92062759e-05, 0.847250938, -0.531192839,
    0.00322511792, -0.531190157, -0.847246647)
E.applyStyleWeapon = function()
    local char = myChar(); if not char then return end
    local arm = char:FindFirstChild("Right Arm"); if not arm then return end
    local existing = char:FindFirstChild("VelorixWeapon")
    -- Holster with the fist: the game only shows the weapon mesh while the Fist
    -- tool is out, but our clone is welded straight to the arm and doesn't follow
    -- equip state â€” so when fists are away, tear it down (the Fist ChildRemoved
    -- watcher calls straight back here) and it vanishes just like the real weapon.
    if not fistsEquipped() then
        if existing then existing:Destroy() end
        return
    end
    local sw = ReplicatedStorage:FindFirstChild("StyleWeapons")
    local tmpl = (S.styleForce and sw) and sw:FindFirstChild(S.styleName) or nil
    if tmpl and tmpl:IsA("MeshPart") then
        if existing and existing.Parent and existing:GetAttribute("vstyle") == S.styleName then return end
        if existing then existing:Destroy() end
        pcall(function()
            local w = tmpl:Clone()
            w.Name = "VelorixWeapon"; w:SetAttribute("vstyle", S.styleName)
            w.Anchored = false; w.CanCollide = false; w.Massless = true
            w.Parent = char
            -- exact grip: read live from the inventory preview NPC, else the measured Katana grip
            local c0
            pcall(function()
                local viz = LP.PlayerGui.ScreenGui.Menus.INVENTORY.Menus.STYLES.List[S.styleName].ViewportFrame.WorldModel.VisualizerNpcLol
                local va, vk = viz:FindFirstChild("Right Arm"), viz:FindFirstChild(S.styleName)
                if va and vk then c0 = va.CFrame:ToObjectSpace(vk.CFrame) end
            end)
            local weld = Instance.new("Motor6D")
            weld.Name = "VelorixWeaponWeld"; weld.Part0 = arm; weld.Part1 = w
            weld.C0 = c0 or KATANA_GRIP
            weld.Parent = arm
        end)
    elseif existing then
        existing:Destroy()   -- non-weapon style, or Force Style off
    end
end

E.applyStyle = function()
    if not S.styleForce or S.styleName == "" then return end
    pcall(function()
        local sv = serverFolder() and serverFolder():FindFirstChild("Style")
        if sv and sv:IsA("StringValue") and sv.Value ~= S.styleName then
            sv.Value = S.styleName
            replayIdle()
        end
    end)
    E.applyStyleWeapon()
end
E.applyFinisher = function()
    if not S.finisherForce or S.finisherName == "" then return end
    pcall(function()
        local gt = serverFolder() and serverFolder():FindFirstChild("GrabType")
        if gt and gt:IsA("StringValue") and gt.Value ~= S.finisherName then gt.Value = S.finisherName end
    end)
end

----------------------------------------------------------------------
-- Free Gamepasses  (client-side perk flags)
--
-- The gamepass-gated perks are read from BoolValues under Server.Has*. Combat is
-- client-authoritative, so flipping HasFasterAttacks (+ the Settings toggle)
-- genuinely gives you the Faster Attacks speed-up in DoPunch. Stronger Punches
-- and the X2 economy passes are validated server-side, so those flags are
-- best-effort (they'll read as owned client-side but the server still enforces
-- the real reward). We set them all + enable the matching Settings toggles.
----------------------------------------------------------------------
local GAMEPASS_FLAGS = { "HasFasterAttacks", "HasStrongerPunches", "HasX2XP", "HasX2ClanXP", "HasX2Kills" }
local GAMEPASS_SETTINGS = { "Faster Attacks", "Stronger Punches" }
E.applyGamepasses = function()
    if not S.freeGamepasses then return end
    pcall(function()
        local srv = serverFolder()
        if srv then
            for _, n in ipairs(GAMEPASS_FLAGS) do
                local b = srv:FindFirstChild(n)
                if b and b:IsA("BoolValue") and b.Value ~= true then b.Value = true end
            end
        end
        local settings = LP:FindFirstChild("Settings")
        if settings then
            for _, n in ipairs(GAMEPASS_SETTINGS) do
                local b = settings:FindFirstChild(n)
                if b and b:IsA("BoolValue") and b.Value ~= true then b.Value = true end
            end
        end
    end)
end

-- Slow reassert loop for the three unlockers (cheap; only acts while enabled and
-- only writes when a value has drifted, so it never loops against the game).
task.spawn(function()
    while isCurrent() do
        E.applyStyle()
        E.applyStyleWeapon()
        E.applyFinisher()
        E.applyGamepasses()
        local waitT = (S.styleForce and styleHasWeapon(S.styleName)) and 0.25 or 1.5
        task.wait(waitT)
    end
end)

-- Reassert style weapon on respawn + when fist equip state changes.
Maid:Give(LP.CharacterAdded:Connect(function(ch)
    task.wait(0.6)
    bindStyleWeaponWatchers(ch)
    E.applyStyle()
    E.applyFinisher()
    E.applyGamepasses()
end))
if LP.Character then task.defer(function()
    bindStyleWeaponWatchers(LP.Character)
    E.applyStyleWeapon()
end) end

----------------------------------------------------------------------
-- Fling engine (self) â€” shared by Touch Fling + Target Fling below.
--
-- FOAB flings work by momentum: a solid moving at enormous velocity that overlaps
-- another player's parts transfers a huge collision impulse to them (their client owns
-- their character, so it simulates the collision and launches). The OLD Touch Fling
-- span our OWN HumanoidRootPart to do this â€” but our body IS a physics part, so the
-- spin flung and span US too. The fix: never touch our own body. We detect any player
-- that comes into contact range and ram them with a SEPARATE free part (not welded to
-- us) that carries all the momentum. None of it couples back, so we stand still and
-- look completely normal â€” only whoever touches us goes flying.
----------------------------------------------------------------------
do
----------------------------------------------------------------------
-- Anti-Fling (hardened)
--
-- Fling/resolver scripts launch or teleport your HumanoidRootPart by dumping huge
-- linear/angular velocity, attaching rotational/force movers, or yanking your CFrame
-- across the map. We can't change network ownership from the client, but every one of
-- those vectors is defeatable locally. This runs on BOTH Stepped AND Heartbeat (so no
-- single-frame velocity spike â€” the exact trick a touch-fling uses â€” slips through the
-- gap between the two), and adds a POSITION RESOLVER: if something displaces us a huge
-- horizontal distance in one frame (momentum OR teleport fling) we snap back to the
-- last sane spot and kill the launch velocity. Vertical motion (jumps/falls) is left
-- alone, and our own Fly / Fling drivers are skipped, so normal play is never trapped.
----------------------------------------------------------------------
local FLING_LINEAR_CAP  = 100   -- studs/s; normal knockback/sprint stays under this
local FLING_ANGULAR_CAP = 12    -- rad/s;  legit play keeps HRP spin at ~0
local FLING_SNAP_STUDS  = 16    -- max un-driven horizontal jump/frame before we resolve it
local FLING_MOVERS = {
    BodyAngularVelocity = true, AngularVelocity = true, Torque = true,
    BodyThrust = true, BodyForce = true, RocketPropulsion = true, LineForce = true,
    VectorForce = true, AlignOrientation = true,
}
local flingLastGoodPos = nil

local function antiFlingStep()
    if not S.antiFling then return end
    local char = myChar()
    if not char then flingLastGoodPos = nil; return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    pcall(function()
        -- Strip any foreign spin/force movers the fling attached to us.
        for _, d in ipairs(char:GetDescendants()) do
            if FLING_MOVERS[d.ClassName] then d:Destroy() end
        end
        -- Our own Fly driver gets a free pass, but keep the good-position marker fresh so
        -- we don't snap ourselves afterward.
        if S.fly then flingLastGoodPos = hrp.Position; return end
        -- Angular: legit HRP never spins. Zero anything past a tiny cap (kills spin flings).
        if hrp.AssemblyAngularVelocity.Magnitude > FLING_ANGULAR_CAP then
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        -- Linear: clamp launches, keep vertical (jumps/falls).
        local lv = hrp.AssemblyLinearVelocity
        if lv.Magnitude > FLING_LINEAR_CAP then
            hrp.AssemblyLinearVelocity = Vector3.new(
                math.clamp(lv.X, -50, 50), math.clamp(lv.Y, -120, 120), math.clamp(lv.Z, -50, 50))
        end
        -- Position resolver: a fling that yanks us a huge HORIZONTAL distance in one
        -- frame gets undone â€” snap back to the last sane spot and drop the launch. Legit
        -- slides/knockback/walking stay well under FLING_SNAP_STUDS; falls are vertical.
        local pos = hrp.Position
        if flingLastGoodPos then
            local dx, dz = pos.X - flingLastGoodPos.X, pos.Z - flingLastGoodPos.Z
            if (dx * dx + dz * dz) > (FLING_SNAP_STUDS * FLING_SNAP_STUDS) then
                hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
                local rot = hrp.CFrame - hrp.CFrame.Position         -- keep facing, reset position
                hrp.CFrame = CFrame.new(flingLastGoodPos) * rot
                pos = flingLastGoodPos
            end
        end
        flingLastGoodPos = pos
    end)
end
Maid:Give(RunService.Stepped:Connect(antiFlingStep))
Maid:Give(RunService.Heartbeat:Connect(antiFlingStep))

----------------------------------------------------------------------
-- Target Fling: glide onto a chosen player, sit on them, spin-launch them, then stop.
----------------------------------------------------------------------
E.flingToken = 0
E.flingPlayer = function(name)
    if not name or name == "" then notify("Velorix", "Pick a player first"); return end
    local token = E.flingToken + 1; E.flingToken = token
    task.spawn(function()
        local tp
        for _, p in ipairs(Players:GetPlayers()) do if p ~= LP and p.Name == name then tp = p; break end end
        local tChar = tp and playerChar(tp)
        local tTorso = tChar and (tChar:FindFirstChild("Torso") or tChar:FindFirstChild("HumanoidRootPart"))
        if not tTorso then notify("Velorix", "Target not found"); return end
        -- 1) Glide onto them with bounded per-frame steps (never a big jump, so the slide
        --    itself can't trip the position AC), all the way to real torso OVERLAP â€” the
        --    HRP is non-collidable, so we have to be inside them for the spin to connect.
        local t0 = os.clock()
        while isCurrent() and E.flingToken == token and os.clock() - t0 < 3 do
            local myH = myHRP()
            local tH  = tTorso.Parent and tTorso
            if not (myH and tH) then break end
            local delta = tH.Position - myH.Position
            if delta.Magnitude <= 1.4 then break end
            RunService.Heartbeat:Wait()
            local step = math.min(delta.Magnitude, 3)   -- <=3 studs/frame: bounded, AC-safe
            pcall(function() myH.CFrame = CFrame.new(myH.Position + delta.Unit * step) end)
        end
        if not (isCurrent() and E.flingToken == token) then return end
        -- 2) Overlap reached â€” spin-fling. spinFling anchors us for the burst, so we can't fly.
        if tTorso.Parent then spinFling(tTorso, 0.7) end
    end)
end
E.flingStop = function() E.flingToken = E.flingToken + 1; flingBusy = false end
end

----------------------------------------------------------------------
-- Anti-Cheat Bypass
--
-- The game's exploit AC is SERVER-SIDE: on a position/speed anomaly it tags your
-- Head with an "Exploiter" billboard ("** POTENTIAL CHEATER **") and arms
-- Server.BanTime. That detection runs in server scripts we can't read or edit,
-- and a server-issued kick/ban can't be undone from a client â€” so the ONLY real
-- defence is not tripping it. That's handled above: every script teleport is
-- bounded (Safe Teleport) so the position check never sees a jump, and signed
-- combat is accepted and never flags. This module cleans up what IS reachable
-- from the client: it strips the shame tag from your screen and zeroes the
-- client-side flag values (harmless if the server ignores the write; defeats any
-- client-read gate). It does NOT and cannot clear a real server-side ban.
----------------------------------------------------------------------
do
    local function strip(char)
        local head = char and char:FindFirstChild("Head")
        local tag  = head and head:FindFirstChild("Exploiter")
        if tag then pcall(function() tag:Destroy() end) end
    end
    local function resetFlags()
        local srv = LP:FindFirstChild("Server"); if not srv then return end
        for _, n in ipairs({ "BanTime", "Strike" }) do
            local v = srv:FindFirstChild(n)
            if v and v:IsA("IntValue") and v.Value ~= 0 then pcall(function() v.Value = 0 end) end
        end
    end
    Maid:Give(RunService.Heartbeat:Connect(function()
        if not S.acBypass then return end
        strip(LP.Character)
        resetFlags()
        local live = Workspace:FindFirstChild("Live")
        if live then for _, m in ipairs(live:GetChildren()) do strip(m) end end
    end))
    -- Instant strip the moment the server parents the tag onto us.
    local function watchChar(ch)
        if not ch then return end
        Maid:Give(ch.DescendantAdded:Connect(function(d)
            if S.acBypass and d.Name == "Exploiter" then pcall(function() d:Destroy() end) end
        end))
    end
    Maid:Give(LP.CharacterAdded:Connect(watchChar))
    watchChar(LP.Character)
end

----------------------------------------------------------------------
-- ESP (Highlight + name/health billboard + optional tracer)
----------------------------------------------------------------------
local espFolder
do
    espFolder = Instance.new("Folder"); espFolder.Name = "FOAB_ESP"
    pcall(function() espFolder.Parent = (typeof(gethui) == "function" and gethui()) or game:GetService("CoreGui") end)
    if not espFolder.Parent then espFolder.Parent = LP:WaitForChild("PlayerGui") end
    Maid:GiveInst(espFolder)

    local objects = {}
    local function clearOne(plr)
        local o = objects[plr]; if not o then return end
        pcall(function() if o.hl then o.hl:Destroy() end end)
        pcall(function() if o.bb then o.bb:Destroy() end end)
        pcall(function() if o.tracer then o.tracer:Destroy() end end)
        objects[plr] = nil
    end
    local function build(plr)
        local ch = plr.Character; if not ch then return end
        local hl = Instance.new("Highlight")
        hl.FillTransparency = 0.6; hl.OutlineTransparency = 0
        hl.Adornee = ch; hl.Parent = espFolder
        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.fromOffset(150, 34); bb.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true; bb.Parent = espFolder
        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1; lbl.Size = UDim2.fromScale(1, 1)
        lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 13
        lbl.TextStrokeTransparency = 0.4; lbl.Parent = bb
        local tracer = Instance.new("Frame")
        tracer.BorderSizePixel = 0; tracer.AnchorPoint = Vector2.new(0.5, 0.5)
        tracer.Parent = espFolder
        objects[plr] = { hl = hl, bb = bb, lbl = lbl, tracer = tracer }
    end

    Maid:Give(RunService.RenderStepped:Connect(function()
        if not S.esp then
            for p in pairs(objects) do clearOne(p) end
            return
        end
        local hrp = myHRP()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local ch  = plr.Character
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                local prt = ch and pickHitPart(ch, targetPart(ch))
                if hum and prt and hum.Health > 0 and not whitelisted(plr.Name) then
                    if not objects[plr] or not objects[plr].hl or objects[plr].hl.Adornee ~= ch then
                        clearOne(plr); build(plr)
                    end
                    local o = objects[plr]
                    o.hl.FillColor = S.espColor; o.hl.OutlineColor = S.espColor
                    o.bb.Adornee = prt
                    local dist = hrp and math.floor((prt.Position - hrp.Position).Magnitude) or 0
                    local txt = S.espNames and plr.Name or ""
                    if S.espHealth then txt = txt .. string.format("  [%d hp]", math.floor(hum.Health)) end
                    txt = txt .. string.format("  %dm", dist)
                    o.lbl.Text = txt; o.lbl.TextColor3 = S.espColor
                    if S.espTracers then
                        local sp, on = Cam:WorldToViewportPoint(prt.Position)
                        o.tracer.Visible = on
                        if on then
                            local vp = Cam.ViewportSize
                            o.tracer.BackgroundColor3 = S.espColor
                            local x1, y1 = vp.X / 2, vp.Y
                            local dx, dy = sp.X - x1, sp.Y - y1
                            local len = math.sqrt(dx * dx + dy * dy)
                            o.tracer.Size = UDim2.fromOffset(2, len)
                            o.tracer.Position = UDim2.fromOffset((x1 + sp.X) / 2, (y1 + sp.Y) / 2)
                            o.tracer.Rotation = math.deg(math.atan2(dy, dx)) - 90
                        end
                    else
                        o.tracer.Visible = false
                    end
                else
                    clearOne(plr)
                end
            end
        end
    end))
    Maid:Give(Players.PlayerRemoving:Connect(clearOne))
end

----------------------------------------------------------------------
-- UI primitives
----------------------------------------------------------------------
local function tw(o, info, props) return TweenService:Create(o, info, props) end
local SMOOTH = TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SNAP   = TweenInfo.new(0.16, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local GLIDE  = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local C = {
    Ink0 = Color3.fromRGB(8, 8, 10),   Ink1 = Color3.fromRGB(13, 13, 16),
    Ink2 = Color3.fromRGB(18, 18, 22), Ink3 = Color3.fromRGB(26, 26, 31),
    Ink4 = Color3.fromRGB(37, 37, 43), Line = Color3.fromRGB(255, 255, 255),
    Red  = Theme.Accent, RedHi = Theme.AccentGlow, RedLo = Theme.Accent2,
    RedInk = Color3.fromRGB(40, 15, 21),
    Text = Color3.fromRGB(238, 238, 242), Mid = Color3.fromRGB(150, 150, 160),
    Low  = Color3.fromRGB(98, 98, 108),
}

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(p, r) return new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p) end
local function stroke(p, col, th, trans)
    local isDefault = (col == nil or col == Theme.Stroke)
    return new("UIStroke", {
        Color = isDefault and Color3.fromRGB(255, 255, 255) or col,
        Thickness = th or 1, Transparency = isDefault and (trans or 0.94) or (trans or 0),
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, p)
end
local function gradient(p, c1, c2, rot) return new("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rot or 0 }, p) end
local function pad(p, l, t, r, b)
    return new("UIPadding", {
        PaddingLeft = UDim.new(0, l or 0), PaddingTop = UDim.new(0, t or l or 0),
        PaddingRight = UDim.new(0, r or l or 0), PaddingBottom = UDim.new(0, b or t or l or 0),
    }, p)
end

-- Tab icons â€” emoji (readable at a glance, same style as free edition).
local ICONS = {
    Combat = "👊", Weave = "🌀", Automation = "🤖", Movement = "🏃",
    Teleport = "📍", Fling = "💨", Visuals = "👁️",
    Whitelist = "🛡️", Player = "👤", Settings = "⚙️",
}
-- Emoji tab icons (per user preference). Rendered big & centered.
local function createVectorIcon(name, parent, size)
    size = size or 16
    local holder = new("Frame", {
        Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6,
    }, parent)
    local lbl = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBold,
        TextScaled = true, ZIndex = 7,
        Text = ICONS[name:gsub("%s+", "")] or "â—",
    }, holder)
    new("UITextSizeConstraint", { MaxTextSize = math.max(8, math.floor(size * 0.95)) }, lbl)
    return holder
end

local function makeLogo(parent, size, x, y, radius, zindex)
    local rad, z = radius or math.floor(size * 0.3), zindex or 3
    local holder = new("Frame", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, ZIndex = z,
    }, parent)
    corner(holder, rad); gradient(holder, Theme.AccentGlow, Theme.Accent2, 115); stroke(holder, Theme.AccentGlow, 1, 0.35)
    local txt = new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "V",
        TextColor3 = C.Text, Font = Enum.Font.GothamBlack, TextScaled = true, ZIndex = z + 2,
    }, holder)
    new("UITextSizeConstraint", { MaxTextSize = math.max(8, math.floor(size * 0.55)) }, txt)
    new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3) }, txt)
    if LOGO_ASSET then
        txt.Visible = false
        local img = new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = LOGO_ASSET, ScaleType = Enum.ScaleType.Crop, ZIndex = z + 3 }, holder)
        corner(img, rad)
    end
    return holder
end

local ScreenGui = new("ScreenGui", {
    Name = "FOAB_Suite_" .. tostring(math.random(1e4, 9e4)),
    ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true,
})
do
    local ok = false
    if typeof(gethui) == "function" then ok = pcall(function() ScreenGui.Parent = gethui() end) end
    if not ok then
        local protected = false
        pcall(function()
            local fn = nil
            pcall(function() fn = syn.protect_gui end)
            if typeof(fn) ~= "function" and typeof(protect_gui) == "function" then fn = protect_gui end
            if typeof(fn) ~= "function" and typeof(protectgui) == "function" then fn = protectgui end
            if typeof(fn) == "function" then
                fn(ScreenGui)
                protected = true
            end
        end)
        if protected then ok = pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end) end
    end
    if not ok then ok = pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end) end
    if not ScreenGui.Parent then pcall(function() ScreenGui.Parent = LP:WaitForChild("PlayerGui", 5) end) end
end
Maid:GiveInst(ScreenGui)

notify = function(title, text)
    pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", { Title = title, Text = text, Duration = 4 }) end)
end

----------------------------------------------------------------------
-- Window shell (forward-declared handles; built in the do-block)
----------------------------------------------------------------------
local mainFrame, uiVisible, setVisible
local TopBar, Sidebar, panelInner, titleLabel, subtitleLabel
local navHolder, navIndicator, headerIconHolder
local Tabs, tabOrder = {}, {}
local TabMeta = {
    Combat     = "Aura punch tools",
    Weave      = "Reactive auto-dodging",
    Automation = "Grab • stomp • push",
    Movement   = "Speed & mobility",
    Teleport   = "Slide to any player",
    Fling      = "Launch players away",
    Visuals    = "Player ESP & tracers",
    Whitelist  = "Players never targeted",
    Player     = "Styles, slams & protection",
    Settings   = "Config, session & info",
}
local UIControls, keybindRefreshers, activeCapture = {}, {}, nil
local makeTab, section, card, toggle, slider, colorpicker, dropdown, button, label

do
    local RAILW, HEADH, RADIUS = 196, 56, 18

    mainFrame = new("Frame", {
        Name = "VelorixWindow", Size = UDim2.fromOffset(752, 512),
        Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1, BorderSizePixel = 0, Active = true, Visible = false,
    }, ScreenGui)
    local winScale = new("UIScale", { Scale = 1 }, mainFrame)

    for i = 1, 4 do
        local sh = new("Frame", {
            Size = UDim2.new(1, i * 12, 1, i * 12), Position = UDim2.new(0, -i * 6, 0, -i * 6 + 3),
            BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.55 + i * 0.1,
            BorderSizePixel = 0, ZIndex = -4,
        }, mainFrame)
        corner(sh, RADIUS + i * 6)
    end
    local ambient = new("Frame", {
        Size = UDim2.new(1, 46, 1, 46), Position = UDim2.new(0, -23, 0, -23),
        BackgroundColor3 = C.Red, BackgroundTransparency = 0.95, BorderSizePixel = 0, ZIndex = -5,
    }, mainFrame)
    corner(ambient, RADIUS + 24)
    tw(ambient, TweenInfo.new(3.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.88 }):Play()

    local body = new("Frame", {
        Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink1,
        BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 1,
    }, mainFrame)
    corner(body, RADIUS)
    gradient(body, Color3.fromRGB(21, 21, 26), Color3.fromRGB(10, 10, 12), 140)
    stroke(body, C.Line, 1.4, 0.9)
    do
        local sheen = new("Frame", {
            Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = C.Line, BackgroundTransparency = 0.94,
            BorderSizePixel = 0, ZIndex = 1,
        }, body)
        new("UIGradient", { Rotation = 90 }, sheen).Transparency =
            NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(1, 1) })
    end

    -- Titlebar (drag handle)
    TopBar = new("Frame", { Name = "TitleBar", Size = UDim2.new(1, 0, 0, HEADH), BackgroundTransparency = 1, ZIndex = 8 }, body)
    new("Frame", {
        Position = UDim2.new(0, 14, 0, HEADH - 1), Size = UDim2.new(1, -28, 0, 1),
        BackgroundColor3 = C.Line, BackgroundTransparency = 0.92, BorderSizePixel = 0, ZIndex = 8,
    }, TopBar)
    makeLogo(TopBar, 32, 18, 12, 9, 9)
    new("TextLabel", {
        Position = UDim2.fromOffset(60, 11), Size = UDim2.fromOffset(200, 18), BackgroundTransparency = 1,
        Text = "VELORIX", TextColor3 = C.Text, Font = Enum.Font.GothamBlack, TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9,
    }, TopBar)
    new("TextLabel", {
        Position = UDim2.fromOffset(61, 31), Size = UDim2.fromOffset(220, 12), BackgroundTransparency = 1,
        Text = "FIGHT ON A BASEPLATE", TextColor3 = C.Mid, Font = Enum.Font.GothamMedium, TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9,
    }, TopBar)
    do
        local pill = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -84, 0.5, 0),
            Size = UDim2.fromOffset(84, 22), BackgroundColor3 = C.RedInk, BackgroundTransparency = 0.15,
            BorderSizePixel = 0, ZIndex = 9,
        }, TopBar)
        corner(pill, 11); stroke(pill, C.Red, 1, 0.35)
        local dot = new("Frame", { Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C.RedHi, BorderSizePixel = 0, ZIndex = 10 }, pill)
        corner(dot, 3)
        tw(dot, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.5 }):Play()
        new("TextLabel", {
            Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -24, 1, 0), BackgroundTransparency = 1,
            Text = "PREMIUM", TextColor3 = C.RedHi, Font = Enum.Font.GothamBold, TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 10,
        }, pill)
    end
    local function ctrlBtn(rightX, kind)
        local b = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -rightX, 0.5, 0),
            Size = UDim2.fromOffset(26, 26), BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.35,
            AutoButtonColor = false, Text = "", BorderSizePixel = 0, ZIndex = 9,
        }, TopBar)
        corner(b, 13); local bs = stroke(b, C.Line, 1, 0.9)
        if kind == "close" then
            for _, rot in ipairs({ 45, -45 }) do
                local ln = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 1.4), BackgroundColor3 = C.Mid, BorderSizePixel = 0, Rotation = rot, ZIndex = 10 }, b)
                corner(ln, 1)
            end
        else
            new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 1.4), BackgroundColor3 = C.Mid, BorderSizePixel = 0, ZIndex = 10 }, b)
        end
        Maid:Give(b.MouseEnter:Connect(function() tw(b, SNAP, { BackgroundColor3 = C.Red, BackgroundTransparency = 0.05 }):Play(); tw(bs, SNAP, { Color = C.RedHi, Transparency = 0.4 }):Play() end))
        Maid:Give(b.MouseLeave:Connect(function() tw(b, SNAP, { BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.35 }):Play(); tw(bs, SNAP, { Color = C.Line, Transparency = 0.9 }):Play() end))
        Maid:Give(b.MouseButton1Click:Connect(function() setVisible(false) end))
        return b
    end
    ctrlBtn(14, "close"); ctrlBtn(46, "min")

    -- Navigation rail (secondary drag handle)
    Sidebar = new("Frame", {
        Name = "Rail", Position = UDim2.fromOffset(0, HEADH), Size = UDim2.new(0, RAILW, 1, -HEADH),
        BackgroundColor3 = C.Ink1, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 4,
    }, body)
    gradient(Sidebar, Color3.fromRGB(16, 16, 20), Color3.fromRGB(10, 10, 13), 180)
    new("Frame", { Position = UDim2.new(1, -1, 0, 10), Size = UDim2.new(0, 1, 1, -20), BackgroundColor3 = C.Line, BackgroundTransparency = 0.92, BorderSizePixel = 0, ZIndex = 4 }, Sidebar)
    new("TextLabel", { Position = UDim2.fromOffset(20, 20), Size = UDim2.fromOffset(120, 12), BackgroundTransparency = 1, Text = "NAVIGATION", TextColor3 = C.Low, Font = Enum.Font.GothamBold, TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }, Sidebar)
    -- Navigation list scrolls (tabs overflow the rail once there are several).
    navHolder = new("ScrollingFrame", {
        Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -20, 1, -136),
        BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.Red, ScrollBarImageTransparency = 0.4,
    }, Sidebar)
    do
        local uc = new("Frame", { Position = UDim2.new(0, 12, 1, -70), Size = UDim2.new(1, -24, 0, 56), BackgroundColor3 = C.Ink2, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 5 }, Sidebar)
        corner(uc, 12); stroke(uc, C.Line, 1, 0.9)
        new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Red, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 6 }, uc)
        local pfp = new("Frame", { Position = UDim2.fromOffset(9, 10), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = C.Ink3, BorderSizePixel = 0, ZIndex = 6 }, uc)
        corner(pfp, 10); stroke(pfp, C.Red, 1.2, 0.3)
        local img = new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "rbxthumb://type=AvatarHeadShot&id=" .. LP.UserId .. "&w=150&h=150", ScaleType = Enum.ScaleType.Crop, ZIndex = 7 }, pfp)
        corner(img, 10)
        new("TextLabel", { Position = UDim2.fromOffset(54, 10), Size = UDim2.new(1, -62, 0, 16), BackgroundTransparency = 1, Text = LP.Name, TextColor3 = C.Text, Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 6 }, uc)
        new("TextLabel", { Position = UDim2.fromOffset(54, 28), Size = UDim2.new(1, -62, 0, 14), BackgroundTransparency = 1, Text = "Premium member", TextColor3 = C.RedHi, Font = Enum.Font.GothamMedium, TextSize = 9.5, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 }, uc)
    end

    local Content = new("Frame", { Name = "Content", Position = UDim2.fromOffset(RAILW, HEADH), Size = UDim2.new(1, -RAILW, 1, -HEADH), BackgroundTransparency = 1, ZIndex = 2 }, body)
    pad(Content, 22, 18, 18, 14)
    titleLabel = new("TextLabel", { Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, -60, 0, 26), BackgroundTransparency = 1, Text = "COMBAT", TextColor3 = C.Text, Font = Enum.Font.GothamBlack, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, Content)
    subtitleLabel = new("TextLabel", { Position = UDim2.fromOffset(2, 31), Size = UDim2.new(1, -60, 0, 15), BackgroundTransparency = 1, Text = TabMeta.Combat, TextColor3 = C.Mid, Font = Enum.Font.Gotham, TextSize = 11.5, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, Content)
    headerIconHolder = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = C.Ink2, BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 3 }, Content)
    corner(headerIconHolder, 12); stroke(headerIconHolder, C.Red, 1, 0.45)
    do
        local div = new("Frame", { Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Line, BorderSizePixel = 0, ZIndex = 3 }, Content)
        new("UIGradient", { Color = ColorSequence.new(C.Red, C.Line) }, div).Transparency =
            NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.5, 0.85), NumberSequenceKeypoint.new(1, 1) })
    end
    panelInner = new("Frame", { Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 1, -66), BackgroundTransparency = 1, ZIndex = 2 }, Content)

    uiVisible = true
    setVisible = function(v)
        uiVisible = v and true or false
        if uiVisible then
            mainFrame.Visible = true; winScale.Scale = 0.92; body.BackgroundTransparency = 1
            tw(winScale, GLIDE, { Scale = 1 }):Play(); tw(body, SMOOTH, { BackgroundTransparency = 0 }):Play()
        else
            local a = tw(winScale, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Scale = 0.93 })
            local b = tw(body, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
            b.Completed:Connect(function() if not uiVisible then mainFrame.Visible = false end end)
            a:Play(); b:Play()
        end
    end
end

----------------------------------------------------------------------
-- Tabs + component factories
----------------------------------------------------------------------
makeTab = function(name)
    local idx = #tabOrder
    local frame = new("Frame", { Name = "Nav_" .. name, Position = UDim2.fromOffset(0, idx * 40), Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.Ink3, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, navHolder)
    corner(frame, 10)
    local hstroke = stroke(frame, C.Line, 1, 1)
    local iconWrap = new("Frame", { Position = UDim2.fromOffset(7, 5), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 6 }, frame)
    corner(iconWrap, 8); local iconStroke = stroke(iconWrap, C.Line, 1, 0.9)
    createVectorIcon(name, iconWrap, 13)
    local lbl = new("TextLabel", { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -52, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = name, TextColor3 = C.Mid, TextSize = 12.5, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6 }, frame)
    local click = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 7 }, frame)
    local page = new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Red, ScrollBarImageTransparency = 0.35, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, ZIndex = 2 }, panelInner)
    new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10) }, page)
    local function deselect()
        page.Visible = false
        tw(frame, SMOOTH, { BackgroundTransparency = 1 }):Play(); tw(hstroke, SMOOTH, { Transparency = 1 }):Play()
        tw(iconWrap, SMOOTH, { BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.4 }):Play(); tw(iconStroke, SMOOTH, { Color = C.Line, Transparency = 0.9 }):Play()
        lbl.TextColor3 = C.Mid; lbl.Font = Enum.Font.GothamMedium
    end
    local function select()
        for _, t in pairs(Tabs) do t.deselect() end
        page.Visible = true
        tw(frame, SMOOTH, { BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.25 }):Play(); tw(hstroke, SMOOTH, { Color = C.Red, Transparency = 0.78 }):Play()
        tw(iconWrap, SMOOTH, { BackgroundColor3 = C.Red, BackgroundTransparency = 0.12 }):Play(); tw(iconStroke, SMOOTH, { Color = C.RedHi, Transparency = 0.35 }):Play()
        lbl.TextColor3 = C.Text; lbl.Font = Enum.Font.GothamBold
        titleLabel.Text = name:upper(); subtitleLabel.Text = TabMeta[name] or "Fight on a Baseplate â€¢ Premium"
        for _, ch in ipairs(headerIconHolder:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
        createVectorIcon(name, headerIconHolder, 18)
    end
    Maid:Give(click.MouseButton1Click:Connect(select))
    Maid:Give(click.MouseEnter:Connect(function() if not page.Visible then tw(frame, SNAP, { BackgroundColor3 = C.Ink2, BackgroundTransparency = 0.45 }):Play(); tw(hstroke, SNAP, { Color = C.Line, Transparency = 0.92 }):Play(); lbl.TextColor3 = C.Text end end))
    Maid:Give(click.MouseLeave:Connect(function() if not page.Visible then tw(frame, SNAP, { BackgroundTransparency = 1 }):Play(); tw(hstroke, SNAP, { Transparency = 1 }):Play(); lbl.TextColor3 = C.Mid end end))
    Tabs[name] = { frame = frame, page = page, select = select, deselect = deselect }
    table.insert(tabOrder, name)
    return page
end

section = function(page, title)
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, BorderSizePixel = 0 }, page)
    local dia = new("Frame", { Position = UDim2.fromOffset(3, 13), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = C.Red, BorderSizePixel = 0, Rotation = 45, ZIndex = 2 }, holder)
    corner(dia, 2); gradient(dia, C.RedHi, C.RedLo, 90)
    new("TextLabel", { Position = UDim2.fromOffset(20, 8), Size = UDim2.new(1, -20, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = title:upper(), TextColor3 = C.Text, TextSize = 11.5, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2 }, holder)
    local div = new("Frame", { Position = UDim2.new(0, 3, 0, 29), Size = UDim2.new(1, -3, 0, 1), BackgroundColor3 = C.Line, BorderSizePixel = 0, ZIndex = 2 }, holder)
    new("UIGradient", { Color = ColorSequence.new(C.Red, C.Line) }, div).Transparency =
        NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 0.85), NumberSequenceKeypoint.new(1, 1) })
    return holder
end

card = function(page, h)
    h = h or 40
    local f = new("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, BorderSizePixel = 0 }, page)
    local inner = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink2, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 2 }, f)
    corner(inner, 10); local s = stroke(inner, C.Line, 1, 0.93)
    new("Frame", { Size = UDim2.new(1, -18, 0, 1), Position = UDim2.fromOffset(9, 1), BackgroundColor3 = C.Line, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 3 }, inner)
    local acc = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(2, 0), BackgroundColor3 = C.Red, BorderSizePixel = 0, ZIndex = 4 }, inner)
    corner(acc, 1)
    local accH = math.max(12, h - 16)
    Maid:Give(inner.MouseEnter:Connect(function() tw(inner, SNAP, { BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.12 }):Play(); tw(s, SNAP, { Color = C.Red, Transparency = 0.72 }):Play(); tw(acc, SNAP, { Size = UDim2.fromOffset(2.5, accH) }):Play() end))
    Maid:Give(inner.MouseLeave:Connect(function() tw(inner, SNAP, { BackgroundColor3 = C.Ink2, BackgroundTransparency = 0.35 }):Play(); tw(s, SNAP, { Color = C.Line, Transparency = 0.93 }):Play(); tw(acc, SNAP, { Size = UDim2.fromOffset(2, 0) }):Play() end))
    return inner
end

toggle = function(page, text, default, callback)
    local TR_W, TR_H, KNOB, MARG = 46, 24, 18, 3
    local f = card(page, 44)
    new("TextLabel", { Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text, TextColor3 = C.Text, TextSize = 12.5, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 3 }, f)
    local track = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(TR_W, TR_H), BackgroundColor3 = default and C.Red or C.Ink4, BorderSizePixel = 0, ZIndex = 3 }, f)
    corner(track, TR_H / 2)
    local trackStroke = stroke(track, default and C.RedHi or C.Line, 1.2, default and 0.35 or 0.85)
    local knob = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, default and (TR_W - KNOB - MARG) or MARG, 0.5, 0), Size = UDim2.fromOffset(KNOB, KNOB), BackgroundColor3 = Color3.fromRGB(250, 250, 252), BorderSizePixel = 0, ZIndex = 5 }, track)
    corner(knob, KNOB / 2)
    local knobScale = new("UIScale", { Scale = 1 }, knob)
    local state = default and true or false
    local function render(anim)
        local slide = anim and TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out) or TweenInfo.new(0)
        local col = anim and SNAP or TweenInfo.new(0)
        tw(track, col, { BackgroundColor3 = state and C.Red or C.Ink4 }):Play()
        tw(trackStroke, col, { Color = state and C.RedHi or C.Line, Transparency = state and 0.5 or 0.9 }):Play()
        tw(knob, slide, { Position = UDim2.new(0, state and (TR_W - KNOB - MARG) or MARG, 0.5, 0) }):Play()
        if anim then knobScale.Scale = 0.82; tw(knobScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() end
    end
    local function setState(v, fire)
        local nv = v and true or false
        if nv == state and fire == false then return end
        state = nv; render(true)
        if fire ~= false then callback(state) end
    end
    local btn = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 6 }, f)
    Maid:Give(btn.MouseButton1Click:Connect(function() setState(not state, true) end))
    UIControls[text] = { get = function() return state end, set = function(v) setState(v, true) end }
    if default then task.spawn(callback, true) end
    return f
end

slider = function(page, text, min, max, default, suffix, callback)
    local f = card(page, 54)
    new("TextLabel", { Size = UDim2.new(1, -96, 0, 18), Position = UDim2.fromOffset(14, 8), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text, TextColor3 = C.Text, TextSize = 12.5, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, f)
    local valPill = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 7), Size = UDim2.fromOffset(66, 20), BackgroundColor3 = C.Ink4, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 3 }, f)
    corner(valPill, 6); stroke(valPill, C.Line, 1, 0.9)
    local valLbl = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = tostring(default) .. (suffix or ""), TextColor3 = C.RedHi, TextSize = 11.5, ZIndex = 4 }, valPill)
    local bar = new("Frame", { Size = UDim2.new(1, -28, 0, 6), Position = UDim2.fromOffset(14, 38), BackgroundColor3 = C.Ink4, BorderSizePixel = 0, ZIndex = 3 }, f)
    corner(bar, 3)
    local fill = new("Frame", { Size = UDim2.fromScale((default - min) / (max - min), 1), BackgroundColor3 = C.Red, BorderSizePixel = 0, ZIndex = 4 }, bar)
    corner(fill, 3); gradient(fill, C.RedHi, C.Red, 0)
    local thumb = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.fromRGB(250, 250, 252), BorderSizePixel = 0, ZIndex = 6 }, bar)
    corner(thumb, 7); stroke(thumb, C.Red, 1.5, 0.15)
    local dragging, curValue = false, default
    local isFloat = (max - min) <= 5
    local function apply(value, fire)
        curValue = math.clamp(value, min, max)
        if not isFloat then curValue = math.floor(curValue + 0.5) else curValue = math.floor(curValue * 100 + 0.5) / 100 end
        local pct = (curValue - min) / (max - min)
        local qi = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        tw(fill, qi, { Size = UDim2.fromScale(pct, 1) }):Play(); tw(thumb, qi, { Position = UDim2.new(pct, 0, 0.5, 0) }):Play()
        valLbl.Text = tostring(curValue) .. (suffix or "")
        if fire ~= false then callback(curValue) end
    end
    local function setFromX(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        apply(min + (max - min) * rel, true)
    end
    local hit = new("TextButton", { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 28), BackgroundTransparency = 1, Text = "", ZIndex = 7 }, f)
    Maid:Give(hit.MouseButton1Down:Connect(function() dragging = true; setFromX(UserInputService:GetMouseLocation().X) end))
    Maid:Give(UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end end))
    Maid:Give(UserInputService.InputChanged:Connect(function(i) if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then setFromX(i.Position.X) end end))
    UIControls[text] = { get = function() return curValue end, set = function(v) apply(v, true) end }
    return f
end

colorpicker = function(page, text, default, callback)
    local f = card(page, 104)
    new("TextLabel", { Size = UDim2.new(1, -72, 0, 20), Position = UDim2.fromOffset(14, 8), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text, TextColor3 = C.Text, TextSize = 12.5, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, f)
    local swatch = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(40, 20), BackgroundColor3 = default, BorderSizePixel = 0, ZIndex = 3 }, f)
    corner(swatch, 6); stroke(swatch, C.Line, 1, 0.75)
    local r, g, b = math.floor(default.R * 255 + 0.5), math.floor(default.G * 255 + 0.5), math.floor(default.B * 255 + 0.5)
    local function fire() local col = Color3.fromRGB(r, g, b); swatch.BackgroundColor3 = col; callback(col) end
    local function channel(yOff, chanColor, getv, setv)
        local barc = new("Frame", { Size = UDim2.new(1, -28, 0, 5), Position = UDim2.fromOffset(14, yOff), BackgroundColor3 = C.Ink4, BorderSizePixel = 0, ZIndex = 3 }, f)
        corner(barc, 3)
        local fillc = new("Frame", { Size = UDim2.fromScale(getv() / 255, 1), BackgroundColor3 = chanColor, BorderSizePixel = 0, ZIndex = 4 }, barc)
        corner(fillc, 3)
        local thumbc = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(getv() / 255, 0, 0.5, 0), Size = UDim2.fromOffset(11, 11), BackgroundColor3 = Color3.fromRGB(250, 250, 252), BorderSizePixel = 0, ZIndex = 6 }, barc)
        corner(thumbc, 6); stroke(thumbc, chanColor, 1.2, 0.2)
        local dragging = false
        local function setFromX(x)
            local rel = math.clamp((x - barc.AbsolutePosition.X) / barc.AbsoluteSize.X, 0, 1)
            setv(math.floor(rel * 255 + 0.5)); fillc.Size = UDim2.fromScale(getv() / 255, 1); thumbc.Position = UDim2.new(getv() / 255, 0, 0.5, 0); fire()
        end
        local hit = new("TextButton", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, yOff - 5), BackgroundTransparency = 1, Text = "", ZIndex = 7 }, f)
        Maid:Give(hit.MouseButton1Down:Connect(function() dragging = true; setFromX(UserInputService:GetMouseLocation().X) end))
        Maid:Give(UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end end))
        Maid:Give(UserInputService.InputChanged:Connect(function(i) if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then setFromX(i.Position.X) end end))
        return function() fillc.Size = UDim2.fromScale(getv() / 255, 1); thumbc.Position = UDim2.new(getv() / 255, 0, 0.5, 0) end
    end
    local refR = channel(42, Color3.fromRGB(227, 60, 60), function() return r end, function(v) r = v end)
    local refG = channel(64, Color3.fromRGB(70, 210, 90), function() return g end, function(v) g = v end)
    local refB = channel(86, Color3.fromRGB(70, 130, 235), function() return b end, function(v) b = v end)
    UIControls[text] = {
        get = function() return string.format("%02X%02X%02X", r, g, b) end,
        set = function(hex)
            if typeof(hex) == "Color3" then r, g, b = math.floor(hex.R * 255 + 0.5), math.floor(hex.G * 255 + 0.5), math.floor(hex.B * 255 + 0.5)
            elseif type(hex) == "string" and #hex >= 6 then r = tonumber(hex:sub(1, 2), 16) or r; g = tonumber(hex:sub(3, 4), 16) or g; b = tonumber(hex:sub(5, 6), 16) or b end
            refR(); refG(); refB(); fire()
        end,
    }
    task.spawn(fire)
    return f
end

button = function(page, text, callback)
    local f = card(page, 40)
    local b = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, Text = text, TextColor3 = C.RedHi, TextSize = 12.5, ZIndex = 5 }, f)
    Maid:Give(b.MouseButton1Click:Connect(function() pcall(callback) end))
    return b, f
end

-- Dropdown: header row that expands a scrollable option list. Options are pulled
-- live via getOptions() each time it opens, so player lists stay current.
dropdown = function(page, text, getOptions, onSelect)
    local ROWH = 30
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 3 }, page)
    local head = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.Ink2, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 3 }, holder)
    corner(head, 10); local hs = stroke(head, C.Line, 1, 0.93)
    new("TextLabel", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.42, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = text, TextColor3 = C.Text, TextSize = 12.5, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 }, head)
    local valBtn = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0.52, -12, 0, 30), BackgroundColor3 = C.Ink4, BackgroundTransparency = 0.15, AutoButtonColor = false, Font = Enum.Font.GothamMedium, Text = "Select", TextColor3 = C.RedHi, TextSize = 11.5, TextTruncate = Enum.TextTruncate.AtEnd, BorderSizePixel = 0, ZIndex = 4 }, head)
    -- drawn down-chevron (no glyph â€” avoids the tofu box)
    do
        local a = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -9, 0.5, -1), Size = UDim2.fromOffset(6, 2), BackgroundColor3 = C.RedHi, BorderSizePixel = 0, Rotation = 45, ZIndex = 5 }, valBtn)
        new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, a)
        local b = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0.5, -1), Size = UDim2.fromOffset(6, 2), BackgroundColor3 = C.RedHi, BorderSizePixel = 0, Rotation = -45, ZIndex = 5 }, valBtn)
        new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
        new("UIPadding", { PaddingRight = UDim.new(0, 14) }, valBtn)
    end
    corner(valBtn, 7); stroke(valBtn, C.Line, 1, 0.85)
    local listWrap = new("ScrollingFrame", { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = C.Ink1, BackgroundTransparency = 0.1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.Red, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, ClipsDescendants = true, ZIndex = 8 }, holder)
    corner(listWrap, 8); stroke(listWrap, C.Red, 1, 0.7)
    new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, listWrap)
    new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, listWrap)
    local open = false
    local function collapse()
        open = false; listWrap.Visible = false; holder.Size = UDim2.new(1, 0, 0, 44); head.ZIndex = 3
        tw(hs, SNAP, { Color = C.Line, Transparency = 0.93 }):Play()
    end
    local function rebuild()
        for _, ch in ipairs(listWrap:GetChildren()) do if ch:IsA("TextButton") or ch:IsA("TextLabel") then ch:Destroy() end end
        local opts = getOptions() or {}
        for _, opt in ipairs(opts) do
            local b = new("TextButton", { Size = UDim2.new(1, 0, 0, ROWH), BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.2, AutoButtonColor = false, Font = Enum.Font.GothamMedium, Text = opt, TextColor3 = C.Text, TextSize = 12, BorderSizePixel = 0, ZIndex = 9 }, listWrap)
            corner(b, 6)
            Maid:Give(b.MouseEnter:Connect(function() tw(b, SNAP, { BackgroundColor3 = C.Red, BackgroundTransparency = 0.15 }):Play() end))
            Maid:Give(b.MouseLeave:Connect(function() tw(b, SNAP, { BackgroundColor3 = C.Ink3, BackgroundTransparency = 0.2 }):Play() end))
            Maid:Give(b.MouseButton1Click:Connect(function() valBtn.Text = opt; collapse(); pcall(onSelect, opt) end))
        end
        if #opts == 0 then new("TextLabel", { Size = UDim2.new(1, 0, 0, ROWH), BackgroundTransparency = 1, Font = Enum.Font.Gotham, Text = "(none)", TextColor3 = C.Low, TextSize = 11, ZIndex = 9 }, listWrap) end
        return math.max(1, #opts)
    end
    Maid:Give(valBtn.MouseButton1Click:Connect(function()
        open = not open
        if open then
            local n = rebuild()
            local h = math.min(158, n * (ROWH + 2) + 8)
            listWrap.Size = UDim2.new(1, 0, 0, h); listWrap.Visible = true
            holder.Size = UDim2.new(1, 0, 0, 44 + 6 + h); head.ZIndex = 10
            tw(hs, SNAP, { Color = C.Red, Transparency = 0.6 }):Play()
        else collapse() end
    end))
    return holder
end

label = function(page, color)
    local f = new("Frame", { Size = UDim2.new(1, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Ink1, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, page)
    corner(f, 9); stroke(f, C.Line, 1, 0.93)
    new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }, f)
    return new("TextLabel", { Size = UDim2.new(1, 0, 0, 12), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = "", TextColor3 = color or C.Mid, TextWrapped = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, f)
end

----------------------------------------------------------------------
-- Config engine (optional filesystem)
----------------------------------------------------------------------
local hasFS = typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
local CFG_FILE = "VelorixFOAB_config.json"
local function saveConfig()
    if not hasFS then notify("Velorix", "No filesystem â€” config unavailable"); return end
    local data = {}
    for k, ctrl in pairs(UIControls) do data[k] = ctrl.get() end
    data.__whitelist = {}
    for n in pairs(whitelist) do table.insert(data.__whitelist, n) end
    local ok = pcall(function() writefile(CFG_FILE, HttpService:JSONEncode(data)) end)
    notify("Velorix", ok and "Config saved" or "Save failed")
end
local function loadConfig()
    if not (hasFS and isfile(CFG_FILE)) then notify("Velorix", "No saved config"); return end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(CFG_FILE)) end)
    if not ok or type(data) ~= "table" then notify("Velorix", "Config corrupt"); return end
    if type(data.__whitelist) == "table" then
        whitelist = {}
        for _, n in ipairs(data.__whitelist) do whitelist[string.lower(n)] = true end
    end
    for k, v in pairs(data) do
        if k ~= "__whitelist" and UIControls[k] then pcall(UIControls[k].set, v) end
    end
    notify("Velorix", "Config loaded")
end

----------------------------------------------------------------------
-- Build the feature tabs
----------------------------------------------------------------------
local refreshWhitelist  -- forward-declared (Whitelist tab)
do
    ------------------------------------------------------------------ COMBAT
    local combat = makeTab("Combat")
    section(combat, "Smart Punch Aura")
    toggle(combat, "Smart Punch Aura", S.auraPunch, function(v) S.auraPunch = v; if v then ensureFists() else clearAuraLock() end end)
    toggle(combat, "Auto-Equip Fist", S.autoEquip, function(v) S.autoEquip = v; if v then ensureFists() end end)
    slider(combat, "Aura Range", 6, 60, S.auraRange, " studs", function(v) S.auraRange = v end)
    slider(combat, "Punch Delay", 0.08, 0.80, S.auraDelay, "s", function(v) S.auraDelay = v end)
    toggle(combat, "Wall Check (LOS)", S.auraLOS, function(v) S.auraLOS = v end)
    toggle(combat, "Include NPCs", S.auraNPC, function(v) S.auraNPC = v end)
    toggle(combat, "Punch Through Weave", S.auraHitWeave, function(v) S.auraHitWeave = v end)
    toggle(combat, "Punch Animation", S.punchAnim, function(v) S.punchAnim = v end)
    toggle(combat, "Lock Onto Target", S.auraLockOn, function(v) S.auraLockOn = v; if not v then clearAuraLock() end end)
    slider(combat, "Lock On Strength", 1, 100, S.auraLockStr, "%", function(v) S.auraLockStr = v end)
    toggle(combat, "Walk To Target (lock til death)", S.walkToNearest, function(v) S.walkToNearest = v; if not v then clearAuraLock() end end)
    label(combat, C.Warn).Text = "Smart Punch Aura only swings when a target is in reach + in your hit cone. Lock Onto Target smoothly aims you at them; Lock On Strength controls how fast/hard it sticks. Punch Animation off = silent hits. Walk To Target auto-walks you to the closest player at any range and stays locked on them until they die, then switches to the next-nearest â€” real walking (no teleport, works with fists out) so it won't flag, and the aura keeps swinging."

    ------------------------------------------------------------------ WEAVE
    local weave = makeTab("Weave")
    section(weave, "Auto Weave")
    toggle(weave, "Auto Weave", S.autoWeave, function(v) S.autoWeave = v; if not v then stopWeaveVisual() end end)
    slider(weave, "Weave Range", 4, 26, S.weaveRange, " studs", function(v) S.weaveRange = v end)
    slider(weave, "Weave Cooldown", 0.08, 0.60, S.weaveCd, "s", function(v) S.weaveCd = v end)
    toggle(weave, "Facing Check (dodge only aimed swings)", S.weaveFacing, function(v) S.weaveFacing = v end)
    toggle(weave, "Weave Animation", S.weaveAnim, function(v) S.weaveAnim = v; if not v then stopWeaveVisual() end end)

    section(weave, "Cooldown")
    toggle(weave, "No Weave Cooldown", S.noWeaveCd, function(v) S.noWeaveCd = v end)
    label(weave, C.Warn).Text = "No Weave Cooldown spams signed Weave packets with no lock/stun â€” bypasses the game's 0.45s WEAVE cell."

    ------------------------------------------------------------------ AUTOMATION
    local auto = makeTab("Automation")
    section(auto, "Grab")
    toggle(auto, "Auto Grab", S.autoGrab, function(v) S.autoGrab = v end)
    slider(auto, "Grab Range", 4, 20, S.grabRange, " studs", function(v) S.grabRange = v end)
    section(auto, "Stomp (downed enemies)")
    toggle(auto, "Auto Stomp", S.autoStomp, function(v) S.autoStomp = v end)
    slider(auto, "Stomp Range", 4, 24, S.stompRange, " studs", function(v) S.stompRange = v end)
    section(auto, "Push")
    toggle(auto, "Auto Push", S.autoPush, function(v) S.autoPush = v end)
    slider(auto, "Push Range", 4, 24, S.pushRange, " studs", function(v) S.pushRange = v end)
end
do
    ------------------------------------------------------------------ MOVEMENT
    local move = makeTab("Movement")
    section(move, "Speed")
    toggle(move, "WalkSpeed Override", S.walkEnabled, function(v) S.walkEnabled = v; if E.applyWalk then E.applyWalk() end end)
    slider(move, "WalkSpeed", 13, 40, S.walkSpeed, "", function(v) S.walkSpeed = v; if E.applyWalk then E.applyWalk() end end)
    section(move, "Jump")
    toggle(move, "Infinite Jump", S.infJump, function(v) S.infJump = v; if E.applyJump then E.applyJump() end end)
    section(move, "Fly")
    toggle(move, "Fly", S.fly, function(v) S.fly = v end)
    slider(move, "Fly Speed", 20, 250, S.flySpeed, " st/s", function(v) S.flySpeed = v end)
    label(move, C.Mid).Text = "Fly: WASD to move (camera-relative), Space = up, Shift/Ctrl = down, release to hover. Flight is a built-in mechanic every player here has, so it's not fling-flagged, and Aura/combat still work mid-air. Anti-Fling won't clamp your own fly velocity."

    section(move, "Noclip")
    toggle(move, "Noclip", S.noclip, function(v) S.noclip = v; if not v and E.restoreNoclip then E.restoreNoclip() end end)
    label(move, C.Mid).Text = "Phases your character through parts and other players (your collision is client-owned). Pairs well with Fly. Collision is restored exactly when you toggle it off."

    section(move, "Freecam")
    toggle(move, "Freecam", S.freecam, function(v) S.freecam = v; if E.setFreecam then E.setFreecam(v) end end)
    slider(move, "Freecam Speed", 0.25, 4, S.freecamSpeed, "x", function(v) S.freecamSpeed = v end)
    label(move, C.Mid).Text = "Detaches the camera to scout the map â€” hold RIGHT-MOUSE to look, WASD to move, E/Q up-down, Shift = faster. Your character stays where it is; toggle off to snap back."
    label(move, C.Warn).Text = "Speed overrides the value the game's own loop applies (no frame-fight). Jump is force-enabled (the game ships it off). Keep speed modest â€” big values can trip server checks."

    ------------------------------------------------------------------ TELEPORT
    local tpTab = makeTab("Teleport")
    section(tpTab, "Slide To Player")
    dropdown(tpTab, "Target", function()
        local names = {}
        for _, p in ipairs(Players:GetPlayers()) do if p ~= LP then names[#names + 1] = p.Name end end
        table.sort(names); return names
    end, function(name) S.tpTarget = name end)
    slider(tpTab, "Slide Speed", 20, 200, S.tpSpeed, " st/s", function(v) S.tpSpeed = v end)
    button(tpTab, "Slide To Selected", function() E.slideTo(S.tpTarget) end)
    button(tpTab, "Stop", function() if E.slideStop then E.slideStop() end end)
    label(tpTab, C.Mid).Text = "Smoothly glides to the selected player at the chosen speed (a gradual slide, not an instant teleport, so it's far less likely to flag). Pick a target from the dropdown first; press Stop any time."

    ------------------------------------------------------------------ FLING
    local flingTab = makeTab("Fling")
    section(flingTab, "Target Fling")
    dropdown(flingTab, "Target", function()
        local names = {}
        for _, p in ipairs(Players:GetPlayers()) do if p ~= LP then names[#names + 1] = p.Name end end
        table.sort(names); return names
    end, function(name) S.flingTarget = name end)
    slider(flingTab, "Fling Power", 20000, 500000, S.flingPower, "", function(v) S.flingPower = v end)
    button(flingTab, "Fling Selected", function() E.flingPlayer(S.flingTarget) end)
    button(flingTab, "Stop", function() if E.flingStop then E.flingStop() end end)

    section(flingTab, "Touch Fling")
    toggle(flingTab, "Touch Fling", S.touchFling, function(v)
        S.touchFling = v
        if not v then local h = myHRP(); if h then pcall(function() h.AssemblyAngularVelocity = Vector3.zero end) end end
    end)
    label(flingTab, C.Warn).Text = "Touch Fling: turn it ON and get near anyone â€” they launch, nothing else to do. Target Fling glides you onto the selected player and flings them. You are ANCHORED for the split-second of each fling, so you can NEVER be flung yourself (that was the old bug â€” fixed). Fling Power nudges how hard they go (best around the middle; maxing it makes the fling LESS stable). Flinging is server-visible and can draw an exploiter flag â€” use it sparingly."
end
do
    ------------------------------------------------------------------ VISUALS
    local vis = makeTab("Visuals")
    section(vis, "Player ESP")
    toggle(vis, "Enable ESP", S.esp, function(v) S.esp = v end)
    toggle(vis, "Show Names", S.espNames, function(v) S.espNames = v end)
    toggle(vis, "Show Health", S.espHealth, function(v) S.espHealth = v end)
    toggle(vis, "Tracers", S.espTracers, function(v) S.espTracers = v end)
    colorpicker(vis, "ESP Color", S.espColor, function(col) S.espColor = col end)

    section(vis, "Camera")
    slider(vis, "Field of View", 40, 120, S.fov, "", function(v) S.fov = v end)
end
do
    ------------------------------------------------------------------ WHITELIST
    local wl = makeTab("Whitelist")
    local plHolder, nmHolder
    section(wl, "Add By Name")
    do
        local rowCard = card(wl, 44)
        local box = new("TextBox", {
            Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -104, 0, 30), BackgroundColor3 = C.Ink4,
            BackgroundTransparency = 0.15, Font = Enum.Font.GothamMedium, PlaceholderText = "Player nameâ€¦",
            Text = "", TextColor3 = C.Text, TextSize = 12, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
        }, rowCard)
        corner(box, 7); stroke(box, C.Line, 1, 0.88); new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
        local add = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(78, 30), BackgroundColor3 = C.Red, Font = Enum.Font.GothamBold, Text = "ADD", TextColor3 = C.Text, TextSize = 12, AutoButtonColor = false, ZIndex = 5 }, rowCard)
        corner(add, 7); gradient(add, C.RedHi, C.RedLo, 90)
        Maid:Give(add.MouseButton1Click:Connect(function()
            local n = (box.Text or ""):match("^%s*(.-)%s*$")
            if n and n ~= "" then whitelist[string.lower(n)] = true; box.Text = ""; refreshWhitelist() end
        end))
        Maid:Give(box.FocusLost:Connect(function(enter)
            if not enter then return end
            local n = (box.Text or ""):match("^%s*(.-)%s*$")
            if n and n ~= "" then whitelist[string.lower(n)] = true; box.Text = ""; refreshWhitelist() end
        end))
    end

    section(wl, "Players In Server  Â·  tap to toggle")
    plHolder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, wl)
    new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, plHolder)
    section(wl, "Whitelisted")
    nmHolder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, wl)
    new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, nmHolder)

    refreshWhitelist = function()
        -- current-players list (click SAFE/TARGET to toggle)
        for _, ch in ipairs(plHolder:GetChildren()) do if not ch:IsA("UIListLayout") then ch:Destroy() end end
        local any = false
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                any = true
                local on = whitelisted(plr.Name)
                local row = card(plHolder, 34)
                new("TextLabel", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -96, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = plr.Name, TextColor3 = C.Text, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 }, row)
                local b = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(74, 22), BackgroundColor3 = on and C.Red or C.Ink4, Font = Enum.Font.GothamBold, Text = on and "SAFE âœ“" or "TARGET", TextColor3 = on and C.Text or C.Mid, TextSize = 10.5, AutoButtonColor = false, ZIndex = 5 }, row)
                corner(b, 6); stroke(b, on and C.RedHi or C.Line, 1, on and 0.4 or 0.85)
                local nm = plr.Name
                Maid:Give(b.MouseButton1Click:Connect(function()
                    local key = string.lower(nm)
                    if whitelist[key] then whitelist[key] = nil else whitelist[key] = true end
                    refreshWhitelist()
                end))
            end
        end
        if not any then label(plHolder, C.Low).Text = "No other players in the server." end
        -- whitelisted names list (typed or toggled) with remove
        for _, ch in ipairs(nmHolder:GetChildren()) do if not ch:IsA("UIListLayout") then ch:Destroy() end end
        local names = {}
        for n in pairs(whitelist) do table.insert(names, n) end
        table.sort(names)
        if #names == 0 then
            label(nmHolder, C.Low).Text = "No players whitelisted."
        else
            for _, n in ipairs(names) do
                local row = card(nmHolder, 34)
                new("TextLabel", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -60, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, Text = n, TextColor3 = C.Text, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 }, row)
                local del = new("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(40, 22), BackgroundColor3 = C.Ink4, Font = Enum.Font.GothamBold, Text = "âœ•", TextColor3 = C.RedHi, TextSize = 12, AutoButtonColor = false, ZIndex = 5 }, row)
                corner(del, 6); stroke(del, C.Red, 1, 0.5)
                local nm = n
                Maid:Give(del.MouseButton1Click:Connect(function() whitelist[nm] = nil; refreshWhitelist() end))
            end
        end
    end
    refreshWhitelist()
    Maid:Give(Players.PlayerAdded:Connect(function() task.defer(refreshWhitelist) end))
    Maid:Give(Players.PlayerRemoving:Connect(function() task.defer(refreshWhitelist) end))
end
do
    ------------------------------------------------------------------ PLAYER
    local player = makeTab("Player")
    section(player, "Style Unlocker")
    dropdown(player, "Style", function() return { "Default", "Tyson", "Strong", "Katana" } end,
        function(name) S.styleName = name; E.equipStyleServer(name); E.applyStyle() end)
    toggle(player, "Force Style", S.styleForce, function(v)
        S.styleForce = v; if v then E.equipStyleServer(S.styleName); E.applyStyle() end
    end)

    section(player, "Slam Unlocker")
    dropdown(player, "Slam", function() return { "Overhead Slam", "Neck Slam", "Back Slam" } end,
        function(name) S.finisherName = name; E.equipFinisherServer(name); E.applyFinisher() end)
    toggle(player, "Force Slam", S.finisherForce, function(v)
        S.finisherForce = v; if v then E.equipFinisherServer(S.finisherName); E.applyFinisher() end
    end)

    section(player, "Gamepasses")
    button(player, "Apply Gamepass Perks", function()
        S.freeGamepasses = true; E.applyGamepasses(); notify("Velorix", "Faster Attacks enabled")
    end)
    label(player, C.Mid).Text = "What you actually get: FASTER ATTACKS â€” real. Combat is client-authoritative, so your M1 attack speed increases immediately and it stays on through respawns. That's the only gamepass perk a client can grant. Stronger Punches and X2 XP / X2 Kills / X2 Clan XP are calculated on the SERVER from real ownership â€” nothing client-side or in the game's remotes can unlock them, so this does NOT boost your damage or your XP/kill rewards. Not listed = not obtainable."

    section(player, "Protection")
    toggle(player, "Anti-Fling", S.antiFling, function(v) S.antiFling = v end)
    toggle(player, "AC Bypass (hide flag)", S.acBypass, function(v) S.acBypass = v end)
    toggle(player, "Safe Teleport", S.safeTP, function(v) S.safeTP = v end)
    label(player, C.Warn).Text = "The exploit anti-cheat is SERVER-SIDE. AC Bypass strips the '** POTENTIAL CHEATER **' tag from your screen and clears client-read flags, and Safe Teleport glides every script teleport in small steps so the server's position check never sees a jump (that's what got flagged). A ban the SERVER already issued can't be undone from the client â€” the win is never tripping it: keep Safe Teleport on and avoid huge speed/teleport values."
    label(player, C.Mid).Text = "Katana shows on RightTool at hand scale (not the huge template size). Stays applied through fist equip/unequip while Force Style is on. Server equip still runs for unlocked levels."

    ------------------------------------------------------------------ SETTINGS
    local set = makeTab("Settings")
    section(set, "Utility")
    toggle(set, "Anti-AFK", S.antiAFK, function(v) S.antiAFK = v end)
    label(set, C.Mid).Text = "Anti-AFK defeats the 20-minute idle disconnect so you can stay in the server indefinitely."
    section(set, "Configuration")
    button(set, "Save Config", saveConfig)
    button(set, "Load Config", function() loadConfig(); if refreshWhitelist then refreshWhitelist() end end)
    section(set, "Session")
    button(set, "Unload Velorix", function() if genv.__FOAB_SUITE and genv.__FOAB_SUITE.Unload then genv.__FOAB_SUITE.Unload() end end)
    local info = label(set, C.Mid)
    info.Text = ("Toggle UI: RightShift / Insert  â€¢  Place v%d\nVelorix â€” Fight on a Baseplate â€¢ Premium build"):format(game.PlaceVersion)
end

----------------------------------------------------------------------
-- Dragging (top bar & rail)
----------------------------------------------------------------------
do
    local dragging, dragStart, startPos
    local function startDrag(i)
        if (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) and UserInputService:GetFocusedTextBox() == nil then
            dragging = true; dragStart = i.Position; startPos = mainFrame.Position
        end
    end
    Maid:Give(TopBar.InputBegan:Connect(startDrag))
    Maid:Give(Sidebar.InputBegan:Connect(startDrag))
    Maid:Give(UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    Maid:Give(UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
end

----------------------------------------------------------------------
-- UI toggle hotkey
----------------------------------------------------------------------
Maid:Give(UserInputService.InputBegan:Connect(function(i)
    if i.KeyCode == Enum.KeyCode.RightShift or i.KeyCode == Enum.KeyCode.Insert then
        setVisible(not uiVisible)
    end
end))

Tabs["Combat"].select()

----------------------------------------------------------------------
-- Floating launcher orb
----------------------------------------------------------------------
do
    local btnFrame = new("Frame", { Name = "ToggleButton", Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(20, 100), BackgroundColor3 = C.Red, BorderSizePixel = 0, ZIndex = 10 }, ScreenGui)
    Maid:GiveInst(btnFrame)
    corner(btnFrame, 24); gradient(btnFrame, C.RedHi, C.RedLo, 115); stroke(btnFrame, C.RedHi, 1.4, 0.35)
    local scaleObj = new("UIScale", { Scale = 1 }, btnFrame)
    local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 16, 1, 16), BackgroundColor3 = C.Red, BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 9 }, btnFrame)
    corner(glow, 32)
    tw(glow, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.9 }):Play()
    new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "V", TextColor3 = C.Text, Font = Enum.Font.GothamBlack, TextSize = 24, ZIndex = 12 }, btnFrame)
    local dragging, dragMoved, dragStart, startPos = false, false, nil, nil
    Maid:Give(btnFrame.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragMoved = false; dragStart = i.Position; startPos = btnFrame.Position
            tw(scaleObj, SNAP, { Scale = 0.9 }):Play()
        end
    end))
    Maid:Give(btnFrame.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = i.Position - dragStart
            if delta.Magnitude > 5 then dragMoved = true end
            btnFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
    Maid:Give(btnFrame.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
            tw(scaleObj, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
            if not dragMoved then setVisible(not uiVisible) end
            dragging = false
        end
    end))
end

----------------------------------------------------------------------
-- Unload hook
----------------------------------------------------------------------
genv.__FOAB_SUITE = { S = S, E = E }  -- S/E exposed for advanced/scripted control
function genv.__FOAB_SUITE.Unload()
    -- bump session first so Heartbeat/RenderStepped loops exit immediately
    genv.__FOAB_SESSION = (genv.__FOAB_SESSION or 0) + 1
    pcall(function() stopWeaveVisual() end)
    pcall(function() Anim.stopAll() end)
    local c = LP.Character
    pcall(function() StarterPlayerSvc.CharacterWalkSpeed = BASE_WS end)
    local hum0 = c and c:FindFirstChildOfClass("Humanoid")
    if hum0 then pcall(function() hum0.UseJumpPower = false; hum0.JumpHeight = 0 end) end
    S.fly = false; S.noclip = false
    S.touchFling = false; S.walkToNearest = false
    pcall(function() if E.flingStop then E.flingStop() end end)
    local hrp0 = c and c:FindFirstChild("HumanoidRootPart")
    if hrp0 then pcall(function() hrp0.AssemblyAngularVelocity = Vector3.zero end) end
    pcall(function() if E.restoreNoclip then E.restoreNoclip() end end)
    S.freecam = false; pcall(function() if E.setFreecam then E.setFreecam(false) end end)
    pcall(function() Workspace.CurrentCamera.FieldOfView = 70 end)
    -- defer instance teardown so we do not destroy the GUI mid-click handler
    pcall(function() RunService:UnbindFromRenderStep("FOAB_AuraLockYaw") end)
    task.defer(function()
        pcall(function() Maid:Clean() end)
        pcall(destroyFoabGuis)
        genv.__FOAB_SUITE = nil
    end)
end

----------------------------------------------------------------------
-- Cinematic loading screen
----------------------------------------------------------------------
local function runLoadingScreen()
    local LoadingGui = new("ScreenGui", { Name = "FOAB_Loader", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true })
    Maid:GiveInst(LoadingGui)
    local ok = false
    if typeof(gethui) == "function" then ok = pcall(function() LoadingGui.Parent = gethui() end) end
    if not ok then
        local protected = false
        pcall(function()
            local fn = nil
            pcall(function() fn = syn.protect_gui end)
            if typeof(fn) ~= "function" and typeof(protect_gui) == "function" then fn = protect_gui end
            if typeof(fn) ~= "function" and typeof(protectgui) == "function" then fn = protectgui end
            if typeof(fn) == "function" then
                fn(LoadingGui)
                protected = true
            end
        end)
        if protected then ok = pcall(function() LoadingGui.Parent = game:GetService("CoreGui") end) end
    end
    if not ok then ok = pcall(function() LoadingGui.Parent = game:GetService("CoreGui") end) end
    if not LoadingGui.Parent then pcall(function() LoadingGui.Parent = LP:WaitForChild("PlayerGui", 5) end) end

    local loadBg = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 6, 8), BorderSizePixel = 0, ZIndex = 100 }, LoadingGui)
    gradient(loadBg, Color3.fromRGB(12, 10, 12), Color3.fromRGB(4, 4, 5), 135)
    local coreGlow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromOffset(520, 520), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 100 }, loadBg)
    corner(coreGlow, 260)
    tw(coreGlow, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.82, Size = UDim2.fromOffset(560, 560) }):Play()
    for _, band in ipairs({ { UDim2.new(1, 0, 0, 160), UDim2.fromScale(0, 0), 0 }, { UDim2.new(1, 0, 0, 200), UDim2.fromScale(0, 1), 1 } }) do
        local v = new("Frame", { Size = band[1], Position = band[2], AnchorPoint = Vector2.new(0, band[3]), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 101 }, loadBg)
        local vg = new("UIGradient", { Rotation = 90 }, v)
        if band[3] == 0 then vg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
        else vg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) }) end
    end
    task.spawn(function()
        while LoadingGui.Parent do
            pcall(function()
                local size = math.random(2, 5)
                local startX = math.random(0, math.max(1, LoadingGui.AbsoluteSize.X))
                local startY = (LoadingGui.AbsoluteSize.Y or 800) + 10
                local p = new("Frame", { Position = UDim2.fromOffset(startX, startY), Size = UDim2.fromOffset(size, size), BackgroundColor3 = (math.random() < 0.5) and Theme.Accent or Theme.AccentGlow, BackgroundTransparency = math.random(30, 70) / 100, BorderSizePixel = 0, ZIndex = 102 }, loadBg)
                corner(p, size / 2)
                local dur = math.random(20, 38) / 10
                tw(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(startX + math.random(-70, 70), startY - math.random(220, 460)), BackgroundTransparency = 1 }):Play()
                task.delay(dur, function() p:Destroy() end)
            end)
            task.wait(0.09)
        end
    end)

    local container = new("Frame", { Size = UDim2.fromOffset(320, 320), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 103 }, loadBg)
    local logoGlow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.fromOffset(122, 122), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.82, BorderSizePixel = 0, ZIndex = 103 }, container)
    corner(logoGlow, 61)
    tw(logoGlow, TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.62, Size = UDim2.fromOffset(138, 138) }):Play()
    local logo = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(96, 96), BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 104 }, container)
    corner(logo, 26)
    -- Two bars form a "V" (open at top, tip at bottom). Prior rotations were flipped (^).
    local leftBar = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(14, 0),
        Position = UDim2.new(0.34, 0, 0.12, 0), BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0, Rotation = -28, ZIndex = 105,
    }, logo)
    corner(leftBar, 7); gradient(leftBar, Theme.AccentGlow, Theme.Accent2, 90)
    local rightBar = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(14, 0),
        Position = UDim2.new(0.66, 0, 0.12, 0), BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0, Rotation = 28, ZIndex = 105,
    }, logo)
    corner(rightBar, 7); gradient(rightBar, Theme.AccentGlow, Theme.Accent2, 90)
    local logoImg
    if LOGO_ASSET then
        leftBar.Visible = false; rightBar.Visible = false
        logo.BackgroundTransparency = 0
        logoImg = new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = LOGO_ASSET, ScaleType = Enum.ScaleType.Crop, ZIndex = 105 }, logo)
        corner(logoImg, 26)
    end

    local title = new("TextLabel", { Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 124), BackgroundTransparency = 1, Text = "VELORIX", TextColor3 = Color3.fromRGB(240, 240, 244), Font = Enum.Font.GothamBlack, TextSize = 30, TextTransparency = 1, ZIndex = 104 }, container)
    local subtitle = new("TextLabel", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 158), BackgroundTransparency = 1, Text = "FIGHT ON A BASEPLATE   Â·   PREMIUM", TextColor3 = Theme.AccentGlow, Font = Enum.Font.GothamBold, TextSize = 10, TextTransparency = 1, ZIndex = 104 }, container)
    local pctLabel = new("TextLabel", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 188), BackgroundTransparency = 1, Text = "0%", TextColor3 = Color3.fromRGB(240, 240, 244), Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 104 }, container)
    local barBg = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 214), Size = UDim2.fromOffset(240, 4), BackgroundColor3 = Color3.fromRGB(30, 30, 34), BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 104 }, container)
    corner(barBg, 2); stroke(barBg, Color3.fromRGB(255, 255, 255), 1, 0.9)
    local barFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 105 }, barBg)
    corner(barFill, 2); gradient(barFill, Theme.AccentGlow, Theme.Accent, 0)
    local barFlare = new("Frame", { Size = UDim2.fromScale(0.25, 1), Position = UDim2.fromScale(-0.25, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 106 }, barFill)
    task.spawn(function()
        while LoadingGui.Parent do
            barFlare.Position = UDim2.fromScale(-0.25, 0)
            local t = tw(barFlare, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(1.05, 0) })
            t:Play(); t.Completed:Wait(); task.wait(0.25)
        end
    end)
    local loadStatus = new("TextLabel", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 228), BackgroundTransparency = 1, Text = "Initializing...", TextColor3 = Color3.fromRGB(150, 150, 160), Font = Enum.Font.GothamMedium, TextSize = 10, ZIndex = 104 }, container)
    local tips = {
        "Tip: Press RightShift to hide or show the menu.",
        "Tip: Lower Aura Range to look more legit.",
        "Tip: Auto Weave dodges the instant enemies swing.",
        "Tip: Whitelist friends so Aura never hits them.",
        "Tip: Enable Wall Check to skip targets behind cover.",
    }
    local tipLabel = new("TextLabel", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 254), BackgroundTransparency = 1, Text = tips[1], TextColor3 = Color3.fromRGB(120, 120, 130), Font = Enum.Font.Gotham, TextSize = 10, TextTransparency = 0.25, ZIndex = 104 }, container)
    task.spawn(function()
        local i = 1
        while LoadingGui.Parent do
            task.wait(1.6); if not LoadingGui.Parent then break end
            i = i % #tips + 1
            tw(tipLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 1 }):Play()
            task.wait(0.25); if not LoadingGui.Parent then break end
            tipLabel.Text = tips[i]
            tw(tipLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 0.25 }):Play()
        end
    end)

    task.spawn(function()
        tw(leftBar, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(14, 72) }):Play()
        tw(rightBar, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(14, 72) }):Play()
        title.Position = UDim2.fromOffset(0, 132)
        tw(title, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { TextTransparency = 0, Position = UDim2.fromOffset(0, 124) }):Play()
        task.wait(0.12)
        tw(subtitle, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { TextTransparency = 0.1 }):Play()
        local steps = {
            { 0.12, "Initializing..." }, { 0.30, "Hooking Combat Remote..." }, { 0.48, "Verifying Signature..." },
            { 0.66, "Preparing Interface..." }, { 0.84, "Loading Configuration..." }, { 0.94, "Finalizing..." }, { 1.00, "Launching Velorix..." },
        }
        local currentPct = 0
        for _, step in ipairs(steps) do
            loadStatus.Text = step[2]
            tw(barFill, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.fromScale(step[1], 1) }):Play()
            local targetPct = math.floor(step[1] * 100)
            task.spawn(function() while currentPct < targetPct do currentPct = currentPct + 1; pctLabel.Text = tostring(currentPct) .. "%"; task.wait(0.01) end end)
            task.wait(0.55)
        end
        task.wait(0.35)
        local info = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        for _, o in ipairs({ loadBg, coreGlow, logo, logoGlow, leftBar, rightBar }) do tw(o, info, { BackgroundTransparency = 1 }):Play() end
        if logoImg then tw(logoImg, info, { ImageTransparency = 1 }):Play() end
        for _, o in ipairs({ title, subtitle, pctLabel, loadStatus, tipLabel }) do tw(o, info, { TextTransparency = 1 }):Play() end
        tw(barBg, info, { BackgroundTransparency = 1 }):Play(); tw(barFill, info, { BackgroundTransparency = 1 }):Play()
        task.wait(0.6)
        LoadingGui:Destroy()
        setVisible(true)
    end)
end

runLoadingScreen()

-- Auto-load saved config if present
if hasFS and isfile(CFG_FILE) then
    task.defer(function()
        if isCurrent() then loadConfig(); if refreshWhitelist then refreshWhitelist() end end
    end)
end

print("[Velorix â€¢ Fight on a Baseplate] loaded â€” RightShift to toggle.")
