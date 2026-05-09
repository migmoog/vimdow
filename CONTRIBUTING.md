# Contributing

Vimdow is MIT-licensed and open to all contributions. If you want to help improve it you have a couple of options

## Feature Requests / Bug Reports

Vimdow is still in its early stages, meaning contributors are more open to the ideas of new features. Bug reports are also a huge help. Both of these can be reported in an Issue.

When making an issue, please acknowledge that ones with more detail or nuance are prioritized. Something to help get your feature idea considered, or helping track down the source of a bug would be greatly improved with:
- code examples
- recorded videos of bugs
- mockups of what you want your feature to look like

This not only helps contributors, but it also helps bring more traction to your issues.

## Building

Vimdow is part rust GDExtension library, so it adds a bit more complication to testing the plugin. Vimdow uses [pyinvoke](https://pyinvoke.org). Once you've installed pyinvoke, you have an available list of targets in `tasks.py`.

- b\[uild\]: will build the rust libraries and copy them to the godot plugin
 - `--profile=<PROFILE>`: the type of profile to build for. Can be "debug", "release", or "both".
- c\[lean\]: will delete all recent builds in the rust and godot plugin

These targets require an environment variable called `GDPATH` to know where godot's binary is.
- s\[tandalone\]: will run Vimdow as a godot project
 - `--profile=<PROFILE>`: same as in "build"
 - `--clean`: will run "clean" before rebuilding the library
- e\[ditor\]: will run an editor session to edit the Vimdow plugin project. Is also the **default task**.
 - `--profile=<PROFILE>`: same as in "build"
 - `--clean`: same as in "standalone"

For additional information you can use `inv <target> --help` to get more information.
