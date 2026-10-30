{
  python3,
  runCommandLocal,
}:

runCommandLocal "ctx" { } /* bash */ ''
  install -D --mode=0755 ${./ctx.py} $out/bin/ctx
  substituteInPlace $out/bin/ctx --replace-fail '#!/usr/bin/env python3' '#!${python3.interpreter}'
''
