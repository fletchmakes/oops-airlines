pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- oops airlines
-- by fletch
-- made for lowrezjam 2024

local debug = false

-- camera
local zoom = 1
local zoom_target = 1
local cam = {x=0, y=0, speed=3}

-- key constants
local k_left = 0
local k_right = 1
local k_up = 2
local k_down = 3
local k_primary = 4
local k_secondary = 5

-- flag animation
local flag_num = 1
local frame = 0

-- TODO: planning mode toggle
local mode = "FLIGHT" -- "PLAN"

function _init()
end

function _update()
    -- write any game update logic here
	frame += 1
	if frame % 5 == 0 then
		flag_num = flag_num % 6 + 1
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

    -- end game update logic

    if btn(5) then
        zoom_target = 0.5
    else
        zoom_target = 1
    end

	if btnp(4) then
		mode = mode == "FLIGHT" and "PLAN" or "FLIGHT"
	end

    zoom = lerp(zoom, zoom_target, 0.2)
end

function _draw()
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

	-- mode
	rectfill(0, 58, #mode*4-1, 63, 0)
	print(mode, 0, 58, 7)

	if debug then
		rectfill(0, 0, 63, 6, 0)
		print(stat(1), 0, 0, 7)
	end
end

-->8
-- helper functions

-- basic lerp <3
function lerp(from, to, amount)
    local dist = to - from
    if abs(dist) <= 0.01 then return to end
    return from + (dist * amount)
end

-- sprite rotation
-- https://www.lexaloffle.com/bbs/?tid=37561
-- num - sprite number
-- cx - centered x coordinate
-- cy - centered y coordinate
-- w - width in sprites
-- h - height in sprites
-- rot - rotation [0, 1)
-- scale - scale factor (size in pixels)
function rotated_sprite(num, cx, cy, width, height, rot, scale)
	-- change where the map region in memory is
	poke(0x5f56, 0xe0)
	  
	-- mset the sprite from the spritesheet
    for j=0,width-1 do
        for i=0,height-1 do
	        mset(i, j, num + (j*16+i))
        end
    end
	  
	-- tline routine
	local c,s=cos(rot),-sin(rot)
	local p={
		{x=0,y=0,u=0,v=0},
		{x=scale,y=0,u=width,v=0},
		{x=scale,y=scale,u=width,v=height},
		{x=0,y=scale,u=0,v=height}}
	local w=(scale-1)/2
	for _,v in pairs(p) do
		local x,y=v.x-w,v.y-w
		v.x=c*x-s*y
		v.y=s*x+c*y
	end
	tquad(p,cx,cy)
	
	-- change map region back to default
	poke(0x5f56, 0x20)
end
  
function tquad(v,dx,dy)
	local p0,spans=v[4],{}
	local x0,y0,u0,v0=p0.x+dx,p0.y+dy,p0.u,p0.v
	for i=1,4 do
		local p1=v[i]
		local x1,y1,u1,v1=p1.x+dx,p1.y+dy,p1.u,p1.v
		local _x1,_y1,_u1,_v1=x1,y1,u1,v1
		if(y0>y1) x0,y0,x1,y1,u0,v0,u1,v1=x1,y1,x0,y0,u1,v1,u0,v0
		local dy=y1-y0
		local dx,du,dv=(x1-x0)/dy,(u1-u0)/dy,(v1-v0)/dy
		if(y0<0) x0-=y0*dx u0-=y0*du v0-=y0*dv y0=0
		local cy0=ceil(y0)
		local sy=cy0-y0
		x0+=sy*dx
		u0+=sy*du
		v0+=sy*dv
		for y=cy0,min(ceil(y1)-1,127) do
			local span=spans[y]
			if span then
				local a,au,av,b,bu,bv=span.x,span.u,span.v,x0,u0,v0
				if(a>b) a,au,av,b,bu,bv=b,bu,bv,a,au,av
				local ca,cb,dab=ceil(a),ceil(b)-1,b-a
				local sa,dau,dav=ca-a,(bu-au)/dab,(bv-av)/dab
				if ca<=cb then
					tline(ca,y,cb,y,au+sa*dau,av+sa*dav,dau,dav)
				end
				else
					spans[y]={x=x0,u=u0,v=v0}
				end
			x0+=dx
			u0+=du
			v0+=dv
		end
		x0,y0,u0,v0=_x1,_y1,_u1,_v1
	end
end

__gfx__
00000000777770007777770077777770777077707770000077770000000000000000000000000000000000000000000000000000000000000000000000000000
00000000688877006888877068878870687778706877777068877000000000000000000000000000000000000000000000000000000000000000000000000000
00700700688887706888787068887770688787706887787068887770000000000000000000000000000000000000000000000000000000000000000000000000
00077000688778706887777068887000688877006888877068888870000000000000000000000000000000000000000000000000000000000000000000000000
00077000677777706777000067777000678870006788770067777770000000000000000000000000000000000000000000000000000000000000000000000000
00700700600000006000000060000000677770006777700060000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000600000006000000060000000600000006000000060000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000600000006000000060000000600000006000000060000000000000000000000000000000000000000000000000000000000000000000000000000000
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
