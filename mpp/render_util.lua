local mpp_util = require("mpp.mpp_util")
local color = require("mpp.color")

local floor, ceil = math.floor, math.ceil
local min, max = math.min, math.max
local EAST, NORTH, SOUTH, WEST = mpp_util.directions()
local DIR = defines.direction

local render_util = {}

local triangles = {
	west={
		{{target={-.6, 0}}, {target={.6, -0.6}}, {target={.6, 0.6}}},
		{{target={-.4, 0}}, {target={.5, -0.45}}, {target={.5, 0.45}}},
	},
	east={
		{{target={.6, 0}}, {target={-.6, -0.6}}, {target={-.6, 0.6}}},
		{{target={.4, 0}}, {target={-.5, -0.45}}, {target={-.5, 0.45}}},
	},
	north={
		{{target={0, -.6}}, {target={-.6, .6}}, {target={.6, .6}}},
		{{target={0, -.4}}, {target={-.45, .5}}, {target={.45, .5}}},
	},
	south={
		{{target={0, .6}}, {target={-.6, -.6}}, {target={.6, -.6}}},
		{{target={0, .4}}, {target={-.45, -.5}}, {target={.45, -.5}}},
	},
}
local alignment = {
	west={"center", "center"},
	east={"center", "center"},
	north={"left", "right"},
	south={"right", "left"},
}

local bound_alignment = {
	west="right",
	east="left",
	north="center",
	south="center",
}

---Draws a belt lane overlay
---@param state State
---@param belt BeltSpecification
function render_util.draw_belt_lane(state, belt)
	local r = state._render_objects
	local c, ttl, player = state.coords, 0, {state.player}
	local x1, y1, x2, y2 = belt.x1, belt.y, math.max(belt.x1+2, belt.x2), belt.y
	local function l2w(x, y) -- local to world
		local rev = mpp_util.revert(c.gx, c.gy, state.direction_choice, x-.5, y-.5, c.tw, c.th)
		return {rev[1]+.5, rev[2]+.5}
	end
	local c1, c2, c3 = {.9, .9, .9}, {0, 0, 0}, {.4, .4, .4}
	local w1, w2 = 4, 10
	if not belt.lane1 and not belt.lane2 then c1 = c3 end
	
	r[#r+1] = rendering.draw_line{ -- background main line
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w2, color=c2, time_to_live=ttl or 1,
		from=l2w(x1, y1), to=l2w(x2+.5, y1),
	}
	r[#r+1] = rendering.draw_line{ -- background vertical cap
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w2, color=c2, time_to_live=ttl or 1,
		from=l2w(x2+.5, y1-.6), to=l2w(x2+.5, y2+.6),
	}
	r[#r+1] = rendering.draw_polygon{ -- background arrow
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w2, color=c2, time_to_live=ttl or 1,
		target=l2w(x1, y1),
		vertices=triangles[state.direction_choice][1],
	}
	r[#r+1] = rendering.draw_line{ -- main line
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w1, color=c1, time_to_live=ttl or 1,
		from=l2w(x1-.2, y1), to=l2w(x2+.5, y1),
	}
	r[#r+1] = rendering.draw_line{ -- vertical cap
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=w1, color=c1, time_to_live=ttl or 1,
		from=l2w(x2+.5, y1-.5), to=l2w(x2+.5, y2+.5),
	}
	r[#r+1] = rendering.draw_polygon{ -- arrow
		surface=state.surface, players=player, only_in_alt_mode=true,
		width=0, color=c1, time_to_live=ttl or 1,
		target=l2w(x1, y1),
		vertices=triangles[state.direction_choice][2],
	}
end

---Draws a belt lane overlay
---@param state State
---@param belt BeltSpecification
function render_util.draw_belt_stats(state, belt, belt_speed, speed1, speed2)
	local r = state._render_objects
	local c, ttl, player = state.coords, 0, {state.player}
	local x1, y1, x2, y2 = belt.x1, belt.y, belt.x2, belt.y
	local function l2w(x, y) -- local to world
		return mpp_util.revert(c.gx, c.gy, state.direction_choice, x, y, c.tw, c.th)
	end
	local c1, c2, c3, c4 = {.9, .9, .9}, {0, 0, 0}, {.9, 0, 0}, {.4, .4, .4}
	
	local ratio1 = speed1 / belt_speed
	local ratio2 = speed2 / belt_speed
	local function get_color(ratio)
		return ratio > 1.01 and c3 or ratio == 0 and c4 or c1
	end

	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=get_color(ratio1), time_to_live=ttl or 1,
		alignment=alignment[state.direction_choice][1], vertical_alignment="middle",
		target=l2w(x1-2, y1-.6), scale=1.6,
		text=string.format("%.2fx", ratio1),
	}
	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=get_color(ratio2), time_to_live=ttl or 1,
		alignment=alignment[state.direction_choice][2], vertical_alignment="middle",
		target=l2w(x1-2, y1+.6), scale=1.6,
		text=string.format("%.2fx", ratio2),
	}

end

---Draws a belt lane overlay
---@param state State
---@param pos_x number
---@param pos_y number
---@param speed1 number
---@param speed2 number
function render_util.draw_belt_total(state, pos_x, pos_y, speed1, speed2)
	local r = state._render_objects
	local c, ttl, player = state.coords, 0, {state.player}
	local function l2w(x, y, b) -- local to world
		if ({south=true, north=true})[state.direction_choice] then
			x = x + (b and -.5 or .5)
			y = y + (b and -.5 or .5)
		end
		return mpp_util.revert(c.gx, c.gy, state.direction_choice, x, y, c.tw, c.th)
	end
	local c1 = {0.7, 0.7, 1.0}

	local lower_bound = math.min(speed1, speed2)
	local upper_bound = math.max(speed1, speed2)

	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=c1, time_to_live=ttl or 1,
		alignment=bound_alignment[state.direction_choice], vertical_alignment="middle",
		target=l2w(pos_x-4, pos_y-.6, false), scale=2,
		text={"mpp.msg_print_info_lane_saturation_belts", string.format("%.2fx", upper_bound), string.format("%.2fx", (lower_bound+upper_bound)/2)},
	}
	r[#r+1] = rendering.draw_text{
		surface=state.surface, players=player, only_in_alt_mode=true,
		color=c1, time_to_live=ttl or 1,
		alignment=bound_alignment[state.direction_choice], vertical_alignment="middle",
		target=l2w(pos_x-4, pos_y+.6, true), scale=2,
		text={"mpp.msg_print_info_lane_saturation_bounds", string.format("%.2fx", lower_bound), string.format("%.2fx", upper_bound)},
	}

end

---@class RendererParams
---@field origin MapPosition?
---@field target MapPosition?
---@field x number?
---@field y number?
---@field w number?
---@field h number?
---@field r number?
---@field color Color?
---@field width number?
---@field c Color?
---@field left_top MapPosition?
---@field right_bottom MapPosition?

---this went off the rails
---@param event EventData.on_player_reverse_selected_area
---@return MppRendering
function render_util.renderer(event)

	---@param t RendererParams
	local function parametrizer(t, overlay)

		for k, v in pairs(overlay or {}) do t[k] = v end
		if t.x and t.y then t.origin = {t.x, t.y} end
		local target = t.origin or t.left_top --[[@as MapPosition]]
		local left_top, right_bottom = t.left_top or t.origin or target, t.right_bottom or t.origin

		if t.origin and t.w or t.h then
			t.w, t.h = t.w or t.h, t.h or t.w
			right_bottom = {(target[1] or target.x) + t.w, (target[2] or target.y) + t.h}
		elseif t.r then
			local r = t.r
			local ox, oy = target[1] or target.x, target[2] or target.y
			left_top = {ox-r, oy-r}
			right_bottom = {ox+r, oy+r}
		end

		local new = {
			surface = event.surface,
			players = {event.player_index},
			filled = false,
			radius = t.r or 1,
			color = t.c or t.color or {1, 1, 1},
			left_top = left_top,
			right_bottom = right_bottom,
			target = target, -- circles
			from = left_top,
			to = right_bottom, -- lines
			width = 1,
		}
		for k, v in pairs(t) do new[k]=v end
		for _, v in ipairs{"x", "y", "h", "w", "r", "origin"} do new[v]=nil end
		return new
	end

	local meta_renderer_meta = {}
	meta_renderer_meta.__index = function(self, k)
		return function(t, t2)
			return {
				rendering[k](
					parametrizer(t, t2)
				)
			}
	end end
	local rendering = setmetatable({}, meta_renderer_meta)

	---@class MppRendering
	local rendering_extension = {}

	---Draws an x between left_top and right_bottom
	---@param params RendererParams
	function rendering_extension.draw_cross(params)
		rendering.draw_line(params)
		rendering.draw_line({
			width = params.width,
			color = params.color,
			left_top={
				params.right_bottom[1],
				params.left_top[2]
			},
			right_bottom={
				params.left_top[1],
				params.right_bottom[2],
			}
		})
	end

	function rendering_extension.draw_rectangle_dashed(params)
		rendering.draw_line(params, {
			from={params.left_top[1], params.left_top[2]},
			to={params.right_bottom[1], params.left_top[2]},
			dash_offset = 0.0,
		})
		rendering.draw_line(params, {
			from={params.left_top[1], params.right_bottom[2]},
			to={params.right_bottom[1], params.right_bottom[2]},
			dash_offset = 0.5,
		})
		rendering.draw_line(params, {
			from={params.right_bottom[1], params.left_top[2]},
			to={params.right_bottom[1], params.right_bottom[2]},
			dash_offset = 0.0,
		})
		rendering.draw_line(params, {
			from={params.left_top[1], params.left_top[2]},
			to={params.left_top[1], params.right_bottom[2]},
			dash_offset = 0.5,
		})
	end

	local meta = {}
	function meta:__index(k)
		return function(t, t2)
			if rendering_extension[k] then
				rendering_extension[k](parametrizer(t, t2))
			else
				rendering[k](parametrizer(t, t2))
			end
		end
	end

	return setmetatable({}, meta)
end

function render_util.draw_clear_rendering(player_data, event)
	rendering.clear("mining-patch-planner")
end

---Draws the properties of a mining drill
---@param player_data PlayerData
---@param event EventData.on_player_reverse_selected_area
function render_util.draw_drill_struct(player_data, event)

	local renderer = render_util.renderer(event)

	local fx1, fy1 = event.area.left_top.x, event.area.left_top.y
	fx1, fy1 = floor(fx1), floor(fy1)
	local x, y = fx1 + 0.5, fy1 + 0.5
	local fx2, fy2 = event.area.right_bottom.x, event.area.right_bottom.y
	fx2, fy2 = ceil(fx2), ceil(fy2)

	--renderer.draw_cross{x=fx1, y=fy1, w=fx2-fx1, h=fy2-fy1}
	--renderer.draw_cross{x=fx1, y=fy1, w=2}

	local drill = mpp_util.miner_struct(player_data.choices.miner_choice)

	renderer.draw_circle{
		x = fx1 + drill.drop_pos.x,
		y = fy1 + drill.drop_pos.y,
		c = {0, 1, 0},
		r = 0.2,
	}

	-- drop pos
	renderer.draw_cross{
		x = fx1 + 0.5 + drill.out_x,
		y = fy1 + 0.5 + drill.out_y,
		r = 0.3,
	}

	for _, pos in pairs(drill.output_rotated) do
		renderer.draw_cross{
			x = fx1 + 0.5 + pos[1],
			y = fy1 + 0.5 + pos[2],
			r = 0.15,
			width = 3,
			c={0, 0, 0, .5},
		}
	end

	renderer.draw_line{
		from={x + drill.x, y},
		to={x + drill.x, y + 2},
		width = 2, color={0.5, 0.5, 0.5}
	}
	renderer.draw_line{
		from={x + drill.x, y},
		to={x + drill.x-.5, y + .65},
		width = 2, color={0.5, 0.5, 0.5}
	}
	renderer.draw_line{
		from={x + drill.x, y},
		to={x + drill.x+.5, y + .65},
		width = 2, color={0.5, 0.5, 0.5}
	}


	-- drill origin
	renderer.draw_circle{
		x = fx1 + 0.5,
		y = fy1 + 0.5,
		width = 2,
		r = 0.4,
	}

	renderer.draw_text{
		target={fx1 + .5, fy1 + .5},
		text = "(0, 0)",
		alignment = "center",
		vertical_alignment="middle",
		scale = 0.6,
	}

	-- negative extent - cyan
	renderer.draw_cross{
		x = fx1 +.5 + drill.extent_negative,
		y = fy1 +.5 + drill.extent_negative,
		r = 0.25,
		c = {0, 0.8, 0.8},
	}

	-- positive extent - purple
	renderer.draw_cross{
		x = fx1 +.5 + drill.extent_positive,
		y = fy1 +.5 + drill.extent_positive,
		r = 0.25,
		c = {1, 0, 1},
	}

	renderer.draw_rectangle{
		x=fx1,
		y=fy1,
		w=drill.size,
		h=drill.size,
		width=3,
		gap_length=0.5,
		dash_length=0.5,
	}

	renderer.draw_rectangle_dashed{
		x=fx1 + drill.extent_negative,
		y=fy1 + drill.extent_negative,
		w=drill.area,
		h=drill.area,
		c={0.5, 0.5, 0.5},
		width=5,
		gap_length=0.5,
		dash_length=0.5,
	}

	if drill.supports_fluids then
		-- pipe connections
		renderer.draw_line{
			width=4, color = {0, .7, 1},
			from={fx1-.3, y+drill.pipe_left-.5},
			to={fx1-.3, y+drill.pipe_left+.5},
		}
		renderer.draw_line{
			width=4, color = {.7, .7, 0},
			from={fx1+drill.size+.3, y+drill.pipe_left-.5},
			to={fx1+drill.size+.3, y+drill.pipe_left+.5},
		}
	end

	renderer.draw_text{
		target={fx1 + drill.extent_negative, fy1 + drill.extent_negative-1.5},
		text = string.format("skip_outer: %s", drill.skip_outer),
		alignment = "left",
		vertical_alignment="middle",
	}

	renderer.draw_circle{x = fx1, y = fy1, r = 0.1}
	--renderer.draw_circle{ x = fx2, y = fy2, r = 0.15, color={1, 0, 0} }
end

---Preview the pole coverage
---@param player_data PlayerData
---@param event EventData.on_player_reverse_selected_area
function render_util.draw_pole_layout(player_data, event)
	rendering.clear("mining-patch-planner")

	local renderer = render_util.renderer(event)

	local fx1, fy1 = event.area.left_top.x, event.area.left_top.y
	fx1, fy1 = floor(fx1), floor(fy1)

	--renderer.draw_cross{x=fx1, y=fy1, w=fx2-fx1, h=fy2-fy1}
	--renderer.draw_cross{x=fx1, y=fy1, w=2}

	local drill = mpp_util.miner_struct(player_data.choices.miner_choice)
	local pole = mpp_util.pole_struct(player_data.choices.pole_choice)

	local function draw_lane(x, y, count)
		for i = 0, count-1 do
			renderer.draw_rectangle{
				x = x + drill.size * i + 0.15 , y = y+.15,
				w = drill.size-.3, h=1-.3,
				color = i % 2 == 0 and {143/255, 86/255, 59/255} or {223/255, 113/255, 38/255},
				width=2,
			}
		end

		---@diagnostic disable-next-line: param-type-mismatch
		local coverage = mpp_util.calculate_pole_coverage(player_data.choices, count, 1)

		renderer.draw_circle{
			x=x+.5, y=y-0.5, radius = .25, color={0.7, 0.7, 0.7},
		}
		for i = coverage.pole_start, coverage.full_miner_width, coverage.pole_step do
			renderer.draw_circle{
				x = x + i + .5,
				y = y - .5,
				radius = 0.3, width=2,
				color = {0, 1, 1},
			}
			renderer.draw_line{
				x = x + i +.5 - pole.supply_width / 2+.2,
				y = y - .2,
				h = 0,
				w = pole.supply_width-.4,
				color = {0, 1, 1},
				width = 2,
			}
			renderer.draw_line{
				x = x + i +.5 - pole.supply_width / 2 + .2,
				y = y - .7,
				h = .5,
				w = 0,
				color = {0, 1, 1},
				width = 2,
			}
			renderer.draw_line{
				x = x + i +.5 + pole.supply_width / 2 - .2,
				y = y - .7,
				h = .5,
				w = 0,
				color = {0, 1, 1},
				width = 2,
			}
		end
	end

	for i = 1, 10 do
		draw_lane(fx1, fy1+(i-1)*3, i)
	end

end

---Preview the pole coverage
---@param player_data PlayerData
---@param event EventData.on_player_reverse_selected_area
function render_util.draw_pole_layout_compact(player_data, event)
	rendering.clear("mining-patch-planner")

	local renderer = render_util.renderer(event)

	local fx1, fy1 = event.area.left_top.x, event.area.left_top.y
	fx1, fy1 = floor(fx1), floor(fy1)

	--renderer.draw_cross{x=fx1, y=fy1, w=fx2-fx1, h=fy2-fy1}
	--renderer.draw_cross{x=fx1, y=fy1, w=2}

	local drill = mpp_util.miner_struct(player_data.choices.miner_choice)
	local pole = mpp_util.pole_struct(player_data.choices.pole_choice)

	local function draw_lane(x, y, count)
		for i = 0, count-1 do
			renderer.draw_rectangle{
				x = x + drill.size * i + 0.15 , y = y+.15,
				w = drill.size-.3, h=1-.3,
				color = i % 2 == 0 and {143/255, 86/255, 59/255} or {223/255, 113/255, 38/255},
				width=2,
			}
		end

		---@diagnostic disable-next-line: param-type-mismatch
		local coverage = mpp_util.calculate_pole_spacing(player_data.choices, count, 1)

		renderer.draw_circle{
			x=x+.5, y=y-0.5, radius = .25, color={0.7, 0.7, 0.7},
		}
		for i = coverage.pole_start, coverage.full_miner_width, coverage.pole_step do
			renderer.draw_circle{
				x = x + i + .5,
				y = y - .5,
				radius = 0.3, width=2,
				color = {0, 1, 1},
			}
			renderer.draw_line{
				x = x + i +.5 - pole.supply_width / 2+.2,
				y = y - .2,
				h = 0,
				w = pole.supply_width-.4,
				color = {0, 1, 1},
				width = 2,
			}
			renderer.draw_line{
				x = x + i +.5 - pole.supply_width / 2 + .2,
				y = y - .7,
				h = .5,
				w = 0,
				color = {0, 1, 1},
				width = 2,
			}
			renderer.draw_line{
				x = x + i +.5 + pole.supply_width / 2 - .2,
				y = y - .7,
				h = .5,
				w = 0,
				color = {0, 1, 1},
				width = 2,
			}
		end
	end

	for i = 1, 10 do
		draw_lane(fx1, fy1+(i-1)*3, i)
	end

end

---Displays the labels of built things on the grid
---@param player_data PlayerData
---@param event EventData.on_player_reverse_selected_area
function render_util.draw_built_things(player_data, event)
	rendering.clear("mining-patch-planner")

	local renderer = render_util.renderer(event)

	local state = player_data.last_state

	if not state then return end

	local C = state.coords
	local G = state.grid

	for _, row in pairs(G) do
		for _, tile in pairs(row) do
			---@cast tile GridTile
			local thing = tile.built_on
			if thing then
				-- renderer.draw_circle{
				-- 	x = C.gx + tile.x, y = C.gy + tile.y,
				-- 	w = 1,
				-- 	color = {0, 0.5, 0, 0.1},
				-- 	r = 0.5,
				-- }
				renderer.draw_rectangle{
					x = C.ix1 + tile.x -.9, y = C.iy1 + tile.y -.9,
					w = .8,
					color = {0, 0.2, 0, 0.1},
				}
				renderer.draw_text{
					x = C.gx + tile.x, y = C.gy + tile.y - .3,
					alignment = "center",
					vertical_alignment = "top",
					--vertical_alignment = tile.x % 2 == 1 and "top" or "bottom",
					text = thing,
					scale = 0.6,
				}
			end
		end
	end

end

---@param player_data PlayerData
---@param event EventData.on_player_reverse_selected_area
function render_util.draw_drill_convolution(player_data, event)
	rendering.clear("mining-patch-planner")

	local renderer = render_util.renderer(event)

	local fx1, fy1 = event.area.left_top.x, event.area.left_top.y
	fx1, fy1 = floor(fx1), floor(fy1)

	local state = player_data.last_state
	if not state then return end

	local C = state.coords
	local grid = state.grid

	for _, row in pairs(grid) do
		for _, tile in pairs(row) do
			---@cast tile GridTile
			--local c1, c2 = tile.neighbor_counts[m_size], tile.neighbor_counts[m_area]
			local c1, c2 = tile.neighbors_inner, tile.neighbors_outer
			if c1 == 0 and c2 == 0 then goto continue end

			rendering.draw_circle{
				surface = state.surface, filled=false, color = {0.3, 0.3, 1},
				width=1, radius = 0.5,
				target={C.gx + tile.x, C.gy + tile.y},
			}
			local stagger = (.5 - (tile.x % 2)) * .25
			local col = c1 == 0 and {0.3, 0.3, 0.3} or {0.6, 0.6, 0.6}
			rendering.draw_text{
				surface = state.surface, filled = false, color = col,
				target={C.gx + tile.x, C.gy + tile.y + stagger},
				text = string.format("%i,%i", c1, c2),
				alignment = "center",
				vertical_alignment="middle",
			}

			::continue::
		end
	end

end


---@param player_data PlayerData
---@param event EventData.on_player_reverse_selected_area
function render_util.draw_power_grid(player_data, event)
	local renderer = render_util.renderer(event)

	local fx1, fy1 = event.area.left_top.x, event.area.left_top.y
	fx1, fy1 = floor(fx1), floor(fy1)

	local state = player_data.last_state
	if not state then return end

	local C = state.coords
	local grid = state.grid

	local connectivity = state.power_connectivity
	if not connectivity then
		game.print("No connectivity exists")
		return
	end
	local rendered = {}

	for set_id, set in pairs(connectivity) do
		local set_color = color.hue_sequence(set_id)
		if set_id == 0 then set_color = {1, 1, 1} end
		for pole, _ in pairs(set) do
			---@cast pole GridPole
			if rendered[pole] then goto continue end
			rendered[pole] = true
			local pole_color = set_color
			if not pole.backtracked and not pole.has_consumers then
				pole_color = {0, 0, 0}
			end

			rendering.draw_circle{
				surface = state.surface,
				filled = not pole.backtracked,
				color = pole_color,
				width = 5,
				target = {C.gx + pole.grid_x, C.gy + pole.grid_y},
				radius = 0.45,
			}
			::continue::
		end
	end --]]

end

---@param player_data PlayerData
---@param event EventData.on_player_reverse_selected_area
function render_util.draw_centricity(player_data, event)
	local renderer = render_util.renderer(event)

	local fx1, fy1 = event.area.left_top.x, event.area.left_top.y
	fx1, fy1 = floor(fx1), floor(fy1)

	local state = player_data.last_state
	if not state then return end

	local C = state.coords
	local grid = state.grid

	

end


return render_util