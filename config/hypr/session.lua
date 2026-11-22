-- Scrub one-shot launch/workspace tokens from anything spawned at startup.
local cleanSessionEnv = "env --unset=HL_INITIAL_WORKSPACE_TOKEN --unset=XDG_ACTIVATION_TOKEN --unset=DESKTOP_STARTUP_ID "

return {
    exec = function(cmd)
        hl.exec_cmd(cleanSessionEnv .. cmd)
    end,
}
