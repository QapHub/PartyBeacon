// Headless test runner: executes a Lua file under fengari.
//   node tests/run.js tests/test.lua      (run from the addon folder)
// fengari is borrowed from ../Sidecar/node_modules if not installed here.
const fs = require('fs');
const path = require('path');
let fengari;
try { fengari = require('fengari'); }
catch (e) { fengari = require(path.join(__dirname, '..', '..', 'Sidecar', 'node_modules', 'fengari')); }
const { lua, lauxlib, lualib, to_luastring } = fengari;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const file = process.argv[2];
const src = fs.readFileSync(file);
if (lauxlib.luaL_loadbuffer(L, to_luastring(src.toString()), null, to_luastring('@' + file)) !== lua.LUA_OK) {
  console.error('LOAD ERROR: ' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}
if (lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0) !== lua.LUA_OK) {
  console.error('RUNTIME ERROR: ' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}
