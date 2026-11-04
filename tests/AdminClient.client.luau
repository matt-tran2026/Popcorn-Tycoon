--!strict
-- Temporary client LocalScript runner during Play (Owner Developer Panel, Nov 4 2026): the real
-- network path. Install in Edit mode with the Studio MCP multi_edit tool at
-- StarterPlayer.StarterPlayerScripts.PopcornTestRunners.AdminClient (className LocalScript),
-- start Play, read this script's Results attribute from the Client DataModel, stop Play and
-- delete the folder. The MCP Luau sandbox itself cannot invoke remotes (no Network capability).
-- Checks the panel exists for the Owner, that commands sent over AdminRequest change the
-- replicated balances and the normal HUD, that replays and malformed numbers are refused over
-- the wire, and the panel's amount parser. Leaves balances at zero.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("PopcornTycoon")
local remote = Shared:WaitForChild("Remotes"):WaitForChild("AdminRequest", 30) :: RemoteFunction
local checks: { { name: string, passed: boolean } } = {}
local function check(name: string, condition: boolean)
	table.insert(checks, { name = name, passed = condition })
	assert(condition, name)
end
local id = 5 * 10 ^ 8 -- above the panel's own request ids
local function send(command: string, args: { [string]: any }?): any
	task.wait(0.25)
	id += 1
	return remote:InvokeServer(id, command, args)
end
-- True once some HUD TextLabel shows `text` (balances count up, so allow a moment).
local function hudShows(text: string): boolean
	local gui = player:WaitForChild("PlayerGui")
	local until_ = os.clock() + 4
	while os.clock() < until_ do
		for _, name in { "PopcornHUD", "PopcornHUDTop" } do
			local hud = gui:FindFirstChild(name)
			if hud then
				for _, label in hud:GetDescendants() do
					if label:IsA("TextLabel") and label.Text == text then return true end
				end
			end
		end
		task.wait(0.2)
	end
	return false
end

local ok, err = pcall(function()
	task.wait(4) -- let the farm, HUD and panel handshake finish
	local gui = player:WaitForChild("PlayerGui")
	local panel = gui:FindFirstChild("PopcornAdmin")
	check("the Owner gets the Developer Panel UI", panel ~= nil and panel:FindFirstChild("AdminPanel") ~= nil)
	local hello = send("hello")
	check("hello over the network returns the Owner's snapshot", hello.ok and hello.state.userId == player.UserId)
	check("the snapshot lists the implemented tools", typeof(hello.state.tools) == "table" and hello.state.tools[1].id == "Sickle")
	send("cash.set", { amount = 0 })
	local given = send("cash.add", { amount = 1e6 })
	task.wait(0.3)
	check("give $1M over the network updates the Cash attribute", given.ok and player:GetAttribute("Cash") == 1e6)
	check("the normal HUD shows $1M", hudShows("$1M"))
	local replay = remote:InvokeServer(id, "cash.add", { amount = 1e6 })
	check("a replayed request over the network is refused", not replay.ok and player:GetAttribute("Cash") == 1e6)
	check("NaN over the network is refused", not send("cash.add", { amount = 0 / 0 }).ok)
	check("infinity over the network is refused", not send("cash.add", { amount = math.huge }).ok)
	check("a negative amount over the network is refused", not send("cash.add", { amount = -100 }).ok and player:GetAttribute("Cash") == 1e6)
	check("give popcorn over the network", send("popcorn.add", { amount = 250 }).ok and player:GetAttribute("Popcorn") == 250)
	check("the HUD popcorn bucket shows 250", hudShows("250"))
	check("fill the bag over the network", send("corn.fill", { cropId = "Normal" }).ok and player:GetAttribute("RawCorn") == player:GetAttribute("BagCapacity"))
	check("the HUD bag meter shows full", hudShows(tostring(player:GetAttribute("RawCorn")) .. "/" .. tostring(player:GetAttribute("BagCapacity"))))
	local upgraded = send("upgrade.max", { upgradeId = "Backpack" })
	check("max Backpack over the network updates BagCapacity", upgraded.ok and player:GetAttribute("BagCapacity") == 800 and player:GetAttribute("Upgrade_Backpack") == 4)
	-- The panel's amount parser (client convenience; the server re-validates everything).
	local Controller = require(player:WaitForChild("PlayerScripts"):WaitForChild("PopcornTycoon"):WaitForChild("AdminController")) :: any
	local parse = Controller.parseAmount
	check("amount parser", parse("1500") == 1500 and parse("1,500") == 1500 and parse("$2.5K") == 2500 and parse("1m") == 1e6
		and parse("1B") == 1e9 and parse("1e6") == 1e6 and parse("abc") == nil and parse("") == nil)
	-- Clean up.
	send("upgrade.reset", { upgradeId = "Backpack" })
	send("corn.empty")
	send("popcorn.set", { amount = 0 })
	send("cash.set", { amount = 0 })
	task.wait(0.3)
	check("cleanup", player:GetAttribute("Cash") == 0 and player:GetAttribute("Popcorn") == 0 and player:GetAttribute("RawCorn") == 0)
end)
script:SetAttribute("Results", Http:JSONEncode({ passed = ok, error = if ok then nil else tostring(err), checks = checks }))
print("[AdminClient tests] " .. (if ok then "PASS " else "FAIL ") .. tostring(#checks) .. " checks" .. (if ok then "" else ": " .. tostring(err)))
