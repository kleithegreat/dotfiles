-- Scrub one-shot launch/workspace tokens from anything spawned at startup.
local cleanSessionEnv = "env -u HL_INITIAL_WORKSPACE_TOKEN -u XDG_ACTIVATION_TOKEN -u DESKTOP_STARTUP_ID "

return {
    exec = function(cmd)
        hl.exec_cmd(cleanSessionEnv .. cmd)
    end,
}
