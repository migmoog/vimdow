# Changelog

## [Unreleased](https://github.com/migmoog/vimdow/tree/HEAD)

### Fixes
- Windows creation flags [eb67326](https://github.com/migmoog/vimdow/commit/eb6732615388016554ae19b0753e07ee57c8991d)
- Shifted characters are preserved as printable character inputs [e752390](https://github.com/migmoog/vimdow/commit/e752390fce64052cca3ada4046d75326938e9b71)

### Added

- Added pyinvoke build system 
- :q disables the plugin [\#17](https://github.com/migmoog/vimdow/issues/17)

### Fixed

- Better support for non-US keyboard layouts \(German QWERTZ\) [\#16](https://github.com/migmoog/vimdow/issues/16)

## [vimdow-v0.3.4](https://github.com/migmoog/vimdow/tree/vimdow-v0.3.4) - 2026-04-26

### Fixes
- unicode zeroes from InputEventKeys ([1a22cbd](https://github.com/migmoog/vimdow/commit/1a22cbd20c61551d3dbd7b745925b67781d78eb1))

## [vimdow-v0.3.3](https://github.com/migmoog/vimdow/tree/vimdow-v0.3.3) - 2026-04-26

### Fixes

- specific breakpoint deletion in editor ([1d7e4db](https://github.com/migmoog/vimdow/commit/1d7e4dbaf6c6879347e013a988ea6734d55190da))

## [vimdow-v0.3.2](https://github.com/migmoog/vimdow/tree/vimdow-v0.3.2) - 2026-04-26


### Added

- Add shortcuts to enter/exit Vimdow [\#13](https://github.com/migmoog/vimdow/issues/13)

### Changed:

- Keyboard overhaul [\#18](https://github.com/migmoog/vimdow/pull/18) ([migmoog](https://github.com/migmoog))

## [vimdow-v0.3.1](https://github.com/migmoog/vimdow/tree/vimdow-v0.3.1) - 2026-04-22

### Fixed

- Standalone version can use ConfigFiles ([1bf6207](https://github.com/migmoog/vimdow/commit/1bf62072664acfc3ee48026d202e9eec61576539))

## [vimdow-v0.3.0](https://github.com/migmoog/vimdow/tree/vimdow-v0.3.0) - 2026-04-20


### Added

- Basic Debugger [\#15](https://github.com/migmoog/vimdow/pull/15) ([migmoog](https://github.com/migmoog))
- Add shortcut to focus Vimdow workspace [\#8](https://github.com/migmoog/vimdow/pull/8) ([eljamm](https://github.com/eljamm))

### Fixed


- fix: close threads when neovim process is dropped [\#10](https://github.com/migmoog/vimdow/pull/10) ([eljamm](https://github.com/eljamm))
- Fix missing initial value for nvim path [\#7](https://github.com/migmoog/vimdow/pull/7) ([eljamm](https://github.com/eljamm))

### Changed

- docs: add neovim requirements note to README [\#12](https://github.com/migmoog/vimdow/pull/12) ([eljamm](https://github.com/eljamm))
- Update shortcuts section in README.md [\#9](https://github.com/migmoog/vimdow/pull/9) ([eljamm](https://github.com/eljamm))

## [vimdow-v0.2.1](https://github.com/migmoog/vimdow/tree/vimdow-v0.2.1) - 2026-04-07


### Fixed

- Actions modifications and CI/CD safeguards [\#5](https://github.com/migmoog/vimdow/pull/5) ([migmoog](https://github.com/migmoog))

## [vimdow-v0.2.0](https://github.com/migmoog/vimdow/tree/vimdow-v0.2.0) - 2026-04-04

### Added

- Finished basic hl_attrs ([#1](https://github.com/migmoog/vimdow/issues/1))

### Changed

- Migrated to godot-rust v0.5.0 ([efefa37](https://github.com/migmoog/vimdow/commit/efefa37c92eda05fcc107bf813300ab4f1ad721a))

## [vimdow-v0.1.2](https://github.com/migmoog/vimdow/tree/vimdow-v0.1.2) - 2026-03-25

### Added

- experimental removeable window ([9eea55b](https://github.com/migmoog/vimdow/commit/9eea55be0aa0ff893fd51617e95dcdfe8c460d8e))

### Changed

- VimdowEditor uses `Control._gui_input` instead of `Node._input` ([73071cb](https://github.com/migmoog/vimdow/commit/73071cb5bd92cc023839c9e833e635e12cd8abb9))
- VimdowEditor doesn't consume events without focus in editor ([e49617a](https://github.com/migmoog/vimdow/commit/e49617ac2064b11a95a98ca0a21480f7070d87fd))

## [vimdow-v0.1.1](https://github.com/migmoog/vimdow/tree/vimdow-v0.1.1) - 2026-03-23

### Changed

- README update

### Fixed

- stop path override on restarting plugin ([b3844a3](https://github.com/migmoog/vimdow/commit/b3844a3ddff81b7fe29cecccc7dad4084d423f2b))

## [vimdow-v0.1.0](https://github.com/migmoog/vimdow/tree/vimdow-v0.1.0) - 2026-03-22


_Initial release._

