-- Shared session helpers for autostart, including host autostart fragments.

-- Scrub one-shot launch/workspace tokens from anything spawned at startup.
local cleanSessionEnv = "env -u HL_INITIAL_WORKSPACE_TOKEN -u XDG_ACTIVATION_TOKEN -u DESKTOP_STARTUP_ID "

return {
    clean_env_prefix = cleanSessionEnv,

    -- exec a command with the session tokens scrubbed
    exec = function(cmd)
        hl.exec_cmd(cleanSessionEnv .. cmd)
    end,
}
