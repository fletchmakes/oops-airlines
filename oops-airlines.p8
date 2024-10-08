pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- oops airlines
-- by fletch
-- made for lowrezjam 2024

-- music by @fettuccini
-- noodle cafe
-- https://fettuccini.itch.io/noodle-cafe

local debug = false

-- key constants
local k_left = 0
local k_right = 1
local k_up = 2
local k_down = 3
local k_primary = 4
local k_secondary = 5

-- easier time switching between game states
local current_update = nil
local current_draw = nil
local mode = "FLIGHT" -- "FLIGHT", "PLAN", "GAMEOVER", "TUTORIAL"
local last_mode = ""

-- particle simulator list
local particles = {}
local score_particles = {}

-- plane related tracking
local planes = {}
local active_planes = {}
local tutorial_planes = { 4, 2, 3 } -- 4 blue planes, 3 red planes, 2 yellow, the rest random
local plan_plane = nil -- plane that is currently being route planned for
local last_plan_node = nil
local last_plan_node_hovered = false

-- score tracking
local points = 0
local point_lookup = { 30, 10, 20 }
local flights_saved = { 0, 0, 0 } -- red, blue, yellow
local flight_type = { RED=1, BLUE=2, YELLOW=3 }
local flight_designations = { "rd", "bl", "yw"}

-- input blocking
local _btn, _btnp = btn, btnp
local input_blocker = false

-- camera
local cam = nil

-- animations
local animation = {
	frame = 1,
	
	-- current is a coroutine, like fly_text()
	queue = nil,
	is_animating = false,

	-- list of all animations that updates or draws
	update_me = {},
	draw_me = {},
}

-- make displaying text sprites easier
local smol_letters = {
	a = function(x, y) sspr(96, 40, 5, 6, x, y) end,
	i = function(x, y) sspr(100, 40, 5, 6, x, y) end,
	r = function(x, y) sspr(104, 40, 5, 6, x, y) end,
	l = function(x, y) sspr(108, 40, 5, 6, x, y) end,
	y = function(x, y) sspr(112, 40, 5, 6, x, y) end,
	n = function(x, y) sspr(96, 45, 5, 6, x, y) end,
	e = function(x, y) sspr(100, 45, 5, 6, x, y) end,
	s = function(x, y) sspr(104, 45, 5, 6, x, y) end,
	f = function(x, y) sspr(108, 45, 5, 6, x, y) end,
	p = function(x, y) sspr(112, 45, 5, 6, x, y) end,
	emphasis = function(x, y) sspr(116, 45, 3, 6, x, y) end,
}

local numerals = split("0,1,2,3,4,5,6,7,8,9")

local focus_paths = false

function _init()
	-- 64x64
    poke(0x5f2c, 3)
	
	-- camera initialization
	cam = new_camera()

	animation.queue = _qnew()
	_qpush(animation.queue, cocreate(fade_in()))

	flags = new_flags()
	add(animation.update_me, flags)
	add(animation.draw_me, flags)

	-- start with the splashscreen
	current_update = splashscreen_update
	current_draw = splashscreen_draw

	-- get 10 planes pooled and ready to be activated
	for i=1,10 do
		add_plane(i)
	end

	-- add menu items for restarting the game
	focus_paths = false
	menuitem(1, "new game", function() reset_game() end)
	menuitem(2, "focus paths: off", toggle_focus_paths)
	menuitem(3, "view tutorial", function() last_mode = mode mode = "TUTORIAL" end)
end

function toggle_focus_paths()
	-- toggle
	focus_paths = not focus_paths

	-- remove old menu item
	menuitem(2)

	-- add new menu item
	if focus_paths then
		menuitem(2, "focus paths: on", toggle_focus_paths)
	else
		menuitem(2, "focus paths: off", toggle_focus_paths)
	end

	-- keep menu open
	return true
end

function _update()
	current_update()
end

function _draw()
	current_draw()

	if debug then
		rectfill(0, 0, 63, 6, 0)
		print(stat(1), 0, 0, 7)
	end
end

-->8
-- gameplay

local plane_spawn_timer = 30
local hangar = {x=192, y=128}
local airport = {x=186, y=128}

local tutorial_page = 0
local tutorial_offset = 0

function game_update()
    -- write any game update logic here
	animation.frame = animation.frame % 30 + 1
	for a in all(animation.update_me) do
		a.update(a)
	end

	-- animation is playing, don't update the game yet
	if (not _qisempty(animation.queue)) and costatus(_qpeek(animation.queue)) ~= 'dead' then
		animation.is_animating = true
	else
		-- remove the dead coroutine from the list
		_qdequeue(animation.queue)

		if _qisempty(animation.queue) then
			animation.is_animating = false
		end
	end

	if mode == "TUTORIAL" then
		if btnp(k_left) and tutorial_page > 0 then tutorial_page -= 1 sfx(4) end
		if btnp(k_right) and tutorial_page < 4 then tutorial_page += 1 sfx(4) end
		if btnp(k_primary) then mode = last_mode sfx(5) end
		tutorial_offset = lerp(tutorial_offset, -tutorial_page*64, 0.3)

	-- flight mode - just watch the planes fly - zoom out to pan, zoom back in to switch between planes
	elseif mode == "FLIGHT" and animation.is_animating == false then
		plane_spawn_timer -= 1
		if plane_spawn_timer <= 0 then -- prevent overflowing the pool  and #active_planes < #planes	
			-- find a plane to spawn (one that is pooled)
			for i=1,#planes do
				local p = planes[i]
				if p.status == "POOLED" then
					local color = nil
					if tutorial_planes[1] > 0 then
						color = flight_type.BLUE
						tutorial_planes[1] -= 1
					elseif tutorial_planes[3] > 0 then
						color = flight_type.YELLOW
						tutorial_planes[3] -= 1
					elseif tutorial_planes[2] > 0 then
						color = flight_type.RED
						tutorial_planes[2] -= 1
					end

					p.activate(p, color)
					break
				end
			end

			-- slowly reduces plane spawn time until it's every 2 seconds
			plane_spawn_timer = 60 + max(0,flr(rnd()*150)-(points/10))
		end

		-- update the planes
		if not animation.is_animating then
			for p in all(planes) do
				if p.status ~= "POOLED" then p.update(p) end
			end
		end

	-- plan mode - no planes move, just set nodes on the current plane
	elseif mode == "PLAN" then
		if animation.is_animating then
			-- update the camera
			cam.update(cam)
			return
		end

		if last_plan_node ~= nil and dist(last_plan_node, cam.get_reticle(cam)) < 5 then 
			last_plan_node_hovered = true 
		else
			last_plan_node_hovered = false
		end

		if btnp(k_primary) then
			if last_plan_node_hovered then
				plan_plane.remove_last_node(plan_plane)
			else
				last_plan_node = cam.get_reticle(cam)
				plan_plane.add_node(plan_plane, last_plan_node.x-7, last_plan_node.y-7)
			end
		end
	end

	-- update the camera
	cam.update(cam)
end

function game_draw()
    -- set video mode to 128x128
    poke(0x5f2c, 0)
    -- set the screen to 0x80
    poke(0x5f55, 0x80)

    -- do your game draw operations here as normal
    cls()

	-- adjust the camera
	camera(cam.x, cam.y)

	-- draw the background
	if mode == "PLAN" then
		-- set ground to grayscale
		pal({[0]=0,129,128,128,134,133,134,134,136,132,4,133,140,141,11,7},1)
	else
		-- reset to default
		pal()
	end
	map(0, 0, 0, 0, 32, 32)

	for a in all(animation.draw_me) do
		a.draw(a)
	end

	-- plane drawing
	for pl in all(active_planes) do
		local p = planes[pl]
		p.shadows_draw(p)
	end

	for pl in all(active_planes) do
		local p = planes[pl]
		p.nodes_draw(p)
	end

	for pl in all(active_planes) do
		local p = planes[pl]
		p.draw(p)
	end

    resolve_particles()

	if mode == "PLAN" then
		-- airport indicator
		spr(9, hangar.x-4, hangar.y-4+sin(t())*2.5, 1, 1, false, true)

		-- current plane indicator
		spr(9, plan_plane.x+4, plan_plane.y-8+sin(t())*2.5, 1, 1, false, true)

		-- last plan node delete UI
		if last_plan_node ~= nil then
			-- show "X" if the camera reticle is close enough
			if last_plan_node_hovered then 
				sspr(117, 40, 3, 3, last_plan_node.x, last_plan_node.y)
			end
		end
	end
    -- end game draw operations

    -- set video mode to 64x64
    poke(0x5f2c, 3)

    -- set spritesheet to 0x80
    poke(0x5f54, 0x80)
    -- set screen to 0x60
    poke(0x5f55, 0x60)
    cls()
    
    -- draw screen to screen
    -- (originx,originy) is the coordinate center of the zoom. 
    -- (-32,-32) will put the center of the 128x128 canvas on the center of the 64x64 screen.
    local sx = -32 * (cam.zoom - 0.5) * 2
    local sy = -32 * (cam.zoom - 0.5) * 2
    local sw = 128 * cam.zoom
    local sh = 128 * cam.zoom
    -- treat the screen as a spritesheet when drawing to the screen (thanks video remapping)
	clip(0,0,64,64)
	camera()
    sspr(0, 0, 128, 128, sx, sy, sw, sh)

    -- video remap back to defaults (screen is the screen, spritesheet is the spritesheet)
    poke(0x5f54, 0x00)

	-- game ui
	draw_crosshair()
	draw_airport_arrow()

	if mode == "PLAN" then
		draw_plan_plane_arrow()
	end

	-- animations
	if (not _qisempty(animation.queue)) and costatus(_qpeek(animation.queue)) ~= 'dead' then
		coresume(_qpeek(animation.queue))
	end

	-- mode
	if mode ~= "GAMEOVER" and mode~= "TUTORIAL" then 
		draw_ui_overlay() 
	end

	if mode == "TUTORIAL" then
		rectfill(0, 0, 63, 63, 0)

		-- page 1 (0)
		print("welcome to", 12+tutorial_offset, 10, 7)
		print("oops airlines!", 5+tutorial_offset, 16, 7)
		local help_text = "help us!"
		for i=1,#help_text do
			print(help_text[i], 16+tutorial_offset+(i-1)*4, 26+sin(-t()*1.5+i/#help_text)*2, 8)
		end
		print("guide our", 14+tutorial_offset, 36, 7)
		print("planes back", 10+tutorial_offset, 42, 7)
		print("to the hangar", 6+tutorial_offset, 48, 7)

		-- page 2 (64)
		print("draw a path", 74+tutorial_offset, 14, 7)
		print("for each", 80+tutorial_offset, 20, 7)
		print("plane to fly", 72+tutorial_offset, 26, 7)
		print("use", 72+tutorial_offset, 36, 7)
		print(chr(139)..chr(145)..chr(148)..chr(131), 88+tutorial_offset, 36, 9)
		print("to get around", 70+tutorial_offset, 42, 7)

		-- page 3 (128)
		print("drop a node", 138+tutorial_offset, 12, 7)
		print("with ", 144+tutorial_offset, 18, 7)
		print(chr(142), 164+tutorial_offset, 18, 9)
		print("finish a path", 134+tutorial_offset, 28, 7)
		print("by dropping", 138+tutorial_offset, 34, 7)
		print("a node on", 142+tutorial_offset, 40, 7)
		print("the runway!", 138+tutorial_offset, 46, 7)

		-- page 4 (192)
		print("red planes", 204+tutorial_offset, 16, 8)
		print("fly slowest", 202+tutorial_offset, 22, 7)
		print("next is ", 200+tutorial_offset, 32, 7)
		print("blue", 232+tutorial_offset, 32, 12)
		print("then ", 202+tutorial_offset, 42, 7)
		print("yellow", 222+tutorial_offset, 42, 10)

		-- page 5 (256)
		print("score points", 264+tutorial_offset, 12, 7)
		print("each time a", 266+tutorial_offset, 18, 7)
		print("plane lands", 266+tutorial_offset, 24, 7)
		print("the game ends", 262+tutorial_offset, 34, 7)
		print("when planes", 266+tutorial_offset, 40, 7)
		print("collide!", 272+tutorial_offset, 46, 7)

		-- page controls
		rectfill(0, 57, 63, 63, 5)
		if tutorial_page > 0 then print(chr(139), 2, 58, 7) end -- left arrow symbol
		if tutorial_page < 4 then print(chr(145), 55, 58, 7) end -- right arrow symbol
		print(chr(142).." done", 19, 58, 7) -- confirm action symbol
	end

	-- point tracking
	resolve_score_particles()
end

function switch_to_plan(plane_to_track)
	mode = "PLAN"
	plan_plane = plane_to_track
	add(active_planes, plan_plane.idx)
	_qpush(animation.queue, cocreate(plan_text()))
	cam.focus_item(cam, plan_plane)
	cam.track_target = plan_plane
	sfx(8)
end

function switch_to_flight()
	mode = "FLIGHT"
	plan_plane = nil
	last_plan_node = nil
	_qpush(animation.queue, cocreate(fly_text()))
	sfx(7)
end

-- takes an x,y coordinate for where the collision happened
function switch_to_gameover(x, y)
	pal()
	mode = "GAMEOVER"
	local explosion = new_explosion(x, y)
	add(animation.update_me, explosion)
	cam.focus_item(cam, {x=x, y=y})
	cam.zoom_target = 1

	-- stop the music
	music(-1, 100)
	sfx(9)

	_qpush(animation.queue, cocreate(wait(2)))
	_qpush(animation.queue, cocreate(fade_to_black()))
	_qpush(animation.queue, cocreate(animate_gameover_screen()))
end

-- adds a plane to the game
local sprites = {16, 48, 80}
local colors = {8, 12, 10}
function add_plane(idx)
	local plane = {}

	plane.x = -100
	plane.y = -100
	plane.idx = idx

	-- choose what type of plane this will be
	plane.type = 1
	plane.sprite = sprites[1]
	plane.color = colors[1]
	plane.speed = 0.25
	plane.code = ""

	-- nodes are represented as a queue
	plane.nodes = _qnew()
	plane.next_node = nil
	plane.theta = nil

	plane.status = "POOLED" -- "POOLED", "IDLE", "ROUTING", "LANDING"
	plane.altitude = 80

	plane.smoke = {}

	-- crude implementation of quadtrees - 256x256 area broken into cels of 32x32
	plane.zone = -999

	plane.add_node = function(self, x, y)
		_qpush(self.nodes, {x=x, y=y})
		if (self.next_node == nil) then
			self.next_node = _qpeek(plane.nodes)
			self.theta = angle(self, self.next_node)
		end

		-- check if we've clicked the airfield
		if is_in_landing_zone({x=x+7, y=y+7}) then
			switch_to_flight()
		else
			sfx(5)
		end
	end

	plane.remove_last_node = function(self)
		_qpop(self.nodes)
		local n = _qpeeklast(self.nodes)
		-- adjust for offset
		if n ~= nil then
			last_plan_node.x, last_plan_node.y = n.x+7, n.y+7
		else
			last_plan_node = nil
			self.next_node = nil
		end

		sfx(6)
	end

	plane.activate = function(self, color)
		self.status = "IDLE"

		local pos = flr(rnd() * 160)+32
		local opos = rnd({32, 192})
		local x_or_y = rnd()

		if x_or_y < 0.5 then
			self.x = pos
			self.y = opos
		else
			self.x = opos
			self.y = pos
		end

		local found_valid_pos = false
		while not found_valid_pos do
			local is_any_plane_too_close = false
			for i=1,#active_planes do
				-- don't spawn close to other planes
				local other_plane = planes[active_planes[i]]
				if dist(self, other_plane) < 30 then
					is_any_plane_too_close = true
					break
				end
			end

			-- don't spawn close to the airport
			if dist(self, airport) < 40 then is_any_plane_too_close = true end

			if is_any_plane_too_close then
				pos = flr(rnd() * 160)+32
				opos = rnd({32, 192})
				x_or_y = rnd()
		
				if x_or_y < 0.5 then
					self.x = pos
					self.y = opos
				else
					self.x = opos
					self.y = pos
				end
			else
				found_valid_pos = true
			end
		end

		self.theta = angle(self, {x=128, y=128})

		local type = color or rnd({1, 2, 3})
		self.type = type
		self.sprite = sprites[type]
		self.color = colors[type]
		self.speed = 0.25*type
		self.code = flight_designations[type]..rnd(numerals)..rnd(numerals)..rnd(numerals)..rnd(numerals)

		self.altitude = 80
		self.smoke = {}
	end

	plane.update = function(self)
		-- check if we're landing
		local plane_center = {x=flr(self.x)+7,y=flr(self.y)+7}
		if self.status == "ROUTING" and is_in_landing_zone(plane_center) then
			self.status = "LANDING"
		end

		if self.status == "ROUTING" then
			-- check if we reached our next node
			if dist(self, self.next_node) < self.speed then
				local last_node = _qdequeue(self.nodes) -- remove the current entry
				self.x, self.y = last_node.x, last_node.y
				self.next_node = _qpeek(self.nodes)
				if self.next_node ~= nil then 
					self.theta = angle(self, self.next_node) 
				end
				
			end
			
			-- move towards destination
			self.x -= cos(self.theta) * self.speed
			self.y -= sin(self.theta) * self.speed

			-- check for collisions
			self.zone = flr(self.x / 32) * 8 + flr(self.y / 32)
			for pidx in all(active_planes) do
				if pidx ~= self.idx then -- don't try to collide with ourself
					local p = planes[pidx]
					if p.zone == self.zone or -- neighbor zone checks
					   p.zone == self.zone - 1 or
					   p.zone == self.zone + 1 or
					   p.zone == self.zone - 8 or
					   p.zone == self.zone + 8 or
					   p.zone == self.zone - 9 or
					   p.zone == self.zone - 7 or
					   p.zone == self.zone + 9 or
					   p.zone == self.zone + 7 then

						local d = dist({x=self.x+8,y=self.y+8}, {x=p.x+8,y=p.y+8})
						if d < 10 then
							local xsign, ysign = 0, 0
							local theta = angle({x=self.x+8,y=self.y+8}, {x=p.x+8,y=p.y+8})
							local midx, midy = p.x+8+cos(theta)*(d/2),p.y+8+sin(theta)*(d/2)
							switch_to_gameover(midx, midy)
						end
					end
				end
			end

		elseif self.status == "LANDING" then
			self.zone = -999

			self.altitude -= 1
			self.x += 0.33
			if self.altitude > 20 then self.y += 0.1237 end

			if self.altitude <= 0 then
				self.status = "POOLED" -- hold onto this object but wait out of sight
				self.x = -100
				self.y = -100
				self.nodes = _qnew()
				self.next_node = nil
				self.theta = nil
				del(active_planes, self.idx)

				cam.set_new_target(cam, self.idx)

				points += point_lookup[self.type]
				create_score_particle(point_lookup[self.type])
				flights_saved[self.type] += 1
			end
		
		elseif self.status == "IDLE" then
			-- fly in a given direction
			-- if we make it into the play area, request game focus, switch to planning mode, and prompt for a route
			self.x -= cos(self.theta) * self.speed
			self.y -= sin(self.theta) * self.speed

			if self.x >= 32 and self.x <= 192 and self.y >= 32 and self.y <= 192 then
				-- activate PLAN mode for this plane
				self.status = "ROUTING"
				switch_to_plan(self)
			end
		end
	end

	plane.draw = function(self)
		-- don't draw pooled objects
		if self.status == "POOLED" then return end

		-- landing sequence
		if self.status == "LANDING" then
			local s = max(self.altitude,20)/80
			sspr(16, 8+(self.type-1)*16, 16, 16, self.x, self.y, 16*s, 16*s)
			return
		end

		-- smoke
		if mode == "FLIGHT" then
			for i=1,2 do
				add(self.smoke, {
					x=self.x+8,
					y=self.y+8,
					r=3,
					dx=rnd(2)*cos(self.theta),
					dy=rnd(2)*sin(self.theta),
					dr=function(p) return p.r - 0.15 end,
					c=function(p) return 7 end,
					ttl=10
				})
			end
		end

		if #self.smoke > 0 then
			for i=#self.smoke,1,-1 do
				local p = self.smoke[i]
				if mode == "FLIGHT" then
					p.ttl -= 1
					p.x += p.dx
					p.y += p.dy
					p.r = p.dr(p)

					if p.ttl <= 0 then deli(self.smoke, i) end
				end

				circfill(p.x, p.y, p.r, p.c(p))
			end
		end

		-- plane
		if self.theta <= 0.0625 or self.theta > 0.9375 then -- right
			spr(self.sprite + 2, self.x, self.y, 2, 2, true)
		elseif self.theta > 0.0625 and self.theta <= 0.1875 then -- down right
			spr(self.sprite + 4, self.x, self.y, 2, 2, true, true)
		elseif self.theta > 0.1875 and self.theta <= 0.3125 then -- down
			spr(self.sprite, self.x, self.y, 2, 2, true, true)
		elseif self.theta > 0.3125 and self.theta <= 0.4375 then -- down left
			spr(self.sprite + 4, self.x, self.y, 2, 2, false, true)
		elseif self.theta > 0.4375 and self.theta <= 0.5625 then -- left
			spr(self.sprite + 2, self.x, self.y, 2, 2, false)
		elseif self.theta > 0.5625 and self.theta <= 0.6875 then -- up left
			spr(self.sprite + 4, self.x, self.y, 2, 2, false, false)
		elseif self.theta > 0.6875 and self.theta <= 0.8125 then -- up
			spr(self.sprite, self.x, self.y, 2, 2, true)
		elseif self.theta > 0.8125 and self.theta <= 0.9375 then -- up right
			spr(self.sprite + 4, self.x, self.y, 2, 2, true)
		end
	end

	plane.nodes_draw = function(self)
		if self.status ~= "ROUTING" then return end
		if self.next_node == nil then return end

		-- draw unfocused paths as gray, and the focused path in the plane's color
		local draw_col = 6
		if mode == "PLAN" and plan_plane.idx == self.idx then draw_col = self.color end
		if cam.track_target ~= nil and cam.track_target.idx == self.idx then draw_col = self.color end

		-- disregard focus path colors if the option is off
		if focus_paths == false then draw_col = self.color end

		-- draw current heading
		line(self.x+8, self.y+8, self.next_node.x+8, self.next_node.y+8, draw_col)
		circfill(self.next_node.x+8, self.next_node.y+8, 2, draw_col)

		print(#self.nodes, 0, 0, 7)

		-- draw future headings
		local cursor = self.next_node
		for i=self.nodes.first+2,self.nodes.last do
			local n = self.nodes[i]
			line(cursor.x+8, cursor.y+8, n.x+8, n.y+8, draw_col)
			circfill(n.x+8, n.y+8, 2, draw_col)
			cursor = n
		end
	end

	plane.shadows_draw = function(self)
		local s = max(self.altitude,20)/80
		circfill(self.x+8*s, self.y+16*s, 3.5-(80-self.altitude)/13, 1)
	end

	add(planes, plane)
end

function draw_airport_arrow()
	local cx,cy = cam.x + 64, cam.y + 64 -- center of the screen
	local ax,ay = hangar.x, hangar.y -- center of airport runway

	local theta = atan2(ax-cx, ay-cy)
	local distance = sqrt((ax-cx)*(ax-cx)+(ay-cy)*(ay-cy))

	-- if the hangar is on the screen, just don't show
	if distance / (1/cam.zoom) <= 32 then return end

	local sy = sin(theta) * 20 + 28
	local sx = cos(theta) * 20 + 28

	if theta > 0.875 or theta < 0.125 then
		spr(8, sx, sy)
	elseif theta <= 0.875 and theta >= 0.5 then
		spr(9, sx, sy, 1, 1, false, true)
	elseif theta >= 0.125 and theta <= 0.5 then
		spr(9, sx, sy)
	end
end

function draw_plan_plane_arrow()
	local cx,cy = cam.x + 64, cam.y + 64 -- center of the screen
	local ax,ay = plan_plane.x+8, plan_plane.y+8 -- center of plan_plane

	local theta = atan2(ax-cx, ay-cy)
	local distance = sqrt((ax-cx)*(ax-cx)+(ay-cy)*(ay-cy))

	-- if the plane is on the screen, just don't show
	if distance / (1/cam.zoom) <= 32 then return end

	local sy = sin(theta) * 20 + 28
	local sx = cos(theta) * 20 + 28

	if theta > 0.875 or theta <= 0.125 then
		spr(8, sx, sy)
	elseif theta <= 0.875 and theta > 0.625 then
		spr(9, sx, sy, 1, 1, false, true)
	elseif theta <= 0.625 and theta > 0.375 then
		spr(8, sx, sy, 1, 1, true)
	elseif theta <= 0.375 and theta > 0.125 then
		spr(9, sx, sy)
	end
end

function draw_crosshair()
	if mode == "PLAN" then 
		-- about to end planning phase
		local reticle = cam.get_reticle(cam)
		if is_in_landing_zone(reticle) then
			spr(15, 28, 28)
			spr(95, 38, 28)
			return
		end

		-- about to delete a node
		if last_plan_node_hovered then
			spr(14, 28, 28) 
			return
		end

		-- regular
		spr(10, 28, 28) 
	end
end

function draw_flight_speed(type)
	if type == flight_type.RED then
		-- draw one triangle
		print(chr(23), 4, 1, 8)
	elseif type == flight_type.BLUE then
		-- draw two triangles
		print(chr(23), 2, 1, 12)
		print(chr(23), 5, 1, 12)
	else
		-- draw three triangles
		print(chr(23), 1, 1, 10)
		print(chr(23), 4, 1, 10)
		print(chr(23), 7, 1, 10)
	end
end

function draw_ui_overlay()
	-- top hud
	rectfill(0, 0, 63, 6, 0)

	if mode == "FLIGHT" then
		if cam.track_target ~= nil and cam.track_target.color ~= nil then
			draw_flight_speed(cam.track_target.type)
			print(cam.track_target.code, 11, 1, 7)
		end
	else
		draw_flight_speed(plan_plane.type)
		print(plan_plane.code, 11, 1, 7)
	end

	local points_str = tostr(points)..chr(146)
	print(points_str, 61-#points_str*4, 1, 7)

	-- bottom hud
	rectfill(0, 57, 63, 63, 0)

	if mode == "FLIGHT" then
		spr(11, 0, 56)
		print(flr(plane_spawn_timer/30), 9, 58, 7)

		if cam.zoom_target == 1 then
			print(chr(139)..chr(145)..chr(151), 41, 58, 7)
		else -- 0.5
			print(chr(139)..chr(145)..chr(148)..chr(131)..chr(151), 25, 58, 7)
		end
	else -- "PLAN"
		spr(12, 0, 56)
		print(chr(139)..chr(145)..chr(148)..chr(131)..chr(142)..chr(151), 17, 58, 7)
	end
end

function reset_game()
	particles = {}

	for i=1,10 do
		planes[i].x = -100
		planes[i].y = -100
		planes[i].zone = -999
		planes[i].status = "POOLED"
		planes[i].nodes = _qnew()
		planes[i].next_node = nil
		planes[i].theta = nil
		planes[i].altitude = 80
		planes[i].smoke = {}
	end

	active_planes = {}
	tutorial_planes = { 4, 3, 2 }
	plan_plane = nil
	last_plan_node = nil
	last_plan_node_hovered = false

	points = 0
	flights_saved = {0, 0, 0}

	cam = new_camera()

	animation.frame = 1
	animation.update_me = {}
	animation.draw_me = {}

	add(animation.update_me, flags)
	add(animation.draw_me, flags)

	mode = "FLIGHT"
	plane_spawn_timer = 30
	animation.queue = _qnew()
	_qpush(animation.queue, cocreate(fade_in()))

	current_update = game_update
	current_draw = game_draw

	music(0, 100, 0b0111)
end

-->8
-- splashscreen

local splash_frame = 0

function splashscreen_update()
	if splash_frame == 0 then
		sfx(2)
	end

	splash_frame += 1

	if splash_frame > 120 then
		current_update = game_update
		current_draw = game_draw
		splash_frame = 0
		-- play noodle cafe by fettuccini
		music(0, 100, 0b0111)
	end
end

function splashscreen_draw()
	cls()

	if splash_frame > 60 then
		print("bgm by", 20, 10, 7)
		print("fettuccini", 12, 16, 7)

		print("made for", 16, 28, 7)
		print("lowrezjam 2024", 4, 34, 7)

		-- pico8 logo
		sspr(99, 123, 29, 5, 18, 46)
	else
		print("a game by", 14, 22, 7)
		print("fletch",  20, 28, 7)
		spr(7, 28, 34)
	end
end

-->8
-- gameover state
local page = 0
local offset = 0
local bgplanes = {{x=-16,smoke={}}, {x=-48,smoke={}}, {x=-80,smoke={}}, {x=-112,smoke={}}}

function gameover_update()
	if btnp(k_left) and page > 0 then page -= 1 sfx(4) end
	if btnp(k_right) and page < 3 then page += 1 sfx(4) end

	if btnp(k_primary) then 
		reset_game() 
		bgplanes = {{x=-16,smoke={}}, {x=-48,smoke={}}, {x=-80,smoke={}}, {x=-112,smoke={}}}
	end

	-- update plane positions in background
	for i=1,#bgplanes do
		-- position
		bgplanes[i].x += 0.7
		if bgplanes[i].x > 63 then
			bgplanes[i].x = -16
		end

		-- smoke
		for j=1,2 do
			add(bgplanes[i].smoke, {
				x=bgplanes[i].x-1,
				y=(i-1)*16+8,
				r=3,
				dx=rnd()*cos(0.5+rnd(0.2)-0.1),
				dy=rnd()*sin(0.5+rnd(0.2)-0.1),
				dr=function(p) return p.r - 0.15 end,
				ttl=10
			})
		end
	end

	offset = lerp(offset, -page*64, 0.2)
end

function gameover_draw()
	-- background
	cls()

	-- draw planes in background
	for i=1,#bgplanes do
		-- plane
		spr(112, bgplanes[i].x, (i-1)*16, 2, 2)

		-- smoke
		for j=#bgplanes[i].smoke,1,-1 do
			local p = bgplanes[i].smoke[j]
			p.ttl -= 1
			p.x += p.dx
			p.y += p.dy
			p.r = p.dr(p)

			if p.ttl <= 0 then deli(bgplanes[i].smoke, j) end

			circfill(p.x, p.y, p.r, 1)
		end
	end

	-- title
	sspr(0, 94, 64, 34, 0, 0)

	-- score
	local pstr = tostr(points)
	print("score", 22+offset, 36, 7)
	print(pstr, 32-(#pstr*4/2)+offset, 42, 7)

	-- red flights
	local redfl = tostr(flights_saved[flight_type.RED])
	print("red", 90+offset, 36, 7)
	print(redfl, 96-(#redfl*4/2)+offset, 42, 7)

	-- blue flights
	local bluefl = tostr(flights_saved[flight_type.BLUE])
	print("blue", 152+offset, 36, 7)
	print(bluefl, 160-(#bluefl*4/2)+offset, 42, 7)

	-- yellow flights
	local yellowfl = tostr(flights_saved[flight_type.YELLOW])
	print("yellow", 212+offset, 36, 7)
	print(yellowfl, 224-(#yellowfl*4/2)+offset, 42, 7)

	-- try again
	print(chr(142), 25, 58, 7)
	spr(13, 33, 56)

	-- pagination buttons
	if page > 0 then print(chr(139), 0, 40+sin(t()/4)*3) end -- left
	if page < 3 then print(chr(145), 57, 40+sin(t()/4)*3) end -- right
end

-->8
-- camera functions

function new_camera()
	local c = {}

	c.x = 0
	c.y = 0
	c.speed = 3

	c.is_tracking = false
	c.track_target = nil
	c.item_needs_focus = nil

	c.zoom = 1
	c.zoom_target = 1
	c.last_zoom_target = 1

	c.update = function(self)
		-- item needs immediate focus, so we ignore everything else
		if self.item_needs_focus ~= nil then
			local lastcamx, lastcamy = self.x, self.y
			local offset = 64
			if self.item_needs_focus.idx ~= nil then offset = 56 end
			local newcamx = lerp(self.x, self.item_needs_focus.x-offset, 0.1)
			local newcamy = lerp(self.y, self.item_needs_focus.y-offset, 0.1)

			self.x = newcamx
			self.y = newcamy

			diffx, diffy = abs(lastcamx - self.x), abs(lastcamy - self.y)

			if diffx < 0.25 and diffy < 0.25 then self.item_needs_focus = nil end
			return
		end

		-- if its gameover, then don't allow the user to pan the camera
		if mode == "GAMEOVER" or mode == "TUTORIAL" then return end

		-- we are watching a plane fly at the moment
		if self.is_tracking then
			if self.track_target == nil then self.track_target = hangar end

			-- lerp to the tracked target
			local ttx, tty = self.track_target.x-56, self.track_target.y-56
			local newcamx = lerp(self.x, ttx, 0.2)
			local newcamy = lerp(self.y, tty, 0.2)

			-- snap to tracked target if we're close enough
			if dist(self, {x=newcamx, y=newcamy}) < 0.5 then
				self.x = ttx
				self.y = tty
			else
				self.x = newcamx
				self.y = newcamy
			end

			-- rotate through the list of active planes for tracking
			if btnp(k_left) then
				if #active_planes > 1 then
					if self.track_target == nil then self.track_target = planes[active_planes[1]] return end

					local cursor = 1
					while cursor ~= #active_planes do
						if planes[active_planes[cursor]].idx == self.track_target.idx then break end
						cursor += 1
					end

					cursor -= 1
					if cursor == 0 then cursor = #active_planes end

					self.track_target = planes[active_planes[cursor]]
					sfx(4)
				else sfx(3) end
			end

			if btnp(k_right) then
				if #active_planes > 1 then
					if self.track_target == nil then self.track_target = planes[active_planes[#active_planes]] return end

					local cursor = 1
					while cursor ~= #active_planes do
						if planes[active_planes[cursor]].idx == self.track_target.idx then break end
						cursor += 1
					end

					cursor += 1
					if cursor > #active_planes then cursor = 1 end

					self.track_target = planes[active_planes[cursor]]
					sfx(4)
				else sfx(3) end
			end
		end
		
		-- pan the camera with arrow keys
		if not self.is_tracking then
			if btn(k_left) and self.x > -30 then
				self.x -= self.speed
			end
	
			if btn(k_right) and self.x < 158 then
				self.x += self.speed
			end
	
			if btn(k_up) and self.y > -30 then
				self.y -= self.speed
			end
	
			if btn(k_down) and self.y < 158 then
				self.y += self.speed
			end
		end

		-- handle zooming
		if btn(k_secondary) then
			self.zoom_target = 0.5
			self.is_tracking = false

			if self.x < 0 then self.x = lerp(self.x, 0, 0.2) end
			if self.x > 128 then self.x = lerp(self.x, 128, 0.2) end
			if self.y < 0 then self.y = lerp(self.y, 0, 0.2) end
			if self.y > 128 then self.y = lerp(self.y, 128, 0.2) end

			if self.zoom_target ~= self.last_zoom_target then sfx(0) end
		else
			self.zoom_target = 1
			if mode == "FLIGHT" then self.is_tracking = true end
			if self.zoom_target ~= self.last_zoom_target then sfx(1) end
		end

		self.zoom = lerp(self.zoom, self.zoom_target, 0.2)
		self.last_zoom_target = self.zoom_target
	end

	-- draw the camera to a location, and stop being drawn towards the tracked target
	c.focus_item = function(self, item)
		self.item_needs_focus = item
		self.is_tracking = false
	end

	c.set_new_target = function(self, idx)
		if #active_planes == 0 then
			self.track_target = hangar
		elseif self.track_target.idx == idx then
			self.track_target = planes[active_planes[1]]
		end
	end

	-- gets the center of the screen
	c.get_reticle = function(self)
		return {x=flr(self.x)+63, y=flr(self.y)+63}
	end

	return c
end

function new_explosion(x, y)
	local e = {}

	e.x = x
	e.y = y

	e.update = function(self)
		-- play explosion effects
		for i=1,2 do
			add(particles, {
				x=self.x,
				y=self.y,
				r=8,
				dx=rnd(2)-1,
				dy=rnd(2)-1,
				dr=function(p) return p.r/1.075 end,
				c=function(p) return min(flr(((8-p.r)/(8))*4)+7,10) end,
				ttl=30
			},1)
		end
	end

	return e
end

-->8
-- animation functions

-- basic lerp <3
function lerp(from, to, amount)
    local dist = to - from
    if abs(dist) <= 0.01 then return to end
    return from + (dist * amount)
end

-- @Werxzy: https://www.lexaloffle.com/bbs/?uid=80204
function smooth_move(x, ax, dx, acc, damp, lim)
    local dif = x - ax
    dx += dif * acc -- accelerate
    ax += dx -- move
    dx *= damp -- dampen
	-- limit, not always necessary, can replace with a default value
    if abs(dif) < lim and abs(dx) < lim then 
        return x, 0
    end
    return ax, dx
end

function new_flags()
	local flags = {}

	flags.num = 1

	flags.update = function(self)
		if animation.frame % 5 == 0 then
			self.num = self.num % 6 + 1
		end
	end

	flags.draw = function(self)
		spr(self.num, 194, 116)
		spr(self.num, 194, 140)
	end

	return flags
end

-- returns a function to be used with cocreate()
function fly_text()
	return function()
		input_blocker = true
		local frames = 0
		local gravity = 0.2
		local y = {64, 64, 64, 64}
		local dy = {-3.5, -3.5, -3.5, -3.5}
		while dy[4] < 0 or y[4] < 64 do -- wait for the last letter
			frames += 1

			-- simulate gravity
			if frames > 0 then y[1] += dy[1] dy[1] += gravity end
			if frames > 5 then y[2] += dy[2] dy[2] += gravity end
			if frames > 10 then y[3] += dy[3] dy[3] += gravity end
			if frames > 15 then y[4] += dy[4] dy[4] += gravity end

			smol_letters.f(23, y[1])
			smol_letters.l(27, y[2])
			smol_letters.y(31, y[3])
			smol_letters.emphasis(35, y[4])

			yield()
		end
		input_blocker = false
	end
end

function plan_text()
	return function()
		input_blocker = true
		local frames = 0
		local gravity = 0.2
		local y = {64, 64, 64, 64, 64}
		local dy = {-3.5, -3.5, -3.5, -3.5, -3.5}
		while dy[5] < 0 or y[5] < 64 do -- wait for the last letter
			frames += 1

			-- simulate gravity
			if frames > 0 then y[1] += dy[1] dy[1] += gravity end
			if frames > 5 then y[2] += dy[2] dy[2] += gravity end
			if frames > 10 then y[3] += dy[3] dy[3] += gravity end
			if frames > 15 then y[4] += dy[4] dy[4] += gravity end
			if frames > 20 then y[5] += dy[5] dy[5] += gravity end

			smol_letters.p(21, y[1])
			smol_letters.l(25, y[2])
			smol_letters.a(29, y[3])
			smol_letters.n(33, y[4])
			smol_letters.emphasis(37, y[5])

			yield()
		end
		input_blocker = false
	end
end

function wait(seconds)
	return function()
		input_blocker = true
		local frame = 30 * seconds
		while frame > 0 do
			frame -= 1
			yield()
		end
		input_blocker = false
	end
end

function fade_to_black()
	return function()
		input_blocker = true
		local r = 100
		while r > 1 do
			yield()
			r = lerp(r, 0, 0.2)
			poke(0x5f34,0x2)
			circfill(32,32,r,0 | 0x1800)
			poke(0x5f34, peek(0x5f34 & ~0x2))
		end
		input_blocker =  false
	end
end

function fade_in()
	return function()
		input_blocker = true
		rectfill(0, 0, 63, 63, 0)

		local r = 0
		while r < 60 do
			yield()
			r += 3
			poke(0x5f34,0x2)
			circfill(32,32,r,0 | 0x1800)
			poke(0x5f34, peek(0x5f34 & ~0x2))
		end
		input_blocker = false
	end
end

function animate_gameover_screen()
	return function()
		input_blocker = true

		local titley, scorey = -25, 64
		local titledy, scoredy = 0, 0
		local frame = 0
		rectfill(0, 0, 63, 63, 0)
		while frame < 60 do
			yield()

			local lasttitley, lastscorey = titley, scorey

			titley, titledy = smooth_move(0, titley, titledy, 0.2, 0.7, 0.1)
			scorey, scoredy = smooth_move(36, scorey, scoredy, 0.2, 0.7, 0.1)

			-- background
			rectfill(0, 0, 63, 63, 0)

			-- title
			sspr(0, 94, 64, 34, 0, titley)

			-- score
			local pstr = tostr(points)
			print("score", 22, scorey, 7)
			print(pstr, 32-(#pstr*4/2), scorey+6, 7)

			frame += 1
		end

		current_update = gameover_update
		current_draw = gameover_draw
		input_blocker = false
	end
end

-->8
-- helper functions

-- vector maths
-- assumes a and b are tables with members x and y
-- https://www.lexaloffle.com/bbs/?tid=36059
function dist(a, b)
	local dx = a.x-b.x
	local dy = a.y-b.y
	local maskx,masky=dx>>31,dy>>31
	local a0,b0=(dx+maskx)^^maskx,(dy+masky)^^masky
	if a0>b0 then
		return a0*0.9609+b0*0.3984
	end
	return b0*0.9609+a0*0.3984
end

-- assumes a and b are tables with members x and y
function angle(a, b)
	return atan2(a.x-b.x, a.y-b.y)
end

-- point is a table with form {x=0,y=0}
function is_in_landing_zone(point)
	if point.x > airport.x+6 and
	   point.x <= airport.x+12 and
	   point.y > airport.y and
	   point.y <= airport.y+15 then
			return true
	end

	return false
end

-- particle system
function resolve_particles()
    if #particles < 1 then return end

    for i=#particles,1,-1 do
        local p = particles[i]
        p.ttl -= 1
        p.x += p.dx
        p.y += p.dy
        p.r = p.dr(p)

        circfill(p.x, p.y, p.r, p.c(p))

        if p.ttl <= 0 then deli(particles, i) end
    end
end

function resolve_score_particles()
	if #score_particles < 1 then return end

	for i=#score_particles,1,-1 do
		local sp = score_particles[i]

		sp.x = lerp(sp.x, sp.fx, 0.2)

		rectfill(sp.x-1, sp.y-1, 63, sp.y+5, 0)
		print(sp.text, sp.x, sp.y, 7)

		if sp.x == sp.fx then deli(score_particles, i) end
	end
end

function create_score_particle(num_points)
	local ptstr = tostr(num_points)
	add(score_particles, {
		x=64,
		y=#score_particles*6+7,
		fx=64-#ptstr*4-7,
		text=ptstr..chr(146)
	})
end

function rounded_rect(x1, y1, x2, y2, r, c)
    circfill(x1+r, y1+r, r, c)
    circfill(x2-r, y1+r, r, c)
    circfill(x1+r, y2-r, r, c)
    circfill(x2-r, y2-r, r, c)
    rectfill(x1+r, y1, x2-r, y2, c)
    rectfill(x1, y1+r, x2, y2-r, c)
end

function btn(num)
	if input_blocker then return end
	return _btn(num)
end

function btnp(num)
	if input_blocker then return end
	return _btnp(num)
end

-- https://www.lua.org/pil/11.4.html
-- basic queue implementation
function _qnew()
	return {first=0, last=0}
end

function _qisempty(queue)
	return queue.first == queue.last
end

function _qpush(queue, value)
	local last = queue.last + 1
	queue.last = last
	queue[last] = value
end

function _qpeek(queue)
	return queue[queue.first+1]
end

function _qpeeklast(queue)
	if queue.first > queue.last then return nil end
	return queue[queue.last]
end

-- stack
function _qpop(queue)
	local last = queue.last
	if queue.first > last then return nil end
	local value = queue[last]
	queue[last] = nil
	queue.last -= 1
	return value
end

-- queue
function _qdequeue(queue)
	local first = queue.first+1
	if first > queue.last then return nil end
	local value = queue[first]
	queue[first] = nil
	queue.first += 1
	return value
end

__gfx__
0000000077777000777777007777777077707770777000007777000000000070000000000008800000000000000000000000000000000000000000000e0000e0
0000000068887700688887706887887068777870687777706887700000007700000008000088880000f00f0000007000000070000000000008800880ee0000ee
007007006888877068887870688877706887877068877870688877700007070000000880088888800ff00ff07007700000077700070777000800008000000000
000770006887787068877770688870006888770068888770688888707007777700000888000000000000000077777770007777700770007000000000000ee000
000770006777777067770000677770006788700067887700677777707777770000000888000000000000000077777777077777000777007000000000000ee000
007007006000000060000000600000006777700067777000600000000777700000000880000000000ff00ff07007700070777000000000700800008000000000
0000000060000000600000006000000060000000600000006000000000707000000008000000000000f00f0000007000700700000077770008800880ee0000ee
0000000060000000600000006000000060000000600000006000000000777700000000000000000000000000000070007770000000000000000000000e0000e0
000000777700000000007770000000000000000000000000bbb3333333bbbbbbbbb3333333bbbbbbbbb3333333bbbbbbbbb3333333bbbbbbbbb3333333bbbbbb
000007788770000000007277000000000000000000777700bb333333333bbbbbbb333333333bbbbbbb333333333bbbbbbb333333333bbbbbbb333333333bbbbb
000007866870000000007227770000000000000007788770b3333bbb332222222222222222222222222222bb3333bbbbb3333bbb3333bbbbb3333bbb3333bbbb
0000076666700000777077222770000000777777776688703333bbbbb244444444444444444444444444442bb3333bbb3333bbbbb3333bbb3333bbbbb3333bbb
000077688677000072700772227700000072222228866870333bbbbb24444444444444444444444444444442bb333333333bbbbbbb333333333bbbbbbb333333
00077288882770007277777722277770007722228888677033bbbbb2444444444444444444444444444444442bb3333333bbbbbbbbb3333333bbbbbbbbb33333
0077228888227700722772288886687700077728888877003bbbbb24444bbbbbbbbbbbbbbbbbbbbbbbbbb44442bb33333bbbbbbbbbbb33333bbbbbbbbbbb3333
007222888822277072222222888866870000078288827000bbbb324444bbbbbbbbbb33333bbbbbbbbbbbbb44442bbbbb77777777777777777777777777777777
077227822872277072222222888866870777772228227000bbb324444bbbbbbbbbb3333333bbbbbbbbb3bbb44442bbbb55555555555555555555555555555555
772277222277227772277228888668770722722282227000bb324444bbbbbbbbbb333333333bbbbbbb333bbb44442bbb57775555555555555555555555555555
722777222277722772777777222777700772222777227000b324444bbb33bbbbb3333bbb3333bbbbb3333bbbb44442bb57775555555555555556666666665555
777707722770777772700772227700000077227707227000332444bbb3333bbb3333bbbbb3333bbb3333bbbbbb4442bb555555555555555555566ddd6ddd6555
000007722770000077707722277000000007722707727000332444bbbb333333333bbbbbbb333333333bbbbbbb4442335777555555555555555666ddd6ddd655
000777222277700000007227770000000000772700777000332444bbbbb3333333bbbbbbbbb3333333bbbbbbbb44423357775555555555555551166ddd6ddd65
0007222222227000000072777000000000000777000000003b2444bbbbbb33333bbbbbbbbbbb33333bbbbbbbbb44423355555555555555555551116ddd6ddd65
000777777777700000007770000000000000000000000000bb2444bb3bbbbbbbbbbb33333bbbbbbbbbbb3333bb4442bb57775557777777777551116ddd6ddd65
000000777700000000007770000000000000000000000000bb2444bb33bbbbbbbbb3333333bbbbbbbbb33333bb4442bb57775557777777777551116ddd6ddd65
0000077cc770000000007177000000000000000000777700bb2444bb333bbbbbbb333333333bbbbbbb333333bb4442bb55555555555555555551116ddd6ddd65
000007c66c700000000071177700000000000000077cc770b32444bb3333bbbbb3333bbb3333bbbbb3333bbbbb4442bb57775555555555555551166ddd6ddd65
00000766667000007770771117700000007777777766cc70332444bbb3333bbb3333bbbbb3333bbb3333bbbbbb4442bb5777555555555555555666ddd6ddd655
0000776cc67700007170077111770000007111111cc66c70332444bbbb333333333bbbbbbb333333333bbbbbbb444233555555555555555555566ddd6ddd6555
000771cccc177000717777771117777000771111cccc6770332444bbbbb3333333bbbbbbbbb3333333bbbbbbbb44423357775555555555555556666666665555
007711cccc1177007117711cccc66c770007771ccccc77003b2444bbbbbb33333bbbbbbbbbbb33333bbbbbbbbb44423357775555555555555555555555555555
007111cccc11170071111111cccc66c7000007c1ccc17000bb2444bb3bbbbbbbbbbb33333bbbbbbbbbbb3333bb4442bb55555555555555555555555555555555
077117c11c71177071111111cccc66c7077777111c117000bb2444bb33bbbbbbbbb3333333bbbbbbbbb33333bb4442bb77777777777777777777777777777777
77117711117711777117711cccc66c7707117111c1117000bb2444bb333bbbbbbb333333333bbbbbbb333333bb4442bbbb333333333bbbbbbb333333333bbbbb
711777111177711771777777111777700771111777117000b32444bb3333bbbbb3333bbb3333bbbbb3333bbbbb4442bbb3333bbb3333bbbbb3333bbb3333bbbb
777707711770777771700771117700000077117707117000332444bbb3333bbb3333bbbbb3333bbb3333bbbbbb4442bb3333bbbbb3333bbb3333bbbbb3333bbb
000007711770000077707711177000000007711707717000332444bbbb333333333bbbbbbb333333333bbbbbbb444233333bbbbbbb333333333bbbbbbb333333
000777111177700000007117770000000000771700777000332444bbbbb3333333bbbbbbbbb3333333bbbbbbbb44423333bbbbbbbbb3333333bbbbbbbbb33333
0007111111117000000071770000000000000777000000003b2444bbbbbb33333bbbbbbbbbbb33333bbbbbbbbb4442333bbbbbbbbbbb33333bbbbbbbbbbb3333
000777777777700000007770000000000000000000000000bb2444bb3bbbbbbbbbbb33333bbbbbbbbbbb3333bb4442bbbbbb33333bbbbbbbbbbb33333bbbbbbb
000000777700000000007770000000000000000000000000bb2444bb33bbbbbbbbb3333333bbbbbbbbb33333bb4442bb777777777777777777777f0f000000ee
0000077aa770000000007977000000000000000000777700bb2444bb333bbbbbbb333333333bbbbbbb333333bb4442bb7111711171117177717170f0000000ee
000007a66a700000000079977700000000000000077aa770b32444bb3333bbbbb3333bbb3333bbbbb3333bbbbb4442bb717177177171717771117f0f00000eee
00000766667000007770779997700000007777777766aa70332444bbb3333bbb3333bbbbb3333bbb3333bbbbbb4442bb71117717711771777771700000000ee0
0000776aa67700007970077999770000007999999aa66a70332444bbbb333333333bbbbbbb333333333bbbbbbb444233717171117171711171117000ee00eee0
000779aaaa977000797777779997777000779999aaaa67703324444bbbb3333333bbbbbbbbb3333333bbbbbbb4444233777777777777777777777770eee0ee00
007799aaaa997700799779aaaaa66a770007779aaaaa77003bb24444bbbb33333bbbbbbbbbbb33333bbbbbbb444423337117711171117111711171700eeeee00
007999aaaa9997007999999aaaaa66a7000007a9aaa97000bbbb24444bbbbbbbbbbb33333bbbbbbbbbbbbbb44442bbbb71717177717771777171717000eee000
077997aaaa7997707999999aaaaa66a7077777999a997000bbb3324444bbbbbbbbbbbbbbbbbbbbbbbbbbbb44442bbbbb71717117777171177111777000000000
779977a99a779977799779aaaaa66a7707997999a9997000bb333324444bbbbbbbbbbbbbbbbbbbbbbbbbb444423bbbbb71717111711171777177717000000000
799777999977799779777777999777700779999777997000b3333bb2444444444444444444444444444444442333bbbb77777777777777777777777000000000
7777077997707777797007799977000000779977079970003333bbbb24444444444444444444444444444442b3333bbb00000000000000000000000000000000
000007799770000077707799977000000007799707797000333bbbbbb244444444444444444444444444442bbb33333300000000000000000000000000000000
00077799997770000000799777000000000077970077700033bbbbbbbb2222222222222222222222222222bbbbb3333300000000000000000000000000000000
0007999999997000000079770000000000000777000000003bbbbbbbbbbb33333bbbbbbbbbbb33333bbbbbbbbbbb333300000000000000000000000000000000
000777777777700000007770000000000000000000000000bbbb33333bbbbbbbbbbb33333bbbbbbbbbbb33333bbbbbbb00000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000011100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000001110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000000111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01100111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01111111111111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01111111111111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01100111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000000111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000001110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000011100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000777700000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000007788770000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000077777777668870000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000072222228866870000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000077222288886770000000000000000000000000000000000000000000000000000000000000000000000000000
00000066666000000000000000000000000000007772888887700000000000000000000000000000000000000000000000000000000000000000000000000000
00006666666660000000000000000000000000000078288827000000000000000000000000000000000000000000000000000000000000000000000000000000
00066666666666600000000000000000000000777772228227000000000000000000000000000000000000000000000000000000000000000000000000000000
00666666666666660000000000000000000000722722282227000000000000000000000000000000000000000000000000000000000000000000000000000000
06666666666666666000000000000000000000772222777227000000000000000000000000000000000000000000000000000000000000000000000000000000
0666cccccc66666666ccccccc0000000ccccccc7722770cccccccc0000ccccc00000000000000000000000000000000000000000000000000000000000000000
666ccccccccc666666cccccccc00000ccccccccc77227cccccccccc00ccccccc0000000000000000000000000000000000000000000000000000000000000000
66ccccccccccc666666cccccccc000ccccccccccc772cccccccccccc7ccccccc0000000000000000000000000000000000000000000000000000000000000000
6ccccccccccccc66666ccccccccc0ccccccccccccc7ccccccccccccc7ccccccc0000000000000000000000000000000000000000000000000000000000000000
7ccccccccccccc666666cccccccc7ccccccccccccc7ccccccccccccc7ccccccc0000000000000000000000000000000000000000000000000000000000000000
7ccccc777ccccc766666777ccccc7ccccc777ccccc7cccc77777ccc07ccccccc0000000000000000000000000000000000000000000000000000000000000000
7ccccc007ccccc766666607ccccc7ccccc667ccccc7cccc0000777007ccccccc0000000000000000000000000000000000000000000000000000000000000000
7ccccc007ccccc7c6666667ccccc7ccccc667ccccc7cccccccccc0007ccccccc0000000000000000000000000000000000000000000000000000000000000000
7ccccc607ccccc7c6666667ccccc7ccccccccccccc77cccccccccc007ccccccc0000000000000000000000000000000000000000000000000000000000000000
7ccccc667ccccc7cc666667ccccc7ccccccccccccc077cccccccccc07ccccccc0000000000000000000000000000000000000000000000000000000000000000
7ccccc666ccccc7ccc66667ccccc7cccccccccccc00077cccccccccc77ccccc00000000000000000000000000000000000000000000000000000000000000000
7ccccc6666cccc7cccc6667ccccc7ccccccccccc000007777777cccc077777000000000000000000000000000000000000000000000000000000000000000000
7ccccc66666ccc7ccccc067ccccc7cccccccccc00000ccc00007cccc000000000000000000000000000000000000000000000000000000000000000000000000
7cccccc66666cc7ccccccccccccc7ccccc777700000ccccccccccccc00ccccc00000000000000000000000000000000000000000000000000000000000000000
7cccccc666666c7ccccccccccccc7ccccc000000007ccccccccccccc0ccccccc0000000000000000000000000000000000000000000000000000000000000000
77cccccc66666077ccccccccccc07ccccc000000007cccccccccccc07ccccccc0000000000000000000000000000000000000000000000000000000000000000
077ccccc666666077ccccccccc007ccccc0000000077cccccccccc007ccccccc0000000000000000000000000000000000000000000000000000000000000000
0077ccccc666666077cccc66c00077ccc000000000077cccccccc00077ccccc00000000000000000000000000000000000000000000000000000000000000000
00077777766666600777766660000777000000000000777777770000077777000000000000000000000000000000000000000000000000000000000000000000
00000000006666606660066660000000000000000000000000000000000000000000000000000000000000000000000000000800077707770077007700000777
000000000006660666660066000006000000000000000000000000000000000000000000000000000000000000000000000097f0070700700700070700000707
000000000000000666660000006000000000000000000000000000000000000000000000000000000000000000000000000a777e077700700700070707770777
0000000000000006666600000666000000000000000000000000000000000000000000000000000000000000000000000000b7d0070000700700070700000707
00000000000000006660000000600000000000000000000000000000000000000000000000000000000000000000000000000c00070007770077077000000777
__label__
bb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbb
bb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbb
bbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbb
bbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbb
bbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bb
bbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bb
bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333
bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333
33bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb333333
33bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb333333
3333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb3333
3333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb3333
3333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb33
3333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb33
33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb
33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb
bb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbb
bb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbb
bbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbb
bbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbb
bbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bb
bbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bb
bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333377777777bbbbbbbb333333333333333333
bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333377777777bbbbbbbb333333333333333333
33bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33777788887777bbbb33333333bbbbbb333333
33bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33777788887777bbbb33333333bbbbbb333333
3333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb333377777777777777776666888877bb33333333bbbbbbbbbb3333
3333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb333377777777777777776666888877bb33333333bbbbbbbbbb3333
3333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb33333333333333337722222222222288886666887733333333bbbbbbbbbbbbbb33
3333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb33333333333333337722222222222288886666887733333333bbbbbbbbbbbbbb33
33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb3333333333333377772222222288888888667777333333bbbbbbbbbbbbbbbbbb
33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb3333333333333377772222222288888888667777333333bbbbbbbbbbbbbbbbbb
bb33333333336666666666bbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbb7777772288888888887777333333bbbbbbbbbbbbbbbbbbbb
bb33333333336666666666bbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbb7777772288888888887777333333bbbbbbbbbbbbbbbbbbbb
bbbbbbbb66666666666666666633bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb337788228888882277bbbbbbbbbbbbbb3333333333bbbb
bbbbbbbb66666666666666666633bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb337788228888882277bbbbbbbbbbbbbb3333333333bbbb
bbbbbb666666666666666666666666bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbb777777777722222288222277bbbbbbbbbbbb33333333333333bb
bbbbbb666666666666666666666666bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbb777777777722222288222277bbbbbbbbbbbb33333333333333bb
11116666666666666666666666666666111111111111111111111111111111111111111111117722227722222288222222771111111111111111111111111111
11116666666666666666666666666666111111111111111111111111111111111111111111117722227722222288222222771111111111111111111111111111
11666666666666666666666666666666661111111111111111111111111111111111111111117777222222227777772222771111111111111111111111111111
11666666666666666666666666666666661111111111111111111111111111111111111111117777222222227777772222771111111111111111111111111111
11666666cccccccccccc6666666666666666cccccccccccccc11111111111111cccccccccccccc77772222777711cccccccccccccccc11111111cccccccccc11
11666666cccccccccccc6666666666666666cccccccccccccc11111111111111cccccccccccccc77772222777711cccccccccccccccc11111111cccccccccc11
666666cccccccccccccccccc666666666666cccccccccccccccc1111111111cccccccccccccccccc7777222277cccccccccccccccccccc1111cccccccccccccc
666666cccccccccccccccccc666666666666cccccccccccccccc1111111111cccccccccccccccccc7777222277cccccccccccccccccccc1111cccccccccccccc
6666cccccccccccccccccccccc666666666666cccccccccccccccc111111cccccccccccccccccccccc777722cccccccccccccccccccccccc77cccccccccccccc
6666cccccccccccccccccccccc666666666666cccccccccccccccc111111cccccccccccccccccccccc777722cccccccccccccccccccccccc77cccccccccccccc
66cccccccccccccccccccccccccc6666666666cccccccccccccccccc11cccccccccccccccccccccccccc77cccccccccccccccccccccccccc77cccccccccccccc
66cccccccccccccccccccccccccc6666666666cccccccccccccccccc11cccccccccccccccccccccccccc77cccccccccccccccccccccccccc77cccccccccccccc
77cccccccccccccccccccccccccc666666666666cccccccccccccccc77cccccccccccccccccccccccccc77cccccccccccccccccccccccccc77cccccccccccccc
77cccccccccccccccccccccccccc666666666666cccccccccccccccc77cccccccccccccccccccccccccc77cccccccccccccccccccccccccc77cccccccccccccc
77cccccccccc777777cccccccccc776666666666777777cccccccccc77cccccccccc777777cccccccccc77cccccccc7777777777cccccc1177cccccccccccccc
77cccccccccc777777cccccccccc776666666666777777cccccccccc77cccccccccc777777cccccccccc77cccccccc7777777777cccccc1177cccccccccccccc
77cccccccccc111177cccccccccc776666666666661177cccccccccc77cccccccccc666677cccccccccc77cccccccc11111111777777111177cccccccccccccc
77cccccccccc111177cccccccccc776666666666661177cccccccccc77cccccccccc666677cccccccccc77cccccccc11111111777777111177cccccccccccccc
77cccccccccc111177cccccccccc77cc66666666666677cccccccccc77cccccccccc666677cccccccccc77cccccccccccccccccccc11111177cccccccccccccc
77cccccccccc111177cccccccccc77cc66666666666677cccccccccc77cccccccccc666677cccccccccc77cccccccccccccccccccc11111177cccccccccccccc
77cccccccccc661177cccccccccc77cc66666666666677cccccccccc77cccccccccccccccccccccccccc7777cccccccccccccccccccc111177cccccccccccccc
77cccccccccc661177cccccccccc77cc66666666666677cccccccccc77cccccccccccccccccccccccccc7777cccccccccccccccccccc111177cccccccccccccc
77cccccccccc666677cccccccccc77cccc666666666677cccccccccc77cccccccccccccccccccccccccc117777cccccccccccccccccccc1177cccccccccccccc
77cccccccccc666677cccccccccc77cccc666666666677cccccccccc77cccccccccccccccccccccccccc117777cccccccccccccccccccc1177cccccccccccccc
77cccccccccc666666cccccccccc77cccccc6666666677cccccccccc77cccccccccccccccccccccccc1111117777cccccccccccccccccccc7777cccccccccc11
77cccccccccc666666cccccccccc77cccccc6666666677cccccccccc77cccccccccccccccccccccccc1111117777cccccccccccccccccccc7777cccccccccc11
77cccccccccc66666666cccccccc77cccccccc66666677cccccccccc77cccccccccccccccccccccc111111111177777777777777cccccccc1177777777771111
77cccccccccc66666666cccccccc77cccccccc66666677cccccccccc77cccccccccccccccccccccc111111111177777777777777cccccccc1177777777771111
77cccccccccc6666666666cccccc77cccccccccc116677cccccccccc77cccccccccccccccccccc1111111111cccccc1111111177cccccccc1111111111111111
77cccccccccc6666666666cccccc77cccccccccc116677cccccccccc77cccccccccccccccccccc1111111111cccccc1111111177cccccccc1111111111111111
77cccccccccccc6666666666cccc77cccccccccccccccccccccccccc77cccccccccc777777771111111111cccccccccccccccccccccccccc1111cccccccccc11
77cccccccccccc6666666666cccc77cccccccccccccccccccccccccc77cccccccccc777777771111111111cccccccccccccccccccccccccc1111cccccccccc11
77cccccccccccc666666666666cc77cccccccccccccccccccccccccc77cccccccccc111111111111111177cccccccccccccccccccccccccc11cccccccccccccc
77cccccccccccc666666666666cc77cccccccccccccccccccccccccc77cccccccccc111111111111111177cccccccccccccccccccccccccc11cccccccccccccc
7777cccccccccccc6666666666117777cccccccccccccccccccccc1177cccccccccc111111111111111177cccccccccccccccccccccccc1177cccccccccccccc
7777cccccccccccc6666666666117777cccccccccccccccccccccc1177cccccccccc111111111111111177cccccccccccccccccccccccc1177cccccccccccccc
117777cccccccccc666666666666117777cccccccccccccccccc111177cccccccccc11111111111111117777cccccccccccccccccccc111177cccccccccccccc
117777cccccccccc666666666666117777cccccccccccccccccc111177cccccccccc11111111111111117777cccccccccccccccccccc111177cccccccccccccc
11117777cccccccccc666666666666117777cccccccc6666cc1111117777cccccc111111111111111111117777cccccccccccccccc1111117777cccccccccc11
11117777cccccccccc666666666666117777cccccccc6666cc1111117777cccccc111111111111111111117777cccccccccccccccc1111117777cccccccccc11
11111177777777777766666666666611117777777766666666111111117777771111111111111111111111117777777777777777111111111177777777771111
11111177777777777766666666666611117777777766666666111111117777771111111111111111111111117777777777777777111111111177777777771111
11111111111111111111666666666611666666111166666666111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111666666666611666666111166666666111111111111111111111111111111111111111111111111111111111111111111111111111111
11111111111111111111116666661166666666661111666611111111116611777777777777777777777777777777777777777777777777777777777777777777
11111111111111111111116666661166666666661111666611111111116611777777777777777777777777777777777777777777777777777777777777777777
bbbbbbbbbbbbbbbb333333333333336666666666bbbbbbbb33336633333333771111117711111177111111771177777711111177111177771111117711111177
bbbbbbbbbbbbbbbb333333333333336666666666bbbbbbbb33336633333333771111117711111177111111771177777711111177111177771111117711111177
bbbbbbbbbbbbbb33333333333333336666666666bbbbbb3333666666333333771177117777117777117711771177777777117777117711771177777711777777
bbbbbbbbbbbbbb33333333333333336666666666bbbbbb3333666666333333771177117777117777117711771177777777117777117711771177777711777777
33bbbbbbbbbb33333333bbbbbb333333666666bbbbbb3333333366bbbb3333771111117777117777111177771177777777117777117711771111777777771177
33bbbbbbbbbb33333333bbbbbb333333666666bbbbbb3333333366bbbb3333771111117777117777111177771177777777117777117711771111777777771177
3333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33771177117711111177117711771111117711111177117711771111117711111177
3333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33771177117711111177117711771111117711111177117711771111117711111177
3333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb777777777777777777777777777777777777777777777777777777777777777777
3333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb777777777777777777777777777777777777777777777777777777777777777777
33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb
33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb
bb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbb
bb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbb
bbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbb
bbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbb
bbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bb
bbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bb
bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333
bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333
33bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb333333
33bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb333333
3333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb3333
3333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb3333
3333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb33
3333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb33
33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb
33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb
bb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbb
bb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbb
bbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbb
bbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbbbbbbbbbbbbbbbbbbbb3333333333bbbb
bbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bb
bbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bb
bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333
bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333
33bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb333333
33bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb333333
3333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb3333
3333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb33333333bbbbbb33333333bbbbbbbbbb3333
3333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb33
3333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb333333333333333333bbbbbbbbbbbbbb33
33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb
33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb33333333333333bbbbbbbbbbbbbbbbbb

__gff__
0001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
3839383938393839383938393839383938393839383938393637383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4849484948494849484948494849484948494849484948494647484948493839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3839383938393839383938393839383938393839383938395657585958595859000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4849484948494849484948494849484948494849484948496667686968696869000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
383938391617181918191819181918191a1b3839383938393839383938394849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
484948492627282928292829282928292a2b4849484948494849484948493839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
383938393637383938393839383938393a3b3839383938393839383938394849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
484948494647484948494849484948494a4b4849484948494849484948493839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
383938393637383938393839383938393a3b3839383938393839383938394849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
484948494647484948494849484948494a4b4849484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
383938393637383938393839383938393a3b3839383938393839383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
484948494647484948494849484948494a4b4849484948493839383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
383938395657585958595859585958595a5b3839383938394849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
484948496667686968696869686968696a6b4849484916171819181918191819000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3839383938393839383938393839383938393839383926272829282928292829000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4849484948494849484948494849484948494849484936371c1d1e1f38393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3839383938393839383938393839383938393839383936372c2d2e2f48494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4849484948494849484948494849484948494849484946473c3d3e3f38393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3839383938393839383938393839383938393839383936374c4d4e4f48494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1819181918191819181918191819181918191a1b484946473839484938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2829282928292829282928292829282928292a2b383956575859585948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3839383938393839383938393839383938393a3b484966676869686968696869000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4849484948494849484948494849484948494a4b383938393839383938394849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3839383938393839383938393839383938393a3b484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4849484948494849484948494849484948494a4b383938393839383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3839383938393839383938393839383938393a3b484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4849484948494849484948494849484948494a4b383938393839383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3839383938393839383938393839383938393a3b484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4849484948494849484948494849484948494a4b383938393839383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3839383938393839383938393839383938393a3b484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3839383938393839383938393839383938393a3b383938393839383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4849484948494849484948494849484948494a4b484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
490400001c0741d0711f0712107123071240712607128071000020000200002000020000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4904000028074260712407123071210711f0711d0711c071000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002
4908000028072280722b0722b07230072300723007230072300523003200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002
050300001007010070100751000013000100701007010075000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
490200001c0741c0711c0711c07507000000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100000
4902000018070180701807018070010000c0000c0000c0000d0000d0000d0000e0000f00011000130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0102000013070130701307013070010000c0000c0000c0000d0000d0000d0000e0000f00011000130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
49040000180741807018070180701c0701c0701c0701c070240702407024070240702407024050240302401500000000000000000000000000000000000000000000000000000000000000000000000000000000
49040000240742407024070240701c0701c0701c0701c070180701807018070180701807018050180301801506000000000000000000000000000000000000000000000000000000000000000000000000000000
010a00001067510675276701065010645106302765410650106501065027634106452763510650106341064010650276551063510645106341065410635106451063010650106541063510620276251061010615
010400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
15100000160430c0300c0350c035356130c0000e0300e030160430e0300e0300e032356130e0350e0350e03516043100301003510035356130c0000e0300e030160430e0300e0300e032356130e0320e0320e032
0d1000001c0341c0301c0351c0350c0000c0001d0301d0301d0341d0301d0301d0321d0341d0351d0351d0351f0341f0301f0351f0350c0000c0001d0301d0301d0341d0301d0301d0321d0341d0321d0321d032
15100000160430c0300c0350c035356130c0000e0300e030160430e0300e0300e032356130e0350e0350e03516043100301003510035356130c0000f0300f035160430e0300e0300e032356130e0320e0320e032
0d1000001c0341c0301c0351c0350c0000c0001d0301d0301d0341d0301d0301d0321d0341d0351d0351d0351f0341f0301f0351f0350c0001e0001e0301e0351d0341d0301d0301d0321d0341d0321d0321d032
051000002874428743007002a7002b7402b7432b7002b7002474424740247402474026741267422674226745287412874026740267402474024745217451f7401f7401f7401f7421f7421f7351f7352174524755
05100000007000070028740287432a7002b7412b7402b74024744247402474024743267402674026740267452874128740267402674024740247452d7452b7402b7402b7422b7422b7422b743000001f0001f000
15100000160430c0300c0350c035356130c0000e0300e030160430e0300e0300e032356130e0350e0350e03516043100301003510035356130c0000f0300f035160430e0300e0300e03235613100351003210033
0d1000001c0341c0301c0351c0350c0000c0001d0301d0301d0341d0301d0301d0321d0341d0351d0351d0351f0341f0301f0351f0350c0001e0001e0301e0351d0341d0301d0301d0321f0341f0352003220033
1510000016043110301103511035356130c0001303013030160431303013030130303561313035130351303516043100301003510035356130c00015030150301604315030150301503235613150321503215032
0d100000210342103021035210350c0000c0001c0301c0301a0341a0301a0301c0311c0341c0351a0351a0351f0341f0301f0351f0350c0000c00018030180301803418030180301803218034180321803218032
0510000024700187002b7402b7432d7402174528741287402b7412b7402b7402d7412d7402d7402b7402b74300700007002b740297402874029740260002874128740267402674224742247421f7451f7421f743
0510000024700247002474426740267402674028740287402b7412b7402b7401f7452b74529740287402674524730267302b7402d7402b74028740267302874228733247302673224722217221f732217551f755
0510000024744247402474326741267402674528740287432b7442b7402b7402d7412d7402d7402b7402b74300700007002b7402b7432d7402f74000000307403074030730307323072230722307123074532745
15100000160430e0300e0330e00035613100401003510000160431104011043110003561312040120431303016043130301303513035356131303213032130321604313022130221302235613130121301213015
151000001d0341d0321d0331d0001c0441c0421c0351c000150341504215043000001a0311a0321a0331803018032180321803218032180321803218032180321802218022180221802218012180121801218015
051000003573435730357332670034734347303473328700307343073030733217002d7312d7302d7352b7302b7302b7302b7302b7302b7322b7222b7222b7222b7222b7222b7222b7122b7122b7122b7122b715
__music__
01 10115355
00 12135353
00 10111454
00 12131555
00 10111454
00 16171555
00 18191a55
00 18191b55
00 18191c55
02 1d1e1f55

