# 🌸 Bloom Tracker

A real-time bloom tracking system for Roblox games with live UI dashboard. Automatically detects and tracks blooms spawning in your game, assigns them to fields, and displays statistics.

## Features

✨ **Live UI Dashboard**
- Real-time bloom tracking with visual indicators
- Active bloom count, spawn statistics, and field assignments
- Live bloom list with color-coded status
- Auto-updating metrics

🎯 **Smart Field Detection**
- Automatically assigns blooms to fields based on position
- Supports both bounding box and radius-based detection
- Visual indicator for blooms without field assignment

🔄 **Continuous Monitoring**
- Tracks bloom position changes
- Detects when blooms move between fields
- Records bloom destruction events

## Installation

### Method 1: Loadstring (Easiest)

In Roblox Studio or a script executor, run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Xan3vo/bloomdata/main/main.lua"))()
```

### Method 2: Manual Script

1. Place `main.lua` in **StarterPlayer > StarterPlayerScripts** as a **LocalScript**
2. Run the game

## Usage

The UI will automatically appear in the top-left corner of the screen showing:

- **Spawned**: Total blooms that have spawned
- **Active**: Currently active blooms in the game
- **Destroyed**: Blooms that have been destroyed/popped
- **Assigned**: Blooms successfully assigned to a field

### Understanding the Bloom List

- **Green Border**: Bloom is in a recognized field
- **Yellow Border**: Bloom spawned but no field was assigned

## Configuration

Edit these values in the script to customize behavior:

```lua
local POSITION_CHECK_THRESHOLD = 2    -- Distance bloom must move to check field (studs)
local CHECK_INTERVAL = 0.5            -- How often to check positions (seconds)
local FIELDS_FOLDER_NAME = "Fields"   -- Name of your fields folder
local POPPABLE_FOLDER_NAME = "PoppablePlants" -- Name of your blooms folder
```

## How It Works

1. **Initialization**: Scans workspace for PoppablePlants folder and caches all fields
2. **Bloom Detection**: Uses name matching (`"bloom"`) and `IsBloom` attribute to identify blooms
3. **Field Assignment**: Uses bounding box or position-based detection to assign fields
4. **Real-time Tracking**: Monitors bloom positions and updates field assignments as they move
5. **UI Updates**: Live dashboard reflects all changes in real-time

## Troubleshooting

### All blooms show "NO FIELD"

The field detection might not be finding your fields. Check:
- Field folder name (default: "Fields")
- Field objects are Models
- Fields have proper position/pivot data

### UI doesn't appear

- Make sure you're running a **LocalScript** in StarterPlayer > StarterPlayerScripts
- Check that your player character loaded
- Try running the loadstring in a different game first to test

### Performance issues with many blooms

The tracker is optimized for 100+ blooms. If performance is slow:
- Increase `CHECK_INTERVAL` (e.g., 1.0 instead of 0.5)
- Increase `POSITION_CHECK_THRESHOLD` to reduce field recalculations
- Check for memory leaks by monitoring active bloom count

## Technical Details

- **Detection Method**: Bloom name pattern + optional IsBloom attribute
- **Field Matching**: Bounding box (fast) + radius fallback (accurate)
- **Update Rate**: Heartbeat-based with configurable intervals
- **Memory**: Minimal impact, auto-cleans destroyed blooms
- **No External Dependencies**: Pure Lua, works with default Roblox services

## License

Free to use and modify.

---

**Questions?** Check the debug console (F9 in Roblox Studio) for diagnostic messages.
