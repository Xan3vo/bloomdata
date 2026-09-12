-- Bloom Tracker UI - Loadstring Ready
-- Execute with: loadstring(game:HttpGet("https://raw.githubusercontent.com/Xan3vo/bloomdata/main/main.lua"))()

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Discord Webhook Configuration
local DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1548446623300849736/pyVshktLNmolGJt5eR1MyyqwUunDGcvRM5G53CNOJKLqo9_a7Wl7KbnQ4-aXSX8sm_Sf"
local DISCORD_ENABLED = true
local DISCORD_REPORT_INTERVAL = 60 -- Report every 60 seconds

local POPPABLE_FOLDER_NAME = "PoppablePlants"
local FIELDS_FOLDER_NAME = "Fields"
local POSITION_CHECK_THRESHOLD = 2
local CHECK_INTERVAL = 0.5

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activeBlooms = {}
local fieldCache = {}
local lastCheckTime = 0
local bloomStats = {total_spawned = 0, total_destroyed = 0, field_assignments = 0, no_field_assigned = 0}

-- ========== UI ==========
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BloomTrackerGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 400, 0, 600)
mainFrame.Position = UDim2.new(0, 20, 0, 20)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
mainFrame.BorderColor3 = Color3.fromRGB(100, 200, 100)
mainFrame.BorderSizePixel = 2
mainFrame.Parent = screenGui

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

-- ========== DISCORD ==========
local lastDiscordReport = 0

local function sendDiscordReport()
    if not DISCORD_ENABLED or not DISCORD_WEBHOOK_URL then return end

    local currentTime = tick()
    if currentTime - lastDiscordReport < DISCORD_REPORT_INTERVAL then return end
    lastDiscordReport = currentTime

    local activeCount = 0
    for _ in pairs(activeBlooms) do activeCount = activeCount + 1 end

    local embed = {
        title = "🌸 Bloom Tracker Report",
        description = "1-Minute Statistics Update",
        fields = {
            {name = "Total Spawned", value = tostring(bloomStats.total_spawned), inline = true},
            {name = "Currently Active", value = tostring(activeCount), inline = true},
            {name = "Total Destroyed", value = tostring(bloomStats.total_destroyed), inline = true},
            {name = "Assigned to Field", value = tostring(bloomStats.field_assignments), inline = true},
            {name = "No Field Found", value = tostring(bloomStats.no_field_assigned), inline = true},
            {name = "Timestamp", value = os.date("%Y-%m-%d %H:%M:%S"), inline = false}
        },
        color = 3447003
    }

    local payload = {
        embeds = {embed},
        username = "🌸 Bloom Tracker"
    }

    local success, err = pcall(function()
        HttpService:PostAsync(DISCORD_WEBHOOK_URL, HttpService:JSONEncode(payload), Enum.HttpContentType.ApplicationJson)
    end)

    if success then
        print("[BloomTracker] ✓ Discord report sent")
    else
        print("[BloomTracker] ✗ Discord error: " .. tostring(err))
    end
end

-- ========== FUNCTIONS ==========
local function getFieldsFolder()
    local f = Workspace:FindFirstChild(FIELDS_FOLDER_NAME) or Workspace:FindFirstChild("FlowerZones")
    if f then
        print("[BloomTracker] Found Fields folder: " .. f:GetFullName())
        return f
    end
    for _, v in ipairs(Workspace:GetDescendants()) do
        if (v.Name == FIELDS_FOLDER_NAME or v.Name == "FlowerZones") and (v:IsA("Folder") or v:IsA("Model")) then
            print("[BloomTracker] Found Fields at: " .. v:GetFullName())
            return v
        end
    end
    print("[BloomTracker] ERROR: Fields folder not found!")
    print("[BloomTracker] Workspace contents:")
    for _, child in ipairs(Workspace:GetChildren()) do
        print("[BloomTracker]   - " .. child.Name .. " (" .. child.ClassName .. ")")
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
    return part and part.Position or nil
end

local function cacheFieldData()
    fieldCache = {}
    local fieldsFolder = getFieldsFolder()
    if not fieldsFolder then return end

    print("[BloomTracker] Caching fields...")
    for _, field in ipairs(fieldsFolder:GetChildren()) do
        -- Handle Model objects
        if field:IsA("Model") then
            local ok, boxCFrame, size = pcall(function() return field:GetBoundingBox() end)
            if ok and boxCFrame and size then
                fieldCache[field.Name] = {field = field, boxCFrame = boxCFrame, size = size, useBoundingBox = true}
                print("[BloomTracker] ✓ Cached field '" .. field.Name .. "' (bounding box)")
            else
                local pivotPos = field.PrimaryPart and field.PrimaryPart.Position or (pcall(function() return field:GetPivot() end) and field:GetPivot().Position or nil)
                if pivotPos then
                    fieldCache[field.Name] = {field = field, position = pivotPos, radius = 50, useBoundingBox = false}
                    print("[BloomTracker] ✓ Cached field '" .. field.Name .. "' at " .. tostring(pivotPos))
                end
            end
        -- Handle Part objects (fields as parts)
        elseif field:IsA("BasePart") then
            local fieldCFrame = field.CFrame
            local fieldSize = field.Size
            fieldCache[field.Name] = {field = field, boxCFrame = fieldCFrame, size = fieldSize, useBoundingBox = true}
            print("[BloomTracker] ✓ Cached field '" .. field.Name .. "' (Part) at " .. tostring(fieldCFrame.Position))
        end
    end
    print("[BloomTracker] Total fields cached: " .. tostring(#fieldCache))
end

local function getFieldForPosition(pos)
    if not pos then return nil end

    for _, data in pairs(fieldCache) do
        if data.useBoundingBox and data.boxCFrame and data.size then
            local rel = (data.boxCFrame:Inverse() * CFrame.new(pos)).Position
            if math.abs(rel.X) <= data.size.X/2 and math.abs(rel.Y) <= data.size.Y/2 and math.abs(rel.Z) <= data.size.Z/2 then
                return data.field
            end
        end
    end

    for _, data in pairs(fieldCache) do
        if not data.useBoundingBox and data.position then
            if (pos - data.position).Magnitude < (data.radius or 50) then return data.field end
        end
    end

    return nil
end

local function createBloomLabel(bloom, field)
    local label = Instance.new("TextLabel")
    label.Name = bloom.Name
    label.Size = UDim2.new(1, 0, 0, 30)
    label.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
    label.BorderColor3 = field and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(255, 200, 100)
    label.BorderSizePixel = 1
    label.Text = ("  %s → %s"):format(bloom.Name, field and field.Name or "NO FIELD")
    label.TextSize = 11
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = listFrame
    return label
end

local function updateUIStats()
    spawnedLabel.Text = ("Spawned: %d"):format(bloomStats.total_spawned)
    activeLabel.Text = ("Active: %d"):format(#activeBlooms)
    destroyedLabel.Text = ("Destroyed: %d"):format(bloomStats.total_destroyed)
    assignedLabel.Text = ("Assigned: %d"):format(bloomStats.field_assignments)
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
        print("[BloomTracker] ✓ Bloom '" .. bloom.Name .. "' assigned to field '" .. field.Name .. "' at position " .. tostring(pos))
    else
        bloomStats.no_field_assigned = bloomStats.no_field_assigned + 1
        local fieldNames = ""
        for name, _ in pairs(fieldCache) do fieldNames = fieldNames .. (fieldNames == "" and name or ", " .. name) end
        print("[BloomTracker] ✗ Bloom '" .. bloom.Name .. "' at position " .. tostring(pos) .. " - NO FIELD MATCH")
        print("[BloomTracker]   Available fields: " .. (fieldNames ~= "" and fieldNames or "NONE"))
    end

    local uiLabel = createBloomLabel(bloom, field)
    activeBlooms[bloom] = {lastPos = pos, lastFieldName = field and field.Name or nil, uiLabel = uiLabel}
    updateUIStats()
end

local function isBloomCandidate(obj)
    if not obj then return false end
    if obj.GetAttribute then
        local ok, val = pcall(function() return obj:GetAttribute("IsBloom") end)
        if ok and val == true then return true end
    end
    return obj.Name and obj.Name:lower():find("bloom") or false
end

local function onDescendantAdded(desc)
    if isBloomCandidate(desc) then trackBloom(desc) return end
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
                    data.uiLabel.BorderColor3 = newField and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(255, 200, 100)
                    data.uiLabel.Text = ("  %s → %s"):format(bloom.Name, newField and newField.Name or "NO FIELD")
                end
                data.lastPos = newPos
            end
        end
    end

    updateUIStats()
end

-- ========== INIT ==========
local poppable = getPoppableFolder()
if poppable then
    cacheFieldData()
    for _, desc in ipairs(poppable:GetDescendants()) do
        if isBloomCandidate(desc) then trackBloom(desc) end
    end
    poppable.DescendantAdded:Connect(onDescendantAdded)
    RunService.Heartbeat:Connect(function()
        updateBloomPositions()
        sendDiscordReport()
    end)
    updateUIStats()
    print("[BloomTracker] ✓ Initialized with Discord webhooks")
end
