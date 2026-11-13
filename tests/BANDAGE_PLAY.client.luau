-- Install separately through Studio in PlayerScripts after the server fixture.

local RS=game:GetService("ReplicatedStorage")
local p=game.Players.LocalPlayer
local api=RS:WaitForChild("BandageIntegrationTest")
local r=RS.Shared.Remotes
local report={}
local function call(cmd,v) return api:InvokeServer(cmd,v) end
local function check(name,pass,observed)
 table.insert(report,{name=name,passed=pass,observed=observed})
 assert(pass,name)
end
local function equip(id) r.EquipItem:FireServer(id);task.wait(.35) end
local function use() r.UseBandage:FireServer() end
local ok,err=xpcall(function()
 local deadline=os.clock()+30
 while call("state").state~="ROUND" and os.clock()<deadline do call("skip");task.wait(1) end
 check("active round",call("state").state=="ROUND")
 call("safe");call("hp",40);equip("bandage")
 check("equipped from loadout",call("state").tool)
 check("model icon in hotbar",p.PlayerGui.HUD.Hotbar:FindFirstChild("ModelIcon",true)~=nil)
 use();task.wait(.8)
 local v=call("state")
 check("no early heal or consume",v.hp==40 and v.count==8 and v.started~=nil,v)
 check("progress displayed",p.PlayerGui.HUD.CooldownBars:FindFirstChild("BandageProgress")~=nil)
 for i=1,10 do use() end
 task.wait(2.5);v=call("state")
 check("spam gives one heal and one consume",v.hp==75 and v.count==7,v)
 call("hp",85);use();task.wait(3.3);v=call("state")
 check("heal capped at max",v.hp==100 and v.count==6,v)
 use();task.wait(.4);v=call("state")
 check("full health does not consume",v.hp==100 and v.count==6 and v.started==nil,v)
 call("hp",40);use();task.wait(.5);equip("grapple");task.wait(3.1);v=call("state")
 check("switch cancels without consume",v.hp==40 and v.count==6 and v.started==nil,v)
 check("cancel removes progress",p.PlayerGui.HUD.CooldownBars:FindFirstChild("BandageProgress")==nil)
 equip("bandage");use();task.wait(.5);call("ragdoll",true);task.wait(.2);call("ragdoll",false)
 task.wait(3.1);v=call("state")
 check("ragdoll cancels without consume",v.hp==40 and v.count==6 and v.started==nil,v)
 call("safe")
 r.UseBandage:FireServer(999);task.wait(.4);v=call("state")
 check("invalid payload rejected",v.started==nil and v.count==6,v)
 call("count",0);use();task.wait(.4);v=call("state")
 check("zero inventory rejected",v.started==nil and v.count==0 and v.hp==40,v)
 call("count",1);use();task.wait(3.3);v=call("state")
 check("last item consumed and tool removed",v.count==0 and not v.tool and v.hp==75,v)
 call("count",1);equip("bandage");use();task.wait(.4);call("end");task.wait(3.5);v=call("state")
 check("round end cancels without consume",v.count==1 and v.started==nil and not v.tool,v)
end,debug.traceback)
call("finish",{ok=ok,report=game:GetService("HttpService"):JSONEncode(report),error=ok and "" or tostring(err)})
print("[BandageTest] "..(ok and "PASSED" or "FAILED").." "..game:GetService("HttpService"):JSONEncode(report))
script:Destroy()
