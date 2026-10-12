on run arguments
    set mountedFolder to POSIX file (item 1 of arguments) as alias
    set backgroundFile to POSIX file ((item 1 of arguments) & "/.background/background.tiff") as alias
    tell application "Finder"
        ignoring application responses
            open mountedFolder
        end ignoring
        activate
        delay 1
        set imageWindow to front Finder window
        if (POSIX path of (target of imageWindow as alias)) is not ((item 1 of arguments) & "/") then error "Unexpected Finder window target"
        set rootFolder to target of imageWindow
        set current view of imageWindow to icon view
        set toolbar visible of imageWindow to false
        set statusbar visible of imageWindow to false
        set bounds of imageWindow to {400, 240, 1040, 662}
        tell icon view options of imageWindow
            set arrangement to not arranged
            set icon size to 112
            set text size to 13
            set label position to bottom
            set background picture to backgroundFile
        end tell
        set position of item "Peek for Codex.app" of rootFolder to {170, 210}
        set position of item "Applications" of rootFolder to {470, 210}
        update rootFolder without registering applications
        delay 1
        close imageWindow
        delay 1
    end tell
end run
