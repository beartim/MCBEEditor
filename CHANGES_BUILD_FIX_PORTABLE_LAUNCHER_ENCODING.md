# Portable launcher encoding build fix

The managed payload and Desktop projects already built successfully. The remaining failure was isolated to `Windows/PortableLauncher/launcher.cpp` when MSVC read the UTF-8 source using Windows code page 936.

Changes:

- Removed duplicate `#define UNICODE` and `#define _UNICODE`; CMake already supplies both definitions.
- Replaced every non-ASCII Chinese launcher message in source with `\uXXXX` escapes inside wide string literals. The compiled UI text is unchanged, while the source file itself is now pure ASCII and cannot be mis-decoded by a legacy system code page.
- Added MSVC `/utf-8` explicitly in `Windows/PortableLauncher/CMakeLists.txt` as a second layer of protection.
- Verified `launcher.cpp` contains no non-ASCII bytes, no literal newlines inside string/character literals, and has balanced braces/parentheses.

This fix does not change portable cache behavior, single-instance behavior, payload extraction, source-world isolation, or cleanup semantics.
