--!strict
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local player = Players.LocalPlayer
local feedback = Shared:WaitForChild("Remotes"):WaitForChild("HarvestResult") :: RemoteEvent

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "PopcornHUD", false
local panel = Instance.new("TextLabel")
panel.Name = "Inventory"
panel.AnchorPoint, panel.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 12)
panel.Size = UDim2.new(0.9, 0, 0, 88)
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(520, 88)
limit.Parent = panel
panel.BackgroundColor3, panel.BackgroundTransparency = Color3.fromRGB(47, 40, 29), 0.1
panel.TextColor3, panel.Font, panel.TextSize = Color3.fromRGB(255, 231, 155), Enum.Font.GothamMedium, 16
panel.TextWrapped = true
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
gui.Parent = player:WaitForChild("PlayerGui")

local message = "Walk to your corn · Press E or tap Pick corn"
local function render()
	panel.Text = "POPCORN TYCOON  |  Raw corn: " .. tostring(player:GetAttribute("RawCorn") or 0)
		.. "\n" .. message .. "\nPrototype · progress resets when you leave"
end
player:GetAttributeChangedSignal("RawCorn"):Connect(render)
local harvestFlash: Tween? = nil
feedback.OnClientEvent:Connect(function(response)
	message = if response.ok then "+" .. tostring(response.amount) .. " corn · stalk regrowing" else response.reason
	if response.ok then
		if harvestFlash then harvestFlash:Cancel() end
		panel.BackgroundColor3 = Color3.fromRGB(78, 111, 44)
		harvestFlash = TweenService:Create(panel, TweenInfo.new(0.4), { BackgroundColor3 = Color3.fromRGB(47, 40, 29) })
		harvestFlash:Play()
	end
	render()
end)
render()
print("[PopcornTycoon] Client ready.")
