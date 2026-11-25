//=============================================================================
// ATTarget - a player model that moves like a real player.
//
// Movement is described in the trainee's frame: F = towards the trainee,
// R = to the trainee's side. Each tick the target asks its movement source
// for a velocity in that frame (and whether to jump or dodge now), turns it
// into world space and drives UT's own walking/falling physics with it, so
// walls, ledges, gravity and dodge physics behave as for a player.
//
// Sources:
//  - Recorded: clips of real players from demos (ATMoves), sampled at
//    ATMoves.SampleRate, with their jumps and dodges.
//  - Synthetic: ADAD strafes, circle strafes, stops, dodges (incl. double
//    dodges), jumps and the odd split-second crouch followed by a dodge, with
//    human timing ranges (used when no clips are installed, or if chosen).
//=============================================================================
class ATTarget extends Pawn;

var ATGame Game;

var class<TournamentPlayer> ModelClass;
var sound  Footstep1, Footstep2, Footstep3, LandGrunt, JumpSnd;

// state
var bool   bDead;
var float  DeadTime;
var float  FreezeTime;
var float  LifeStart;
var vector Anchor;
var float  LastPainTime;

// movement in the trainee frame
var float  WantF, WantR;    // desired velocity (uu/s) towards / beside the trainee
var bool   bWantLaunch;     // jump or dodge this tick
var bool   bLaunchDodge;
var float  LaunchZ;
var bool   bDodging;        // in the air from a dodge (landing cuts velocity like UT)
var bool   bMirror;         // mirror the lateral movement
var float  FlipCooldown;
var float  BlockedTime;

// recorded clip
var bool   bUseClip;
var int    ClipLen;
var float  ClipT;
var int    LastLaunchIdx;
var float  ClipF[400], ClipR[400], ClipZ[400];
var byte   ClipS[400];      // 0 walk, 1 air, 2 jump start, 3 dodge start, 4 crouch
var float  SegmentLeft;     // Mixed: seconds left of a synthetic segment

// synthetic
var int    SynMode;         // 0 ADAD, 1 circle strafe, 2 stop-and-go
var float  SynModeLeft;
var float  SynDirLeft;
var float  SynDir;
var float  SynF;
var float  DodgeCooldown;
var float  DodgeLockUntil;  // UT: no new dodge until 0.35 s after landing from one
var bool   bPendingDodge;   // a clip dodge waiting for the lock to end
var float  PendingDodgeZ, PendingDodgeUntil;
var float  NoSightTime;
var float  JumpKeep;         // share of recorded jumps that are kept
var float  ApproachSide;     // which diagonal an approach uses (+1/-1)
var float  ApproachSwitch;   // seconds until it may switch
var int    LastCat;          // pattern of the current clip (see ATMoves)
var int    CircleKey;        // circle strafe: which keys are held (0 W, 1 W+side, 2 side, ... 8 steps of 45 degrees)
var float  CircleStep, CircleStepLeft;
var int    FaceOffset;       // yaw added to 'look at the trainee' (see FaceEnemy); always 0: targets aim at the trainee
var float  SlowTime;         // how long it has been (nearly) standing still
var float  AnimMismatch;     // how long the running animation has been for the other direction   // how long each key is held, and what's left of it
var float  SideSign, SideRun, SideLimit;   // the side it is strafing to, for how long, and the limit
var bool   bReplaceMe;
var float  DeadSince;
var int    RespawnFails;
var float  KeyLead;          // recorded clips: how far ahead the 'keys' read the clip
var bool   bEndCircleDodge;
var bool   bChainDodge;     // dodge back right after landing (double dodge)
var float  AimTime;
var float  ReactCooldown;
var bool   bCrouch;         // ducked this tick (walks at walking speed, can't dodge)
var float  CrouchLeft;      // synthetic crouch: seconds left
var bool   bDodgeAfterCrouch;

// timing tables for synthetic movement (index 1 is used; the others are kept for tuning)
var float  ADADMin[4], ADADMax[4];
var float  DodgeRate[4], JumpRate[4], CircleChance[4], StopChance[4];
var float  ReactChance[4], ReactDelay[4], ChainChance[4], LateralScale[4];
var float  CrouchRate[4], CrouchDodgeChance[4];

// ============================================================================
// Setup
// ============================================================================

function Setup( ATGame G, Pawn E, class<TournamentPlayer> MC, string SkinName, string FaceName, int Team )
{
	local class<Weapon> WC;
	local Weapon W;

	Game = G;
	Enemy = E;
	ModelClass = MC;

	Mesh = MC.default.Mesh;
	DrawScale = MC.default.DrawScale;
	SetCollisionSize(MC.default.CollisionRadius, MC.default.CollisionHeight);
	HitSound1 = MC.default.HitSound1;
	HitSound2 = MC.default.HitSound2;
	Die = MC.default.Die;
	Land = MC.default.Land;
	LandGrunt = MC.default.LandGrunt;
	JumpSnd = MC.default.JumpSound;
	Footstep1 = MC.default.Footstep1;
	Footstep2 = MC.default.Footstep2;
	Footstep3 = MC.default.Footstep3;
	// Some models' skin code (TBoss) writes to the scoreboard entry: give it a
	// temporary one so it doesn't log errors.
	if ( PlayerReplicationInfo == None )
	{
		PlayerReplicationInfo = Spawn(class'PlayerReplicationInfo', self);
		MC.static.SetMultiSkin(self, SkinName, FaceName, Team);
		if ( PlayerReplicationInfo != None )
			PlayerReplicationInfo.Destroy();
		PlayerReplicationInfo = None;
	}
	else
		MC.static.SetMultiSkin(self, SkinName, FaceName, Team);

	// The trainer weapon in the target's hands (visual only).
	WC = class<Weapon>(DynamicLoadObject(Game.TrainWeapon, class'Class', true));
	if ( WC != None )
	{
		W = Spawn(WC, self);
		if ( W != None )
		{
			W.RespawnTime = 0;
			W.Instigator = self;
			W.BecomeItem();
			W.bHeldItem = true;
			AddInventory(W);
			Weapon = W;
			W.GotoState('');
		}
	}

	Anchor = Location;
	SynDir = 1;
	if ( FRand() < 0.5 )
		SynDir = -1;
	bMirror = FRand() < 0.5;
	ResetLife();
	NewSegment();
	SetPhysics(PHYS_Falling);
	PlayIdle();
}

function ResetLife()
{
	Health = Game.TargetHealth;
	LifeStart = Level.TimeSeconds;
}

function Freeze( float T )
{
	FreezeTime = T;
}

// ============================================================================
// Main loop
// ============================================================================

function Tick( float Delta )
{
	local vector F, R, World, Away, Axis, Side, ToSpot, AxisOrigin;
	local int AxisYaw;
	local float ApF, ApR, MinSide;
	local float Dist, Speed, MinKeep, MaxKeep;

	if ( Game == None || Enemy == None || Enemy.bDeleteMe )
		return;

	if ( bReplaceMe )
	{
		Destroy();
		return;
	}
	if ( bDead )
	{
		DeadTime -= Delta;
		if ( DeadTime <= 0 )
			Respawn();
		return;
	}

	FaceEnemy(Delta);
	FlipCooldown -= Delta;
	ApproachSwitch -= Delta;
	DodgeCooldown -= Delta;
	ReactCooldown -= Delta;

	F = Enemy.Location - Location;
	F.Z = 0;
	Dist = VSize(F);
	F = Normal(F);
	R = F cross vect(0,0,1);

	bWantLaunch = false;
	if ( FreezeTime > 0 )
	{
		FreezeTime -= Delta;
		WantF = 0;
		WantR = 0;
	}
	else
	{
		CheckAim(Delta, Dist);
		if ( bUseClip )
			RecordedMove(Delta);
		else
			SyntheticMove(Delta);
	}

	if ( bMirror )
		World = WantF * F - WantR * R;
	else
		World = WantF * F + WantR * R;

	// keep within the range band of the trainee
	MinKeep = Game.RangeMin[Game.Range] * 0.6;
	MaxKeep = Game.RangeMax[Game.Range] * 1.25;
	if ( (Dist < MinKeep && (World dot F) > 0) || (Dist > MaxKeep && (World dot F) < 0) )
	{
		World -= 2 * (World dot F) * F;
		WantF = -WantF;
	}
	// Stay in the area it spawned in, loosely: circle strafes go around the
	// trainee (who has to turn to follow), so only a long drift turns it back.
	// A synthetic circle strafe carries its anchor along.
	if ( !bUseClip && SynMode == 1 )
		Anchor = Location;
	Away = Location - Anchor;
	Away.Z = 0;
	if ( VSize(Away) > 1600 && (World dot Away) > 0 && FlipCooldown <= 0 )
	{
		bMirror = !bMirror;
		FlipCooldown = 0.8;
		SynDir = -SynDir;
		World -= 2 * (World dot (R * (Normal(Away) dot R))) * (R * (Normal(Away) dot R));
	}
	if ( VSize(Away) > 2500 )
		Anchor = Location;
	// Fixed position (or anywhere on DM-AimRange): stay downrange, within +-45
	// degrees of the firing direction.
	if ( Game.DownrangeAxis(AxisOrigin, AxisYaw) )
	{
		Axis = vector(rot(0,1,0) * AxisYaw);
		Side = Axis cross vect(0,0,1);
		ToSpot = Location - AxisOrigin;
		ToSpot.Z = 0;
		// a soft wall at the sector's edge: outward movement is turned back every
		// frame (strafing alone can't fix a diagonal retreat)
		if ( Abs(ToSpot dot Side) > FMax(ToSpot dot Axis, 300) && (World dot Side) * (ToSpot dot Side) > 0 )
		{
			if ( FlipCooldown <= 0 )
			{
				bMirror = !bMirror;
				SynDir = -SynDir;
				FlipCooldown = 0.6;
			}
			World -= 2 * (World dot Side) * Side;
		}
		// and never come up level with the firing spot
		if ( (ToSpot dot Axis) < 400 && (World dot Axis) < 0 )
			World -= 2 * (World dot Axis) * Axis;
	}
	// Out of the trainee's sight for a while: come back the other way.
	if ( FastTrace(Enemy.Location, Location) )
		NoSightTime = 0;
	else
	{
		NoSightTime += Delta;
		if ( NoSightTime > 1.5 && FlipCooldown <= 0 )
		{
			bMirror = !bMirror;
			SynDir = -SynDir;
			FlipCooldown = 1.0;
			NoSightTime = 0;
			World -= 2 * (World dot R) * R;
		}
	}

	// Never run straight at the trainee: coming closer happens on a diagonal
	// (at least 45 degrees), strafing and dodging, switching sides now and then.
	// Dodges may be steeper: a forward dodge while holding A or D keeps the
	// sideways speed and goes off at about 30 degrees (at least 27 here).
	ApF = World dot F;
	ApR = World dot R;
	MinSide = 1.0;
	if ( bWantLaunch && bLaunchDodge )
		MinSide = 0.5;
	if ( ApF > 50 && Abs(ApR) < MinSide * ApF && (bUseClip || SynMode != 1) )
	{
		if ( Abs(ApR) > 60 )
			ApproachSide = 1;
		if ( ApR < -60 )
			ApproachSide = -1;
		else if ( Abs(ApR) <= 60 && ApproachSwitch <= 0 )
		{
			if ( FRand() < 0.5 )
				ApproachSide = -ApproachSide;
			ApproachSwitch = 0.6 + FRand() * 1.2;
		}
		Speed = VSize(World * vect(1,1,0));
		ApR = ApproachSide * ApF * MinSide;
		World = Normal(ApF * F + ApR * R) * Speed + World.Z * vect(0,0,1);
	}

	// Don't strafe too wide: after holding one side for a while (0.9 s up to
	// Game.MaxStrafeTime, different each time) switch to the other, like A -> D.
	ApR = World dot R;
	if ( Abs(ApR) > 150 && (bUseClip || SynMode != 1) )
	{
		if ( ApR * SideSign > 0 )
			SideRun += Delta;
		else
		{
			SideSign = 1;
			if ( ApR < 0 )
				SideSign = -1;
			SideRun = 0;
			SideLimit = NewSideLimit();
		}
		if ( SideRun > SideLimit && Physics == PHYS_Walking )
		{
			bMirror = !bMirror;
			SynDir = -SynDir;
			ApproachSide = -ApproachSide;
			World -= 2 * ApR * R;
			SideSign = -SideSign;
			SideRun = 0;
			SideLimit = NewSideLimit();
		}
	}

	Speed = VSize(World);
	// The engine caps an AI pawn's walking speed at GroundSpeed * DesiredSpeed
	// (normally set by MoveTo); 0 would freeze it in place.
	// Crouched: UT's walking speed (30 %).
	if ( bCrouch )
		DesiredSpeed = 0.3;
	else
		DesiredSpeed = 1.0;
	MaxDesiredSpeed = 1.0;
	if ( Physics == PHYS_Walking )
	{
		// Walking into a wall: turn around (like a player would).
		if ( Speed > 200 && (Velocity dot Normal(World * vect(1,1,0))) < 0.3 * FMin(Speed, GroundSpeed) )
		{
			// a direction change takes UT's physics ~0.3 s; longer than that, it's a wall
			BlockedTime += Delta;
			if ( BlockedTime > 0.45 && FlipCooldown <= 0 )
			{
				bMirror = !bMirror;
				SynDir = -SynDir;
				FlipCooldown = 0.5;
				BlockedTime = 0;
				if ( bUseClip && FRand() < 0.5 )
					NewSegment();
			}
		}
		else
			BlockedTime = 0;

		if ( bWantLaunch && bLaunchDodge && Level.TimeSeconds < DodgeLockUntil )
		{
			// too soon after the last dodge (UT's 0.35 s): a clip dodge waits for
			// the lock to end, a made-up one is dropped
			bWantLaunch = false;
			if ( bUseClip )
			{
				bPendingDodge = true;
				PendingDodgeZ = LaunchZ;
				PendingDodgeUntil = DodgeLockUntil + 0.15;
			}
		}
		else if ( !bWantLaunch && bPendingDodge && Level.TimeSeconds >= DodgeLockUntil )
		{
			bPendingDodge = false;
			if ( Level.TimeSeconds < PendingDodgeUntil && bUseClip )
			{
				bWantLaunch = true;
				bLaunchDodge = true;
				LaunchZ = PendingDodgeZ;
			}
		}
		if ( bWantLaunch )
		{
			bCrouch = false;
			bPendingDodge = false;
			Launch(World);
		}
		else
		{
			// "Press the keys": only the direction is set, as a player's input
			// would. UT's walking physics then gives the same acceleration,
			// braking, direction changes and top speed as for a player.
			if ( Speed > 120 )
				Acceleration = Normal(World * vect(1,1,0)) * AccelRate;
			else
				Acceleration = vect(0,0,0);
		}
	}
	else if ( Physics == PHYS_Falling )
	{
		// in the air, the same keys; the engine applies UT's air control
		if ( Speed > 120 )
			Acceleration = Normal(World * vect(1,1,0)) * AccelRate;
		else
			Acceleration = vect(0,0,0);
	}
	UpdateAnim(Delta);
}

// How long the next strafe to one side may last.
function vector ToEnemy()
{
	return Normal((Enemy.Location - Location) * vect(1,1,0));
}

function vector RightOfEnemy()
{
	return ToEnemy() cross vect(0,0,1);
}

function float NewSideLimit()
{
	local float MaxT;

	MaxT = FMax(Game.MaxStrafeTime, 0.6);
	return FMin(0.9, MaxT * 0.6) + FRand() * (MaxT - FMin(0.9, MaxT * 0.6));
}

function FaceEnemy( float Delta )
{
	local rotator Want, Cur;
	local int D;

	// FaceOffset: 0 looks at the trainee, 32768 looks away (the way the trainee
	// looks), +-16384 looks to one side (circle strafes)
	Want = rotator(Enemy.Location - Location);
	Want.Yaw += FaceOffset;
	Cur = Rotation;
	D = ((Want.Yaw - Cur.Yaw + 98304) & 65535) - 32768;
	Cur.Yaw += Clamp(D, -100000 * Delta, 100000 * Delta);
	Cur.Pitch = 0;
	Cur.Roll = 0;
	SetRotation(Cur);
	DesiredRotation = Cur;
}

// Is the trainee's crosshair on us? Players react to that on Hard and Pro.
function CheckAim( float Delta, float Dist )
{
	local vector ToMe;
	local float Off;

	if ( PlayerPawn(Enemy) == None )
		return;
	ToMe = Location - (Enemy.Location + Enemy.EyeHeight * vect(0,0,1));
	Off = VSize(Normal(ToMe) - vector(PlayerPawn(Enemy).ViewRotation)) * VSize(ToMe);
	if ( Off < CollisionRadius * 1.6 )
		AimTime += Delta;
	else
		AimTime = 0;
}

function bool ShouldReact()
{
	// Reacting to the crosshair made targets move in ways no player does: off.
	return false;
}

// ============================================================================
// Movement sources
// ============================================================================

function NewSegment()
{
	local int Src;
	local float R;

	bCrouch = false;
	CrouchLeft = 0;
	FaceOffset = 0;
	Src = Game.EffectiveMoveSource();
	if ( Src == 2 )
	{
		if ( FRand() < 0.5 )
			Src = 0;
		else
			Src = 1;
	}
	bUseClip = false;
	// Recorded clips are short CTF moments: long quick-ADAD runs and circle
	// strafes are rare in them, so they are played as patterns in between.
	if ( Src == 0 )
	{
		R = FRand();
		if ( R < Game.BurstChance )
		{
			StartPattern(3);
			SegmentLeft = SynModeLeft;
			return;
		}
		if ( R < Game.BurstChance + Game.CircleStrafeChance )
		{
			StartPattern(1);
			SegmentLeft = SynModeLeft;
			return;
		}
		if ( LoadClip() )
		{
			bUseClip = true;
			return;
		}
	}
	SegmentLeft = 2.5 + FRand() * 3;
	SynModeLeft = 0;
}

// Synthetic movement patterns: 0 ADAD, 1 circle strafe, 2 stop-and-go,
// 3 quick ADAD burst.
function StartPattern( int M )
{
	SynMode = M;
	SynDirLeft = 0;
	// targets always aim at the trainee
	FaceOffset = 0;
	if ( M == 1 )
	{
		// circle strafe: a small loop on the spot (around its own axis, still
		// facing the trainee) by pressing the keys in turn, A-W-D-S or D-W-A-S
		CircleStep = 0.06 + FRand() * 0.03;   // 8 short presses per loop: a tight, round loop
		CircleStepLeft = CircleStep;
		if ( FRand() < 0.5 )
			SynDir = -SynDir;
		// start with the keys closest to where it is already running
		CircleKey = 2;
		if ( (Velocity dot RightOfEnemy()) < 0 )
			CircleKey = 6;
		if ( Abs(Velocity dot ToEnemy()) > Abs(Velocity dot RightOfEnemy()) )
		{
			CircleKey = 0;
			if ( (Velocity dot ToEnemy()) < 0 )
				CircleKey = 4;
		}
		// two to five loops
		SynModeLeft = (16 + Rand(25)) * CircleStep;
	}
	else if ( M == 2 )
		SynModeLeft = 0.8 + FRand() * 1.2;
	else if ( M == 3 )
		SynModeLeft = 2.0 + FRand() * 1.5;
	else
		SynModeLeft = 2.0 + FRand() * 2.5;
}

function bool LoadClip()
{
	local int Idx, i, N;
	local string S;
	local ATMoves M;

	M = Game.Moves;
	N = M.NumClips;
	if ( N == 0 )
		return false;
	// a random clip, of another pattern than the last one (long strafe, ADAD,
	// mixed, dodge-heavy), so the target keeps changing how it moves
	Idx = M.PickClip(LastCat, LastCat);
	S = M.Clip[Idx];
	ClipLen = Min(Len(S) / 4, ArrayCount(ClipF));
	if ( ClipLen < 4 )
		return false;
	for ( i = 0; i < ClipLen; i++ )
	{
		ClipS[i] = Max(0, InStr("wajdc", Mid(S, i * 4, 1)));
		ClipF[i] = M.Val(Mid(S, i * 4 + 1, 1));
		ClipR[i] = M.Val(Mid(S, i * 4 + 2, 1));
		ClipZ[i] = M.Val(Mid(S, i * 4 + 3, 1));
	}
	ClipT = 0;
	LastLaunchIdx = -1;
	bMirror = FRand() < 0.5;
	return true;
}

function RecordedMove( float Delta )
{
	local int i, j;
	local float A, B, Rate;

	Rate = Game.Moves.SampleRate;
	ClipT += Delta;
	i = int(ClipT * Rate);
	if ( i >= ClipLen - 1 )
	{
		NewSegment();
		if ( !bUseClip )
		{
			SyntheticMove(Delta);
			return;
		}
		i = 0;
	}
	A = ClipT * Rate - i;
	bCrouch = ClipS[i] == 4;
	// A player presses a key before the velocity follows: steer by the clip a
	// moment ahead (the physics then lags it by about as much).
	j = Min(int((ClipT + KeyLead) * Rate), ClipLen - 2);
	B = (ClipT + KeyLead) * Rate - j;
	WantF = ClipF[j] + (ClipF[j + 1] - ClipF[j]) * FClamp(B, 0, 1);
	WantR = ClipR[j] + (ClipR[j + 1] - ClipR[j]) * FClamp(B, 0, 1);
	if ( ClipS[i] >= 2 && LastLaunchIdx < i )
	{
		LastLaunchIdx = i;
		// jumps: only a few are kept, the rest carry on running
		if ( ClipS[i] == 3 || FRand() < JumpKeep )
		{
			bWantLaunch = true;
			bLaunchDodge = ClipS[i] == 3;
			LaunchZ = ClipZ[i];
			WantF = ClipF[i];
			WantR = ClipR[i];
		}
	}
}

function SyntheticMove( float Delta )
{
	local int D;
	local float Lat, Len2;

	D = 1;
	if ( Game.EffectiveMoveSource() != 1 )
	{
		SegmentLeft -= Delta;
		if ( SegmentLeft <= 0 )
		{
			NewSegment();
			if ( bUseClip )
				return;
		}
	}

	// split-second crouch, then (usually) dodge away and start a new pattern
	if ( CrouchLeft > 0 )
	{
		CrouchLeft -= Delta;
		bCrouch = true;
		WantF = SynF * 0.3;
		WantR = SynDir * GroundSpeed * 0.3;
		if ( CrouchLeft <= 0 )
		{
			bCrouch = false;
			SynModeLeft = 0;
			if ( bDodgeAfterCrouch && Physics == PHYS_Walking )
			{
				if ( FRand() < 0.5 )
					SynDir = -SynDir;
				SyntheticDodge();
			}
		}
		return;
	}
	bCrouch = false;
	if ( Physics == PHYS_Walking && DodgeCooldown <= 0 && SynMode != 1 && SynMode != 3
		&& FRand() < CrouchRate[D] * Game.CrouchFrequency * Delta )
	{
		CrouchLeft = 0.15 + FRand() * 0.35;
		bDodgeAfterCrouch = FRand() < CrouchDodgeChance[D];
		WantF = SynF * 0.3;
		WantR = SynDir * GroundSpeed * 0.3;
		bCrouch = true;
		return;
	}

	SynModeLeft -= Delta;
	if ( SynModeLeft <= 0 )
	{
		// a circle strafe or a quick-ADAD burst often ends with a dodge out
		if ( (SynMode == 1 && FRand() < 0.35) || (SynMode == 3 && FRand() < 0.4) )
			bEndCircleDodge = true;
		Len2 = FRand();
		if ( Len2 < CircleChance[D] )
			StartPattern(1);
		else if ( Len2 < CircleChance[D] + 0.25 )
			StartPattern(3);
		else if ( FRand() < StopChance[D] )
			StartPattern(2);
		else
			StartPattern(0);
	}

	SynDirLeft -= Delta;
	if ( SynDirLeft <= 0 )
	{
		if ( SynMode == 1 )
			SynDirLeft = 1000;   // the loop is steered below
		else if ( SynMode == 3 )
		{
			// quick ADAD: short taps, a little drift
			SynDir = -SynDir;
			// time per side as in real ADAD (median 0.3 s): a few very quick taps,
			// mostly 0.2-0.45 s, and some longer holds that get back to full speed
			Len2 = FRand();
			if ( Len2 < 0.2 )
				SynDirLeft = 0.12 + FRand() * 0.08;
			else if ( Len2 < 0.75 )
				SynDirLeft = 0.2 + FRand() * 0.25;
			else
				SynDirLeft = 0.45 + FRand() * 0.25;
			SynF = (FRand() - 0.5) * 120;
		}
		else
		{
			SynDir = -SynDir;
			SynDirLeft = ADADMin[D] + FRand() * (ADADMax[D] - ADADMin[D]);
			if ( FRand() < 0.35 )
				SynF = (FRand() - 0.5) * 2 * GroundSpeed * 0.6;
			else
				SynF = 0;
		}
	}

	Lat = SynDir * GroundSpeed * LateralScale[D];
	if ( SynMode == 2 && SynDirLeft < 0.25 )
		Lat = 0;    // brief stop before going again
	WantF = SynF;
	WantR = Lat;
	if ( SynMode == 1 )
	{
		// next key in the loop when this one has been held long enough
		CircleStepLeft -= Delta;
		if ( CircleStepLeft <= 0 )
		{
			CircleStepLeft += CircleStep;
			CircleKey = (CircleKey + 8 + int(SynDir)) % 8;
		}
		WantF = cos(CircleKey * Pi / 4) * GroundSpeed;
		WantR = sin(CircleKey * Pi / 4) * GroundSpeed;
	}
	Len2 = Sqrt(WantF * WantF + WantR * WantR);
	if ( Len2 > GroundSpeed )
	{
		WantF *= GroundSpeed / Len2;
		WantR *= GroundSpeed / Len2;
	}

	if ( Physics != PHYS_Walking )
		return;
	if ( bEndCircleDodge && DodgeCooldown <= 0 )
	{
		bEndCircleDodge = false;
		SynDir = -SynDir;
		SyntheticDodge();
		return;
	}
	if ( bChainDodge && DodgeCooldown <= 0 )
	{
		bChainDodge = false;
		SynDir = -SynDir;
		SyntheticDodge();
		return;
	}
	if ( SynMode != 3 && DodgeCooldown <= 0 && FRand() < DodgeRate[D] * Delta * (1.0 - 0.6 * int(SynMode == 1)) )
		SyntheticDodge();
	else if ( DodgeCooldown <= 0 && FRand() < JumpRate[D] * Delta )
	{
		bWantLaunch = true;
		bLaunchDodge = false;
		LaunchZ = JumpZ;
	}
}

// UT dodge: 1.5 x GroundSpeed sideways (or back / forward), 160 up.
function SyntheticDodge()
{
	local float Pick;

	Pick = FRand();
	if ( Pick < 0.5 )
	{
		WantR = SynDir * 1.5 * GroundSpeed;
		WantF = 0;
	}
	else if ( Pick < 0.75 )
	{
		// holding A or D and double-tapping W: forward dodge that keeps the strafe
		WantR = SynDir * GroundSpeed * 0.9;
		WantF = 1.5 * GroundSpeed;
	}
	else if ( Pick < 0.9 )
	{
		WantR = 0;
		WantF = -1.5 * GroundSpeed;
	}
	else
	{
		WantR = SynDir * 1.06 * GroundSpeed;
		WantF = -1.06 * GroundSpeed;
	}
	if ( bMirror )
		WantR = -WantR;    // the mirror is applied again later
	bWantLaunch = true;
	bLaunchDodge = true;
	LaunchZ = 160;
	if ( SynMode != 1 && FRand() < ChainChance[1] )
		bChainDodge = true;
}

function Launch( vector World )
{
	local vector X, Y, Z, Dir;
	local float S;

	// a UT dodge is 1.5 x GroundSpeed plus what's kept of the sideways speed
	World.Z = 0;
	if ( VSize(World) > 1.8 * GroundSpeed )
		World = Normal(World) * 1.8 * GroundSpeed;
	if ( !bLaunchDodge )
	{
		// a jump keeps the running velocity
		World = Velocity;
		World.Z = 0;
	}
	Velocity.X = World.X;
	Velocity.Y = World.Y;
	Velocity.Z = FMax(LaunchZ, 100);
	SetPhysics(PHYS_Falling);
	bDodging = bLaunchDodge;
	if ( Game.bTestMode )
		Log("ATLAUNCH" @ Name @ Level.TimeSeconds @ int(bLaunchDodge) @ int(bUseClip)
			@ int((World dot Normal((Enemy.Location - Location) * vect(1,1,0))) > 0.35 * VSize(World)), 'ATTest');
	if ( JumpSnd != None )
		PlaySound(JumpSnd, SLOT_Talk, 1.0, true, 800, 1.0);

	GetAxes(Rotation, X, Y, Z);
	Dir = Normal(World * vect(1,1,0));
	if ( bLaunchDodge )
	{
		S = Dir dot Y;
		if ( S > 0.7 )
			TweenAnim('DodgeR', 0.1);
		else if ( S < -0.7 )
			TweenAnim('DodgeL', 0.1);
		else if ( (Dir dot X) < 0 )
			TweenAnim('DodgeB', 0.1);
		else
			PlayAnim('Flip', 1.35, 0.06);
	}
	else
	{
		if ( Weapon == None || Weapon.Mass < 20 )
			TweenAnim('JumpSMFR', 0.1);
		else
			TweenAnim('JumpLGFR', 0.1);
	}
}

event Landed( vector HitNormal )
{
	if ( Game != None && Game.bTestMode )
		Log("ATLAND" @ Name @ Level.TimeSeconds @ int(bDodging), 'ATTest');
	if ( bDodging )
	{
		// UT: landing from a dodge kills most of the speed
		Velocity.X *= 0.1;
		Velocity.Y *= 0.1;
		bDodging = false;
		DodgeLockUntil = Level.TimeSeconds + 0.35;
		DodgeCooldown = 0.45 + FRand() * 0.6;
		if ( bChainDodge )
			DodgeCooldown = 0.36 + FRand() * 0.1;    // double dodge: as soon as UT allows
	}
	else
		DodgeCooldown = FMax(DodgeCooldown, 0.2);
	SetPhysics(PHYS_Walking);
	if ( Velocity.Z < -500 && LandGrunt != None )
		PlaySound(LandGrunt, SLOT_Talk, 1.5, true, 1200, FRand() * 0.4 + 0.8);
	if ( Land != None )
		PlaySound(Land, SLOT_Interact, 0.8, false, 1000, 1.0);
	if ( Weapon == None || Weapon.Mass < 20 )
		TweenAnim('LandSMFR', 0.12);
	else
		TweenAnim('LandLGFR', 0.12);
}

// ============================================================================
// Animation and sounds
// ============================================================================

function UpdateAnim( float Delta )
{
	local name Want;
	local float Spd;

	if ( Physics != PHYS_Walking )
		return;
	Spd = VSize(Velocity * vect(1,1,0));
	if ( bCrouch )
	{
		if ( Weapon == None || Weapon.Mass < 20 )
			Want = 'DuckWlkS';
		else
			Want = 'DuckWlkL';
		if ( Spd > 30 )
		{
			if ( AnimSequence != Want || !bAnimLoop )
				LoopAnim(Want, FClamp(Spd / (0.3 * GroundSpeed), 0.5, 1.5), 0.1);
		}
		else if ( AnimSequence != Want || bAnimLoop )
			TweenAnim(Want, 0.12);
		return;
	}
	if ( IsAnimating() && (GetAnimGroup(AnimSequence) == 'Landing' || AnimSequence == 'Flip') && !bAnimLoop )
		return;
	// Standing still for a moment (not just the instant of an A <-> D switch).
	if ( Spd < 60 )
		SlowTime += Delta;
	else
		SlowTime = 0;
	if ( Spd < 60 && SlowTime > 0.25 )
	{
		PlayIdle();
		return;
	}
	// Like UT for players: a running animation is only chosen again when its
	// cycle ends (AnimEnd), so the body sometimes switches sides on an A <-> D
	// tap, but not on every one.
	// A quick tap doesn't flip it; going the new way for 0.2 s does.
	if ( bAnimLoop && IsRunAnim(AnimSequence) )
	{
		if ( Spd >= 60 && RunAnimFor(Spd) != AnimSequence )
		{
			AnimMismatch += Delta;
			if ( AnimMismatch > 0.2 )
			{
				AnimMismatch = 0;
				PlayRunAnim(Spd);
			}
		}
		else
			AnimMismatch = 0;
		return;
	}
	if ( Spd < 60 )
		return;
	PlayRunAnim(Spd);
}

function bool IsRunAnim( name A )
{
	return A == 'StrafeL' || A == 'StrafeR' || A == 'BackRun' || A == 'RunSMFR' || A == 'RunLGFR';
}

// End of an animation cycle: choose the running animation for the next one.
event AnimEnd()
{
	local float Spd;

	if ( Physics != PHYS_Walking || bCrouch || bDead )
		return;
	Spd = VSize(Velocity * vect(1,1,0));
	if ( Spd < 60 )
	{
		if ( SlowTime > 0.25 || !IsRunAnim(AnimSequence) )
			PlayIdle();
		return;
	}
	PlayRunAnim(Spd);
}

function PlayRunAnim( float Spd )
{
	AnimMismatch = 0;
	// a fixed rate, as for UT's players (a rate taken from the speed of the
	// moment makes a whole cycle look slow after an A <-> D switch)
	LoopAnim(RunAnimFor(Spd), 1.0, 0.1);
}

// The running animation for the current direction (as TournamentPlayer.PlayRunning).
function name RunAnimFor( float Spd )
{
	local vector X, Y, Z, Dir;
	local name Want;

	GetAxes(Rotation, X, Y, Z);
	Dir = Normal(Velocity * vect(1,1,0));
	if ( (Dir dot X) < -0.75 )
		Want = 'BackRun';
	else if ( (Dir dot X) < 0.75 )
	{
		if ( (Dir dot Y) > 0 )
			Want = 'StrafeR';
		else
			Want = 'StrafeL';
	}
	else if ( Weapon == None || Weapon.Mass < 20 )
		Want = 'RunSMFR';
	else
		Want = 'RunLGFR';
	return Want;
}

function PlayIdle()
{
	local name Want;

	if ( Weapon == None || Weapon.Mass < 20 )
		Want = 'Breath1';
	else
		Want = 'Breath1L';
	if ( AnimSequence != Want )
		LoopAnim(Want, 0.4 + 0.4 * FRand(), 0.2);
}

// Called by the player meshes' animation notifies.
simulated function PlayFootStep()
{
	local sound Step;
	local float R;

	R = FRand();
	if ( R < 0.34 )
		Step = Footstep1;
	else if ( R < 0.67 )
		Step = Footstep2;
	else
		Step = Footstep3;
	if ( Step != None )
		PlaySound(Step, SLOT_Interact, 2.2, false, 1000.0, 1.0);
}

// ============================================================================
// Damage, death, respawn
// ============================================================================

function TakeDamage( int Dmg, Pawn InstigatedBy, vector HitLocation, vector Momentum, name DamageType )
{
	local int Actual, Effective;
	local bool bHead, bKilled;
	local vector BloodOffset;

	if ( bDead || bHidden || Game == None )
		return;

	Actual = Game.ReduceDamage(Dmg, DamageType, self, InstigatedBy);
	if ( Actual <= 0 )
		return;
	bHead = DamageType == 'decapitated' || (HitLocation.Z - Location.Z > 0.62 * CollisionHeight);

	BloodOffset = 0.2 * CollisionRadius * Normal(HitLocation - Location);
	BloodOffset.Z *= 0.5;
	if ( DamageType == 'shot' || DamageType == 'decapitated' || DamageType == 'shredded' )
		Spawn(class'UT_BloodHit', self, , HitLocation + BloodOffset, rotator(Momentum));
	else
		Spawn(class'UT_BloodBurst', self, , HitLocation + BloodOffset);

	if ( Game.Mode == 0 )
	{
		Effective = Min(Actual, Health);
		Health -= Actual;
		bKilled = Health <= 0;
	}
	else
		Effective = Min(Actual, 100);

	if ( InstigatedBy != None && InstigatedBy == Game.Trainee )
	{
		Game.TargetHit(self, Effective, bHead, bKilled, Level.TimeSeconds - LifeStart);
		Game.PlayHitSound();
	}

	if ( bKilled )
		DieNow(DamageType);
	else if ( Level.TimeSeconds - LastPainTime > 0.4 )
	{
		LastPainTime = Level.TimeSeconds;
		if ( FRand() < 0.5 && HitSound1 != None )
			PlaySound(HitSound1, SLOT_Pain, 2.0, true, 1000, 0.9 + FRand() * 0.2);
		else if ( HitSound2 != None )
			PlaySound(HitSound2, SLOT_Pain, 2.0, true, 1000, 0.9 + FRand() * 0.2);
	}
}

function DieNow( name DamageType )
{
	local Carcass C;
	local float R;

	if ( Die != None )
		PlaySound(Die, SLOT_Talk, 3.0, true, 1500, 1.0);
	R = FRand();
	if ( R < 0.25 )
		PlayAnim('Dead2', , 0.1);
	else if ( R < 0.5 )
		PlayAnim('Dead3', , 0.1);
	else if ( R < 0.75 )
		PlayAnim('Dead7', , 0.1);
	else
		PlayAnim('Dead9', , 0.1);

	if ( ModelClass != None && ModelClass.default.CarcassType != None )
	{
		C = Spawn(ModelClass.default.CarcassType, , , Location, Rotation);
		if ( C != None )
		{
			C.Initfor(self);
			C.SetCollision(false, false, false);
			C.LifeSpan = 2.5;
		}
	}

	bDead = true;
	DeadSince = Level.TimeSeconds;
	DeadTime = Game.RespawnDelay;
	bHidden = true;
	SetCollision(false, false, false);
	SetPhysics(PHYS_None);
	Velocity = vect(0,0,0);
	Acceleration = vect(0,0,0);
}

function Respawn()
{
	local vector Spot;

	if ( Game.FindTargetSpot(Spot) )
	{
		SetCollision(true, true, true);
		if ( SetLocation(Spot) )
		{
			RespawnFails = 0;
			bDead = false;
			bHidden = false;
			Anchor = Spot;
			SetRotation(rotator(Enemy.Location - Spot));
			SetPhysics(PHYS_Falling);
			ResetLife();
			NewSegment();
			Game.PlayTeleportEffect(self, false, false);
			PlayIdle();
			return;
		}
		SetCollision(false, false, false);
	}
	// can't be moved back in (seen after falling into a pit): the game spawns
	// a fresh target instead
	if ( ++RespawnFails >= 5 )
		Destroy();
}

event FellOutOfWorld()
{
	Relocate();
}

event ZoneChange( ZoneInfo NewZone )
{
	if ( NewZone.bPainZone || NewZone.bKillZone )
		Relocate();
}

// Fell into a pit, lava or out of the world: the game replaces it.
function Relocate()
{
	bDead = true;
	DeadSince = Level.TimeSeconds;
	bHidden = true;
	SetCollision(false, false, false);
	SetPhysics(PHYS_None);
	bReplaceMe = true;
}

function Destroyed()
{
	local Inventory Inv, Next;
	for ( Inv = Inventory; Inv != None; Inv = Next )
	{
		Next = Inv.Inventory;
		Inv.Destroy();
	}
	Super.Destroyed();
}

defaultproperties
{
	ADADMin(0)=0.55
	ADADMin(1)=0.32
	ADADMin(2)=0.2
	ADADMin(3)=0.13
	ADADMax(0)=1.2
	ADADMax(1)=0.8
	ADADMax(2)=0.55
	ADADMax(3)=0.42
	DodgeRate(0)=0.08
	DodgeRate(1)=0.25
	DodgeRate(2)=0.45
	DodgeRate(3)=0.7
	JumpRate(0)=0.02
	JumpRate(1)=0.01
	JumpRate(2)=0.12
	JumpRate(3)=0.15
	CircleChance(0)=0.3
	CircleChance(1)=0.2
	CircleChance(2)=0.4
	CircleChance(3)=0.4
	StopChance(0)=0.3
	StopChance(1)=0.2
	StopChance(2)=0.15
	StopChance(3)=0.1
	ReactChance(0)=0
	ReactChance(1)=0
	ReactChance(2)=0.4
	ReactChance(3)=0.8
	ReactDelay(0)=1
	ReactDelay(1)=1
	ReactDelay(2)=0.3
	ReactDelay(3)=0.2
	ChainChance(0)=0
	ChainChance(1)=0.1
	ChainChance(2)=0.25
	ChainChance(3)=0.35
	KeyLead=0.12
	JumpKeep=0.1
	ApproachSide=1
	LastCat=-1
	CrouchRate(0)=0.02
	CrouchRate(1)=0.04
	CrouchRate(2)=0.06
	CrouchRate(3)=0.08
	CrouchDodgeChance(0)=0.4
	CrouchDodgeChance(1)=0.6
	CrouchDodgeChance(2)=0.75
	CrouchDodgeChance(3)=0.85
	LateralScale(0)=0.75
	LateralScale(1)=0.9
	LateralScale(2)=1
	LateralScale(3)=1

	GroundSpeed=400
	AirSpeed=400
	AccelRate=2048
	AirControl=0.35
	JumpZ=325
	BaseEyeHeight=27
	EyeHeight=27
	Health=100
	Mass=100
	Buoyancy=99
	bCanJump=True
	bCanWalk=True
	DesiredSpeed=1.0
	MaxDesiredSpeed=1.0
	bStopAtLedges=True
	bAvoidLedges=True
	bIsPlayer=False
	bProjTarget=True
	bCollideActors=True
	bCollideWorld=True
	bBlockActors=True
	bBlockPlayers=True
	CollisionRadius=17
	CollisionHeight=39
	DrawType=DT_Mesh
	Mesh=LodMesh'Botpack.Commando'
	bRotateToDesired=False
	RotationRate=(Pitch=0,Yaw=100000,Roll=0)
	MenuName="Target"
	Visibility=128
	SightRadius=0
	AmbientGlow=17
	LightType=LT_None
}
