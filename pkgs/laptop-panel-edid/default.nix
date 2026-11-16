{ lib, runCommand }:

let
  inherit (lib.lists) concatMap drop foldl' length replicate take;
  inherit (lib.strings) concatMapStrings fixedWidthString replaceStrings splitString trim;
  inherit (lib.trivial) fromHexString mod toHexString;

  # 68 Hz is the panel's limit; past 70 Hz i915 would also drop every mode to 6 bpc.
  overclocks = [ 68 ];

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

  # i915 offers only rates whose timing matches the preferred one but for the pixel clock.
  factoryTiming = take 18 (drop 54 panel);
  timingAt = hz:
    let clock = (2080 * 1235 * hz + 5000) / 10000;
    in [ (mod clock 256) (clock / 256) ] ++ drop 2 factoryTiming;

  checksummed = bytes: bytes ++ [ (mod (256 - mod (foldl' builtins.add 0 bytes) 256) 256) ];

  base = take 126 panel ++ [ 1 ] |> checksummed;
  # CTA-861 revision 3, underscanned, no data blocks: timings start at byte 4.
  extension = [ 2 3 4 128 ] ++ concatMap timingAt overclocks
    |> (bytes: bytes ++ replicate (127 - length bytes) 0)
    |> checksummed;
in
runCommand "laptop-panel-edid" { } /* bash */ ''
  mkdir --parents "$out/lib/firmware/edid"
  printf '%b' '${base ++ extension |> concatMapStrings (byte: "\\x" + fixedWidthString 2 "0" (toHexString byte))}' \
    > "$out/lib/firmware/edid/panel.bin"
''
