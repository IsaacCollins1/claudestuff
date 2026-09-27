--!strict
-- A big double-sided leaderboard sign (top 10 with avatar headshots).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Build = require(ReplicatedStorage.Shared.Build)

local LeaderboardBuilder = {}

LeaderboardBuilder.Rows = 10

export type Row = {
	Frame: Frame,
	Rank: TextLabel,
	Avatar: ImageLabel,
	Name: TextLabel,
	Value: TextLabel,
}

export type Board = {
	Model: Model,
	Faces: { { Rows: { Row }, Footer: TextLabel } },
}

local DARK = Color3.fromRGB(28, 30, 46)
local WHITE = Color3.fromRGB(255, 255, 255)
local MEDALS = { Color3.fromRGB(255, 205, 50), Color3.fromRGB(210, 215, 230), Color3.fromRGB(225, 150, 90) }

local function face(part: BasePart, normal: Enum.NormalId, title: string, icon: string, color: Color3): { Rows: { Row }, Footer: TextLabel }
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board" .. normal.Name
	gui.Face = normal
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 36
	gui.Parent = part

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = DARK
	background.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 175, 200))
	gradient.Rotation = 90
	gradient.Parent = background

	local header = Instance.new("Frame")
	header.Size = UDim2.fromScale(1, 0.16)
	header.BackgroundColor3 = color
	header.Parent = background
	local titleLabel = Build.textLabel(header, `{icon} {title}`, WHITE)
	titleLabel.Font = Enum.Font.LuckiestGuy
	titleLabel.Size = UDim2.fromScale(0.94, 0.8)
	titleLabel.Position = UDim2.fromScale(0.03, 0.1)
	Build.stroke(titleLabel, color:Lerp(Color3.new(0, 0, 0), 0.5), 4)

	local rows: { Row } = {}
	local rowHeight = 0.074
	for index = 1, LeaderboardBuilder.Rows do
		local row = Instance.new("Frame")
		row.Name = "Row" .. index
		row.Size = UDim2.fromScale(0.94, rowHeight * 0.88)
		row.Position = UDim2.fromScale(0.03, 0.18 + (index - 1) * rowHeight)
		row.BackgroundColor3 = if index % 2 == 0 then Color3.fromRGB(46, 49, 72) else Color3.fromRGB(58, 62, 90)
		row.Parent = background
		Build.corner(row, UDim.new(0.3, 0))

		local rank = Build.textLabel(row, "#" .. index, if index <= 3 then MEDALS[index] else WHITE)
		rank.Font = Enum.Font.LuckiestGuy
		rank.Size = UDim2.fromScale(0.12, 0.8)
		rank.Position = UDim2.fromScale(0.01, 0.1)

		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.BackgroundColor3 = Color3.fromRGB(90, 95, 130)
		avatar.Size = UDim2.fromScale(0.075, 0.86)
		avatar.Position = UDim2.fromScale(0.14, 0.07)
		avatar.Image = ""
		avatar.Parent = row
		Build.corner(avatar, UDim.new(0.5, 0))

		local name = Build.textLabel(row, "—", WHITE)
		name.Size = UDim2.fromScale(0.46, 0.7)
		name.Position = UDim2.fromScale(0.235, 0.15)
		name.TextXAlignment = Enum.TextXAlignment.Left

		local value = Build.textLabel(row, "", Color3.fromRGB(120, 255, 140))
		value.Font = Enum.Font.LuckiestGuy
		value.Size = UDim2.fromScale(0.28, 0.7)
		value.Position = UDim2.fromScale(0.7, 0.15)
		value.TextXAlignment = Enum.TextXAlignment.Right
		Build.stroke(value, DARK, 2)

		rows[index] = { Frame = row, Rank = rank, Avatar = avatar, Name = name, Value = value }
	end

	local footer = Build.textLabel(background, "Updating…", Color3.fromRGB(190, 195, 220))
	footer.Size = UDim2.fromScale(0.9, 0.05)
	footer.Position = UDim2.fromScale(0.05, 0.935)
	return { Rows = rows, Footer = footer }
end

-- Board centred at `cframe` (bottom of the posts), readable from both sides.
function LeaderboardBuilder.build(parent: Instance, cframe: CFrame, title: string, icon: string, color: Color3): Board
	local model = Instance.new("Model")
	model.Name = "Leaderboard"
	local width, height = 22, 15
	local postColor = Color3.fromRGB(60, 64, 80)
	for _, x in { -width / 2 + 1, width / 2 - 1 } do
		Build.part(model, "Post", Vector3.new(1, 5, 1), cframe * CFrame.new(x, 2.5, 0), postColor)
	end
	local frame = Build.part(model, "Frame", Vector3.new(width + 1, height + 1, 1.2), cframe * CFrame.new(0, 5 + height / 2, 0), color)
	frame.CastShadow = false
	local board = Build.part(model, "Board", Vector3.new(width, height, 1.4), cframe * CFrame.new(0, 5 + height / 2, 0), DARK)
	local topper = Build.part(model, "Topper", Vector3.new(6, 3, 1.6), cframe * CFrame.new(0, 5 + height + 1.2, 0), color)
	Build.surfaceText(topper, Enum.NormalId.Front, icon, WHITE)
	Build.surfaceText(topper, Enum.NormalId.Back, icon, WHITE)
	local faces = {
		face(board, Enum.NormalId.Front, title, icon, color),
		face(board, Enum.NormalId.Back, title, icon, color),
	}
	model.Parent = parent
	return { Model = model, Faces = faces }
end

return LeaderboardBuilder
