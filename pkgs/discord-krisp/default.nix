{
  discord,
  brotli,
  fetchurl,
  lib,
  python3,
  runCommand,
  runtimeShell,
}:

let
  krispSrc = fetchurl {
    inherit (discord.source.modules.discord_krisp) url hash;
  };

  patcherPython = python3.withPackages (ps: [ ps.lief ]);

  patchedKrisp = runCommand "discord-krisp-patched" {
    nativeBuildInputs = [ brotli ];
  } /* bash */ ''
    mkdir --parents "$out"
    brotli --decompress < ${krispSrc} | tar --extract --file=- --strip-components=1 --directory="$out"
    ${lib.getExe' patcherPython "python3"} ${./patch-linux.py} "$out"
  '';

  deployPython = python3.withPackages (ps: [ ps.watchdog ]);
in
discord.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ python3 ];
  postInstall = (old.postInstall or "") + /* bash */ ''
    rm --recursive --force "$out/opt/Discord/modules/discord_krisp"
    mkdir --parents "$out/opt/Discord/modules/discord_krisp"
    cp --recursive ${patchedKrisp}/. "$out/opt/Discord/modules/discord_krisp/"
    chmod --recursive u+w "$out/opt/Discord/modules/discord_krisp"

    python3 ${./patch-voice.py} \
      "$out/opt/Discord/modules/discord_voice/index.js" \
      "require('path').join(process.env.XDG_CONFIG_HOME || require('path').join(require('os').homedir(), '.config'), 'discord', '${old.version}', 'modules', 'discord_krisp')" \
      "$out/opt/Discord/resources/build_info.json" \
      "$out/opt/Discord/modules"

    install -D --mode=0755 ${./deploy.py} "$out/bin/.discord-deploy-krisp"
    substituteInPlace "$out/bin/.discord-deploy-krisp" \
      --replace-fail '@pythonInterpreter@' '${lib.getExe' deployPython "python3"}' \
      --replace-fail '@krispPath@' "$out/opt/Discord/modules/discord_krisp" \
      --replace-fail '@discordVersion@' '${old.version}' \
      --replace-fail '@configDirName@' 'discord'

    rm --force "$out/bin/Discord" "$out/bin/discord"
    install -D --mode=0755 /dev/stdin "$out/bin/Discord" <<EOF
    #!${runtimeShell}
    "$out/bin/.discord-deploy-krisp"
    exec "$out/opt/Discord/Discord" "\$@"
    EOF
    ln --symbolic "$out/bin/Discord" "$out/bin/discord" || true
  '';
})
