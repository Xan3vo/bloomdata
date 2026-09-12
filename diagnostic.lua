-- Bloom Tracker DIAGNOSTIC - Debug Only
print("\n[BloomTracker] ===== DIAGNOSTIC START =====")

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

print("[BloomTracker] Script loaded successfully!")
print("[BloomTracker] Looking for PoppablePlants and Fields folders...")

-- Check workspace
print("\n[BloomTracker] WORKSPACE CONTENTS:")
for _, child in ipairs(Workspace:GetChildren()) do
    print("[BloomTracker]   - " .. child.Name .. " (" .. child.ClassName .. ")")
end

-- Look for PoppablePlants
print("\n[BloomTracker] Looking for PoppablePlants...")
local poppable = Workspace:FindFirstChild("PoppablePlants")
if poppable then
    print("[BloomTracker] ✓ FOUND PoppablePlants at: " .. poppable:GetFullName())
    print("[BloomTracker]   Contents:")
    for _, child in ipairs(poppable:GetChildren()) do
        print("[BloomTracker]     - " .. child.Name .. " (" .. child.ClassName .. ")")
    end
else
    print("[BloomTracker] ✗ PoppablePlants NOT FOUND")
    -- Check Happenings folder
    local happenings = Workspace:FindFirstChild("Happenings")
    if happenings then
        print("[BloomTracker] Found Happenings folder, checking inside:")
        for _, child in ipairs(happenings:GetChildren()) do
            print("[BloomTracker]   - " .. child.Name .. " (" .. child.ClassName .. ")")
        end
    end
end

-- Look for Fields
print("\n[BloomTracker] Looking for Fields...")
local fields = Workspace:FindFirstChild("Fields") or Workspace:FindFirstChild("FlowerZones")
if fields then
    print("[BloomTracker] ✓ FOUND Fields at: " .. fields:GetFullName())
    print("[BloomTracker]   Contents:")
    for _, child in ipairs(fields:GetChildren()) do
        print("[BloomTracker]     - " .. child.Name .. " (" .. child.ClassName .. ")")
        if child:IsA("Model") then
            local ok, bbox, size = pcall(function() return child:GetBoundingBox() end)
            if ok and bbox then
                print("[BloomTracker]       → Has bounding box")
            else
                print("[BloomTracker]       → No bounding box")
            end
        end
    end
else
    print("[BloomTracker] ✗ Fields NOT FOUND")
    print("[BloomTracker] Searching entire workspace for 'Fields' or 'FlowerZones'...")
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc.Name == "Fields" or desc.Name == "FlowerZones" then
            print("[BloomTracker]   Found at: " .. desc:GetFullName())
        end
    end
end

-- Check for existing blooms
print("\n[BloomTracker] Looking for existing blooms...")
if poppable then
    local bloomCount = 0
    for _, desc in ipairs(poppable:GetDescendants()) do
        if desc.Name:lower():find("bloom") or (desc.GetAttribute and desc:GetAttribute("IsBloom")) then
            bloomCount = bloomCount + 1
            print("[BloomTracker]   ✓ Found bloom: " .. desc:GetFullName())
        end
    end
    print("[BloomTracker] Total blooms found: " .. bloomCount)
end

print("\n[BloomTracker] ===== DIAGNOSTIC END =====\n")
