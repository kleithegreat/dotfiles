{
  lib,
  symlinkJoin,
  openchamberCli,
  openchamberDesktop,
}:

symlinkJoin {
  name = "openchamber";
  paths = [
    openchamberCli
    openchamberDesktop
  ];

  meta = openchamberCli.meta // {
    description = "OpenChamber CLI plus desktop launcher";
  };
}
