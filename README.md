# Showdown EmuLink

Play Pokemon battles on a real Game Boy ROM, driven by [Pokemon Showdown](https://pokemonshowdown.com/) as the authoritative server. The emulator runs a patched Pokemon Yellow ROM in the browser via EmulatorJS, while a JS bridge translates Showdown protocol messages into WRAM overrides so every move, damage roll, and status effect matches the server exactly.

## Prerequisites

- [Node.js](https://nodejs.org/) v18+
- [rgbds](https://rgbds.gbdev.io/install) v1.0.1 (Game Boy assembler — needed to build the ROM)
- `make`, `gcc`, `git`

See [`pokeRBY_showdown/INSTALL.md`](pokeRBY_showdown/INSTALL.md) for platform-specific rgbds install instructions.

## Setup

```bash
git clone https://github.com/mpai17/ShowdownEmuLink.git
cd ShowdownEmuLink
git submodule update --init
npm install
```

## Build the ROM

```bash
cd pokeRBY_showdown
make
cd ..
```

This produces `pokeyellow.gbc` and automatically copies it to `EmulatorJS_showdown/roms/`.

## Run

Start the dev server:

```bash
node serve.mjs
```

Open [http://localhost:8080](http://localhost:8080) in your browser. You'll see the sign-in screen where you can enter your Showdown credentials and start a battle.

### Play mode

Sign in with your Showdown account, paste a Gen 1 OU team (pokepaste or packed format), and either search for a ladder match or challenge a specific user.

### Test mode

Requires two Showdown accounts. The bridge connects both, creates a self-play battle, and the enemy account auto-picks random moves. Useful for verifying the bridge end-to-end.

## Run headless tests

The test suite runs 22 scripted turns in a headless browser using Puppeteer:

```bash
node run-test.mjs
```

Expected result: 18 PASS, 4 SKIP, 0 FAIL. The 4 skipped tests cover residual damage (burn/poison/confusion) which require ROM-side turn counting not yet implemented.

Run multiple iterations:

```bash
node run-test.mjs --runs 3
```

## Project structure

```
ShowdownEmuLink/
  serve.mjs                  Dev server (static files + Showdown login proxy)
  run-test.mjs               Headless Puppeteer test runner
  test-connection.mjs        Quick WebSocket connection test
  package.json               Node dependencies (puppeteer, ws)

  pokeRBY_showdown/          Modified Pokemon Yellow ROM (rgbds assembly)
    engine/battle/core.asm     Main battle engine
    engine/showdown/           Showdown override patches
      showdown_init.asm          Battle init, party setup
      showdown_battle.asm        Turn override functions
    ram/wram.asm               WRAM variable definitions
    Makefile                   Build system

  EmulatorJS_showdown/       Browser emulator + Showdown bridge
    showdown/                  Showdown integration files
      showdown.html              Main UI (auth, battle setup, emulator)
      test.html                  Headless test page
      showdown-config.js         WRAM addresses, team parser, constants
      showdown-rom.js            ROMInterface (WRAM read/write via WASM heap)
      showdown-connection.js     WebSocket client + Showdown auth
      showdown-translator.js     TurnTranslator (protocol -> WRAM overrides)
      showdown-party.js          Party writer (team -> WRAM structs)
      showdown-bridge.js         ShowdownBridge (state machine, polling loop)
      showdown-test.js           Automated test turns
      bridge/
        showdown-bridge-input.js     Button press, menu navigation
        showdown-bridge-wram.js      Phase polling, turn override writes
        showdown-bridge-faint.js     Faint exchange handlers
        showdown-bridge-callbacks.js Connection callbacks, battle end
        showdown-bridge-sync.js      Status/HP sync, desync detection
        showdown-bridge-format.js    Debug logging, HP/status parsing
    roms/pokeyellow.gbc        Built ROM (copy from pokeRBY_showdown/)
```

## How it works

The ROM runs in `LINK_STATE_BATTLING` mode. A JS bridge polls a shared phase variable in WRAM:

| Phase | State | Description |
|-------|-------|-------------|
| 0 | Idle | ROM is showing the battle menu, waiting for player input |
| 1 | Player selected | Player picked a move/switch; bridge reads it from WRAM |
| 2 | Turn ready | Bridge wrote all overrides (damage, crit, miss, etc.) |
| 3 | Executing | ROM is running the turn animation |

Each turn, the bridge:
1. Reads the player's action from WRAM
2. Sends the choice to Showdown via WebSocket
3. Waits for turn resolution messages
4. Translates the result into WRAM overrides (exact damage, crit, effectiveness, status, etc.)
5. Writes overrides and advances the phase
6. Corrects HP after the ROM finishes to stay in sync

Desync detection compares HP and faint state between the emulator and Showdown after every turn. If a mismatch is found, the connection is closed and an error overlay is shown.
