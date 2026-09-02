lovr.mouse = require 'lovr.lovr-mouse'

local model
local shader

local world
local groundCollider
local playground = {}

local particles = {}
local spawnTimer = 0
local spawnRate = 1 / 2.5 -- 2.5 particles per second

local player = {
    position = vector(0, 0, 0),

    speed = 10,
    jumpSpeed = 11,

    -- How quickly horizontal velocity ramps toward its target, in units/s^2.
    -- Higher = snappier turns, lower = more slide/inertia.
    groundAcceleration = 60,
    airAcceleration = 20, -- lower air control avoids fighting wall contacts

    moveX = 0,
    moveZ = 0,

    minSpeedForFacing = .1, -- below this, keep last facing instead of jittering

    radius = .5,
    height = 2,

    grounded = false,

    -- Gravity feel: falling uses a stronger pull than rising, for a
    -- snappier arc (standard platformer trick). 1.0 = world default.
    fallGravityScale = 1.6,
    riseGravityScale = 1.0,

    maxFallSpeed = 25, -- terminal velocity, in units/s

    transform = lovr.math.newMat4(),
    collider = nil,

    anim = {
        current = 1, -- idle
        next = nil,
        time = 0,
        nextTime = 0,
        blend = 0,
        duration = .2
    }
}

local camera = {
    transform = lovr.math.newMat4(),

    yaw = 0,
    pitch = .15,

    distance = 10,
    height = 4,

    minHeight = .3, -- floor is at y=0; keep the camera at least this far above it

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

local function spawnParticle(x, y, z)
    table.insert(particles, {
        position = lovr.math.newVec3(x, y, z),
        velocity = lovr.math
            .newVec3((math.random() - 0.5) * 2, -- x direction/speed
        math.random() * 3, -- y direction/speed (upward)
        (math.random() - 0.5) * 2 -- z direction/speed
        ),
        life = 1.0, -- seconds remaining
        maxLife = 1.0,
        color = {0.8, 0.8, 0.8}
    })
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
-- ANIMATION
--------------------------------------------------

-- Crossfades to a new animation instead of snapping to it. Safe to call
-- every frame; it's a no-op once already playing (or transitioning to)
-- the requested animation.
local function playAnimation(index, crossfadeTime)
    local anim = player.anim

    if index == anim.current or index == anim.next then return end

    anim.next = index
    anim.nextTime = 0
    anim.blend = 0
    anim.duration = crossfadeTime or .2
end

-- Advances animation playback and applies the blended pose to the model.
-- Called once per frame from lovr.update (NOT lovr.draw, which runs once
-- per eye in VR and would double-apply / desync the animation clock).
local function updateAnimation(dt)
    local anim = player.anim

    anim.time = anim.time + dt

    if anim.next then
        anim.nextTime = anim.nextTime + dt
        anim.blend = math.min(anim.blend + dt / anim.duration, 1)

        model:animate(anim.current, anim.time, 1 - anim.blend)
        model:animate(anim.next, anim.nextTime, anim.blend)

        if anim.blend >= 1 then
            anim.current = anim.next
            anim.time = anim.nextTime
            anim.next = nil
        end
    else
        model:animate(anim.current, anim.time)
    end
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
    local y = player.position.y + 2
    local z = player.position.z

    local length = 2

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
    local cameraForwardZ = -math.cos(camera.pitch)

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

    -- Default gravity (~9.81) reads as floaty at this scale/speed; roughly
    -- 2.5x that feels a lot more grounded. jumpSpeed above was bumped up
    -- to compensate, so jump height stays about the same.
    world:setGravity(0, -24, 0)

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
    addBox(5, 1.625, 8.25, 5, .5, 5)

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
    -- CAMERA-RELATIVE DESIRED DIRECTION
    --------------------------------------------------

    local forwardX = -math.sin(camera.yaw)
    local forwardZ = -math.cos(camera.yaw)

    local rightX = -forwardZ
    local rightZ = forwardX

    local desiredX = forwardX * inputZ + rightX * inputX
    local desiredZ = forwardZ * inputZ + rightZ * inputX

    local desiredLength = math.sqrt(desiredX * desiredX + desiredZ * desiredZ)

    if desiredLength > 0 then
        desiredX = desiredX / desiredLength
        desiredZ = desiredZ / desiredLength
    end

    --------------------------------------------------
    -- SMOOTHED (ACCELERATION-LIMITED) MOVEMENT
    --------------------------------------------------

    -- Instead of snapping straight to the target speed, ramp the horizontal
    -- velocity toward it. This smooths direction changes, and — crucially —
    -- it starts from whatever velocity the physics solver actually produced
    -- last step, rather than blindly overwriting it. That's what let the
    -- player get pinned against walls in the air: a hard setLinearVelocity()
    -- every frame fights any push-back the solver applies on contact.

    local vx, vy, vz = player.collider:getLinearVelocity()

    local targetVX = desiredX * player.speed
    local targetVZ = desiredZ * player.speed

    local acceleration = player.grounded and player.groundAcceleration or
                             player.airAcceleration

    local dvx = targetVX - vx
    local dvz = targetVZ - vz

    local dv = math.sqrt(dvx * dvx + dvz * dvz)
    local maxDelta = acceleration * dt

    if dv > maxDelta and dv > 1e-6 then
        local scale = maxDelta / dv

        dvx = dvx * scale
        dvz = dvz * scale
    end

    local newVX = vx + dvx
    local newVZ = vz + dvz

    player.collider:setLinearVelocity(newVX, vy, newVZ)

    --------------------------------------------------
    -- FACING DIRECTION
    --------------------------------------------------

    -- Derive facing from the resulting velocity rather than raw input, so
    -- the character (and debug arrow) turns smoothly and matches what's
    -- actually happening physically (e.g. sliding along a wall).

    local speedSq = newVX * newVX + newVZ * newVZ

    if speedSq > player.minSpeedForFacing * player.minSpeedForFacing then
        local speed = math.sqrt(speedSq)

        player.moveX = newVX / speed
        player.moveZ = newVZ / speed
    else
        player.moveX = 0
        player.moveZ = 0
    end

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
    -- GRAVITY FEEL
    --------------------------------------------------

    do
        local gvx, gvy, gvz = player.collider:getLinearVelocity()

        -- Fall faster than you rise, for a snappier arc.
        if gvy < 0 then
            player.collider:setGravityScale(player.fallGravityScale)
        else
            player.collider:setGravityScale(player.riseGravityScale)
        end

        -- Terminal velocity clamp, so a long fall can't build up enough
        -- speed to tunnel through thin geometry in one physics step.
        if gvy < -player.maxFallSpeed then
            player.collider:setLinearVelocity(gvx, -player.maxFallSpeed, gvz)
        end
    end

    --------------------------------------------------
    -- ANIMATION
    --------------------------------------------------

    local isMoving = player.moveX ~= 0 or player.moveZ ~= 0

    if isMoving then
        playAnimation(3, .2) -- walk
    else
        playAnimation(1, .3) -- idle
    end

    updateAnimation(dt)

    --------------------------------------------------
    -- THIRD-PERSON CAMERA
    --------------------------------------------------

    local targetX = player.position.x
    local targetY = player.position.y + 1.2
    local targetZ = player.position.z

    local cosPitch = math.cos(camera.pitch)

    local cameraX = targetX + math.sin(camera.yaw) * cosPitch * camera.distance

    local cameraY = targetY + math.sin(camera.pitch) * camera.distance

    -- Keep the camera from dipping below the floor. The pitch clamp alone
    -- (see lovr.mousemoved) constrains angle, not world-space height, so at
    -- large distances/low pitches the orbit math can still put the camera
    -- underground — clamp the resulting height directly against the floor.
    cameraY = math.max(cameraY, camera.minHeight)

    local cameraZ = targetZ + math.cos(camera.yaw) * cosPitch * camera.distance

    camera.transform:lookAt(cameraX, cameraY, cameraZ, targetX, targetY, targetZ)

    camera.transform:invert()

    spawnTimer = spawnTimer + dt
    if spawnTimer >= spawnRate then
        spawnTimer = spawnTimer - spawnRate
        if isMoving then spawnParticle(player.position.x, 0, player.position.z) end
    end

    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(particles, i)
        else
            p.position = p.position + p.velocity * dt
        end
    end
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

    for _, p in ipairs(particles) do
        local alpha = p.life / p.maxLife
        pass:setColor(p.color[1], p.color[2], p.color[3], alpha)
        pass:sphere(p.position, 0.25)
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
