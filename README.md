# Riverwing

A modern take on Atari's River Raid for Android and iOS, made with Godot 4.7.
Fly a stealth jet up a river, earn special weapons, survive fortified zones and a
battlefield every five minutes. Full game notes are in [README.txt](README.txt).

## Get the game

- **Android:** download `riverwing.apk` from the
  [latest release](../../releases/latest) on your phone and tap it to install
  (allow "Install unknown apps" when Android asks).
- **Browser:** upload `riverwing-web.zip` from the same release to itch.io.

## How builds work

Every push to `main` runs the **Build Riverwing** action
(`.github/workflows/build.yml`). It downloads Godot, exports the APK and the web
build, and publishes them as a new release. You can also start it by hand from
the Actions tab (Run workflow).

The APK is signed with the debug key in `ci/debug.keystore`, which is fine for
installing on your own phones. A store release on Google Play will need a
separate private release key.

## Edit locally

Open the folder in Godot 4.7 (Import, pick `project.godot`) and press F5.
