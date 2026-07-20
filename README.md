# Haze UI Library

A polished holographic UI library for Roblox, written in Luau. Haze combines a readable dark interface with cyan/magenta neon accents, animated controls, a cinematic intro, notifications, and a complete controller API.

The included showcase demonstrates the full interface: sidebar navigation, labels, buttons, toggles, sliders, dropdowns, textboxes, keybinds, color pickers, notifications, and runtime `Set`/`Get` methods.

> [!NOTE]
> Haze is intended for client-side interfaces in experiences you own or are authorized to modify ;)

## Features

- Readable cyberpunk glass theme with bright primary and secondary text
- Animated cyan/magenta border, glow, hover, ripple, and page transitions
- Cinematic startup sequence
- Draggable windows with close and hide controls
- Tabs and automatically sized sections
- Buttons, toggles, sliders, dropdowns, textboxes, keybinds, color pickers, and labels
- Single- and multi-select dropdown support
- Animated notification system
- Mouse and touch input support
- Global visibility toggle with `RightShift`
- Configurable accent color and window size
- Controller methods for updating controls after creation
- No external image assets required by the library
- Executor-aware GUI parenting with a `PlayerGui` compatibility fallback

## Installation

### Remote loader

```luau
local Haze = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ShaneDasPro/Roblox-HAZE-UI-LIBRARY/main/HazeUILibrary.luau"
))()
```

`loadstring` and `game:HttpGet` are not available to ordinary Roblox LocalScripts. When working in Roblox Studio, use the ModuleScript setup below instead.

> [!TIP]
> The URL above follows the latest commit on `main`. For a production project, pin the URL to a reviewed commit so upstream changes cannot alter your interface unexpectedly.

### Roblox Studio ModuleScript

1. Create a `ModuleScript` named `HazeUILibrary`.
2. Paste the contents of [`HazeUILibrary.luau`](./HazeUILibrary.luau) into it.
3. Require it from a client-side `LocalScript`:

```luau
local Haze = require(script.Parent.HazeUILibrary)
```

## Quick Start

```luau
local Haze = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ShaneDasPro/Roblox-HAZE-UI-LIBRARY/main/HazeUILibrary.luau"
))()

local Window = Haze:CreateWindow({
    Title = "Haze Control Deck",
    Size = UDim2.fromOffset(760, 520),
    Accent = Color3.fromRGB(0, 229, 255),
})

local MainTab = Window:CreateTab({
    Name = "Main",
    Icon = "◆",
})

local Controls = MainTab:CreateSection("Controls")

Controls:CreateLabel("Haze is online and ready.")

Controls:CreateButton({
    Name = "Show Notification",
    Callback = function()
        Haze:Notify({
            Title = "Haze",
            Text = "Everything is working!",
            Duration = 3,
        })
    end,
})

local Enabled = Controls:CreateToggle({
    Name = "Example Toggle",
    Default = true,
    Callback = function(value)
        print("Enabled:", value)
    end,
})

local Amount = Controls:CreateSlider({
    Name = "Example Slider",
    Min = 0,
    Max = 100,
    Default = 50,
    Step = 5,
    Callback = function(value)
        print("Amount:", value)
    end,
})

-- Controllers can be updated later.
Enabled:Set(false)
Amount:Set(75)
```

The library reserves `RightShift` as its global show/hide key:

```luau
Haze.ToggleKey = Enum.KeyCode.RightShift
```

## Run the Showcase

The showcase creates every public control and demonstrates the returned controller methods:

```luau
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ShaneDasPro/Roblox-HAZE-UI-LIBRARY/main/HazeShowcase.luau"
))()
```

You can also inspect [`HazeShowcase.luau`](./HazeShowcase.luau) for a compact all-features example.

> [!IMPORTANT]
> `HazeShowcase.luau` downloads the library from GitHub. Local edits to `HazeUILibrary.luau` will not appear in the showcase until the updated library is pushed, or the showcase is changed to load your local ModuleScript.

## API Reference

### Library

| Method or property | Description |
| --- | --- |
| `Haze:CreateWindow(config)` | Creates and returns a window. |
| `Haze:Notify(config)` | Displays an animated notification. |
| `Haze:SetVisible(visible)` | Shows or hides all Haze windows, notifications, and the active intro. |
| `Haze.ToggleKey` | Global UI toggle key. Defaults to `Enum.KeyCode.RightShift`. |

### Window

| Method | Description |
| --- | --- |
| `Window:CreateTab(config)` | Creates and returns a tab. |
| `Window:SetVisible(visible)` | Shows or hides this window. |
| `Window:Close()` | Plays the close animation and cleans up the window. |
| `Window:Destroy()` | Alias for `Window:Close()`. |

### Tab and Section

| Method | Description |
| --- | --- |
| `Tab:CreateSection(name)` | Creates and returns an automatically sized section. |
| `Section:CreateLabel(text)` | Creates text that wraps and resizes vertically. |
| `Section:CreateButton(config)` | Creates an animated button. |
| `Section:CreateToggle(config)` | Creates a boolean toggle. |
| `Section:CreateSlider(config)` | Creates a stepped numeric slider. |
| `Section:CreateDropdown(config)` | Creates a single- or multi-select dropdown. |
| `Section:CreateTextbox(config)` | Creates a single-line textbox. |
| `Section:CreateKeybind(config)` | Creates a keyboard keybind. |
| `Section:CreateColorPicker(config)` | Creates an HSV color picker. |

## Configuration

### Window

```luau
local Window = Haze:CreateWindow({
    Title = "Haze",                       -- string
    Size = UDim2.fromOffset(760, 510),    -- UDim2 or Vector2
    Accent = Color3.fromRGB(0, 229, 255), -- Color3
})
```

The first live window establishes the library-wide accent. Additional windows share that accent until all current windows are closed.

### Notification

```luau
Haze:Notify({
    Title = "Notification",
    Text = "Your message goes here.",
    Duration = 4,
})
```

### Button

```luau
Controls:CreateButton({
    Name = "Launch",
    Callback = function()
        print("Launched")
    end,
})
```

### Toggle

```luau
local Toggle = Controls:CreateToggle({
    Name = "Enabled",
    Default = false,
    Callback = function(value)
        print(value)
    end,
})

Toggle:Set(true)
print(Toggle:Get())
```

### Slider

```luau
local Slider = Controls:CreateSlider({
    Name = "Walk Speed",
    Min = 8,
    Max = 100,
    Default = 16,
    Step = 1,
    Callback = function(value)
        print(value)
    end,
})

Slider:Set(32)
print(Slider:Get())
```

If `Step` is omitted, Haze uses `1` for integer ranges and `0.01` when decimal precision is needed.

### Dropdown

```luau
local Dropdown = Controls:CreateDropdown({
    Name = "Location",
    Options = { "Alpha", "Beta", "Gamma" },
    Multi = false,
    Callback = function(value)
        print(value)
    end,
})

Dropdown:Set("Beta")
Dropdown:SetOptions({ "Delta", "Echo", "Foxtrot" })
print(Dropdown:Get())
```

For a multi-select dropdown, set `Multi = true`. Its callback and `Get()` method return an array of selected options:

```luau
local Modules = Controls:CreateDropdown({
    Name = "Modules",
    Options = { "Movement", "Visuals", "Utility" },
    Multi = true,
    Callback = function(values)
        print(table.concat(values, ", "))
    end,
})

Modules:Set({ "Movement", "Utility" })
```

### Textbox

```luau
local Textbox = Controls:CreateTextbox({
    Name = "Callsign",
    Default = "",
    Placeholder = "Type here...",
    Callback = function(text, enterPressed)
        print(text, enterPressed)
    end,
})

Textbox:Set("Haze")
Textbox:Focus()
print(Textbox:Get())
```

### Keybind

```luau
local Keybind = Controls:CreateKeybind({
    Name = "Ability",
    Default = Enum.KeyCode.Q,
    Callback = function(key)
        print(key.Name)
    end,
})

Keybind:Set(Enum.KeyCode.E)
print(Keybind:Get())
```

`Haze.ToggleKey` is reserved and cannot be assigned to a component keybind. Press `Escape` while capturing a key to clear the binding.

### Color Picker

```luau
local Picker = Controls:CreateColorPicker({
    Name = "Tracer Color",
    Default = Color3.fromRGB(255, 46, 151),
    Callback = function(color)
        print(color)
    end,
})

Picker:Set(Color3.fromRGB(0, 229, 255))
print(Picker:Get())
```

### Label

```luau
local Label = Controls:CreateLabel("Status: Ready")
Label:Set("Status: Running")
print(Label:Get())
```

## Returned Controllers

| Component | Returned methods |
| --- | --- |
| Label | `Set(text)`, `Get()` |
| Toggle | `Set(value)`, `Get()` |
| Slider | `Set(value)`, `Get()` |
| Dropdown | `Set(value)`, `Get()`, `SetOptions(options)` |
| Textbox | `Set(text)`, `Get()`, `Focus()` |
| Keybind | `Set(keyCode)`, `Get()` |
| Color picker | `Set(color)`, `Get()` |

Calling a controller's `Set` method also invokes that component's callback where applicable.

## Theming

Set a custom accent while creating the first window:

```luau
local Window = Haze:CreateWindow({
    Title = "Custom Haze",
    Accent = Color3.fromRGB(125, 90, 255),
})
```

For a complete retheme, edit the `THEME` table near the top of `HazeUILibrary.luau`. It centralizes the main surfaces, text colors, status colors, corner radius, and fonts.

```luau
local THEME = {
    Accent = DEFAULT_ACCENT,
    AccentB = DEFAULT_MAGENTA,
    Background = Color3.fromRGB(16, 22, 38),
    Glass = Color3.fromRGB(28, 36, 58),
    GlassRaised = Color3.fromRGB(45, 57, 86),
    Control = Color3.fromRGB(40, 51, 78),
    Text = Color3.fromRGB(250, 253, 255),
    Muted = Color3.fromRGB(190, 204, 226),
    Dark = Color3.fromRGB(11, 16, 29),
}
```

## Troubleshooting

### The whole window looks black or the text is heavily dimmed

Update to the latest `HazeUILibrary.luau`. Do not attach a `UIGradient` directly to the main `CanvasGroup`: Roblox applies it to the composited group, which multiplies the appearance of every descendant and can look like a translucent black rectangle over the entire UI. Put decorative gradients on a dedicated background `Frame` instead.

### The showcase does not include my local changes

The showcase fetches `HazeUILibrary.luau` from the repository's `main` branch. Push the updated file first, pin the showcase to another raw URL, or use the ModuleScript workflow for local development.

### Nothing appears

- Run Haze from the client, not a server Script.
- In Studio, require the library from a `LocalScript`.
- Confirm the target environment allows the selected GUI parent.
- Check the developer console for callback or permission errors.

### `RightShift` does not toggle the UI

The global shortcut is intentionally suspended while a Haze keybind is capturing keyboard input. It also respects input already processed by Roblox.

## Repository Files

```text
HazeUILibrary.luau  # Main library
HazeShowcase.luau   # Compact all-features showcase
HazeShowcase.lua    # Alternate Lua-named showcase copy
```

## Credits

Created by [$hane / ShaneDasPro](https://github.com/ShaneDasPro).
