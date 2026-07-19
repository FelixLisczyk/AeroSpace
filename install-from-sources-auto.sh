#!/usr/bin/env bash
# Wraps install-from-sources.sh to work around two environment issues seen on
# macOS 27 / Xcode 27 betas:
#
# 1. Building with the Xcode 27 beta toolchain (Swift 6.4) currently fails on
#    swift-collections with "conflicting options '-warnings-as-errors' and
#    '-suppress-warnings'". Building with a stable (non-beta) Xcode works.
# 2. `brew install-path` (part of the final install step) refuses to build its
#    own formula from source unless the active Xcode is >= Homebrew's required
#    minimum for the running macOS version, which on macOS 27 betas is newer
#    than the stable Xcode above.
#
# This script builds with the newest installed non-beta Xcode, then only
# switches to the newest installed Xcode overall (which may be a beta) for the
# final Homebrew step, and only if that step actually fails under the stable
# one. The originally active Xcode is restored on exit either way.
#
# Delete this script once Homebrew/Xcode support macOS 27 without the
# workarounds above.
set -euo pipefail
cd "$(dirname "$0")"

list-xcodes() {
    for app in /Applications/Xcode*.app; do
        test -d "$app" || continue
        plist="$app/Contents/version.plist"
        test -f "$plist" || continue
        version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null) || continue
        build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist" 2>/dev/null) || continue
        echo "$version|$build|$app"
    done
}

is-newer() { # is-newer a b -> true if a > b (version compare)
    test "$1" != "$2" && test "$(printf '%s\n%s' "$1" "$2" | sort -V | tail -1)" == "$1"
}

is-newer-xcode() { # is-newer-xcode version build other-version other-build -> true if newer
    is-newer "$1" "$3" || { test "$1" == "$3" && is-newer "$2" "$4"; }
}

stable_version="" stable_build="" stable_xcode=""
latest_version="" latest_build="" latest_xcode=""
while IFS='|' read -r version build app; do
    test -z "$version" && continue
    if test -z "$latest_version" || is-newer-xcode "$version" "$build" "$latest_version" "$latest_build"; then
        latest_version=$version
        latest_build=$build
        latest_xcode=$app
    fi
    if [[ "$app" != *[Bb]eta* ]]; then
        if test -z "$stable_version" || is-newer-xcode "$version" "$build" "$stable_version" "$stable_build"; then
            stable_version=$version
            stable_build=$build
            stable_xcode=$app
        fi
    fi
done < <(list-xcodes)

if test -z "$stable_xcode"; then
    echo "No non-beta Xcode installation found in /Applications" >&2
    exit 1
fi

echo "Building with stable Xcode $stable_version ($stable_build; $stable_xcode)"
echo "Newest installed Xcode is $latest_version ($latest_build; $latest_xcode)"

original_dev_dir="$(xcode-select -p)"
restore-xcode() {
    if test "$(xcode-select -p)" != "$original_dev_dir"; then
        echo "Restoring active Xcode to $original_dev_dir"
        sudo xcode-select -s "$original_dev_dir"
    fi
}
trap restore-xcode EXIT

# The system default Ruby may be newer than the Gemfile's `~> 3.0` constraint
# (used by build-docs.sh). Fall back to a Homebrew-provided Ruby 3.x if so.
if ! ruby -e 'exit(RUBY_VERSION.split(".")[0].to_i < 4)' 2>/dev/null; then
    ruby34_prefix="$(brew --prefix ruby@3.4 2>/dev/null || true)"
    if test -z "$ruby34_prefix"; then
        echo "Installing ruby@3.4 (system ruby is too new for the docs Gemfile)..."
        brew install ruby@3.4
        ruby34_prefix="$(brew --prefix ruby@3.4)"
    fi
    if ! "$ruby34_prefix/bin/gem" list bundler -i --silent > /dev/null 2>&1; then
        "$ruby34_prefix/bin/gem" install bundler --no-document
    fi
    export PATH="$ruby34_prefix/bin:$PATH"
fi

if ! command -v fish > /dev/null 2>&1; then
    echo "Installing fish (needed to validate generated shell completions)..."
    brew install fish
fi

if test "$(xcode-select -p)" != "$stable_xcode/Contents/Developer"; then
    sudo xcode-select -s "$stable_xcode/Contents/Developer"
fi
./build-release.sh "$@"

if ! ./install-from-sources.sh --dont-rebuild; then
    if test "$latest_xcode" == "$stable_xcode"; then
        exit 1 # Nothing newer to retry with
    fi
    echo "Homebrew install step failed under Xcode $stable_version ($stable_build); retrying with $latest_version ($latest_build)..."
    sudo xcode-select -s "$latest_xcode/Contents/Developer"
    ./install-from-sources.sh --dont-rebuild
fi
