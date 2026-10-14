# Contributing to Mixpilot

Thank you for helping. Bug reports and ideas are the most useful contributions: Mixpilot deals with
many apps and audio devices, and your setup is probably one the developer doesn't have.

## Reporting a bug or an idea

Open an [issue](https://github.com/ahmedmaaloul/Mixpilot/issues/new/choose) with the form. Please
include the apps and devices involved and, if you can, the log the form explains how to get.

## Changing code

1. **Open an issue first** and describe what you'd like to change, so we can agree on the approach
   before you spend time on it.
2. Read [CLAUDE.md](CLAUDE.md): it explains the architecture, the Core Audio pitfalls and the
   design rules (native controls only, semantic colors, text styles, both languages, accessibility).
3. Keep changes small and focused. Logic goes in `MixpilotKit` with tests
   (`cd MixpilotKit && swift test`). The audio thread's code stays in C and real-time safe.
4. Every user-facing string needs German too: add it to `Localization/de.py` and run
   `python3 Localization/localize.py`.
5. Open a pull request against `main` and describe how you tested it (apps, devices, macOS version).

New third-party dependencies aren't accepted without discussing them first.

## License of contributions

Mixpilot is under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). By contributing, you agree
that your contribution is licensed under that license and may also be included in commercial
licenses the author grants.
