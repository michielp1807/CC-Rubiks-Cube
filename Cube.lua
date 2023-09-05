--- ComputerCraft Rubik's Cube by Michiel
local Pine3D = require("Pine3D.Pine3D")
local frame = Pine3D.newFrame()

local abs = math.abs
local sqrt = math.sqrt
local floor = math.floor
local sin = math.sin
local cos = math.cos
local rad = math.rad
local max = math.max
local min = math.min

local SCREEN_WIDTH, SCREEN_HEIGHT = term.getSize()
local keyTurnSpeed = 180
local mouseTurnSpeed = 600 / SCREEN_WIDTH
local ROTATE_SPEED = rad(360) / SCREEN_WIDTH * 0.5
local running = true

local function newPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, c)
    return {
        x1 = x1,
        y1 = y1,
        z1 = z1,
        x2 = x2,
        y2 = y2,
        z2 = z2,
        x3 = x3,
        y3 = y3,
        z3 = z3,
        c = c,
    }
end

local function newCube(options)
    options.color = options.color or colors.black
    local s = (options.scale or 1) / 2
    return {
        -- Order is important: 2 * (axis + slice), with axis 1-3, slice 0-1 (negative or positive)
        -- front / negative x
        newPoly(-s, -s, -s, -s, -s, s, -s, s, -s, options.front or options.color),
        newPoly(-s, -s, s, -s, s, s, -s, s, -s, options.front or options.color),
        -- back / positive x
        newPoly(s, -s, -s, s, s, s, s, -s, s, options.back or options.color),
        newPoly(s, -s, -s, s, s, -s, s, s, s, options.back or options.color),
        -- down / negative y
        newPoly(-s, -s, -s, s, -s, s, -s, -s, s, options.down or options.color),
        newPoly(-s, -s, -s, s, -s, -s, s, -s, s, options.down or options.color),
        -- up / positive y
        newPoly(-s, s, -s, -s, s, s, s, s, s, options.up or options.color),
        newPoly(-s, s, -s, s, s, s, s, s, -s, options.up or options.color),
        -- left / negative z
        newPoly(-s, -s, -s, s, s, -s, s, -s, -s, options.left or options.color),
        newPoly(-s, -s, -s, -s, s, -s, s, s, -s, options.left or options.color),
        -- right / positive z
        newPoly(-s, -s, s, s, -s, s, -s, s, s, options.right or options.color),
        newPoly(s, -s, s, s, s, s, -s, s, s, options.right or options.color),
    }
end

COLOR_BODY = colors.black
COLOR_UP = colors.yellow
COLOR_DOWN = colors.white
COLOR_LEFT = colors.orange
COLOR_RIGHT = colors.red
COLOR_FRONT = colors.green
COLOR_BACK = colors.blue

---@type PineObject[]
local objects = {}
local options = { scale = 1 / 3 }
for x = -1, 1 do
    for y = -1, 1 do
        for z = -1, 1 do
            options.up = y == 1 and COLOR_UP or COLOR_BODY
            options.down = y == -1 and COLOR_DOWN or COLOR_BODY
            options.left = z == -1 and COLOR_LEFT or COLOR_BODY
            options.right = z == 1 and COLOR_RIGHT or COLOR_BODY
            options.front = x == -1 and COLOR_FRONT or COLOR_BODY
            options.back = x == 1 and COLOR_BACK or COLOR_BODY
            local model = newCube((x ~= 0 or y ~= 0 or z ~= 0) and options or { scale = 0.75 })
            local object = frame:newObject(model, x / 2.75, y / 2.75, z / 2.75)
            object.model = model
            objects[#objects + 1] = object
        end
    end
end

local function sign(n)
    if n < -0.0000001 then
        return -1
    elseif n > 0.0000001 then
        return 1
    else
        return 0
    end
end

-- Sort objects into slices
local function newSlice()
    ---@class Slice
    local slice = {
        -- cubes in slice, ordered top to bottom left to right
        ---@type PineObject[]
        cubes = {},

        -- faces around the slice, in cyclic order
        -- 1-3: outward facing faces from slice
        -- 4-7: left and right sides of outside of slice
        ---@type Face[][]
        faces = { {}, {}, {}, {}, {}, {}, {} }
    }
    return slice
end

---@type Slice[][]
local slices = {
    { newSlice(), newSlice(), newSlice() }, -- x slices
    { newSlice(), newSlice(), newSlice() }, -- y slices
    { newSlice(), newSlice(), newSlice() }, -- z slices
}

-- Add cubes to the correct slices for every axis
for i = 1, #objects do
    local cube = objects[i]
    for axis = 1, 3 do
        -- sign remapped to from 1 to 3
        local x = sign(cube[axis]) + 2               -- this axis' coordinate sign (slice 1, 2, or 3)
        local y = sign(cube[axis % 3 + 1]) + 2       -- next axis' coordinate sign
        local z = sign(cube[(axis + 1) % 3 + 1]) + 2 -- last axis' coordinate sign
        slices[axis][x].cubes[(y - 1) * 3 + z] = cube
    end
end

---@param obj PineObject (with model reference included)
---@param axis integer 1-3 for xyz
---@param side integer 0 or 1 for negative or positive side
---@return PinePoly[]
local function getFace(obj, axis, side)
    local i = 1 + 2 * (2 * (axis - 1) + side)
    ---@type PinePoly[]
    ---@diagnostic disable-next-line: undefined-field
    local model = obj.model

    ---@class Face
    local face = {
        -- object = obj,
        model[i],
        model[i + 1]
    }
    return face
end

local ROTATE_INDEX = {
    5, 6, 7,
    4, nil, 0,
    3, 2, 1
}
local ROTATE_INDEX_INV = {
    6, 9, 8, 7, 4, 1, 2, 3
}

--- Gather faces for every slice
for axis = 1, 3 do
    for sliceIndex = 1, 3 do
        local slice = slices[axis][sliceIndex]
        local y = axis % 3 + 1       -- next axis'
        local z = (axis + 1) % 3 + 1 -- last axis'

        -- Outward facing faces
        for i = 1, 3 do
            slice.faces[i][1] = getFace(slice.cubes[i], y, 0)
        end
        for i = 1, 3 do
            slice.faces[i][2] = getFace(slice.cubes[3 * i], z, 1)
        end
        for i = 1, 3 do
            slice.faces[i][3] = getFace(slice.cubes[10 - i], y, 1)
        end
        for i = 1, 3 do
            slice.faces[i][4] = getFace(slice.cubes[10 - 3 * i], z, 0)
        end

        -- Sideways facing faces
        for j = 1, 8 do
            local ci = ROTATE_INDEX_INV[j]
            local fi = floor((j + 1) / 2)
            slice.faces[4 + j % 2][fi] = getFace(slice.cubes[ci], axis, 0)
            slice.faces[6 + j % 2][fi] = getFace(slice.cubes[ci], axis, 1)
        end
    end
end

-- Load colors from configuration file
local CONF_FILE = "cube.conf"
local conf_data = {}
if fs.exists(CONF_FILE) then
    local file = fs.open(CONF_FILE, "r")
    if not file then error("Can't read file " .. CONF_FILE .. "...") end
    local str = file.readAll()
    file.close()
    conf_data = textutils.unserialise(str or "") or {}

    if conf_data.cubeColors then
        -- Apply cube colors from file
        for axis = 1, 3 do
            for side = 0, 1 do
                local sideColors = conf_data.cubeColors[2 * (axis - 1) + side + 1]
                local slice = slices[axis][side * 2 + 1]
                for i = 1, 9 do
                    local cube = slice.cubes[i]
                    local face = getFace(cube, axis, side)
                    face[1].c = sideColors[i]
                    face[2].c = sideColors[i]
                    ---@diagnostic disable-next-line: undefined-field
                    cube:setModel(cube.model)
                end
            end
        end
    end
end

local function saveToFile()
    local str = textutils.serialise(conf_data)
    local file = fs.open(CONF_FILE, "w")
    if not file then error("Can't write to file " .. CONF_FILE .. "...") end
    file.write(str)
    file.close()
end

local NUM_OBJECTS = #objects -- number of default objects (i.e. the cubes)
local NUM_PARTICLES = 200
local CONFETTI_COLORS = {
    COLOR_UP, COLOR_DOWN, COLOR_LEFT, COLOR_RIGHT, COLOR_FRONT, COLOR_BACK
}
---@type PinePoly[]
local confetti = {
    {
        x1 = 0,
        y1 = 0,
        z1 = 0,
        x2 = 0.1,
        y2 = 0,
        z2 = 0,
        x3 = 0.05,
        y3 = 0.075,
        z3 = 0,
        c = colors.white,
        forceRender = true
    }
}
local function initConfetti()
    local i = 1
    while #objects < NUM_OBJECTS + NUM_PARTICLES do
        i = i + 1
        local r = sin(i * 140)
        confetti[1].c = CONFETTI_COLORS[(i % #CONFETTI_COLORS) + 1]
        local particle = frame:newObject(confetti, 0, 5 + 2 * r, 0, 0, 0, 0)
        particle.ty = "confetti"
        particle.ind = i
        objects[#objects + 1] = particle
    end
end

local function animateConfetti(time, dt)
    for i = #objects, 1, -1 do
        local obj = objects[i]
        ---@diagnostic disable-next-line: undefined-field
        if obj.ty == "confetti" then
            ---@diagnostic disable-next-line: undefined-field
            local offset = 51 * obj.ind / NUM_PARTICLES
            local d = (5.45 * offset) % 6 + 1
            ---@diagnostic disable-next-line: undefined-field
            local a = (0.4532378 * obj.ind) % 1 + 1
            obj[1] = d * sin(time * 0.2 * a + offset) -- x
            obj[2] = obj[2] - a * dt                  -- y
            obj[3] = d * cos(time * 0.2 * a + offset) -- z
            if obj[2] < -3 then
                table.remove(objects, i)
            end
        end
    end
end

local DIST_STRAIGT = 1 / 2.75
local DIST_CORNER = math.sqrt(2 * DIST_STRAIGT ^ 2)

---Rotate a side of the cube
---@type number|nil
local rot = 0               -- how for to rotate (in radians)
local currentAxis = 1       -- 1, 2, 3 for x, y, or z
local currentSliceIndex = 1 -- 1, 2, 3 for slice index
local function rotateSlice()
    if not rot then return end

    local r = currentAxis == 2 and -rot or rot
    for i, obj in ipairs(slices[currentAxis][currentSliceIndex].cubes) do
        obj[3 + currentAxis] = r
        local da = ROTATE_INDEX[i]
        if da then
            da = da * math.pi / 4
            -- y axis rotates in wrong direction
            local d = (i % 2) == 1 and DIST_CORNER or DIST_STRAIGT
            obj[currentAxis % 3 + 1] = d * sin(rot + da)
            obj[(currentAxis + 1) % 3 + 1] = d * cos(rot + da)
        end
    end
    if rot == 0 then rot = nil end
end

local SNAP_ANGLE = rad(90)
local solveTime = nil

---Apply colors and reset rotations
---@param dontSave? boolean do not save configuration to file
local function applyRotation(dontSave)
    if not rot or rot == 0 then return end

    local turns = floor(rot / SNAP_ANGLE + 0.5)
    rot = 0
    rotateSlice()
    if turns == 0 then return end

    local slice = slices[currentAxis][currentSliceIndex]

    -- Swap colors based on number of turns
    for j = 1, 7 do
        local faces = slice.faces[j]
        local prevColors = {}
        -- Collect previous colors
        for i = 1, 4 do
            local square = faces[i]
            prevColors[i] = square[1].c
        end
        -- Apply new colors
        for i = 1, 4 do
            local square = faces[i]
            local ci = (i - turns - 1) % 4 + 1
            square[1].c = prevColors[ci]
            square[2].c = prevColors[ci]
        end
    end

    -- Reapply models to show color changes
    for i = 1, 9 do
        local cube = slice.cubes[i]
        ---@diagnostic disable-next-line: undefined-field
        cube:setModel(cube.model)
    end

    -- Save current configuration to file
    if dontSave then return end
    local allColors = {}
    solveTime = os.epoch("utc")
    for axis = 1, 3 do
        for side = 0, 1 do
            local sideColors = {}
            local slice = slices[axis][side * 2 + 1]
            local firstColor = nil
            for i = 1, 9 do
                local cube = slice.cubes[i]
                local face = getFace(cube, axis, side)
                sideColors[i] = face[1].c
                -- Check if all colors on this side are the same
                if firstColor then
                    if sideColors[i] ~= firstColor then solveTime = nil end
                else
                    firstColor = sideColors[i]
                end
            end
            allColors[2 * (axis - 1) + side + 1] = sideColors
        end
    end
    conf_data.cubeColors = allColors
    conf_data.numMoves = (conf_data.numMoves or 0) + 1
    saveToFile()

    if solveTime then initConfetti() end
end

local clickedFaceAxis, clickedObject
local cubeIsDragging = false
local cubeDragStartX, cubeDragStartY = 0, 0
local cubeDragNewX, cubeDragNewY = 0, 0
local rAxis1mapX, rAxis1mapY, rAxis2mapX, rAxis2mapY
local cubeMouseHandlers = {
    mouse_click = function(x, y)
        local objectIndex, polyIndex = frame:getObjectIndexTrace(objects, x, y)
        if not objectIndex or not polyIndex then return end

        cubeDragStartX, cubeDragStartY = x, y
        cubeDragNewX, cubeDragNewY = x, y
        cubeIsDragging = true

        -- Reset rotation
        applyRotation()

        -- Start rotating slice
        clickedFaceAxis = floor((polyIndex - 1) / 4) + 1       -- 1 to 3 axis of face that was clicked
        local clickedFaceSide = floor((polyIndex - 1) / 2) % 2 -- 0 or 1 for negative or positive side
        clickedFaceSide = clickedFaceSide * 2 - 1              -- -1 or 1

        clickedObject = objects[objectIndex]
        currentSliceIndex = sign(clickedObject[currentAxis]) + 2

        local center = { clickedObject[1], clickedObject[2], clickedObject[3] }
        local oX, oY = frame:map3dTo2d(center[1], center[2], center[3])

        -- first rotation axis vector
        local nextAxis = clickedFaceAxis % 3 + 1
        center[nextAxis] = center[nextAxis] - clickedFaceSide
        local aX, aY = frame:map3dTo2d(center[1], center[2], center[3])
        center[nextAxis] = clickedObject[nextAxis]
        rAxis1mapX = aX - oX
        rAxis1mapY = aY - oY
        local axis1len = sqrt(rAxis1mapX ^ 2 + rAxis1mapY ^ 2)
        rAxis1mapX = rAxis1mapX / axis1len -- normalize
        rAxis1mapY = rAxis1mapY / axis1len

        -- second rotation axis vector
        nextAxis = nextAxis % 3 + 1
        center[nextAxis] = center[nextAxis] + clickedFaceSide
        local bX, bY = frame:map3dTo2d(center[1], center[2], center[3])
        rAxis2mapX = bX - oX
        rAxis2mapY = bY - oY
        local axis2len = sqrt(rAxis2mapX ^ 2 + rAxis2mapY ^ 2)
        rAxis2mapX = rAxis2mapX / axis2len -- normalize
        rAxis2mapY = rAxis2mapY / axis2len
    end,
    mouse_drag = function(x, y)
        if not cubeIsDragging then return end
        cubeDragNewX, cubeDragNewY = x, y
        local dX = (cubeDragNewX - cubeDragStartX) * 2
        local dY = (cubeDragNewY - cubeDragStartY) * 3

        local lAxis1 = dX * rAxis1mapX + dY * rAxis1mapY -- dot product
        local lAxis2 = dX * rAxis2mapX + dY * rAxis2mapY

        local rotAxis = {}
        rotAxis[clickedFaceAxis] = 0
        rotAxis[clickedFaceAxis % 3 + 1] = lAxis2
        rotAxis[(clickedFaceAxis + 1) % 3 + 1] = lAxis1

        if abs(lAxis1) < 5 and abs(lAxis2) < 5 then -- only switch if close to no rotation
            local newAxis = (clickedFaceAxis + (abs(lAxis1) > abs(lAxis2) and 1 or 0)) % 3 + 1
            if newAxis ~= currentAxis then
                rot = 0
                rotateSlice()
                currentAxis = newAxis
                currentSliceIndex = sign(clickedObject[currentAxis]) + 2
            end
        end

        rot = rotAxis[currentAxis] * ROTATE_SPEED
    end,
    mouse_up = function(x, y)
        cubeIsDragging = false
        applyRotation()
    end
}

---@param amount integer
local function shuffle(amount)
    cubeIsDragging = false
    applyRotation()

    for _ = 1, amount do
        currentAxis = math.random(1, 3)
        currentSliceIndex = math.random(1, 3)
        rot = SNAP_ANGLE * math.random(1, 3)
        rotateSlice()
        applyRotation(true)
    end
    conf_data.lastShuffle = os.epoch("utc")
    conf_data.numMoves = 0
    solveTime = nil
end

local function terminate()
    local function formatTime(time)
        local s = time / 1000
        local m = floor(s / 60)
        s = s - 60 * m
        return m .. "m" .. s .. "s"
    end

    running = false
    if solveTime and conf_data.lastShuffle then
        -- Update fastest time
        local time = solveTime - conf_data.lastShuffle
        local newFastestTime = false
        if not conf_data.fastestTime or time < conf_data.fastestTime then
            newFastestTime = true
            conf_data.fastestTime = time
        end
        -- Update fewest moves
        local newFewestMoves = false
        if not conf_data.fewestMoves or conf_data.numMoves < conf_data.fewestMoves then
            newFewestMoves = true
            conf_data.fewestMoves = conf_data.numMoves
        end
        saveToFile()

        term.setTextColor(colors.yellow)
        print("Solved in " .. conf_data.numMoves .. " moves in " .. formatTime(time) .. "!\n")
        term.setTextColor(colors.white)


        term.write(" Fastest time: ") --.. formatTime(conf_data.fastestTime))
        if newFastestTime then
            term.setTextColor(colors.orange)
            print(formatTime(conf_data.fastestTime) .. " [New best!]")
            term.setTextColor(colors.white)
        else
            print(formatTime(conf_data.fastestTime))
        end

        term.write(" Fewest moves: ")
        if newFewestMoves then
            term.setTextColor(colors.orange)
            print(conf_data.fewestMoves .. " [New best!]")
            term.setTextColor(colors.white)
        else
            print(conf_data.fewestMoves)
        end
    end
    print("\nGood bye!")
end

local camDragStartX, camDragStartY = 0, 0
local camDragNewX, camDragNewY = 0, 0
local cameraMouseHandlers = {
    mouse_click = function(x, y)
        camDragStartX, camDragStartY = x, y
        camDragNewX, camDragNewY = x, y
    end,
    mouse_drag = function(x, y)
        camDragNewX, camDragNewY = x, y
    end,
    mouse_up = function(x, y)
        camDragStartX, camDragStartY = 0, 0
        camDragNewX, camDragNewY = 0, 0
    end
}

local MOUSE_CUBE_BUTTON = 1
local MOUSE_CAM_BUTTON = 2
local distance = 2
local keysDown = {}
local shuffling = false
local function userInput()
    while running do
        local event, which, x, y = os.pullEventRaw()
        if event == "key" then
            if which == keys.space and not shuffling then
                shuffle(20)
                shuffling = true
            elseif which == keys.grave then
                terminate()
            end
            keysDown[which] = true
        elseif event == "key_up" then
            if which == keys.space then shuffling = false end
            keysDown[which] = nil
        elseif event == "mouse_scroll" then
            if which > 0 then
                distance = min(10, distance + 0.2)
            else
                distance = max(1, distance - 0.2)
            end
        elseif event:find("^mouse") then
            if which == MOUSE_CAM_BUTTON then
                local handler = cameraMouseHandlers[event]
                if handler then handler(x, y) end
            elseif which == MOUSE_CUBE_BUTTON then
                local handler = cubeMouseHandlers[event]
                if handler then handler(x, y) end
            end
        elseif event == "term_resize" then
            SCREEN_WIDTH, SCREEN_HEIGHT = term.getSize()
            mouseTurnSpeed = 600 / SCREEN_WIDTH
            ROTATE_SPEED = rad(360) / SCREEN_WIDTH * 0.5
            frame:setSize(1, 1, SCREEN_WIDTH, SCREEN_HEIGHT)
        elseif event == "terminate" then
            terminate()
        end
    end
end

local camera = {
    x = -distance,
    y = 0,
    z = 0,
    rotX = 0,
    rotY = -135,
    rotZ = -30,
}
local function handleCameraMovement(dt)
    -- handle arrow keys for camera rotation
    if keysDown[keys.left] or keysDown[keys.a] then
        camera.rotY = (camera.rotY - keyTurnSpeed * dt) % 360
    end
    if keysDown[keys.right] or keysDown[keys.d] then
        camera.rotY = (camera.rotY + keyTurnSpeed * dt) % 360
    end
    if keysDown[keys.down] or keysDown[keys.s] then
        camera.rotZ = min(90, camera.rotZ + keyTurnSpeed * dt)
    end
    if keysDown[keys.up] or keysDown[keys.w] then
        camera.rotZ = max(-90, camera.rotZ - keyTurnSpeed * dt)
    end

    -- handle mouse drag for camera rotation
    camera.rotY = (camera.rotY + mouseTurnSpeed * (camDragNewX - camDragStartX)) % 360
    camera.rotZ = min(90, max(-90, camera.rotZ - mouseTurnSpeed * (camDragNewY - camDragStartY)))
    camDragStartX, camDragStartY = camDragNewX, camDragNewY

    -- update distance from keyboard presses
    if keysDown[keys.pageUp] or keysDown[keys.q] then
        distance = max(1, distance - 0.01)
    end
    if keysDown[keys.pageDown] or keysDown[keys.e] then
        distance = min(10, distance + 0.01)
    end

    -- set camera position based on rotation and distance
    local a = rad(camera.rotZ)
    local distanceXZ = -cos(a) * distance
    camera.y = -sin(a) * distance

    a = rad(camera.rotY)
    camera.x = cos(a) * distanceXZ
    camera.z = sin(a) * distanceXZ

    frame:setCamera(camera)
end

local function gameLoop()
    local lastTime = os.clock()

    while running do
        -- compute the time passed since last step
        local currentTime = os.clock()
        local dt = currentTime - lastTime
        lastTime = currentTime

        -- rotate slices that is currently being rotated (currentAxis, currentSlice)
        rotateSlice()

        -- run all functions that need to be run
        handleCameraMovement(dt)
        if #objects > NUM_OBJECTS then animateConfetti(currentTime, dt) end

        -- keep randomly shuffling
        if keysDown[keys.space] then shuffle(1) end

        -- use a fake event to yield the coroutine
        os.queueEvent("gameLoop")
        ---@diagnostic disable-next-line: param-type-mismatch
        os.pullEventRaw("gameLoop")
    end
end

local environmentObjects = {
    frame:newObject(Pine3D.models:mountains({
        color = colors.lightGray,
        y = -10,
        res = 12,
        scale = 100,
        randomHeight = 0.5,
        randomOffset = 0.5,
        snow = true,
        snowHeight = 0.6,
    })),
    frame:newObject(Pine3D.models:mountains({
        color = colors.brown,
        y = -10,
        res = 18,
        scale = 75,
        randomHeight = 0.5,
        randomOffset = 0.25,
    })),
    frame:newObject(Pine3D.models:plane({
        color = colors.gray,
        size = 200,
        y = -12,
    })),
}

local function rendering()
    while running do
        frame:drawObjects(environmentObjects)
        frame:drawObjects(objects)
        frame:drawBuffer()

        os.queueEvent("FakeEvent")
        ---@diagnostic disable-next-line: param-type-mismatch
        os.pullEvent("FakeEvent")
    end
end

parallel.waitForAll(userInput, gameLoop, rendering)
