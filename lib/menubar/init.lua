---------------------------------------------------------------------------
--- Menubar module, which aims to provide a freedesktop menu alternative.
--
-- List of menubar keybindings:
-- ---
--
-- <table class='widget_list' border=1>
-- <tr style='font-weight: bold;'>
--  <th align='center'>Keybinding</th>
--  <th align='center'>Description</th>
-- </tr>                                                                                    </td></tr>
--  <tr><td><kbd>Left</kbd><kbd>C-j</kbd></td><td> select an item on the left                 </td></tr>
--  <tr><td><kbd>Right</kbd><kbd>C-k</kbd></td><td> select an item on the right                </td></tr>
--  <tr><td><kbd>Backspace    </kbd></td><td> exit the current category if we are in any </td></tr>
--  <tr><td><kbd>Escape       </kbd></td><td> exit the current directory or exit menubar </td></tr>
--  <tr><td><kbd>Home         </kbd></td><td> select the first item                      </td></tr>
--  <tr><td><kbd>End          </kbd></td><td> select the last                            </td></tr>
--  <tr><td><kbd>Return       </kbd></td><td> execute the entry                          </td></tr>
--  <tr><td><kbd>C-Return     </kbd></td><td> execute the command with awful.spawn       </td></tr>
--  <tr><td><kbd>C-M-Return   </kbd></td><td> execute the command in a terminal          </td></tr>
-- </table>
--
-- @author Alexander Yakushev &lt;yakushev.alex@gmail.com&gt;
-- @copyright 2011-2012 Alexander Yakushev
-- @popupmod menubar
---------------------------------------------------------------------------

-- Grab environment we need
local capi = {
    client = client,
    mouse = mouse,
    screen = screen
}
local gmath = require("gears.math")
local awful = require("awful")
local gfs = require("gears.filesystem")
local common = require("awful.widget.common")
local theme = require("beautiful")
local wibox = require("wibox")
local gcolor = require("gears.color")
local gstring = require("gears.string")
local gdebug = require("gears.debug")

local function get_screen(s)
    return s and capi.screen[s]
end


--- Menubar normal text color.
-- @beautiful beautiful.menubar_fg_normal
-- @param color

--- Menubar normal background color.
-- @beautiful beautiful.menubar_bg_normal
-- @param color
--
--- Menubar base background color.
-- @beautiful beautiful.menubar_bg_base
-- @param color

--- Menubar border width.
-- @beautiful beautiful.menubar_border_width
-- @tparam[opt=0] number menubar_border_width

--- Menubar border color.
-- @beautiful beautiful.menubar_border_color
-- @param color

--- Menubar selected item text color.
-- @beautiful beautiful.menubar_fg_focus
-- @param color

--- Menubar selected item background color.
-- @beautiful beautiful.menubar_bg_focus
-- @param color

--- Menubar font.
-- @beautiful beautiful.menubar_font
-- @param[opt=beautiful.font] font


-- menubar
local menubar = { menu_entries = {} }
menubar.menu_gen = require("menubar.menu_gen")
menubar.utils = require("menubar.utils")

-- Options section

--- When true the .desktop files will be reparsed only when the
-- extension is initialized. Use this if menubar takes much time to
-- open.
-- @tfield[opt=true] boolean cache_entries
menubar.cache_entries = true

--- When true the categories will be shown alongside application
-- entries.
-- @tfield[opt=true] boolean show_categories
menubar.show_categories = true

--- When false will hide results if the current query is empty
-- @tfield[opt=true] boolean match_empty
menubar.match_empty = true

--- Specifies the geometry of the menubar. This is a table with the keys
-- x, y, width and height. Missing values are replaced via the screen's
-- geometry. However, missing height is replaced by the font size.
-- @table geometry
-- @tfield number geometry.x A forced horizontal position
-- @tfield number geometry.y A forced vertical position
-- @tfield number geometry.width A forced width
-- @tfield number geometry.height A forced height
menubar.geometry = { width = nil,
                     height = nil,
                     x = nil,
                     y = nil }

--- Width of blank space left in the right side.
-- @tfield number right_margin
menubar.right_margin = theme.xresources.apply_dpi(8)

--- Label used for "Next page", default "▶▶".
-- @tfield[opt="▶▶"] string right_label
menubar.right_label = "▶▶"

--- Label used for "Previous page", default "◀◀".
-- @tfield[opt="◀◀"] string left_label
menubar.left_label = "◀◀"

-- awful.widget.common.list_update adds spacing of dpi(4) between items.
-- @tfield number list_spacing
local list_spacing = theme.xresources.apply_dpi(4)

--- Allows user to specify custom parameters for prompt.run function
-- (like colors). This will merge with the default parameters, overriding affected values.
-- @see awful.prompt
menubar.prompt_args = {}

-- Private section
local current_item = 1
local previous_item = nil
local current_category = nil
local shownitems = nil
local instance = nil

local common_args = { w = wibox.layout.fixed.horizontal(),
                      data = setmetatable({}, { __mode = 'kv' }) }

--- Wrap the text with the color span tag.
-- @param s The text.
-- @param c The desired text color.
-- @return the text wrapped in a span tag.
local function colortext(s, c)
    return "<span color='" .. gcolor.ensure_pango_color(c) .. "'>" .. s .. "</span>"
end

--- Get how the menu item should be displayed.
-- @param o The menu item.
-- @return item name, item background color, background image, item icon, item args.
local function label(o)
    local fg_color = theme.menubar_fg_normal or theme.menu_fg_normal or theme.fg_normal
    local bg_color = theme.menubar_bg_normal or theme.menu_bg_normal or theme.bg_normal
    if o.focused then
        fg_color = theme.menubar_fg_focus or theme.menu_fg_focus or theme.fg_focus
        bg_color = theme.menubar_bg_focus or theme.menu_bg_focus or theme.bg_focus
    end
    return colortext(gstring.xml_escape(o.name), fg_color),
           bg_color,
           nil,
           o.icon,
           o.icon and {icon_size=instance.geometry.height}
end

local function load_count_table()
    if instance.count_table then
        return instance.count_table
    end
    instance.count_table = {}
    local count_file_name = gfs.get_cache_dir() .. "/menu_count_file"
    local count_file = io.open (count_file_name, "r")
    if count_file then
        for line in count_file:lines() do
            local name, count = string.match(line, "([^;]+);([^;]+)")
            if name ~= nil and count ~= nil then
                instance.count_table[name] = count
            end
        end
        count_file:close()
    end
    return instance.count_table
end

local function write_count_table(count_table)
    count_table = count_table or instance.count_table
    local count_file_name = gfs.get_cache_dir() .. "/menu_count_file"
    local count_file = assert(io.open(count_file_name, "w"))
    for name, count in pairs(count_table) do
        local str = string.format("%s;%d\n", name, count)
        count_file:write(str)
    end
    count_file:close()
end

--- Perform an action for the given menu item.
-- @param o The menu item.
-- @return if the function processed the callback, new awful.prompt command, new awful.prompt prompt text.
local function perform_action(o)
    if not o then return end
    if o.key then
        current_category = o.key
        local new_prompt = shownitems[current_item].name .. ": "
        previous_item = current_item
        current_item = 1
        return true, "", new_prompt
    elseif shownitems[current_item].cmdline then
        awful.spawn(shownitems[current_item].cmdline)
        -- load count_table from cache file
        local count_table = load_count_table()
        -- increase count
        local curname = shownitems[current_item].name
        count_table[curname] = (count_table[curname] or 0) + 1
        -- write updated count table to cache file
        write_count_table(count_table)
        -- Let awful.prompt execute dummy exec_callback and
        -- done_callback to stop the keygrabber properly.
        return false
    end
end

-- Cut item list to return only current page.
-- @tparam table all_items All items list.
-- @tparam str query Search query.
-- @tparam number|screen scr Screen
-- @return table List of items for current page.
local function get_current_page(all_items, query, scr)

    local compute_text_width = function(text, s)
        return wibox.widget.textbox.get_markup_geometry(text, s, instance.font)['width']
    end

    scr = get_screen(scr)
    if not instance.prompt.width then
        instance.prompt.width = compute_text_width(instance.prompt.prompt, scr)
    end
    if not menubar.left_label_width then
        menubar.left_label_width = compute_text_width(menubar.left_label, scr)
    end
    if not menubar.right_label_width then
        menubar.right_label_width = compute_text_width(menubar.right_label, scr)
    end
    local border_width = theme.menubar_border_width or theme.menu_border_width or 0
    local available_space = instance.geometry.width - menubar.right_margin -
        menubar.right_label_width - menubar.left_label_width -
        compute_text_width(query..' ', scr) - instance.prompt.width - border_width * 2
        -- space character is added as input cursor placeholder

    local width_sum = 0
    local current_page = {}
    for i, item in ipairs(all_items) do
        item.width = item.width or (
            compute_text_width(label(item), scr) +
            (item.icon and (instance.geometry.height + list_spacing) or 0) + list_spacing * 2
        )
        if width_sum + item.width > available_space then
            if current_item < i then
                table.insert(current_page, { name = menubar.right_label, icon = nil })
                break
            end
            current_page = { { name = menubar.left_label, icon = nil }, item, }
            width_sum = item.width
        else
            table.insert(current_page, item)
            width_sum = width_sum + item.width
        end
    end
    return current_page
end

--- Update the menubar according to the command entered by user.
-- @tparam number|screen scr Screen
local function menulist_update(scr)
    local query = instance.query or ""
    shownitems = {}
    local pattern = gstring.query_to_pattern(query)

    -- All entries are added to a list that will be sorted
    -- according to the priority (first) and weight (second) of its
    -- entries.
    -- If categories are used in the menu, we add the entries matching
    -- the current query with high priority as to ensure they are
    -- displayed first. Afterwards the non-category entries are added.
    -- All entries are weighted according to the number of times they
    -- have been executed previously (stored in count_table).
    local count_table = load_count_table()
    local command_list = {}

    local PRIO_NONE = 0
    local PRIO_CATEGORY_MATCH = 2

    -- Add the categories
    if menubar.show_categories then
        for _, v in pairs(menubar.menu_gen.all_categories) do
            v.focused = false
            if not current_category and v.use then

                -- check if current query matches a category
                if string.match(v.name, pattern) then

                    v.weight = 0
                    v.prio = PRIO_CATEGORY_MATCH

                    -- get use count from count_table if present
                    -- and use it as weight
                    if string.len(pattern) > 0 and count_table[v.name] ~= nil then
                        v.weight = tonumber(count_table[v.name])
                    end

                    -- check for prefix match
                    if string.match(v.name, "^" .. pattern) then
                        -- increase default priority
                        v.prio = PRIO_CATEGORY_MATCH + 1
                    else
                        v.prio = PRIO_CATEGORY_MATCH
                    end

                    table.insert (command_list, v)
                end
            end
        end
    end

    -- Add the applications according to their name and cmdline
    local add_entry = function(entry)
        entry.focused = false
        if not current_category or entry.category == current_category then

            -- check if the query matches either the name or the commandline
            -- of some entry
            if string.match(entry.name, pattern)
                or string.match(entry.cmdline, pattern) then

                entry.weight = 0
                entry.prio = PRIO_NONE

                -- get use count from count_table if present
                -- and use it as weight
                if string.len(pattern) > 0 and count_table[entry.name] ~= nil then
                    entry.weight = tonumber(count_table[entry.name])
                end

                -- check for prefix match
                if string.match(entry.name, "^" .. pattern)
                    or string.match(entry.cmdline, "^" .. pattern) then
                    -- increase default priority
                    entry.prio = PRIO_NONE + 1
                else
                    entry.prio = PRIO_NONE
                end

                table.insert (command_list, entry)
            end
        end
    end

    -- Add entries if required
    if query ~= "" or menubar.match_empty then
        for _, v in ipairs(menubar.menu_entries) do
            add_entry(v)
        end
    end


    local function compare_counts(a, b)
        if a.prio == b.prio then
            return a.weight > b.weight
        end
        return a.prio > b.prio
    end

    -- sort command_list by weight (highest first)
    table.sort(command_list, compare_counts)
    -- copy into showitems
    shownitems = command_list

    if #shownitems > 0 then
        -- Insert a run item value as the last choice
        table.insert(shownitems, { name = "Exec: " .. query, cmdline = query, icon = nil })

        if current_item > #shownitems then
            current_item = #shownitems
        end
        shownitems[current_item].focused = true
    else
        table.insert(shownitems, { name = "", cmdline = query, icon = nil })
    end

    common.list_update(common_args.w, nil, label,
                       common_args.data,
                       get_current_page(shownitems, query, scr))
end

--- Refresh menubar's cache by reloading .desktop files.
-- @tparam[opt=awful.screen.focused()] screen scr Screen.
-- @noreturn
-- @staticfct menubar.refresh
function menubar.refresh(scr)
    scr = get_screen(scr or awful.screen.focused() or 1)
    menubar.menu_gen.generate(function(entries)
        menubar.menu_entries = entries
        if instance then
            menulist_update(scr)
        end
    end)
end

--- Awful.prompt keypressed callback to be used when the user presses a key.
-- @param mod Table of key combination modifiers (Control, Shift).
-- @param key The key that was pressed.
-- @param comm The current command in the prompt.
-- @return if the function processed the callback, new awful.prompt command, new awful.prompt prompt text.
local function prompt_keypressed_callback(mod, key, comm)
    if key == "Left" or (mod.Control and key == "j") then
        current_item = math.max(current_item - 1, 1)
        return true
    elseif key == "Right" or (mod.Control and key == "k") then
        current_item = current_item + 1
        return true
    elseif key == "BackSpace" then
        if comm == "" and current_category then
            current_category = nil
            current_item = previous_item
            return true, nil, "Run: "
        end
    elseif key == "Escape" then
        if current_category then
            current_category = nil
            current_item = previous_item
            return true, nil, "Run: "
        end
    elseif key == "Home" then
        current_item = 1
        return true
    elseif key == "End" then
        current_item = #shownitems
        return true
    elseif key == "Return" or key == "KP_Enter" then
        if mod.Control then
            current_item = #shownitems
            if mod.Mod1 then
                -- add a terminal to the cmdline
                shownitems[current_item].cmdline = menubar.utils.terminal
                        .. " -e " .. shownitems[current_item].cmdline
            end
        end
        return perform_action(shownitems[current_item])
    end
    return false
end

--- Show the menubar on the given screen.
-- @tparam[opt=awful.screen.focused()] screen scr Screen.
-- @noreturn
-- @staticfct menubar.show
-- @usebeautiful beautiful.menubar_fg_normal
-- @usebeautiful beautiful.menubar_bg_normal
-- @usebeautiful beautiful.menubar_bg_base
-- @usebeautiful beautiful.menubar_border_width
-- @usebeautiful beautiful.menubar_border_color
-- @usebeautiful beautiful.menubar_fg_focus
-- @usebeautiful beautiful.menubar_bg_focus
-- @usebeautiful beautiful.menubar_font
function menubar.show(scr)
    scr = get_screen(scr or awful.screen.focused() or 1)
    local fg_color = theme.menubar_fg_normal or theme.menu_fg_normal or theme.fg_normal
    local bg_color = theme.menubar_bg_base or theme.menubar_bg_normal or theme.menu_bg_normal or theme.bg_normal
    local border_width = theme.menubar_border_width or theme.menu_border_width or 0
    local border_color = theme.menubar_border_color or theme.menu_border_color
    local font = theme.menubar_font or theme.font or "Monospace 10"

    if not instance then
        -- Add to each category the name of its key in all_categories
        for k, v in pairs(menubar.menu_gen.all_categories) do
            v.key = k
        end

        if menubar.cache_entries then
            menubar.refresh(scr)
        end

        instance = {
            wibox = wibox{
                ontop = true,
                bg = bg_color,
                fg = fg_color,
                border_width = border_width,
                border_color = border_color,
                font = font,
            },
            widget = common_args.w,
            prompt = awful.widget.prompt(),
            query = nil,
            count_table = nil,
            font = font,
        }
        local layout = wibox.layout.fixed.horizontal()
        layout:add(instance.prompt)
        layout:add(instance.widget)
        instance.wibox:set_widget(layout)
    end

    if instance.wibox.visible then -- Menu already shown, exit
        return
    elseif not menubar.cache_entries then
        menubar.refresh(scr)
    end

    -- Set position and size
    local scrgeom = scr.workarea
    local geometry = menubar.geometry
    instance.geometry = {x = geometry.x or scrgeom.x,
                             y = geometry.y or scrgeom.y,
                             height = geometry.height or gmath.round(theme.get_font_height(font) * 1.5),
                             width = (geometry.width or scrgeom.width) - border_width * 2}
    instance.wibox:geometry(instance.geometry)

    current_item = 1
    current_category = nil
    menulist_update(scr)

    local default_prompt_args = {
        prompt              = "Run: ",
        textbox             = instance.prompt.widget,
        completion_callback = awful.completion.shell,
        history_path        = gfs.get_cache_dir() .. "/history_menu",
        done_callback       = menubar.hide,
        changed_callback    = function(query)
            instance.query = query
            menulist_update(scr)
        end,
        keypressed_callback = prompt_keypressed_callback
    }

    awful.prompt.run(setmetatable(menubar.prompt_args, {__index=default_prompt_args}))


    instance.wibox.visible = true
end

--- Hide the menubar.
-- @staticfct menubar.hide
-- @noreturn
function menubar.hide()
    if instance then
        instance.wibox.visible = false
        instance.query = nil
    end
end

--- Get a menubar wibox.
-- @tparam[opt] screen scr Screen.
-- @return menubar wibox.
-- @deprecated get
function menubar.get(scr)
    gdebug.deprecate("Use menubar.show() instead", { deprecated_in = 5 })
    menubar.refresh(scr)
    -- Add to each category the name of its key in all_categories
    for k, v in pairs(menubar.menu_gen.all_categories) do
        v.key = k
    end
    return common_args.w
end

local mt = {}
function mt.__call(_, ...)
    return menubar.get(...)
end

return setmetatable(menubar, mt)

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
