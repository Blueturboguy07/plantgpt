-- UI helper of tests/updater/live-proof-macos.sh (System Events). GitHub macOS runners only.
--
--   osascript ui.applescript list
--       one line per window of the processes that can show the proof's dialogs:
--       <process> TAB <window number> TAB <texts, " | " between> TAB <buttons, ", " between>
--   osascript ui.applescript click <process> <text in the window> <button>
--       clicks <button> in the first window of <process> whose texts contain <text>
--   osascript ui.applescript menu <bundle id> <menu item name prefix>
--       brings the app to the front and clicks the item of its app menu (the menu after the Apple menu)
--   osascript ui.applescript icons <Finder window name>
--       one line per element of that Finder window: <class> TAB <label> TAB <center x> TAB <center y>
--       (screen points, the coordinates of a mouse event)
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
	-- Every element of the window with a label and a place: <class> TAB <label> TAB <center x> TAB <center y>.
	-- The label is the name, else the value, else the description (Finder icon views differ by release).
	set out to ""
	tell application "System Events"
		tell process "Finder"
			set w to first window whose name is wname
			repeat with e in (entire contents of w)
				try
					set lbl to missing value
					try
						set lbl to name of e
					end try
					if lbl is missing value or lbl is "" then
						try
							set lbl to value of e
						end try
					end if
					if lbl is missing value or lbl is "" then
						try
							set lbl to description of e
						end try
					end if
					set p to position of e
					set z to size of e
					set out to out & (class of e as text) & tab & (lbl as text) & tab & ((item 1 of p) + (item 1 of z) div 2) & tab & ((item 2 of p) + (item 2 of z) div 2) & linefeed
				end try
			end repeat
		end tell
	end tell
	return out
end finderIcons
