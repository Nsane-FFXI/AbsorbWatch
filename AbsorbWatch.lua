_addon.name     = 'AbsorbWatch'
_addon.author   = 'Nsane'
_addon.version  = '2025.9.1'
_addon.commands = {'aw', 'absorbwatch'}

----------------------------------------
-- Requires
----------------------------------------
local packets = require('packets')
local texts   = require('texts')
local conf    = require('config')
require('sets')

----------------------------------------
-- Constants
----------------------------------------
local PACKET_ACTION            = 0x028
local MSG_ABSORB_TP_NORMAL     = 454  -- Normal Absorb result (TP in action param)
local MSG_SPELL_HIT            = 114  -- Spell hit message; Absorb-TP identified by Param
local PARAM_ABSORB_TP_SPELL_ID = 275  -- "Absorb-TP" identifier at top-level Param

local UI_FONT      = 'Consolas'
local UI_FONT_SIZE = 12
local UI_BG_ALPHA  = 255

local UPDATE_INTERVAL_S   = 0.10
local POS_SAVE_DEBOUNCE_S = 0.50

----------------------------------------
-- Defaults and settings
----------------------------------------
local defaults = {
    decay_time    = 900,   -- seconds to keep absorb entries
    onscreen_time = 60,    -- seconds to show since last absorb
    colors        = true,  -- colored amounts on/off
    counter       = true,  -- show [count]
    timer         = true,  -- show (elapsed s)
    box = { x = 100, y = 100 },
}
local settings = conf.load(defaults)

----------------------------------------
-- Party traversal helpers
----------------------------------------
local PARTY_GROUP_KEYS = { 'party1_count', 'party2_count', 'party3_count' }
local PARTY_POS_KEYS = {
    { 'p0','p1','p2','p3','p4','p5'   },
    { 'a10','a11','a12','a13','a14','a15' },
    { 'a20','a21','a22','a23','a24','a25' },
}

-- Public shim for testing hook compatibility
local ID = {}
_G.ID = ID

local function add_player(set, member)
    if member and member.hpp and member.hpp > 0 and not set:contains(member.name) then
        set[member.name] = member
    end
end

local function players()
    local party = windower.ffxi.get_party()
    if not party or not party.p0 then return S{} end

    local zone = party.p0.zone
    local members = S{}

    for g = 1, #PARTY_GROUP_KEYS do
        local count = party[PARTY_GROUP_KEYS[g]] or 0
        for p = 1, count do
            local key = PARTY_POS_KEYS[g][p]
            local m = key and party[key]
            if m and m.zone == zone then
                add_player(members, m)
            end
        end
    end
    return members
end
ID.players = players

local function player_ids_by_mobid()
    local map = S{}
    for _, p in pairs(players()) do
        local pid = (p.mob and p.mob.id) or p.id
        if pid then map[pid] = p.name end
    end
    return map
end

----------------------------------------
-- Absorb storage
----------------------------------------
-- absorbs[name] = { {time=..., display=...}, ... }
local absorbs = {}

local function add_absorb(name, display)
    if not name or not display then return end
    local list = absorbs[name]
    if not list then
        list = {}
        absorbs[name] = list
    end
    list[#list+1] = { time = os.clock(), display = display }
end

----------------------------------------
-- UI
----------------------------------------
local status_box = texts.new({
    pos   = { x = settings.box.x or defaults.box.x, y = settings.box.y or defaults.box.y },
    text  = { font = UI_FONT, size = UI_FONT_SIZE },
    bg    = { alpha = UI_BG_ALPHA },
    flags = { draggable = true, right = false },
}, true)

status_box:hide()

local last_pos = {
    x = settings.box.x or defaults.box.x,
    y = settings.box.y or defaults.box.y,
}
local last_pos_save_time = 0.0

local function maybe_save_box_pos(now)
    local bx, by = status_box:pos()
    bx = math.floor(bx or last_pos.x)
    by = math.floor(by or last_pos.y)

    if bx ~= last_pos.x or by ~= last_pos.y then
        if now - last_pos_save_time >= POS_SAVE_DEBOUNCE_S then
            last_pos.x, last_pos.y = bx, by
            settings.box.x, settings.box.y = bx, by
            conf.save(settings)
            last_pos_save_time = now
        end
    end
end

----------------------------------------
-- Coloring
----------------------------------------
local function colorize_amount(amount)
    if not amount then return '0' end
    if not settings.colors then return tostring(amount) end

    if amount <= 99 then
        return ('\\cs(255,255,255)%d\\cr'):format(amount) -- white
    elseif amount <= 200 then
        return ('\\cs(0,255,0)%d\\cr'):format(amount)     -- green
    elseif amount <= 300 then
        return ('\\cs(255,255,0)%d\\cr'):format(amount)   -- yellow
    elseif amount <= 400 then
        return ('\\cs(255,165,0)%d\\cr'):format(amount)   -- orange
    else
        return ('\\cs(255,0,0)%d\\cr'):format(amount)     -- red
    end
end

----------------------------------------
-- UI update
----------------------------------------
local function update_box()
    local now = os.clock()
    local lines = {}

    for name, events in pairs(absorbs) do
        -- prune by decay_time
        local fresh = {}
        for i = 1, #events do
            local ev = events[i]
            if now - ev.time <= settings.decay_time then
                fresh[#fresh+1] = ev
            end
        end
        absorbs[name] = fresh

        local n = #fresh
        if n > 0 then
            local latest = fresh[n]
            local elapsed = math.floor(now - latest.time)
            if elapsed <= settings.onscreen_time then
                local parts = { ("%s: %s TP"):format(name, latest.display) }
                if settings.timer  then parts[#parts+1] = ("(%ds ago)"):format(elapsed) end
                if settings.counter then parts[#parts+1] = ("[%d]"):format(n) end
                lines[#lines+1] = table.concat(parts, ' ')
            end
        end
    end

    if #lines > 0 then
        table.sort(lines) -- stable, deterministic ordering
        status_box:text(table.concat(lines, '\n'))
        status_box:show()
    else
        status_box:text('')
        status_box:hide()
    end
end

----------------------------------------
-- Ticker
----------------------------------------
local last_update = 0.0
windower.register_event('prerender', function()
    local now = os.clock()
    if now - last_update >= UPDATE_INTERVAL_S then
        update_box()
        last_update = now
    end
    maybe_save_box_pos(now)
end)

----------------------------------------
-- Packet watch
----------------------------------------
windower.register_event('incoming chunk', function(id, data)
    if id ~= PACKET_ACTION or not data then return end

    local action = packets.parse('incoming', data)
    if not action then return end

    local ids = player_ids_by_mobid()
    local actor_name = action.Actor and ids[action.Actor]
    if not actor_name then return end

    local msg = action["Target 1 Action 1 Message"]
    if msg == MSG_ABSORB_TP_NORMAL then
        local tp_value = tonumber(action["Target 1 Action 1 Param"]) or 0
        add_absorb(actor_name, colorize_amount(tp_value))

    elseif msg == MSG_SPELL_HIT and action.Param == PARAM_ABSORB_TP_SPELL_ID then
        local display = settings.colors and "\\cs(0,125,255)0\\cr" or "0" -- blue zero
        add_absorb(actor_name, display)
    end
end)

----------------------------------------
-- CLI
----------------------------------------
local function print_status()
    windower.add_to_chat(207, ('[AbsorbWatch] decay=%ds, screen=%ds, colors=%s, counter=%s, timer=%s, pos=(%d,%d)')
        :format(
            settings.decay_time, settings.onscreen_time,
            settings.colors  and 'on' or 'off',
            settings.counter and 'on' or 'off',
            settings.timer   and 'on' or 'off',
            settings.box.x, settings.box.y
        ))
end

local function print_help()
    local help = {
        '[AbsorbWatch] Commands:',
        '  //aw decay <seconds>     -- Absorb counter decay (1..86400, default 900)',
        '  //aw screen <seconds>    -- Time until player is removed (1..3600, default 60)',
        '  //aw colors on|off       -- Toggle colored amounts',
        '  //aw counter on|off      -- Show/hide absorb count [n]',
        '  //aw timer on|off        -- Show/hide (xxs ago)',
        '  //aw pos <x> <y>         -- Move box to (x,y) & save',
        '  //aw resetpos            -- Reset box to default position',
        '  //aw clear               -- Clear current absorbs and hide box',
        '  //aw test                -- Add sample absorbs for testing',
        '  //aw status              -- Show current settings (incl. position)',
        '  //aw help                -- Show this help',
    }
    for i = 1, #help do windower.add_to_chat(207, help[i]) end
end

local function save_and_echo(msg)
    conf.save(settings)
    if msg then windower.add_to_chat(207, msg) end
end

windower.register_event('addon command', function(cmd, ...)
    cmd = (cmd or ''):lower()
    local args = { ... }

    if cmd == 'decay' then
        local v = tonumber(args[1])
        if v and v >= 1 and v <= 86400 then
            settings.decay_time = math.floor(v)
            save_and_echo(('[AbsorbWatch] decay set to %ds'):format(settings.decay_time))
        else
            windower.add_to_chat(207, '[AbsorbWatch] Invalid decay. Usage: //aw decay <1..86400>')
        end

    elseif cmd == 'screen' or cmd == 'onscreen' or cmd == 'display' then
        local v = tonumber(args[1])
        if v and v >= 1 and v <= 3600 then
            settings.onscreen_time = math.floor(v)
            save_and_echo(('[AbsorbWatch] screen set to %ds'):format(settings.onscreen_time))
        else
            windower.add_to_chat(207, '[AbsorbWatch] Invalid screen. Usage: //aw screen <1..3600>')
        end

    elseif cmd == 'colors' or cmd == 'colour' then
        local a = (args[1] or ''):lower()
        if a == '' then
            settings.colors = not settings.colors
            save_and_echo(('[AbsorbWatch] colors: %s'):format(settings.colors and 'on' or 'off'))
        elseif a == 'on' or a == 'true' or a == '1' then
            settings.colors = true
            save_and_echo('[AbsorbWatch] colors: on')
        elseif a == 'off' or a == 'false' or a == '0' then
            settings.colors = false
            save_and_echo('[AbsorbWatch] colors: off')
        else
            windower.add_to_chat(207, '[AbsorbWatch] Invalid colors. Usage: //aw colors on|off')
        end

    elseif cmd == 'counter' then
        local a = (args[1] or ''):lower()
        if a == '' then
            settings.counter = not settings.counter
            save_and_echo(('[AbsorbWatch] counter: %s'):format(settings.counter and 'on' or 'off'))
        elseif a == 'on' or a == 'true' or a == '1' then
            settings.counter = true
            save_and_echo('[AbsorbWatch] counter: on')
        elseif a == 'off' or a == 'false' or a == '0' then
            settings.counter = false
            save_and_echo('[AbsorbWatch] counter: off')
        else
            windower.add_to_chat(207, '[AbsorbWatch] Usage: //aw counter on|off')
        end

    elseif cmd == 'timer' then
        local a = (args[1] or ''):lower()
        if a == '' then
            settings.timer = not settings.timer
            save_and_echo(('[AbsorbWatch] timer: %s'):format(settings.timer and 'on' or 'off'))
        elseif a == 'on' or a == 'true' or a == '1' then
            settings.timer = true
            save_and_echo('[AbsorbWatch] timer: on')
        elseif a == 'off' or a == 'false' or a == '0' then
            settings.timer = false
            save_and_echo('[AbsorbWatch] timer: off')
        else
            windower.add_to_chat(207, '[AbsorbWatch] Usage: //aw timer on|off')
        end

    elseif cmd == 'pos' then
        local x = tonumber(args[1])
        local y = tonumber(args[2])
        if x and y then
            settings.box.x, settings.box.y = math.floor(x), math.floor(y)
            status_box:pos(settings.box.x, settings.box.y)
            last_pos.x, last_pos.y = settings.box.x, settings.box.y
            save_and_echo(('[AbsorbWatch] moved to (%d, %d)'):format(settings.box.x, settings.box.y))
        else
            windower.add_to_chat(207, '[AbsorbWatch] Usage: //aw pos <x> <y>')
        end

    elseif cmd == 'resetpos' then
        settings.box.x, settings.box.y = defaults.box.x, defaults.box.y
        status_box:pos(settings.box.x, settings.box.y)
        last_pos.x, last_pos.y = settings.box.x, settings.box.y
        save_and_echo(('[AbsorbWatch] position reset to (%d, %d)'):format(settings.box.x, settings.box.y))

    elseif cmd == 'clear' then
        absorbs = {}
        status_box:text('')
        status_box:hide()
        windower.add_to_chat(207, '[AbsorbWatch] cleared current absorbs.')

    elseif cmd == 'test' or cmd == 'simulate' then
        local names = {}
        for _, p in pairs(players()) do
            names[#names+1] = p.name
            if #names >= 3 then break end
        end
        if #names == 0 then names = { 'Alice', 'Bob', 'Cara' } end

        local samples = { 75, 220, 345, 410, 510 }
        for i, name in ipairs(names) do
            add_absorb(name, colorize_amount(samples[(i % #samples) + 1]))
            if i == 1 then add_absorb(name, colorize_amount(185)) end
        end
        update_box()
        windower.add_to_chat(207, ('[AbsorbWatch] test entries added for %d player(s).'):format(#names))

    elseif cmd == 'status' then
        print_status()

    elseif cmd == 'help' or cmd == '' then
        print_help()

    else
        windower.add_to_chat(207, ('[AbsorbWatch] Unknown command: %s'):format(cmd))
        print_help()
    end
end)
