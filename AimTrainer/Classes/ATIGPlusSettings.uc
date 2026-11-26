//=============================================================================
// ATIGPlusSettings - reads the InstaGib rifle's beam settings that InstaGibPlus
// (IG+) keeps in System\InstaGibPlus.ini, section [ClientSettings], of the UT
// this runs in. Players who set up their beam in IG+ see the same beam here.
//
// Read only: never call SaveConfig on this, the file belongs to IG+.
// Create it with  new(None, 'ClientSettings') class'ATIGPlusSettings'
// (per-object config: the object's name is the ini section; with an outer
// the section would be the outer's name plus this one, and not found).
//=============================================================================
class ATIGPlusSettings extends Object
	config(InstaGibPlus)
	perobjectconfig;

var config bool  bInitialized;     // IG+ has written its settings (else: no IG+ here)
var config int   cShockBeam;       // 1 default, 2 team colored, 3 hidden, 4 instant
var config bool  bHideOwnBeam;
var config bool  bBeamEnableLight;
var config float BeamScale;
var config float BeamFadeCurve;
var config float BeamDuration;
var config int   SSRRingType;      // 0 small impact, 1 default ring, 2 team colored ring

defaultproperties
{
	cShockBeam=1
	bBeamEnableLight=True
	BeamScale=0.45
	BeamFadeCurve=4
	BeamDuration=0.75
	SSRRingType=1
}
