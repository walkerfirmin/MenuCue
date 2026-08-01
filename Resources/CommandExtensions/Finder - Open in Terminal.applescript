-- Finder - Open in Terminal
-- Opens the front Finder window's folder in Terminal.

tell application "Finder"
	if (count of windows) is 0 then return
	set targetPath to POSIX path of (target of front window as alias)
end tell

tell application "Terminal"
	activate
	do script "cd " & quoted form of targetPath
end tell
