-- UI helper of tests/updater/live-proof-macos.sh (System Events). GitHub macOS runners only.
--
--   osascript ui.applescript list
--       one line per window of the processes that can show the proof's dialogs:
--       <process> TAB <window number> TAB <texts, " | " between> TAB <buttons, ", " between>
--   osascript ui.applescript click <process> <text in the window> <button>
--       clicks <button> in the first window of <process> whose texts contain <text>
--   osascript ui.applescript menu <bundle id> <menu item name prefix>
--       brings the app to the front and clicks the item of its app menu (the menu after the Apple menu)
--   osascript ui.applescript icons <disk name>
--       where the icons of the disk's Finder window are: Finder's item positions, the window's place
--       (see finderIcons; screen points = mouse event coordinates)
--   osascript ui.applescript axdump <window name>
--       every accessibility element of that Finder window with its label and center
--
-- PlantGPT shows its questions with the dialog plugin (rfd). With no parent window, rfd uses
-- CFUserNotificationDisplayAlert, so macOS draws them in UserNotificationCenter, not in the app.
-- The Gatekeeper question of the first launch belongs to CoreServicesUIAgent.

on run argv
	set cmd to item 1 of argv
	if cmd is "list" then return listWindows()
	if cmd is "click" then return clickButton(item 2 of argv, item 3 of argv, item 4 of argv)
	if cmd is "menu" then return clickMenu(item 2 of argv, item 3 of argv)
	if cmd is "icons" then return finderIcons(item 2 of argv)
	if cmd is "axdump" then return axDump(item 2 of argv)
	error "unknown command " & cmd
end run

on procNames()
	return {"UserNotificationCenter", "CoreServicesUIAgent", "PlantGPT", "plantgpt"}
end procNames

on textsOf(w)
	set out to ""
	tell application "System Events"
		try
			set els to entire contents of w
			repeat with e in els
				try
					set c to class of e
					if c is static text or c is text area or c is text field then
						set v to value of e
						if v is not missing value then set out to out & (v as text) & " | "
					end if
				end try
			end repeat
		end try
	end tell
	return out
end textsOf

on buttonsOf(w)
	set out to ""
	tell application "System Events"
		try
			repeat with b in (buttons of w)
				set out to out & (name of b as text) & ", "
			end repeat
		end try
	end tell
	return out
end buttonsOf

on listWindows()
	set out to ""
	tell application "System Events"
		repeat with pn in my procNames()
			set pname to pn as text
			if exists process pname then
				set i to 0
				repeat with w in (windows of process pname)
					set i to i + 1
					set out to out & pname & tab & i & tab & my textsOf(w) & tab & my buttonsOf(w) & linefeed
				end repeat
			end if
		end repeat
	end tell
	return out
end listWindows

on clickButton(pname, needle, btn)
	tell application "System Events"
		if not (exists process pname) then return "no process " & pname
		repeat with w in (windows of process pname)
			if (my textsOf(w)) contains needle then
				click button btn of w
				return "clicked " & btn
			end if
		end repeat
	end tell
	return "not found"
end clickButton

on clickMenu(bid, prefix)
	tell application "System Events"
		set p to first process whose bundle identifier is bid
		set frontmost of p to true
		delay 1
		set appMenu to menu 1 of menu bar item 2 of menu bar 1 of p
		set target to first menu item of appMenu whose name starts with prefix
		set n to name of target
		click target
		return "clicked " & n
	end tell
end clickMenu

on finderIcons(wname)
	-- Rows <kind> TAB <label> TAB <x> TAB <y>, every step in its own try (errors are rows too):
	--   finder   an item of the disk and its icon position in the window's content (Finder scripting)
	--   bounds   the left and top of the disk's Finder window (Finder scripting)
	--   window   the window's position on the screen; content: the position of its scroll area
	set out to ""
	try
		tell application "Finder"
			set d to disk wname
			repeat with x in (every item of d)
				set p to position of x
				set out to out & "finder" & tab & (name of x) & tab & (item 1 of p) & tab & (item 2 of p) & linefeed
			end repeat
			set b to bounds of container window of d
			set out to out & "bounds" & tab & wname & tab & (item 1 of b) & tab & (item 2 of b) & linefeed
		end tell
	on error m
		set out to out & "error" & tab & "Finder: " & m & linefeed
	end try
	try
		tell application "System Events"
			tell process "Finder"
				set w to window wname
				set p to position of w
				set out to out & "window" & tab & wname & tab & (item 1 of p) & tab & (item 2 of p) & linefeed
				try
					set p to position of scroll area 1 of w
					set out to out & "content" & tab & wname & tab & (item 1 of p) & tab & (item 2 of p) & linefeed
				end try
			end tell
		end tell
	on error m
		set out to out & "error" & tab & "System Events: " & m & linefeed
	end try
	return out
end finderIcons

on axDump(wname)
	-- Every element of the window: ax:<role> TAB <label> TAB <center x> TAB <center y> (can be slow).
	set out to ""
	try
		tell application "System Events"
			tell process "Finder"
				set w to window wname
				repeat with e in (entire contents of w)
					try
						set c to (role of e) as text
						set lbl to ""
						try
							set lbl to (name of e) as text
						end try
						if lbl is "" or lbl is "missing value" then
							try
								set lbl to (value of e) as text
							end try
						end if
						if lbl is "" or lbl is "missing value" then
							try
								set lbl to (description of e) as text
							end try
						end if
						set p to position of e
						set z to size of e
						set out to out & "ax:" & c & tab & lbl & tab & ((item 1 of p) + (item 1 of z) div 2) & tab & ((item 2 of p) + (item 2 of z) div 2) & linefeed
					end try
				end repeat
			end tell
		end tell
	on error m
		set out to out & "error" & tab & "System Events: " & m & linefeed
	end try
	return out
end axDump
