@echo off
call build.cmd
if errorlevel 1 exit /b 1
python run-checked-tests.py input_projection_tests camera_context_tests cockpit_local_tests cockpit_input_tests cutscene_recovery_tests first_person_context_tests camera_return_tests hud_reference_tests native_hud_snapshot_tests takeover_logic_tests
exit /b %errorlevel%
