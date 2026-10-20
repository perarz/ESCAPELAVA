--!strict
-- Cosmetic continuous surface. Never parent under Lava: its parts drive damage.
local AssetService = game:GetService("AssetService")
local Workspace = game:GetService("Workspace")
local Wave = {}
Wave.__index = Wave

function Wave.new(source: BasePart, cfg: any, originals: {BasePart}?)
	local modifiers = {}
	for _, p in ipairs(originals or {source}) do modifiers[p] = p.LocalTransparencyModifier end
	return setmetatable({source=source, cfg=cfg, mesh=nil, part=nil, points={},
		dead=false, building=false, failed=false, elapsed=0, hidden=false,
		modifiers=modifiers, size=source.Size}, Wave)
end

function Wave:_restore()
	if self.hidden then
		for p, modifier in pairs(self.modifiers) do
			if p.Parent then p.LocalTransparencyModifier = modifier end
		end
		self.hidden = false
	end
	if self.part then self.part.Transparency = 1 end
end

function Wave:Destroy()
	self.dead = true
	self:_restore()
	if self.part then self.part:Destroy(); self.part = nil end
	if self.mesh then self.mesh:Destroy(); self.mesh = nil end
end

function Wave:_build()
	self.building = true
	local mesh: EditableMesh? = nil
	local part: MeshPart? = nil
	local ok, err = pcall(function()
		mesh = AssetService:CreateEditableMesh()
		assert(mesh, "EditableMesh budget unavailable")
		local m = mesh :: EditableMesh
		local cfg = self.cfg
		local cells = cfg.Cells
		local width, depth = self.size.X, self.size.Z
		local points = {}
		for z = 0, cells do
			for x = 0, cells do
				local px, pz = (x/cells-0.5)*width, (z/cells-0.5)*depth
				local phase1 = (px + pz*cfg.DirectionZ) * math.pi*2/cfg.Wavelength
				local phase2 = (pz - px*cfg.CrossDirectionX) * math.pi*2/cfg.CrossWavelength
				-- Initial envelope gives the mesh nonzero vertical bounds.
				local py = cfg.Amplitude * (if (x+z)%2 == 0 then 1 else -1)
				table.insert(points, {id=m:AddVertex(Vector3.new(px,py,pz)),
					normal=m:AddNormal(Vector3.yAxis), uv=m:AddUV(Vector2.new(px/cfg.TileSize,pz/cfg.TileSize)),
					x=px,z=pz,s1=math.sin(phase1),c1=math.cos(phase1),s2=math.sin(phase2),c2=math.cos(phase2)})
			end
			if z % 4 == 0 then task.wait(); assert(not self.dead, "cancelled") end
		end
		local function triangle(a, b, c)
			local face = m:AddTriangle(a.id,b.id,c.id)
			m:SetFaceNormals(face,{a.normal,b.normal,c.normal})
			m:SetFaceUVs(face,{a.uv,b.uv,c.uv})
		end
		for z = 0, cells-1 do
			for x = 0, cells-1 do
				local i = z*(cells+1)+x+1
				local a,b,c,d = points[i],points[i+1],points[i+cells+1],points[i+cells+2]
				triangle(a,c,b); triangle(b,c,d)
			end
			if z % 4 == 0 then task.wait(); assert(not self.dead, "cancelled") end
		end
		part = AssetService:CreateMeshPartAsync(Content.fromObject(m), {CollisionFidelity=Enum.CollisionFidelity.Box})
		assert(not self.dead and self.source.Parent and self.source.Size == self.size, "cancelled")
		local p = part :: MeshPart
		p.Name = "LavaWaveSurface"
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Locked = true
		p.DoubleSided = false
		p.Transparency = 1
		self.mesh, self.part, self.points = m,p,points
		self:_deform(os.clock())
		p:SetAttribute("WaveVertexCount", #points)
		p:SetAttribute("WaveAmplitude", cfg.Amplitude)
		p.Parent = Workspace
		print("[LavaWaves] Connected mesh ready: "..#points.." vertices")
	end)
	self.building = false
	if not ok then
		if part then part:Destroy() end
		if mesh then mesh:Destroy() end
		self.part, self.mesh = nil,nil
		self.failed = true
		if not self.dead then warn("[LavaWaves] Flat surface retained: "..tostring(err)) end
	end
end

function Wave:_deform(now: number)
	local cfg = self.cfg
	local t1,t2 = now*math.pi*2/cfg.Period, -now*math.pi*2/cfg.CrossPeriod
	local s1,c1,s2,c2 = math.sin(t1),math.cos(t1),math.sin(t2),math.cos(t2)
	local a1,a2 = cfg.Amplitude*(1-cfg.CrossWeight),cfg.Amplitude*cfg.CrossWeight
	local k1,k2 = math.pi*2/cfg.Wavelength,math.pi*2/cfg.CrossWavelength
	for _, v in ipairs(self.points) do
		local y = a1*(v.s1*c1+v.c1*s1) + a2*(v.s2*c2+v.c2*s2)
		v.y = y
		local slope1,slope2 = a1*k1*(v.c1*c1-v.s1*s1),a2*k2*(v.c2*c2-v.s2*s2)
		self.mesh:SetPosition(v.id,Vector3.new(v.x,y,v.z))
		self.mesh:SetNormal(v.normal,Vector3.new(-slope1+slope2*cfg.CrossDirectionX,1,-slope1*cfg.DirectionZ-slope2).Unit)
	end
end

-- Sample the actual rendered triangles, not a second independently timed wave.
-- Cosmetic consumers only: damage continues to use the server surface.
function Wave:surfaceY(x: number, z: number): number?
	local part = self.part
	if not part or not self.hidden then return nil end
	local localPoint = part.CFrame:PointToObjectSpace(Vector3.new(x, part.Position.Y, z))
	local cells = self.cfg.Cells
	local gx = math.clamp((localPoint.X / self.size.X + 0.5) * cells, 0, cells)
	local gz = math.clamp((localPoint.Z / self.size.Z + 0.5) * cells, 0, cells)
	local ix, iz = math.min(math.floor(gx), cells-1), math.min(math.floor(gz), cells-1)
	local u, v = gx-ix, gz-iz
	local i = iz*(cells+1)+ix+1
	local a,b,c,d = self.points[i],self.points[i+1],self.points[i+cells+1],self.points[i+cells+2]
	local y = if u+v <= 1 then a.y*(1-u-v)+b.y*u+c.y*v
		else b.y*(1-v)+c.y*(1-u)+d.y*(u+v-1)
	return part.CFrame:PointToWorldSpace(Vector3.new(localPoint.X,y,localPoint.Z)).Y
end

function Wave:update(dt: number, allowed: boolean)
	if self.dead then return end
	if not self.source.Parent or self.source.Size ~= self.size then self:Destroy(); return end
	if not allowed or not self.cfg.Enabled or Workspace:GetAttribute("LavaWavesDisabled") == true then
		self:_restore(); return
	end
	if self.failed then return end
	if not self.part then
		if not self.building then task.spawn(function() self:_build() end) end
		return
	end
	local p,source = self.part,self.source
	local baseY = source:GetAttribute("LavaVisualBaseY")
	if typeof(baseY) ~= "number" then baseY = source.Position.Y + source.Size.Y/2 end
	p.CFrame = source.CFrame.Rotation + Vector3.new(source.Position.X,baseY,source.Position.Z)
	p.Material = source.Material
	p.MaterialVariant = source.MaterialVariant
	p.Color = source.Color
	p.Reflectance = source.Reflectance
	self.elapsed += dt
	if self.elapsed >= 1/self.cfg.UpdateHz or not self.hidden then
		self.elapsed %= 1/self.cfg.UpdateHz
		self:_deform(os.clock())
	end
	p.Transparency = 0
	if not self.hidden then
		-- Hide the lower plates too: their old bob would intersect wave troughs.
		for original in pairs(self.modifiers) do
			self.modifiers[original] = original.LocalTransparencyModifier
			original.LocalTransparencyModifier = 1
		end
		self.hidden = true
	end
end

return Wave
