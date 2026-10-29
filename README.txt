RIVERWING PROTOTYPE v0.5.1
==========================

What this is
------------
You fly a small stealth jet up a river. Drag to move it anywhere on screen;
while your finger is down you fire, lift it to glide over FUEL tanks.
- Your jet has a basic cannon. SPECIAL WEAPONS are earned: points from kills
  and bridges fill the orange SUPPLY bar under your score. When it's full a
  weapon crate parachutes onto the river ahead: fly over it to take it.
  Each drop needs a bit more than the last. New weapon types unlock as your
  score grows: Spread Gun (start), Homing Missiles 2,000, Support Jets 5,000,
  Cluster Rockets 9,000, Laser Beam 14,000, Guard Drones 20,000, EMP 27,000.
  Crates only contain weapons you've unlocked. Each has its own energy bar (100%) that runs
  down as you use it; when it's empty the weapon is gone. You carry two at a
  time; tap a weapon in the bottom panel to switch (PC: Q / Tab or 1-3).
  Picking up a third drops the one with the least energy; picking up one you
  already have refills it.
  Weapons: Spread Gun, Laser Beam, Homing Missiles, Cluster Rockets,
  Support Jets, Guard Drones (block shots), EMP Blast (clears nearby shots).
- Every 5 minutes: a 45-second BATTLEFIELD. Tanks, troops, flak guns and SAM
  launchers fire from the banks and artillery strikes land on red circles.
  SAMs need about 1.6 s to lock on: keep a rock spire between you and the SAM
  (the cyan "radar shadow") to break the lock. Flares fire automatically at
  incoming missiles, but you only have a few and they recharge slowly.
  On the battlefield you automatically get a SHIELD (absorbs damage, even one
  bridge crash or ground missile) and the THUNDER RAILGUN in a bonus third
  slot. Both are taken back when the battlefield ends.
- After each battlefield the scenery changes: Green Valley, Frozen North,
  Desert Storm, Jungle Delta, City River, Volcanic Front, then round again,
  harder each time.
- RIVERBANKS: you can fly over land in an emergency, but a red ring starts
  filling. After about 2.5 s a ground missile launches and one hit downs the
  jet. Get back over the river before it reaches you and it loses its lock.
  Flares don't work against it.
- FORTIFIED ZONES (about every minute): only the green corridor between the
  beacon lights is safe. Red water has laser grids, and flak batteries open
  fire the moment you leave the corridor.

Play it on your PC
------------------
1. Open Godot (4.6 or newer), open the Riverwing project.
2. Press F5 (or the Play arrow at the top right).
   - Hold the mouse button and drag to fly and fire (works like a finger).
   - Or arrow keys / WASD to fly and hold Space to fire.
   - P or Esc pauses.
   - Test keys (only when run from the editor):
     B = next bridge, F = fortified zone now, N = battlefield now,
     M = finish the battlefield, K = switch scenery, G = god mode,
     J = get a random special weapon, H = supply drop now.
   - If a click doesn't start the game, click the game once to focus it, then click again.

Play it on your Pixel 9 (one-time setup)
----------------------------------------
1. Install Java: OpenJDK 17 (Eclipse Temurin 17).
2. Install Android Studio, open its SDK Manager and make sure these are ticked:
   Android SDK Platform-Tools, Android SDK Build-Tools, Android SDK Command-line Tools.
3. In Godot: Editor > Editor Settings > Export > Android
   - Java SDK Path: the Temurin 17 folder (e.g. C:\Program Files\Eclipse Adoptium\jdk-17...)
   - Android SDK Path: usually C:\Users\<you>\AppData\Local\Android\Sdk
4. In Godot: Editor > Manage Export Templates > Download and Install.
5. On the phone: Settings > About phone > tap "Build number" 7 times,
   then Settings > System > Developer options > turn on "USB debugging".
6. Plug the phone into the PC with USB and accept the "Allow USB debugging" prompt.
7. In Godot, a small Android icon appears at the top right next to the Play button.
   Click it: Godot builds, installs and launches the game on the phone.

What to tell me after playing
-----------------------------
- Does steering feel right? Too twitchy or too slow?
- Is the fuel too tight or too easy?
- Are the fortified corridors too narrow? Is the battlefield too hard?
- Is enemy fire too hard or too easy? Do repair kits show up often enough?
- Are special weapons too rare or too common? Which ones feel best?
- Anything confusing.
