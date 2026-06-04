# Command Catalog

Every command should have a plain English label, menu location, optional shortcut, command palette entry, description, enabled state, and risk level.

## Initial commands

| Command | Menu | Shortcut | Palette label | Description | Phase |
|---|---|---|---|---|---|
| New File | File > New File | Cmd/Ctrl+N | New File | Start with a blank file. | 1A |
| Open File | File > Open File | Cmd/Ctrl+O | Open File | Edit an existing file. | 1A |
| Save | File > Save | Cmd/Ctrl+S | Save | Save changes to the current file. | 1A |
| Save As | File > Save As | Cmd/Ctrl+Shift+S | Save As | Save this file to a chosen location. | 1A |
| Close Tab | File > Close Tab | Cmd/Ctrl+W | Close Tab | Close the current file, asking first if unsaved. | 1B |
| Find | Edit > Find | Cmd/Ctrl+F | Find | Find text in the current file. | 1B |
| Replace | Edit > Replace | Cmd/Ctrl+H | Replace | Replace text in the current file. | 2 |
| Go to Line | Go > Go to Line | Cmd/Ctrl+G | Go to Line | Jump to a line number. | 2 |
| Command Palette | View > Command Palette | Cmd/Ctrl+Shift+P | Command Palette | Search available commands. | 2 |
| Toggle Sidebar | View > Toggle Sidebar | Cmd/Ctrl+B | Toggle Sidebar | Show or hide the sidebar. | 1B |
| Open Folder | File > Open Folder | Cmd/Ctrl+Shift+O | Open Folder | See a folder of files on the left. | 2 |
| Search Folder | Search panel | none | Search Folder | Search inside the opened folder. | 3 |
| Run Current File | Run > Run Current File | F5 or Cmd/Ctrl+R | Run Current File | Run the current file when supported. | 3 |
| Toggle Terminal | Terminal > Toggle Terminal | Ctrl+` | Toggle Terminal | Open or close the terminal. | 3 |
| Open Settings | App/Menu > Settings | Cmd/Ctrl+, | Open Settings | Change theme, font size, and editor options. | 1B |
| Open Welcome | Help > Welcome | none | Open Welcome | Return to the welcome screen. | 1A |
| Learn DietCode Basics | Help > Learn DietCode Basics | none | Learn DietCode Basics | Start or restart the optional beginner guide. | 4 |

## Command safety requirements

- Destructive commands require confirmation.
- Disabled commands should explain why when practical.
- Commands that spawn processes must be visible and user-triggered.
- Command names use plain English.