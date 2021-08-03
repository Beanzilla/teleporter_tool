
local S = minetest.get_translator("teleporter_tool")

-- The wear added to the teleporter per teleport. When the wear gets past 65535, the
-- tool breaks.
local WEAR_PER_USE = 328 -- 200 uses.

-- Provides a reference to ...
-- https://stackoverflow.com/questions/2282444/how-to-check-if-a-table-contains-an-element-in-lua
function table.contains(table, element)
  for _, value in pairs(table) do
    if value == element then
      return true
    end
  end
  return false
end

-- Tries to tell whether an ObjectRef represents a real connected player.
local function object_is_player(object)
	if not object then return false end
	if not minetest.is_player(object) then return false end
	-- Pipeworks uses this:
	if object.is_fake_player then return false end
	-- Check if the positions match:
	local player = minetest.get_player_by_name(object:get_player_name())
	if not player then return false end
	local object_pos = object:get_pos()
	local player_pos = player:get_pos()
	if not object_pos or not player_pos then return false end
	return vector.equals(object_pos, player_pos)
end

-- Verify when we talk to meta it is setup
local function pre_check(item)
	local meta = minetest.deserialize(item:get_metadata())
	if meta == nil then
		meta = {}
		meta.save_block = nil
	end
	return meta
end

-- Tries to teleport the node. The user will be
-- messaged if the teleport didn't occur. The return value is whether it did.
local function teleport_node(pos, user, pt, tool)
	local meta = pre_check(tool)
	local pname = user:get_player_name()
	if meta.save_block == nil then
		local old = minetest.get_node_or_nil(pos)
		if old ~= nil then
			-- Allow aquiring teleport only if source is allowed to be interacted by the player. (Except if they have server or protection_bypass privs)
			if not minetest.is_protected(pos, pname) or minetest.check_player_privs(pname, {server = true}) or minetest.check_player_privs(pname, {protection_bypass = true}) then
				meta.save_block = pos -- Store the pos table
				tool:set_metadata(minetest.serialize(meta)) -- Save it
				minetest.chat_send_player(pname, S("Aquired node at %s for teleport"):format(minetest.pos_to_string(pos)))
			else
				minetest.log("action", S("Player '%s' tried to move block %s by means of teleporter_tool:teleporter"):format(pname, minetest.pos_to_string(pos)))
				minetest.chat_send_player(pname, S("Node at %s can't be teleported."):format(minetest.pos_to_string(pos)))
			end
			return {action=true, use=false}
		else
			minetest.chat_send_player(pname, S("Old location at %s is unloaded, get closer."):format(minetest.pos_to_string(pos)))
			meta.save_block = nil -- Reset the teleport
			tool:set_metadata(minetest.serialize(meta)) -- Save it
			return {action=false, use=false}
		end
	else
		local old = minetest.get_node_or_nil(meta.save_block)
		local old_meta = minetest.get_meta(meta.save_block)
		old_meta = old_meta:to_table()
		if old ~= nil then
			local new = pt.above
			-- Allow teleport only if source and destination are allowed to be interacted by the player. (Except if they have server or protection_bypass privs)
			if not minetest.is_protected(meta.save_block, pname) and not minetest.is_protected(new, pname) or minetest.check_player_privs(pname, {server = true}) or minetest.check_player_privs(pname, {protection_bypass = true}) then
				minetest.remove_node(meta.save_block)
				minetest.add_node(new, old)
				local new_node = minetest.get_meta(new)
				new_node:from_table(old_meta)
				minetest.chat_send_player(pname, S("Teleported %s to %s."):format(minetest.pos_to_string(meta.save_block), minetest.pos_to_string(new)))
				meta.save_block = nil -- Reset the teleport
				tool:set_metadata(minetest.serialize(meta)) -- Save it
				return {action=true, use=true}
			else
				minetest.log("action", S("Player '%s' tried to move block %s to %s by means of teleporter_tool:teleporter"):format(pname, minetest.pos_to_string(meta.save_block), minetest.pos_to_string(new)))
				minetest.chat_send_player(pname, S("Node at %s can't be teleported to %s."):format(minetest.pos_to_string(meta.save_block), minetest.pos_to_string(new)))
				meta.save_block = nil -- Reset the teleport
				tool:set_metadata(minetest.serialize(meta)) -- Save it
			end
		else
			minetest.chat_send_player(pname, S("Old location at %s is unloaded, get closer."):format(minetest.pos_to_string(meta.save_block)))
			meta.save_block = nil -- Reset the teleport
			tool:set_metadata(minetest.serialize(meta)) -- Save it
			return {action=false, use=false}
		end
	end
	return {action=false, use=false}
end

-- Do the interaction. If reverse is true, the action pulling (otherwise it's
-- pushing.)
local function interact(tool, user, pointed_thing, reverse)
	local meta_updated = false
	if pointed_thing.type == "node" then
		local name = user and user:get_player_name() or ""
		local use_pos = pointed_thing.under
		local meta = pre_check(tool)
		local op = teleport_node(use_pos, user, pointed_thing, tool)
		if op.action then
			local sound = "teleporter_tool_pull"
			if meta.save_block ~= nil then
				sound = "teleporter_tool_push"
			end
			--minetest.chat_send_player(name, S("Playing sound '%s'"):format(sound))
			minetest.sound_play(sound, {
				pos = use_pos,
				gain = 0.2,
			}, true)
			-- Only remove wear if not in creative
			if not minetest.is_creative_enabled(name) and op.use then
				tool:add_wear(WEAR_PER_USE)
			end
		end
	end
	if meta_updated then
		tool:set_metadata(minetest.serialize(meta))
	end
	return tool
end

minetest.register_tool("teleporter_tool:teleporter", {
	description = S("Teleporter"),
	inventory_image = "teleporter_tool_teleporter.png",
	_mcl_toollike_wield = true,
	node_dig_prediction = "",
	on_place = function(tool, user, pointed_thing)
		return interact(tool, user, pointed_thing, true)
	end,
	on_use = function(tool, user, pointed_thing)
		return interact(tool, user, pointed_thing, false)
	end,
	after_use = function() return nil end, -- Do nothing.
})

local EXTRA_BLOCK = "default:diamond"
local STICK = "group:stick"
-- In case default isn't present then switch to mcl_core
if (not minetest.registered_items[EXTRA_BLOCK]) and minetest.registered_items["mcl_core:diamond"] then
	EXTRA_BLOCK = "mcl_core:diamond"
end

if minetest.registered_items["mesecons_pistons:piston_sticky_off"] then
	local PISTON = "mesecons_pistons:piston_sticky_off"
	minetest.register_craft({
		output = "teleporter_tool:teleporter",
		recipe = {
			{PISTON, EXTRA_BLOCK},
			{PISTON, STICK},
			{""    , STICK},
		},
	})
end
