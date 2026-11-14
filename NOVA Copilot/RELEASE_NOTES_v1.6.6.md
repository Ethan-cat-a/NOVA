# NOVA Copilot for macOS 1.6.6

## CS Agent

- Combines coding help, Word document creation/filling, and Agent tools in one mode. Older Coding, Word Doc and Agent chats migrate to CS Agent.
- Search source files inside folders you chose for My Documents. NOVA sends relevant excerpts only when you turn on My Documents for that request.
- Include a read-only Git status, unstaged diff summary and latest commit for a selected repository when you opt in for a message.
- Create or fill a Word document from CS Agent. Review and edit the draft before saving a `.docx` file.
- Search a question in Google Chrome, share the current Chrome page after reviewing its extracted text, open the selected project in Xcode, or open Microsoft Word.

## Local computer access

CS Agent does not receive unrestricted desktop control. Git access is read-only. Chrome page text is read only after you choose the action and review the preview. Xcode and Word actions open the selected project or app; they do not type or click in those apps. The existing server plugin registry remains allowlisted. NOVA does not apply code changes, run arbitrary shell commands, commit or push Git changes, or install third-party plugins.

Sharing a Chrome page requires allowing NOVA to control Google Chrome in macOS System Settings. Chrome must also have **View → Developer → Allow JavaScript from Apple Events** enabled. Page text remains local until you choose to attach the reviewed preview and send the message.
