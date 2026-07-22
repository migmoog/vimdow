import subprocess
from enum import StrEnum
import subprocess
from dataclasses import dataclass
from invoke import Context

def cargo_cmd(method: str, *args) -> str:
    cmd = f"cargo {method} {' '.join(args)} --manifest-path=rust/Cargo.toml"
    return cmd

class BuildProfile(StrEnum):
    BOTH = "both"
    DEBUG = "debug"
    RELEASE = "release"

    def get_list(self):
        if self == BuildProfile.BOTH:
            return ["debug", "release"]
        else:
            return [self.value]

@dataclass
class Platform:
    rust_target: str
    libfile: str

    def __post_init__(self):
        pass

    def target_flag(self) -> str:
        return f" --target {self.rust_target} "

    def build(self, c: Context, profile: BuildProfile, use_target_flag=True) -> list[str]:
        tf = self.target_flag() if use_target_flag else ""
        profiles = {}
        match profile:
            case BuildProfile.DEBUG:
                profiles[profile.value] = cargo_cmd("build", tf)
            case BuildProfile.RELEASE:
                profiles[profile.value] = cargo_cmd("build", tf, "--release")
            case BuildProfile.BOTH:
                profiles["debug"] = cargo_cmd("build", tf)
                profiles["release"] = cargo_cmd("build", tf, "--release")

        out = []
        for key, value in profiles.items():
            print(f"Building for {key} target {self.rust_target}")
            c.run(value)
            out.append(f"rust/target/{key}/{self.libfile}")
        return out

TARGETS = {
    "Windows" : Platform( rust_target="x86_64-pc-windows-msvc", libfile="vimdow.dll" ),
    "Darwin" : Platform( rust_target="x86_64-apple-darwin", libfile="libvimdow.dylib" ),
    "Linux" : Platform( rust_target="x86_64-unknown-linux-gnu", libfile="libvimdow.so" ),
}

def available_targets() -> dict[str, str]:
    result = subprocess.run(
        ["rustup", "target", "list", "--installed"],
        capture_output=True,
        check=True,
        text=True,
    )
    print(result.stdout)
    return {k: v for k, v in TARGETS.items() if v.rust_target in result.stdout}


def flag_to_platforms(flag: str) -> list[Platform]:
    out = []
    at = available_targets()
    if "w" in flag:
        if "Windows" in at:
            out.append(at["Windows"])
        else:
            print(f"""Windows target is unavailable. Try 'rustup target add {TARGETS["Windows"].rust_target}'""")
    if "m" in flag:
        if "Darwin" in at:
            out.append(at["Darwin"])
        else:
            print(f"""Mac target is unavailable. Try 'rustup target add {TARGETS["Darwin"].rust_target}'""")

    if "l" in flag:
        if "Linux" in at:
            out.append(at["Linux"])
        else:
            print(f"""Linux target is unavailable. Try 'rustup target add {TARGETS["Linux"].rust_target}'""")

    if len(out) == 0:
        raise RuntimeError("No platform flag supplied")
    return out
