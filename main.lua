-- 🌸 Bloom Tracker v2.0 - Loadstring Ready
-- Execute with: loadstring(game:HttpGet("https://raw.githubusercontent.com/Xan3vo/bloomdata/main/main.lua"))()

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- ===================== CONFIG =====================
local DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1548446623300849736/pyVshktLNmolGJt5eR1MyyqwUunDGcvRM5G53CNOJKLqo9_a7Wl7KbnQ4-aXSX8sm_Sf"
local DISCORD_ENABLED = true
local DISCORD_REPORT_INTERVAL = 60

local POPPABLE_FOLDER_NAME = "PoppablePlants"
local FIELDS_FOLDER_NAME = "Fields"
local POSITION_CHECK_THRESHOLD = 2
local CHECK_INTERVAL = 0.5
local FIELD_PADDING = 12 -- studs of tolerance added to each field's box
local DEBUG_MODE = true

pcall(function() HttpService:SetHttpEnabled(true) end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===================== STATE =====================
local activeBlooms = {}      -- [instance] = {lastPos, lastFieldName, uiLabel}
local fieldCache = {}        -- [name] = {part/model, cframe, size, halfSize}
local fieldCounts = {}        -- [name] = current live bloom count
local fieldOverlapParams = OverlapParams.new()
fieldOverlapParams.FilterType = Enum.RaycastFilterType.Include

local lastCheckTime = 0
local lastDiscordReport = 0
local startTime = os.time()
local bloomStats = {total_spawned = 0, total_destroyed = 0, field_assignments = 0, no_field_assigned = 0}
local searchFilter = ""

-- ===================== UTIL =====================
local function tween(obj, props, time, style)
    return TweenService:Create(obj, TweenInfo.new(time or 0.25, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
end

local function fmtVec(v)
    return string.format("(%.0f, %.0f, %.0f)", v.X, v.Y, v.Z)
end

local function fmtDuration(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then return string.format("%dh %dm %ds", h, m, s) end
    if m > 0 then return string.format("%dm %ds", m, s) end
    return string.format("%ds", s)
end

-- ===================== UI BUILD =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BloomTrackerGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Drop shadow (9-slice-ish simple version)
local shadow = Instance.new("ImageLabel")
shadow.Name = "Shadow"
shadow.BackgroundTransparency = 1
shadow.Image = "rbxassetid://1316045217"
shadow.ImageColor3 = Color3.new(0, 0, 0)
shadow.ImageTransparency = 0.45
shadow.ScaleType = Enum.ScaleType.Slice
shadow.SliceCenter = Rect.new(10, 10, 118, 118)
shadow.Size = UDim2.new(0, 420, 0, 480)
shadow.Position = UDim2.new(0, 4, 0, 4)
shadow.ZIndex = 0

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 400, 0, 470)
mainFrame.Position = UDim2.new(0, 20, 0, 20)
mainFrame.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.ZIndex = 1
mainFrame.Parent = screenGui
shadow.Parent = mainFrame

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(80, 200, 120)
mainStroke.Thickness = 1.5
mainStroke.Transparency = 0.3
mainStroke.Parent = mainFrame

-- ===== Title bar (draggable) =====
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 32, 36)
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 2
titleBar.Parent = mainFrame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleFix = Instance.new("Frame") -- cover bottom rounded corners of title bar
titleFix.Size = UDim2.new(1, 0, 0, 10)
titleFix.Position = UDim2.new(0, 0, 1, -10)
titleFix.BackgroundColor3 = titleBar.BackgroundColor3
titleFix.BorderSizePixel = 0
titleFix.ZIndex = 2
titleFix.Parent = titleBar

local titleIcon = Instance.new("TextLabel")
titleIcon.BackgroundTransparency = 1
titleIcon.Size = UDim2.new(0, 30, 1, 0)
titleIcon.Position = UDim2.new(0, 10, 0, 0)
titleIcon.Text = "🌸"
titleIcon.TextSize = 20
titleIcon.ZIndex = 3
titleIcon.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Size = UDim2.new(1, -110, 1, 0)
titleLabel.Position = UDim2.new(0, 40, 0, 0)
titleLabel.Text = "Bloom Tracker"
titleLabel.TextSize = 16
titleLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 3
titleLabel.Parent = titleBar

local liveDot = Instance.new("Frame")
liveDot.Size = UDim2.new(0, 8, 0, 8)
liveDot.Position = UDim2.new(1, -78, 0.5, -4)
liveDot.BackgroundColor3 = Color3.fromRGB(90, 255, 120)
liveDot.BorderSizePixel = 0
liveDot.ZIndex = 3
liveDot.Parent = titleBar
Instance.new("UICorner", liveDot).CornerRadius = UDim.new(1, 0)

task.spawn(function()
    while liveDot.Parent do
        tween(liveDot, {BackgroundTransparency = 0.7}, 0.8):Play()
        task.wait(0.8)
        tween(liveDot, {BackgroundTransparency = 0}, 0.8):Play()
        task.wait(0.8)
    end
end)

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 28, 0, 28)
minimizeBtn.Position = UDim2.new(1, -70, 0.5, -14)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 48)
minimizeBtn.Text = "—"
minimizeBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 16
minimizeBtn.ZIndex = 3
minimizeBtn.AutoButtonColor = true
minimizeBtn.Parent = titleBar
Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -36, 0.5, -14)
closeBtn.BackgroundColor3 = Color3.fromRGB(60, 35, 35)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 150, 150)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.ZIndex = 3
closeBtn.AutoButtonColor = true
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

closeBtn.MouseButton1Click:Connect(function()
    tween(mainFrame, {Size = UDim2.new(0, 400, 0, 0)}, 0.25):Play()
    task.wait(0.25)
    screenGui:Destroy()
end)

local minimized = false
local expandedSize = UDim2.new(0, 400, 0, 470)
minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    tween(mainFrame, {Size = minimized and UDim2.new(0, 400, 0, 44) or expandedSize}, 0.25):Play()
    minimizeBtn.Text = minimized and "▢" or "—"
end)

-- Dragging
do
    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- ===== Stat cards =====
local statsHolder = Instance.new("Frame")
statsHolder.Size = UDim2.new(1, -20, 0, 74)
statsHolder.Position = UDim2.new(0, 10, 0, 52)
statsHolder.BackgroundTransparency = 1
statsHolder.ZIndex = 2
statsHolder.Parent = mainFrame

local statsLayout = Instance.new("UIGridLayout")
statsLayout.CellSize = UDim2.new(0.25, -6, 1, 0)
statsLayout.CellPadding = UDim2.new(0, 8, 0, 0)
statsLayout.FillDirection = Enum.FillDirection.Horizontal
statsLayout.Parent = statsHolder

local statCards = {}
local function createStatCard(key, label, color)
    local card = Instance.new("Frame")
    card.BackgroundColor3 = Color3.fromRGB(32, 36, 40)
    card.ZIndex = 2
    card.Parent = statsHolder
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Transparency = 0.75
    stroke.Parent = card

    local valueLabel = Instance.new("TextLabel")
    valueLabel.BackgroundTransparency = 1
    valueLabel.Size = UDim2.new(1, 0, 0, 30)
    valueLabel.Position = UDim2.new(0, 0, 0, 8)
    valueLabel.Text = "0"
    valueLabel.TextSize = 20
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextColor3 = color
    valueLabel.ZIndex = 3
    valueLabel.Parent = card

    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.Size = UDim2.new(1, 0, 0, 16)
    nameLabel.Position = UDim2.new(0, 0, 1, -22)
    nameLabel.Text = label
    nameLabel.TextSize = 10
    nameLabel.Font = Enum.Font.Gotham
    nameLabel.TextColor3 = Color3.fromRGB(150, 155, 160)
    nameLabel.ZIndex = 3
    nameLabel.Parent = card

    statCards[key] = valueLabel
end

createStatCard("spawned", "SPAWNED", Color3.fromRGB(120, 190, 255))
createStatCard("active", "ACTIVE", Color3.fromRGB(255, 210, 90))
createStatCard("assigned", "IN FIELD", Color3.fromRGB(100, 255, 140))
createStatCard("destroyed", "POPPED", Color3.fromRGB(255, 120, 120))

-- ===== Search bar =====
local searchBar = Instance.new("Frame")
searchBar.Size = UDim2.new(1, -20, 0, 30)
searchBar.Position = UDim2.new(0, 10, 0, 132)
searchBar.BackgroundColor3 = Color3.fromRGB(32, 36, 40)
searchBar.ZIndex = 2
searchBar.Parent = mainFrame
Instance.new("UICorner", searchBar).CornerRadius = UDim.new(0, 8)

local searchIcon = Instance.new("TextLabel")
searchIcon.BackgroundTransparency = 1
searchIcon.Size = UDim2.new(0, 24, 1, 0)
searchIcon.Position = UDim2.new(0, 6, 0, 0)
searchIcon.Text = "🔍"
searchIcon.TextSize = 12
searchIcon.ZIndex = 3
searchIcon.Parent = searchBar

local searchBox = Instance.new("TextBox")
searchBox.BackgroundTransparency = 1
searchBox.Size = UDim2.new(1, -34, 1, 0)
searchBox.Position = UDim2.new(0, 30, 0, 0)
searchBox.PlaceholderText = "Filter by bloom or field name..."
searchBox.Text = ""
searchBox.TextSize = 12
searchBox.Font = Enum.Font.Gotham
searchBox.TextColor3 = Color3.fromRGB(220, 220, 220)
searchBox.PlaceholderColor3 = Color3.fromRGB(120, 125, 130)
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.ZIndex = 3
searchBox.Parent = searchBar

-- ===== Bloom list =====
local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "BloomListFrame"
listFrame.Size = UDim2.new(1, -20, 1, -172)
listFrame.Position = UDim2.new(0, 10, 0, 170)
listFrame.BackgroundColor3 = Color3.fromRGB(28, 30, 34)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 5
listFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 200, 120)
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.ZIndex = 2
listFrame.Parent = mainFrame
Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 8)

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 6)
listPadding.PaddingLeft = UDim.new(0, 6)
listPadding.PaddingRight = UDim.new(0, 6)
listPadding.Parent = listFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    searchFilter = searchBox.Text:lower()
    for bloom, data in pairs(activeBlooms) do
        if data.uiLabel then
            local haystack = (bloom.Name .. " " .. (data.lastFieldName or "no field")):lower()
            data.uiLabel.Visible = searchFilter == "" or haystack:find(searchFilter, 1, true) ~= nil
        end
    end
end)

-- ===================== FIELD / BLOOM DETECTION =====================
local function getFieldsFolder()
    local f = Workspace:FindFirstChild(FIELDS_FOLDER_NAME) or Workspace:FindFirstChild("FlowerZones")
    if f then return f end
    for _, v in ipairs(Workspace:GetDescendants()) do
        if (v.Name == FIELDS_FOLDER_NAME or v.Name == "FlowerZones") and (v:IsA("Folder") or v:IsA("Model")) then
            return v
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
    return part and part.Position or nil
end

local fieldParts = {} -- flat list of {part, name} for GetPartBoundsInBox filtering

local function cacheFieldData()
    fieldCache = {}
    fieldParts = {}
    fieldCounts = {}
    local fieldsFolder = getFieldsFolder()
    if not fieldsFolder then
        warn("[BloomTracker] Fields folder not found!")
        return
    end

    for _, field in ipairs(fieldsFolder:GetChildren()) do
        local part, cf, size

        if field:IsA("BasePart") then
            part, cf, size = field, field.CFrame, field.Size
        elseif field:IsA("Model") then
            local ok, boxCFrame, boxSize = pcall(function() return field:GetBoundingBox() end)
            if ok and boxCFrame then
                part, cf, size = field:FindFirstChildWhichIsA("BasePart"), boxCFrame, boxSize
            end
        end

        if cf and size then
            fieldCache[field.Name] = {
                instance = field,
                part = part,
                cframe = cf,
                size = size,
                halfSize = size / 2 + Vector3.new(FIELD_PADDING, FIELD_PADDING, FIELD_PADDING),
            }
            fieldCounts[field.Name] = 0
            if part then table.insert(fieldParts, part) end
            if DEBUG_MODE then print("[BloomTracker] ✓ Cached field '" .. field.Name .. "'") end
        end
    end

    fieldOverlapParams.FilterDescendantsInstances = fieldParts
    print("[BloomTracker] Total fields cached: " .. tostring(#fieldParts))
end

-- 1) Point-in-box test (fast, works for axis/rotated boxes via CFrame space)
local function pointInBox(pos, data)
    local rel = data.cframe:PointToObjectSpace(pos)
    return math.abs(rel.X) <= data.halfSize.X and math.abs(rel.Y) <= data.halfSize.Y and math.abs(rel.Z) <= data.halfSize.Z
end

-- 2) Real physical overlap test using GetPartBoundsInBox around the bloom
local probeSize = Vector3.new(6, 12, 6)
local function overlapField(pos)
    if #fieldParts == 0 then return nil end
    local ok, parts = pcall(function()
        return Workspace:GetPartBoundsInBox(CFrame.new(pos), probeSize, fieldOverlapParams)
    end)
    if ok and parts and #parts > 0 then
        for name, data in pairs(fieldCache) do
            if data.part and table.find(parts, data.part) then
                return data.instance, name
            end
        end
    end
    return nil
end

-- 3) Downward raycast to catch blooms hovering just above a field plate
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local function raycastField(pos)
    rayParams.FilterDescendantsInstances = fieldParts
    local result = Workspace:Raycast(pos + Vector3.new(0, 5, 0), Vector3.new(0, -40, 0), rayParams)
    if result and result.Instance then
        for name, data in pairs(fieldCache) do
            if data.part == result.Instance then return data.instance, name end
        end
    end
    return nil
end

local function getFieldForPosition(pos)
    if not pos then return nil end

    -- Method 1: point-in-box (handles rotation correctly, most accurate)
    for name, data in pairs(fieldCache) do
        if pointInBox(pos, data) then return data.instance, name end
    end

    -- Method 2: real collision volume overlap
    local inst, name = overlapField(pos)
    if inst then return inst, name end

    -- Method 3: raycast straight down onto field plates
    inst, name = raycastField(pos)
    if inst then return inst, name end

    return nil
end

-- ===================== UI HELPERS =====================
local function createBloomLabel(bloom, field)
    local label = Instance.new("Frame")
    label.BackgroundColor3 = field and Color3.fromRGB(34, 48, 38) or Color3.fromRGB(48, 42, 32)
    label.Size = UDim2.new(1, 0, 0, 30)
    label.ZIndex = 2
    label.LayoutOrder = os.clock() * -1
    Instance.new("UICorner", label).CornerRadius = UDim.new(0, 6)

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 6, 0, 6)
    dot.Position = UDim2.new(0, 10, 0.5, -3)
    dot.BackgroundColor3 = field and Color3.fromRGB(100, 255, 130) or Color3.fromRGB(255, 190, 90)
    dot.ZIndex = 3
    dot.Parent = label
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.Size = UDim2.new(0.5, -20, 1, 0)
    nameLabel.Position = UDim2.new(0, 24, 0, 0)
    nameLabel.Text = bloom.Name
    nameLabel.TextSize = 12
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.ZIndex = 3
    nameLabel.Parent = label

    local fieldLabel = Instance.new("TextLabel")
    fieldLabel.BackgroundTransparency = 1
    fieldLabel.Size = UDim2.new(0.5, -10, 1, 0)
    fieldLabel.Position = UDim2.new(0.5, 0, 0, 0)
    fieldLabel.Text = field and field.Name or "no field"
    fieldLabel.TextSize = 12
    fieldLabel.Font = Enum.Font.Gotham
    fieldLabel.TextColor3 = field and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(255, 190, 110)
    fieldLabel.TextXAlignment = Enum.TextXAlignment.Right
    fieldLabel.TextTruncate = Enum.TextTruncate.AtEnd
    fieldLabel.ZIndex = 3
    fieldLabel.Parent = label

    local padding = Instance.new("UIPadding")
    padding.PaddingRight = UDim.new(0, 10)
    padding.Parent = label

    label.Parent = listFrame
    label.BackgroundTransparency = 1
    for _, c in ipairs({dot, nameLabel, fieldLabel}) do
        if c:IsA("TextLabel") then c.TextTransparency = 1 end
    end
    tween(label, {BackgroundTransparency = 0}, 0.2):Play()
    tween(nameLabel, {TextTransparency = 0}, 0.2):Play()
    tween(fieldLabel, {TextTransparency = 0}, 0.2):Play()

    return label, nameLabel, fieldLabel, dot
end

local function updateUIStats()
    local active = 0
    for _ in pairs(activeBlooms) do active = active + 1 end
    statCards.spawned.Text = tostring(bloomStats.total_spawned)
    statCards.active.Text = tostring(active)
    statCards.assigned.Text = tostring(bloomStats.field_assignments)
    statCards.destroyed.Text = tostring(bloomStats.total_destroyed)
end

-- ===================== DISCORD =====================
local function buildFieldBreakdownText()
    local lines = {}
    local sorted = {}
    for name, count in pairs(fieldCounts) do
        table.insert(sorted, {name = name, count = count})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    for i, entry in ipairs(sorted) do
        if i > 10 then break end
        if entry.count > 0 then
            table.insert(lines, string.format("%-20s %d", entry.name, entry.count))
        end
    end
    if #lines == 0 then return "No active blooms in any field" end
    return table.concat(lines, "\n")
end

local function sendDiscordReport()
    if not DISCORD_ENABLED or not DISCORD_WEBHOOK_URL then return end
    local currentTime = tick()
    if currentTime - lastDiscordReport < DISCORD_REPORT_INTERVAL then return end
    lastDiscordReport = currentTime

    local active, fieldBlooms, noFieldBlooms = 0, 0, 0
    for _, data in pairs(activeBlooms) do
        active = active + 1
        if data.lastFieldName then fieldBlooms = fieldBlooms + 1 else noFieldBlooms = noFieldBlooms + 1 end
    end

    local destroyRate = bloomStats.total_spawned > 0 and math.floor((bloomStats.total_destroyed / bloomStats.total_spawned) * 100) or 0
    local assignRate = bloomStats.total_spawned > 0 and math.floor((bloomStats.field_assignments / bloomStats.total_spawned) * 100) or 0
    local uptime = fmtDuration(os.time() - startTime)

    local barLength = 20
    local filled = math.floor((assignRate / 100) * barLength)
    local bar = string.rep("█", filled) .. string.rep("░", barLength - filled)

    local embed = {
        title = "🌸 Bloom Tracker — Live Report",
        description = string.format("```\n%s  %d%%\n```\n**Session uptime:** `%s`", bar, assignRate, uptime),
        color = fieldBlooms >= noFieldBlooms and 0x57F287 or 0xFEE75C,
        fields = {
            { name = "📈 Totals", value = string.format("```yaml\nSpawned:   %d\nDestroyed: %d\nPop Rate:  %d%%\n```", bloomStats.total_spawned, bloomStats.total_destroyed, destroyRate), inline = true },
            { name = "🌿 Live Status", value = string.format("```yaml\nActive:    %d\nIn Field:  %d\nNo Field:  %d\n```", active, fieldBlooms, noFieldBlooms), inline = true },
            { name = "🗺️ Field Breakdown (top 10)", value = "```\n" .. buildFieldBreakdownText() .. "\n```", inline = false },
        },
        footer = { text = "Bloom Tracker v2.0 • next report in " .. DISCORD_REPORT_INTERVAL .. "s" },
        timestamp = DateTime.now():ToIsoDate(),
    }

    local payload = {
        embeds = { embed },
        username = "Bloom Tracker",
    }

    local success, err = pcall(function()
        HttpService:PostAsync(DISCORD_WEBHOOK_URL, HttpService:JSONEncode(payload), Enum.HttpContentType.ApplicationJson)
    end)

    if success then
        print(string.format("[BloomTracker] ✓ Discord report sent — Active %d | Spawned %d | Destroyed %d", active, bloomStats.total_spawned, bloomStats.total_destroyed))
    else
        warn("[BloomTracker] ✗ Discord error: " .. tostring(err))
    end
end

-- ===================== BLOOM TRACKING =====================
local function isBloomCandidate(obj)
    if not obj then return false end
    if obj.GetAttribute then
        local ok, val = pcall(function() return obj:GetAttribute("IsBloom") end)
        if ok and val == true then return true end
    end
    return obj.Name and obj.Name:lower():find("bloom") ~= nil
end

local function trackBloom(bloom)
    if activeBlooms[bloom] then return end
    local pos = getInstancePosition(bloom)
    if not pos then return end

    bloomStats.total_spawned = bloomStats.total_spawned + 1
    local field, fieldName = getFieldForPosition(pos)

    if field then
        bloomStats.field_assignments = bloomStats.field_assignments + 1
        fieldCounts[fieldName] = (fieldCounts[fieldName] or 0) + 1
        if DEBUG_MODE then print("[BloomTracker] ✓ " .. bloom.Name .. " → " .. fieldName .. " @ " .. fmtVec(pos)) end
    else
        bloomStats.no_field_assigned = bloomStats.no_field_assigned + 1
        if DEBUG_MODE then print("[BloomTracker] ✗ " .. bloom.Name .. " @ " .. fmtVec(pos) .. " — no field match") end
    end

    local uiLabel = createBloomLabel(bloom, field)
    activeBlooms[bloom] = {lastPos = pos, lastFieldName = fieldName, uiLabel = uiLabel}
    updateUIStats()
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
            if data.lastFieldName then fieldCounts[data.lastFieldName] = math.max(0, (fieldCounts[data.lastFieldName] or 1) - 1) end
            local lbl = data.uiLabel
            tween(lbl, {BackgroundTransparency = 1}, 0.2):Play()
            task.delay(0.2, function() if lbl and lbl.Parent then lbl:Destroy() end end)
            activeBlooms[bloom] = nil
        else
            local newPos = getInstancePosition(bloom)
            if newPos and (newPos - data.lastPos).Magnitude > POSITION_CHECK_THRESHOLD then
                local newField, newFieldName = getFieldForPosition(newPos)
                if data.lastFieldName ~= newFieldName then
                    if data.lastFieldName then fieldCounts[data.lastFieldName] = math.max(0, (fieldCounts[data.lastFieldName] or 1) - 1) end
                    if newFieldName then fieldCounts[newFieldName] = (fieldCounts[newFieldName] or 0) + 1 end
                    data.lastFieldName = newFieldName

                    local label = data.uiLabel
                    local nameLabel, fieldLabel, dot = label:FindFirstChildWhichIsA("TextLabel"), nil, nil
                    for _, c in ipairs(label:GetChildren()) do
                        if c:IsA("TextLabel") and c.TextXAlignment == Enum.TextXAlignment.Right then fieldLabel = c end
                        if c:IsA("Frame") then dot = c end
                    end
                    tween(label, {BackgroundColor3 = newField and Color3.fromRGB(34, 48, 38) or Color3.fromRGB(48, 42, 32)}, 0.2):Play()
                    if dot then tween(dot, {BackgroundColor3 = newField and Color3.fromRGB(100, 255, 130) or Color3.fromRGB(255, 190, 90)}, 0.2):Play() end
                    if fieldLabel then
                        fieldLabel.Text = newFieldName or "no field"
                        tween(fieldLabel, {TextColor3 = newField and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(255, 190, 110)}, 0.2):Play()
                    end
                end
                data.lastPos = newPos
            end
        end
    end

    updateUIStats()
end

-- ===================== INIT =====================
local function init()
    local poppable = getPoppableFolder()
    if not poppable then
        warn("[BloomTracker] PoppablePlants not found — retrying when it appears...")
        Workspace.ChildAdded:Connect(function(child)
            if child.Name == POPPABLE_FOLDER_NAME then init() end
        end)
        return
    end

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
    print("[BloomTracker] ✓ v2.0 initialized — tracking " .. tostring(#fieldParts) .. " fields")
end

-- Intro animation
mainFrame.Size = UDim2.new(0, 400, 0, 0)
mainFrame.Position = UDim2.new(0, 20, 0, 20)
tween(mainFrame, {Size = expandedSize}, 0.35, Enum.EasingStyle.Back):Play()

init()
