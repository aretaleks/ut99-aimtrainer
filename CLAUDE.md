# Aim Trainer for UT99 (469f)

An aim trainer mod for Unreal Tournament (UT99, OldUnreal patch 469f). Its targets
are player models that move like real players: movement clips recorded from
real iCTF demos, plus quick-ADAD bursts and small circle strafes. Public repo:
https://github.com/aretaleks/ut99-aimtrainer (MIT).

- `README.md`: the player-facing description.
- `docs/DEVELOPMENT.md`: how it's built, tested and how the targets move.

Read `DEVELOPMENT.md` before changing movement or the tools.

## This folder

The repository root is a **full UT99 469f install used as a workspace**: game
copies, demo recordings, logs. A whitelist `.gitignore` keeps everything out
except:
- the project's own files: `AimTrainer/{Classes,Tools,Launcher,Map,Sounds}`,
  `ATRecorder/Classes`, `docs`, `README.md`, `LICENSE`, `PlayAimTrainer.bat`;
- the game files a release needs: `System/AimTrainer.int`,
  `System/AimTrainerMoves.ini`, `Maps/DM-AimRange.unr`.

A new file outside these paths must be added to `.gitignore`'s whitelist, or
it won't be committed.

Local paths (the main install that demos are read from, the mapping install)
are in `AimTrainer/Tools/paths.local.ini`. That file is gitignored and read
by `atpaths.py`.

## Packages and classes

- `AimTrainer`: the game.
  - `ATGame`: game type, sessions, scores, settings, `mutate at` commands,
    test mode.
  - `ATTarget`: the targets (movement, animation, hitbox, damage).
  - `ATMoves`: the clip library.
  - `ATHUD`: the HUD.
  - `ATMenuWindow` / `ATMenuClient`: the Esc window.
  - `ATEscHook`: makes Esc open that window instead of UT's menu.
  - `ATSuperShockRifle`: InstaGib rifle that reports its shots.
  - `ATMutator`.
- `ATRecorder`: a udemo console that records player movement from demos. It
  runs in `Rec469e/`, a 469e copy, because 469f crashes on demos from
  NPLoader servers.

## Commands

Run them from this folder. Use `python`, not `python3` (the Windows Store stub),
and not `py -I` for `make_release.py` (Pillow is in user site-packages).

```
python AimTrainer/Tools/build.py                 # compile System/AimTrainer.u (UCC, copied ini)
python AimTrainer/Tools/test_fresh.py 45         # fresh-install session check; run before every release
python AimTrainer/Tools/make_release.py          # Release/AimTrainer.exe + README.txt + AimTrainer.zip
python AimTrainer/Tools/make_sounds.py           # regenerate the kill-streak chimes (AimTrainer/Sounds)
```

Test mode: an unattended session that logs every target, `ATTEST` lines in
`System/ATTest.log`. The field layout is in `ATGame.uc`, next to the
`ATTEST` log call.

```
cd System && rm -f Running.ini ATTest.log
timeout 80 ./AimTrainerUT.exe "DM-AimRange?game=AimTrainer.ATGame?ATTest=1?ATTargets=3?ATStance=1" ini=UnrealTournament.ini userini=User.ini log=ATTest.log -nosound -forceflush < /dev/null
taskkill //F //IM AimTrainerUT.exe ; rm -f Running.ini
```

Options:
- `?ATTestFire=1`: shoots, half the time at body or head;
- `?ATTestMenu=1`: opens the window (this pauses the game, so no session runs);
- `?ATTestEsc=1`;
- `?ATMoves=0|1|2`, `?ATStance=0|1`, `?ATTargets=1-4`, `?ATWeapon=<class>`;
- `?ATCrouch=20`: 20× more crouches;
- `?ATTestDuck=1`: keeps the hitbox crouched.

Nothing is saved to `AimTrainer.ini` in test mode.

Always delete `System/Running.ini` after a run. If 469f finds one left over, it
shows a Recovery Mode prompt. The game window opens on the user's screen, so
keep test runs few and short.

Measure, don't guess: check behaviour changes against the test log (speeds,
anims per direction, stroke lengths, launches and landings). Where possible,
compare against the previous build (`git stash`, build, run, `git stash pop`,
rebuild).

To read stock source, export it into a scratch folder with the workspace's UCC:
`System/ucc.exe batchexport Botpack.u class uc <dir>` (likewise Engine, UWindow,
UMenu).

## Conventions

- Commits are small, one finished and tested change each, with a message that
  says why. End each with the attribution line Claude Code gives.
- Versioning is MAJOR.MINOR.PATCH:
  - patch for fixes and tweaks;
  - minor for new features or options;
  - major for breaking changes (needs a newer UT patch, scores no longer
    comparable, settings format changes).
- Release flow, only when asked:
  1. bump `AssemblyVersion`/`AssemblyFileVersion` in
     `AimTrainer/Launcher/AimTrainerLauncher.cs`;
  2. run `test_fresh.py`;
  3. add notes to `AimTrainer/Build/release_notes_X.Y.Z.md` (not committed);
  4. update the README template in `make_release.py` if the features changed;
  5. run `make_release.py`;
  6. commit "Release X.Y.Z" and push;
  7. `gh release create vX.Y.Z Release/AimTrainer.zip --title "Aim Trainer X.Y.Z" --notes-file ...`.
- Keep `README.md` and `docs/DEVELOPMENT.md` in step with behaviour changes.
- Only stock UT content and original assets. Nothing from other games: the
  streak chimes are synthesized by `make_sounds.py`.

## Design decisions (from the user's feedback; keep them)

The point is targets that move like real players. If a change makes them move
in a way no human does, it's wrong.

**Movement**
- No difficulty setting: movement is random, never reactive to your aim.
- UT physics only: drive targets by Acceleration ("keys"), never set Velocity.
  - Dodges follow UT: 1.5 × GroundSpeed, Z 160, landing cuts velocity to 10%,
    and a 0.35 s lock after landing.
  - A non-player pawn needs DesiredSpeed > 0 and bCanWalk.
- Hardly any jumps: only 1 in 10 recorded jumps is kept.
- Never run straight at the trainee: approaches are diagonal (at least 45°,
  dodges 27°).
- Strafes to one side are capped (0.9 s up to MaxStrafeTime). There are
  longer quick-ADAD bursts of about 0.3 s per side.
- Front dodges are common: hold A/D and double-tap W.
- Circle strafe means a small A-W-D-S loop around the target's own axis, not
  orbiting the player.
- Targets always aim at (face) the trainee.

**Animation**
- Running animations play at a fixed rate of 1.0. In quick A-D strokes the
  torso keeps one side: it only flips after 0.45 s going the other way
  (`SideFlipHold`).
- UT's dodge animation names are swapped: a dodge to the right plays `DodgeL`,
  as `PlayerPawn` and `TournamentPlayer` do.

**Range and feedback**
- DM-AimRange is the default map. On it, targets spawn and stay downrange in
  free roam too. Fixed position pins the player at the firing line.
- No camera shake, no shell cases, no death scream.
- Kill streak chime: kills less than 1.5 s apart, counting only time with a
  target up. The first kill plays nothing.
- Headshot announcer: only for decapitating weapons (Sniper, Ripper).

**Hitboxes**
They match IG+ as run on PassionateGaming servers (rxut/InstaGibPlus,
next-netcode, default WeaponSettings):
- standing, the plain cylinder;
- crouching, the top lowers to (1 − 0.7·duck)·H, taking 0.25 s to go down and
  0.1 s to come back up;
- Sniper headshots from (0.66 − 0.7·duck)·H, 100 damage on the head and 45 on
  the body.

**Esc window**
Esc opens the Aim Trainer window. `ATEscHook` hides UT's menu bar and closes
the Game pulldown that UT drops open by itself.

## Engine lessons

- A target that falls out of the level may stop being ticked, so the GameInfo
  replaces it.
- `GameInfo.IsRelevant` with `bNoMonsters` (on in fresh installs) deletes
  non-player pawns. `ATGame` overrides it.
- udemo:
  - call `SetPlayBackMode(0)` before `SetSpeed`;
  - game speed = TimeDilation / mySpeed;
  - the engine's `slomo` doesn't speed up demos.
- 469 hands a command to a running copy with the same exe name. The workspace
  runs `System/AimTrainerUT.exe` (a renamed copy) to avoid that.
- Calling SaveConfig from a console Tick crashed (GPF).
