# Windows build script encoding hotfix

The original Windows PowerShell scripts were UTF-8 without BOM and contained
Chinese text. Windows PowerShell 5.1 can decode such files using the active ANSI
code page, which corrupts UTF-8 source text and may produce ParserError before
any build command runs.

This hotfix makes all entry-point PowerShell build scripts ASCII-only:

- build.ps1
- build-native.ps1
- bootstrap-native.ps1

No MCBEEditor data-format or application logic was changed by this hotfix.
Run `build.cmd` again from the `Windows` directory.
