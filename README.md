# Friday

*A local-first macOS personal AI assistant.*

![Platform](https://img.shields.io/badge/platform-macOS-blue)
![UI](https://img.shields.io/badge/UI-SwiftUI-lightgrey)
![Assistant](https://img.shields.io/badge/assistant-screen--aware-purple)
![Storage](https://img.shields.io/badge/storage-local--first-green)

Friday is a native macOS assistant built around a translucent island interface. It helps decide what to focus on next, answers questions from the Home screen, reads local Calendar and Mail signals, remembers useful preferences locally, and can use screen context when asked.

## Features

- Frosted-glass SwiftUI interface with independent resizable islands
- Home focus dashboard with calendar, mail, map, and recommendation context
- Local memory persisted under Application Support
- OpenAI-backed assistant responses when an API key is configured
- Apple Foundation Models fallback path when available
- Screen-aware prompt island from the menu bar or `Command + Option + F`
- Markdown rendering with headings, lists, tables, and syntax-highlighted code blocks
- Built-in market view with quotes, news, and AI investment overview
- macOS widget showing Friday's next recommended step
- Local macOS notifications for meaningful focus changes

## Privacy

Friday is designed to keep personal state local by default.

- OpenAI API keys are stored in macOS Keychain, not in the repository.
- Memory is stored locally in Application Support.
- Full email bodies, chat logs, generated files, and API keys should not be committed.
- `.env` files are ignored by Git.

Before publishing this repository, the local tree and local `main` history were scanned for API keys, bearer tokens, private keys, credential files, `.env` files, provisioning profiles, and assistant state JSON.

## Requirements

- macOS with Xcode installed
- Apple Mail and Calendar permissions for local context features
- Screen Recording permission for screen-aware answers
- Optional: OpenAI API key configured in Friday Settings

## Build

```bash
xcodebuild -scheme Friday -project Friday.xcodeproj -configuration Debug build
```

## Notes

Friday currently suggests actions rather than automatically changing calendars, tasks, or email state without user intent. Browser and screen-aware features are intended to be explicit: Friday should only open or inspect browser context when asked.
