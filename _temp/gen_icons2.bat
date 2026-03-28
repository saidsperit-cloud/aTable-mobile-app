@echo off
cd /d "e:\vs\repos\aTable\atable_app"
echo Current dir: %CD%
where dart >> "e:\vs\repos\aTable\_temp\icons_bat.txt" 2>&1
echo dart found
dart run flutter_launcher_icons >> "e:\vs\repos\aTable\_temp\icons_bat.txt" 2>&1
echo Done. Exit: %ERRORLEVEL%
