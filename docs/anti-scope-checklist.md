# Anti-Scope Checklist

Reject these until later phases:

- Extension marketplace.
- Plugin API.
- Language server integration.
- Debug adapter protocol.
- Remote SSH.
- Dev containers.
- Cloud projects.
- Account login.
- Copilot clone.
- AI chat.
- Background embeddings.
- Project graph.
- Full semantic search.
- Automatic package manager detection.
- Complex settings sync.
- Custom theme marketplace.
- Startup terminal process.
- Startup repo-wide indexing.
- Hidden daemons.

Before adding any subsystem, ask:

1. Does this help the user edit, run, or understand code?
2. Can it be done manually for now?
3. Is this secretly an extension system?
4. Is this secretly an LSP system?
5. Is this secretly a build system?
6. Is this secretly VSCode again?
7. Can this wait until v2?
