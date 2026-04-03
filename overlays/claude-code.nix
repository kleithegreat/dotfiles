final: prev: {
  claude-code = prev.claude-code.overrideAttrs (old: rec {
    version = "2.1.91";
    src = final.fetchzip {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
      hash = "sha256-u7jdM6hTYN05ZLPz630Yj7gI0PeCSArg4O6ItQRAMy4=";
    };
    postPatch = ''
      cp ${./claude-code/package-lock.json} package-lock.json
    '';
    npmDeps = final.fetchNpmDeps {
      name = "claude-code-${version}-npm-deps";
      inherit src postPatch;
      hash = "sha256-0ppKP+XMgTzVVZtL7GDsOjgvSPUDrUa7SoG048RLaNg=";
    };
  });
}
