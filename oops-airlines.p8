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

local current_update = nil
local current_draw = nil

local planes = {}
local active_planes = 0

function _init()
    poke(0x5f2c, 3)
	current_update = splashscreen_update
	current_draw = splashscreen_draw

	-- get 10 planes pooled and ready to be activated
	for i=1,10 do
		add_plane()
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
local frame = 0

local mode = "FLIGHT" -- "PLAN"
local focused_plane = -1 -- index into planes table
local hangar = {x=192, y=136}

function game_update()
    -- write any game update logic here
	frame += 1
	if frame % 5 == 0 then
		flag_num = flag_num % 6 + 1
	end

	-- flight mode - just watch the planes fly - zoom out to pan, zoom back in to switch between planes
	if mode == "FLIGHT" then
		for p in all(planes) do
			if p.status ~= "POOLED" then p.update(p) end
		end

		-- we're zoomed in, so we just switch between tracking planes
		if zoom_target == 1 then
			local cam_target = hangar
			if focused_plane > 0 then
				cam_target = planes[focused_plane]
			end

			local newcamx = lerp(cam.x, cam_target.x-64, 0.2)
			local newcamy = lerp(cam.y, cam_target.y-64, 0.2)

			if newcamx > 0 and newcamx < 128 then cam.x = newcamx end
			if newcamy > 0 and newcamy < 128 then cam.y = newcamy end

			if btnp(k_left) and active_planes > 0 then
				local new_target = -1
				local cursor = focused_plane
				-- search for the next unpooled plane
				while new_target == -1 do
					if cursor > 1 then 
						cursor -= 1
					else 
						cursor = #planes 
					end
					
					if planes[cursor].status ~= "POOLED" then new_target = cursor end
				end

				focused_plane = new_target
			end

			if btnp(k_right) and active_planes > 0 then
				local new_target = -1
				local cursor = focused_plane
				-- search for the next unpooled plane
				while new_target == -1 do
					if cursor < #planes then 
						cursor += 1
					else 
						cursor = 1 
					end
					
					if planes[cursor].status ~= "POOLED" then new_target = cursor end
				end
				focused_plane = new_target
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

		if btnp(5) then
			zoom_target = zoom_target == 0.5 and 1 or 0.5
		end

	-- plan mode - no planes move, just set nodes on the current plane
	elseif mode == "PLAN" then
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

		-- TODO: keybinding for adding nodes to the current plane

		if btn(5) then
			zoom_target = 0.5
		else
			zoom_target = 1
		end
	end
    -- end game update logic
    zoom = lerp(zoom, zoom_target, 0.2)
end

-- adds a plane to the game
local max_speed = 0.5
local hangar = {x=186, y=128}
function add_plane()
	local plane = {}

	-- TODO: randomize direction and location
	plane.x = -100
	plane.y = -100
	-- nodes are represented as a queue
	plane.nodes = _qnew()
	plane.next_node = nil
	plane.theta = nil

	-- TODO: account for statuses
	plane.status = "POOLED" -- "POOLED", "IDLE", ROUTING", "LANDING"
	plane.altitude = 80

	plane.add_node = function(self, x, y)
		_qpush(self.nodes, {x=x, y=y})
		if (self.next_node == nil) then
			self.next_node = _qpop(plane.nodes)
			self.theta = angle(self, self.next_node)
		end
	end

	plane.activate = function(self)
		-- TODO: randomize start location and direction
		self.status = "IDLE"
		active_planes += 1
	end

	plane.update = function(self)
		-- check if we're landing
		if self.status ~= "POOLED" and dist(self, hangar) < max_speed then
			self.status = "LANDING"
		end

		if plane.status == "ROUTING" then
			-- check if we reached our next node
			if dist(self, self.next_node) < max_speed then
				self.next_node = _qpop(self.nodes) -- remove the current entry
				self.theta = angle(self, self.next_node)
			end
			
			-- move towards destination
			self.x -= cos(self.theta) * max_speed
			self.y -= sin(self.theta) * max_speed
		elseif plane.status == "LANDING" then
			self.altitude -= 1
			self.x += 0.33
			if self.altitude > 20 then self.y += 0.1237 end

			if self.altitude <= 0 then
				self.status = "POOLED" -- hold onto this object but wait out of sight
				self.x = -100
				self.y = -100
				active_planes -= 1
			end
		elseif plane.status == "IDLE" then
			-- fly in a given direction
			-- if we make it into the play area, request game focus, switch to planning mode, and prompt for a route
		end
	end

	plane.draw = function(self)
		-- don't draw pooled objects
		if self.status == "POOLED" then return end

		-- landing sequence
		if self.status == "LANDING" then
			local s = max(self.altitude,20)/80
			sspr(16, 8, 16, 16, self.x, self.y, 16*s, 16*s)
			return
		end

		if self.theta <= 0.0625 or self.theta > 0.9375 then -- right
			spr(18, self.x, self.y, 2, 2, true)
		elseif self.theta > 0.0625 and self.theta <= 0.1875 then -- down right
			spr(20, self.x, self.y, 2, 2, true, true)
		elseif self.theta > 0.1875 and self.theta <= 0.3125 then -- down
			spr(16, self.x, self.y, 2, 2, true, true)
		elseif self.theta > 0.3125 and self.theta <= 0.4375 then -- down left
			spr(20, self.x, self.y, 2, 2, false, true)
		elseif self.theta > 0.4375 and self.theta <= 0.5625 then -- left
			spr(18, self.x, self.y, 2, 2, false)
		elseif self.theta > 0.5625 and self.theta <= 0.6875 then -- up left
			spr(20, self.x, self.y, 2, 2, false, false)
		elseif self.theta > 0.6875 and self.theta <= 0.8125 then -- up
			spr(16, self.x, self.y, 2, 2, true)
		elseif self.theta > 0.8125 and self.theta <= 0.9375 then -- up right
			spr(20, self.x, self.y, 2, 2, true)
		end
	end

	plane.nodes_draw = function(self)
		if self.status ~= "ROUTING" then return end

		-- draw current heading
		line(self.x+8, self.y+8, self.next_node.x+8, self.next_node.y+8, 8)
		circfill(self.next_node.x+8, self.next_node.y+8, 2, 8)

		-- draw future headings
		local cursor = self.next_node
		for i=self.nodes.first,self.nodes.last-1 do
			local n = self.nodes[i]
			line(cursor.x+8, cursor.y+8, n.x+8, n.y+8, 8)
			circfill(n.x+8, n.y+8, 2, 8)
		end
	end

	add(planes, plane)
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
		pal({[0]=0,129,128,128,134,133,134,134,136,9,10,133,12,141,14,15},1)
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
	for p in all(planes) do
		p.nodes_draw(p)
		p.draw(p)
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

	-- mode
	draw_ui_overlay()
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

-- https://www.lua.org/pil/11.4.html
-- basic queue implementation
function _qnew()
	return {first=0, last=0}
end

function _qpush(queue, value)
	queue[queue.last] = value
	queue.last += 1
end

function _qpeek(queue)
	return queue[queue.first]
end

function _qpop(queue)
	local first = queue.first
	if first >= queue.last then return nil end
	local value = queue[first]
	queue[first] = nil
	queue.first += 1
	return value
end

__gfx__
00000000777770007777770077777770777077707770000077770000000000700000000000088000000000000000700000000700007777000077770000000000
00000000688877006888877068878870687778706877777068877000000077000000080000888800007007000000700000007070070000700700007000000000
00700700688887706888787068887770688787706887787068887770000707000000088008888880077007707007700000070007700770077070070700000000
00077000688778706887777068887000688877006888877068888870700777770000088800000000000000007777777000700070707007077007700700000000
00077000677777706777000067777000678870006788770067777770777777000000088800000000000000007777777707000700707007077007700700000000
00700700600000006000000060000000677770006777700060000000077770000000088000000000077007707007700070007000700770077070070700000000
00000000600000006000000060000000600000006000000060000000007070000000080000000000007007000000700077070000070000700700007000000000
00000000600000006000000060000000600000006000000060000000007777000000000000000000000000000000700077700000007777000077770000000000
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
000007711770000000007c77000000000000000000777700bb2444bb333bbbbbbb333333333bbbbbbb333333bb4442bb55555555555555555551116ddd6ddd65
000007166170000000007cc7770000000000000007711770b32444bb3333bbbbb3333bbb3333bbbbb3333bbbbb4442bb57775555555555555551166ddd6ddd65
0000076666700000777077ccc77000000077777777661170332444bbb3333bbb3333bbbbb3333bbb3333bbbbbb4442bb5777555555555555555666ddd6ddd655
00007761167700007c70077ccc770000007cccccc1166170332444bbbb333333333bbbbbbb333333333bbbbbbb444233555555555555555555566ddd6ddd6555
00077c1111c770007c777777ccc777700077cccc11116770332444bbbbb3333333bbbbbbbbb3333333bbbbbbbb44423357775555555555555556666666665555
0077cc1111cc77007cc77cc111166177000777c1c11177003b2444bbbbbb33333bbbbbbbbbbb33333bbbbbbbbb44423357775555555555555555555555555555
007ccc1111ccc7007ccccccc11116617000007cccc1c7000bb2444bb3bbbbbbbbbbb33333bbbbbbbbbbb3333bb4442bb55555555555555555555555555555555
077cc71cc17cc7707ccccccc11116617077777ccc1cc7000bb2444bb33bbbbbbbbb3333333bbbbbbbbb33333bb4442bb77777777777777777777777777777777
77cc77cccc77cc777cc77cc11116617707cc7ccccccc7000bb2444bb333bbbbbbb333333333bbbbbbb333333bb4442bbbb333333333bbbbbbb333333333bbbbb
7cc777cccc777cc77c777777ccc77770077cccc777cc7000b32444bb3333bbbbb3333bbb3333bbbbb3333bbbbb4442bbb3333bbb3333bbbbb3333bbb3333bbbb
7777077cc77077777c70077ccc7700000077cc7707cc7000332444bbb3333bbb3333bbbbb3333bbb3333bbbbbb4442bb3333bbbbb3333bbb3333bbbbb3333bbb
0000077cc7700000777077ccc770000000077cc7077c7000332444bbbb333333333bbbbbbb333333333bbbbbbb444233333bbbbbbb333333333bbbbbbb333333
000777cccc77700000007cc777000000000077c700777000332444bbbbb3333333bbbbbbbbb3333333bbbbbbbb44423333bbbbbbbbb3333333bbbbbbbbb33333
0007cccccccc700000007c770000000000000777000000003b2444bbbbbb33333bbbbbbbbbbb33333bbbbbbbbb4442333bbbbbbbbbbb33333bbbbbbbbbbb3333
000777777777700000007770000000000000000000000000bb2444bb3bbbbbbbbbbb33333bbbbbbbbbbb3333bb4442bbbbbb33333bbbbbbbbbbb33333bbbbbbb
000000777700000000007770000000000000000000000000bb2444bb33bbbbbbbbb3333333bbbbbbbbb33333bb4442bb00000000000000000000000000000000
000007733770000000007b77000000000000000000777700bb2444bb333bbbbbbb333333333bbbbbbb333333bb4442bb00000000000000000000000000000000
000007366370000000007bb7770000000000000007733770b32444bb3333bbbbb3333bbb3333bbbbb3333bbbbb4442bb00000000000000000000000000000000
0000076666700000777077bbb77000000077777777663370332444bbb3333bbb3333bbbbb3333bbb3333bbbbbb4442bb00000000000000000000000000000000
00007763367700007b70077bbb770000007bbbbbb3366370332444bbbb333333333bbbbbbb333333333bbbbbbb44423300000000000000000000000000000000
00077b3333b770007b777777bbb777700077bbbb333367703324444bbbb3333333bbbbbbbbb3333333bbbbbbb444423300000000000000000000000000000000
0077bb3333bb77007bb77bb333366377000777b3b33377003bb24444bbbb33333bbbbbbbbbbb33333bbbbbbb4444233300000000000000000000000000000000
007bbb3333bbb7007bbbbbbb33336637000007bbbb3b7000bbbb24444bbbbbbbbbbb33333bbbbbbbbbbbbbb44442bbbb00000000000000000000000000000000
077bb73bb37bb7707bbbbbbb33336637077777bbb3bb7000bbb3324444bbbbbbbbbbbbbbbbbbbbbbbbbbbb44442bbbbb00000000000000000000000000000000
77bb77bbbb77bb777bb77bb33336637707bb7bbbbbbb7000bb333324444bbbbbbbbbbbbbbbbbbbbbbbbbb444423bbbbb00000000000000000000000000000000
7bb777bbbb777bb77b777777bbb77770077bbbb777bb7000b3333bb2444444444444444444444444444444442333bbbb00000000000000000000000000000000
7777077bb77077777b70077bbb7700000077bb7707bb70003333bbbb24444444444444444444444444444442b3333bbb00000000000000000000000000000000
0000077bb7700000777077bbb770000000077bb7077b7000333bbbbbb244444444444444444444444444442bbb33333300000000000000000000000000000000
000777bbbb77700000007bb777000000000077b70077700033bbbbbbbb2222222222222222222222222222bbbbb3333300000000000000000000000000000000
0007bbbbbbbb700000007b770000000000000777000000003bbbbbbbbbbb33333bbbbbbbbbbb33333bbbbbbbbbbb333300000000000000000000000000000000
000777777777700000007770000000000000000000000000bbbb33333bbbbbbbbbbb33333bbbbbbbbbbb33333bbbbbbb00000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000076770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000076770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000076770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000076770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000776777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000776777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000777677000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007777677700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007777677700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007777677700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00007777677700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077777677770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
