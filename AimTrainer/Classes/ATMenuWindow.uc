//=============================================================================
// ATMenuWindow - Aim Trainer settings window ("mutate at menu").
//=============================================================================
class ATMenuWindow extends UWindowFramedWindow;

var bool bKeepMenus;   // closing to show UT's menu: don't return to the game

function Close( optional bool bByParent )
{
	Super.Close(bByParent);
	// back to playing (Esc, Resume, Start, ...)
	if ( !bByParent && !bKeepMenus && Root != None && Root.Console != None )
		Root.Console.CloseUWindow();
}

// Shown again (the window is kept between visits): fresh values, normal close.
function WindowShown()
{
	Super.WindowShown();
	bKeepMenus = false;
	if ( ATMenuClient(ClientArea) != None )
		ATMenuClient(ClientArea).Refresh();
}

defaultproperties
{
	ClientClass=Class'AimTrainer.ATMenuClient'
	WindowTitle="Aim Trainer"
	bSizable=False
}
