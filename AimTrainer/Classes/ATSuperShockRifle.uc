//=============================================================================
// ATSuperShockRifle - the InstaGib rifle, telling the trainer about each shot.
// (It never uses ammo, so shots can't be counted from ammo like other weapons.)
//
// If this UT has InstaGibPlus settings (System\InstaGibPlus.ini), the beam and
// the impact look as the player set them up in IG+; otherwise they are stock.
//=============================================================================
class ATSuperShockRifle extends SuperShockRifle;

var ATIGPlusSettings IGPlus;   // None: no IG+ settings here, stock effects

function PostBeginPlay()
{
	Super.PostBeginPlay();
	// No outer: the object's name alone is the ini section, [ClientSettings].
	IGPlus = new(None, 'ClientSettings') class'ATIGPlusSettings';
	if ( !IGPlus.bInitialized )
	{
		IGPlus = None;
		log("AimTrainer: no InstaGibPlus settings, stock beam");
	}
	else
		log("AimTrainer: InstaGibPlus beam settings: beam"@IGPlus.cShockBeam@"scale"@IGPlus.BeamScale
			@"duration"@IGPlus.BeamDuration@"curve"@IGPlus.BeamFadeCurve@"impact"@IGPlus.SSRRingType);
}

function TraceFire( float Accuracy )
{
	if ( ATGame(Level.Game) != None )
		ATGame(Level.Game).ShotFired(self);
	Super.TraceFire(Accuracy);
}

function ProcessTraceHit( Actor Other, vector HitLocation, vector HitNormal, vector X, vector Y, vector Z )
{
	if ( IGPlus == None )
	{
		Super.ProcessTraceHit(Other, HitLocation, HitNormal, X, Y, Z);
		return;
	}
	// as SuperShockRifle, with the IG+ beam and impact
	if ( Other == None )
	{
		HitNormal = -X;
		HitLocation = Owner.Location + X * 10000.0;
	}
	DrawBeam(Owner.Location + CalcDrawOffset() + (FireOffset.X + 20) * X + FireOffset.Y * Y + FireOffset.Z * Z,
		HitLocation);
	DrawImpact(HitLocation, HitNormal);
	if ( (Other != self) && (Other != Owner) && (Other != None) )
		Other.TakeDamage(HitDamage, Pawn(Owner), HitLocation, 60000.0 * X, MyDamageType);
}

// The beam's team colour: the trainee is on the other team from the targets
// (red targets: a blue beam), as in a CTF match. No target team: no colour.
function int BeamTeam()
{
	if ( ATGame(Level.Game) != None )
	{
		if ( ATGame(Level.Game).TargetTeam == 0 )
			return 1;
		if ( ATGame(Level.Game).TargetTeam == 1 )
			return 0;
	}
	return 255;
}

function DrawBeam( vector Start, vector End )
{
	local vector D, Step;
	local rotator R;
	local int N, i, Team;
	local ATBeam B;
	local SuperShockBeam S;

	D = End - Start;
	N = VSize(D) / 135.0;
	if ( N < 1 )
		return;
	if ( IGPlus.cShockBeam == 3 )
		return;
	if ( IGPlus.bHideOwnBeam && PlayerPawn(Owner) != None && !PlayerPawn(Owner).bBehindView )
		return;
	R = rotator(D);
	R.Roll = Rand(65535);
	Step = D / N;
	Team = BeamTeam();

	if ( IGPlus.cShockBeam == 2 )
	{
		B = Spawn(class'ATBeam', Owner,, Start, R);
		if ( B != None )
			B.Setup(Team, IGPlus.BeamScale, IGPlus.BeamFadeCurve, IGPlus.BeamDuration,
				Step, N - 1, IGPlus.bBeamEnableLight);
	}
	else if ( IGPlus.cShockBeam == 4 )
	{
		for ( i = 0; i < N; i++ )
		{
			B = Spawn(class'ATBeam', Owner,, Start + i * Step, R);
			if ( B != None )
				B.Setup(Team, IGPlus.BeamScale, IGPlus.BeamFadeCurve, IGPlus.BeamDuration,
					Step, 0, IGPlus.bBeamEnableLight);
		}
	}
	else
	{
		S = Spawn(class'SuperShockBeam',,, Start, R);
		if ( S != None )
		{
			S.MoveAmount = Step;
			S.NumPuffs = N - 1;
		}
	}
}

function DrawImpact( vector HitLocation, vector HitNormal )
{
	local Actor A;

	if ( IGPlus.SSRRingType == 0 )
	{
		A = Spawn(class'EnergyImpact',,, HitLocation, rotator(HitNormal));
		if ( A != None )
			A.PlaySound(Sound'UnrealShare.General.Explo1',, 12.0,, 2200);
	}
	else if ( IGPlus.SSRRingType == 2 && BeamTeam() == 1 )
	{
		Spawn(class'UT_RingExplosion',,, HitLocation + HitNormal * 8, rotator(HitNormal));
		Spawn(class'EnergyImpact',,, HitLocation, rotator(HitNormal));
	}
	else
		Spawn(class'ut_SuperRing2',,, HitLocation + HitNormal * 8, rotator(HitNormal));
}
