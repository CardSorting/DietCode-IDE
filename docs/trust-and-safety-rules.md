# Trust and Safety Rules

## Core trust rule

Nothing expensive, networked, destructive, or process-spawning happens unless the user asks.

## Startup rules

At launch, DietCode must not:

- Make network requests.
- Start a terminal.
- Spawn background processes.
- Scan a repository.
- Index files.
- Load extensions.
- Start AI services.
- Start hidden daemons.

## File safety

- Confirm before deleting files.
- Confirm before replacing unsaved editor contents.
- Warn before closing unsaved tabs.
- Keep unsaved text in memory if Save As is canceled.
- Show whether the file is saved.
- Explain save failures in plain language.

## Error message structure

Every user-facing error should include:

- What happened.
- Why it might have happened.
- What the user can try next.
- Whether their file is safe.
- Raw details when useful.

Example:

```text
Could not save file.
DietCode does not have permission to write to this location.
Try Save As and choose another folder.
Your changes are still open in DietCode.
Details: [system error]
```

## Run safety

- Never run code automatically.
- Show the command about to run.
- Show raw output and friendly explanation.
- Provide Stop when a process is running.
- Terminal starts only when user opens it.
