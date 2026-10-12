-- EVE Unbound V1.0
local source=debug.getinfo(1,"S").source
local scripts=source:sub(1,1)=="@" and source:sub(2):match("^(.*[/\\])") or nil
assert(scripts,"EVE Unbound could not determine its Scripts directory")
package.path=scripts.."?.lua;"..package.path
local directory=scripts:gsub("[Ss][Cc][Rr][Ii][Pp][Tt][Ss][/\\]$","")
local config=require("Config")
require("UsabilityBatch").start(config,directory)
