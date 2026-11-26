//=============================================================================
// ATGame - Aim Trainer game type.
//
// Targets are player models that move like real players: their movement is
// replayed from clips recorded from demos of real matches (ATMoves), or made
// up on the spot (ADAD strafes, circle strafes, dodges, jumps) when no clips
// are installed. Sessions are timed; results are kept as local highscores in
// AimTrainer.ini.
//
// Settings: Advanced Options > Game Types > Aim Trainer, AimTrainer.ini, or
// in game with "mutate at <command>" (see "mutate at help").
//=============================================================================
class ATGame extends DeathMatchPlus config(AimTrainer);

// kill-streak chimes (made by Tools\make_sounds.py)
#exec AUDIO IMPORT FILE="Sounds\Streak1.wav" NAME="Streak1"
#exec AUDIO IMPORT FILE="Sounds\Streak2.wav" NAME="Streak2"
#exec AUDIO IMPORT FILE="Sounds\Streak3.wav" NAME="Streak3"
#exec AUDIO IMPORT FILE="Sounds\Streak4.wav" NAME="Streak4"

// ---- Settings --------------------------------------------------------------
var() config int    Mode;          // 0 = Duel (targets die and respawn), 1 = Tracking (targets never die)
var() config int    Stance;        // 0 = free roam, 1 = fixed: stand in place, targets downrange
var() config string TrainWeapon;   // weapon class the player gets
var() config int    Range;         // 0 Close, 1 Mid, 2 Far
var() config int    Course;        // DM-AimRange's hall: 0 Flat Range, 1 High Ground (platforms), 2 Airborne (kickers)
var() config int    Duration;      // session length in seconds
var() config int    NumTargets;    // targets at once (1-4)
var() config int    MoveSource;    // 0 Recorded (demo clips), 1 Synthetic, 2 Mixed
var() config string TargetClass;   // player class for the targets ("" = a random stock model each time)
var() config string TargetSkin;    // skin for TargetClass ("" = its default)
var() config string TargetFace;    // face for TargetClass ("" = none)
var() config int    TargetTeam;    // 0 red, 1 blue, 255 no team colours
var() config int    TargetHealth;  // Duel mode health
var() config bool   bHitSound;
var() config bool   bHeadshotAnnouncer; // "Head Shot!!" like UT on decapitating hits (sniper, ripper)
var() config bool   bStreakSound;   // a chime that climbs with each kill of a streak (from the 2nd kill)
var() config float  StreakWindow;   // seconds between kills to keep a streak (UT's multikills: 3), counted only while a target is up
var() config string HitSoundName;
var() config float  RespawnDelay;
var() config float  CrouchFrequency;
var() config float  BurstChance;        // recorded movement: share of segments that are a quick-ADAD burst
var() config float  CircleStrafeChance; // ... and that are a circle strafe
var() config float  MaxStrafeTime;   // longest strafe to one side before switching (seconds; each one is 0.9 s up to this)
var() config bool   bMenuAtStart;   // open the Aim Trainer window when a map starts // synthetic movement: how often targets do a quick crouch (1 = normal, 0 = never)  // Duel mode: seconds before a killed target comes back

// ---- Highscores --------------------------------------------------------------
// Each entry: Key;Score;Accuracy x10;Kills;Hits;Shots;Date;Name
var config string Scores[300];
var int MaxPerKey;
var string TopScores[10];

// ---- Static data ---------------------------------------------------------------
var string ModeNames[2];
var string RangeNames[3];
var string CourseNames[3];
var string MoveNames[3];
var float  RangeMin[3], RangeMax[3];
var string WeaponList[12];
var string WeaponNames[12];
var class<TournamentPlayer> ModelClasses[5];
var string ModelSkins[5];
var string ModelFaces[5];

// ---- Session state ------------------------------------------------------------
enum ESessionPhase
{
	SP_Idle,
	SP_Countdown,
	SP_Running,
	SP_Results
};
var ESessionPhase Phase;
var float PhaseTime;        // seconds since the phase began
var float SessionLeft;      // seconds left in the running session
var int   LastCount;        // last countdown number announced

var PlayerPawn Trainee;
var ATTarget   Targets[4];
var ATMoves    Moves;
var bool       bCleanedLevel;
var bool       bFireWasDown;
var int        LastAmmo;
var Weapon     LastWeapon;
var sound      HitSnd;

// stats of the current (or last) session
var int   Shots, Hits, Kills, Headshots, Damage;
var float HitTick;          // Level.TimeSeconds of the last counted hit
var float TTKSum;           // Duel: sum of time-to-kill
var int   TTKCount;
var bool  bNewBest;
var int   ResultRank;       // 1-based rank of the last result in its table, 0 = not placed
var bool  bTestMode, bTestJoined, bTestMenu, bTestMenuOpened, bTestEsc, bTestFire, bTestDuck;
var float TestFireTime, TestEscTime;
var int   TestEscStep;
var bool  bHookChecked, bStartMenuShown;
var bool  bFixedSet, bFixedApplied;   // Fixed position: firing spot taken / player movement locked
var vector FixedSpot;
var int   FixedYaw;
var int   Streak;          // kills in the current streak
var float StreakTime;      // seconds (with a target up) since the last kill
var float StreakSoundAt;   // Level.TimeSeconds of the last streak chime
var Sound StreakSounds[4];
var bool  bRangeMap;     // on DM-AimRange: downrange is +X (yaw 0) wherever the trainee stands
var Kicker Pads[16];      // Airborne: the kicker pads of its hall
var int    NumPads;
var() config float MaxKickSpeed;  // Airborne: fastest sideways speed of a pad's arc (uu/s)
var float TestLogTime;
var string StatusMsg;       // short message for the HUD (settings changes etc)
var float  StatusTime;

// ============================================================================
// Setup
// ============================================================================

event InitGame( string Options, out string Error )
{
	local string S;

	Super.InitGame(Options, Error);

	// No bots, limits or translocator: the session timer is the only rule.
	MinPlayers = 0;
	InitialBots = 0;
	RemainingBots = 0;
	FragLimit = 0;
	TimeLimit = 0;
	bUseTranslocator = false;
	bRequireReady = false;
	bMultiWeaponStay = false;
	// UT deletes non-player pawns as they spawn when this is on, and fresh
	// installs have it on: the targets are non-player pawns.
	bNoMonsters = false;
	// DM-AimRange: targets stay down the range (+X) in free roam too
	bRangeMap = InStr(Caps(string(Level)), "DM-AIMRANGE.") == 0;

	// URL options override the ini for this run, e.g. ?ATWeapon=Botpack.ShockRifle?ATTargets=2
	S = ParseOption(Options, "ATWeapon");
	if ( S != "" ) TrainWeapon = S;
	S = ParseOption(Options, "ATMode");
	if ( S != "" ) Mode = Clamp(int(S), 0, 1);
	S = ParseOption(Options, "ATRange");
	if ( S != "" ) Range = Clamp(int(S), 0, 2);
	S = ParseOption(Options, "ATCourse");
	if ( S != "" ) Course = Clamp(int(S), 0, 2);
	S = ParseOption(Options, "ATTime");
	if ( S != "" ) Duration = Clamp(int(S), 10, 600);
	S = ParseOption(Options, "ATTargets");
	if ( S != "" ) NumTargets = Clamp(int(S), 1, 4);
	S = ParseOption(Options, "ATMoves");
	if ( S != "" ) MoveSource = Clamp(int(S), 0, 2);
	bTestMode = ParseOption(Options, "ATTest") == "1";
	S = ParseOption(Options, "ATStance");
	if ( S != "" ) Stance = Clamp(int(S), 0, 1);
	S = ParseOption(Options, "ATCrouch");
	if ( S != "" ) CrouchFrequency = float(S);
	bTestMenu = ParseOption(Options, "ATTestMenu") == "1";
	bTestEsc = ParseOption(Options, "ATTestEsc") == "1";
	bTestFire = ParseOption(Options, "ATTestFire") == "1";
	bTestDuck = ParseOption(Options, "ATTestDuck") == "1";
	ClampSettings();

	Moves = new class'ATMoves';
	Moves.Init();
	if ( HitSoundName != "" )
		HitSnd = Sound(DynamicLoadObject(HitSoundName, class'Sound', true));
}

function PostBeginPlay()
{
	local ATMutator M;

	Super.PostBeginPlay();
	FindPads();
	M = Spawn(class'ATMutator');
	M.Game = self;
	if ( BaseMutator != None )
		BaseMutator.AddMutator(M);
	else
		BaseMutator = M;
}

function ClampSettings()
{
	Mode = Clamp(Mode, 0, 1);
	Range = Clamp(Range, 0, 2);
	Course = Clamp(Course, 0, 2);
	Duration = Clamp(Duration, 10, 600);
	NumTargets = Clamp(NumTargets, 1, 4);
	MoveSource = Clamp(MoveSource, 0, 2);
	TargetHealth = Clamp(TargetHealth, 1, 1000);
	if ( TargetTeam != 0 && TargetTeam != 1 )
		TargetTeam = 255;
	if ( TrainWeapon == "" )
		TrainWeapon = "Botpack.SuperShockRifle";
}

event PostLogin( PlayerPawn NewPlayer )
{
	Super.PostLogin(NewPlayer);
	if ( Trainee == None && !NewPlayer.IsA('Spectator') )
		Trainee = NewPlayer;
}

function Logout( Pawn Exiting )
{
	Super.Logout(Exiting);
	if ( Exiting == Trainee )
	{
		Trainee = None;
		RemoveTargets();
	}
}

// Only the training weapon, nothing else.
function AddDefaultInventory( Pawn P )
{
	if ( P.IsA('Spectator') || !P.IsA('PlayerPawn') )
		return;
	GiveTrainWeapon(P);
}

function GiveTrainWeapon( Pawn P )
{
	local Inventory Inv, Next;
	local class<Weapon> WC;

	WC = class<Weapon>(DynamicLoadObject(TrainWeapon, class'Class', true));
	if ( WC == None )
	{
		Status("Unknown weapon"@TrainWeapon$", using InstaGib rifle");
		TrainWeapon = "Botpack.SuperShockRifle";
		WC = class'SuperShockRifle';
	}
	// the InstaGib rifle uses no ammo: this version reports its shots instead
	if ( WC == class'SuperShockRifle' )
		WC = class'ATSuperShockRifle';
	for ( Inv = P.Inventory; Inv != None; Inv = Next )
	{
		Next = Inv.Inventory;
		if ( Weapon(Inv) != None && Inv.Class != WC )
		{
			if ( P.Weapon == Inv )
				P.Weapon = None;
			Inv.Destroy();
		}
	}
	if ( P.FindInventoryType(WC) == None )
		GiveWeapon(P, string(WC));
	if ( P.Weapon == None || P.Weapon.Class != WC )
	{
		P.PendingWeapon = Weapon(P.FindInventoryType(WC));
		if ( P.PendingWeapon != None )
		{
			if ( P.Weapon == None )
				P.ChangedWeapon();
			else
				P.Weapon.PutDown();
		}
	}
	LastWeapon = None;
}

// Targets take damage from everything; the trainee takes none.
function int ReduceDamage( int Dmg, name DamageType, Pawn Injured, Pawn InstigatedBy )
{
	if ( Injured.IsA('PlayerPawn') )
		return 0;
	return Super.ReduceDamage(Dmg, DamageType, Injured, InstigatedBy);
}

function bool ShouldRespawn( Actor Other )
{
	return false;
}

// Our targets are always allowed, whatever the game or a mutator thinks of
// non-player pawns (bNoMonsters, difficulty flags, ...).
function bool IsRelevant( Actor Other )
{
	if ( ATTarget(Other) != None )
		return true;
	return Super.IsRelevant(Other);
}

// ============================================================================
// Main loop
// ============================================================================

function Tick( float Delta )
{
	local Inventory I;

	Super.Tick(Delta);

	if ( !bCleanedLevel )
	{
		// Remove the map's pickups: the trainee only uses the training weapon.
		foreach AllActors(class'Inventory', I)
			if ( I.Owner == None )
				I.Destroy();
		bCleanedLevel = true;
	}

	if ( Trainee == None || Trainee.bDeleteMe )
	{
		Trainee = None;
		return;
	}

	// The streak clock only runs while there is a target to shoot, so a
	// respawn delay doesn't break a streak.
	if ( Streak > 0 && AnyTargetUp() )
		StreakTime += Delta;
	if ( bTestMode && Trainee.IsInState('PlayerWaiting') && !bTestJoined )
	{
		bTestJoined = true;
		StartMatch();
	}
	if ( Trainee.Health <= 0 || Trainee.IsInState('Dying') || Trainee.IsInState('PlayerWaiting') )
		return;

	if ( !bHookChecked )
	{
		bHookChecked = true;
		InstallEscHook();
	}
	if ( bMenuAtStart && !bStartMenuShown && !bTestMode && PhaseTime > 0.5 )
	{
		bStartMenuShown = true;
		OpenMenu(Trainee);
	}
	KeepInCourse();
	ApplyStance();
	NoShakeNoShells();
	TrackShots();
	PhaseTime += Delta;
	if ( bTestMode )
		TestTick(Delta);

	switch ( Phase )
	{
		case SP_Idle:
			// Targets keep moving in idle so the trainee can warm up.
			KeepTargets();
			if ( FirePressed() && PhaseTime > 0.75 )
				StartCountdown();
			break;
		case SP_Countdown:
			KeepTargets();
			if ( int(3.999 - PhaseTime) != LastCount && PhaseTime < 3.0 )
			{
				LastCount = int(3.999 - PhaseTime);
				Announce(LastCount);
			}
			if ( PhaseTime >= 3.0 )
				StartSession();
			break;
		case SP_Running:
			KeepTargets();
			SessionLeft -= Delta / Level.TimeDilation;
			if ( SessionLeft <= 0 )
				EndSession();
			break;
		case SP_Results:
			KeepTargets();
			if ( PhaseTime > 1.5 && FirePressed() )
				StartCountdown();
			break;
	}
	bFireWasDown = Trainee.bFire != 0;
}

// ?ATTest=1: joins and starts a session by itself and logs what the targets do,
// so the trainer can be checked from the log without anyone playing.
function TestTick( float Delta )
{
	local int i;
	local ATTarget T;
	local WindowConsole C;
	local UT_ShellCase Shell;

	TestLogTime += Delta;
	if ( bTestEsc )
	{
		// Esc -> window, Resume, Esc again, Resume, F7 route: log what is shown each time
		C = WindowConsole(Trainee.Player.Console);
		if ( C != None )
		{
			TestEscTime += Delta / Level.TimeDilation;
			if ( TestEscStep == 0 && TestEscTime > 1.0 ) { TestEscStep++; C.bQuickKeyEnable = false; C.LaunchUWindow(); Trainee.SetPause(false); Log("ATTEST step esc #1", 'ATTest'); }
			else if ( TestEscStep == 1 && TestEscTime > 1.5 ) { TestEscStep++; LogMenuState(C); ResumeFromTest(C); }
			else if ( TestEscStep == 2 && TestEscTime > 2.0 ) { TestEscStep++; C.bQuickKeyEnable = false; C.LaunchUWindow(); Trainee.SetPause(false); Log("ATTEST step esc #2", 'ATTest'); }
			else if ( TestEscStep == 3 && TestEscTime > 2.5 ) { TestEscStep++; LogMenuState(C); ResumeFromTest(C); }
			else if ( TestEscStep == 4 && TestEscTime > 3.0 ) { TestEscStep++; OpenMenu(Trainee); Trainee.SetPause(false); Log("ATTEST step F7", 'ATTest'); }
			else if ( TestEscStep == 5 && TestEscTime > 3.5 ) { TestEscStep++; LogMenuState(C); ResumeFromTest(C); }
			else if ( TestEscStep == 6 && TestEscTime > 4.0 ) { TestEscStep++; LogMenuState(C); }
		}
	}
	else if ( bTestMenu )
	{
		if ( !bTestMenuOpened && PhaseTime > 1.0 )
		{
			bTestMenuOpened = true;
			OpenMenu(Trainee);
			Log("ATTEST menu opened", 'ATTest');
		}
	}
	else if ( Phase == SP_Idle && PhaseTime > 2.0 )
		StartCountdown();
	if ( bTestFire && Phase == SP_Running && Trainee.Weapon != None )
	{
		TestFireTime += Delta;
		if ( TestFireTime > 1.2 )
		{
			TestFireTime = 0;
			// aim at target 0 now and then so some shots hit
			// (at the body or the head)
			if ( Targets[0] != None && !Targets[0].bHidden && FRand() < 0.5 )
				Trainee.ViewRotation = rotator(Targets[0].Location + int(FRand() < 0.5) * 0.8 * Targets[0].CollisionHeight * vect(0,0,1)
					- (Trainee.Location + Trainee.EyeHeight * vect(0,0,1)));
			i = 0;
			foreach AllActors(class'UT_ShellCase', Shell)
				i++;
			Log("ATTEST before shot: shells=" $ i @ "shaketimer=" $ Trainee.shaketimer @ "weaponshake=" $ Trainee.Weapon.ShakeMag, 'ATTest');
			Trainee.Weapon.Fire(0);
			Log("ATTEST fired shots=" $ Shots @ "hits=" $ Hits @ "acc=" $ Accuracy(), 'ATTest');
		}
	}
	if ( TestLogTime < 0.05 )
		return;
	TestLogTime = 0;
	// One line per target, 20 times a second:
	//   ATTEST time phase slot X Y Z hspeed vz accel physics anim useclip cliplen
	//     dist dead health crouch synmode dodgelock towardsvel sidevel faceoffset
	//     yaw-off-trainee ledgeturns kicked
	// (speeds uu/s; dist horizontal to the trainee; yaw 0 = facing the trainee).
	// Also ATLAUNCH name time dodge clip approach, ATLAND name time dodging kicked
	// X Y Z, ATKICK time pad hspeed vz apex flight-time*100 partner.
	for ( i = 0; i < 4; i++ )
	{
		T = Targets[i];
		if ( T == None )
			continue;
		Log("ATTEST" @ Level.TimeSeconds @ int(Phase) @ i @ int(T.Location.X) @ int(T.Location.Y) @ int(T.Location.Z)
			@ int(VSize(T.Velocity * vect(1,1,0))) @ int(T.Velocity.Z) @ int(VSize(T.Acceleration)) @ int(T.Physics) @ T.AnimSequence
			@ int(T.bUseClip) @ T.ClipLen @ int(VSize((T.Location - Trainee.Location) * vect(1,1,0)))
			@ int(T.bDead) @ T.Health @ int(T.bCrouch) @ T.SynMode @ int(Level.TimeSeconds < T.DodgeLockUntil)
			@ int(T.Velocity dot Normal((Trainee.Location - T.Location) * vect(1,1,0)))
			@ int(T.Velocity dot (Normal((Trainee.Location - T.Location) * vect(1,1,0)) cross vect(0,0,1)))
			@ T.FaceOffset @ ((T.Rotation.Yaw - rotator(Trainee.Location - T.Location).Yaw) & 65535)
			@ int(T.LedgeTurns) @ int(T.bKicked), 'ATTest');
	}
}

// A steady view: no camera shake from shooting (the weapon's own shake is set
// to 0) or from explosions (the shake timers are cleared), and no bullet
// shells (minigun, enforcer, sniper) flying around.
function NoShakeNoShells()
{
	local UT_ShellCase Shell;

	if ( Trainee.Weapon != None )
	{
		Trainee.Weapon.ShakeTime = 0;
		Trainee.Weapon.ShakeMag = 0;
		Trainee.Weapon.ShakeVert = 0;
	}
	if ( Trainee.shaketimer > 0 || Trainee.verttimer > 0 )
	{
		Trainee.shaketimer = 0;
		Trainee.shakemag = 0;
		Trainee.shakevert = 0;
		Trainee.verttimer = 0;
		Trainee.ViewRotation.Roll = 0;
	}
	foreach AllActors(class'UT_ShellCase', Shell)
		Shell.Destroy();
}

// ============================================================================
// Courses (DM-AimRange's three halls, see AimTrainer/Map/make_range_map.py)
// ============================================================================

// The course in use: the halls only exist on DM-AimRange, other maps are flat.
function int ActiveCourse()
{
	if ( bRangeMap )
		return Course;
	return 0;
}

// Which hall a point is in: they lie side by side along Y, 5120 apart.
function int CourseOfY( float Y )
{
	if ( Y > 2560 )
		return 1;
	if ( Y < -2560 )
		return 2;
	return 0;
}

function float CourseCenterY( int C )
{
	if ( C == 1 )
		return 5120;
	if ( C == 2 )
		return -5120;
	return 0;
}

function bool InCourse( vector V )
{
	return CourseOfY(V.Y) == ActiveCourse();
}

// Players start at the firing line of the chosen course's hall.
function NavigationPoint FindPlayerStart( Pawn Player, optional byte InTeam, optional string incomingName )
{
	local PlayerStart P, Pick;
	local int N;

	if ( bRangeMap )
	{
		foreach AllActors(class'PlayerStart', P)
			if ( InCourse(P.Location) && Rand(++N) == 0 )
				Pick = P;
		if ( Pick != None )
			return Pick;
	}
	return Super.FindPlayerStart(Player, InTeam, incomingName);
}

// The trainee is always in the chosen hall: after a course change, and after
// falling into High Ground's pit, back to its firing line.
function KeepInCourse()
{
	local NavigationPoint N;

	if ( !bRangeMap )
		return;
	if ( InCourse(Trainee.Location) && !(ActiveCourse() == 1 && Trainee.Location.Z < -100) )
		return;
	N = FindPlayerStart(Trainee);
	if ( N == None || !InCourse(N.Location) )
		return;
	RemoveTargets();
	Trainee.SetLocation(N.Location);
	Trainee.Velocity = vect(0,0,0);
	Trainee.SetPhysics(PHYS_Falling);
	Trainee.ClientSetRotation(N.Rotation);
	bFixedSet = false;   // the firing spot is taken again where it lands
	if ( Phase == SP_Running || Phase == SP_Countdown )
		StopSession();
}

// Airborne: the hall's kicker pads (placed by the map, their arcs set here).
function FindPads()
{
	local Kicker K;

	NumPads = 0;
	if ( !bRangeMap )
		return;
	foreach AllActors(class'Kicker', K)
		if ( CourseOfY(K.Location.Y) == 2 && NumPads < ArrayCount(Pads) )
			Pads[NumPads++] = K;
}

// Horizontal distance from Origin (the firing spot, or the trainee) within the
// range band, give or take Slack?
function bool InBand( vector V, vector Origin, float Slack )
{
	local float D;

	D = VSize((V - Origin) * vect(1,1,0));
	return D > RangeMin[Range] * (1 - Slack) && D < RangeMax[Range] * (1 + Slack);
}

// Airborne: is V downrange by a distance in the range band? Pads belong to a
// band by how far down the range they are, wherever along the firing line the
// trainee stands.
function bool DownrangeInBand( vector V )
{
	local vector Origin;
	local int Yaw;
	local float D;

	if ( !DownrangeAxis(Origin, Yaw) )
	{
		Origin = Trainee.Location;
		Yaw = 0;
	}
	D = (V - Origin) dot vector(rot(0,1,0) * Yaw);
	return D >= RangeMin[Range] && D <= RangeMax[Range];
}

// Airborne: the pad nearest to V among those in the range band (None if none).
function Kicker NearestPad( vector V )
{
	local int i;
	local float D, BestD;
	local Kicker Best;

	BestD = 1000000;
	for ( i = 0; i < NumPads; i++ )
	{
		if ( !DownrangeInBand(Pads[i].Location) )
			continue;
		D = VSize((Pads[i].Location - V) * vect(1,1,0));
		if ( D < BestD )
		{
			BestD = D;
			Best = Pads[i];
		}
	}
	return Best;
}

// Airborne: a pad across the hall from K in the range band, picked at random
// (straight across or diagonally, towards or away from the trainee).
function Kicker PartnerPad( Kicker K )
{
	local int i, N;
	local Kicker Pick;

	for ( i = 0; i < NumPads; i++ )
		if ( (Pads[i].Location.Y - CourseCenterY(2)) * (K.Location.Y - CourseCenterY(2)) < 0
			&& DownrangeInBand(Pads[i].Location) && Rand(++N) == 0 )
			Pick = Pads[i];
	return Pick;
}

// Airborne: a new arc for K, set just before a target steps on it, so no two
// flights are the same. It lands between half way and just short of a pad
// across, a little up or down the range (staying in the band), on a low and
// fast or a high and slow arc, no faster than MaxKickSpeed sideways (a long,
// flat arc gets higher instead). Solved for the zone's gravity; the kickers
// kill the old velocity (bKillVelocity), so the arc is exact.
function AimKick( Kicker K )
{
	local Kicker P;
	local vector From, To;
	local float Apex, Top, Vz, T, G, H;

	P = PartnerPad(K);
	if ( P == None )
		return;
	From = K.Location;
	To = From + (P.Location - From) * (0.5 + FRand() * 0.4);
	To.X += (FRand() - 0.5) * 500;
	if ( !DownrangeInBand(To) )
		To.X = From.X + (P.Location.X - From.X) * (To.Y - From.Y) / (P.Location.Y - From.Y);
	To.Z = P.Location.Z;
	Apex = 64 + FRand() * FRand() * 640;
	G = Abs(K.Region.Zone.ZoneGravity.Z);
	if ( G < 100 )
		G = 950;
	Top = FMax(From.Z, To.Z) + Apex;
	Vz = Sqrt(2 * G * (Top - From.Z));
	T = Vz / G + Sqrt(2 * (Top - To.Z) / G);
	H = VSize((To - From) * vect(1,1,0));
	if ( H / T > MaxKickSpeed )
	{
		T = H / MaxKickSpeed;
		Vz = (To.Z - From.Z) / T + 0.5 * G * T;
	}
	K.KickVelocity.X = (To.X - From.X) / T;
	K.KickVelocity.Y = (To.Y - From.Y) / T;
	K.KickVelocity.Z = Vz;
	K.bKillVelocity = true;
	if ( bTestMode )
		Log("ATKICK" @ Level.TimeSeconds @ K.Name @ int(VSize(K.KickVelocity * vect(1,1,0))) @ int(Vz)
			@ int(Vz * Vz / (2 * G)) @ int(T * 100) @ P.Name, 'ATTest');
}

// A spot on a course. High Ground: the flat top of a platform in the range
// band (not a ramp, not near an edge, not the pit). Airborne: the floor beside
// a pad in the band. False if none was found (the caller falls back).
function bool FindCourseSpot( out vector Spot, vector Eye, vector Origin, int AxisYaw )
{
	local int Try, Dir;
	local vector Axis, Side, Cand, HitLoc, HitNorm, H2, N2;
	local float Fwd, Lat;
	local Kicker K;

	Axis = vector(rot(0,1,0) * AxisYaw);
	Side = Axis cross vect(0,0,1);
	for ( Try = 0; Try < 120; Try++ )
	{
		if ( ActiveCourse() == 2 )
		{
			if ( NumPads == 0 )
				return false;
			K = Pads[Rand(NumPads)];
			if ( !DownrangeInBand(K.Location) )
				continue;
			// beside the pad, towards the middle of the hall
			Cand = K.Location + Normal((CourseCenterY(2) - K.Location.Y) * vect(0,1,0)) * (120 + FRand() * 250)
				+ (FRand() - 0.5) * 300 * vect(1,0,0);
		}
		else
		{
			Fwd = RangeMin[Range] + FRand() * (RangeMax[Range] - RangeMin[Range]);
			Lat = (FRand() * 2 - 1) * FMax(Fwd * 0.9, 300);
			Cand = Origin + Axis * Fwd + Side * Lat;
		}
		Cand.Z = 1100;
		if ( Trace(HitLoc, HitNorm, Cand - vect(0,0,1500), Cand, false) == None || HitNorm.Z < 0.95 )
			continue;
		if ( ActiveCourse() == 1 )
		{
			if ( HitLoc.Z < -100 )
				continue;   // the pit
			// room all round: the same floor 80 out on each side
			for ( Dir = 0; Dir < 4; Dir++ )
			{
				Cand = HitLoc + vect(0,0,8) + 80 * vector(rot(0,16384,0) * Dir);
				if ( Trace(H2, N2, Cand - vect(0,0,40), Cand, false) == None || Abs(H2.Z - HitLoc.Z) > 4 )
					break;
			}
			if ( Dir < 4 )
				continue;
		}
		Spot = HitLoc + vect(0,0,40);
		if ( !InCourse(Spot) || !FastTrace(Spot + vect(0,0,30), Eye) || TooCloseToTargets(Spot) )
			continue;
		return true;
	}
	return false;
}

// Fixed position: the trainee stands at the firing spot (aiming is free),
// targets stay downrange. Free roam: normal movement.
function ApplyStance()
{
	local vector V;

	if ( Stance == 1 )
	{
		if ( !bFixedSet )
		{
			bFixedSet = true;
			FixedSpot = Trainee.Location;
			FixedYaw = Trainee.ViewRotation.Yaw & 65535;
		}
		if ( !bFixedApplied )
		{
			bFixedApplied = true;
			Trainee.GroundSpeed = 0;
			Trainee.AirSpeed = 0;
			Trainee.AccelRate = 0;
			Trainee.JumpZ = 0;
		}
		V = Trainee.Location - FixedSpot;
		V.Z = 0;
		if ( VSize(V) > 4 && Trainee.Physics == PHYS_Walking )
		{
			Trainee.SetLocation(FixedSpot + (Trainee.Location.Z - FixedSpot.Z) * vect(0,0,1));
			Trainee.Velocity = vect(0,0,0);
		}
	}
	else
	{
		bFixedSet = false;
		if ( bFixedApplied )
		{
			bFixedApplied = false;
			Trainee.GroundSpeed = Trainee.default.GroundSpeed;
			Trainee.AirSpeed = Trainee.default.AirSpeed;
			Trainee.AccelRate = Trainee.default.AccelRate;
			Trainee.JumpZ = Trainee.default.JumpZ * PlayerJumpZScaling();
		}
	}
}

// Settings and highscores go to AimTrainer.ini; test runs (?ATTest=1, with
// their URL settings and automatic shots) never write it.
function SaveSettings()
{
	if ( !bTestMode )
		SaveConfig();
}

// Weapons that use no ammo report their shots here.
function ShotFired( Weapon W )
{
	if ( Phase == SP_Running )
		Shots++;
}

function LogMenuState( WindowConsole C )
{
	local UWindowWindow W;
	local string S;

	S = "menu active=" $ C.bUWindowActive;
	if ( UMenuRootWindow(C.Root) != None )
		S = S @ "utbar=" $ UMenuRootWindow(C.Root).MenuBar.bWindowVisible;
	for ( W = C.Root.FirstChildWindow; W != None; W = W.NextSiblingWindow )
	{
		if ( ATMenuWindow(W) != None )
			S = S @ "trainerwindow=" $ W.bWindowVisible;
		if ( UWindowPulldownMenu(W) != None && W.bWindowVisible )
			S = S @ "utpulldown=" $ W.Class.Name;
	}
	Log("ATTEST" @ S, 'ATTest');
}

function ResumeFromTest( WindowConsole C )
{
	local UWindowWindow W;
	for ( W = C.Root.FirstChildWindow; W != None; W = W.NextSiblingWindow )
		if ( ATMenuWindow(W) != None && W.bWindowVisible )
			W.Close();
	Log("ATTEST resumed", 'ATTest');
}

function bool FirePressed()
{
	return Trainee.bFire != 0 && !bFireWasDown;
}

// Shots are counted from ammo use; ammo is refilled so it never runs out.
function TrackShots()
{
	local Weapon W;
	local int Used;

	W = Trainee.Weapon;
	if ( W == None || W.AmmoType == None )
	{
		LastWeapon = None;
		return;
	}
	if ( W != LastWeapon )
	{
		LastWeapon = W;
		LastAmmo = W.AmmoType.AmmoAmount;
	}
	Used = LastAmmo - W.AmmoType.AmmoAmount;
	if ( Used > 0 && Phase == SP_Running )
		Shots += Used;
	if ( W.AmmoType.AmmoAmount < W.AmmoType.MaxAmmo )
		W.AmmoType.AmmoAmount = W.AmmoType.MaxAmmo;
	LastAmmo = W.AmmoType.AmmoAmount;
}

function Announce( int N )
{
	local sound S;

	if ( N == 3 )
		S = Sound(DynamicLoadObject("Announcer.cd3", class'Sound', true));
	else if ( N == 2 )
		S = Sound(DynamicLoadObject("Announcer.cd2", class'Sound', true));
	else if ( N == 1 )
		S = Sound(DynamicLoadObject("Announcer.cd1", class'Sound', true));
	if ( S != None )
		Trainee.ClientPlaySound(S, , true);
}

function StartCountdown()
{
	local int i;

	Phase = SP_Countdown;
	PhaseTime = 0;
	LastCount = -1;
	Shots = 0; Hits = 0; Kills = 0; Headshots = 0; Damage = 0;
	Streak = 0;
	TTKSum = 0; TTKCount = 0;
	bNewBest = false;
	ResultRank = 0;
	// fresh targets in fresh spots
	RemoveTargets();
	KeepTargets();
	for ( i = 0; i < 4; i++ )
		if ( Targets[i] != None )
			Targets[i].Freeze(3.0);
}

function StartSession()
{
	local int i;

	Phase = SP_Running;
	PhaseTime = 0;
	SessionLeft = Duration;
	for ( i = 0; i < 4; i++ )
		if ( Targets[i] != None )
			Targets[i].ResetLife();
	Trainee.ClientPlaySound(Sound(DynamicLoadObject("Botpack.Generic.RespawnSound2", class'Sound', true)), , true);
}

function StopSession()
{
	if ( Phase == SP_Running || Phase == SP_Countdown )
	{
		Phase = SP_Idle;
		PhaseTime = 0;
		Status("Session stopped");
	}
}

function EndSession()
{
	Phase = SP_Results;
	PhaseTime = 0;
	ResultRank = AddScore();
	bNewBest = (ResultRank == 1);
	if ( bNewBest )
		Trainee.ClientPlaySound(Sound(DynamicLoadObject("Announcer.cd1min", class'Sound', true)), , true);
}

// ============================================================================
// Targets
// ============================================================================

function KeepTargets()
{
	local int i;

	for ( i = 0; i < 4; i++ )
	{
		if ( Targets[i] != None && Targets[i].bDeleteMe )
			Targets[i] = None;
		// A target that fell out of the level may not get ticked any more, so the
		// game replaces it (and anything else that stays dead too long).
		if ( Targets[i] != None && (Targets[i].bReplaceMe
			|| (Targets[i].bDead && Level.TimeSeconds - Targets[i].DeadSince > 2.0)) )
		{
			Targets[i].Destroy();
			Targets[i] = None;
		}
		if ( i < NumTargets && Targets[i] == None )
			Targets[i] = SpawnTarget(i);
		else if ( i >= NumTargets && Targets[i] != None )
		{
			Targets[i].Destroy();
			Targets[i] = None;
		}
	}
}

function RemoveTargets()
{
	local int i;
	for ( i = 0; i < 4; i++ )
		if ( Targets[i] != None )
		{
			Targets[i].Destroy();
			Targets[i] = None;
		}
}

function ATTarget SpawnTarget( int Slot )
{
	local vector Spot;
	local ATTarget T;
	local int m;
	local class<TournamentPlayer> MC;

	if ( !FindTargetSpot(Spot) )
		return None;
	T = Spawn(class'ATTarget', , , Spot, rotator(Trainee.Location - Spot));
	if ( T == None )
		return None;
	if ( TargetClass != "" )
		MC = class<TournamentPlayer>(DynamicLoadObject(TargetClass, class'Class', true));
	if ( MC != None && MC.default.Mesh != None )
	{
		if ( TargetSkin != "" )
			T.Setup(self, Trainee, MC, TargetSkin, TargetFace, TargetTeam);
		else
			T.Setup(self, Trainee, MC, MC.default.DefaultSkinName, TargetFace, TargetTeam);
	}
	else
	{
		m = Rand(4);
		T.Setup(self, Trainee, ModelClasses[m], ModelSkins[m], ModelFaces[m], TargetTeam);
	}
	PlayTeleportEffect(T, false, false);
	return T;
}

// A spot on the floor at the range's distance, roughly where the trainee looks,
// The direction targets keep to, if any: the firing direction in Fixed
// position, down the range on DM-AimRange in free roam. Origin is where
// the sector starts (the firing spot, or the trainee).
function bool DownrangeAxis( out vector Origin, out int Yaw )
{
	if ( Stance == 1 && bFixedSet )
	{
		Origin = FixedSpot;
		Yaw = FixedYaw;
		return true;
	}
	if ( bRangeMap && Trainee != None )
	{
		Origin = Trainee.Location;
		Yaw = 0;
		return true;
	}
	return false;
}

// with a clear line of sight. Falls back to navigation points.
function bool FindTargetSpot( out vector Spot )
{
	local int Try;
	local rotator R;
	local vector Eye, Dir, HitLoc, HitNorm, Cand, Floor;
	local float Dist, MinD, MaxD;
	local Actor HitActor;
	local NavigationPoint N, Best;
	local float BestScore, Score;
	local vector AxisOrigin;
	local int AxisYaw;
	local bool bAxis;

	bAxis = DownrangeAxis(AxisOrigin, AxisYaw);
	MinD = RangeMin[Range];
	MaxD = RangeMax[Range];
	Eye = Trainee.Location + Trainee.EyeHeight * vect(0,0,1);
	if ( bAxis && ActiveCourse() != 0 && FindCourseSpot(Spot, Eye, AxisOrigin, AxisYaw) )
		return true;

	for ( Try = 0; Try < 40; Try++ )
	{
		if ( bAxis )
			R.Yaw = AxisYaw + (FRand() - 0.5) * (6000 + Try * 200);
		else
			R.Yaw = Trainee.ViewRotation.Yaw + (FRand() - 0.5) * (8000 + Try * 900);
		R.Pitch = 0;
		Dir = vector(R);
		Dist = MinD + FRand() * (MaxD - MinD);
		HitActor = Trace(HitLoc, HitNorm, Eye + Dir * Dist, Eye, false);
		if ( HitActor != None )
		{
			Dist = VSize(HitLoc - Eye) - 60;
			if ( Dist < MinD * 0.7 )
				continue;
		}
		Cand = Eye + Dir * Dist;
		// down to the floor
		HitActor = Trace(HitLoc, HitNorm, Cand - vect(0,0,600), Cand, false);
		if ( HitActor == None || HitNorm.Z < 0.7 )
			continue;
		Floor = HitLoc + vect(0,0,40);
		if ( !FastTrace(Floor + vect(0,0,30), Eye) )
			continue;
		if ( TooCloseToTargets(Floor) )
			continue;
		Spot = Floor;
		return true;
	}

	// Fallback: best navigation point by distance and visibility.
	BestScore = -1000000;
	for ( N = Level.NavigationPointList; N != None; N = N.nextNavigationPoint )
	{
		if ( N.IsA('LiftCenter') || N.IsA('Teleporter') || N.Region.Zone.bPainZone )
			continue;
		Dist = VSize(N.Location - Trainee.Location);
		Score = -Abs(Dist - 0.5 * (MinD + MaxD)) + 200 * FRand();
		if ( FastTrace(N.Location, Eye) )
			Score += 3000;
		if ( TooCloseToTargets(N.Location) )
			Score -= 5000;
		if ( Score > BestScore )
		{
			BestScore = Score;
			Best = N;
		}
	}
	if ( Best == None )
		return false;
	Spot = Best.Location;
	return true;
}

function bool TooCloseToTargets( vector V )
{
	local int i;
	for ( i = 0; i < 4; i++ )
		if ( Targets[i] != None && !Targets[i].bHidden && VSize(Targets[i].Location - V) < 250 )
			return true;
	return VSize(V - Trainee.Location) < 250;
}

// Called by targets when the trainee damages them.
function TargetHit( ATTarget T, int Dmg, bool bHead, bool bKilled, float LifeTime )
{
	if ( Phase != SP_Running )
		return;
	// several damage events in one frame (flak shards, splash) are one hit
	if ( HitTick != Level.TimeSeconds )
	{
		Hits++;
		HitTick = Level.TimeSeconds;
		if ( bHead )
			Headshots++;
	}
	Damage += Dmg;
	if ( bKilled )
	{
		Kills++;
		TTKSum += LifeTime;
		TTKCount++;
	}
}

// UT's own headshot announcement (voice and "Head Shot!!" on screen). The
// weapons that can decapitate send damage type 'decapitated', as in UT.
function AnnounceHeadshot()
{
	if ( bTestMode )
		Log("ATTEST headshot announced=" $ bHeadshotAnnouncer, 'ATTest');
	if ( bHeadshotAnnouncer && Trainee != None )
		Trainee.ReceiveLocalizedMessage(class'DecapitationMessage');
}

function bool AnyTargetUp()
{
	local int i;

	for ( i = 0; i < 4; i++ )
		if ( Targets[i] != None && !Targets[i].bDead && !Targets[i].bHidden )
			return true;
	return false;
}

// The trainee killed a target. Kills less than StreakWindow apart make a
// streak; from the 2nd kill on, each one plays a higher, brighter chime
// (the 5th and later all play the top one). The first kill plays nothing, so
// with targets always on the range the chime stays a reward, not a constant.
function KillStreak()
{
	if ( Streak > 0 && StreakTime <= StreakWindow )
		Streak++;
	else
		Streak = 1;
	StreakTime = 0;
	if ( bTestMode )
		Log("ATTEST streak=" $ Streak, 'ATTest');
	if ( Streak >= 2 && bStreakSound && Trainee != None )
	{
		Trainee.ClientPlaySound(StreakSounds[Min(Streak - 2, 3)], , true);
		StreakSoundAt = Level.TimeSeconds;
	}
}

function PlayHitSound()
{
	// the streak chime replaces the hit sound on that kill
	if ( StreakSoundAt == Level.TimeSeconds )
		return;
	if ( bHitSound && HitSnd != None && Trainee != None )
		Trainee.ClientPlaySound(HitSnd, , true);
}

// ============================================================================
// Highscores
// ============================================================================

function string WeaponShortName( optional string W )
{
	local int i;
	if ( W == "" )
		W = TrainWeapon;
	i = InStr(W, ".");
	while ( i >= 0 )
	{
		W = Mid(W, i + 1);
		i = InStr(W, ".");
	}
	return W;
}

function string ScoreKey()
{
	return ModeNames[Mode] $ "/" $ WeaponShortName() $ "/" $ RangeNames[Range]
		$ "/" $ Duration $ "s/" $ NumTargets $ "T/" $ MoveNames[EffectiveMoveSource()] $ StanceKey() $ CourseKey();
}

// Flat Range results keep their old key (no suffix).
function string CourseKey()
{
	if ( ActiveCourse() == 1 )
		return "/HighGround";
	if ( ActiveCourse() == 2 )
		return "/Airborne";
	return "";
}

function string CourseText()
{
	if ( ActiveCourse() != 0 )
		return CourseNames[ActiveCourse()] $ " | ";
	return "";
}

function string StanceText()
{
	if ( Stance == 1 )
		return " | fixed position";
	return "";
}

function string StanceKey()
{
	if ( Stance == 1 )
		return "/Fixed";
	return "";
}

function int EffectiveMoveSource()
{
	if ( MoveSource != 1 && Moves.NumClips == 0 )
		return 1;
	return MoveSource;
}

function float Accuracy()
{
	if ( Shots <= 0 )
		return 0;
	return FMin(100.0, 100.0 * Hits / Shots);
}

function string Field( string S, int N )
{
	local int i;
	while ( N > 0 )
	{
		i = InStr(S, ";");
		if ( i < 0 )
			return "";
		S = Mid(S, i + 1);
		N--;
	}
	i = InStr(S, ";");
	if ( i >= 0 )
		S = Left(S, i);
	return S;
}

// Adds the current result; returns its rank in its table (1 = best), 0 if not kept.
function int AddScore()
{
	local string Key, Entry, PName;
	local int i, Count, Rank, Worst, WorstScore, Free, Oldest;

	if ( Shots == 0 && Hits == 0 )
		return 0;
	Key = ScoreKey();
	PName = Trainee.PlayerReplicationInfo.PlayerName;
	PName = ReplaceText(PName, ";", ",");
	Entry = Key $ ";" $ Damage $ ";" $ int(Accuracy() * 10) $ ";" $ Kills $ ";" $ Hits $ ";" $ Shots
		$ ";" $ Level.Year $ "-" $ Pad2(Level.Month) $ "-" $ Pad2(Level.Day) $ ";" $ PName;

	Rank = 1;
	Worst = -1;
	WorstScore = 1000000000;
	Free = -1;
	for ( i = 0; i < ArrayCount(Scores); i++ )
	{
		if ( Scores[i] == "" )
		{
			if ( Free < 0 )
				Free = i;
			continue;
		}
		if ( Field(Scores[i], 0) != Key )
			continue;
		Count++;
		if ( int(Field(Scores[i], 1)) >= Damage )
			Rank++;
		if ( int(Field(Scores[i], 1)) < WorstScore )
		{
			WorstScore = int(Field(Scores[i], 1));
			Worst = i;
		}
	}
	if ( Count >= MaxPerKey )
	{
		if ( Damage <= WorstScore )
			return 0;
		Scores[Worst] = Entry;
	}
	else if ( Free >= 0 )
		Scores[Free] = Entry;
	else
	{
		// table full: replace a random old entry of another key
		Oldest = Rand(ArrayCount(Scores));
		Scores[Oldest] = Entry;
	}
	SaveSettings();
	return Rank;
}

function string FormatAcc( int Tenths )
{
	return (Tenths / 10) $ "." $ (Tenths % 10);
}

function string Pad2( int N )
{
	if ( N < 10 )
		return "0" $ N;
	return string(N);
}

function string ReplaceText( string S, string A, string B )
{
	local int i;
	local string R;
	i = InStr(S, A);
	while ( i >= 0 )
	{
		R = R $ Left(S, i) $ B;
		S = Mid(S, i + Len(A));
		i = InStr(S, A);
	}
	return R $ S;
}

// Top entries for the current settings, best first, into TopScores. Returns the count.
function int GetTopScores( int MaxN )
{
	local int i, j, k, N;
	local string Key;
	local int Idx[10];

	Key = ScoreKey();
	for ( i = 0; i < ArrayCount(Scores); i++ )
	{
		if ( Scores[i] == "" || Field(Scores[i], 0) != Key )
			continue;
		// insertion sort by score
		for ( j = 0; j < N; j++ )
			if ( int(Field(Scores[i], 1)) > int(Field(Scores[Idx[j]], 1)) )
				break;
		if ( j >= MaxN )
			continue;
		for ( k = Min(N, MaxN - 1); k > j; k-- )
			Idx[k] = Idx[k - 1];
		Idx[j] = i;
		N = Min(N + 1, MaxN);
	}
	for ( i = 0; i < N; i++ )
		TopScores[i] = Scores[Idx[i]];
	return N;
}

// ============================================================================
// Commands ("mutate at ...")
// ============================================================================

function Status( string S )
{
	StatusMsg = S;
	StatusTime = Level.TimeSeconds;
	if ( Trainee != None )
		Trainee.ClientMessage("[AimTrainer]" @ S);
}

// Names is a comma separated list of the choices.
function int NextIndex( string Arg, int Cur, int Count, string Names )
{
	local int i;
	local string N;
	if ( Arg == "" || Arg ~= "next" )
		return (Cur + 1) % Count;
	if ( Arg ~= "prev" )
		return (Cur + Count - 1) % Count;
	for ( i = 0; i < Count; i++ )
	{
		N = Field(ReplaceText(Names, ",", ";"), i);
		if ( Arg ~= N || Arg ~= Left(N, Len(Arg)) )
			return i;
	}
	return Clamp(int(Arg), 0, Count - 1);
}

function Command( string Cmd, PlayerPawn Sender )
{
	local string Verb, Arg;
	local int i;
	local bool bChanged;

	Cmd = Trim(Cmd);
	i = InStr(Cmd, " ");
	if ( i >= 0 )
	{
		Verb = Left(Cmd, i);
		Arg = Trim(Mid(Cmd, i + 1));
	}
	else
		Verb = Cmd;

	if ( Verb ~= "start" )
	{
		if ( Phase != SP_Countdown && Phase != SP_Running )
			StartCountdown();
		return;
	}
	if ( Verb ~= "stop" )
	{
		StopSession();
		return;
	}
	if ( Verb ~= "menu" )
	{
		OpenMenu(Sender);
		return;
	}
	if ( Verb ~= "help" || Verb == "" )
	{
		Sender.ClientMessage("AimTrainer commands (type in console or bind to keys):");
		Sender.ClientMessage("  mutate at menu   (settings window)");
		Sender.ClientMessage("  mutate at start | stop");
		Sender.ClientMessage("  mutate at mode [duel|tracking]       mutate at weapon [next|prev|<class>]");
		Sender.ClientMessage("  mutate at course [flat|highground|airborne] (DM-AimRange)  mutate at range [close|mid|far]");
		Sender.ClientMessage("  mutate at time <seconds>  mutate at targets <1-4>  mutate at moves [recorded|synthetic|mixed]");
		Sender.ClientMessage("  mutate at model [random|<class>]  mutate at team [red|blue|none]  mutate at hitsound  mutate at headshot  mutate at streak");
		Sender.ClientMessage("  mutate at scores | resetscores");
		return;
	}
	if ( Verb ~= "scores" )
	{
		PrintScores(Sender);
		return;
	}
	if ( Verb ~= "resetscores" )
	{
		for ( i = 0; i < ArrayCount(Scores); i++ )
			if ( Scores[i] != "" && Field(Scores[i], 0) == ScoreKey() )
				Scores[i] = "";
		SaveSettings();
		Status("Highscores cleared for" @ ScoreKey());
		return;
	}

	// Settings: not while a session runs.
	if ( Phase == SP_Running || Phase == SP_Countdown )
		StopSession();

	if ( Verb ~= "mode" )
	{
		Mode = NextIndex(Arg, Mode, 2, ModeNames[0] $ "," $ ModeNames[1]);
		bChanged = true;
	}
	else if ( Verb ~= "course" )
	{
		Course = NextIndex(Arg, Course, 3, "flat,highground,airborne");
		RemoveTargets();
		bChanged = true;
	}
	else if ( Verb ~= "range" || Verb ~= "dist" )
	{
		Range = NextIndex(Arg, Range, 3, RangeNames[0] $ "," $ RangeNames[1] $ "," $ RangeNames[2]);
		bChanged = true;
	}
	else if ( Verb ~= "moves" )
	{
		MoveSource = NextIndex(Arg, MoveSource, 3, MoveNames[0] $ "," $ MoveNames[1] $ "," $ MoveNames[2]);
		if ( MoveSource != 1 && Moves.NumClips == 0 )
			Status("No recorded clips installed (AimTrainerMoves.ini): using synthetic movement");
		bChanged = true;
	}
	else if ( Verb ~= "time" )
	{
		if ( Arg == "" )
			Duration = (Duration % 120) + 30;
		else
			Duration = int(Arg);
		bChanged = true;
	}
	else if ( Verb ~= "targets" )
	{
		if ( Arg == "" )
			NumTargets = (NumTargets % 4) + 1;
		else
			NumTargets = int(Arg);
		bChanged = true;
	}
	else if ( Verb ~= "model" )
	{
		TargetSkin = "";
		TargetFace = "";
		if ( Arg ~= "random" )
			TargetClass = "";
		else if ( Arg != "" && Arg != "next" )
			TargetClass = Arg;
		else
		{
			// cycle: random -> the four stock models -> random
			for ( i = 0; i < 4; i++ )
				if ( string(ModelClasses[i]) ~= TargetClass )
					break;
			if ( TargetClass == "" )
				TargetClass = string(ModelClasses[0]);
			else if ( i < 3 )
				TargetClass = string(ModelClasses[i + 1]);
			else
				TargetClass = "";
		}
		RemoveTargets();
		bChanged = true;
	}
	else if ( Verb ~= "team" )
	{
		if ( Arg ~= "red" ) TargetTeam = 0;
		else if ( Arg ~= "blue" ) TargetTeam = 1;
		else if ( Arg ~= "none" ) TargetTeam = 255;
		else if ( TargetTeam == 0 ) TargetTeam = 1;
		else if ( TargetTeam == 1 ) TargetTeam = 255;
		else TargetTeam = 0;
		RemoveTargets();
		bChanged = true;
	}
	else if ( Verb ~= "hitsound" )
	{
		bHitSound = !bHitSound;
		bChanged = true;
	}
	else if ( Verb ~= "headshot" )
	{
		bHeadshotAnnouncer = !bHeadshotAnnouncer;
		bChanged = true;
	}
	else if ( Verb ~= "streak" )
	{
		bStreakSound = !bStreakSound;
		bChanged = true;
	}
	else if ( Verb ~= "weapon" )
	{
		TrainWeapon = PickWeapon(Arg);
		GiveTrainWeapon(Trainee);
		bChanged = true;
	}
	else
	{
		Sender.ClientMessage("[AimTrainer] Unknown command '" $ Verb $ "'. Try: mutate at help");
		return;
	}

	if ( bChanged )
	{
		ClampSettings();
		SaveSettings();
		Phase = SP_Idle;
		PhaseTime = 0;
		Status(SettingsLine());
	}
}

// Settings window: shows the window (class ATMenuWindow) on the trainee's screen.
function OpenMenu( PlayerPawn P )
{
	local WindowConsole C;

	if ( P == None || P.Player == None )
		return;
	C = WindowConsole(P.Player.Console);
	if ( C == None )
		return;
	InstallEscHook();
	// The same way Esc opens UT's menu (game paused, mouse on); the Esc hook
	// then shows the Aim Trainer window in it.
	if ( !C.bUWindowActive )
	{
		C.bQuickKeyEnable = false;
		C.LaunchUWindow();
	}
}

function UWindowWindow CreateMenuWindow( UWindowRootWindow Root )
{
	if ( bTestMode )
		Log("ATTEST menu window created", 'ATTest');
	return Root.CreateWindow(class'ATMenuWindow', Max(0, (Root.WinWidth - 420) / 2),
		Max(0, (Root.WinHeight - 538) / 2), 420, 538, None, true);
}

// Esc opens the Aim Trainer window instead of UT's menu (see ATEscHook).
function InstallEscHook()
{
	local WindowConsole C;
	local UWindowWindow W;

	if ( Trainee == None || Trainee.Player == None )
		return;
	C = WindowConsole(Trainee.Player.Console);
	if ( C == None )
		return;
	if ( !C.bCreatedRoot || C.Root == None )
		C.CreateRootWindow(None);
	if ( C.Root == None )
		return;
	for ( W = C.Root.FirstChildWindow; W != None; W = W.NextSiblingWindow )
		if ( ATEscHook(W) != None )
			return;
	C.Root.CreateWindow(class'ATEscHook', 0, 0, 0, 0);
}

// The settings window changed something.
function MenuChanged( bool bWeaponChanged, bool bLooksChanged )
{
	if ( Phase == SP_Running || Phase == SP_Countdown )
		StopSession();
	ClampSettings();
	SaveSettings();
	if ( bWeaponChanged && Trainee != None )
		GiveTrainWeapon(Trainee);
	if ( bLooksChanged )
	{
		RemoveTargets();
		bFixedSet = false;
	}
	Phase = SP_Idle;
	PhaseTime = 0;
}

function string ModelName()
{
	local class<TournamentPlayer> MC;
	if ( TargetClass == "" )
		return "random model";
	MC = class<TournamentPlayer>(DynamicLoadObject(TargetClass, class'Class', true));
	if ( MC == None )
		return TargetClass;
	if ( MC.default.MenuName != "" )
		return MC.default.MenuName;
	return string(MC.Name);
}

function string PickWeapon( string Arg )
{
	local int i, Cur, N;

	for ( N = 0; N < ArrayCount(WeaponList) && WeaponList[N] != ""; N++ );
	Cur = -1;
	for ( i = 0; i < N; i++ )
		if ( WeaponList[i] ~= TrainWeapon )
			Cur = i;
	if ( Arg == "" || Arg ~= "next" )
		return WeaponList[(Cur + 1) % N];
	if ( Arg ~= "prev" )
		return WeaponList[(Cur + N - 1 + int(Cur < 0)) % N];
	if ( InStr(Arg, ".") >= 0 )
		return Arg;
	for ( i = 0; i < N; i++ )
		if ( InStr(Caps(WeaponList[i]), Caps(Arg)) >= 0 )
			return WeaponList[i];
	return "Botpack." $ Arg;
}

function string SettingsLine()
{
	return CourseText() $ ModeNames[Mode] @ "|" @ WeaponShortName() @ "|" @ RangeNames[Range]
		@ "|" @ Duration $ "s |" @ NumTargets @ "target(s) |" @ MoveNames[EffectiveMoveSource()] @ "moves" $ StanceText();
}

function PrintScores( PlayerPawn P )
{
	local int i, N;

	N = GetTopScores(10);
	P.ClientMessage("[AimTrainer] Best for" @ ScoreKey() $ ":");
	if ( N == 0 )
		P.ClientMessage("  none yet");
	for ( i = 0; i < N; i++ )
		P.ClientMessage("  " $ (i + 1) $ ". " $ Field(TopScores[i], 1) $ " pts  " $ FormatAcc(int(Field(TopScores[i], 2))) $ "% acc  "
			$ Field(TopScores[i], 3) $ " kills  " $ Field(TopScores[i], 6) @ Field(TopScores[i], 7));
}

function string Trim( string S )
{
	while ( Left(S, 1) == " " )
		S = Mid(S, 1);
	while ( Right(S, 1) == " " )
		S = Left(S, Len(S) - 1);
	return S;
}

defaultproperties
{
	Mode=0
	Stance=1
	TrainWeapon="Botpack.SuperShockRifle"
	Range=1
	Course=0
	MaxKickSpeed=1400
	Duration=60
	NumTargets=1
	MoveSource=0
	TargetClass=""
	TargetSkin=""
	TargetFace=""
	TargetTeam=0
	TargetHealth=100
	bHitSound=True
	bHeadshotAnnouncer=True
	bStreakSound=True
	StreakWindow=1.5
	StreakSounds(0)=Sound'Streak1'
	StreakSounds(1)=Sound'Streak2'
	StreakSounds(2)=Sound'Streak3'
	StreakSounds(3)=Sound'Streak4'
	HitSoundName="UnrealShare.Eightball.SeekLock"
	RespawnDelay=0.4
	CrouchFrequency=1.0
	MaxStrafeTime=1.5
	BurstChance=0.2
	CircleStrafeChance=0.15
	bMenuAtStart=True
	MaxPerKey=10

	ModeNames(0)="Duel"
	ModeNames(1)="Tracking"
	CourseNames(0)="Flat Range"
	CourseNames(1)="High Ground"
	CourseNames(2)="Airborne"
	RangeNames(0)="Close"
	RangeNames(1)="Mid"
	RangeNames(2)="Far"
	MoveNames(0)="Recorded"
	MoveNames(1)="Synthetic"
	MoveNames(2)="Mixed"
	RangeMin(0)=350
	RangeMax(0)=750
	RangeMin(1)=800
	RangeMax(1)=1500
	RangeMin(2)=1600
	RangeMax(2)=2800

	WeaponList(0)="Botpack.SuperShockRifle"
	WeaponList(1)="Botpack.ShockRifle"
	WeaponList(2)="Botpack.Enforcer"
	WeaponList(3)="Botpack.SniperRifle"
	WeaponList(4)="Botpack.minigun2"
	WeaponList(5)="Botpack.PulseGun"
	WeaponList(6)="Botpack.UT_FlakCannon"
	WeaponList(7)="Botpack.UT_Eightball"
	WeaponList(8)="Botpack.ripper"
	WeaponList(9)="Botpack.UT_BioRifle"
	WeaponNames(0)="Enhanced Shock Rifle (InstaGib)"
	WeaponNames(1)="Shock Rifle"
	WeaponNames(2)="Enforcer"
	WeaponNames(3)="Sniper Rifle"
	WeaponNames(4)="Minigun"
	WeaponNames(5)="Pulse Gun"
	WeaponNames(6)="Flak Cannon"
	WeaponNames(7)="Rocket Launcher"
	WeaponNames(8)="Ripper"
	WeaponNames(9)="Bio Rifle"

	ModelClasses(0)=Class'Botpack.TMale1'
	ModelClasses(1)=Class'Botpack.TMale2'
	ModelClasses(2)=Class'Botpack.TFemale1'
	ModelClasses(3)=Class'Botpack.TFemale2'
	ModelClasses(4)=Class'Botpack.TBoss'
	ModelSkins(0)="CommandoSkins.cmdo"
	ModelSkins(1)="SoldierSkins.blkt"
	ModelSkins(2)="FCommandoSkins.cmdo"
	ModelSkins(3)="SGirlSkins.army"
	ModelSkins(4)="BossSkins.boss"
	ModelFaces(0)="CommandoSkins.Blake"
	ModelFaces(1)=""
	ModelFaces(2)="FCommandoSkins.Gromida"
	ModelFaces(3)=""
	ModelFaces(4)=""

	HUDType=Class'AimTrainer.ATHUD'
	GameName="Aim Trainer"
	MapPrefix="DM"
	BeaconName="AIM"
	bUseTranslocator=False
	bNoMonsters=False
	MinPlayers=0
	InitialBots=0
}
