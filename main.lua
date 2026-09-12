-- Bloom Tracker UI - Loadstring Ready
-- Execute with: loadstring(game:HttpGet("https://raw.githubusercontent.com/Xan3vo/bloomdata/main/main.lua"))()

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Discord Webhook Configuration
local DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1548446623300849736/pyVshktLNmolGJt5eR1MyyqwUunDGcvRM5G53CNOJKLqo9_a7Wl7KbnQ4-aXSX8sm_Sf"
local DISCORD_ENABLED = true
local DISCORD_REPORT_INTERVAL = 60

-- Enable HTTP for executor
pcall(function() HttpService:SetHttpEnabled(true) end)

local POPPABLE_FOLDER_NAME = "PoppablePlants"
local FIELDS_FOLDER_NAME = "Fields"
local POSITION_CHECK_THRESHOLD = 2
local CHECK_INTERVAL = 0.5
local FIELD_DETECTION_RADIUS = 100 -- Larger radius for better detection
local DEBUG_MODE = true -- Set to false to disable debug logging

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
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui

-- Add shadow effect
local shadow = Instance.new("Frame")
shadow.Size = UDim2.new(1, 8, 1, 8)
shadow.Position = UDim2.new(0, -4, 0, -4)
shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadow.BorderSizePixel = 0
shadow.ZIndex = -1
shadow.Parent = mainFrame

-- Add rounded corner effect with border
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = mainFrame

local borderFrame = Instance.new("Frame")
borderFrame.Size = UDim2.new(1, 0, 1, 0)
borderFrame.BackgroundTransparency = 1
borderFrame.BorderSizePixel = 2
borderFrame.BorderColor3 = Color3.fromRGB(100, 200, 100)
borderFrame.Parent = mainFrame

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

local recentBlooms = {} -- Track recent bloom events

local function sendDiscordReport()
    if not DISCORD_ENABLED or not DISCORD_WEBHOOK_URL then return end

    local currentTime = tick()
    if currentTime - lastDiscordReport < DISCORD_REPORT_INTERVAL then return end
    lastDiscordReport = currentTime

    local activeCount = 0
    local fieldBlooms = 0
    local noFieldBlooms = 0

    for bloom, data in pairs(activeBlooms) do
        activeCount = activeCount + 1
        if data.lastFieldName then
            fieldBlooms = fieldBlooms + 1
        else
            noFieldBlooms = noFieldBlooms + 1
        end
    end

    -- Calculate stats
    local destroyRate = bloomStats.total_spawned > 0 and math.floor((bloomStats.total_destroyed / bloomStats.total_spawned) * 100) or 0
    local assignmentRate = bloomStats.total_spawned > 0 and math.floor((bloomStats.field_assignments / bloomStats.total_spawned) * 100) or 0

    -- Build nice embeds
    local statsEmbed = {
        title = "📊 Bloom Tracker - 1 Minute Report",
        description = "Real-time bloom statistics and field tracking",
        color = 0x00ff00, -- Green
        fields = {
            {name = "📈 Spawn Statistics", value = "```\nTotal Spawned: " .. bloomStats.total_spawned .. "\nTotal Destroyed: " .. bloomStats.total_destroyed .. "\nDestruction Rate: " .. destroyRate .. "%\n```", inline = false},
            {name = "🌸 Current Status", value = "```\nActive Blooms: " .. activeCount .. "\nIn Fields: " .. fieldBlooms .. "\nNo Field: " .. noFieldBlooms .. "\n```", inline = false},
            {name = "🎯 Field Assignment", value = "```\nSuccessfully Assigned: " .. bloomStats.field_assignments .. "\nAssignment Rate: " .. assignmentRate .. "%\nMissing Field: " .. bloomStats.no_field_assigned .. "\n```", inline = false},
            {name = "⏰ Timestamp", value = "```\n" .. os.date("%Y-%m-%d %H:%M:%S") .. "\n```", inline = false}
        },
        thumbnail = {
            url = "https://www.roblox.com/avatar-thumbnails?username=Bloom&x=150&y=150&format=Png"
        },
        footer = {
            text = "Bloom Tracker v1.0 | Next report in 60 seconds"
        }
    }

    local payload = {
        embeds = {statsEmbed},
        username = "🌸 Bloom Tracker Bot",
        avatar_url = "https://www.roblox.com/avatar-thumbnails?username=Bloom&x=150&y=150&format=Png"
    }

    local success, err = pcall(function()
        HttpService:PostAsync(DISCORD_WEBHOOK_URL, HttpService:JSONEncode(payload), Enum.HttpContentType.ApplicationJson)
    end)

    if success then
        print("[BloomTracker] ✓ Discord report sent - Active: " .. activeCount .. " | Spawned: " .. bloomStats.total_spawned .. " | Destroyed: " .. bloomStats.total_destroyed)
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

    -- Check bounding box collision (for Part-based fields)
    for _, data in pairs(fieldCache) do
        if data.useBoundingBox and data.boxCFrame and data.size then
            local rel = (data.boxCFrame:Inverse() * CFrame.new(pos)).Position
            -- Add padding/tolerance to bounding box check
            local padX = data.size.X/2 + 10
            local padY = data.size.Y/2 + 10
            local padZ = data.size.Z/2 + 10
            if math.abs(rel.X) <= padX and math.abs(rel.Y) <= padY and math.abs(rel.Z) <= padZ then
                return data.field
            end
        end
    end

    -- Fallback to distance check with larger radius
    for _, data in pairs(fieldCache) do
        if data.useBoundingBox and data.boxCFrame and data.size then
            local fieldPos = data.boxCFrame.Position
            local distance = (pos - fieldPos).Magnitude
            -- Use field size to calculate dynamic radius
            local fieldRadius = math.max(data.size.X, data.size.Y, data.size.Z) / 2 + 30
            if distance < fieldRadius then
                return data.field
            end
        end
    end

    for _, data in pairs(fieldCache) do
        if not data.useBoundingBox and data.position then
            if (pos - data.position).Magnitude < FIELD_DETECTION_RADIUS then return data.field end
        end
    end

    return nil
end

local function createBloomLabel(bloom, field)
    local label = Instance.new("TextLabel")
    label.Name = bloom.Name
    label.Size = UDim2.new(1, -6, 0, 32)
    label.BackgroundColor3 = field and Color3.fromRGB(45, 65, 45) or Color3.fromRGB(65, 55, 35)
    label.BorderSizePixel = 0
    label.Text = ("  %s %s"):format(field and "✓" or "✗", field and field.Name or "NO FIELD")
    label.TextSize = 12
    label.TextColor3 = field and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 200, 100)
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = label

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 6)
    padding.Parent = label

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
        if DEBUG_MODE then
            print("[BloomTracker] ✓ Bloom '" .. bloom.Name .. "' → " .. field.Name .. " at " .. string.format("(%.0f, %.0f, %.0f)", pos.X, pos.Y, pos.Z))
        end
    else
        bloomStats.no_field_assigned = bloomStats.no_field_assigned + 1
        if DEBUG_MODE then
            print("[BloomTracker] ✗ Bloom at " .. string.format("(%.0f, %.0f, %.0f)", pos.X, pos.Y, pos.Z) .. " - checking nearest fields...")
            -- Find and show nearest field for debugging
            local nearestDist = math.huge
            local nearestField = nil
            for name, data in pairs(fieldCache) do
                if data.boxCFrame then
                    local dist = (pos - data.boxCFrame.Position).Magnitude
                    if dist < nearestDist then
                        nearestDist = dist
                        nearestField = name
                    end
                end
            end
            if nearestField then
                print("[BloomTracker]   Nearest: " .. nearestField .. " (" .. string.format("%.1f", nearestDist) .. " studs away)")
            end
        end
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
                    data.uiLabel.BackgroundColor3 = newField and Color3.fromRGB(45, 65, 45) or Color3.fromRGB(65, 55, 35)
                    data.uiLabel.TextColor3 = newField and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 200, 100)
                    data.uiLabel.Text = ("  %s %s"):format(newField and "✓" or "✗", newField and newField.Name or "NO FIELD")
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
