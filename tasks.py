import shutil
from enum import StrEnum
from invoke.exceptions import PlatformError
from invoke import task
import platform
import os
from shutil import copy

GDPATH = os.getenv("GDPATH")
if not GDPATH:
    GDPATH = "godot"
def gd_cmd(editor=True):
    cmd = f"{GDPATH} {'-e' if editor else ''} --path godot/"
    return cmd

class BuildProfile(StrEnum):
    BOTH = "both"
    DEBUG = "debug"
    RELEASE = "release"

SYSTEM = platform.system()
LIB=None
match SYSTEM:
    case "Windows":
        LIB = "vimdow.dll"
    case "Linux":
        LIB = "libvimdow.so"
    case "Darwin":
        LIB = "libvimdow.dylib"
if LIB is None:
    raise PlatformError("On an unsupported platform: " + SYSTEM)

CARGO_TOML = "rust/Cargo.toml"
def cargo_cmd(method: str, *args) -> str:
    cmd = f"cargo {method} {' '.join(args)} --manifest-path={CARGO_TOML}"
    return cmd

@task(aliases=["c"])
def clean(c):
    print("Cleaning cargo build")
    c.run(cargo_cmd("clean"))
    shutil.rmtree("godot/addons/vimdow/bin")

@task(
    help = {
        "clean" : "Clean old build before compiling",
        "profile" : "Type of profile to build. Should only be \"debug\", \"release\", or \"both\""
    },
    aliases=["b"]
)
def build(c, profile: BuildProfile = None, clean=False):
    if clean: 
        clean(c)

    if not os.path.exists("godot/addons/vimdow/bin"):
        os.mkdir("godot/addons/vimdow/bin")

    if not profile:
        profile = BuildProfile.DEBUG
    profiles: dict = {}
    match profile:
        case BuildProfile.DEBUG:
            profiles[profile.value] = cargo_cmd("build")
        case BuildProfile.RELEASE:
            profiles[profile.value] = cargo_cmd("build", "--release")
        case _:
            profiles["debug"] = cargo_cmd("build")
            profiles["release"] = cargo_cmd("build", "--release")

    for key, value in profiles.items():
        print(f"Building for {key}")
        c.run(value)
        src = f"rust/target/{key}/{LIB}"
        dst = "godot/addons/vimdow/bin/" + key
        if not os.path.exists(dst):
            print(f"Making profile location in godot/addons/vimdow/bin/{key}/")
            os.mkdir(dst)
        dst = os.path.join(dst, LIB)
        copy(src, dst)

@task(
    help={
        "clean" : "Clean old build before compiling",
        "profile" : "The profile of the library to build. Default is \"debug\""
    },
    aliases=["s"]
)
def standalone(c, nobuild=False, profile: BuildProfile = BuildProfile.DEBUG, clean=False):
    if not nobuild:
        build(c, profile, clean)
    c.run(gd_cmd(False))

@task(
    help={
        "clean" : "Clean old build before compiling",
        "profile" : "The profile of the library to build. Default is \"debug\""
    },
    aliases=["e"],
    default=True
)
def editor(c, nobuild=False, profile: BuildProfile = BuildProfile.DEBUG, clean=False):
    if not nobuild:
        build(c, profile, clean)
    c.run(gd_cmd())

