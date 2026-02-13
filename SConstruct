#!/usr/bin/env python
"""
SConstruct for building the loopy_native GDExtension.

Wraps Simon Tatham's Loopy puzzle C code as a Godot GDExtension
using godot-cpp C++ bindings.

Usage:
    scons platform=windows target=template_debug
    scons platform=windows target=template_release
"""

import os

# Load godot-cpp's build environment
env = SConscript("godot-cpp/SConstruct")

# Add include paths: our wrapper source + Tatham's C headers
env.Append(CPPPATH=["native/src/", "native/tatham/"])

# C++ source files (our GDExtension wrapper)
cpp_sources = Glob("native/src/*.cpp")

# C source file (the bridge that #includes Tatham's .c files)
# We only compile loopy_bridge.c — it #includes all Tatham .c files
# internally, so we must NOT add native/tatham/*.c here.
#
# Tatham's C code produces many warnings (old style, unused params, etc.)
# so we compile the C bridge with reduced warning level.
c_env = env.Clone()
if c_env["platform"] == "windows":
    # MSVC: replace /W4 with /W2 for C code, suppress specific warnings
    ccflags = c_env.get("CCFLAGS", [])
    ccflags = [f for f in ccflags if f not in ("/W4", "/W3", "/WX")]
    ccflags.append("/W2")
    c_env.Replace(CCFLAGS=ccflags)
else:
    # GCC/Clang: suppress warnings for Tatham's legacy C code
    c_env.Append(CFLAGS=["-w"])

c_sources = [c_env.SharedObject(src) for src in Glob("native/src/*.c")]

sources = cpp_sources + c_sources

# Build the shared library
libname = "loopy_native"
suffix = env["suffix"]
suffix_clean = suffix.replace(".dev", "").replace(".universal", "")
lib_filename = "{}{}{}{}".format(
    env.subst("$SHLIBPREFIX"), libname, suffix_clean, env.subst("$SHLIBSUFFIX")
)

library = env.SharedLibrary(
    "bin/{}/{}".format(env["platform"], lib_filename),
    source=sources,
)

Default(library)
