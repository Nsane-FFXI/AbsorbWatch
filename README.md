<img width="263" height="57" alt="aw" src="https://github.com/user-attachments/assets/d9ff5de0-df5a-4cba-a0b6-1f22c0d0de93" />

# AbsorbWatch

Author: Nsane  
Version: 2025.9.1

## What it does
Tracks party members casting Absorb-TP.  
Puts a small box on your screen with:
- Player name
- TP stolen (colored by amount)
- Time since last absorb
- How many absorbs for that player

It works only for players in your party.  
The box updates live and remembers its position.

## Install
1. Put AbsorbWatch.lua in Windower/addons/AbsorbWatch/
2. In game: //lua load absorbwatch

## Basic commands
```
//aw help         Show all commands
//aw status       Show current settings
//aw decay <sec>  How long to remember absorbs (default 900s)
//aw screen <sec> How long to show after last absorb (default 60s)
//aw colors on/off   Turn colored TP numbers on or off
//aw counter on/off  Show or hide [count]
//aw timer on/off    Show or hide (time ago)
// move box:
//   //aw pos <x> <y>
//   //aw resetpos
//   //can be dragged to position.
//aw clear        Clear all absorbs
//aw test         Show sample data
```

## Defaults
- Keep total amount absorbs casted for last 15 minutes.
- Show for 60s after last
- Colors on
- Counter on
- Timer on
- Position: (100, 100)

## Color guide
- ≤99 TP: white
- ≤200 TP: green
- ≤300 TP: yellow
- ≤400 TP: orange
- >400 TP: red
- 0 TP: blue, indicates a resist

## Notes
- Updates every 0.10s
- Saves box position when moved
