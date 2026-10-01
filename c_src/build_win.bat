@echo off
rem Build the playable Clowns C port with the Windows backend (x64, VS2022 cl).
rem
rem Target:
rem   clowns_win.exe   (c_src\, next to clowns_win.ini): app_loop.c + every
rem                    game module + the ROM image + sound.c + platform\windows
rem
rem Objects go to obj\win\ so they never collide with build_all.bat's.
call "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat" -arch=amd64 -no_logo
cd /d "%~dp0"

for %%f in (state_defs.h rom_labels.h progrom.c progrom.h) do if not exist %%f (echo MISSING %%f - run tools\gen_state.py and tools\gen_roms.py & exit /b 1)
if not exist obj mkdir obj
if not exist obj\win mkdir obj\win

set GAME=state.c boot.c irq.c draw.c mainloop.c events.c switchtest.c script.c contact.c progrom.c
set SEAM=app_loop.c sound.c

echo === clowns_win.exe
cl /nologo /O2 /W4 /std:c11 /MD /D_CRT_SECURE_NO_WARNINGS /I. /Foobj\win\ ^
   %GAME% %SEAM% platform\windows\plat_win.c ^
   /Fe:clowns_win.exe ^
   /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib winmm.lib shell32.lib || exit /b 1

echo WIN BUILD OK
