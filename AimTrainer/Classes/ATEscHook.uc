//=============================================================================
// ATEscHook - Esc opens the Aim Trainer window instead of UT's menu.
//
// An invisible window in UT's window system (created by ATGame). It ticks
// while UT's menu is open. During an Aim Trainer game it keeps UT's menu bar
// hidden and the Aim Trainer window shown, every frame, so there is no state
// to get out of step. The window's "UT Menu" button lets UT's menu through
// until the player goes back to the game. No console or ini change is needed,
// so it works for anyone who installs the package.
//=============================================================================
class ATEscHook extends UWindowWindow;

var bool  bAllowUTMenu;  // the player asked for UT's menu
var float AllowAt;       // game time when they did (the game is paused in the menu)

function Tick( float Delta )
{
	local UMenuRootWindow R;
	local LevelInfo L;

	R = UMenuRootWindow(Root);
	if ( R == None || R.MenuBar == None || Root.Console == None )
		return;
	L = GetLevel();
	if ( L == None || ATGame(L.Game) == None || !Root.Console.bUWindowActive )
	{
		// not in the trainer (or no full menu): UT's menu as usual
		if ( !R.MenuBar.bWindowVisible )
			R.MenuBar.ShowWindow();
		return;
	}
	// "UT Menu" was chosen during this visit (game time stands still in the menu)
	if ( bAllowUTMenu && L.TimeSeconds > AllowAt + 0.05 )
		bAllowUTMenu = false;
	if ( bAllowUTMenu )
	{
		if ( !R.MenuBar.bWindowVisible )
			R.MenuBar.ShowWindow();
		return;
	}
	if ( R.MenuBar.bWindowVisible )
		R.MenuBar.HideWindow();
	if ( !TrainerWindowShown() )
		ATGame(L.Game).CreateMenuWindow(Root);
}

function bool TrainerWindowShown()
{
	local UWindowWindow W;

	for ( W = Root.FirstChildWindow; W != None; W = W.NextSiblingWindow )
		if ( ATMenuWindow(W) != None && W.bWindowVisible )
			return true;
	return false;
}

// From the Aim Trainer window: show UT's own menu until back in the game.
function ShowUTMenu()
{
	bAllowUTMenu = true;
	if ( GetLevel() != None )
		AllowAt = GetLevel().TimeSeconds;
}

defaultproperties
{
}
