--!strict
-- Frees the mouse while any menu panel is open (Nov 6 2026). In first person Roblox locks the
-- mouse to the centre to steer the camera, so menus could not be clicked. A visible GuiButton
-- with Modal = true asks the PlayerModule to release the mouse, and a render step after the
-- camera forces it free as well; closing every panel hands the mouse back to the camera. Panels are found by name so the menu modules stay unaware.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local BIND = "PopcornMenuCursor"
local MenuCursor = {}

-- Every centre panel that should free the mouse while Visible.
MenuCursor.PANELS = { "ShopPanel", "UpgradesPanel", "InventoryPanel", "AdminPanel" }

function MenuCursor.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "PopcornMenuCursor", false, -100
	local unlock = Instance.new("TextButton")
	unlock.Name, unlock.Text, unlock.BackgroundTransparency = "ModalUnlock", "", 1
	unlock.Size, unlock.Selectable, unlock.Active = UDim2.fromOffset(1, 1), false, false
	unlock.Modal, unlock.Visible = true, false
	unlock.Parent = gui
	gui.Parent = playerGui

	local names: { [string]: boolean } = {}
	for _, name in MenuCursor.PANELS do names[name] = true end
	local open: { [GuiObject]: boolean } = {}
	local freed = false
	local function refresh()
		local want = next(open) ~= nil
		unlock.Visible = want
		if want == freed then return end
		freed = want
		if want then
			-- The camera scripts re-lock the mouse every frame in first person, so release it
			-- again right after they run.
			RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function()
				Input.MouseBehavior = Enum.MouseBehavior.Default
				Input.MouseIconEnabled = true
			end)
		else
			RunService:UnbindFromRenderStep(BIND)
		end
	end
	local function watch(panel: Instance)
		if not panel:IsA("GuiObject") or not names[panel.Name] then return end
		local object = panel :: GuiObject
		local function update()
			open[object] = (object.Visible and object:IsDescendantOf(playerGui)) or nil
			refresh()
		end
		object:GetPropertyChangedSignal("Visible"):Connect(update)
		object.AncestryChanged:Connect(update)
		update()
	end
	for _, d in playerGui:GetDescendants() do watch(d) end
	playerGui.DescendantAdded:Connect(watch)
end

return MenuCursor
