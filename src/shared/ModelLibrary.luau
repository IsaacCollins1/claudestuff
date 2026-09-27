--!strict
-- Drop-in 3D models.
--
-- Everything in the game is built from Parts, so it works straight away. To
-- use real meshes instead (from the Creator Store / Toolbox, or your own
-- Blender models brought in with Studio's 3D Importer), put them here:
--
--   ReplicatedStorage
--   └─ CustomModels
--      ├─ Products   one Model per product, named by product id: "Cola", "Laptop", ...
--      └─ Props      "DeliveryVan", "Car", "Forklift", "Tree"
--
-- A custom model is cloned, scaled to fit the space the Part version uses,
-- stood on the ground and turned to match its pivot. Make the model's pivot
-- face forward (the front of the model looking along the pivot's -Z).
-- Anything not found falls back to the built-in Part version.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelLibrary = {}

ModelLibrary.FolderName = "CustomModels"

function ModelLibrary.template(category: string, name: string): Model?
	local root = ReplicatedStorage:FindFirstChild(ModelLibrary.FolderName)
	local folder = root and root:FindFirstChild(category)
	local found = folder and folder:FindFirstChild(name)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

-- Settings for purely visual parts: anchored, no collisions, no raycasts.
function ModelLibrary.makeDecor(model: Model, castShadow: boolean?)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.CastShadow = castShadow == true
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			-- Free models sometimes carry scripts; never run them.
			descendant:Destroy()
		end
	end
end

-- Clone `template`, scale it to fit inside `fit` (studs, in the model's own
-- axes) and move it so the middle of its base sits at `at` (default origin).
function ModelLibrary.fitted(template: Model, fit: Vector3, at: CFrame?): Model
	local model = template:Clone()
	local pivot = model:GetPivot()
	local _, size = model:GetBoundingBox()
	local scale = math.min(fit.X / math.max(size.X, 0.01), fit.Y / math.max(size.Y, 0.01), fit.Z / math.max(size.Z, 0.01))
	if scale > 0 and scale < math.huge and math.abs(scale - 1) > 1e-3 then
		model:ScaleTo(model:GetScale() * scale)
	end
	local box, newSize = model:GetBoundingBox()
	local base = box.Position - pivot.UpVector * (newSize.Y / 2)
	model.WorldPivot = CFrame.new(base) * pivot.Rotation
	model:PivotTo(at or CFrame.new())
	return model
end

-- Build a prop: the custom model if there is one, otherwise `fallback()`.
function ModelLibrary.prop(name: string, fit: Vector3, cframe: CFrame, fallback: () -> Model): Model
	local template = ModelLibrary.template("Props", name)
	if template then
		local ok, result = pcall(ModelLibrary.fitted, template, fit, cframe)
		if ok then
			result.Name = name
			ModelLibrary.makeDecor(result, true)
			return result
		end
		warn(`[FillTheStore] Couldn't use CustomModels.Props.{name}: {result}`)
	end
	return fallback()
end

return ModelLibrary
