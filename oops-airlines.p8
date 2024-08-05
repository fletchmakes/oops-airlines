pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- oops airlines
-- by fletch
-- made for lowrezjam 2024

-- FLIGHT MODE CONTROLS
-- zoomed in:
--   - left / right - switch focus between planes
--   - X - zoom out
-- zoomed out:
--   - left / right / up / down - slowly pan the camera
--   - X - zoom in

-- PATH MODE CONTROLS
--   - left / right / up / down - slowly pan the camera
--   - Z - place node / pickup node
--   - (hold) X - zoom out

local debug = false

-- key constants
local k_left = 0
local k_right = 1
local k_up = 2
local k_down = 3
local k_primary = 4
local k_secondary = 5

-- override button events with our own
local _btn, _btnp = btn, btnp

-- easier time switching between game states
local current_update = nil
local current_draw = nil

-- particle simulator list
local particles = {}

-- plane related tracking
local planes = {}
local active_planes = {}
local plan_plane = nil -- plane that is currently being route planned for
local last_plan_node = nil
local last_plan_node_hovered = false

-- score tracking
local points = 0
local flights_saved = { 0, 0, 0 } -- red, blue, yellow
local flight_type = { RED=1, BLUE=2, YELLOW=3 }

-- goes with btnp and btn
local user_input_blocker = false

-- make displaying text sprites easier
local beeg_letters = {
	o = function(x, y) sspr(0, 109, 14, 19, x, y) end,
	p = function(x, y) sspr(14, 109, 14, 19, x, y) end,
	s = function(x, y) sspr(28, 109, 14, 19, x, y) end,
}

local smol_letters = {
	a = function(x, y) sspr(40, 117, 5, 6, x, y) end,
	i = function(x, y) sspr(44, 117, 5, 6, x, y) end,
	r = function(x, y) sspr(48, 117, 5, 6, x, y) end,
	l = function(x, y) sspr(52, 117, 5, 6, x, y) end,
	y = function(x, y) sspr(56, 117, 5, 6, x, y) end,
	n = function(x, y) sspr(40, 122, 5, 6, x, y) end,
	e = function(x, y) sspr(44, 122, 5, 6, x, y) end,
	s = function(x, y) sspr(48, 122, 5, 6, x, y) end,
	f = function(x, y) sspr(52, 122, 5, 6, x, y) end,
	p = function(x, y) sspr(56, 122, 5, 6, x, y) end,
	emphasis = function(x, y) sspr(60, 122, 3, 6, x, y) end,
}

function _init()
    poke(0x5f2c, 3)
	current_update = splashscreen_update
	current_draw = splashscreen_draw

	-- get 10 planes pooled and ready to be activated
	for i=1,10 do
		add_plane(i)
	end
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
-- menus

function menu_update()

end

function menu_draw()

end

-->8
-- gameplay

-- camera
local zoom = 1
local zoom_target = 1
local cam = {x=0, y=0, speed=3}

-- flag animation
local flag_num = 1
local frame = 1

local mode = "FLIGHT" -- "PLAN", "GAMEOVER"
local focused_plane = nil
local hangar = {x=192, y=136}
local plane_spawner = 90 -- 10 seconds
local focus_scene = nil
local game_over_stuff = {
	explosion = nil
}

local animation_stuff = {
	current = nil
}

function game_update()
    -- write any game update logic here
	frame = frame % 30 + 1
	if frame % 5 == 0 then
		flag_num = flag_num % 6 + 1
	end

	-- animation is playing, don't update the game yet
	if animation_stuff.current and costatus(animation_stuff.current) ~= 'dead' then
		return
	end

	-- end-of-game updates
	if mode == "GAMEOVER" then
		-- play explosion effects
		for i=1,2 do
			add(particles, {
				x=game_over_stuff.explosion.x,
				y=game_over_stuff.explosion.y,
				r=8,
				dx=rnd(2)-1,
				dy=rnd(2)-1,
				dr=function(p) return p.r/1.075 end,
				c=function(p) return min(flr(((8-p.r)/(8))*4)+7,10) end,
				ttl=30
			},1)
		end
		
		-- camera
		if focus_scene and costatus(focus_scene) ~= 'dead' then
			coresume(focus_scene)
		else
			focus_scene = nil
		end

	-- flight mode - just watch the planes fly - zoom out to pan, zoom back in to switch between planes
	elseif mode == "FLIGHT" then
		plane_spawner -= 1
		if plane_spawner <= 0 then 
			plane_spawner = 100 + flr(rnd()*100)
	
			-- find a plane to spawn (one that is pooled)
			for i=1,#planes do
				local p = planes[i]
				if p.status == "POOLED" then
					p.activate(p)
					break
				end
			end
		end

		for p in all(planes) do
			if p.status ~= "POOLED" then p.update(p) end
		end

		-- we're zoomed in, so we just switch between tracking planes
		if zoom_target == 1 then
			local cam_target = hangar
			if focused_plane ~= nil then
				cam_target = focused_plane
			end

			local newcamx = lerp(cam.x, cam_target.x-56, 0.2)
			local newcamy = lerp(cam.y, cam_target.y-56, 0.2)

			if abs(newcamx - cam.x) < 0.76 then
				if cam_target.x > 0 and cam_target.x < 128 then cam.x = cam_target.x - 56 end
			else
				if newcamx > 0 and newcamx < 128 then cam.x = newcamx end
			end

			if abs(newcamy - cam.y) < 0.76 then 
				if cam_target.y > 0 and cam_target.y < 128 then cam.y = cam_target.y - 56 end
			else
				if newcamy > 0 and newcamy < 128 then cam.y = newcamy end
			end


			if btnp(k_left) and #active_planes > 0 then
				if focused_plane == nil then focused_plane = planes[active_planes[1]] return end

				local cursor = 1
				while cursor ~= #active_planes do
					if planes[active_planes[cursor]].idx == focused_plane.idx then break end
					cursor += 1
				end

				cursor -= 1
				if cursor == 0 then cursor = #active_planes end

				focused_plane = planes[active_planes[cursor]]
			end

			if btnp(k_right) and #active_planes > 0 then
				if focused_plane == nil then focused_plane = planes[active_planes[#active_planes]] return end

				local cursor = 1
				while cursor ~= #active_planes do
					if planes[active_planes[cursor]].idx == focused_plane.idx then break end
					cursor += 1
				end

				cursor += 1
				if cursor > #active_planes then cursor = 1 end

				focused_plane = planes[active_planes[cursor]]
			end
			
		-- we're zoomed out, so allow the camera to pan	
		else
			if btn(k_left) and cam.x > 0 then
				cam.x -= cam.speed
			end
	
			if btn(k_right) and cam.x < 128 then
				cam.x += cam.speed
			end
	
			if btn(k_up) and cam.y > 0 then
				cam.y -= cam.speed
			end
	
			if btn(k_down) and cam.y < 128 then
				cam.y += cam.speed
			end
		end

		if btn(k_secondary) then
			zoom_target = 0.5
		else
			zoom_target = 1
		end

	-- plan mode - no planes move, just set nodes on the current plane
	elseif mode == "PLAN" then
		if focus_scene and costatus(focus_scene) ~= 'dead' then
			coresume(focus_scene)
			return
		else
			focus_scene = nil
		end

		if btn(k_left) and cam.x > 0 then
			cam.x -= cam.speed
		end

		if btn(k_right) and cam.x < 128 then
			cam.x += cam.speed
		end

		if btn(k_up) and cam.y > 0 then
			cam.y -= cam.speed
		end

		if btn(k_down) and cam.y < 128 then
			cam.y += cam.speed
		end

		if last_plan_node ~= nil and dist(last_plan_node, {x=cam.x+63, y=cam.y+63}) < 5 then 
			last_plan_node_hovered = true 
		else
			last_plan_node_hovered = false
		end

		if btnp(k_primary) then
			if last_plan_node_hovered then
				plan_plane.remove_last_node(plan_plane)
			else
				last_plan_node = {x=cam.x+63,y=cam.y+63}
				plan_plane.add_node(plan_plane, cam.x+56, cam.y+56)
			end
		end

		if btn(k_secondary) then
			zoom_target = 0.5
		else
			zoom_target = 1
		end
	end
    -- end game update logic
    zoom = lerp(zoom, zoom_target, 0.2)
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
		pal({[0]=0,129,128,128,134,133,134,134,136,132,4,133,140,141,14,15},1)
	else
		-- reset to default
		pal()
	end
	map(0, 0, 0, 0, 32, 32)

	-- animate our flag
	spr(flag_num, 194, 116)
	spr(flag_num, 194, 140)

	draw_play_area_border()

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
		spr(9, hangar.x-4, hangar.y-8+sin(t())*2.5, 1, 1, false, true)

		-- last plan node delete UI
		if last_plan_node ~= nil then
			-- blinking cursor if the camera reticle is close enough
			if last_plan_node_hovered then --sin(t()/3) < 0 and 
				sspr(40, 114, 3, 3, last_plan_node.x, last_plan_node.y)
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
    local sx = -32 * (zoom - 0.5) * 2
    local sy = -32 * (zoom - 0.5) * 2
    local sw = 128 * zoom
    local sh = 128 * zoom
    -- treat the screen as a spritesheet when drawing to the screen (thanks video remapping)
	clip(0,0,64,64)
	camera()
    sspr(0, 0, 128, 128, sx, sy, sw, sh)

    -- video remap back to defaults (screen is the screen, spritesheet is the spritesheet)
    poke(0x5f54, 0x00)

	-- game ui
	draw_airport_arrow()
	draw_crosshair()

	-- animations
	if animation_stuff.current and costatus(animation_stuff.current) ~= 'dead' then
		coresume(animation_stuff.current)
	else
		animation_stuff.current = nil
	end

	-- mode
	if mode ~= "GAMEOVER" then 
		draw_ui_overlay() 
	else
		-- TODO: animate end game screen
		-- show end game screen
		-- print(points, 0, 6, 7)
		-- print(flights_saved[flight_type.RED], 0, 12, 7)
		-- print(flights_saved[flight_type.BLUE], 0, 18, 7)
		-- print(flights_saved[flight_type.YELLOW], 0, 24, 7)
	end
end

-- adds a plane to the game
local airport = {x=186, y=128}
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
		local dist_to_hangar = dist({x=x, y=y}, airport)
		if dist_to_hangar < 5 then
			mode = "FLIGHT"
			plan_plane = nil
			last_plan_node = nil
			animation_stuff.current = cocreate(fly_text())
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
	end

	plane.activate = function(self)
		-- play area is (0, 0) (256, 256)
		self.status = "IDLE"

		local pos = rnd() * 256
		local opos = rnd({0, 256})
		local x_or_y = rnd()

		if x_or_y < 0.5 then
			self.x = pos
			self.y = opos
		else
			self.x = opos
			self.y = pos
		end

		self.theta = angle(self, {x=128, y=128})

		local type = rnd({1, 2, 3})
		self.type = type
		self.sprite = sprites[type]
		self.color = colors[type]
		self.speed = 0.25*type

		self.altitude = 80
		self.smoke = {}
	end

	plane.update = function(self)
		-- check if we're landing
		if self.status == "ROUTING" and dist(self, airport) < 6 then
			self.status = "LANDING"
			return
		end

		if plane.status == "ROUTING" then
			-- check if we reached our next node
			if dist(self, self.next_node) < self.speed then
				_qdequeue(self.nodes) -- remove the current entry
				self.next_node = _qpeek(self.nodes)
				self.theta = angle(self, self.next_node)
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
							mode = "GAMEOVER"
							game_over_stuff.explosion = {x=midx, y=midy}
							focus_scene = cocreate(pan_to_position(midx, midy))
						end
					end
				end
			end

		elseif plane.status == "LANDING" then
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

				if #active_planes == 0 then
					focused_plane = nil
				else
					focused_plane = planes[active_planes[1]]
				end

				-- TODO: re-evaluate how best to distribute points - maybe more points for slower planes is better since they are trickier?
				points += self.type * 10 -- 10 points for red, 20 for blue, and 30 for yellow
				flights_saved[self.type] += 1
			end
		elseif plane.status == "IDLE" then
			-- fly in a given direction
			-- if we make it into the play area, request game focus, switch to planning mode, and prompt for a route
			self.x -= cos(self.theta) * self.speed
			self.y -= sin(self.theta) * self.speed

			if self.x > 32 and self.x < 192 and self.y > 32 and self.y < 192 then
				-- activate PLAN mode for this plane
				mode = "PLAN"
				self.status = "ROUTING"
				plan_plane = self
				add(active_planes, self.idx)

				animation_stuff.current = cocreate(plan_text())

				-- move the camera to the plane
				focus_scene = cocreate(pan_to_position(self.x, self.y))
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

		-- draw current heading
		line(self.x+8, self.y+8, self.next_node.x+8, self.next_node.y+8, self.color)
		circfill(self.next_node.x+8, self.next_node.y+8, 2, self.color)

		print(#self.nodes, 0, 0, 7)

		-- draw future headings
		local cursor = self.next_node
		for i=self.nodes.first+2,self.nodes.last do
			local n = self.nodes[i]
			line(cursor.x+8, cursor.y+8, n.x+8, n.y+8, self.color)
			circfill(n.x+8, n.y+8, 2, self.color)
			cursor = n
		end
	end

	plane.shadows_draw = function(self)
		local s = max(self.altitude,20)/80
		circfill(self.x+8*s, self.y+16*s, 3.5-(80-self.altitude)/13, 1)
	end

	add(planes, plane)
end

function draw_play_area_border()

end

function draw_airport_arrow()
	local cx,cy = cam.x + 64, cam.y + 64 -- center of the screen
	local ax,ay = hangar.x, hangar.y -- center of airport runway

	local theta = atan2(ax-cx, ay-cy)
	local distance = sqrt((ax-cx)*(ax-cx)+(ay-cy)*(ay-cy))

	-- if the hangar is on the screen, just don't show
	if distance / (1/zoom) <= 32 then return end

	local sy = sin(theta) * 20 + 28
	local sx = cos(theta) * 20 + 32

	if theta > 0.875 or theta < 0.125 then
		spr(8, sx, sy)
	elseif theta <= 0.875 and theta >= 0.5 then
		spr(9, sx, sy, 1, 1, false, true)
	elseif theta >= 0.125 and theta <= 0.5 then
		spr(9, sx, sy)
	end
end

function draw_crosshair()
	if mode == "PLAN" then spr(10, 28, 28) end
end

function draw_ui_overlay()
	rectfill(0, 56, 63, 63, 0)

	if mode == "FLIGHT" then
		spr(11, 0, 56)
		if zoom_target == 1 then
			print(chr(139)..chr(145)..chr(151), 41, 57, 7)
		else -- 0.5
			print(chr(139)..chr(145)..chr(148)..chr(131)..chr(151), 25, 57, 7)
		end
	else -- "PLAN"
		spr(12, 0, 56)
		print(chr(139)..chr(145)..chr(148)..chr(131)..chr(142)..chr(151), 17, 57, 7)
	end
end

-->8
-- splashscreen

local splash_frame = 0

function splashscreen_update()
	if splash_frame == 0 then
		sfx(2)
	end

	splash_frame += 1

	if (splash_frame > 60) then
		current_update = game_update
		current_draw = game_draw
		splash_frame = 0
	end
end

function splashscreen_draw()
	rectfill(0, 0, 63, 63, 0)
	print("a game by", 14, 22, 7)
	print("fletch",  20, 28, 7)
	spr(7, 28, 34)
end

-->8
-- helper functions

-- basic lerp <3
function lerp(from, to, amount)
    local dist = to - from
    if abs(dist) <= 0.01 then return to end
    return from + (dist * amount)
end

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

-- returns a function to be used with cocreate()
function pan_to_position(x, y)
	return function()
		user_input_blocker = true
		local diffx, diffy = 999, 999
		while diffx > 0.25 or diffy > 0.25 do
			local lastcamx, lastcamy = cam.x, cam.y
			local newcamx = lerp(cam.x, x-64, 0.1)
			local newcamy = lerp(cam.y, y-64, 0.1)

			if newcamx > 0 and newcamx < 128 then cam.x = newcamx end
			if newcamy > 0 and newcamy < 128 then cam.y = newcamy end

			diffx, diffy = abs(lastcamx - cam.x), abs(lastcamy - cam.y)

			yield()
		end

		user_input_blocker = false
	end
end

-- returns a function to be used with cocreate()
function fly_text()
	return function()
		user_input_blocker = true

		local frames = 0
		local gravity = 0.5
		local y = {64, 64, 64, 64}
		local dy = {-5, -5, -5, -5}
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

		user_input_blocker = false
	end
end

function plan_text()
	return function()
		user_input_blocker = true

		local frames = 0
		local gravity = 0.5
		local y = {64, 64, 64, 64, 64}
		local dy = {-5, -5, -5, -5, -5}
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

		user_input_blocker = false
	end
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

-- https://www.lua.org/pil/11.4.html
-- basic queue implementation
function _qnew()
	return {first=0, last=0}
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

-- stop user input if we want
function btn(num)
	if user_input_blocker then return false end
	return _btn(num)
end

function btnp(num)
	if user_input_blocker then return false end
	return _btnp(num)
end

__gfx__
00000000777770007777770077777770777077707770000077770000000000700000000000088000000000000000700000000700000000000000000000000000
00000000688877006888877068878870687778706877777068877000000077000000080000888800007007000000700000007770000000000000000000000000
00700700688887706888787068887770688787706887787068887770000707000000088008888880077007707007700000077777000000000000000000000000
00077000688778706887777068887000688877006888877068888870700777770000088800000000000000007777777000777770000000000000000000000000
00077000677777706777000067777000678870006788770067777770777777000000088800000000000000007777777707777700000000000000000000000000
00700700600000006000000060000000677770006777700060000000077770000000088000000000077007707007700070777000000000000000000000000000
00000000600000006000000060000000600000006000000060000000007070000000080000000000007007000000700070070000000000000000000000000000
00000000600000006000000060000000600000006000000060000000007777000000000000000000000000000000700077700000000000000000000000000000
000000777700000000007770000000000000000000000000bbb3333333bbbbbbbbb3333333bbbbbbbbb3333333bbbbbbbbb3333333bbbbbbbbb3333333bbbbbb
000007788770000000007277000000000000000000777700bb333333333bbbbbbb333333333bbbbbbb333333333bbbbbbb333333333bbbbbbb333333333bbbbb
000007866870000000007227770000000000000007788770b3333bbb332222222222222222222222222222bb3333bbbbb3333bbb3333bbbbb3333bbb3333bbbb
0000076666700000777077222770000000777777776688703333bbbbb244444444444444444444444444442bb3333bbb3333bbbbb3333bbb3333bbbbb3333bbb
000077688677000072700772227700000072222228866870333bbbbb24444444444444444444444444444442bb333333333bbbbbbb333333333bbbbbbb333333
00077288882770007277777722277770007722228888677033bbbbb2444444444444444444444444444444442bb3333333bbbbbbbbb3333333bbbbbbbbb33333
0077228888227700722772288886687700077728288877003bbbbb24444bbbbbbbbbbbbbbbbbbbbbbbbbb44442bb33333bbbbbbbbbbb33333bbbbbbbbbbb3333
007222888822277072222222888866870000072222827000bbbb324444bbbbbbbbbb33333bbbbbbbbbbbbb44442bbbbb77777777777777777777777777777777
077227822872277072222222888866870777772228227000bbb324444bbbbbbbbbb3333333bbbbbbbbb3bbb44442bbbb55555555555555555555555555555555
772277222277227772277228888668770722722222227000bb324444bbbbbbbbbb333333333bbbbbbb333bbb44442bbb57775555555555555555555555555555
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
007711cccc1177007117711cccc66c770007771c1ccc77003b2444bbbbbb33333bbbbbbbbbbb33333bbbbbbbbb44423357775555555555555555555555555555
007111cccc11170071111111cccc66c70000071111c17000bb2444bb3bbbbbbbbbbb33333bbbbbbbbbbb3333bb4442bb55555555555555555555555555555555
077117c11c71177071111111cccc66c7077777111c117000bb2444bb33bbbbbbbbb3333333bbbbbbbbb33333bb4442bb77777777777777777777777777777777
77117711117711777117711cccc66c770711711111117000bb2444bb333bbbbbbb333333333bbbbbbb333333bb4442bbbb333333333bbbbbbb333333333bbbbb
711777111177711771777777111777700771111777117000b32444bb3333bbbbb3333bbb3333bbbbb3333bbbbb4442bbb3333bbb3333bbbbb3333bbb3333bbbb
777707711770777771700771117700000077117707117000332444bbb3333bbb3333bbbbb3333bbb3333bbbbbb4442bb3333bbbbb3333bbb3333bbbbb3333bbb
000007711770000077707711177000000007711707717000332444bbbb333333333bbbbbbb333333333bbbbbbb444233333bbbbbbb333333333bbbbbbb333333
000777111177700000007117770000000000771700777000332444bbbbb3333333bbbbbbbbb3333333bbbbbbbb44423333bbbbbbbbb3333333bbbbbbbbb33333
0007111111117000000071770000000000000777000000003b2444bbbbbb33333bbbbbbbbbbb33333bbbbbbbbb4442333bbbbbbbbbbb33333bbbbbbbbbbb3333
000777777777700000007770000000000000000000000000bb2444bb3bbbbbbbbbbb33333bbbbbbbbbbb3333bb4442bbbbbb33333bbbbbbbbbbb33333bbbbbbb
000000777700000000007770000000000000000000000000bb2444bb33bbbbbbbbb3333333bbbbbbbbb33333bb4442bb00000000000000000000000000000000
0000077aa770000000007977000000000000000000777700bb2444bb333bbbbbbb333333333bbbbbbb333333bb4442bb00000000000000000000000000000000
000007a66a700000000079977700000000000000077aa770b32444bb3333bbbbb3333bbb3333bbbbb3333bbbbb4442bb00000000000000000000000000000000
00000766667000007770779997700000007777777766aa70332444bbb3333bbb3333bbbbb3333bbb3333bbbbbb4442bb00000000000000000000000000000000
0000776aa67700007970077999770000007999999aa66a70332444bbbb333333333bbbbbbb333333333bbbbbbb44423300000000000000000000000000000000
000779aaaa977000797777779997777000779999aaaa67703324444bbbb3333333bbbbbbbbb3333333bbbbbbb444423300000000000000000000000000000000
007799aaaa9977007997799aaaa66a770007779a9aaa77003bb24444bbbb33333bbbbbbbbbbb33333bbbbbbb4444233300000000000000000000000000000000
007999aaaa99970079999999aaaa66a70000079999a97000bbbb24444bbbbbbbbbbb33333bbbbbbbbbbbbbb44442bbbb00000000000000000000000000000000
077997a99a79977079999999aaaa66a7077777999a997000bbb3324444bbbbbbbbbbbbbbbbbbbbbbbbbbbb44442bbbbb00000000000000000000000000000000
77997799997799777997799aaaa66a770799799999997000bb333324444bbbbbbbbbbbbbbbbbbbbbbbbbb444423bbbbb00000000000000000000000000000000
799777999977799779777777999777700779999777997000b3333bb2444444444444444444444444444444442333bbbb00000000000000000000000000000000
7777077997707777797007799977000000779977079970003333bbbb24444444444444444444444444444442b3333bbb00000000000000000000000000000000
000007799770000077707799977000000007799707797000333bbbbbb244444444444444444444444444442bbb33333300000000000000000000000000000000
00077799997770000000799777000000000077970077700033bbbbbbbb2222222222222222222222222222bbbbb3333300000000000000000000000000000000
0007999999997000000079770000000000000777000000003bbbbbbbbbbb33333bbbbbbbbbbb33333bbbbbbbbbbb333300000000000000000000000000000000
000777777777700000007770000000000000000000000000bbbb33333bbbbbbbbbbb33333bbbbbbbbbbb33333bbbbbbb00000000000000000000000000000000
000000000000000000000000000000000000000000000000999fffffff999999999fffffff999999999fffffff99999900000000000000000000000000000000
00000000000000000000000000000000000000000000000099fffffffff9999999fffffffff9999999fffffffff9999900000000000000000000000000000000
0000000000000000000000000000000000000000000000009ffff999ffff99999ffff999ffff99999ffff999ffff999900000000000000000000000000000000
000000000000000000000000000000000000000000000000ffff99999ffff999ffff99999ffff999ffff99999ffff99900000000000000000000000000000000
000000000000000000000000000000000000000000000000fff9999999fffffffff9999999fffffffff9999999ffffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000ff999999999fffffff999999999fffffff999999999fffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000f9999999999111111111111111111111111119999999ffff00000000000000000000000000000000
0000000000000000000000000000000000000000000000009999fffff91111111111ccccc1111111111111fff999999900000000000000000000000000000000
000000000000000000000000000000000000000000000000999ffffff1111111111ccccccc111111111c111fff99999900000000000000000000000000000000
00000000000000000000000000000000000000000000000099ffffff1111111111ccccccccc1111111ccc111fff9999900000000000000000000000000000000
0000000000000000000000000000000000000000000000009ffff99111cc11111cccc111cccc11111cccc1111fff999900000000000000000000000000000000
000000000000000000000000000000000000000000000000ffff99111cccc111cccc11111cccc111cccc111111fff99900000000000000000000000000000000
000000000000000000000000000000000000000000000000fff9991111ccccccccc1111111ccccccccc1111111ffffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000ff999911111ccccccc111111111ccccccc111111119fffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000f99999111111ccccc11111111111ccccc11111111199ffff00000000000000000000000000000000
0000000000000000000000000000000000000000000000009999ff11c11111111111ccccc11111111111cccc1199999900000000000000000000000000000000
000000000000000000000000000000000000000000000000999fff11cc111111111ccccccc111111111ccccc1199999900000000000000000000000000000000
00000000000000000000000000000000000000000000000099ffff11ccc1111111ccccccccc1111111cccccc11f9999900000000000000000000000000000000
0000000000000000000000000000000000000000000000009ffff911cccc11111cccc111cccc11111cccc11111ff999900000000000000000000000000000000
000000000000000000000000000000000000000000000000ffff99111cccc111cccc11111cccc111cccc111111fff99900000000000000000000000000000000
000000000000000000000000000000000000000000000000fff9991111ccccccccc1111111ccccccccc1111111ffffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000ff999911111ccccccc111111111ccccccc111111119fffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000f99999111111ccccc11111111111ccccc11111111199ffff00000000000000000000000000000000
0000000000000000000000000000000000000000000000009999ff11c11111111111ccccc11111111111cccc1199999900000000000000000000000000000000
000000000000000000000000000000000000000000000000999fff11cc111111111ccccccc111111111ccccc1199999900000000000000000000000000000000
00000000000000000000000000000000000000000000000099ffff11ccc1111111ccccccccc1111111cccccc11f9999900000000000000000000000000000000
0000000000000000000000000000000000000000000000009ffff911cccc11111cccc111cccc11111cccc11111ff999900000000000000000000000000000000
000000000000000000000000000000000000000000000000ffff99111cccc111cccc11111cccc111cccc111111fff99900000000000000000000000000000000
000000000000000000000000000000000000000000000000fff9991111ccccccccc1111111ccccccccc1111111ffffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000ff999911111ccccccc111111111ccccccc111111119fffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000f99999111111ccccc11111111111ccccc11111111199ffff00000000000000000000000000000000
0000000000000000000000000000000000000000000000009999ff11c11111111111ccccc11111111111cccc1199999900000000000000000000000000000000
000000000000000000000000000000000000000000000000999fff11cc111111111ccccccc111111111ccccc1199999900000000000000000000000000000000
00000000000000000000000000000000000000000000000099ffff11ccc1111111ccccccccc1111111cccccc11f9999900000000000000000000000000000000
0000000000000000000000000000000000000000000000009ffff911cccc11111cccc111cccc11111cccc11111ff999900000000000000000000000000000000
000000000000000000000000000000000000000000000000ffff99111cccc111cccc11111cccc111cccc111111fff99900000000000000000000000000000000
000000000000000000000000000000000000000000000000fff9991111ccccccccc1111111ccccccccc1111111ffffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000ff999991111ccccccc111111111ccccccc111111199fffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000f99999991111ccccc11111111111ccccc11111119999ffff00000000000000000000000000000000
0000000000000000000000000000000000000000000000009999fffff11111111111ccccc11111111111111ff999999900000000000000000000000000000000
000000000000000000000000000000000000000000000000999fffffff1111111111111111111111111111ffff99999900000000000000000000000000000000
00000000000000000000000000000000000000000000000099fffffffff11111111111111111111111111ffffff9999900000000000000000000000000000000
0000000000000000000000000000000000000000000000009ffff999ffff99999ffff999ffff99999ffff999ffff999900000000000000000000000000000000
000000000000000000000000000000000000000000000000ffff99999ffff999ffff99999ffff999ffff99999ffff99900000000000000000000000000000000
000000000000000000000000000000000000000000000000fff9999999fffffffff9999999fffffffff9999999ffffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000ff999999999fffffff999999999fffffff999999999fffff00000000000000000000000000000000
000000000000000000000000000000000000000000000000f99999999999fffff99999999999fffff99999999999ffff00000000000000000000000000000000
0000000000000000000000000000000000000000000000009999fffff99999999999fffff99999999999fffff999999900000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000ccccccc0000000ccccccc0000000cccccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000ccccccccc00000ccccccccc00000cccccccc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccccccccccc000ccccccccccc000cccccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0ccccccccccccc0ccccccccccccc0ccccccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7ccccccccccccc7ccccccccccccc7ccccccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7ccccc777ccccc7ccccc777ccccc7cccc777ccc07070000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7ccccc007ccccc7ccccc007ccccc7cccc00777000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7ccccc007ccccc7ccccc007ccccc7cccccccc0007070000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7ccccc007ccccc7ccccccccccccc77cccccccc007777777777777777777770000000000000000000000000000000000000000000000000000000000000000000
7ccccc007ccccc7ccccccccccccc077cccccccc07111711171117177717170000000000000000000000000000000000000000000000000000000000000000000
7ccccc007ccccc7cccccccccccc00077cccccccc7171771771717177711170000000000000000000000000000000000000000000000000000000000000000000
7ccccc007ccccc7ccccccccccc0000077777cccc7111771771177177777170000000000000000000000000000000000000000000000000000000000000000000
7ccccc007ccccc7cccccccccc00000ccc007cccc7171711171717111711170000000000000000000000000000000000000000000000000000000000000000000
7ccccccccccccc7ccccc777700000ccccccccccc7777777777777777777777700000000000000000000000000000000000000000000000000000000000000000
7ccccccccccccc7ccccc000000007ccccccccccc7117711171117111711171700000000000000000000000000000000000000000000000000000000000000000
77ccccccccccc07ccccc000000007cccccccccc07171717771777177717171700000000000000000000000000000000000000000000000000000000000000000
077ccccccccc007ccccc0000000077cccccccc007171711777717117711177700000000000000000000000000000000000000000000000000000000000000000
0077ccccccc00077ccc000000000077cccccc0007171711171117177717771700000000000000000000000000000000000000000000000000000000000000000
00077777770000077700000000000077777700007777777777777777777777700000000000000000000000000000000000000000000000000000000000000000
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
181918191a1b4849484948494849484948493a3b484966676869686968696869000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
282928292a2b3839383938393839383938394a4b383938393839383938394849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
484948493a3b484948491617181918191a1b3a3b484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
383938394a4b383938392627282928292a2b4a4b383938393839383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
484948493a3b484948493637484948493a3b3a3b484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
383938394a4b383938394647383938394a4b4a4b383938393839383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
484948493a3b484948493637484948493a3b3a3b484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
383938394a4b383938394647383938394a4b4a4b383938393839383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
484948493a3b484948495657585958595a5b3a3b484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
383938393a3b383938396667686968696a6b3a3b383938393839383938393839000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
484948494a4b4849484948494849484948494a4b484948494849484948494849000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
95030000100701007010070100751f000220002400024000290002b0002e000330003500035000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
490400002407024070240702407500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4908000028072280722b0722b07230072300723007230072300523003200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002
050900000960315603016030160301603026030260300603000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300000000000000000000
010200001a0050b0010160101601016010c0010c0010c0010d0010d0010d0010e0010f00111001130010000100001000010000100001000010000100001000010000100001000010000100001000000000000000
010200001a005016010360101601016010c0010c0010c0010d0010d0010d0010e0010f00111001130010000100001000010000100001000010000100001000010000100001000010000100001000000000000000
010200001a005016010160101601016010c0010c0010c0010d0010d0010d0010e0010f00111001130010000100001000010000100001000010000100001000010000100001000010000100001000000000000000
0104000002605026010160101601016010c0010c0010c0010d0010d0010d0010e0010f00111001130010000100001000010000100001000010000100001000010000100001000010000100001000000000000000
0307000000b0000b001fb0000b0000b002ab0000b0000b0000b0000b0000b0000b0000b0000b0000b0009b0006b0000b0000b0000b0000b0000b0000b0000b000000000000000000000000000000000000000000
031400000c703007031e7030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000000000000000000000000000000000000000000000000000000
010400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
