# hFLClash

hFLClash is a small, non-commercial fork of [FlClash](https://github.com/chen08209/FlClash), a multi-platform Mihomo client built with Flutter.

## Highlights

- Android, Windows, macOS, and Linux support inherited from FlClash.
- Material You interface and local subscription conversion.
- Mihomo YAML, Xray JSON, share-link, and Base64 subscription sources.
- Encrypted Happ, V2RayTun, and INCY subscription links, including optional encrypted response bodies.

Releases and source code are available in the [hFLClash repository](https://github.com/h-m-256/hFlClash).

## Credits

- hFLClash is based on [FlClash](https://github.com/chen08209/FlClash).
- Encrypted subscription support uses [hpwnr](https://github.com/Omegaplexx/hpwnr), the command-line companion to [Happwner](https://github.com/Omegaplexx/Happwner), developed by [slavrom21](https://github.com/slavrom21) and [Omegaplex](https://github.com/Omegaplexx). It is used here for this non-commercial fork with attribution to its authors and source repositories.

## Build

Install Flutter, Go, and the platform toolchain, initialize submodules, then run:

```bash
git submodule update --init --recursive
dart setup.dart android
```

Replace `android` with `windows`, `linux`, or `macos` for another target.

## License

hFLClash follows the upstream [GPL-3.0 license](LICENSE). Third-party components remain subject to their respective terms.
