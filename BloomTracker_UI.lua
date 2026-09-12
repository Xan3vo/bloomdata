-- Bloom Tracker with Live UI
-- Client-side script with GUI dashboard
-- Place in StarterPlayer > StarterCharacterScripts or StarterPlayer > StarterPlayerScripts

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local POPPABLE_FOLDER_NAME = "PoppablePlants"
local FIELDS_FOLDER_NAME = "Fields"
local POSITION_CHECK_THRESHOLD = 2
local CHECK_INTERVAL = 0.5

-- Get player and create UI
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activeBlooms = {}
local fieldCache = {}
local lastCheckTime = 0
local bloomStats = {
    total_spawned = 0,
    total_destroyed = 0,
    field_assignments = 0,
    no_field_assigned = 0
}

-- ========== UI SETUP ==========
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BloomTrackerGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndex = 100
screenGui.Parent = playerGui

-- Main frame
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 400, 0, 600)
mainFrame.Position = UDim2.new(0, 20, 0, 20)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
mainFrame.BorderColor3 = Color3.fromRGB(100, 200, 100)
mainFrame.BorderSizePixel = 2
mainFrame.Parent = screenGui

-- Title
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0, 40)
titleLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
titleLabel.BorderSizePixel = 0
titleLabel.Text = "🌸 Bloom Tracker"
titleLabel.TextSize = 18
titleLabel.TextColor3 = Color3.fromRGB(100, 200, 100)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Parent = mainFrame

-- Stats frame
local statsFrame = Instance.new("Frame")
statsFrame.Name = "StatsFrame"
statsFrame.Size = UDim2.new(1, -10, 0, 80)
statsFrame.Position = UDim2.new(0, 5, 0, 45)
statsFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
statsFrame.BorderSizePixel = 0
statsFrame.Parent = mainFrame

local function createStatLabel(name, yOffset)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Size = UDim2.new(0.5, -5, 0, 18)
    label.Position = UDim2.new((name == "Spawned" or name == "Active") and 0 or 0.5, 2, 0, yOffset)
    label.BackgroundTransparency = 1
    label.Text = name .. ": 0"
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = statsFrame
    return label
end

local spawnedLabel = createStatLabel("Spawned", 0)
local activeLabel = createStatLabel("Active", 0)
local destroyedLabel = createStatLabel("Destroyed", 20)
local assignedLabel = createStatLabel("Assigned", 20)

-- Bloom list frame
local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "BloomListFrame"
listFrame.Size = UDim2.new(1, -10, 1, -140)
listFrame.Position = UDim2.new(0, 5, 0, 130)
listFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 8
listFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 200, 100)
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 2)
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

-- ========== FIELD DETECTION ==========
local function getFieldsFolder()
    local f = Workspace:FindFirstChild(FIELDS_FOLDER_NAME)
    if f then return f end
    local alt = Workspace:FindFirstChild("FlowerZones")
    if alt then return alt end
    for _, v in ipairs(Workspace:GetDescendants()) do
        if v.Name == FIELDS_FOLDER_NAME or v.Name == "FlowerZones" then
            if v:IsA("Folder") or v:IsA("Model") then return v end
        end
    end
    return nil
end

local function getPoppableFolder()
    local p = Workspace:FindFirstChild(POPPABLE_FOLDER_NAME)
    if p then return p end
    local h = Workspace:FindFirstChild("Happenings")
    if h and h:FindFirstChild(POPPABLE_FOLDER_NAME) then return h:FindFirstChild(POPPABLE_FOLDER_NAME) end
    for _, v in ipairs(Workspace:GetDescendants()) do
        if v.Name == POPPABLE_FOLDER_NAME and (v:IsA("Folder") or v:IsA("Model")) then return v end
    end
    return nil
end

local function getInstancePosition(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then
        local ok, pivot = pcall(function() return inst:GetPivot() end)
        if ok and pivot then return pivot.Position end
    end
    local part = inst:FindFirstChildWhichIsA("BasePart")
    if part then return part.Position end
    return nil
end

local function cacheFieldData()
    fieldCache = {}
    local fieldsFolder = getFieldsFolder()
    if not fieldsFolder then return end

    for _, field in ipairs(fieldsFolder:GetChildren()) do
        if field:IsA("Model") then
            local ok, boxCFrame, size = pcall(function() return field:GetBoundingBox() end)
            if ok and boxCFrame and size then
                fieldCache[field.Name] = {
                    field = field,
                    boxCFrame = boxCFrame,
                    size = size,
                    useBoundingBox = true
                }
            else
                local pivotPos
                if field.PrimaryPart then
                    pivotPos = field.PrimaryPart.Position
                else
                    local succ, pf = pcall(function() return field:GetPivot() end)
                    if succ and pf then pivotPos = pf.Position end
                end
                if pivotPos then
                    fieldCache[field.Name] = {
                        field = field,
                        position = pivotPos,
                        radius = 50,
                        useBoundingBox = false
                    }
                end
            end
        end
    end
end

local function getFieldForPosition(pos)
    if not pos then return nil end

    for fieldName, data in pairs(fieldCache) do
        if data.useBoundingBox and data.boxCFrame and data.size then
            local inv = data.boxCFrame:Inverse()
            local relCFrame = inv * CFrame.new(pos)
            local rel = relCFrame.Position
            if math.abs(rel.X) <= data.size.X/2 and math.abs(rel.Y) <= data.size.Y/2 and math.abs(rel.Z) <= data.size.Z/2 then
                return data.field
            end
        end
    end

    for fieldName, data in pairs(fieldCache) do
        if not data.useBoundingBox and data.position then
            local distance = (pos - data.position).Magnitude
            if distance < (data.radius or 50) then
                return data.field
            end
        end
    end

    return nil
end

-- ========== BLOOM TRACKING ==========
local function createBloomLabel(bloom, field)
    local bloomLabel = Instance.new("TextLabel")
    bloomLabel.Name = bloom.Name
    bloomLabel.Size = UDim2.new(1, 0, 0, 30)
    bloomLabel.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
    bloomLabel.BorderColor3 = field and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(255, 200, 100)
    bloomLabel.BorderSizePixel = 1
    bloomLabel.Text = ("  %s → %s"):format(bloom.Name, field and field.Name or "NO FIELD")
    bloomLabel.TextSize = 11
    bloomLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
    bloomLabel.Font = Enum.Font.Gotham
    bloomLabel.TextXAlignment = Enum.TextXAlignment.Left
    bloomLabel.Parent = listFrame
    return bloomLabel
end

local function updateUIStats()
    spawnedLabel.Text = ("Spawned: %d"):format(bloomStats.total_spawned)
    activeLabel.Text = ("Active: %d"):format(#activeBlooms)
    destroyedLabel.Text = ("Destroyed: %d"):format(bloomStats.total_destroyed)
    assignedLabel.Text = ("Assigned: %d"):format(bloomStats.field_assignments)

    -- Update list size
    listFrame.CanvasSize = UDim2.new(0, 0, 0, #listFrame:GetChildren() * 32)
end

local function trackBloom(bloom)
    if activeBlooms[bloom] then return end

    local pos = getInstancePosition(bloom)
    if not pos then return end

    bloomStats.total_spawned = bloomStats.total_spawned + 1
    local field = getFieldForPosition(pos)

    if field then
        bloomStats.field_assignments = bloomStats.field_assignments + 1
    else
        bloomStats.no_field_assigned = bloomStats.no_field_assigned + 1
    end

    local uiLabel = createBloomLabel(bloom, field)
    activeBlooms[bloom] = {
        lastPos = pos,
        lastFieldName = field and field.Name or nil,
        uiLabel = uiLabel
    }

    updateUIStats()
end

local function isBloomCandidate(obj)
    if not obj then return false end
    if obj.GetAttribute then
        local ok, val = pcall(function() return obj:GetAttribute("IsBloom") end)
        if ok and val == true then return true end
    end
    if obj.Name and obj.Name:lower():find("bloom") then return true end
    return false
end

local function onDescendantAdded(desc)
    if isBloomCandidate(desc) then trackBloom(desc); return end
    if desc:IsA("Model") or desc:IsA("Folder") then
        for _, d in ipairs(desc:GetDescendants()) do
            if isBloomCandidate(d) then trackBloom(d) end
        end
    end
end

local function updateBloomPositions()
    local currentTime = tick()
    if currentTime - lastCheckTime < CHECK_INTERVAL then return end
    lastCheckTime = currentTime

    for bloom, data in pairs(activeBlooms) do
        if not bloom.Parent then
            bloomStats.total_destroyed = bloomStats.total_destroyed + 1
            data.uiLabel:Destroy()
            activeBlooms[bloom] = nil
        else
            local newPos = getInstancePosition(bloom)
            if newPos and (newPos - data.lastPos).Magnitude > POSITION_CHECK_THRESHOLD then
                local newField = getFieldForPosition(newPos)
                local newFieldName = newField and newField.Name or nil
                if data.lastFieldName ~= newFieldName then
                    data.lastFieldName = newFieldName
                    -- Update UI label color
                    data.uiLabel.BorderColor3 = newField and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(255, 200, 100)
                    data.uiLabel.Text = ("  %s → %s"):format(bloom.Name, newField and newField.Name or "NO FIELD")
                end
                data.lastPos = newPos
            end
        end
    end

    updateUIStats()
end

-- ========== INITIALIZATION ==========
local function init()
    local poppable = getPoppableFolder()
    if not poppable then
        Workspace.ChildAdded:Connect(function(child)
            if child.Name == POPPABLE_FOLDER_NAME then
                init()
            end
        end)
        return
    end

    cacheFieldData()
    for _, desc in ipairs(poppable:GetDescendants()) do
        if isBloomCandidate(desc) then trackBloom(desc) end
    end

    poppable.DescendantAdded:Connect(onDescendantAdded)
    RunService.Heartbeat:Connect(updateBloomPositions)
    updateUIStats()
end

init()
