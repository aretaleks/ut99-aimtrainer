# Aim Trainer for Unreal Tournament (UT99, 469f)

An aim trainer for UT99 whose targets move like real players. Their movement is
replayed from about 3 hours of recorded movement of real players in iCTF matches:
strafes, ADAD, dodges (including the hold-A/D-and-tap-W front dodge), double
dodges and the odd split-second crouch. It's mixed with patterns players use in
duels: longer quick-ADAD runs and small A-W-D-S circle strafes on the spot.

Targets move with UT's own player physics: the same acceleration, braking, top
speed, dodge (and the 0.35 s lock after landing) and air control as a player.
They always aim at you, hardly ever jump, and never run straight at you.

## Download and play

1. Get **AimTrainer.zip** from [Releases](../../releases) and unzip it anywhere.
2. Double-click **AimTrainer.exe**. It finds your Unreal Tournament folder (or
   asks for it), copies the trainer's four files into it and starts the game on
   the shooting range. Only these files are added; nothing of yours is changed:
   - `System\AimTrainer.u`, `System\AimTrainer.int`, `System\AimTrainerMoves.ini`
   - `Maps\DM-AimRange.unr`
3. Next time, run AimTrainer.exe again (a newer version updates the files).

You need UT99 with the [OldUnreal](https://www.oldunreal.com) **469f** patch.

Windows may warn that the exe is from an unknown publisher (it isn't signed):
choose "More info" > "Run anyway". You can also start the trainer from the game:
Practice Session, game type "Aim Trainer", any DM or CTF map.

`AimTrainer.exe uninstall` removes the four files again (your settings and
highscores in `System\AimTrainer.ini` stay).

## In the game

- **Esc** opens the Aim Trainer window instead of UT's menu. It has:
  - map (with a Load button);
  - weapon (Enhanced Shock Rifle / InstaGib, Sniper Rifle, Shock Rifle,
    Enforcer, Minigun, ...);
  - mode, range and position;
  - movement, session length and number of targets;
  - target model (random, or a fixed model with its skin and face; installed
    custom models are listed too);
  - team colour, hit sound, the headshot announcer ("Head Shot!!" as in UT,
    with the weapons that can headshot: Sniper Rifle and Ripper) and the kill
    streak sound: a chime that climbs with each kill in a row, Valorant style.
    Kills have to come less than 1.5 s apart (UT's multikills allow 3 s), not
    counting the time with no target up, and the first kill plays nothing, so
    it stays a reward rather than constant noise.

  Buttons: Start, UT Menu (UT's own menu), Main Menu, Exit UT, Resume.
- **Fire** starts a session: 3-2-1, then the timer runs (60 s by default).
- At the end you get your score, accuracy, kills, headshots and average time to
  kill, plus your best results for the same settings.

| Setting | Choices |
|---|---|
| Mode | **Duel**: targets have 100 health, die and come back elsewhere. **Tracking**: they never die; score is damage over time |
| Position | **Fixed**: you stand at the firing line and targets move downrange (within about 45°). **Free roam**: move around as in a game (on DM-AimRange targets still appear and stay down the range from you; on other maps they appear where you look) |
| Movement | **Recorded**: real players (default). **Synthetic**: made-up movement. **Mixed**: both |
| Range | Close, Mid, Far |

Score is the damage you deal (a kill is 100). Accuracy is hits / shots. Your
best 10 results for each combination of settings are kept in
`System\AimTrainer.ini`. There's no camera shake or bullet shells, so nothing
moves your view but your mouse.

Hitboxes match IG+ servers (rxut's next-netcode build, default settings):
standing, the target is UT's plain collision cylinder. A crouching target's
hitbox shrinks to about 65% of its height (over 0.25 s, back up in 0.1 s), so
shots just above a crouched model miss. Sniper headshots start at 0.66 of the
height (stock UT: 0.62), lower on a crouching target; 100 damage for a
headshot, 45 for the body.

Console commands for key binds: `mutate at help`.

**DM-AimRange** is a long, flat, evenly lit hall with the firing position at
one end and pillars along the walls every 1024 uu for judging distance.

## How the movement was made

A recording console played about 140 iCTF demos through udemo at high speed and
logged where every visible enemy moved. A script kept the moments when an enemy
was in view at fighting range and moving like in a duel (no flag runs, no
kickers). It stored their movement relative to the person they were fighting,
and grouped it into patterns (long strafes, ADAD, mixed, dodge-heavy). Targets
play a random clip of one pattern, then one of another, with quick-ADAD runs and
circle strafes in between. Only movement is stored, not names or anything else
from the demos.

## Building from source

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## License

[MIT](LICENSE). Unreal Tournament and its content belong to Epic Games; nothing
of the game is included here.
