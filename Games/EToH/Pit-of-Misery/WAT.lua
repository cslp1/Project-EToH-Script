return function()
    local route = {}
    local function makeWaypoint(x, y, z)
        local part = Instance.new("Part")
        part.Anchored, part.CanCollide, part.Transparency = true, false, 1
        part.Size = Vector3.new(1, 1, 1)
        part.Position = Vector3.new(x, y, z)
        part.Parent = workspace
        return part
    end

    route[#route + 1] = workspace.Towers["WAT"]:GetChildren()[2]
    route[#route + 1] = workspace.Parts:GetChildren()[27]
    route[#route + 1] = workspace.Parts:GetChildren()[54]
    route[#route + 1] = workspace.Parts:GetChildren()[135]
    route[#route + 1] = workspace.Parts:GetChildren()[242]
    route[#route + 1] = workspace.Parts:GetChildren()[152]
    route[#route + 1] = workspace.Parts:GetChildren()[134]
    route[#route + 1] = workspace.Parts:GetChildren()[263]
    route[#route + 1] = workspace.Parts:GetChildren()[51]
    route[#route + 1] = workspace.Parts:GetChildren()[169]
    route[#route + 1] = workspace.Parts:GetChildren()[84]
    route[#route + 1] = workspace.Parts:GetChildren()[47]
    route[#route + 1] = workspace.Parts:GetChildren()[110]
    route[#route + 1] = workspace.Parts:GetChildren()[26]
    route[#route + 1] = workspace.Parts:GetChildren()[10]
    route[#route + 1] = workspace.Parts:GetChildren()[122]
    route[#route + 1] = workspace.Parts:GetChildren()[22]
    route[#route + 1] = workspace.Parts:GetChildren()[123]
    route[#route + 1] = workspace.Parts:GetChildren()[53]
    route[#route + 1] = workspace.Towers["WAT"].Obby:GetChildren()[11]
    route[#route + 1] = workspace.Parts:GetChildren()[88]
    route[#route + 1] = workspace.Parts:GetChildren()[55]
    route[#route + 1] = workspace.Parts:GetChildren()[91]
    route[#route + 1] = workspace.Parts:GetChildren()[101]
    route[#route + 1] = workspace.Parts:GetChildren()[124]
    route[#route + 1] = workspace.Parts:GetChildren()[111]
    route[#route + 1] = workspace.Parts:GetChildren()[118]
    route[#route + 1] = workspace.Towers["WAT"]:GetChildren()[3]:GetChildren()[44]
    route[#route + 1] = workspace.Parts:GetChildren()[163]
    route[#route + 1] = workspace.Parts:GetChildren()[159]
    route[#route + 1] = workspace.Parts:GetChildren()[82]
    route[#route + 1] = workspace.Parts:GetChildren()[178]
    route[#route + 1] = workspace.Parts:GetChildren()[74]
    route[#route + 1] = workspace.Parts:GetChildren()[15]
    route[#route + 1] = workspace.Parts:GetChildren()[112]
    route[#route + 1] = workspace.Towers["WAT"].Obby:GetChildren()[18]
    route[#route + 1] = workspace.Parts:GetChildren()[107]
    route[#route + 1] = workspace.Parts:GetChildren()[58]
    route[#route + 1] = workspace.Parts:GetChildren()[24]
    route[#route + 1] = workspace.Parts:GetChildren()[175]
    route[#route + 1] = workspace.Parts:GetChildren()[56]
    route[#route + 1] = workspace.Towers["WAT"].Obby:GetChildren()[23]
    route[#route + 1] = workspace.Parts:GetChildren()[48]
    route[#route + 1] = workspace.Parts:GetChildren()[120]
    route[#route + 1] = workspace.Parts:GetChildren()[125]
    route[#route + 1] = workspace.Parts:GetChildren()[79]
    route[#route + 1] = workspace.Parts:GetChildren()[73]
    route[#route + 1] = workspace.Parts:GetChildren()[137]
    route[#route + 1] = workspace.Parts:GetChildren()[188]
    route[#route + 1] = workspace.Parts:GetChildren()[21]
    route[#route + 1] = workspace.Parts:GetChildren()[126]
    route[#route + 1] = workspace.Parts:GetChildren()[93]
    route[#route + 1] = workspace.Towers["WAT"].Obby:GetChildren()[26]
    route[#route + 1] = workspace.Parts:GetChildren()[36]
    route[#route + 1] = workspace.Towers["WAT"]:GetChildren()[1]

    return route
end
