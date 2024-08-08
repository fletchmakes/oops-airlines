pico-8 cartridge // http://www.pico-8.com
version 42
__lua__

particles = {}

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

function _init()
    poke(0x5f2c, 3)
    angle = 0
end

function _update()
    -- explosion
    for i=1,2 do
        add(particles, {
            x=32,
            y=32,
            r=8,
            dx=rnd(2)-1,
            dy=rnd(2)-1,
            dr=function(p) return p.r/1.075 end,
            c=function(p) return min(flr(((8-p.r)/(8))*4)+7,10) end,
            ttl=30
        },1)
    end

    -- smoke trail
    -- if btn(0) then angle += 0.05 end
    -- if btn(1) then angle -= 0.05 end
    -- for i=1,2 do
    --     add(particles, {
    --         x=32,
    --         y=32,
    --         r=3,
    --         dx=rnd(3)*cos(angle),
    --         dy=rnd(3)*sin(angle),
    --         dr=function(p) return p.r end,
    --         c=function(p) return p.ttl < 6 and 6 or 5 end,
    --         ttl=10
    --     })
    -- end
end

function _draw()
    cls()
    print(stat(1), 0, 0, 7)
    resolve_particles()
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
