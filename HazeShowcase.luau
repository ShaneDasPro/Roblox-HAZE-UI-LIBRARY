-- Haze UI Library - compact all-features showcase
local Haze = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ShaneDasPro/Roblox-HAZE-UI-LIBRARY/main/HazeUILibrary.luau"
))()

Haze.ToggleKey = Enum.KeyCode.RightShift

local Window = Haze:CreateWindow({
    Title = "Haze Showcase",
    Size = UDim2.fromOffset(760, 520),
    Accent = Color3.fromRGB(0, 229, 255),
})

local ControlsTab = Window:CreateTab({ Name = "Controls", Icon = "◆" })
local Controls = ControlsTab:CreateSection("All Controls")

local InfoLabel = Controls:CreateLabel(
    "Every public Haze control is shown below. Press RightShift to toggle the UI."
)

Controls:CreateButton({
    Name = "Show Notification",
    Callback = function()
        Haze:Notify({
            Title = "Haze Showcase",
            Text = "Button and notification callbacks work!",
            Duration = 3,
        })
    end,
})

local Toggle = Controls:CreateToggle({
    Name = "Example Toggle",
    Default = true,
    Callback = function(value)
        print("Toggle:", value)
    end,
})

local Slider = Controls:CreateSlider({
    Name = "Example Slider",
    Min = 0,
    Max = 100,
    Default = 50,
    Step = 5,
    Callback = function(value)
        print("Slider:", value)
    end,
})

local Dropdown = Controls:CreateDropdown({
    Name = "Single Dropdown",
    Options = { "Alpha", "Beta", "Gamma" },
    Multi = false,
    Callback = function(value)
        print("Selected:", value)
    end,
})

local MultiDropdown = Controls:CreateDropdown({
    Name = "Multi Dropdown",
    Options = { "ESP", "Movement", "Visuals" },
    Multi = true,
    Callback = function(values)
        print("Selected:", table.concat(values, ", "))
    end,
})

local Textbox = Controls:CreateTextbox({
    Name = "Textbox",
    Default = "",
    Placeholder = "Type something...",
    Callback = function(text, enterPressed)
        print("Textbox:", text, "Enter:", enterPressed)
    end,
})

local Keybind = Controls:CreateKeybind({
    Name = "Example Keybind",
    Default = Enum.KeyCode.Q,
    Callback = function(key)
        print("Keybind pressed:", key.Name)
    end,
})

local ColorPicker = Controls:CreateColorPicker({
    Name = "Color Picker",
    Default = Color3.fromRGB(255, 46, 151),
    Callback = function(color)
        print("Color:", color)
    end,
})

local ApiTab = Window:CreateTab({ Name = "API Demo", Icon = "⚙" })
local Api = ApiTab:CreateSection("Controller Methods")

Api:CreateButton({
    Name = "Run Set / Get Demo",
    Callback = function()
        Toggle:Set(not Toggle:Get())
        Slider:Set(Slider:Get() >= 100 and 0 or Slider:Get() + 10)
        Dropdown:SetOptions({ "Delta", "Echo", "Foxtrot" })
        Dropdown:Set("Delta")
        MultiDropdown:Set({ "ESP", "Visuals" })
        Textbox:Set("Hello Haze!")
        Keybind:Set(Enum.KeyCode.E)
        ColorPicker:Set(Color3.fromHSV(math.random(), 0.85, 1))
        InfoLabel:Set("Controller API updated every control successfully.")

        print("Label:", InfoLabel:Get())
        print("Toggle:", Toggle:Get(), "Slider:", Slider:Get())
        print("Dropdown:", Dropdown:Get())
        print("Multi:", table.concat(MultiDropdown:Get(), ", "))
        print("Textbox:", Textbox:Get(), "Keybind:", Keybind:Get().Name)
        print("Color:", ColorPicker:Get())

        Haze:Notify({
            Title = "Controller Demo",
            Text = "Set, Get and SetOptions were demonstrated. Check the console too.",
            Duration = 4,
        })
    end,
})

Api:CreateButton({
    Name = "Focus Textbox",
    Callback = function()
        Textbox:Focus()
    end,
})

Api:CreateButton({
    Name = "Hide for 2 Seconds",
    Callback = function()
        Window:SetVisible(false)
        task.delay(2, function()
            Haze:SetVisible(true)
        end)
    end,
})

Api:CreateLabel("Close and Destroy both play the closing animation and clean up the window.")

Api:CreateButton({
    Name = "Close Window",
    Callback = function()
        Window:Close()
    end,
})

Api:CreateButton({
    Name = "Destroy Window",
    Callback = function()
        Window:Destroy()
    end,
})
