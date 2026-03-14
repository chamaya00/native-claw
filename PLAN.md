# iOS On-Device LLM Chat App

## Project Overview

Build an iOS chat app that uses Apple's native Foundation Models framework for on-device LLM inference. The entire project must be manageable via CLI tools and GitHub Actions—no manual Xcode interaction required.

## Tech Stack

- **Project generation:** XcodeGen (YAML-based)
- **UI:** SwiftUI
- **LLM:** Apple Foundation Models framework (iOS 26+)
- **CI/CD:** GitHub Actions with Fastlane

## Directory Structure

```
LLMChat/
├── project.yml                 # XcodeGen config
├── Sources/
│   ├── App/
│   │   └── LLMChatApp.swift
│   ├── Views/
│   │   ├── ChatView.swift
│   │   └── MessageBubble.swift
│   ├── ViewModels/
│   │   └── ChatViewModel.swift
│   └── Services/
│       └── LLMService.swift
├── Resources/
│   ├── Assets.xcassets/
│   │   └── Contents.json
│   └── Info.plist
├── Gemfile                     # Fastlane dependency
├── fastlane/
│   ├── Fastfile
│   └── Appfile
└── .github/
    └── workflows/
        ├── generate.yml        # Generate .xcodeproj
        ├── build.yml           # Build and test
        └── deploy.yml          # TestFlight deployment
```

## Implementation Tasks

### 1. Create project.yml (XcodeGen config)

- App name: LLMChat
- Bundle ID: com.${DEVELOPMENT_TEAM}.llmchat
- Deployment target: iOS 26.0
- Swift version: 6.0
- Sources: Sources/**
- Resources: Resources/**
- Required frameworks: Foundation, SwiftUI, FoundationModels

### 2. Create LLMChatApp.swift

- Standard SwiftUI app entry point
- Launch ChatView as main view

### 3. Create ChatView.swift

- ScrollView with messages list
- Text input field at bottom
- Send button
- Display loading indicator during LLM generation

### 4. Create MessageBubble.swift

- Reusable view for chat bubbles
- Different styling for user vs assistant messages

### 5. Create ChatViewModel.swift

- @Observable class
- messages array of Message structs (id, role, content, timestamp)
- sendMessage() async function
- isGenerating state for loading UI

### 6. Create LLMService.swift

- Import FoundationModels
- Use LanguageModelSession for conversation
- Simple async function: generateResponse(prompt: String) async throws -> String
- Handle device capability check (LanguageModelSession.isAvailable)

### 7. Create Assets.xcassets/Contents.json

- Minimal asset catalog structure

### 8. Create Info.plist

- Standard iOS app plist
- Add NSAppTransportSecurity if needed

### 9. Create Gemfile

```ruby
source "https://rubygems.org"
gem "fastlane"
```

### 10. Create fastlane/Appfile

- app_identifier and team_id from environment variables

### 11. Create fastlane/Fastfile

- `generate_project` lane: runs xcodegen
- `build` lane: builds with gym
- `test` lane: runs tests with scan
- `beta` lane: uploads to TestFlight with pilot

### 12. Create .github/workflows/generate.yml

- Trigger: push to main (when project.yml changes)
- Runs on: macos-latest
- Steps: checkout, install xcodegen, run xcodegen, commit .xcodeproj

### 13. Create .github/workflows/build.yml

- Trigger: push to main
- Runs on: macos-latest
- Steps: checkout, run fastlane build

### 14. Create .github/workflows/deploy.yml

- Trigger: manual (workflow_dispatch) or tag push
- Runs on: macos-latest
- Secrets needed: APP_STORE_CONNECT_API_KEY, MATCH_PASSWORD
- Steps: checkout, setup certificates, run fastlane beta

## Code Requirements

- Use async/await throughout
- Handle errors gracefully with user-facing messages
- Show fallback message if device doesn't support on-device LLM
- Keep UI responsive during generation
- Minimal dependencies—Apple frameworks only

## Output

After completing all tasks, provide:

1. List of files created
2. Commands to generate project locally (for users with Mac)
3. Note that GitHub Actions will auto-generate .xcodeproj on push
