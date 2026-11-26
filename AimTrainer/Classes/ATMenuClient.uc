//=============================================================================
// ATMenuClient - the controls of the Aim Trainer settings window.
// Every change applies at once (and stops a running session).
//=============================================================================
class ATMenuClient extends UWindowDialogClientWindow;

var UWindowComboControl ModeCombo, WeaponCombo, RangeCombo, MovesCombo;
var UWindowComboControl TimeCombo, TargetsCombo, ModelCombo, SkinCombo, FaceCombo, TeamCombo;
var UWindowCheckbox HitSoundCheck, HeadshotCheck, StreakCheck;
var UWindowSmallButton StartButton, CloseButton, LoadButton, UTMenuButton, MainMenuButton, ExitButton;
var UWindowCheckbox MenuAtStartCheck;
var UWindowComboControl StanceCombo;
var UWindowComboControl MapCombo;
var UWindowEditControl SensEdit;
var bool bUpdating;
var string MeshName;
var bool bMultiSkinned;

function ATGame Game()
{
	return ATGame(GetLevel().Game);
}

function UWindowComboControl AddCombo( string Label, string Help, float Y )
{
	local UWindowComboControl C;

	C = UWindowComboControl(CreateControl(class'UWindowComboControl', 10, Y, WinWidth - 20, 1));
	C.SetText(Label);
	C.SetHelpText(Help);
	C.SetFont(F_Normal);
	C.SetEditable(False);
	C.EditBoxWidth = WinWidth - 130;
	return C;
}

function Created()
{
	local ATGame G;
	local int i;
	local float Y;

	Super.Created();
	G = Game();
	if ( G == None )
		return;
	bUpdating = true;

	Y = 8;
	MapCombo = AddCombo("Map", "Pick a map and press Load (DM and CTF maps; open, flat ones work best).", Y);
	MapCombo.SetSize(WinWidth - 90, MapCombo.WinHeight);
	MapCombo.EditBoxWidth = WinWidth - 200;
	AddMaps("DM");
	AddMaps("CTF");
	MapCombo.Sort();
	i = MapCombo.FindItemIndex(GetPlayerOwner().GetURLMap(), true);
	if ( i >= 0 )
		MapCombo.SetSelectedIndex(i);
	LoadButton = UWindowSmallButton(CreateControl(class'UWindowSmallButton', WinWidth - 74, Y, 64, 16));
	LoadButton.SetText("Load");
	LoadButton.SetHelpText("Switch to this map (your settings stay).");
	Y += 32;

	ModeCombo = AddCombo("Mode", "Duel: targets die and come back elsewhere. Tracking: they never die.", Y);
	for ( i = 0; i < 2; i++ )
		ModeCombo.AddItem(G.ModeNames[i], string(i));
	Y += 24;

	WeaponCombo = AddCombo("Weapon", "Your weapon (ammo never runs out).", Y);
	for ( i = 0; i < ArrayCount(G.WeaponList) && G.WeaponList[i] != ""; i++ )
		WeaponCombo.AddItem(G.WeaponNames[i], G.WeaponList[i]);
	if ( WeaponCombo.FindItemIndex2(G.TrainWeapon, true) < 0 )
		WeaponCombo.AddItem(G.WeaponShortName(), G.TrainWeapon);
	Y += 24;


	RangeCombo = AddCombo("Range", "How far away the targets are.", Y);
	for ( i = 0; i < 3; i++ )
		RangeCombo.AddItem(G.RangeNames[i], string(i));
	Y += 24;

	MovesCombo = AddCombo("Movement", "Recorded: random clips of real players from demos. Synthetic: made up. Mixed: both.", Y);
	for ( i = 0; i < 3; i++ )
		MovesCombo.AddItem(G.MoveNames[i], string(i));
	Y += 24;

	StanceCombo = AddCombo("Position", "Free roam: move around as in a game. Fixed: you stand in place and the targets move in front of you, like a shooting range.", Y);
	StanceCombo.AddItem("Free roam", "0");
	StanceCombo.AddItem("Fixed (shooting range)", "1");
	Y += 24;

	TimeCombo = AddCombo("Session", "Session length.", Y);
	TimeCombo.AddItem("30 seconds", "30");
	TimeCombo.AddItem("45 seconds", "45");
	TimeCombo.AddItem("60 seconds", "60");
	TimeCombo.AddItem("90 seconds", "90");
	TimeCombo.AddItem("2 minutes", "120");
	TimeCombo.AddItem("3 minutes", "180");
	TimeCombo.AddItem("5 minutes", "300");
	if ( TimeCombo.FindItemIndex2(string(G.Duration)) < 0 )
		TimeCombo.AddItem(G.Duration @ "seconds", string(G.Duration));
	Y += 24;

	TargetsCombo = AddCombo("Targets", "How many targets at once.", Y);
	for ( i = 1; i <= 4; i++ )
		TargetsCombo.AddItem(string(i), string(i));
	Y += 24;

	SensEdit = UWindowEditControl(CreateControl(class'UWindowEditControl', 10, Y, WinWidth - 20, 1));
	SensEdit.SetText("Mouse sensitivity");
	SensEdit.SetHelpText("Your mouse sensitivity, the same as in UT's Input options (saved to User.ini).");
	SensEdit.SetFont(F_Normal);
	SensEdit.SetNumericOnly(True);
	SensEdit.SetNumericFloat(True);
	SensEdit.SetMaxLength(8);
	SensEdit.Align = TA_Left;
	SensEdit.EditBoxWidth = 70;
	Y += 32;

	ModelCombo = AddCombo("Target model", "Random stock models, or always the same model.", Y);
	LoadModels();
	Y += 24;
	SkinCombo = AddCombo("Skin", "Skin of the fixed model.", Y);
	Y += 24;
	FaceCombo = AddCombo("Face", "Face of the fixed model.", Y);
	Y += 24;

	TeamCombo = AddCombo("Team colour", "Team colours on the targets' skins.", Y);
	TeamCombo.AddItem("Red", "0");
	TeamCombo.AddItem("Blue", "1");
	TeamCombo.AddItem("None", "255");
	Y += 24;

	HitSoundCheck = AddCheck("Hit sound", "Beep when you hit a target.", Y);
	Y += 20;
	HeadshotCheck = AddCheck("Headshot announcer", "\"Head Shot!!\" like in UT, with the weapons that can headshot (Sniper Rifle, Ripper).", Y);
	Y += 20;
	StreakCheck = AddCheck("Kill streak sound", "A chime that climbs with each quick kill in a row (kills less than 1.5 s apart, from the 2nd kill).", Y);
	Y += 20;
	MenuAtStartCheck = UWindowCheckbox(CreateControl(class'UWindowCheckbox', 10, Y, WinWidth - 20, 1));
	MenuAtStartCheck.SetText("Open this window at start");
	MenuAtStartCheck.SetHelpText("Show this window when a map starts (Esc always opens it).");
	MenuAtStartCheck.SetFont(F_Normal);
	MenuAtStartCheck.Align = TA_Left;
	Y += 30;

	StartButton = AddButton("Start", "Close this window and start a session (or press Fire).", 0, Y);
	UTMenuButton = AddButton("UT Menu", "UT's own menu (options, servers, ...).", 1, Y);
	MainMenuButton = AddButton("Main Menu", "Leave the trainer.", 2, Y);
	ExitButton = AddButton("Exit UT", "Quit the game.", 3, Y);
	CloseButton = AddButton("Resume", "Back to the game (Esc does the same).", 4, Y);

	LoadCurrent();
	bUpdating = false;
}

function UWindowCheckbox AddCheck( string Text, string Help, float Y )
{
	local UWindowCheckbox C;

	C = UWindowCheckbox(CreateControl(class'UWindowCheckbox', 10, Y, WinWidth - 20, 1));
	C.SetText(Text);
	C.SetHelpText(Help);
	C.SetFont(F_Normal);
	C.Align = TA_Left;
	return C;
}

function UWindowSmallButton AddButton( string Text, string Help, int Slot, float Y )
{
	local UWindowSmallButton B;
	local float W;

	W = (WinWidth - 20 - 4 * 6) / 5;
	B = UWindowSmallButton(CreateControl(class'UWindowSmallButton', 10 + Slot * (W + 6), Y, W, 16));
	B.SetText(Text);
	B.SetHelpText(Help);
	return B;
}

function AddMaps( string Prefix )
{
	local string FirstMap, NextMap, TestMap;

	FirstMap = GetPlayerOwner().GetMapName(Prefix, "", 0);
	if ( FirstMap == "" )
		return;
	NextMap = FirstMap;
	while ( !(FirstMap ~= TestMap) )
	{
		MapCombo.AddItem(Left(NextMap, Len(NextMap) - 4), NextMap);
		NextMap = GetPlayerOwner().GetMapName(Prefix, NextMap, 1);
		TestMap = NextMap;
	}
}

function LoadModels()
{
	local int N;
	local string NextPlayer, NextDesc;

	ModelCombo.Clear();
	GetPlayerOwner().GetNextIntDesc("Botpack.TournamentPlayer", 0, NextPlayer, NextDesc);
	while ( NextPlayer != "" && N < 200 )
	{
		if ( InStr(Caps(NextPlayer), "SPECTATOR") < 0 && InStr(Caps(NextPlayer), "COMMANDER") < 0 )
			ModelCombo.AddItem(NextDesc, NextPlayer);
		N++;
		GetPlayerOwner().GetNextIntDesc("Botpack.TournamentPlayer", N, NextPlayer, NextDesc);
	}
	ModelCombo.Sort();
	ModelCombo.InsertItem("Random (stock models)", "");
}

function Select( UWindowComboControl C, string Value2 )
{
	local int i;
	i = C.FindItemIndex2(Value2, true);
	if ( i >= 0 )
		C.SetSelectedIndex(i);
}

function LoadCurrent()
{
	local ATGame G;

	G = Game();
	Select(ModeCombo, string(G.Mode));
	Select(WeaponCombo, G.TrainWeapon);
	Select(RangeCombo, string(G.Range));
	Select(MovesCombo, string(G.MoveSource));
	Select(TimeCombo, string(G.Duration));
	Select(TargetsCombo, string(G.NumTargets));
	Select(TeamCombo, string(G.TargetTeam));
	HitSoundCheck.bChecked = G.bHitSound;
	HeadshotCheck.bChecked = G.bHeadshotAnnouncer;
	StreakCheck.bChecked = G.bStreakSound;
	MenuAtStartCheck.bChecked = G.bMenuAtStart;
	SensEdit.SetValue(SensText(GetPlayerOwner().MouseSensitivity));
	Select(StanceCombo, string(G.Stance));
	if ( G.TargetClass == "" || ModelCombo.FindItemIndex2(G.TargetClass, true) < 0 )
		ModelCombo.SetSelectedIndex(0);
	else
		Select(ModelCombo, G.TargetClass);
	ModelChanged(false);
	if ( G.TargetSkin != "" )
		Select(SkinCombo, G.TargetSkin);
	IterateFaces(SkinCombo.GetValue2());
	if ( G.TargetFace != "" )
		Select(FaceCombo, G.TargetFace);
}

// Sensitivity as text, without trailing zeros (2.500000 -> 2.5).
function string SensText( float F )
{
	local string S;

	S = string(F);
	if ( InStr(S, ".") < 0 )
		return S;
	while ( Right(S, 1) == "0" )
		S = Left(S, Len(S) - 1);
	if ( Right(S, 1) == "." )
		S = Left(S, Len(S) - 1);
	return S;
}

// Typed a sensitivity: apply it at once and save it as UT does (SetSensitivity).
// Ignores 0 and half-typed values such as "" or "0.", which would freeze the mouse.
function SensChanged( ATGame G )
{
	local float F;

	F = float(SensEdit.GetValue());
	if ( F <= 0 || F == GetPlayerOwner().MouseSensitivity )
		return;
	GetPlayerOwner().UpdateSensitivity(F);
	if ( !G.bTestMode )
		GetPlayerOwner().SaveConfig();
}

// The model changed: list its skins (and faces), hidden for Random.
function ModelChanged( bool bPickDefault )
{
	local class<TournamentPlayer> MC;

	SkinCombo.Clear();
	FaceCombo.Clear();
	if ( ModelCombo.GetValue2() == "" )
	{
		SkinCombo.HideWindow();
		FaceCombo.HideWindow();
		return;
	}
	MC = class<TournamentPlayer>(DynamicLoadObject(ModelCombo.GetValue2(), class'Class', true));
	if ( MC == None || MC.default.Mesh == None )
	{
		SkinCombo.HideWindow();
		FaceCombo.HideWindow();
		return;
	}
	MeshName = GetPlayerOwner().GetItemName(string(MC.default.Mesh));
	bMultiSkinned = MC.default.bIsMultiSkinned;
	SkinCombo.ShowWindow();
	IterateSkins();
	if ( bPickDefault || SkinCombo.GetSelectedIndex() < 0 )
	{
		if ( SkinCombo.FindItemIndex2(MC.default.DefaultSkinName, true) >= 0 )
			Select(SkinCombo, MC.default.DefaultSkinName);
		else
			SkinCombo.SetSelectedIndex(0);
	}
	IterateFaces(SkinCombo.GetValue2());
}

// Same listing as UT's player setup window.
function IterateSkins()
{
	local string SkinName, SkinDesc, TestName, Temp;

	SkinName = "None";
	TestName = "";
	while ( true )
	{
		GetPlayerOwner().GetNextSkin(MeshName, SkinName, 1, SkinName, SkinDesc);
		if ( SkinName == TestName )
			break;
		if ( TestName == "" )
			TestName = SkinName;
		Temp = GetPlayerOwner().GetItemName(SkinName);
		if ( !bMultiSkinned )
		{
			if ( Left(Temp, 2) != "T_" )
			{
				if ( SkinDesc == "" )
					SkinDesc = Temp;
				SkinCombo.AddItem(SkinDesc, SkinName);
			}
		}
		else if ( SkinDesc != "" && Mid(Temp, 5, 64) == "" )
			SkinCombo.AddItem(SkinDesc, Left(SkinName, Len(SkinName) - Len(Temp)) $ Left(Temp, 4));
	}
	SkinCombo.Sort();
}

function IterateFaces( string InSkinName )
{
	local string SkinName, SkinDesc, TestName, Temp;

	FaceCombo.Clear();
	if ( !bMultiSkinned || InSkinName == "" )
	{
		FaceCombo.HideWindow();
		return;
	}
	FaceCombo.ShowWindow();
	InSkinName = GetPlayerOwner().GetItemName(InSkinName);
	SkinName = "None";
	TestName = "";
	while ( true )
	{
		GetPlayerOwner().GetNextSkin(MeshName, SkinName, 1, SkinName, SkinDesc);
		if ( SkinName == TestName )
			break;
		if ( TestName == "" )
			TestName = SkinName;
		if ( SkinDesc != "" )
		{
			Temp = GetPlayerOwner().GetItemName(SkinName);
			if ( Mid(Temp, 5) != "" && Left(Temp, 4) == InSkinName )
				FaceCombo.AddItem(SkinDesc, Left(SkinName, Len(SkinName) - Len(Temp)) $ Mid(Temp, 5));
		}
	}
	FaceCombo.Sort();
	if ( FaceCombo.GetSelectedIndex() < 0 )
		FaceCombo.SetSelectedIndex(0);
}

function Notify( UWindowDialogControl C, byte E )
{
	local ATGame G;
	local bool bWeapon, bLooks;

	Super.Notify(C, E);
	if ( bUpdating || C == None )
		return;
	G = Game();
	if ( G == None )
		return;

	if ( E == DE_Click )
	{
		if ( C == LoadButton && MapCombo.GetValue() != "" )
		{
			ParentWindow.Close();
			GetPlayerOwner().ClientTravel(MapCombo.GetValue() $ "?game=AimTrainer.ATGame", TRAVEL_Absolute, false);
		}
		else if ( C == StartButton )
		{
			ParentWindow.Close();
			G.StartCountdown();
		}
		else if ( C == CloseButton )
			ParentWindow.Close();
		else if ( C == UTMenuButton )
			ShowUTMenu();
		else if ( C == MainMenuButton )
		{
			ParentWindow.Close();
			GetPlayerOwner().ConsoleCommand("disconnect");
		}
		else if ( C == ExitButton )
			GetPlayerOwner().ConsoleCommand("exit");
		return;
	}
	if ( E != DE_Change )
		return;

	if ( C == SensEdit )
	{
		SensChanged(G);
		return;
	}
	bUpdating = true;
	if ( C == ModeCombo )
		G.Mode = int(ModeCombo.GetValue2());
	else if ( C == WeaponCombo )
	{
		G.TrainWeapon = WeaponCombo.GetValue2();
		bWeapon = true;
	}
	else if ( C == RangeCombo )
	{
		G.Range = int(RangeCombo.GetValue2());
		bLooks = true;     // respawn them at the new range
	}
	else if ( C == MovesCombo )
		G.MoveSource = int(MovesCombo.GetValue2());
	else if ( C == TimeCombo )
		G.Duration = int(TimeCombo.GetValue2());
	else if ( C == TargetsCombo )
		G.NumTargets = int(TargetsCombo.GetValue2());
	else if ( C == TeamCombo )
	{
		G.TargetTeam = int(TeamCombo.GetValue2());
		bLooks = true;
	}
	else if ( C == HitSoundCheck )
		G.bHitSound = HitSoundCheck.bChecked;
	else if ( C == HeadshotCheck )
		G.bHeadshotAnnouncer = HeadshotCheck.bChecked;
	else if ( C == StreakCheck )
		G.bStreakSound = StreakCheck.bChecked;
	else if ( C == MenuAtStartCheck )
		G.bMenuAtStart = MenuAtStartCheck.bChecked;
	else if ( C == StanceCombo )
	{
		G.Stance = int(StanceCombo.GetValue2());
		bLooks = true;
	}
	else if ( C == ModelCombo )
	{
		ModelChanged(true);
		bLooks = true;
	}
	else if ( C == SkinCombo )
	{
		IterateFaces(SkinCombo.GetValue2());
		bLooks = true;
	}
	else if ( C == FaceCombo )
		bLooks = true;

	if ( bLooks )
	{
		G.TargetClass = ModelCombo.GetValue2();
		if ( G.TargetClass == "" )
		{
			G.TargetSkin = "";
			G.TargetFace = "";
		}
		else
		{
			G.TargetSkin = SkinCombo.GetValue2();
			G.TargetFace = FaceCombo.GetValue2();
		}
	}
	bUpdating = false;
	G.MenuChanged(bWeapon, bLooks);
}

// UT's own menu: let the Esc hook show it, close this window but keep the menus open.
function ShowUTMenu()
{
	local UWindowWindow W;

	for ( W = Root.FirstChildWindow; W != None; W = W.NextSiblingWindow )
		if ( ATEscHook(W) != None )
			ATEscHook(W).ShowUTMenu();
	ATMenuWindow(ParentWindow).bKeepMenus = true;
	ParentWindow.Close();
}

// Window shown again: show the current settings.
function Refresh()
{
	if ( Game() == None || ModeCombo == None )
		return;
	bUpdating = true;
	LoadCurrent();
	bUpdating = false;
}

defaultproperties
{
}
