fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac upload_testflight

```sh
[bundle exec] fastlane mac upload_testflight
```

Build R2Drop and upload to TestFlight

### mac testflight

```sh
[bundle exec] fastlane mac testflight
```

Alias for upload_testflight

### mac release_appstore

```sh
[bundle exec] fastlane mac release_appstore
```

Build R2Drop and submit to Mac App Store

### mac appstore

```sh
[bundle exec] fastlane mac appstore
```

Alias for release_appstore

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
