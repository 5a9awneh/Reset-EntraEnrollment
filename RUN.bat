@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Start-Process powershell.exe -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%~dp0Reset-EntraEnrollment.ps1\"' -Verb RunAs"
