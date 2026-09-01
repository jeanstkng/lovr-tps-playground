lovr.mouse = require 'lovr.lovr-mouse'

local model
local shader

local player = {
    position = vector(0, 0, 0),
    speed = 10,

    moveX = 0,
    moveZ = 0,

    transform = lovr.math.newMat4()
}

local camera = {
    transform = lovr.math.newMat4(),

    yaw = 0,
    pitch = .15,

    distance = 10,
    height = 4,

    sensitivity = .004
}

local function drawDebugAxes(pass)
    local x = player.position.x
    local y = player.position.y + 1.2
    local z = player.position.z

    local length = 1.5

    --------------------------------------------------
    -- ACTUAL MOVEMENT
    --------------------------------------------------

    -- YELLOW = actual dx/dz used to move the player
    pass:setColor(1, 1, 0)

    pass:line(x, y + .15, z, x + player.moveX * length, y + .15,
              z + player.moveZ * length)

    --------------------------------------------------
    -- CAMERA FORWARD
    --------------------------------------------------

    local cameraForwardX = -math.sin(camera.yaw)
    local cameraForwardZ = -math.cos(camera.yaw)

    -- GREEN = camera forward / direction W should move
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

function lovr.load()
    -- Use the external lovr-mouse library for now.
    lovr.mouse.setRelativeMode(true)

    model = lovr.graphics.newModel('character-a.glb')

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

      vec4 baseColor = Color * getPixel(ColorTexture, UV);

      return vec4(baseColor.rgb * light, baseColor.a);
    }
  ]])
end

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

    -- Camera sits at:
    --
    --   x = targetX + sin(yaw) * distance
    --   z = targetZ + cos(yaw) * distance
    --
    -- Therefore the direction FROM camera TO player is:
    --
    --   (-sin(yaw), -cos(yaw))
    --
    -- That's exactly what W should use.

    local forwardX = -math.sin(camera.yaw)
    local forwardZ = -math.cos(camera.yaw)

    -- 90 degrees clockwise from forward
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

        player.position.x = player.position.x + dx * player.speed * dt

        player.position.z = player.position.z + dz * player.speed * dt
    end

    --------------------------------------------------
    -- THIRD PERSON CAMERA
    --------------------------------------------------

    local targetX = player.position.x
    local targetY = player.position.y + 1.2
    local targetZ = player.position.z

    local cosPitch = math.cos(camera.pitch)

    local cameraX = targetX + math.sin(camera.yaw) * cosPitch * camera.distance

    local cameraY = targetY + math.sin(camera.pitch) * camera.distance

    local cameraZ = targetZ + math.cos(camera.yaw) * cosPitch * camera.distance

    camera.transform:lookAt(cameraX, cameraY, cameraZ, targetX, targetY, targetZ)

    -- lookAt creates a view transform.
    -- setViewPose expects a pose.
    camera.transform:invert()
end

function lovr.draw(pass)
    pass:setViewPose(1, camera.transform)

    pass:setShader(shader)
    pass:setColor(1, 1, 1)

    local px = player.position.x
    local py = player.position.y
    local pz = player.position.z

    -- Point the model directly along its movement vector
    if player.moveX ~= 0 or player.moveZ ~= 0 then
        player.transform:target(vector(px, py, pz), vector(px - player.moveX,
                                                           py, pz - player.moveZ),
                                vector(0, 1, 0))
    else
        player.transform:setPosition(px, py, pz)
    end

    pass:draw(model, player.transform)

    pass:setShader()

    drawDebugAxes(pass)

    pass:setColor(.3, .3, .3)

    pass:plane(0, 0, 0, 30, 30, math.pi / 2, 1, 0, 0)

    pass:setColor(1, 1, 1)
end

function lovr.mousemoved(x, y, dx, dy)

    camera.yaw = camera.yaw - dx * camera.sensitivity

    camera.pitch = camera.pitch - dy * camera.sensitivity

    camera.pitch = math.max(-.5, math.min(.8, camera.pitch))
end

function lovr.keypressed(key)

    if key == 'escape' then
        lovr.mouse.setRelativeMode(false)
        lovr.event.quit()
    end
end
