@echo off
rem Build the headless test program of the Clowns C port (x64, VS2022 cl).
rem   tests\clowns_headless.exe   the whole port on the quiet backend:
rem                               scripted inputs, PNG shots, RAM dumps
rem Everything compiles at /W4 /std:c11.  Objects go to obj\.
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64 -no_logo
cd /d "%~dp0"

for %%f in (state_defs.h rom_labels.h progrom.c progrom.h) do if not exist %%f (echo MISSING %%f - run tools\gen_state.py and tools\gen_roms.py & exit /b 1)
if not exist obj mkdir obj

set GAME=state.c boot.c irq.c draw.c mainloop.c events.c switchtest.c script.c contact.c progrom.c
set SEAM=app_loop.c sound.c shot.c

echo === tests\clowns_headless.exe
cl /nologo /O2 /W4 /std:c11 /MD /D_CRT_SECURE_NO_WARNINGS /I. /Foobj\ ^
   tests\headless.c %GAME% %SEAM% platform\headless\plat_headless.c ^
   /Fe:tests\clowns_headless.exe || exit /b 1

rem ---- the oracle: the ROM on AAE's 8080 core, against the game modules -----
rem tests\i8080\cpu_i8080.cpp is a copied core (its own warning level).
echo === tests\lockstep.exe
cl /nologo /O2 /W3 /std:c++17 /EHsc /MD /D_CRT_SECURE_NO_WARNINGS /I. /Itests\i8080 /c ^
   tests\i8080\cpu_i8080.cpp /Foobj\ || exit /b 1
cl /nologo /O2 /W4 /std:c++17 /EHsc /MD /D_CRT_SECURE_NO_WARNINGS /I. /Itests\i8080 /Foobj\ ^
   tests\lockstep.cpp obj\cpu_i8080.obj ^
   obj\state.obj obj\boot.obj obj\irq.obj obj\draw.obj obj\mainloop.obj obj\events.obj ^
   obj\switchtest.obj obj\script.obj obj\contact.obj obj\progrom.obj obj\shot.obj ^
   /Fe:tests\lockstep.exe || exit /b 1

echo ALL BUILDS OK
