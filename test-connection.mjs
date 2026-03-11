#!/usr/bin/env node
/**
 * Quick test: connect to public Showdown server, authenticate two guests,
 * create a gen1ou battle, and verify messages flow.
 */

import WebSocket from 'ws';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// Load config
let config = {};
try {
  config = JSON.parse(readFileSync(join(import.meta.dirname, 'config.json'), 'utf8'));
} catch (e) {
  console.warn('[Runner] No config.json found, using defaults/env vars');
}

const SERVER_URL = config.server || 'wss://sim3.psim.us/showdown/websocket';
const LOGIN_URL = 'https://play.pokemonshowdown.com/~~showdown/action.php';

const PACKED_TEAM = 'Alakazam|||noability|psychic,thunderwave,recover,seismictoss|Serious|1,0,0,0,0,0||30,30,30,30,30,30||100|]Starmie|||noability|surf,psychic,thunderbolt,recover|Serious|1,0,0,0,0,0||30,30,30,30,30,30||100|]Snorlax|||noability|bodyslam,earthquake,icebeam,rest|Serious|1,0,0,0,0,0||30,30,30,30,30,30||100|]Tauros|||noability|bodyslam,earthquake,blizzard,hyperbeam|Serious|1,0,0,0,0,0||30,30,30,30,30,30||100|]Chansey|||noability|icebeam,thunderbolt,thunderwave,softboiled|Serious|1,0,0,0,0,0||30,30,30,30,30,30||100|]Exeggutor|||noability|psychic,explosion,megadrain,rest|Serious|1,0,0,0,0,0||30,30,30,30,30,30||100|';

function delay(ms) { return new Promise(r => setTimeout(r, ms)); }

class TestConnection {
  constructor(name) {
    this.name = name;
    this.ws = null;
    this.challstr = null;
    this.username = '';
    this.battleRoom = null;
    this._resolvers = {};
  }

  connect() {
    return new Promise((resolve, reject) => {
      console.log(`[${this.name}] Connecting to ${SERVER_URL}...`);
      this.ws = new WebSocket(SERVER_URL);
      this.ws.on('open', () => {
        console.log(`[${this.name}] Connected`);
        resolve();
      });
      this.ws.on('error', (e) => {
        console.error(`[${this.name}] Error:`, e.message);
        reject(e);
      });
      this.ws.on('close', (code, reason) => console.log(`[${this.name}] Closed (code=${code}, reason=${reason?.toString()})`));
      this.ws.on('message', (data) => {
        const str = data.toString();
        // Log all raw messages for debugging
        for (const line of str.split('\n')) {
          if (line.trim()) console.log(`[${this.name}] RAW: ${line}`);
        }
        this._onMessage(str);
      });
    });
  }

  _onMessage(raw) {
    const lines = raw.split('\n');
    let roomId = '';
    if (lines[0]?.startsWith('>')) {
      roomId = lines[0].slice(1).trim();
      lines.shift();
    }

    for (const line of lines) {
      if (!line.startsWith('|')) continue;
      const parts = line.slice(1).split('|');
      const cmd = parts[0];

      if (cmd === 'challstr') {
        this.challstr = parts.slice(1).join('|');
        console.log(`[${this.name}] Got challstr (${this.challstr.length} chars)`);
        if (this._resolvers.challstr) this._resolvers.challstr();
      }

      if (cmd === 'updateuser') {
        const loggedIn = parts[2]?.trim() === '1';
        this.username = parts[1]?.trim();
        console.log(`[${this.name}] updateuser: "${this.username}" loggedIn=${loggedIn}`);
        if (loggedIn && this._resolvers.auth) this._resolvers.auth();
      }

      if (cmd === 'updatechallenges') {
        console.log(`[${this.name}] updatechallenges: ${parts[1]}`);
        try {
          const data = JSON.parse(parts[1]);
          if (data.challengesFrom && Object.keys(data.challengesFrom).length > 0) {
            if (this._resolvers.challenged) this._resolvers.challenged(data.challengesFrom);
          }
        } catch (e) {}
      }

      // Challenge also arrives as PM: |pm|SENDER|RECEIVER|/challenge FORMAT|...
      if (cmd === 'pm' && parts[3]?.startsWith('/challenge ')) {
        const from = parts[1]?.trim();
        const format = parts[3].replace('/challenge ', '');
        console.log(`[${this.name}] Challenge PM from ${from} (${format})`);
        if (this._resolvers.challenged) this._resolvers.challenged({ [from]: format });
      }

      if (roomId.startsWith('battle-')) {
        if (!this.battleRoom) {
          this.battleRoom = roomId;
          console.log(`[${this.name}] Joined battle: ${roomId}`);
          if (this._resolvers.battle) this._resolvers.battle(roomId);
        }
        if (cmd === 'request') {
          try {
            const req = JSON.parse(parts[1] || '{}');
            console.log(`[${this.name}] Request: rqid=${req.rqid} forceSwitch=${!!req.forceSwitch} active=${!!req.active}`);
            if (this._resolvers.request) this._resolvers.request(req);
          } catch (e) {}
        }
        if (cmd === 'turn') {
          console.log(`[${this.name}] Turn ${parts[1]}`);
        }
        if (cmd === 'win' || cmd === 'tie') {
          console.log(`[${this.name}] Battle ended: ${cmd} ${parts[1]}`);
        }
      }
    }
  }

  waitFor(event, timeout = 15000) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        delete this._resolvers[event];
        reject(new Error(`[${this.name}] Timeout waiting for ${event}`));
      }, timeout);
      this._resolvers[event] = (data) => {
        clearTimeout(timer);
        delete this._resolvers[event];
        resolve(data);
      };
    });
  }

  async login(name, password) {
    // Wait for challstr if we don't have it yet
    if (!this.challstr) await this.waitFor('challstr');

    const authPromise = this.waitFor('auth');
    let assertion;

    if (password) {
      // Registered account login
      const body = new URLSearchParams({
        act: 'login',
        name,
        pass: password,
        challstr: this.challstr,
      });

      console.log(`[${this.name}] Password login for "${name}"...`);
      const resp = await fetch(LOGIN_URL, { method: 'POST', body });
      const text = await resp.text();
      const json = JSON.parse(text.startsWith(']') ? text.slice(1) : text);

      if (!json.actionsuccess) {
        throw new Error(`Login failed for "${name}": ${json.assertion || 'bad credentials'}`);
      }
      assertion = json.assertion;
    } else {
      // Guest login
      const body = new URLSearchParams({
        act: 'getassertion',
        userid: name.toLowerCase().replace(/[^a-z0-9]/g, ''),
        challstr: this.challstr,
      });

      console.log(`[${this.name}] Guest login for "${name}"...`);
      const resp = await fetch(LOGIN_URL, { method: 'POST', body });
      assertion = await resp.text();

      if (assertion.startsWith(';;')) {
        throw new Error(`Name "${name}" is registered — use password login`);
      }
    }

    console.log(`[${this.name}] Assertion: "${assertion.slice(0, 30)}..."`);
    this.ws.send(`|/trn ${name},0,${assertion}`);

    await authPromise;
    console.log(`[${this.name}] Authenticated as "${this.username}"`);
  }

  send(msg) { this.ws.send(msg); }
  close() { this.ws?.close(); }
}

// ============= Main =============

const player = new TestConnection('player');
const enemy = new TestConnection('enemy');

// Credentials: config.json > env vars > random guest names
const playerName = config.player?.name || process.env.SD_PLAYER || `SDemuP${Math.floor(Math.random() * 90000 + 10000)}`;
const playerPass = config.player?.pass || process.env.SD_PLAYER_PASS || undefined;
const enemyName = config.enemy?.name || process.env.SD_ENEMY || `SDemuB${Math.floor(Math.random() * 90000 + 10000)}`;
const enemyPass = config.enemy?.pass || process.env.SD_ENEMY_PASS || undefined;

try {
  // Step 1: Connect both
  console.log('\n=== Step 1: Connect ===');
  await player.connect();
  await enemy.connect();

  // Step 2: Authenticate
  console.log('\n=== Step 2: Authenticate ===');
  console.log(`Player: "${playerName}" (${playerPass ? 'registered' : 'guest'})`);
  console.log(`Enemy:  "${enemyName}" (${enemyPass ? 'registered' : 'guest'})`);
  await player.login(playerName, playerPass);
  await enemy.login(enemyName, enemyPass);

  // Step 3: Set teams
  console.log('\n=== Step 3: Set teams ===');
  player.send(`|/utm ${PACKED_TEAM}`);
  enemy.send(`|/utm ${PACKED_TEAM}`);
  await delay(500);

  // Step 4: Challenge
  console.log('\n=== Step 4: Challenge ===');
  const challengePromise = enemy.waitFor('challenged');
  player.send(`|/challenge ${enemy.username}, gen1ou`);
  const challenges = await challengePromise;
  console.log('Enemy received challenge:', challenges);

  // Step 5: Accept
  console.log('\n=== Step 5: Accept ===');
  const playerBattlePromise = player.waitFor('battle');
  const enemyBattlePromise = enemy.waitFor('battle');
  enemy.send(`|/accept ${player.username}`);

  const [pRoom, eRoom] = await Promise.all([playerBattlePromise, enemyBattlePromise]);
  console.log(`Battle created! Player room: ${pRoom}, Enemy room: ${eRoom}`);

  // Step 6: Wait for first request (team preview / move selection)
  console.log('\n=== Step 6: First request ===');
  const req = await player.waitFor('request', 10000);
  console.log('Player got first request. Side pokemon:', req.side?.pokemon?.map(p => p.ident));

  console.log('\n=== SUCCESS: Full connection + battle setup working ===');

  // Forfeit cleanly
  player.send(`${pRoom}|/forfeit`);
  await delay(1000);

} catch (e) {
  console.error('\n=== FAILED ===');
  console.error(e.message);
} finally {
  player.close();
  enemy.close();
  process.exit(0);
}
