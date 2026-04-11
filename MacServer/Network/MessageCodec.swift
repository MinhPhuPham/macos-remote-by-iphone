// Re-export: The server uses the shared MessageCodec.
// This file exists so the Xcode target can reference it locally.
// In a workspace setup, import MyRemoteShared instead.

// When using a shared framework, remove this file and add
// `import MyRemoteShared` at the top of files that need the codec.

// For now, the shared sources are at:
//   MyRemoteShared/Sources/MessageCodec.swift
//   MyRemoteShared/Sources/Protocol.swift
//   MyRemoteShared/Sources/Constants.swift
//   MyRemoteShared/Sources/KeyCodeMap.swift
