import commentedconfigparser
import shutil
from enum import StrEnum
from invoke.exceptions import PlatformError
from invoke import task, call
import platform
import os
from shutil import copy

GDPATH = os.getenv("GDPATH")
if not GDPATH:
    GDPATH = "godot"

def gd_cmd(*args) -> str:
    return f"\"{GDPATH}\" {" ".join(args)} --path godot/"

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

def init_dir(path):
    if not os.path.exists(path):
        os.mkdir(path)

@task(aliases=["c"])
def clean(c):
    print("Cleaning cargo build")
    c.run(cargo_cmd("clean"))
    shutil.rmtree("godot/addons/vimdow/bin")
    shutil.rmtree("build/")

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

    init_dir("godot/addons/vimdow/bin")
    init_dir("build/")

    profile = profile or BuildProfile.DEBUG
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
    c.run(gd_cmd())

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
    c.run(gd_cmd("-e"))


@task(
    pre = [call(build, profile=BuildProfile.BOTH)],
    aliases = ["ep"]
)
def export_plugin(c):
    print("Setting defaults for plugin")
    local_config = commentedconfigparser.CommentedConfigParser()
    LOCAL_CFG_PATH = "godot/addons/vimdow/local.cfg"
    local_config.read(LOCAL_CFG_PATH)
    local_config["neovim"]["template"] = "true"
    with open(LOCAL_CFG_PATH, "w") as local_config_file:
        local_config.write(local_config_file)

    print("Zipping plugin to build/")
    shutil.make_archive("build/vimdow-plugin", "zip", root_dir="godot/addons")

@task(
    aliases = ["es"],
    help = {
     "profile" : "The profile of the library to build. Default is \"debug\""
    }
)
def export_standalone(c, profile=BuildProfile.DEBUG):
    build(c, profile)
    
    preset_name = "vimdow-standalone-"
    export_file = "vimdow."
    extension=None
    if profile != BuildProfile.BOTH:
        export_file += profile.value
    match SYSTEM:
        case "Windows":
            preset_name += "win"
            extension = ".exe"
        case "Linux":
            preset_name += "linux"
            extension = ".x86_64"
        case "Darwin":
            preset_name += "mac"
            extension = ".app"
    if profile != BuildProfile.BOTH:
        path = "build/" + profile.value
        init_dir(path)
        c.run(gd_cmd(
            "--export-" + profile.value,
            preset_name,
            f"../{path}/" + export_file + extension
        ))
    else:
        init_dir("build/debug")
        c.run(gd_cmd(
            "--export-debug",
            preset_name,
            "../build/debug/vimdow.debug" + extension
        ))
        init_dir("build/release")
        c.run(gd_cmd(
            "--export-release",
            preset_name,
            "../build/release/vimdow.release" + extension
        ))


    
