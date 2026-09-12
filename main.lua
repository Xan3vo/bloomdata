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
local INTERVAL_OPTIONS = {30, 60, 300, 600} -- 30s, 1m, 5m, 10m
local intervalIndex = 2 -- defaults to 60s
local DISCORD_MAX_RETRIES = 4
local DISCORD_RETRY_BASE_DELAY = 2 -- seconds, doubles each retry

local POPPABLE_FOLDER_NAME = "PoppablePlants"
local FIELDS_FOLDER_NAME = "Fields"
local POSITION_CHECK_THRESHOLD = 2
local CHECK_INTERVAL = 0.5
local FIELD_PADDING = 12 -- studs of tolerance added to each field's box
local DEBUG_MODE = true

pcall(function() HttpService:SetHttpEnabled(true) end)

-- Executor HTTP detection: HttpService:PostAsync is blocked ("dangerous call") for
-- non-Roblox scripts even under executors. Executors instead expose their own request
-- function (request / http_request / syn.request / etc) that bypasses this restriction.
local executorRequest = (syn and syn.request)
    or (http and http.request)
    or request
    or http_request
    or fluxus and fluxus.request
    or nil

local HTTP_METHOD = executorRequest and "executor" or "roblox"
print("[BloomTracker] HTTP method: " .. HTTP_METHOD .. (executorRequest and " (using executor's request function)" or " (using HttpService:PostAsync - may be blocked!)"))

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

-- Spawn history: every spawn event timestamped, so we can compute rolling rates
-- (spawns in the last 10 min / 1 hr / etc) per field. Pruned periodically so it
-- never grows unbounded during long sessions.
local SPAWN_HISTORY_RETENTION = 3600 * 6 -- keep 6 hours of history max
local spawnHistory = {} -- { {time = os.time(), field = "Mushroom Field" or "NO_FIELD"}, ... }

local function recordSpawn(fieldName)
    table.insert(spawnHistory, {time = os.time(), field = fieldName or "NO_FIELD"})
end

local function pruneSpawnHistory()
    local cutoff = os.time() - SPAWN_HISTORY_RETENTION
    local i = 1
    while i <= #spawnHistory and spawnHistory[i].time < cutoff do
        i = i + 1
    end
    if i > 1 then
        local trimmed = table.create and table.create(#spawnHistory - i + 1) or {}
        for j = i, #spawnHistory do trimmed[#trimmed + 1] = spawnHistory[j] end
        spawnHistory = trimmed
    end
end

-- Counts spawns per field within the last `windowSeconds`. Returns {fieldName = count, ...}
-- plus a "NO_FIELD" bucket for unmatched spawns.
local function countSpawnsInWindow(windowSeconds)
    local cutoff = os.time() - windowSeconds
    local counts = {}
    for i = #spawnHistory, 1, -1 do
        local entry = spawnHistory[i]
        if entry.time < cutoff then break end -- history is time-ordered, safe to stop early
        counts[entry.field] = (counts[entry.field] or 0) + 1
    end
    return counts
end

-- Projects an hourly rate from a shorter window (e.g. 10 min of data -> spawns/hr estimate)
local function projectHourlyRate(count, windowSeconds)
    if windowSeconds <= 0 then return 0 end
    return count * (3600 / windowSeconds)
end

-- Forward declarations (assigned later; referenced by UI callbacks created earlier in the file)
local sendDiscordReport
local refreshStatusLabel

-- Discord delivery state
local discordState = {
    lastSuccessTime = nil,
    lastFailTime = nil,
    consecutiveFailures = 0,
    totalSent = 0,
    totalFailed = 0,
    sending = false,
    queue = {}, -- undelivered payloads waiting to be retried/flushed
}

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
shadow.Size = UDim2.new(0, 420, 0, 532)
shadow.Position = UDim2.new(0, 4, 0, 4)
shadow.ZIndex = 0

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 400, 0, 522)
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
local expandedSize = UDim2.new(0, 400, 0, 522)
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

-- ===== Discord control bar =====
local discordBar = Instance.new("Frame")
discordBar.Size = UDim2.new(1, -20, 0, 52)
discordBar.Position = UDim2.new(0, 10, 0, 168)
discordBar.BackgroundColor3 = Color3.fromRGB(32, 36, 40)
discordBar.ZIndex = 2
discordBar.Parent = mainFrame
Instance.new("UICorner", discordBar).CornerRadius = UDim.new(0, 8)

local discordIcon = Instance.new("TextLabel")
discordIcon.BackgroundTransparency = 1
discordIcon.Size = UDim2.new(0, 26, 0, 26)
discordIcon.Position = UDim2.new(0, 8, 0, 6)
discordIcon.Text = "💬"
discordIcon.TextSize = 14
discordIcon.ZIndex = 3
discordIcon.Parent = discordBar

-- Toggle switch
local toggleTrack = Instance.new("Frame")
toggleTrack.Size = UDim2.new(0, 38, 0, 20)
toggleTrack.Position = UDim2.new(0, 8, 0, 26)
toggleTrack.BackgroundColor3 = Color3.fromRGB(90, 220, 130)
toggleTrack.ZIndex = 3
toggleTrack.Parent = discordBar
Instance.new("UICorner", toggleTrack).CornerRadius = UDim.new(1, 0)

local toggleKnob = Instance.new("Frame")
toggleKnob.Size = UDim2.new(0, 16, 0, 16)
toggleKnob.Position = UDim2.new(1, -18, 0.5, -8)
toggleKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
toggleKnob.ZIndex = 4
toggleKnob.Parent = toggleTrack
Instance.new("UICorner", toggleKnob).CornerRadius = UDim.new(1, 0)

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, 0, 1, 0)
toggleBtn.BackgroundTransparency = 1
toggleBtn.Text = ""
toggleBtn.ZIndex = 5
toggleBtn.Parent = toggleTrack

local statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.Size = UDim2.new(1, -110, 0, 16)
statusLabel.Position = UDim2.new(0, 36, 0, 4)
statusLabel.Text = "Discord Webhook"
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.ZIndex = 3
statusLabel.Parent = discordBar

local statusSubLabel = Instance.new("TextLabel")
statusSubLabel.BackgroundTransparency = 1
statusSubLabel.Size = UDim2.new(1, -110, 0, 16)
statusSubLabel.Position = UDim2.new(0, 36, 0, 20)
statusSubLabel.Text = "Never sent yet"
statusSubLabel.TextSize = 10
statusSubLabel.Font = Enum.Font.Gotham
statusSubLabel.TextColor3 = Color3.fromRGB(150, 155, 160)
statusSubLabel.TextXAlignment = Enum.TextXAlignment.Left
statusSubLabel.ZIndex = 3
statusSubLabel.Parent = discordBar

-- Interval buttons
local intervalHolder = Instance.new("Frame")
intervalHolder.Size = UDim2.new(0, 96, 0, 44)
intervalHolder.Position = UDim2.new(1, -100, 0, 4)
intervalHolder.BackgroundTransparency = 1
intervalHolder.ZIndex = 3
intervalHolder.Parent = discordBar

local intervalGrid = Instance.new("UIGridLayout")
intervalGrid.CellSize = UDim2.new(0.5, -2, 0.5, -2)
intervalGrid.CellPadding = UDim2.new(0, 4, 0, 4)
intervalGrid.Parent = intervalHolder

local intervalLabels = {"30s", "1m", "5m", "10m"}
local intervalButtons = {}
for i, lbl in ipairs(intervalLabels) do
    local btn = Instance.new("TextButton")
    btn.BackgroundColor3 = i == intervalIndex and Color3.fromRGB(90, 200, 120) or Color3.fromRGB(45, 50, 55)
    btn.Text = lbl
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.TextColor3 = i == intervalIndex and Color3.fromRGB(15, 30, 20) or Color3.fromRGB(200, 200, 205)
    btn.ZIndex = 4
    btn.AutoButtonColor = true
    btn.Parent = intervalHolder
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    intervalButtons[i] = btn

    btn.MouseButton1Click:Connect(function()
        intervalIndex = i
        for j, b in ipairs(intervalButtons) do
            local sel = j == intervalIndex
            tween(b, {BackgroundColor3 = sel and Color3.fromRGB(90, 200, 120) or Color3.fromRGB(45, 50, 55)}, 0.15):Play()
            b.TextColor3 = sel and Color3.fromRGB(15, 30, 20) or Color3.fromRGB(200, 200, 205)
        end
        lastDiscordReport = 0 -- send immediately on interval change so you see it take effect
        print("[BloomTracker] Discord interval set to " .. INTERVAL_OPTIONS[intervalIndex] .. "s")
    end)
end

local function refreshDiscordToggleUI()
    tween(toggleTrack, {BackgroundColor3 = DISCORD_ENABLED and Color3.fromRGB(90, 220, 130) or Color3.fromRGB(80, 84, 90)}, 0.15):Play()
    tween(toggleKnob, {Position = DISCORD_ENABLED and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)}, 0.15):Play()
    for _, b in ipairs(intervalButtons) do b.AutoButtonColor = DISCORD_ENABLED end
end

toggleBtn.MouseButton1Click:Connect(function()
    DISCORD_ENABLED = not DISCORD_ENABLED
    refreshDiscordToggleUI()
    print("[BloomTracker] Discord webhook " .. (DISCORD_ENABLED and "ENABLED" or "DISABLED"))
    if DISCORD_ENABLED then
        lastDiscordReport = 0
        sendDiscordReport(true)
    end
    refreshStatusLabel()
end)

-- ===== Bloom list =====
local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "BloomListFrame"
listFrame.Size = UDim2.new(1, -20, 1, -226)
listFrame.Position = UDim2.new(0, 10, 0, 224)
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

-- Builds a spawn-rate table: per field, how many spawned in the last 10 min and last 1 hr.
-- Sorted by 1-hour count descending. Includes a "(No Field)" row for unmatched spawns.
local function buildSpawnRateText()
    local counts10m = countSpawnsInWindow(600)   -- 10 minutes
    local counts1h = countSpawnsInWindow(3600)   -- 1 hour

    local names = {}
    local seen = {}
    for _, data in pairs(fieldCache) do
        if not seen[data.instance.Name] then
            seen[data.instance.Name] = true
            table.insert(names, data.instance.Name)
        end
    end
    if counts10m.NO_FIELD or counts1h.NO_FIELD then table.insert(names, "(No Field)") end

    local rows = {}
    for _, name in ipairs(names) do
        local key = name == "(No Field)" and "NO_FIELD" or name
        local c10 = counts10m[key] or 0
        local c1h = counts1h[key] or 0
        if c10 > 0 or c1h > 0 then
            table.insert(rows, {name = name, c10 = c10, c1h = c1h})
        end
    end
    table.sort(rows, function(a, b) return a.c1h > b.c1h end)

    if #rows == 0 then return "No spawns recorded yet" end

    local lines = {string.format("%-18s %5s %5s", "FIELD", "10m", "1h")}
    for i, row in ipairs(rows) do
        if i > 12 then break end
        table.insert(lines, string.format("%-18s %5d %5d", row.name:sub(1, 18), row.c10, row.c1h))
    end
    return table.concat(lines, "\n")
end

refreshStatusLabel = function()
    if DISCORD_ENABLED then
        statusLabel.Text = "Discord Webhook"
    else
        statusLabel.Text = "Discord Webhook (off)"
    end

    if discordState.sending then
        statusSubLabel.Text = "Sending..."
        statusSubLabel.TextColor3 = Color3.fromRGB(255, 210, 90)
    elseif discordState.consecutiveFailures > 0 then
        statusSubLabel.Text = string.format("✗ Failed x%d — retrying", discordState.consecutiveFailures)
        statusSubLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
    elseif discordState.lastSuccessTime then
        local ago = math.floor(os.time() - discordState.lastSuccessTime)
        statusSubLabel.Text = string.format("✓ Last sent %ds ago (%d total)", ago, discordState.totalSent)
        statusSubLabel.TextColor3 = Color3.fromRGB(120, 220, 150)
    else
        statusSubLabel.Text = "Never sent yet"
        statusSubLabel.TextColor3 = Color3.fromRGB(150, 155, 160)
    end
end

local function buildReportPayload()
    local active, fieldBlooms, noFieldBlooms = 0, 0, 0
    for _, data in pairs(activeBlooms) do
        active = active + 1
        if data.lastFieldName then fieldBlooms = fieldBlooms + 1 else noFieldBlooms = noFieldBlooms + 1 end
    end

    local destroyRate = bloomStats.total_spawned > 0 and math.floor((bloomStats.total_destroyed / bloomStats.total_spawned) * 100) or 0
    local assignRate = bloomStats.total_spawned > 0 and math.floor((bloomStats.field_assignments / bloomStats.total_spawned) * 100) or 0
    local uptime = fmtDuration(os.time() - startTime)
    local currentInterval = INTERVAL_OPTIONS[intervalIndex]

    local barLength = 20
    local filled = math.floor((assignRate / 100) * barLength)
    local bar = string.rep("█", filled) .. string.rep("░", barLength - filled)

    local reliabilityNote = discordState.consecutiveFailures > 0
        and string.format("⚠️ %d delivery failure(s) recovered before this report", discordState.consecutiveFailures)
        or "✓ Delivering normally"

    local embed = {
        title = "🌸 Bloom Tracker — Live Report",
        description = string.format("```\n%s  %d%%\n```\n**Session uptime:** `%s`   •   %s", bar, assignRate, uptime, reliabilityNote),
        color = fieldBlooms >= noFieldBlooms and 0x57F287 or 0xFEE75C,
        fields = {
            { name = "📈 Totals", value = string.format("```yaml\nSpawned:   %d\nDestroyed: %d\nPop Rate:  %d%%\n```", bloomStats.total_spawned, bloomStats.total_destroyed, destroyRate), inline = true },
            { name = "🌿 Live Status", value = string.format("```yaml\nActive:    %d\nIn Field:  %d\nNo Field:  %d\n```", active, fieldBlooms, noFieldBlooms), inline = true },
            { name = "🗺️ Currently Active (top 10)", value = "```\n" .. buildFieldBreakdownText() .. "\n```", inline = false },
            { name = "⏱️ Spawn Rate by Field (10m / 1h)", value = "```\n" .. buildSpawnRateText() .. "\n```", inline = false },
        },
        footer = { text = string.format("Bloom Tracker v2.0 • report #%d • every %ds", discordState.totalSent + 1, currentInterval) },
        timestamp = DateTime.now():ToIsoDate(),
    }

    return {
        embeds = { embed },
        username = "Bloom Tracker",
    }
end

-- Performs the actual HTTP POST, preferring the executor's request function
-- (bypasses Roblox's "dangerous call" block on HttpService:PostAsync).
local function postJson(url, encoded)
    if executorRequest then
        local ok, response = pcall(function()
            return executorRequest({
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = encoded,
            })
        end)
        if not ok then return false, response end
        -- Discord returns 204/200 on success; treat anything else as failure
        local status = response and (response.StatusCode or response.Status)
        if status and (status == 200 or status == 204) then
            return true
        elseif status then
            return false, "HTTP " .. tostring(status) .. (response.Body and (": " .. tostring(response.Body)) or "")
        end
        return true -- some executors return nothing on success
    else
        local ok, err = pcall(function()
            HttpService:PostAsync(url, encoded, Enum.HttpContentType.ApplicationJson)
        end)
        return ok, err
    end
end

-- Sends one payload with automatic retry + exponential backoff.
-- Returns true/false via callback so the caller knows the final outcome.
local function sendToDiscordWithRetry(payload, onDone)
    task.spawn(function()
        local attempt = 0
        local delaySec = DISCORD_RETRY_BASE_DELAY
        local encoded = HttpService:JSONEncode(payload)

        while attempt <= DISCORD_MAX_RETRIES do
            attempt = attempt + 1
            local success, errOrResult = postJson(DISCORD_WEBHOOK_URL, encoded)

            if success then
                if onDone then onDone(true, attempt) end
                return
            end

            warn(string.format("[BloomTracker] Discord send attempt %d/%d failed: %s", attempt, DISCORD_MAX_RETRIES + 1, tostring(errOrResult)))

            if attempt <= DISCORD_MAX_RETRIES then
                task.wait(delaySec)
                delaySec = math.min(delaySec * 2, 30)
            end
        end

        if onDone then onDone(false, attempt) end
    end)
end

sendDiscordReport = function(forceNow)
    if not DISCORD_ENABLED or not DISCORD_WEBHOOK_URL or discordState.sending then return end

    local currentTime = tick()
    local interval = INTERVAL_OPTIONS[intervalIndex]
    if not forceNow and currentTime - lastDiscordReport < interval then return end
    lastDiscordReport = currentTime

    discordState.sending = true
    refreshStatusLabel()

    local active, fieldBlooms = 0, 0
    for _, data in pairs(activeBlooms) do
        active = active + 1
        if data.lastFieldName then fieldBlooms = fieldBlooms + 1 end
    end

    local payload = buildReportPayload()

    sendToDiscordWithRetry(payload, function(success, attempts)
        discordState.sending = false
        if success then
            discordState.lastSuccessTime = os.time()
            discordState.consecutiveFailures = 0
            discordState.totalSent = discordState.totalSent + 1
            print(string.format("[BloomTracker] ✓ Discord report sent (attempt %d) — Active %d | Spawned %d | Destroyed %d",
                attempts, active, bloomStats.total_spawned, bloomStats.total_destroyed))
        else
            discordState.lastFailTime = os.time()
            discordState.consecutiveFailures = discordState.consecutiveFailures + 1
            discordState.totalFailed = discordState.totalFailed + 1
            warn(string.format("[BloomTracker] ✗ Discord report FAILED after %d attempts — data still tracked locally, will retry next interval", attempts))
        end
        refreshStatusLabel()
    end)
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
        recordSpawn(fieldName)
        if DEBUG_MODE then print("[BloomTracker] ✓ " .. bloom.Name .. " → " .. fieldName .. " @ " .. fmtVec(pos)) end
    else
        bloomStats.no_field_assigned = bloomStats.no_field_assigned + 1
        recordSpawn(nil)
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

    local lastStatusRefresh = 0
    local lastPrune = 0
    RunService.Heartbeat:Connect(function()
        updateBloomPositions()
        sendDiscordReport()

        local now = tick()
        if now - lastStatusRefresh >= 1 then -- refresh "Xs ago" text once a second
            lastStatusRefresh = now
            refreshStatusLabel()
        end
        if now - lastPrune >= 60 then -- prune old spawn history once a minute
            lastPrune = now
            pruneSpawnHistory()
        end
    end)

    refreshDiscordToggleUI()
    refreshStatusLabel()
    updateUIStats()
    print("[BloomTracker] ✓ v2.0 initialized — tracking " .. tostring(#fieldParts) .. " fields")

    if DISCORD_ENABLED then
        task.delay(2, function() sendDiscordReport(true) end) -- fire an immediate confirmation report on startup
    end
end

-- Intro animation
mainFrame.Size = UDim2.new(0, 400, 0, 0)
mainFrame.Position = UDim2.new(0, 20, 0, 20)
tween(mainFrame, {Size = expandedSize}, 0.35, Enum.EasingStyle.Back):Play()

init()
