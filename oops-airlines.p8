pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- oops airlines
-- by fletch
-- made for lowrezjam 2024

-- interpolated value [0.5,1]
local zoom = 1
-- discrete value [0.5,1]
local zoom_target = 1

function _init()

end

function _update()
    -- write any game update logic here

    -- end game update logic

    if btn(5) then
        zoom_target = 0.5
    else
        zoom_target = 1
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
    sspr(0, 0, 128, 128, sx, sy, sw, sh)

    -- video remap back to defaults (screen is the screen, spritesheet is the spritesheet)
    poke(0x5f54, 0x00)
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
-- rot - rotation [0, 1)
-- scale - scale factor
function rotated_sprite(num, cx, cy, rot, scale)
    -- TODO: modify to account for sprites larger than 8x8
	scale = scale * 8
	  
	-- change where the map region in memory is
	poke(0x5f56, 0xe0)
	  
	-- mset the sprite from the spritesheet
	mset(0, 0, num)
	  
	-- tline routine
	local c,s=cos(rot),-sin(rot)
	local p={
		{x=0,y=0,u=0,v=0},
		{x=scale,y=0,u=1,v=0},
		{x=scale,y=scale,u=1,v=1},
		{x=0,y=scale,u=0,v=1}}
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
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
