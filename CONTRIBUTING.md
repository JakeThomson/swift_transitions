# Contributing

Thanks for your interest in `swift_transitions`. Bug reports, feature requests
and pull requests are all welcome.

## Before you start

* For anything beyond a small fix, open an issue first so the approach can be
  agreed before you spend time on it.
* Check the existing issues and pull requests to avoid duplicating work.

## Setting up

You need a recent stable Flutter SDK. The minimum supported version is listed
in `pubspec.yaml`.

```sh
git clone https://github.com/JakeThomson/swift_transitions.git
cd swift_transitions
flutter pub get
```

## Running the checks

CI runs the following on every pull request. Run them locally before pushing.

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter pub publish --dry-run
```

The example app is checked separately:

```sh
cd example
flutter pub get
flutter analyze --fatal-infos
```

## Making changes

* Every public member needs a doc comment. The analyzer enforces this.
* Add or update tests for behaviour you change. Widget tests for animation
  behaviour should drive the transition with `WidgetTester.pump` and assert on
  the rendered geometry, not on implementation details.
* Add a line to the `## Unreleased` section of `CHANGELOG.md` for anything a
  user of the package would notice. Create the section if it does not exist.
* Keep pull requests focused. Unrelated refactors belong in their own pull
  request.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) prefixes
(`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `refactor:`). Keep the subject
line under about 70 characters and explain the *why* in the body when it is
not obvious from the diff.

## Releasing

Maintainers only.

1. Update the version in `pubspec.yaml` and move the `## Unreleased` entries in
   `CHANGELOG.md` under the new version heading.
2. Check the package as pub.dev will see it: `flutter pub publish --dry-run`,
   and `dart doc` for broken references.
3. Commit, then tag the commit as `vX.Y.Z` and push the tag.
4. The `publish` workflow publishes the tagged commit to pub.dev over an OIDC
   token from GitHub Actions. It needs automated publishing to be enabled for
   this repository under the package's admin settings on pub.dev, with the tag
   pattern `v{{version}}`.
