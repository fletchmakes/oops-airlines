pico-8 cartridge // http://www.pico-8.com
version 42
__lua__


function ef_spring_underdamped(amount)
    if amount >= 1 then amount = 1 end
    if amount <= 0 then amount = 0 end
    
    local normalized = amount * 1.5

    local omega = (3.14159 * 2)
    local psi = 0.5
    local alpha = omega * sqrt(1 - (psi * psi))
   
    local x0 = 1
   
    return (
     x0 * cos(alpha * normalized) + sin(alpha * normalized) * (omega * psi * x0)/alpha
     ) / e_exp_approx(omega * psi * normalized)
end

function e_exp_approx(f)
    return 1 + f*(1 + f/2*(1 + f/3*(1 + f/4)))
end

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

function _init()
    ax = -25
    dx = 0
end

function _update()
    ax, dx = smooth_move(4, ax, dx, 0.2, 0.7, 0.05)
end

function _draw()
    cls()
    camera(-20, 0)
    print(ax, 0, 6, 7)
    rectfill(ax, 64, ax+10, 74, 8)
    line(30, 0, 30, 63, 7)
end

__gfx__
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0070070088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0007700088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0007700088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0070070088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
0000000088888888888888889999999999999999aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000050605060506050605060506000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000151615161516151615161516000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000050603040304030403040506000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000151613141314131413141516000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000050603040102010203040506000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000151613141112111213141516000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000050603040102010203040506000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000151613141112111213141516000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000050603040304030403040506000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000151613141314131413141516000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000050605060506050605060506000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000151615161516151615161516000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
