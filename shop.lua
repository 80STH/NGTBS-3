local shop = {}

shop.isOpen = false
shop.gold = 9999
shop.purchased = {}
shop.notification = nil
shop.notificationTimer = 0
shop.selectedCategory = 1

shop.categories = {
    { name = "All", filter = nil },
    { name = "Consumables", filter = "consumable" },
    { name = "Artifacts", filter = "artifact" },
    { name = "Spells", filter = "spell" },
    { name = "Cores", filter = "core" },
}

shop.allItems = {
    { id = "chaos_reduction", name = "Chaos Reduction", desc = "Reduces chaos level by 1", price = 100, category = "consumable", icon = "*" },
    { id = "iron_will", name = "Iron Will", desc = "Artifact: immunity to roots and slow", price = 200, category = "artifact", icon = "#" },
    { id = "scout", name = "Scout", desc = "Artifact: deploy on any terrain", price = 200, category = "artifact", icon = "#" },
    { id = "fortress", name = "Fortress", desc = "Artifact: all units take -1 damage", price = 200, category = "artifact", icon = "#" },
    { id = "swift_boots", name = "Swift Boots", desc = "Artifact: all units +1 move range", price = 200, category = "artifact", icon = "#" },
    { id = "hit_and_run", name = "Hit & Run", desc = "Artifact: move after attacking", price = 200, category = "artifact", icon = "#" },
    { id = "ghost_cloak", name = "Ghost Cloak", desc = "Artifact: phase through enemies", price = 200, category = "artifact", icon = "#" },
    { id = "heal", name = "Heal Sphere", desc = "Spell: restores squad health", price = 150, category = "spell", icon = "~" },
    { id = "extra_move", name = "Speed Sphere", desc = "Spell: extra move for a unit", price = 150, category = "spell", icon = "~" },
    { id = "wind_torrent", name = "Wind Sphere", desc = "Spell: pushes enemies away", price = 150, category = "spell", icon = "~" },
    { id = "unearth", name = "Earth Sphere", desc = "Spell: summons obstacles", price = 150, category = "spell", icon = "~" },
    { id = "energy_core", name = "Energy Core", desc = "Upgrades one unit in your squad", price = 300, category = "core", icon = "+" },
    { id = "energy_core_plus", name = "Large Energy Core", desc = "Upgrades two units in your squad", price = 500, category = "core", icon = "+" },
}

function shop.getFilteredItems()
    local cat = shop.categories[shop.selectedCategory]
    if not cat.filter then
        return shop.allItems
    end
    local result = {}
    for _, item in ipairs(shop.allItems) do
        if item.category == cat.filter then
            table.insert(result, item)
        end
    end
    return result
end

function shop.update(dt)
    if shop.notificationTimer > 0 then
        shop.notificationTimer = shop.notificationTimer - dt
        if shop.notificationTimer <= 0 then
            shop.notification = nil
        end
    end
end

function shop.draw()
    if not shop.isOpen then return end
    local w, h = logicalW, logicalH

    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local panelW, panelH = 600, math.min(h - 80, 520)
    local panelX = w/2 - panelW/2
    local panelY = h/2 - panelH/2

    love.graphics.setColor(0.1, 0.1, 0.16, 0.96)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 12)
    love.graphics.setColor(0.4, 0.6, 0.3, 0.5)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 12)

    -- Title
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(22))
    love.graphics.printf("SHOP", panelX, panelY + 12, panelW, "center")

    -- Gold display
    love.graphics.setFont(love.graphics.newFont(14))
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.printf("$" .. shop.gold, panelX + panelW - 120, panelY + 16, 100, "right")

    -- Close button
    local closeX = panelX + panelW - 36
    local closeY = panelY + 8
    local mx, my = love.mouse.getPosition()
    mx = mx / dpiScale; my = my / dpiScale
    local closeHover = mx >= closeX and mx <= closeX + 28 and my >= closeY and my <= closeY + 28
    love.graphics.setColor(closeHover and 0.8 or 0.4, closeHover and 0.2 or 0.2, closeHover and 0.2 or 0.2, 0.9)
    love.graphics.rectangle("fill", closeX, closeY, 28, 28, 6)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setFont(love.graphics.newFont(16))
    love.graphics.printf("X", closeX, closeY + 4, 28, "center")

    -- Category tabs
    local tabY = panelY + 50
    local tabH = 30
    local tabStartX = panelX + 10
    local tabGap = 4
    local totalTabW = panelW - 20
    local tabCount = #shop.categories
    local tabW = math.floor((totalTabW - tabGap * (tabCount - 1)) / tabCount)

    for i, cat in ipairs(shop.categories) do
        local tx = tabStartX + (i - 1) * (tabW + tabGap)
        local isSelected = shop.selectedCategory == i
        local hover = mx >= tx and mx <= tx + tabW and my >= tabY and my <= tabY + tabH

        love.graphics.setColor(isSelected and 0.25 or 0.12, isSelected and 0.5 or 0.15, isSelected and 0.3 or 0.2, isSelected and 0.9 or 0.8)
        love.graphics.rectangle("fill", tx, tabY, tabW, tabH, 4)
        if isSelected then
            love.graphics.setColor(0.3, 0.8, 0.3, 0.6)
            love.graphics.rectangle("line", tx, tabY, tabW, tabH, 4)
        end

        love.graphics.setColor(isSelected and 1 or 0.7, isSelected and 1 or 0.7, isSelected and 1 or 0.7, isSelected and 1 or 0.7)
        love.graphics.setFont(love.graphics.newFont(11))
        love.graphics.printf(cat.name, tx, tabY + 6, tabW, "center")
    end

    -- Item list
    local items = shop.getFilteredItems()
    local listX = panelX + 12
    local listY = tabY + tabH + 10
    local listW = panelW - 24
    local itemH = 56
    local maxVisible = math.floor((panelY + panelH - 10 - listY) / (itemH + 6))

    for i = 1, math.min(#items, maxVisible) do
        local item = items[i]
        local ix = listX
        local iy = listY + (i - 1) * (itemH + 6)
        local iw = listW
        local already = shop.purchased[item.id]
        local hover = not already and mx >= ix and mx <= ix + iw and my >= iy and my <= iy + itemH
        local buyHover = not already and mx >= ix + iw - 90 and mx <= ix + iw and my >= iy and my <= iy + itemH

        love.graphics.setColor(already and 0.08 or (hover and 0.2 or 0.12), already and 0.12 or (hover and 0.25 or 0.15), already and 0.08 or (hover and 0.28 or 0.18), 0.9)
        love.graphics.rectangle("fill", ix, iy, iw, itemH, 6)
        if hover and not already then
            love.graphics.setColor(0.3, 0.5, 0.4, 0.3)
            love.graphics.rectangle("line", ix, iy, iw, itemH, 6)
        end

        -- Icon
        love.graphics.setColor(already and 0.4 or 1, already and 0.4 or 1, already and 0.4 or 1, already and 0.4 or 1)
        love.graphics.setFont(love.graphics.newFont(18))
        love.graphics.print(item.icon, ix + 8, iy + 14)

        -- Name + desc
        love.graphics.setFont(love.graphics.newFont(13))
        love.graphics.setColor(already and 0.4 or 1, already and 0.4 or 1, already and 0.4 or 1, already and 0.5 or 1)
        love.graphics.print(item.name, ix + 38, iy + 6)

        love.graphics.setFont(love.graphics.newFont(10))
        love.graphics.setColor(already and 0.3 or 0.6, already and 0.3 or 0.6, already and 0.3 or 0.6, already and 0.4 or 0.7)
        love.graphics.printf(item.desc, ix + 38, iy + 26, iw - 130, "left")

        -- Price or purchased
        if already then
            love.graphics.setColor(0.3, 0.7, 0.3, 0.7)
            love.graphics.setFont(love.graphics.newFont(12))
            love.graphics.printf("[x]", ix + iw - 40, iy + 16, 40, "center")
        else
            local canBuy = shop.gold >= item.price
            local btnColor = buyHover and (canBuy and 0.3 or 0.25) or (canBuy and 0.18 or 0.12)
            love.graphics.setColor(btnColor, canBuy and (buyHover and 0.6 or 0.4) or 0.15, buyHover and (canBuy and 0.25 or 0.15) or (canBuy and 0.15 or 0.1), 0.9)
            love.graphics.rectangle("fill", ix + iw - 84, iy + 10, 78, itemH - 20, 4)
            love.graphics.setColor(canBuy and 1 or 0.5, canBuy and 0.85 or 0.4, canBuy and 0.2 or 0.3, canBuy and 1 or 0.6)
            love.graphics.setFont(love.graphics.newFont(11))
            love.graphics.printf("$" .. item.price, ix + iw - 84, iy + 16, 78, "center")
        end
    end

    -- Notification
    if shop.notification and shop.notificationTimer > 0 then
        local alpha = math.min(1, shop.notificationTimer * 4)
        love.graphics.setColor(0.15, 0.5, 0.2, alpha * 0.95)
        love.graphics.rectangle("fill", panelX + panelW/2 - 140, panelY + panelH - 50, 280, 36, 8)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.setFont(love.graphics.newFont(14))
        love.graphics.printf(shop.notification, panelX + panelW/2 - 140, panelY + panelH - 44, 280, "center")
    end
end

function shop.mousepressed(x, y)
    if not shop.isOpen then return false end
    local w, h = logicalW, logicalH
    local panelW, panelH = 600, math.min(h - 80, 520)
    local panelX = w/2 - panelW/2
    local panelY = h/2 - panelH/2

    -- Close button
    local closeX = panelX + panelW - 36
    local closeY = panelY + 8
    if x >= closeX and x <= closeX + 28 and y >= closeY and y <= closeY + 28 then
        shop.isOpen = false
        return true
    end

    -- Category tabs
    local tabY = panelY + 50
    local tabH = 30
    local tabStartX = panelX + 10
    local tabGap = 4
    local tabCount = #shop.categories
    local tabW = math.floor((panelW - 20 - tabGap * (tabCount - 1)) / tabCount)

    for i in ipairs(shop.categories) do
        local tx = tabStartX + (i - 1) * (tabW + tabGap)
        if x >= tx and x <= tx + tabW and y >= tabY and y <= tabY + tabH then
            shop.selectedCategory = i
            return true
        end
    end

    -- Items
    local items = shop.getFilteredItems()
    local listX = panelX + 12
    local listY = tabY + tabH + 10
    local itemH = 56
    local listW = panelW - 24
    local maxVisible = math.floor((panelY + panelH - 10 - listY) / (itemH + 6))

    for i = 1, math.min(#items, maxVisible) do
        local item = items[i]
        local ix = listX
        local iy = listY + (i - 1) * (itemH + 6)
        local iw = listW

        if shop.purchased[item.id] then
            -- already purchased, skip
        elseif x >= ix + iw - 84 and x <= ix + iw and y >= iy + 10 and y <= iy + itemH - 10 then
            if shop.gold >= item.price then
                shop.gold = shop.gold - item.price
                shop.purchased[item.id] = true
                shop.notification = item.name .. " purchased!"
                shop.notificationTimer = 1.5
            else
                shop.notification = "Not enough gold!"
                shop.notificationTimer = 1.5
            end
            return true
        end
    end

    return true
end

function shop.keypressed(key)
    if not shop.isOpen then return false end
    if key == "escape" then
        shop.isOpen = false
        return true
    end
    return false
end

return shop
