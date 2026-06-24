from decimal import Context
from build_targets import flag_to_platforms
from build_targets import cargo_cmd
import commentedconfigparser
import shutil
import dotenv
from invoke.exceptions import PlatformError
from invoke import task, call
import platform
import os
from shutil import copy, rmtree
from build_targets import BuildProfile, TARGETS

dotenv.load_dotenv()

def gd_cmd(*args) -> str:
    if not os.environ["GDPATH"]:
        raise RuntimeError("No GDPATH set. Cannot do Godot commands")
    return f"\"{os.environ[ "GDPATH" ]}\" {" ".join(args)} --path godot/"

SYSTEM = platform.system()
current_platform = TARGETS[SYSTEM]
if not current_platform:
    raise PlatformError("On an unsupported platform: " + SYSTEM)


def init_dir(path):
    if not os.path.exists(path):
        os.mkdir(path)

@task(aliases=["c"])
def clean(c):
    print("Cleaning cargo build")
    c.run(cargo_cmd("clean"))
    rmtree("godot/addons/vimdow/bin")
    rmtree("build/")
    os.remove("godot/project.godot")

@task(
    help = {
        "clean" : "Clean old build before compiling",
        "profile" : "Type of profile to build. Should only be \"debug\", \"release\", or \"both\"",
        "platform" : """Type of OS target to compile the rust library for. 
All are in compound flag form.
t- ex: 'l' for linux, 'w' for windows, 'm' for mac
t- ex: 'lw' for linux and windows, 'lwm' for all 
"""
    },
    aliases=["b"]
)
def build(c: Context, profile: BuildProfile = BuildProfile.DEBUG, platform: str = "", clean=False):
    if clean: 
        clean(c)

    init_dir("godot/addons/vimdow/bin")
    init_dir("build/")
    if not os.path.exists("godot/project.godot"):
        print("Making project.godot")
        with open("godot/project.godot", "w") as f:
            f.writelines([
              'config_version=5',
              '[application]',
              'config/name="Vimdow"',
              'config/features=PackedStringArray("4.6.2", "Forward Plus")',
              'config/icon="res://icon.svg"',
              'run/main_scene="res://addons/vimdow/vimdow_editor.tscn"',
              '[display]',
              'window/stretch/mode="canvas_items"',
              'window/stretch/aspect="expand"',
              '[editor_plugins]',
              'enabled=PackedStringArray("res://addons/vimdow/plugin.cfg")',
              '[physics]',
              '3d/physics_engine="Jolt Physics"',
              '[rendering]',
              'rendering_device/driver.windows="d3d12"',
              'textures/vram_compression/import_etc2_astc=true',
            ])
    libfiles = None
    if platform:
        platforms = flag_to_platforms(platform)
        for p in platforms:
            libfiles = p.build(c, profile)
    else: 
        libfiles = current_platform.build(c, profile)

    DST = "godot/addons/vimdow/bin"
    for src in libfiles:
        for dst_dir in profile.get_list():
            destination = os.path.join(DST, dst_dir)
            destination = os.path.join(destination, os.path.basename(src))
            print(f"Copying {src} to {destination}")
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            copy(src, destination)


@task(
    help={
        "clean" : "Clean old build before compiling",
        "profile" : "The profile of the library to build. Default is \"debug\"",
        "platform" : "Same as in 'build' task"
    },
    aliases=["s"]
)
def standalone(c, nobuild=False, profile: BuildProfile = BuildProfile.DEBUG, platform: str = "", clean=False):
    if not nobuild:
        build(c, profile, platform, clean)
    c.run(gd_cmd())

@task(
    help={
        "clean" : "Clean old build before compiling",
        "profile" : "The profile of the library to build. Default is \"debug\"",
        "platform" : "Same as in 'build' task"
    },
    aliases=["e"],
    default=True
)
def editor(c, nobuild=False, profile: BuildProfile = BuildProfile.DEBUG, platform: str = "", clean=False):
    if not nobuild:
        build(c, profile, platform, clean)
    c.run(gd_cmd("-e"))


@task(
    pre = [call(build, profile=BuildProfile.BOTH, platform="lwm")],
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
     "profile" : "The profile of the library to build. Default is \"debug\"",
     "platform" : "Which platform to build for",
    }
)
def export_standalone(c, profile=BuildProfile.DEBUG, platform: str = ""):
    build(c, profile, platform)
    
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


    
