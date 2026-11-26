//=============================================================================
// ATHUD - Aim Trainer overlay on top of the normal UT HUD.
//=============================================================================
class ATHUD extends ChallengeHUD;

simulated function PostRender( canvas Canvas )
{
	local ATGame G;

	Super.PostRender(Canvas);
	G = ATGame(Level.Game);
	if ( G == None || PlayerOwner == None || PlayerOwner.bShowScores || PlayerOwner.bShowMenu )
		return;
	Canvas.Reset();
	Canvas.Style = ERenderStyle.STY_Normal;
	Canvas.bCenter = false;

	switch ( G.Phase )
	{
		case SP_Idle:
			DrawIdle(Canvas, G);
			break;
		case SP_Countdown:
			DrawCountdown(Canvas, G);
			break;
		case SP_Running:
			DrawRunning(Canvas, G);
			break;
		case SP_Results:
			DrawResults(Canvas, G);
			break;
	}
	if ( G.StatusMsg != "" && Level.TimeSeconds - G.StatusTime < 4.0 )
	{
		Canvas.Font = MyFonts.GetSmallFont(Canvas.ClipX);
		SetColor(Canvas, 255, 255, 128);
		Centered(Canvas, G.StatusMsg, Canvas.ClipY * 0.80);
	}
}

// ----------------------------------------------------------------------------

function SetColor( canvas C, byte R, byte G, byte B )
{
	C.DrawColor.R = R;
	C.DrawColor.G = G;
	C.DrawColor.B = B;
}

function float Centered( canvas C, string S, float Y )
{
	local float XL, YL;
	C.StrLen(S, XL, YL);
	C.SetPos((C.ClipX - XL) / 2, Y);
	C.DrawText(S, false);
	return YL;
}

function float Line( canvas C, string S, float X, float Y )
{
	local float XL, YL;
	C.StrLen(S, XL, YL);
	C.SetPos(X, Y);
	C.DrawText(S, false);
	return YL;
}

function string TimeText( float T )
{
	local int M, S, Tenth;
	T = FMax(0, T);
	M = int(T) / 60;
	S = int(T) % 60;
	Tenth = int((T - int(T)) * 10);
	if ( S < 10 )
		return M $ ":0" $ S $ "." $ Tenth;
	return M $ ":" $ S $ "." $ Tenth;
}

function string AccText( ATGame G )
{
	return G.FormatAcc(int(G.Accuracy() * 10)) $ "%";
}

// ----------------------------------------------------------------------------

function DrawIdle( canvas C, ATGame G )
{
	local float Y;

	C.Font = MyFonts.GetBigFont(C.ClipX);
	SetColor(C, 255, 200, 0);
	Y = C.ClipY * 0.08;
	Y += Centered(C, "AIM TRAINER", Y);
	C.Font = MyFonts.GetSmallFont(C.ClipX);
	SetColor(C, 255, 255, 255);
	Y += Centered(C, G.SettingsLine(), Y + 4) + 4;
	if ( G.ActiveCourse() == 2 )
		Y += Centered(C, "Airborne: only targets flying from a pad can be hit", Y + 2) + 2;
	if ( int(Level.TimeSeconds * 2) % 2 == 0 )
		SetColor(C, 0, 255, 0);
	else
		SetColor(C, 0, 160, 0);
	C.Font = MyFonts.GetMediumFont(C.ClipX);
	Centered(C, "Press FIRE (or F8) to start  -  F7 for settings", Y + 8);

	DrawTopScores(C, G, false);
	DrawHelp(C, G);
}

function DrawCountdown( canvas C, ATGame G )
{
	C.Font = MyFonts.GetHugeFont(C.ClipX);
	SetColor(C, 255, 200, 0);
	Centered(C, string(Max(1, int(3.999 - G.PhaseTime))), C.ClipY * 0.3);
	C.Font = MyFonts.GetSmallFont(C.ClipX);
	SetColor(C, 255, 255, 255);
	Centered(C, G.SettingsLine(), C.ClipY * 0.12);
}

function DrawRunning( canvas C, ATGame G )
{
	local float Y, X;

	C.Font = MyFonts.GetBigFont(C.ClipX);
	if ( G.SessionLeft < 5 )
		SetColor(C, 255, 60, 60);
	else
		SetColor(C, 255, 255, 255);
	Y = C.ClipY * 0.06;
	Y += Centered(C, TimeText(G.SessionLeft), Y);
	C.Font = MyFonts.GetMediumFont(C.ClipX);
	SetColor(C, 255, 200, 0);
	Centered(C, G.Damage @ "pts", Y + 2);

	C.Font = MyFonts.GetSmallFont(C.ClipX);
	SetColor(C, 200, 200, 200);
	X = C.ClipX * 0.02;
	Y = C.ClipY * 0.35;
	Y += Line(C, "Hits   " $ G.Hits $ " / " $ G.Shots, X, Y);
	Y += Line(C, "Acc    " $ AccText(G), X, Y);
	if ( G.Mode == 0 )
		Y += Line(C, "Kills  " $ G.Kills, X, Y);
	Y += Line(C, "Heads  " $ G.Headshots, X, Y);
}

function DrawResults( canvas C, ATGame G )
{
	local float Y;

	C.Font = MyFonts.GetBigFont(C.ClipX);
	Y = C.ClipY * 0.08;
	if ( G.bNewBest )
	{
		SetColor(C, 0, 255, 0);
		Y += Centered(C, "NEW BEST!", Y);
	}
	else
	{
		SetColor(C, 255, 200, 0);
		Y += Centered(C, "SESSION OVER", Y);
	}
	C.Font = MyFonts.GetMediumFont(C.ClipX);
	SetColor(C, 255, 255, 255);
	Y += Centered(C, G.Damage @ "pts   " $ AccText(G) @ "accuracy", Y + 4) + 4;
	C.Font = MyFonts.GetSmallFont(C.ClipX);
	SetColor(C, 200, 200, 200);
	if ( G.Mode == 0 )
	{
		if ( G.TTKCount > 0 )
			Y += Centered(C, G.Kills @ "kills   " $ G.Hits $ "/" $ G.Shots @ "hits   " $ G.Headshots @ "headshots   avg time to kill" @ TimeText(G.TTKSum / G.TTKCount) $ "s", Y + 4);
		else
			Y += Centered(C, G.Kills @ "kills   " $ G.Hits $ "/" $ G.Shots @ "hits   " $ G.Headshots @ "headshots", Y + 4);
	}
	else
		Y += Centered(C, G.Hits $ "/" $ G.Shots @ "hits   " $ G.Headshots @ "headshots", Y + 4);
	if ( G.ResultRank > 1 )
		Centered(C, "#" $ G.ResultRank @ "on your list", Y + 8);
	if ( G.PhaseTime > 1.5 )
	{
		SetColor(C, 0, 255, 0);
		C.Font = MyFonts.GetMediumFont(C.ClipX);
		Centered(C, "FIRE to go again", C.ClipY * 0.62);
	}
	DrawTopScores(C, G, true);
}

function DrawTopScores( canvas C, ATGame G, bool bResults )
{
	local int i, N;
	local float X, Y, YL;
	local string S;

	N = G.GetTopScores(10);
	C.Font = MyFonts.GetSmallFont(C.ClipX);
	X = C.ClipX * 0.70;
	Y = C.ClipY * 0.30;
	SetColor(C, 255, 200, 0);
	Y += Line(C, "Your best (" $ Repl(G.CourseText(), " | ", ", ") $ G.ModeNames[G.Mode] $ ", " $ G.WeaponShortName() $ ", " $ G.RangeNames[G.Range] $ ")", X, Y);
	C.Font = MyFonts.GetSmallestFont(C.ClipX);
	if ( N == 0 )
	{
		SetColor(C, 160, 160, 160);
		Line(C, "no scores yet", X, Y + 2);
		return;
	}
	for ( i = 0; i < N; i++ )
	{
		if ( bResults && i == G.ResultRank - 1 )
			SetColor(C, 0, 255, 0);
		else
			SetColor(C, 220, 220, 220);
		S = (i + 1) $ ".  " $ G.Field(G.TopScores[i], 1) $ " pts   " $ G.FormatAcc(int(G.Field(G.TopScores[i], 2))) $ "%";
		if ( G.Mode == 0 )
			S = S $ "   " $ G.Field(G.TopScores[i], 3) $ " kills";
		S = S $ "   " $ G.Field(G.TopScores[i], 6);
		YL = Line(C, S, X, Y + 2);
		Y += YL;
	}
}

function DrawHelp( canvas C, ATGame G )
{
	local float X, Y;

	C.Font = MyFonts.GetSmallestFont(C.ClipX);
	SetColor(C, 170, 170, 170);
	X = C.ClipX * 0.02;
	Y = C.ClipY * 0.30;
	Y += Line(C, "F7 / mutate at menu    settings window", X, Y);
	Y += Line(C, "F8 / mutate at start   start a session", X, Y);
	Y += Line(C, "mutate at help         all console commands", X, Y);
	Y += Line(C, " ", X, Y);
	Y += Line(C, "Targets:" @ G.ModelName(), X, Y);
	if ( G.Moves.NumClips > 0 )
		Line(C, G.Moves.NumClips @ "recorded clips loaded", X, Y + 6);
	else
		Line(C, "no recorded clips: synthetic movement", X, Y + 6);
}
