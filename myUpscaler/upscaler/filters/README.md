# F3KDB Filter Support

The project currently emulates `f3kdb` using FFmpeg's built-in `deband` filter because the bundled `libavfilter` does not include the `f3kdb` filter (flash3kyuu_deband).

## Emulation Details
The application maps `f3kdb` parameters to `deband` parameters as follows:
- `y` (threshold) is scaled down (approx / 2000.0) to match `deband` sensitivity.
- `cb`/`cr` are similarly scaled.
- `range` is mapped to `deband` range (radius).
- Grain is handled by the separate `noise` filter integration.

## Enabling Real F3KDB
To use the actual `f3kdb` filter:
1. Recompile FFmpeg/libavfilter with `f3kdb` support enabled.
2. Replace the libraries in `myUpscaler/lib/`.
3. Modify `up60p_restore_beast_main.c` to remove the fallback logic and use the `f3kdb` filter string directly.

Source code for `f3kdb` can be found in the FFmpeg source tree or as a separate plugin.

