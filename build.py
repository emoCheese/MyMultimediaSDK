#!/usr/bin/env python3
"""MultimediaSDK build orchestrator."""

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
OUTPUT_DIR = PROJECT_ROOT / "output"


def run(cmd, **kwargs):
    print(f"\n==> Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=str(PROJECT_ROOT), **kwargs)
    if result.returncode != 0:
        print(f"ERROR: command failed with code {result.returncode}")
        sys.exit(result.returncode)


def detect_target(args):
    if args.target:
        return args.target
    system = platform.system().lower()
    machine = platform.machine().lower()
    if system == "linux":
        if machine in ("aarch64", "arm64"):
            return "linux-arm64"
        return "linux-x64"
    elif system == "windows":
        return "win-x64"
    else:
        print(f"ERROR: unsupported platform: {system}/{machine}")
        sys.exit(1)


def validate_target(target):
    valid = {"linux-x64", "linux-arm64", "win-x64"}
    if target not in valid:
        print(f"ERROR: invalid target '{target}'. Must be one of: {valid}")
        sys.exit(1)


def build(args):
    target = detect_target(args)
    validate_target(target)

    build_dir = OUTPUT_DIR / "build" / target
    sdk_dir = OUTPUT_DIR / "sdk" / target
    ffmpeg_install = build_dir / "ffmpeg-install"
    gst_install = build_dir / "gst-install"
    dist_dir = OUTPUT_DIR / "dist"

    if args.clean:
        for d in [build_dir, sdk_dir, dist_dir]:
            if d.exists():
                shutil.rmtree(d)
                print(f"Cleaned: {d}")

    build_dir.mkdir(parents=True, exist_ok=True)
    sdk_dir.mkdir(parents=True, exist_ok=True)

    print("\n" + "=" * 40)
    print("STEP 1/4: Building FFmpeg")
    print("=" * 40)
    run(["bash", str(SCRIPTS_DIR / "build-ffmpeg.sh"),
         str(ffmpeg_install)])

    print("\n" + "=" * 40)
    print("STEP 2/4: Building GStreamer")
    print("=" * 40)
    run(["bash", str(SCRIPTS_DIR / "build-gstreamer.sh"),
         str(gst_install),
         str(ffmpeg_install / "lib" / "pkgconfig"),
         str(ffmpeg_install)])

    print("\n" + "=" * 40)
    print("STEP 3/4: Merging SDK artifacts")
    print("=" * 40)

    run(["cp", "-r", str(gst_install / "usr" / "local" / "include"), str(sdk_dir / "include")],
        check=False)

    # Copy system GLib/GObject headers for self-contained SDK
    for name in ["glib-2.0", "gobject-2.0"]:
        run(["bash", "-c",
             f"cp -r /usr/include/{name} {sdk_dir}/include/ 2>/dev/null || true"],
            check=False)

    (sdk_dir / "lib").mkdir(exist_ok=True)

    run(["bash", "-c",
         f"cp -r /usr/lib/x86_64-linux-gnu/glib-2.0 {sdk_dir}/lib/ 2>/dev/null || true"],
        check=False)
    run(["bash", "-c",
         f"find {gst_install} {ffmpeg_install} -name '*.a' -exec cp {{}} {sdk_dir}/lib/ \\; 2>/dev/null || true"],
        check=False)
    # Copy core .so + SONAME symlinks (.so.0, .so.0.*), preserve symlinks with -d
    run(["bash", "-c",
         f"find {gst_install} -name '*.so' -not -path '*/gstreamer-1.0/*' -exec cp -d {{}} {sdk_dir}/lib/ \\; 2>/dev/null || true"],
        check=False)
    run(["bash", "-c",
         f"find {gst_install} -name '*.so.*' -not -path '*/gstreamer-1.0/*' -exec cp -d {{}} {sdk_dir}/lib/ \\; 2>/dev/null || true"],
        check=False)

    (sdk_dir / "plugins").mkdir(exist_ok=True)
    # Copy plugin .so + SONAME symlinks, preserve symlinks
    run(["bash", "-c",
         f"find {gst_install} -path '*/gstreamer-1.0/*.so' -not -name '*.so.*' -exec cp -d {{}} {sdk_dir}/plugins/ \\; 2>/dev/null || true"],
        check=False)
    run(["bash", "-c",
         f"find {gst_install} -path '*/gstreamer-1.0/*.so.*' -exec cp -d {{}} {sdk_dir}/plugins/ \\; 2>/dev/null || true"],
        check=False)
    # Set RPATH on plugins: $ORIGIN/../lib so they find our SDK's libraries
    run(["bash", "-c",
         f"for f in {sdk_dir}/plugins/*.so; do "
         f"  patchelf --set-rpath '$ORIGIN/../lib' \"$f\" 2>/dev/null || true; "
         f"done"],
        check=False)

    # Set RUNPATH on core libs: $ORIGIN so they can find each other
    run(["bash", "-c",
         f"for f in {sdk_dir}/lib/*.so; do "
         f"  patchelf --set-rpath '$ORIGIN' \"$f\" 2>/dev/null || true; "
         f"done"],
        check=False)

    # Copy GStreamer tools (gst-plugin-scanner, gst-inspect, etc.)
    run(["bash", "-c",
         f"cp -r {gst_install}/usr/local/bin {sdk_dir}/bin 2>/dev/null || true"],
        check=False)
    run(["bash", "-c",
         f"cp -r {gst_install}/usr/local/libexec {sdk_dir}/libexec 2>/dev/null || true"],
        check=False)
    # Set RPATH on scanner/tools:
    #   libexec/gstreamer-1.0/ → $ORIGIN/../../lib  (../../lib = lib/)
    #   bin/                  → $ORIGIN/../lib       (../lib = lib/)
    for tool in ["gst-plugin-scanner", "gst-completion-helper"]:
        run(["bash", "-c",
             f"patchelf --set-rpath '$ORIGIN/../../lib' {sdk_dir}/libexec/gstreamer-1.0/{tool} 2>/dev/null || true"],
            check=False)
    for tool in ["gst-inspect-1.0", "gst-launch-1.0", "gst-stats-1.0", "gst-typefind-1.0", "gst-transcoder-1.0"]:
        run(["bash", "-c",
             f"patchelf --set-rpath '$ORIGIN/../lib' {sdk_dir}/bin/{tool} 2>/dev/null || true"],
            check=False)

    print("  Generating CMake config...")
    cmake_template = PROJECT_ROOT / "cmake" / "MultimediaSDKConfig.cmake.in"
    cmake_output = sdk_dir / "cmake" / "MultimediaSDKConfig.cmake"
    (sdk_dir / "cmake").mkdir(exist_ok=True)

    if cmake_template.exists():
        content = cmake_template.read_text()
        content = content.replace("@VERSION@", (PROJECT_ROOT / "version.txt").read_text().strip())
        cmake_output.write_text(content)
    else:
        print("WARNING: cmake template not found, skipping CMake config generation")

    if args.package:
        print("\n" + "=" * 40)
        print("STEP 4/4: Packaging")
        print("=" * 40)
        pkg_script = SCRIPTS_DIR / "package.sh"
        if pkg_script.exists():
            run(["bash", str(pkg_script), str(target)])
        else:
            print("WARNING: package.sh not found, skipping packaging")

    print("\n" + "=" * 40)
    print(f"BUILD COMPLETE")
    print(f"SDK location: {sdk_dir}")
    print(f"  include/  -> headers")
    print(f"  lib/      -> static libraries")
    print(f"  plugins/  -> dynamic plugins")
    print(f"  cmake/     -> CMake config")
    print("=" * 40)
    return 0


def main():
    parser = argparse.ArgumentParser(description="MultimediaSDK build orchestrator")
    parser.add_argument("--target", choices=["linux-x64", "linux-arm64", "win-x64"],
                        help="Build target (auto-detect if omitted)")
    parser.add_argument("--clean", action="store_true", help="Clean build directories before build")
    parser.add_argument("--package", action="store_true", help="Package SDK after build")
    parser.add_argument("--verbose", action="store_true", help="Verbose output")

    args = parser.parse_args()
    build(args)


if __name__ == "__main__":
    main()
