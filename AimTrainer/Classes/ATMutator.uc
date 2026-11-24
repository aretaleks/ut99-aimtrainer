//=============================================================================
// ATMutator - routes "mutate at <command>" to the Aim Trainer game.
//=============================================================================
class ATMutator extends Mutator;

var ATGame Game;

function Mutate( string MutateString, PlayerPawn Sender )
{
	if ( Game != None && (MutateString ~= "at" || Left(MutateString, 3) ~= "at ") )
		Game.Command(Mid(MutateString, 3), Sender);
	Super.Mutate(MutateString, Sender);
}
