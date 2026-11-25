# Development

## Workspace

The repository lives inside a **separate UT99 469f install used as a workspace**,
so building and testing never touch the install you play on. The workspace has:

- its own `System` folder (a copy of a 469f `System`, without demos and logs) and
  its own `UnrealTournament.ini` / `User.ini`;
- `Maps`, `Textures`, `Sounds`, `Music`: the copies needed at startup (at least
  `Textures\Palettes.utx`), plus `Help` and `Web`. Its `UnrealTournament.ini`
  has extra `Paths=` and `CachePath=` entries that point to the main install, so
  maps, textures and the cache are read from there (read-only);
- optionally `Rec469e`: a 469e copy used only to play back demos for recording
  (see below).

Folders on your computer that the tools need go into
`AimTrainer\Tools\paths.local.ini` (not in the repository):

```ini
[paths]
main_install = C:\Games\UnrealTournament          ; demos are read from its System folder
mapping_install = C:\Games\UT469e_mapping         ; only for rebuilding the range map
```

`PlayAimTrainer.bat [map]` plays from the workspace. It uses a renamed copy of
the exe (`AimTrainerUT.exe`): UT 469 runs one copy per program name, so this
never hands its command to a game you have open.

## Building

```
python AimTrainer\Tools\build.py              # System\AimTrainer.u (the game)
python AimTrainer\Tools\make_release.py       # Release\AimTrainer.exe + README.txt + AimTrainer.zip
```

`build.py` compiles with UCC using a copy of `UnrealTournament.ini` that has the
package added to `EditPackages`, so the ini itself isn't changed.

`make_release.py` compiles the package and packs `AimTrainer.u`,
`AimTrainer.int`, `AimTrainerMoves.ini` and `Maps\DM-AimRange.unr` into
`AimTrainer.exe` as resources. It uses the .NET Framework's own C# compiler
(`csc.exe`), so nothing needs installing. The launcher's source is
`AimTrainer\Launcher\AimTrainerLauncher.cs`; it accepts
`AimTrainer.exe ["<UT folder>"] [install|uninstall] [quiet]`.

## Tests

```
python AimTrainer\Tools\test_fresh.py 45
```

This plays a session as a fresh install would: UT's `Default.ini` settings and
no saved `AimTrainer.ini` (yours is put back afterwards). It reports whether the
targets spawn and move. Run it before every release; a fresh install once had
`bNoMonsters` on, which deleted every target.

The game has a test mode for unattended runs. It joins and starts a session by
itself and logs every target's position, speed, physics, animation, movement
pattern and every takeoff and landing. In test mode nothing is saved to
`AimTrainer.ini`.

```
System\AimTrainerUT.exe "DM-AimRange?game=AimTrainer.ATGame?ATTest=1" ini=UnrealTournament.ini userini=User.ini log=ATTest.log -nosound -forceflush
```

Extra URL options:
- `?ATTestMenu=1` opens the Aim Trainer window;
- `?ATTestEsc=1` opens UT's menu the way Esc does, then Resume, several times;
- `?ATTestFire=1` fires every 1.2 s and logs shots, hits and accuracy;
- `?ATMoves=0|1|2`, `?ATStance=0|1`, `?ATTargets=1-4`, `?ATWeapon=<class>`
  override settings;
- `?ATCrouch=20` makes crouches 20x more frequent.
- `?ATTestDuck=1` keeps every target's hitbox fully crouched (the model
  doesn't crouch); the log shows each shot tested against it.

## Movement clips from demos

```
python AimTrainer\Tools\build.py ATRecorder --runtime Rec469e   # once: the recording console
python AimTrainer\Tools\record_demos.py                        # plays every demo not recorded yet
python AimTrainer\Tools\make_clips.py --stats                  # writes System\AimTrainerMoves.ini
```

- `record_demos.py` plays the demos from the main install's `System` and
  `System\Demos` with `Rec469e`. 469f RC crashes now and then on demos from
  servers running NPLoader (`scan_demos.py` lists them); 469e doesn't.
  - The recording console (`ATRecorder.ATRecConsole`) switches udemo to time
    based playback and adapts the speed, so that each drawn frame covers at most
    about 0.03 s of demo. It logs every visible player.
  - Demos that crash or stall are closed (the runner watches the log for
    `Critical:` lines), noted in `AimTrainer\Recordings\_failed.txt`, and
    skipped.
- `make_clips.py`:
  - keeps the moments when an enemy was in view at fighting range, moving like
    in a duel (no net run at or away from the viewer, no kickers, not standing
    still);
  - stores velocity relative to the viewer, in game time (udemo's speed and the
    server's game speed are taken out);
  - sorts the clips into patterns: long strafe, ADAD, mixed, dodge-heavy.

## How the targets move (ATTarget)

- Movement is a velocity in the trainee's frame (towards / beside the trainee),
  turned into an **acceleration direction** ("pressing keys"). UT's walking and
  falling physics do the rest. A non-player pawn only walks with
  `DesiredSpeed > 0` and `bCanWalk`.
- Sources:
  - recorded clips: picked by pattern, never the same pattern twice in a row,
    read 0.12 s ahead because keys lead velocity;
  - quick-ADAD bursts: about 0.3 s per side, as measured in the demos;
  - circle strafes: eight key directions in turn, a small loop on the spot;
  - synthetic ADAD and stop-and-go.
- Rules on top of every source:
  - dodges as UT does them: no new dodge until 0.35 s after landing;
  - only 1 in 10 recorded jumps is kept;
  - no run straight at the trainee (at least 45°; dodges 27°);
  - a strafe to one side lasts at most 0.9 s up to `MaxStrafeTime`;
  - in Fixed position, targets stay downrange within about 45°; on DM-AimRange
    they do in free roam too (from wherever the trainee stands, down +X).
- Hitbox: IG+'s crouch rule in `AdjustHitLocation` (called by
  `Pawn.TraceShot`) and IG+'s Sniper headshot line in `HeadshotZ`.
- Animations follow `TournamentPlayer.PlayRunning`, but a running animation is
  only chosen again at the end of its cycle or after 0.2 s the other way, so
  quick taps don't flip the body.
- A target that falls out of the level is replaced by the game. Such an actor
  may not get ticked any more, so its own code can't do it.

## Files

- `AimTrainer\Classes`:
  - `ATGame`: the game type, session, scores, settings;
  - `ATTarget`: the targets;
  - `ATMoves`: the clip library;
  - `ATHUD`: the HUD;
  - `ATMenuWindow` / `ATMenuClient`: the Aim Trainer window;
  - `ATEscHook`: Esc opens the window;
  - `ATSuperShockRifle`: the InstaGib rifle reporting its shots;
  - `ATMutator`: the `mutate at` commands.
- `ATRecorder\Classes\ATRecConsole.uc`: the demo recording console.
- `AimTrainer\Tools`: the build, release, test, recording and clip scripts.
- `AimTrainer\Sounds`: the kill-streak chimes, made by `Tools\make_sounds.py`
  and imported into `AimTrainer.u` when it is compiled.
- `AimTrainer\Map`: the range map's build script (UnrealEd MCP map generator)
  and its project file.
- `System\AimTrainer.int`, `System\AimTrainerMoves.ini`, `Maps\DM-AimRange.unr`:
  game files that the release packs (`AimTrainer.u` is built).
