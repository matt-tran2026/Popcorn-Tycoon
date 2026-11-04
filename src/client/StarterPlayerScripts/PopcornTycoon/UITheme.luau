--!strict
return {
	Gold = Color3.fromRGB(244, 197, 66), Cream = Color3.fromRGB(255, 240, 209),
	Brown = Color3.fromRGB(68, 49, 38), Dark = Color3.fromRGB(38, 29, 23),
	Red = Color3.fromRGB(217, 76, 58), Green = Color3.fromRGB(74, 154, 88),
	Muted = Color3.fromRGB(163, 148, 124),
	CornIcon = "rbxassetid://99795210689047", PopcornIcon = "rbxassetid://101313976457910", -- ForgeGUI asset publication tracked in assets/ui/manifest.json.
	-- HUD art (Nov 3 2026): source PNGs in assets/ui/hud, ids recorded in assets/ui/manifest.json.
	Font = Enum.Font.FredokaOne,
	Hud = {
		Popcorn = "rbxassetid://80917126698468", Cash = "rbxassetid://132039463006444",
		Index = "rbxassetid://94122681293200", Settings = "rbxassetid://135211638465712", Rebirth = "rbxassetid://95432742957662",
		Shop = "rbxassetid://127043114998171", Quests = "rbxassetid://133951945676679", Upgrades = "rbxassetid://75064606374733",
		-- Menu art: the outlined shop bag for the panel header and a tintable stud tile.
		ShopBag = "rbxassetid://110102567004174", Studs = "rbxassetid://97083921962489",
	} :: { [string]: string },
	-- Brick colours shared by the HUD tiles and menus (top face, rim).
	Brick = {
		Green = Color3.fromRGB(54, 196, 67), GreenRim = Color3.fromRGB(30, 138, 41),
		Yellow = Color3.fromRGB(246, 193, 31), YellowRim = Color3.fromRGB(207, 138, 10),
		Red = Color3.fromRGB(236, 52, 64), RedRim = Color3.fromRGB(174, 26, 38),
		Blue = Color3.fromRGB(31, 127, 234), BlueRim = Color3.fromRGB(20, 80, 184),
		Grey = Color3.fromRGB(138, 143, 152), GreyRim = Color3.fromRGB(92, 96, 104),
	},
}
