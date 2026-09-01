lovr.mouse = require 'lovr.lovr-mouse'

local model
local shader

local world
local groundCollider
local playground = {}

local player = {
    position = vector(0, 0, 0),

    speed = 10,
    jumpSpeed = 7,

    moveX = 0,
    moveZ = 0,

    radius = .25,
    height = 1.2,

    grounded = false,

    transform = lovr.math.newMat4(),
    collider = nil
}

local camera = {
    transform = lovr.math.newMat4(),

    yaw = 0,
    pitch = .15,

    distance = 10,
    height = 4,

    sensitivity = .004
}

local function drawPlaygroundDebug(pass)
    for _, object in ipairs(playground) do
        local x, y, z = object.collider:getPosition()
        local angle, ax, ay, az = object.collider:getOrientation()

        --------------------------------------------------
        -- COLLIDER BOX
        --------------------------------------------------

        -- Bright green transparent box = physics collider
        pass:setColor(0, 1, 0, .25)

        pass:box(x, y, z, object.width, object.height, object.depth, angle, ax,
                 ay, az, 'line')

        --------------------------------------------------
        -- CENTER POINT
        --------------------------------------------------

        pass:setColor(1, 0, 0)

        pass:sphere(x, y, z, .08)

        --------------------------------------------------
        -- LOCAL UP AXIS
        --------------------------------------------------

        -- This gives us a quick visual indication of
        -- the collider's rotation.
        local transform = lovr.math.newMat4()

        transform:set(x, y, z, 1, angle, ax, ay, az)

        local upX, upY, upZ = transform:mul(0, 1, 0)

        pass:setColor(0, 0, 1)

        pass:line(x, y, z, upX, upY, upZ)
    end

    pass:setColor(1, 1, 1)
end

--------------------------------------------------
-- PLAYGROUND
--------------------------------------------------

local function addBox(x, y, z, width, height, depth, angle)
    angle = angle or 0

    local collider = world:newBoxCollider(x, y, z, width, height, depth)

    collider:setKinematic(true)

    if angle ~= 0 then collider:setOrientation(angle, 1, 0, 0) end

    table.insert(playground, {
        collider = collider,

        width = width,
        height = height,
        depth = depth
    })

    return collider
end

--------------------------------------------------
-- GROUNDED CHECK
--------------------------------------------------

local function checkGrounded()
    local x, y, z = player.collider:getPosition()

    local feetY = y - player.height / 2

    local collider = world:raycast(x, feetY + .05, z, x, feetY - .15, z,

                                   '~player')

    player.grounded = collider ~= nil
end

--------------------------------------------------
-- DEBUG AXES
--------------------------------------------------

local function drawDebugAxes(pass)
    local x = player.position.x
    local y = player.position.y + 1.2
    local z = player.position.z

    local length = 1.5

    --------------------------------------------------
    -- MOVEMENT
    --------------------------------------------------

    pass:setColor(1, 1, 0)

    pass:line(x, y + .15, z, x + player.moveX * length, y + .15,
              z + player.moveZ * length)

    --------------------------------------------------
    -- CAMERA FORWARD
    --------------------------------------------------

    local cameraForwardX = -math.sin(camera.yaw)
    local cameraForwardZ = -math.cos(camera.yaw)

    pass:setColor(0, 1, 0)

    pass:line(x, y + .3, z, x + cameraForwardX * length, y + .3,
              z + cameraForwardZ * length)

    --------------------------------------------------
    -- UP
    --------------------------------------------------

    pass:setColor(0, 0, 1)

    pass:line(x, y, z, x, y + length, z)

    pass:setColor(1, 1, 1)
end

--------------------------------------------------
-- LOAD
--------------------------------------------------

function lovr.load()
    lovr.mouse.setRelativeMode(true)

    model = lovr.graphics.newModel('character-a.glb')

    --------------------------------------------------
    -- PHYSICS WORLD
    --------------------------------------------------

    world = lovr.physics.newWorld({tags = {'player'}})

    --------------------------------------------------
    -- PLAYER COLLIDER
    --------------------------------------------------

    player.collider = world:newCollider(0, player.height / 2, 0)

    local capsule = lovr.physics.newCapsuleShape(player.radius, player.height -
                                                     player.radius * 2)

    -- Rotate the shape locally from Z-axis to Y-axis
    capsule:setOffset(0, 0, 0, math.pi / 2, 1, 0, 0)

    player.collider:addShape(capsule)

    player.collider:setTag('player')
    player.collider:setFriction(.2)
    player.collider:setContinuous(true)

    -- Allow XYZ movement, prevent the capsule from tipping/rotating
    player.collider:setDegreesOfFreedom('xyz', '')

    --------------------------------------------------
    -- GROUND
    --------------------------------------------------

    groundCollider = world:newBoxCollider(0, -.5, 0, 50, 1, 50)

    groundCollider:setKinematic(true)

    --------------------------------------------------
    -- PLAYGROUND
    --------------------------------------------------

    -- Small step
    addBox(3, .25, -3, 2, .5, 2)

    -- Medium step
    addBox(5, .5, -3, 2, 1, 2)

    -- Large block
    addBox(8, 1, -3, 4, 2, 4)

    -- Wall
    addBox(-5, 1.5, -5, 8, 3, .5)

    -- Tall pillar
    addBox(-5, 2, 3, 1, 4, 1)

    -- Short pillar
    addBox(-2, 1.25, 5, 1.5, 2.5, 1.5)

    -- Raised platform
    addBox(5, 2.5, 8, 5, .5, 5)

    -- Ramp
    addBox(5, .85, 3.5, 3, .4, 5, math.rad(-20))

    --------------------------------------------------
    -- SHADER
    --------------------------------------------------

    shader = lovr.graphics.newShader([[
        vec4 lovrmain() {
            return DefaultPosition;
        }
    ]], [[
        #define BANDS 5.0

        vec4 lovrmain() {
            const vec3 lightDirection = vec3(-1, -1, -1);

            vec3 L = normalize(-lightDirection);
            vec3 N = normalize(Normal);

            float light = max(dot(N, L), 0.0);

            light = round(light * BANDS) / BANDS;
            light = .25 + light * .75;

            vec4 baseColor =
                Color * getPixel(ColorTexture, UV);

            return vec4(
                baseColor.rgb * light,
                baseColor.a
            );
        }
    ]])
end

--------------------------------------------------
-- UPDATE
--------------------------------------------------

function lovr.update(dt)

    --------------------------------------------------
    -- INPUT
    --------------------------------------------------

    local inputX = 0
    local inputZ = 0

    if lovr.system.isKeyDown('w', 'up') then inputZ = inputZ + 1 end

    if lovr.system.isKeyDown('s', 'down') then inputZ = inputZ - 1 end

    if lovr.system.isKeyDown('a', 'left') then inputX = inputX - 1 end

    if lovr.system.isKeyDown('d', 'right') then inputX = inputX + 1 end

    --------------------------------------------------
    -- CAMERA-RELATIVE MOVEMENT
    --------------------------------------------------

    local forwardX = -math.sin(camera.yaw)
    local forwardZ = -math.cos(camera.yaw)

    local rightX = -forwardZ
    local rightZ = forwardX

    local dx = forwardX * inputZ + rightX * inputX

    local dz = forwardZ * inputZ + rightZ * inputX

    local length = math.sqrt(dx * dx + dz * dz)

    if length > 0 then
        dx = dx / length
        dz = dz / length

        player.moveX = dx
        player.moveZ = dz
    else
        dx = 0
        dz = 0
    end

    --------------------------------------------------
    -- MOVEMENT
    --------------------------------------------------

    local vx, vy, vz = player.collider:getLinearVelocity()

    player.collider:setLinearVelocity(dx * player.speed, vy, dz * player.speed)

    --------------------------------------------------
    -- PHYSICS STEP
    --------------------------------------------------

    world:update(dt)

    --------------------------------------------------
    -- READ PLAYER POSITION FROM PHYSICS
    --------------------------------------------------

    local x, y, z = player.collider:getPosition()

    player.position.x = x

    -- Model origin is at the character's feet.
    player.position.y = y - player.height / 2

    player.position.z = z

    --------------------------------------------------
    -- GROUNDED
    --------------------------------------------------

    checkGrounded()

    --------------------------------------------------
    -- THIRD-PERSON CAMERA
    --------------------------------------------------

    local targetX = player.position.x
    local targetY = player.position.y + 1.2
    local targetZ = player.position.z

    local cosPitch = math.cos(camera.pitch)

    local cameraX = targetX + math.sin(camera.yaw) * cosPitch * camera.distance

    local cameraY = targetY + math.sin(camera.pitch) * camera.distance

    local cameraZ = targetZ + math.cos(camera.yaw) * cosPitch * camera.distance

    camera.transform:lookAt(cameraX, cameraY, cameraZ, targetX, targetY, targetZ)

    camera.transform:invert()
end

--------------------------------------------------
-- DRAW
--------------------------------------------------

function lovr.draw(pass)

    pass:setViewPose(1, camera.transform)

    --------------------------------------------------
    -- CHARACTER
    --------------------------------------------------

    pass:setShader(shader)

    pass:setColor(1, 1, 1)

    local px = player.position.x
    local py = player.position.y
    local pz = player.position.z

    if player.moveX ~= 0 or player.moveZ ~= 0 then

        player.transform:target(vector(px, py, pz), vector(px - player.moveX,
                                                           py, pz - player.moveZ),

                                vector(0, 1, 0))

    else

        player.transform:setPosition(px, py, pz)

    end

    pass:draw(model, player.transform)

    pass:setShader()

    --------------------------------------------------
    -- DEBUG AXES
    --------------------------------------------------

    drawDebugAxes(pass)

    --------------------------------------------------
    -- DEBUG PLAYER CAPSULE
    --------------------------------------------------

    local cx, cy, cz = player.collider:getPosition()

    if player.grounded then
        -- Cyan = grounded
        pass:setColor(0, 1, 1, .35)
    else
        -- Magenta = airborne
        pass:setColor(1, 0, 1, .35)
    end

    pass:capsule(cx, cy, cz, player.radius, player.height - player.radius * 2,

                 math.pi / 2, 1, 0, 0)

    --------------------------------------------------
    -- FLOOR
    --------------------------------------------------

    pass:setColor(.3, .3, .3)

    pass:plane(0, 0, 0, 50, 50, math.pi / 2, 1, 0, 0)

    --------------------------------------------------
    -- PLAYGROUND
    --------------------------------------------------

    pass:setColor(.45, .45, .5)

    for _, object in ipairs(playground) do

        local x, y, z = object.collider:getPosition()

        local angle, ax, ay, az = object.collider:getOrientation()

        pass:box(x, y, z, object.width, object.height, object.depth, angle, ax,
                 ay, az)

    end

    drawPlaygroundDebug(pass)

    pass:setColor(1, 1, 1)
end

--------------------------------------------------
-- MOUSE
--------------------------------------------------

function lovr.mousemoved(x, y, dx, dy)

    camera.yaw = camera.yaw - dx * camera.sensitivity

    camera.pitch = camera.pitch - dy * camera.sensitivity

    camera.pitch = math.max(-.5, math.min(.8, camera.pitch))
end

--------------------------------------------------
-- KEYBOARD
--------------------------------------------------

function lovr.keypressed(key)

    --------------------------------------------------
    -- JUMP
    --------------------------------------------------

    if key == 'space' and player.grounded then

        local vx, vy, vz = player.collider:getLinearVelocity()

        player.collider:setLinearVelocity(vx, player.jumpSpeed, vz)

        player.grounded = false
    end

    --------------------------------------------------
    -- QUIT
    --------------------------------------------------

    if key == 'escape' then
        lovr.mouse.setRelativeMode(false)
        lovr.event.quit()
    end
end
