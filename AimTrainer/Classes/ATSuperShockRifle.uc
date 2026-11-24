//=============================================================================
// ATSuperShockRifle - the InstaGib rifle, telling the trainer about each shot.
// (It never uses ammo, so shots can't be counted from ammo like other weapons.)
//=============================================================================
class ATSuperShockRifle extends SuperShockRifle;

function TraceFire( float Accuracy )
{
	if ( ATGame(Level.Game) != None )
		ATGame(Level.Game).ShotFired(self);
	Super.TraceFire(Accuracy);
}
