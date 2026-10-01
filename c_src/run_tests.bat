@echo off
rem Run every lockstep scenario: the C port against the real ROM on the 8080
rem core, compared after every main-loop pass and every interrupt.
rem Build first with build_all.bat.  Prints TESTS OK or stops at the first FAIL.
cd /d "%~dp0"
if not exist tests\lockstep.exe (echo tests\lockstep.exe is missing - run build_all.bat & exit /b 1)
if exist tests\coverage.bin del tests\coverage.bin
set L=tests\lockstep.exe --quiet --coverage tests\coverage.bin

echo attract, 1500 frames
%L% --frames 1500 || exit /b 1
echo one player, steered, 12000 frames
%L% --frames 12000 --coin 950 --start1 1010 --track || exit /b 1
echo one player, paddle held: three splats, game over, high score
%L% --frames 6000 --coin 950 --start1 1010 --paddle 60 || exit /b 1
echo one player, steered then left alone: game over with a score
%L% --frames 9000 --coin 950 --start1 1010 --track-frames 1000 4000 || exit /b 1
echo two players (coinage 1), turns change
%L% --frames 14000 --dip 0x01 --coin 950 --start2 1010 --track-frames 1000 2600 --track-frames 3000 4800 --track-frames 5400 7000 --track-frames 7600 9000 --track-frames 9600 11000 || exit /b 1
echo all rows, bonus game at 9000, 4 jumps, extra jump at 4000, steered, 20000 frames
%L% --frames 20000 --dip 0x74 --coin 950 --start1 1010 --track || exit /b 1
echo bonus game at 11000, extra jump at 3000
%L% --frames 16000 --dip 0x08 --coin 950 --start1 1010 --track || exit /b 1
echo coinage 2: two coins, one player
%L% --frames 5000 --dip 0x02 --coin 950 --coin 1000 --start1 1100 --track-frames 1100 3000 || exit /b 1
echo coinage 3: four coins, two players
%L% --frames 6000 --dip 0x03 --coin 950 --coin 1000 --coin 1050 --coin 1100 --start2 1200 --track-frames 1200 3000 --paddle 200 || exit /b 1
echo coinage 3: three coins, one player (a coin is given back)
%L% --frames 4000 --dip 0x03 --coin 950 --coin 1000 --coin 1050 --start1 1200 --track-frames 1200 3000 || exit /b 1
echo coinage 0: second coin, two players
%L% --frames 5000 --coin 950 --coin 1100 --start2 1250 --track-frames 1250 2500 || exit /b 1
echo self test: RAM and ROM test, looping
%L% --frames 4 --test || exit /b 1
echo self test, switch turned off: into the game
%L% --frames 1200 --test --testoff 3 || exit /b 1
echo switch test: coin held during the RAM test, buttons, paddle
%L% --frames 300 --test --coin 0 --start1 60 --start2 120 --coin 200 --paddle 180 || exit /b 1
echo 1 pass per interrupt period
%L% --frames 6000 --passes 1 --coin 950 --start1 1010 --track || exit /b 1
echo 12 passes per interrupt period
%L% --frames 6000 --passes 12 --coin 950 --start1 1010 --track || exit /b 1

python tools\coverage.py tests\coverage.bin || exit /b 1
echo TESTS OK
