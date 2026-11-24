@echo off
rem Aim Trainer: plays from this workspace with its own copy of the game settings.
rem Usage: PlayAimTrainer.bat [map]   (default DM-AimRange)
cd /d "%~dp0System"
if not exist AimTrainerUT.exe copy /y UnrealTournament.exe AimTrainerUT.exe >nul
if not exist AimTrainerUT.int copy /y UnrealTournament.int AimTrainerUT.int >nul
set MAP=%~1
if "%MAP%"=="" set MAP=DM-AimRange
start "" AimTrainerUT.exe "%MAP%?game=AimTrainer.ATGame" ini=UnrealTournament.ini userini=User.ini
