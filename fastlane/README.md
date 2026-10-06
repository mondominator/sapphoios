fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios test

```sh
[bundle exec] fastlane ios test
```

Build and run the unit tests on a simulator

### ios certificates

```sh
[bundle exec] fastlane ios certificates
```

Sync the App Store certificate and profile with match

### ios build

```sh
[bundle exec] fastlane ios build
```

Archive and export a signed App Store IPA

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload to TestFlight (run by CI on a v* tag)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
