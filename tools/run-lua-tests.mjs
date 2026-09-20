// === Lua-Tests ohne installiertes Lua =====================================
//
// tests/smoke.lua und tests/reduced.lua sind fuer Lua 5.1 geschrieben, weil
// WoW Lua 5.1 hat. Auf einem beliebigen Entwicklungsrechner - und erst recht
// auf einem CI-Laeufer - liegt kein Lua herum, und "installier dir erst mal
// LuaJIT" ist keine reproduzierbare Testanweisung.
//
// Deshalb fengari: eine Lua-Implementierung in JavaScript, als normale
// npm-Abhaengigkeit im Repository festgeschrieben. Ein "npm ci" genuegt.
//
// Ein Unterschied bleibt und wird hier geradegezogen: fengari ist Lua 5.3, und
// dort heisst unpack "table.unpack". Im Spiel gibt es beide Namen nicht
// gleichzeitig - der Addoncode selbst nimmt deshalb "unpack or table.unpack".

import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { basename } from "node:path";
import { lauxlib, lua, lualib, to_luastring } from "fengari";

const SHIM = `
-- Lua 5.1, wie im Spiel: fengari ist 5.3 und kennt unpack nur als table.unpack.
if unpack == nil then unpack = table.unpack end
-- 5.3 trennt Ganzzahl und Fliesskomma; "1.0" statt "1" in einer Meldung waere
-- ein Unterschied, den es im Spiel nicht gibt.
if math.type then
  local realTostring = tostring
  tostring = function(value)
    if math.type(value) == "float" and value == math.floor(value)
        and value == value and value ~= math.huge and value ~= -math.huge then
      return string.format("%d", value)
    end
    return realTostring(value)
  end
end
`;

// fengari bringt io.open nicht mit (loadfile schon). Die Tests lesen aber die
// TOC, um dieselbe Ladereihenfolge zu benutzen wie das Spiel. Statt die Tests
// darauf zu verbiegen, bekommt der Lua-Zustand hier eine Lesefunktion; unter
// einem echten Lua nimmt tests/wow-stubs.lua weiterhin io.open.
function installFileReader(L) {
  lua.lua_pushcfunction(L, (state) => {
    const path = lua.lua_tojsstring(state, 1);
    try {
      lua.lua_pushstring(state, readFileSync(path));
      return 1;
    } catch (error) {
      lua.lua_pushnil(state);
      lua.lua_pushstring(state, to_luastring(String(error.message)));
      return 2;
    }
  });
  lua.lua_setglobal(L, to_luastring("GC_ReadTextFile"));
}

function run(L, source, chunkName) {
  if (lauxlib.luaL_loadbuffer(L, source, null, to_luastring(chunkName)) !== lua.LUA_OK) {
    throw new Error(`${chunkName} laesst sich nicht laden:\n${lua.lua_tojsstring(L, -1)}`);
  }
  if (lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0) !== lua.LUA_OK) {
    throw new Error(`${chunkName} ist fehlgeschlagen:\n${lua.lua_tojsstring(L, -1)}`);
  }
}

// Ein frischer Zustand je Datei: Die Tests setzen jede Menge Globals, und ein
// Test, der nur laeuft, weil ein anderer vorher etwas hinterlassen hat, ist
// keiner.
export function runLuaFile(path) {
  if (process.env.GCP_LUA51) {
    const result = spawnSync(process.env.GCP_LUA51,
      ["-e", "assert(_VERSION == 'Lua 5.1', 'Lua 5.1 required')", path], { stdio: "inherit" });
    if (result.error || result.status !== 0) {
      throw new Error(`Lua 5.1: ${path}: ${result.error?.message ?? `exit ${result.status}`}`);
    }
    return true;
  }
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  installFileReader(L);
  run(L, to_luastring(SHIM), "=shim");
  // Als Bytes lesen, nicht als Zeichenkette: Die Tests enthalten Umlaute, und
  // fengari rechnet in Bytes wie Lua selbst.
  run(L, readFileSync(path), `@${path}`);
  return true;
}

const FILES = ["tests/forever.lua", "tests/package.lua"];

if (process.argv[1] && basename(process.argv[1]) === "run-lua-tests.mjs") {
  const only = process.argv.slice(2);
  for (const file of only.length > 0 ? only : FILES) {
    runLuaFile(file);
  }
}
