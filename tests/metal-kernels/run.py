#!/usr/bin/env python3
"""Build the split Core Image library and test its ABI, app loader, and rendered pixels.

No downloads or installs. An optional original shader file enables paired output checks.
Artifacts remain in --output-dir; without it they are removed when the run ends.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
TOOLCHAIN_ID = "com.apple.dt.toolchain.Metal.32023.921.5"


def run(command, *, env, log=None):
    result = subprocess.run([str(part) for part in command], cwd=ROOT, env=env,
                            capture_output=True, text=True)
    if log:
        log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {command}\n"
                           f"{result.stdout}{result.stderr}")
    if result.stderr:
        print(result.stderr, end="")
    return result.stdout.strip()


def extract_registry(output):
    source = (ROOT / "myUpscaler/Processing/CoreMLEngine+Shaders.swift").read_text()
    start = source.index("    final class ShaderRegistry:")
    end = source.index("\n    // Shared CIContext", start)
    registry = source[start:end]
    output.write_text("import Foundation\nimport CoreImage\n"
                      "enum CoreMLEngine {}\nnonisolated extension CoreMLEngine {\n"
                      + registry + "\n}\n")


def validate(args, output):
    output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = args.developer_dir
    version = run(["xcodebuild", "-version"], env=env)
    if not version.startswith("Xcode 27."):
        raise RuntimeError(f"Xcode 27 is required, found: {version}")
    sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"], env=env)
    metal = Path(run(["xcrun", "--toolchain", TOOLCHAIN_ID, "--find", "metal"], env=env))
    tools = metal.parent
    if not (tools / "metallib").is_file():
        raise RuntimeError("Installed Metal toolchain lacks metallib; no installation attempted")
    print(version)
    print(run([metal, "--version"], env=env))
    sources = sorted((ROOT / "myUpscaler/Native/Process/Shaders").glob("*.ci.metal"))
    if len(sources) != 21:
        raise RuntimeError(f"Expected 21 individual kernel source files, found {len(sources)}")
    registry = output / "Registry.swift"
    extract_registry(registry)
    compile_report = []
    for mode, flag in (("precise", "-fno-fast-math"), ("fast", "-ffast-math")):
        work = output / mode
        work.mkdir(exist_ok=True)

        def compile_one(source):
            air = work / (source.stem + ".air")
            command = [metal, "-target", "air64-apple-macos15.2", "-fcikernel", flag,
                       "-std=macos-metal2.4",
                       f"-fmodules-cache-path={work / 'module-cache'}",
                       "-isysroot", sdk, "-c", source, "-o", air]
            run(command, env=env, log=work / (source.stem + ".log"))
            return air

        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            airs = list(pool.map(compile_one, sources))
        # Match Xcode's MetalLink driver: it combines AIR and invokes the CI linker.
        # The driver accepts -fcikernel; direct metallib uses -cikernel instead.
        # Compile and link targets must agree or the linker may ignore newer AIR.
        library = work / "default.metallib"
        run([metal, "-target", "air64-apple-macos15.2", "-fcikernel", *airs, "-o", library],
            env=env, log=work / "library-link.log")
        baseline = None
        if args.baseline_source:
            baseline_air = compile_one(args.baseline_source.resolve())
            baseline = work / "baseline.metallib"
            run([metal, "-target", "air64-apple-macos15.2", "-fcikernel",
                 baseline_air, "-o", baseline], env=env,
                log=work / "baseline-link.log")
        bundle = work / "ShaderRegression.app/Contents"
        (bundle / "MacOS").mkdir(parents=True, exist_ok=True)
        (bundle / "Resources").mkdir(exist_ok=True)
        (bundle / "Resources/default.metallib").write_bytes(library.read_bytes())
        executable = bundle / "MacOS/ShaderRegression"
        run(["xcrun", "swiftc", "-module-cache-path", output / "swift-cache",
             "-swift-version", "6", "-strict-concurrency=complete", "-default-isolation", "MainActor",
             "-warnings-as-errors",
             "-target", "arm64-apple-macos15.2", "-O", registry,
             ROOT / "tests/metal-kernels/ShaderKernelRegression.swift", "-o", executable],
            env=env, log=work / "swift-compile.log")
        compile_report.append({"mode": mode, "shaderUnits": len(sources),
                               "baselineCompiled": baseline is not None,
                               "library": str(library), "runtimeExecutable": str(executable)})
        (output / "compile-results.json").write_text(json.dumps(compile_report, indent=2) + "\n")
        print(f"{mode}: compiled 21 kernels, linked library, compiled strict Swift 6 app registry probe")
        if not args.compile_only:
            command = [executable] + ([baseline] if baseline else [])
            report = run(command, env=env, log=work / "runtime.log")
            print(report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-source", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--compile-only", action="store_true")
    parser.add_argument("--developer-dir", default="/Applications/Xcode.app/Contents/Developer")
    args = parser.parse_args()
    if args.output_dir:
        validate(args, args.output_dir.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix="myupscaler-metal-") as directory:
            validate(args, Path(directory))


if __name__ == "__main__":
    main()
