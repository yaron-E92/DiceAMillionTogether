@echo off
setlocal
cd /d "%~dp0.."
echo DiceAMillionTogether .NET relay - requires .NET 10 SDK
echo Default binding: 127.0.0.1:7777
echo For private LAN/VPN set DMT_BIND to the local private interface IP first.
dotnet run --project src\DiceAMillionTogether.Relay -c Release
