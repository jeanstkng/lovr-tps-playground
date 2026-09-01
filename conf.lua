function lovr.conf(t)
    -- This is a desktop game, not VR: disable the headset module entirely.
    -- Without this, LÖVR tries to run through an OpenXR runtime (or its
    -- desktop VR simulator) and renders stereo, neither of which you want.
    t.modules.headset = false

    t.window.title = 'Playground'
    t.window.width = 1280
    t.window.height = 720
    t.window.vsync = 1
    t.window.resizable = true
end