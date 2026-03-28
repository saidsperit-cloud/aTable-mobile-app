@echo off
cd /d "e:\vs\repos\aTable\atable_app"
echo Current dir: %CD%
dart run flutter_launcher_icons
echo Exit code: %ERRORLEVEL%
pause
