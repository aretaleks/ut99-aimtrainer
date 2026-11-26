//=============================================================================
// ATBeam - one segment of an InstaGib beam drawn with the player's IG+ beam
// settings (ATIGPlusSettings): size, how long it stays and how it fades, team
// colour and light. A beam is a row of these, 135 uu apart. The next segment
// either appears 0.05 s later (like the stock beam) or all at once (Instant).
//=============================================================================
class ATBeam extends Effects;

var int    Team;        // -1 stock look, 0-3 team colours, other: no colour
var float  Size;
var float  Curve;
var float  Duration;
var float  Age;
var vector Step;        // from this segment to the next
var int    MoreSegments;  // segments still to add after this one, one per 0.05 s
var bool   bLight;

function Setup( int InTeam, float InSize, float InCurve, float InDuration,
	vector InStep, int InMore, bool bInLight )
{
	Team = InTeam;
	Size = InSize;
	Curve = InCurve;
	Duration = InDuration;
	Step = InStep;
	MoreSegments = InMore;
	bLight = bInLight;

	if ( Team >= 0 )
	{
		Mesh = LodMesh'Botpack.Shockbm';
		LightType = LT_None;
		if ( bLight && Level.bHighDetailMode )
			LightType = LT_Steady;
		LightEffect = LE_NonIncidence;
		LightSaturation = 64;
		LightRadius = 6;
		if ( Team == 0 )
		{
			Texture = Texture'Botpack.Translocator.Tranglow';
			LightHue = 0;
		}
		else if ( Team == 1 )
		{
			Texture = Texture'Botpack.Translocator.Tranglowb';
			LightHue = 150;
		}
		else if ( Team == 2 )
		{
			Texture = Texture'Botpack.Translocator.Tranglowg';
			LightHue = 75;
		}
		else if ( Team == 3 )
		{
			Texture = Texture'Botpack.Translocator.Tranglowy';
			LightHue = 40;
		}
	}
	DrawScale = 0.44 * Size;
	Age = 0;
	Fade();
	if ( MoreSegments > 0 )
		SetTimer(0.05, false);
}

function Fade()
{
	local float Left;

	Left = 1.0 - Age / FMax(Duration, 0.01);
	if ( Left <= 0 )
	{
		Destroy();
		return;
	}
	ScaleGlow = Left ** Curve;
	AmbientGlow = ScaleGlow * 210;
	if ( Team >= 0 )
		LightBrightness = ScaleGlow * 128;
}

function Tick( float DeltaTime )
{
	Age += DeltaTime;
	Fade();
}

function Timer()
{
	local ATBeam Next;

	Next = Spawn(class'ATBeam', Owner,, Location + Step, Rotation);
	if ( Next != None )
		Next.Setup(Team, Size, Curve, Duration, Step, MoreSegments - 1, bLight);
}

defaultproperties
{
	Physics=PHYS_Rotating
	RemoteRole=ROLE_None
	LifeSpan=0
	Rotation=(Roll=20000)
	DrawType=DT_Mesh
	Style=STY_Translucent
	Texture=Texture'Botpack.Effects.jenergy3'
	Mesh=LodMesh'Botpack.SShockbm'
	DrawScale=0.44
	bUnlit=True
	bParticles=True
	bFixedRotationDir=True
	RotationRate=(Roll=1000000)
	DesiredRotation=(Roll=20000)
}
