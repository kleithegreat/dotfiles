{ lib, runCommand }:

let
  inherit (lib.lists) drop foldl' take;
  inherit (lib.strings) concatMapStrings concatMapStringsSep fixedWidthString replaceStrings splitString trim;
  inherit (lib.trivial) fromHexString mod toHexString;

  refreshRates = [ 65 70 75 ];

  # The LG LP156WU1's own EDID, checksum byte dropped.
  panel = ''
    00 ff ff ff ff ff ff 00 30 e4 b3 06 00 00 00 00
    00 1f 01 04 a5 22 15 78 06 a2 05 a6 54 49 a2 25
    0e 50 54 00 00 00 01 01 01 01 01 01 01 01 01 01
    01 01 01 01 01 01 28 3c 80 a0 70 b0 23 40 30 20
    36 00 50 d2 10 00 00 1a 20 30 80 a0 70 b0 23 40
    30 20 36 00 50 d2 10 00 00 1a 00 00 00 fe 00 34
    44 57 56 4a 81 31 35 36 57 55 31 0a 00 00 00 00
    00 02 41 31 b2 00 11 00 00 0a 01 0a 20 20 00
  ''
    |> trim
    |> replaceStrings [ "\n" ] [ " " ]
    |> splitString " "
    |> map fromHexString;

  # Bytes 54–55 hold the preferred timing's pixel clock in 10 kHz units; its frame is 2080 × 1235.
  edid = hz:
    let
      clock = (2080 * 1235 * hz + 5000) / 10000;
      bytes = take 54 panel ++ [ (mod clock 256) (clock / 256) ] ++ drop 56 panel;
      checksum = mod (256 - mod (foldl' builtins.add 0 bytes) 256) 256;
    in
    bytes ++ [ checksum ] |> concatMapStrings (byte: "\\x" + fixedWidthString 2 "0" (toHexString byte));

  name = hz: "panel-${toString hz}hz";
in
runCommand "laptop-panel-edid" { passthru.names = map name refreshRates; } /* bash */ ''
  mkdir --parents "$out/lib/firmware/edid"
  ${concatMapStringsSep "\n" (hz: "printf '%b' '${edid hz}' > \"$out/lib/firmware/edid/${name hz}.bin\"") refreshRates}
''
