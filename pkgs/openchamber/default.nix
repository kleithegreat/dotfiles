{
  symlinkJoin,
  openchamberCli,
  openchamberDesktop,
}:

symlinkJoin {
  name = "openchamber-${openchamberCli.version}";
  paths = [
    openchamberCli
    openchamberDesktop
  ];

  meta = openchamberCli.meta // {
    description = "OpenChamber CLI plus desktop launcher";
  };
}
