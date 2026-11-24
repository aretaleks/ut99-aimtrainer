//=============================================================================
// ATRecConsole - records how real players move while a demo plays back.
//
// Used only by the recording run (AimTrainer\Tools\record_demos.py), which
// starts the game with its own ini where Console=ATRecorder.ATRecConsole.
// It plays each demo in DemoList through udemo, sets udemo's playback speed,
// samples every visible player each SampleInterval of demo time and writes
// the samples to the log as "ATRec:" lines. The Python tools turn them into
// movement clips for the aim trainer targets.
//=============================================================================
class ATRecConsole extends UTConsole config(AimTrainerRec);

var config string DemoList[512];   // demo names, as typed after "demoplay"
var config int    DemoIndex;       // next entry of DemoList to play
var config bool   bAutoPlay;       // play the list one after another
var config bool   bQuitWhenDone;   // exit the game after the last demo
var config float  SampleInterval;  // seconds of demo time between samples
var config float  MaxDistance;     // ignore players further than this from the viewer
var config float  PlaySpeed;       // udemo playback speed to start with
var config float  MaxSpeed;        // upper limit for the adaptive speed
var config float  MaxStep;         // most demo seconds one drawn frame may cover

var float  RealTime;        // real seconds since the last state change
var float  LastSampleTime;  // demo time of the last sample
var float  LastDemoTime;    // demo time seen last tick
var float  StallTime;       // real seconds the demo time did not move
var bool   bInDemo;
var bool   bRequested;      // a demoplay command was issued and not yet started
var string CurDemo;
var LevelInfo CurLevel;
var bool   bSpeedSet;
var float  CurSpeed;
var float  StepSum, StepReal;
var int    StepCount;

function bool IsEntry(LevelInfo L)
{
	return L == None || InStr(Caps(string(L)), "ENTRY.") == 0;
}

function StartNextDemo()
{
	while ( DemoIndex < ArrayCount(DemoList) && DemoList[DemoIndex] == "" )
		DemoIndex++;
	if ( DemoIndex >= ArrayCount(DemoList) )
	{
		Log("ALLDONE", 'ATRec');
		bAutoPlay = false;
		if ( bQuitWhenDone )
			Viewport.Actor.ConsoleCommand("exit");
		return;
	}
	CurDemo = DemoList[DemoIndex];
	DemoIndex++;
	bRequested = true;
	RealTime = 0;
	Log("REQ"@CurDemo, 'ATRec');
	Viewport.Actor.ConsoleCommand("demoplay \""$CurDemo$"\"");
}

function ATRecTick(float Delta)
{
	local LevelInfo L;
	local DemoPlaybackSpec Spec;
	local float DemoTime;

	if ( Viewport == None || Viewport.Actor == None )
		return;
	L = Viewport.Actor.Level;
	RealTime += Delta;

	if ( IsEntry(L) || L.NetMode != NM_Client )
	{
		if ( bInDemo )
			EndDemo("level");
		// Wait a moment in the menu level, then start the next demo. A demo
		// that never loads (missing map) is skipped after a timeout.
		if ( bAutoPlay && ((!bRequested && RealTime > 1.0) || (bRequested && RealTime > 20.0)) )
		{
			if ( bRequested )
				Log("FAILED"@CurDemo, 'ATRec');
			StartNextDemo();
		}
		return;
	}

	// In a client level: a playing demo.
	Spec = DemoPlaybackSpec(Viewport.Actor);
	if ( Spec == None || Spec.Driver == None )
		return;
	if ( !bInDemo || L != CurLevel )
	{
		bInDemo = true;
		bRequested = false;
		CurLevel = L;
		LastSampleTime = -1000;
		LastDemoTime = -1;
		StallTime = 0;
		bSpeedSet = false;
		StepSum = 0;
		StepCount = 0;
		StepReal = 0;
		Log("BEGIN"@CurDemo@L.Title@string(L)@Spec.Driver.GetTotalTime(), 'ATRec');
	}
	// udemo starts console-launched demos frame based (one recorded frame per
	// drawn frame), which ignores the speed. Switch to time based, then keep
	// the speed as high as possible while one drawn frame covers at most
	// MaxStep of demo time, so samples stay close enough for dodges.
	if ( !bSpeedSet )
	{
		bSpeedSet = true;
		Spec.Driver.SetPlayBackMode(0);
		CurSpeed = FMax(1.0, PlaySpeed);
		Spec.Driver.SetSpeed(CurSpeed);
		Log("SPEED mode=" $ Spec.Driver.PlayBackMode @ "speed=" $ Spec.Driver.mySpeed, 'ATRec');
	}
	DemoTime = Spec.Driver.GetCurrentTime();
	if ( DemoTime <= LastDemoTime )
	{
		StallTime += Delta;
		if ( StallTime > 4.0 )
		{
			EndDemo("stall");
			if ( bAutoPlay )
				Viewport.Actor.ConsoleCommand("disconnect");
		}
		return;
	}
	StallTime = 0;
	if ( LastDemoTime >= 0 )
		AdaptSpeed(Spec, Delta, DemoTime - LastDemoTime);
	LastDemoTime = DemoTime;

	if ( DemoTime - LastSampleTime >= SampleInterval )
	{
		LastSampleTime = DemoTime;
		Sample(Spec, DemoTime);
	}
}

function AdaptSpeed(DemoPlaybackSpec Spec, float RealDelta, float DemoStep)
{
	StepSum += DemoStep;
	StepCount++;
	StepReal += RealDelta;
	if ( StepReal < 1.0 )
		return;
	// demo seconds per drawn frame, averaged over a second
	if ( StepSum / StepCount > MaxStep * 1.15 && CurSpeed > 1 )
		CurSpeed = FMax(1.0, CurSpeed * 0.8);
	else if ( StepSum / StepCount < MaxStep * 0.8 && CurSpeed < MaxSpeed )
		CurSpeed = FMin(MaxSpeed, CurSpeed * 1.2);
	if ( CurSpeed != Spec.Driver.mySpeed )
		Spec.Driver.SetSpeed(CurSpeed);
	StepSum = 0;
	StepCount = 0;
	StepReal = 0;
}

function EndDemo(string Why)
{
	Log("END"@Why, 'ATRec');
	bInDemo = false;
	CurLevel = None;
	RealTime = 0;
}

function Sample(DemoPlaybackSpec Spec, float DemoTime)
{
	local Pawn P, V;
	local Actor VT;
	local vector Eye;
	local int Team, ID, LOS;

	V = Viewport.Actor;
	VT = Viewport.Actor.ViewTarget;
	if ( Pawn(VT) != None )
		V = Pawn(VT);
	Eye = V.Location + V.EyeHeight * vect(0,0,1);

	Team = 255;
	ID = -1;
	if ( V.PlayerReplicationInfo != None )
	{
		Team = V.PlayerReplicationInfo.Team;
		ID = V.PlayerReplicationInfo.PlayerID;
	}
	Log("F" @ DemoTime @ ID @ Team @ int(V.Location.X) @ int(V.Location.Y) @ int(V.Location.Z)
		@ int(V.Velocity.X) @ int(V.Velocity.Y) @ int(V.Velocity.Z) @ (V.ViewRotation.Yaw & 65535) @ int(V.Physics) @ V.Level.TimeDilation @ Spec.Driver.mySpeed, 'ATRec');

	foreach Viewport.Actor.AllActors(class'Pawn', P)
	{
		if ( P == V || P == Viewport.Actor || P.PlayerReplicationInfo == None || P.bHidden
			|| P.Mesh == None || P.IsA('Spectator') || P.PlayerReplicationInfo.bIsSpectator )
			continue;
		if ( VSize(P.Location - V.Location) > MaxDistance )
			continue;
		LOS = 0;
		if ( Viewport.Actor.FastTrace(P.Location, Eye) )
			LOS = 1;
		Log("P" @ P.PlayerReplicationInfo.PlayerID @ P.PlayerReplicationInfo.Team
			@ int(P.Location.X) @ int(P.Location.Y) @ int(P.Location.Z)
			@ int(P.Velocity.X) @ int(P.Velocity.Y) @ int(P.Velocity.Z)
			@ int(P.Physics) @ (P.Rotation.Yaw & 65535) @ LOS
			@ P.AnimSequence, 'ATRec');
	}
}

event Tick( float Delta )
{
	Super.Tick(Delta);
	ATRecTick(Delta);
}

state UWindow
{
	event Tick( float Delta )
	{
		Super.Tick(Delta);
		ATRecTick(Delta);
	}
}

defaultproperties
{
	SampleInterval=0.025
	MaxDistance=6000
	PlaySpeed=10
	MaxSpeed=60
	MaxStep=0.03
	bQuitWhenDone=true
}
