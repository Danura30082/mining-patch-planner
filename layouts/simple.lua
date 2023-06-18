local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max

local common = require("layouts.common")
local base = require("layouts.base")
local grid_mt = require("grid_mt")
local pole_grid_mt = require("pole_grid_mt")
local mpp_util = require("mpp_util")
local builder = require("builder")
local coord_convert, coord_revert = mpp_util.coord_convert, mpp_util.coord_revert
local miner_direction, opposite = mpp_util.miner_direction, mpp_util.opposite

---@class SimpleLayout : Layout
local layout = table.deepcopy(base)

---@class SimpleState : State
---@field debug_dump boolean
---@field saved_attempts PlacementAttempt[]
---@field first_pass any
---@field attempts PlacementCoords[]
---@field attempt_index number
---@field best_attempt PlacementAttempt
---@field best_attempt_score number Heuristic value
---@field best_attempt_index number
---@field resourcs LuaEntity[]
---@field resource_tiles GridTile
---@field longest_belt number For pole alignment information
---@field power_poles_all table
---@field pole_step number
---@field miner_lane_count number Miner lane count
---@field miner_max_column number Miner column span
---@field grid Grid
---@field belts BeltSpecification[]
---@field miner_lanes table<number, MinerPlacement[]>
---@field place_pipes boolean
---@field pipe_layout_specification PlacementSpecification[]
---@field belt_count number For info printout

layout.name = "simple"
layout.translation = {"mpp.settings_layout_choice_simple"}

layout.restrictions.miner_near_radius = {1, 10e3}
layout.restrictions.miner_far_radius = {1, 10e3}
layout.restrictions.pole_omittable = true
layout.restrictions.pole_width = {1, 1}
layout.restrictions.pole_length = {5, 10e3}
layout.restrictions.pole_supply_area = {2.5, 10e3}
layout.restrictions.lamp_available = true
layout.restrictions.coverage_tuning = true
layout.restrictions.module_available = true
layout.restrictions.pipe_available = true
layout.restrictions.placement_info_available = true
layout.restrictions.lane_filling_info_available = true

--[[-----------------------------------

	Basic rundown:
	* Create a virtual grid from resources
	* Run calculations on grid tiles to 
	* _brute_ force several miner layouts on the grid and find the best one
	* Mark the area around for deconstruction
	* Place the entity ghosts and mark built-on tiles
	* Place landfill

--]]-----------------------------------

--- Called from script.on_load
--- ONLY FOR SETMETATABLE USE
---@param self SimpleLayout
---@param state SimpleState
function layout:on_load(state)
	if state.grid then
		setmetatable(state.grid, grid_mt)
	end
end

-- Validate the selection
---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:validate(state)
	local c = state.coords
	-- if (state.direction_choice == "west" or state.direction_choice == "east") then
	-- 	if c.h < 7 then
	-- 		return nil, {"mpp.msg_miner_err_1_w", 7}
	-- 	end
	-- else
	-- 	if c.w < 7 then
	-- 		return nil, {"mpp.msg_miner_err_1_h", 7}
	-- 	end
	-- end
	return base.validate(self, state)
end

---@param self SimpleLayout
---@param state SimpleState
function layout:start(state)
	local grid = {}
	local miner = state.miner
	local c = state.coords

	grid.miner = miner

	local th, tw = c.h, c.w
	if state.direction_choice == "south" or state.direction_choice == "north" then
		th, tw = tw, th
	end
	c.th, c.tw = th, tw

	local x1, x2 = -1-miner.full_size, tw + miner.full_size+1
	for y = -1-miner.full_size, th + miner.full_size+1 do
		local row = {}
		grid[y] = row
		for x = x1, x2 do
			--local tx1, ty1 = conv(c.x1, c.y1, c.tw, c.th)
			row[x] = {
				contains_resource = false,
				resources = 0,
				neighbor_count = 0,
				far_neighbor_count = 0,
				x = x, y = y,
				gx = c.x1 + x, gy = c.y1 + y,
				consumed = false,
				built_on = false,
			}
		end
	end

	--[[ debug rendering - bounds ]]
	rendering.draw_rectangle{
		surface=state.surface,
		left_top={state.coords.ix1, state.coords.iy1},
		right_bottom={state.coords.ix1 + c.tw, state.coords.iy1 + c.th},
		filled=false, width=4, color={0, 0, 1, 1},
		players={state.player},
	}

	rendering.draw_rectangle{
		surface=state.surface,
		left_top={state.coords.ix1-miner.full_size-1, state.coords.iy1-miner.full_size-1},
		right_bottom={state.coords.ix1+state.coords.tw+miner.full_size+1, state.coords.iy1+state.coords.th+miner.full_size+1},
		filled=false, width=4, color={0, 0.5, 1, 1},
		players={state.player},
	}
	--]]

	state.grid = setmetatable(grid, grid_mt)
	return "process_grid"
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:process_grid(state)
	local grid = state.grid
	local DIR = state.direction_choice
	local c = state.coords
	local conv = coord_convert[state.direction_choice]
	local gx, gy = state.coords.gx, state.coords.gy
	local resources = state.resources

	state.resource_tiles = state.resource_tiles or {}
	local resource_tiles = state.resource_tiles

	local convolve_size = state.miner.full_size ^ 2
	local budget, cost = 12000, 0

	local i = state.resource_iter or 1
	while i <= #resources and cost < budget do
		local ent = resources[i]
		local x, y = ent.position.x, ent.position.y
		local tx, ty = conv(x-gx, y-gy, c.w, c.h)
		local tile = grid:get_tile(tx, ty)
		tile.contains_resource = true
		tile.amount = ent.amount
		grid:convolve(tx, ty)
		resource_tiles[#resource_tiles+1] = tile
		cost = cost + convolve_size
		i = i + 1
	end
	state.resource_iter = i

	-- for _, ent in ipairs(resources) do
	-- 	local x, y = ent.position.x, ent.position.y
	-- 	local tx, ty = conv(x-gx, y-gy, c.w, c.h)
	-- 	local tile = grid:get_tile(tx, ty)
	-- 	tile.contains_resource = true
	-- 	tile.amount = ent.amount
	-- 	grid:convolve(tx, ty)
	-- 	resource_tiles[#resource_tiles+1] = tile
	-- end

	--[[ debug visualisation - resource and coord
	for _, ent in ipairs(resource_tiles) do
		rendering.draw_circle{
			surface = state.surface,
			filled = false,
			color = {0.3, 0.3, 1},
			width = 1,
			target = {c.gx + ent.x, c.gy + ent.y},
			radius = 0.5,
		}
		rendering.draw_text{
			text=string.format("%i,%i", ent.x, ent.y),
			surface = state.surface,
			color={1,1,1},
			target={c.gx + ent.x, c.gy + ent.y},
			alignment = "center",
		}
	end --]]
	
	if state.resource_iter >= #state.resources then
		state.grid_backup = table.deepcopy(state.grid) --[[@as Grid]]

		return "prepare_layout_attempts"
	end
	return true
end

---@class MinerPlacement
---@field tile GridTile
---@field center GridTile
---@field line number lane index
---@field stagger number Super compact layout stagger index
---@field column number column index
---@field ent BlueprintEntity|nil
---@field unconsumed number Unconsumed resource count for postponed miners
---@field direction string

---@class PlacementCoords
---@field sx number x shift
---@field sy number y shift

---@class PlacementAttempt
---@field sx number x shift
---@field sy number y shift
---@field miners MinerPlacement[]
---@field miner_count number
---@field postponed MinerPlacement[]
---@field heuristic_score number
---@field neighbor_sum number
---@field lane_layout LaneInfo
---@field far_neighbor_sum number
---@field unconsumed_count number
---@field simple_density number
---@field real_density number
---@field leech_sum number
---@field postponed_count number
---@field empty_space number

---@class LaneInfo
---@field y number
---@field row_index number

function layout:_get_miner_placement_heuristic(state)
	if state.coverage_choice then
		return common.overfill_miner_placement(state.miner)
	else
		return common.simple_miner_placement(state.miner)
	end
end

function layout:_get_layout_heuristic(state)
	if state.coverage_choice then
		return common.overfill_layout_heuristic
	else
		return common.simple_layout_heuristic
	end
end

---@param state SimpleState
---@return PlacementAttempt
function layout:_placement_attempt(state, shift_x, shift_y)
	local c = state.coords
	local grid = state.grid
	local size, near, far, fullsize = state.miner.size, state.miner.near, state.miner.far, state.miner.full_size
	local miners, postponed = {}, {}
	local neighbor_sum = 0
	local far_neighbor_sum = 0
	local simple_density = 0
	local real_density = 0
	local leech_sum = 0
	local empty_space = 0
	local lane_layout = {}
	
	local heuristic = self:_get_miner_placement_heuristic(state)
	
	local row_index = 1
	for y = 1 + shift_y, state.coords.th + near, size + 1 do
		local column_index = 1
		lane_layout[#lane_layout+1] = {y = y+near, row_index = row_index}
		for x = 1 + shift_x, state.coords.tw + near, size do
			local tile = grid:get_tile(x, y)
			local center = grid:get_tile(x+near, y+near) --[[@as GridTile]]
			local miner = {
				tile = tile,
				line = row_index,
				center = center,
				column=column_index,
			}
			if center.far_neighbor_count > 0 and heuristic(center) then
				miners[#miners+1] = miner
				neighbor_sum = neighbor_sum + center.neighbor_count
				far_neighbor_sum = far_neighbor_sum + center.far_neighbor_count
				empty_space = empty_space + (size^2) - center.neighbor_count
				simple_density = simple_density + center.neighbor_count / (size ^ 2)
				real_density = real_density + center.far_neighbor_count / (fullsize ^ 2)
				leech_sum = leech_sum + max(0, center.far_neighbor_count - center.neighbor_count)
			elseif center.far_neighbor_count > 0 then
				postponed[#postponed+1] = miner
			end
			column_index = column_index + 1
		end
		row_index = row_index + 1
	end

	local result = {
		sx=shift_x, sy=shift_y,
		miners=miners,
		miner_count=#miners,
		lane_layout=lane_layout,
		postponed=postponed,
		neighbor_sum=neighbor_sum,
		far_neighbor_sum=far_neighbor_sum,
		leech_sum=leech_sum,
		simple_density=simple_density,
		real_density=real_density,
		empty_space=empty_space,
		unconsumed_count=0,
		postponed_count=0,
	}

	common.process_postponed(state, result, miners, postponed)

	return result
end

---@param self SimpleLayout
---@param state SimpleState
function layout:prepare_layout_attempts(state)
	local m = state.miner
	--local init_pos_x, init_pos_y = -m.near, -m.near
	local init_pos_x, init_pos_y = 0, 0
	local attempts = {{init_pos_x, init_pos_y}}
	state.attempts = attempts
	state.best_attempt_index = 1
	state.attempt_index = 1 -- first attempt is used up
	--local ext_behind, ext_forward = -m.far, m.far - m.near
	local ext_behind, ext_forward = -m.far, m.far - m.near
	
	--for sy = ext_behind, ext_forward do
	--	for sx = ext_behind, ext_forward do
	for sy = ext_forward, ext_behind, -1 do
		for sx = ext_forward, ext_behind, -1 do
			if not (sx == init_pos_x and sy == init_pos_y) then
				attempts[#attempts+1] = {sx, sy}
			end
		end
	end

	return "init_layout_attempt"
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:init_layout_attempt(state)

	local attempt = state.attempts[state.attempt_index]

	state.best_attempt = self:_placement_attempt(state, attempt[1], attempt[2])
	state.best_attempt_score = self:_get_layout_heuristic(state)(state.best_attempt)
	
	if state.debug_dump then
		state.best_attempt.heuristic_score = state.best_attempt_score
		state.saved_attempts = {}
		state.saved_attempts[#state.saved_attempts+1] = state.best_attempt
	end

	state.attempt_index = state.attempt_index + 1
	return "layout_attempt"
end

---Bruteforce the best solution
---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:layout_attempt(state)
	local attempt_state = state.attempts[state.attempt_index]
	---@type PlacementAttempt
	local current_attempt = self:_placement_attempt(state, attempt_state[1], attempt_state[2])
	local current_attempt_score = self:_get_layout_heuristic(state)(current_attempt)

	if state.debug_dump then
		current_attempt.heuristic_score = current_attempt_score
		state.saved_attempts[#state.saved_attempts+1] = current_attempt
	end

	if current_attempt.unconsumed_count == 0 and current_attempt_score < state.best_attempt_score  then
		state.best_attempt_index = state.attempt_index
		state.best_attempt = current_attempt
		state.best_attempt_score = current_attempt_score
	end

	if state.attempt_index >= #state.attempts then
		--game.print(("Chose attempt #%i, %i miners"):format(state.best_attempt_index, #state.best_attempt.miners))
		return "prepare_miner_layout"
	end
	state.attempt_index = state.attempt_index + 1
	return true
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:prepare_miner_layout(state)
	local c = state.coords
	local g = state.grid

	---@type table<number, MinerPlacement[]>
	local miner_lanes = {}
	local miner_lane_count = 0 -- highest index of a lane, because using # won't do the job if a lane is missing
	local miner_max_column = 0
	state.miner_lanes = miner_lanes

	for _, miner in ipairs(state.best_attempt.miners) do
		local center = miner.center
		g:build_miner(center.x, center.y)
		-- local can_place = surface.can_place_entity{
		-- 	name=state.miner.name,
		-- 	force = state.player.force,
		-- 	position={center.gx, center.gy},
		-- 	direction = defines.direction.north,
		-- 	build_check_type = 
		-- }

		--[[ debug visualisation - miner placement
		local off = state.miner.size / 2
		rendering.draw_rectangle{
			surface = state.surface,
			filled = false,
			color = miner.postponed and {1, 0, 0} or {0, 1, 0},
			width = 3,
			--target = {c.x1 + x, c.y1 + y},
			left_top = {c.gx+x-off, c.gy + y - off},
			right_bottom = {c.gx+x+off, c.gy + y + off},
		}
		--]]

		local index = miner.line
		miner_lane_count = max(miner_lane_count, index)
		if not miner_lanes[index] then miner_lanes[index] = {} end
		local line = miner_lanes[index]
		line[#line+1] = miner
		miner_max_column = max(miner_max_column, miner.column)
	end
	state.miner_lane_count = miner_lane_count
	state.miner_max_column = miner_max_column

	for _, lane in pairs(miner_lanes) do
		table.sort(lane, function(a, b) return a.center.x < b.center.x end)
	end

	return "prepare_pipe_layout"
end

---@class PlacementSpecification
---@field x number
---@field w number
---@field y number
---@field h number
---@field structure string
---@field entity string
---@field skip_up boolean
---@field skip_down boolean

--- Process gaps between miners in "miner space" and translate them to grid specification
---@param self SimpleLayout
---@param state SimpleState
function layout:prepare_pipe_layout(state)
	local next_step = "prepare_belt_layout"
	if state.pipe_choice == "none"
	or (not state.requires_fluid and not state.force_pipe_placement_choice)
	then
		return next_step
	end
	local pipe_layout = {}
	state.pipe_layout_specification = pipe_layout
	state.place_pipes = true

	local m = state.miner
	local attempt = state.best_attempt

	for _, pre_lane in ipairs(state.miner_lanes) do
		if not pre_lane[1] then goto continue_lanes end
		local y = pre_lane[1].center.y
		local sx = state.best_attempt.sx
		local lane = table.mapkey(pre_lane, function(t) return t.column end) -- make array with intentional gaps between miners

		-- Calculate a list of run-length gaps
		-- start and length are in miner count
		local gaps = {}
		local current_start, current_length = nil, 0
		for i = 1, state.miner_max_column do
			local miner = lane[i]
			if miner and current_start then
				gaps[#gaps+1] = {start=current_start, length=current_length}
				current_start, current_length = nil, 0
			elseif not miner and not current_start then
				current_start, current_length = i, 1
			else
				current_length = current_length + 1
			end
		end

		for i, gap in ipairs(gaps) do
			local start, length = gap.start, gap.length
			local gap_length = m.size * length
			local gap_start = sx + (start-1) * m.size + 1
			
			pipe_layout[#pipe_layout+1] = {
				structure="horizontal",
				x = gap_start,
				w = gap_length-1,
				y = y,
			}
		end

		::continue_lanes::
	end

	for i = 1, state.miner_lane_count do
		local lane = attempt.lane_layout[i]
		pipe_layout[#pipe_layout+1] = {
			structure="cap_vertical",
			x=attempt.sx,
			y=lane.y,
			skip_up=i == 1,
			skip_down=i == state.miner_lane_count,
		}
	end

	return next_step
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:prepare_belt_layout(state)
	local c = state.coords
	local m = state.miner
	local g = state.grid
	local surface = state.surface
	local attempt = state.best_attempt

	---@type table<number, MinerPlacement[]>
	local miner_lanes = state.miner_lanes
	local miner_lane_count = state.miner_lane_count -- highest index of a lane, because using # won't do the job if a lane is missing
	local miner_max_column = state.miner_max_column

	---@param lane MinerPlacement[]
	local function get_lane_length(lane) if lane and lane[#lane] then return lane[#lane].center.x end return 0 end

	local pipe_adjust = state.place_pipes and -1 or 0

	local belts = {}
	state.belts = belts
	state.belt_count = 0
	local longest_belt = 0
	for i = 1, miner_lane_count, 2 do
		local lane1 = miner_lanes[i]
		local lane2 = miner_lanes[i+1]

		local y = attempt.sy + (m.size + 1) * i

		local belt = {x1=attempt.sx + 1 + pipe_adjust, x2=attempt.sx + 1, y=y, built=false}
		belts[#belts+1] = belt
		
		if lane1 or lane2 then
			state.belt_count = state.belt_count + 1
			local x1 = attempt.sx + 1
			local x2 = max(get_lane_length(lane1), get_lane_length(lane2)) + m.near
			longest_belt = max(longest_belt, x2 - x1 + 1)
			belt.x1, belt.x2, belt.built = x1, x2, true
		end
	end
	state.longest_belt = longest_belt

	return "prepare_pole_layout"
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:prepare_pole_layout(state)
	local c = state.coords
	local DIR = state.direction_choice
	local m = state.miner
	local g = state.grid
	local surface = state.surface
	local attempt = state.best_attempt

	local pole_proto = game.entity_prototypes[state.pole_choice] or {supply_area_distance=3, max_wire_distance=9}
	local supply_area, wire_reach = 3, 9
	if pole_proto then
		supply_area, wire_reach = floor(pole_proto.supply_area_distance), pole_proto.max_wire_distance
	end

	--TODO: figure out double lane coverage with insane supply areas
	local function get_covered_miners(ix, iy)
		--for sy = -supply_radius, supply_radius do
		for sy = -supply_area, supply_area, 1 do
			for sx = -supply_area, supply_area, 1 do
				local tile = g:get_tile(ix+sx, iy+sy)
				if tile and tile.built_on == "miner" then
					return true
				end
			end
		end
	end

	---@type PowerPoleGrid
	local power_poles_grid = setmetatable({}, pole_grid_mt)
	local power_poles_all = {}
	state.power_poles_all = power_poles_all

	local coverage = mpp_util.calculate_pole_coverage(state, state.miner_max_column, state.miner_lane_count)

	-- rendering.draw_circle{
	-- 	surface = state.surface,
	-- 	player = state.player,
	-- 	filled = true,
	-- 	color = {1, 1, 1},
	-- 	radius = 0.5,
	-- 	target = mpp_revert(c.gx, c.gy, DIR, attempt.sx, attempt.sy, c.tw, c.th),
	-- }

	local iy = 1
	for y = attempt.sy + coverage.lane_start, c.th + m.size, coverage.lane_step do
		local ix, pole_lane = 1, {}
		for x = 1 + attempt.sx + coverage.pole_start, attempt.sx + coverage.full_miner_width + 1, coverage.pole_step do
			local built = false
			---@type LuaEntity
			local ghost
			if get_covered_miners(x, y) then
				built = true
				g:get_tile(x, y).built_on = "pole"
			end
			local pole = {x=x, y=y, ix=ix, iy=iy, built=built, ghost=ghost}
			power_poles_grid:set_pole(ix, iy, pole)
			power_poles_all[#power_poles_all+1] = pole
			pole_lane[ix] = pole

			if built and ix > 1 and pole_lane[ix-1] then
				for bx = ix - 1, 1, -1 do
					local backtrack_pole = pole_lane[bx]
					if not backtrack_pole.built then
						backtrack_pole.built = true
					else
						break
					end
				end
			end

			ix = ix + 1
		end
		iy = iy + 1
	end

	return "unagressive_deconstruct"
end

function layout:_prepare_deconstruct_specification(state)
	state.deconstruct_specification = {
		x = state.best_attempt.sx - 1,
		y = state.best_attempt.sy - 1,
		width = state.miner_max_column * state.miner.size + 1,
		height = state.miner_lane_count * (state.miner.size + 1) + 1,
	}

	return state.deconstruct_specification
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:unagressive_deconstruct(state)
	local c = state.coords
	local player = state.player
	local surface = state.surface
	local spec = self:_prepare_deconstruct_specification(state)

	local reverter = coord_revert[state.direction_choice]
	local spec_x, spec_y = reverter(spec.x, spec.y, c.tw, c.th)
	local spec_w, spec_h = reverter(spec.x+spec.width, spec.y+spec.height, c.tw, c.th)

	local left_top = { c.x1-.5 + spec_x, c.y1-.5 + spec_y }
	local right_bottom = { left_top[1] + spec_w, left_top[2] + spec_h }

	local deconstructor = global.script_inventory[state.deconstruction_choice and 2 or 1]
	surface.deconstruct_area{
		force=player.force,
		player=player.index,
		area={left_top=left_top, right_bottom=right_bottom},
		item=deconstructor,
	}

	--[[]]
	rendering.draw_rectangle{
		surface=state.surface, players={state.player},
		width=4, color={1, 0, 0}, filled=false,
		left_top=left_top,
		right_bottom=right_bottom,
	} -- ]]
	return "placement_miners"
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:placement_miners(state)
	local create_entity = builder.create_entity_builder(state)

	local module_inv_size = state.miner.module_inventory_size --[[@as uint]]
	local grid = state.grid

	for i, miner in ipairs(state.best_attempt.miners) do
		local flip_lane = miner.line % 2 ~= 1
		local direction = miner_direction[state.direction_choice]
		if flip_lane then direction = opposite[direction] end

		local x, y = miner.center.x, miner.center.y

		grid:build_miner(x, y)
		local ghost = create_entity{
			name = state.miner_choice,
			thing="miner",
			grid_x = x,
			grid_y = y,
			direction = defines.direction[direction],
		}

		if state.module_choice ~= "none" then
			ghost.item_requests = {[state.module_choice] = module_inv_size}
		end
	end

	return "placement_pipes"
end


--- Pipe placement deals in tile grid space with spectifications from previous step
---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:placement_pipes(state)
	local next_step = "placement_belts"
	if not state.place_pipes then return next_step end

	local create_entity = builder.create_entity_builder(state)
	local g = state.grid
	local pipe = state.pipe_choice
	
	local ground_pipe, ground_proto = mpp_util.find_underground_pipe(pipe)
	---@cast ground_pipe string

	local step, span
	if ground_proto then
		step = ground_proto.max_underground_distance
		span = step + 1
	end

	local function horizontal_underground(x1, y, w)
		local x = x1
		create_entity{
			name=ground_pipe,
			thing="pipe",
			grid_x=x,
			grid_y=y,
			direction=defines.direction.west,
		}
		create_entity{
			name=ground_pipe,
			thing="pipe",
			grid_x=x+w,
			grid_y=y,
			direction=defines.direction.east,
		}
	end
	local function horizontal_filled(x1, y, w)
		for x = x1, x1+w do
			create_entity{
				name=pipe,
				thing="pipe",
				grid_x=x,
				grid_y=y,
			}
		end
	end
	local function cap_vertical(x, y, skip_up, skip_down)
		create_entity{
			name=pipe,
			thing="pipe",
			grid_x=x,
			grid_y=y,
		}

		if not ground_pipe then return end
		if not skip_up then
			create_entity{
				name=ground_pipe,
				thing="pipe",
				grid_x=x,
				grid_y=y-1,
				direction=defines.direction.south,
			}
		end
		if not skip_down then
			create_entity{
				name=ground_pipe,
				thing="pipe",
				grid_x=x,
				grid_y=y+1,
				direction=defines.direction.north,
			}
		end
	end

	for i, p in ipairs(state.pipe_layout_specification) do
		local structure = p.structure
		local x1, w, y1, h = p.x, p.w, p.y, p.h
		if structure == "horizontal" then
			if not ground_pipe then
				horizontal_filled(x1, y1, w)
				goto continue_pipe
			end

			local quotient, remainder = math.divmod(w, span)
			for j = 1, quotient do
				local x = x1 + (j-1)*span
				horizontal_underground(x, y1, step)
			end
			local x = x1 + quotient * span
			if remainder >= 2 then
				horizontal_underground(x, y1, remainder)
			else
				horizontal_filled(x, y1, remainder)
			end
		elseif structure == "cap_vertical" then
			cap_vertical(x1, y1, p.skip_up, p.skip_down)
		end
		::continue_pipe::
	end

	return next_step
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:placement_belts(state)
	local create_entity = builder.create_entity_builder(state)

	for i, belt in ipairs(state.belts) do
		if not belt.built  then goto continue end
		local x1, x2, y = belt.x1, belt.x2, belt.y
		for x = x1, x2 do
			create_entity{
				name=state.belt_choice,
				thing="belt",
				grid_x=x,
				grid_y=y,
				direction=defines.direction.west,
			}
		end

		::continue::
	end

	return "placement_poles"
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:placement_poles(state)
	local next_step = "placement_lamp"
	if state.pole_choice == "none" then return next_step end
	
	local create_entity = builder.create_entity_builder(state)

	for  _, pole in ipairs(state.power_poles_all) do
		if pole.built then
			local ghost = create_entity{
				name=state.pole_choice,
				thing="pole",
				grid_x = pole.x,
				grid_y = pole.y,
			}
			--ghost.disconnect_neighbour()
			pole.ghost = ghost
		end
	end

	return next_step
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:placement_lamp(state)
	local next_step = "placement_landfill"
	if not state.lamp_choice then return next_step end

	local c = state.coords
	local grid = state.grid
	local surface = state.surface

	local sx, sy = -1, 0
	if state.pole_choice == "none" then sx = 0 end

	for _, pole in ipairs(state.power_poles_all) do
		local x, y = pole.x, pole.y
		local ix, iy = pole.ix, pole.iy
		local tile = grid:get_tile(x+sx, y+sy)
		if tile and pole.built and not pole.no_light then
			tile.built_on = "lamp"
			local tx, ty = coord_revert[state.direction_choice](x + sx, y + sy, c.tw, c.th)
			surface.create_entity{
				raise_built=true,
				name="entity-ghost",
				player=state.player,
				force=state.player.force,
				position={c.gx + tx, c.gy + ty},
				inner_name="small-lamp",
			}
		end
	end

	return next_step
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:placement_landfill(state)
	local c = state.coords
	local m = state.miner
	local grid = state.grid
	local surface = state.surface

	if state.landfill_choice then
		return "finish"
	end

	local conv = coord_convert[state.direction_choice]
	local gx, gy = state.coords.ix1 - 1, state.coords.iy1 - 1

	local resource_tiles = {}
	state.resource_tiles = resource_tiles

	local fill_tiles, landfill
	local area = {left_top={c.x1-m.full_size-1, c.y1-m.full_size-1}, right_bottom={c.x2+m.full_size+1, c.y2+m.full_size+1}}
	if state.is_space then
		fill_tiles = surface.find_tiles_filtered{area=area, name="se-space"}
		landfill = state.space_landfill_choice
	else
		fill_tiles = surface.find_tiles_filtered{area=area, collision_mask="water-tile"}
		landfill = "landfill"
	end

	for _, fill in ipairs(fill_tiles) do
		local x, y = fill.position.x, fill.position.y
		x, y = conv(x-gx, y-gy, c.w, c.h)
		local tile = grid:get_tile(x, y)

		if tile and tile.built_on then
			surface.create_entity{
				raise_built=true,
				name="tile-ghost",
				player=state.player,
				force=state.player.force,
				position=fill.position --[[@as MapPosition]],
				inner_name=landfill,
			}
		end
	end

	return "finish"
end

---@param self SimpleLayout
---@param state SimpleState
---@return CallbackState
function layout:finish(state)
	if state.print_placement_info_choice and state.player.valid then
		state.player.print({"mpp.msg_print_info_miner_placement", state.best_attempt.miner_count, state.belt_count, #state.resources})
	end

	if mpp_util.get_dump_state(state.player.index) then
		common.save_state_to_file(state, "json")
	end

	return false
end

return layout
