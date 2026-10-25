# Manual two-player playtest

- [ ] Same Steam game version, and mod builds against local `data.win` on both computers
- [ ] Host starts relay in private LAN/VPN, both can reach TCP 7777
- [ ] Both games show **CO-OP**, one creates a room, other joins with code
- [ ] Both can choose different characters and READY
- [ ] Both start run with a consistent map
- [ ] Selecting dice locally works; peer dice have blue outlines and are not selectable
- [ ] Roll barrier waits for both players, total score agrees after resolution
- [ ] Shop exit and map votes resolve consistently
- [ ] Both see same boss outcome and game-over state
- [ ] Returning to solo does not corrupt local saves

Troubleshooting: start with `run_coop_debug.bat` (if present) or capture `coop_mod.log` from each client. Record game version, stage, host/guest and any desync. Never publicly share private relay IPs or saved account data.
