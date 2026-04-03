final: prev: {
  claude-code = prev.claude-code.overrideAttrs (old: {
    version = "2.1.91";
    src = final.fetchzip {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-2.1.91.tgz";
      hash = "sha256-u7jdM6hTYN05ZLPz630Yj7gI0PeCSArg4O6ItQRAMy4=";
    };
  });
}
