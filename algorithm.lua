local enums = require("enums")

local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local algorithm = {}

---@type table<string, Layout>
local layouts = {}
algorithm.layouts = layouts
local function require_layout(layout) 
	layouts[layout] = require("layouts."..layout)
	layouts[#layouts+1] = layouts[layout]
end
require_layout("simple")
require_layout("compact")
require_layout("super_compact")
require_layout("sparse")
require_layout("logistics")
require_layout("compact_logistics")
require_layout("blueprints")

---@class State
---@field delegate string
---@field finished boolean
---@field tick number
---@field surface LuaSurface
---@field player LuaPlayer
---@field resources LuaEntity[] Filtered resources
---@field found_resources LuaEntity[] Found resource types
---@field layout_choice string
---@field direction_choice string
---@field miner_choice string
---@field pole_choice string
---@field belt_choice string Belt name
---@field lamp_choice boolean Lamp placement
---@field coverage_choice boolean
---@field logistics_choice string
---@field landfill_choice boolean
---@field start_choice boolean
---@field deconstruction_choice boolean
---@field pipe_choice string
---@field module_choice string
---@field coords Coords
---@field grid Grid
---@field miner MinerStruct
---@field preview_rectangle nil|uint64 -- LuaRendering.draw_rectangle
---@field blueprint_choice LuaGuiElement
---@field blueprint_inventory LuaInventory
---@field blueprint LuaItemStack
---@field cache EvaluatedBlueprint

---@param event EventData.on_player_selected_area
---@return State|nil
---@return LocalisedString error status
local function create_state(event)
	---@type State
	local state = {}
	state.delegate = "start"
	state.finished = false
	state.tick = 0
	state.preview_rectangle = nil
	
	---@type PlayerData
	local player_data = global.players[event.player_index]

	-- game state properties
	state.surface = event.surface
	state.player = game.players[event.player_index]

	-- player option properties
	local player_choices = player_data.choices
	for k, v in pairs(player_choices) do
		state[k] = util.copy(v)
	end

	if state.layout_choice == "blueprints" then
		if not player_data.choices.blueprint_choice then
			return nil, {"mpp.msg_unselected_blueprint"}
		end
		local blueprint = player_data.choices.blueprint_choice
		-- state.blueprint_inventory = game.create_inventory(1)
		-- state.blueprint = state.blueprint_inventory.find_empty_stack()
		-- state.blueprint.set_stack(blueprint)
		state.cache = player_data.blueprints.cache[blueprint.item_number]
	end

	return state
end

---Filters resource entity list and returns patch coordinates and size
---@param entities LuaEntity[]
---@param available_resource_categories table<string, true>
---@return Coords, LuaEntity[]
---@return table<string, string> @key:resource name; value:resource category
local function process_entities(entities, available_resource_categories)
	local filtered = {}
	local found_resources = {} -- resource.name: resource_category
	local x1, y1 = math.huge, math.huge
	local x2, y2 = -math.huge, -math.huge
	local _, cached_resource_categories = enums.get_available_miners()
	for _, entity in pairs(entities) do
		local category = entity.prototype.resource_category
		found_resources[entity.name] = category
		if cached_resource_categories[category] and available_resource_categories[category] then
			filtered[#filtered+1] = entity
			local x, y = entity.position.x, entity.position.y
			if x < x1 then x1 = x end
			if y < y1 then y1 = y end
			if x2 < x then x2 = x end
			if y2 < y then y2 = y end
		end
	end
	local coords = {
		x1 = x1, y1 = y1, x2 = x2, y2 = y2,
		ix1 = floor(x1), iy1 = floor(y1),
		ix2 = ceil(x2), iy2 = ceil(y2),
		gx = x1 - 1, gy = y1 - 1,
	}
	coords.w, coords.h = coords.ix2 - coords.ix1, coords.iy2 - coords.iy1
	return coords, filtered, found_resources
end

---@param state State
---@param layout Layout
local function get_miner_categories(state, layout)
	if layout.name == "blueprints" then
		return state.cache:get_resource_categories()
	else
		return game.entity_prototypes[state.miner_choice].resource_categories or {}
	end
end

--- Algorithm hook
--- Returns nil if it fails
---@param event EventData.on_player_selected_area
function algorithm.on_player_selected_area(event)
	---@type PlayerData
	local player_data = global.players[event.player_index]
	local state, err = create_state(event)
	if not state then return nil, err end
	local layout = layouts[player_data.choices.layout_choice]

	local layout_categories = get_miner_categories(state, layout)
	local coords, filtered, found_resources = process_entities(event.entities, layout_categories)
	state.coords = coords
	state.resources = filtered
	state.found_resources = found_resources

	if #state.resources == 0 then
		for resource, category in pairs(state.found_resources) do
			if not layout_categories[category] then
				local miner_name = game.entity_prototypes[state.miner_choice].localised_name
				if layout.name == "blueprints" then
					miner_name = {"mpp.choice_none"}
					for k, v in pairs(state.cache.miners) do
						miner_name = game.entity_prototypes[k].localised_name
						break
					end
				end
				local resource_name = game.entity_prototypes[resource].localised_name
				--player.print(("Can't build on this resource patch with selected miner \"%s\" because it can't mine resource \"%s\""):format())
				return nil, {"", {"mpp.msg_miner_err_2_1"}, " \"", miner_name, "\" ", {"mpp.msg_miner_err_2_2"}, " \"", resource_name, "\""}
			end
		end

		return nil, {"mpp.msg_miner_err_0"}
	end

	local validation_result, error = layout:validate(state)
	if validation_result then
		layout:initialize(state)

		-- "Progress" bar
		local c = state.coords
		state.preview_rectangle = rendering.draw_rectangle{
			surface=state.surface,
			left_top={state.coords.ix1, state.coords.iy1},
			right_bottom={state.coords.ix1 + c.w, state.coords.iy1 + c.h},
			filled=false, color={0, 0.8, 0.3, 1},
			width = 8,
			draw_on_ground = true,
			time_to_live = 60*15,
			players={state.player},
		}

		return state
	else
		return nil, error
	end
end

return algorithm
