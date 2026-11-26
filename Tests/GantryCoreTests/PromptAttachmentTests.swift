import Foundation
import Testing
@testable import GantryCore

@Test func composesTextAndAttachments() {
    let attachments = [
        PromptAttachment(path: "/tmp/a.swift", name: "a.swift"),
        PromptAttachment(path: "/tmp/Sources", name: "Sources", isDirectory: true)
    ]

    let prompt = PromptAttachmentComposer.compose(
        text: "  Explain these.  ",
        attachments: attachments
    )

    #expect(prompt == """
    Explain these.

    Use these paths as context:
    - /tmp/a.swift
    - /tmp/Sources
    """)
}

@Test func composesAttachmentsWithoutText() {
    let attachment = PromptAttachment(path: "/tmp/a.swift", name: "a.swift")
    let prompt = PromptAttachmentComposer.compose(text: " \n ", attachments: [attachment])
    #expect(prompt == """
    Use this path as context:
    - /tmp/a.swift
    """)
}

@Test func composerDeduplicatesAttachmentPaths() {
    let attachments = [
        PromptAttachment(path: "/tmp/a.swift", name: "a.swift"),
        PromptAttachment(path: "/tmp/b.swift", name: "b.swift"),
        PromptAttachment(path: "/tmp/a.swift", name: "a.swift")
    ]
    let prompt = PromptAttachmentComposer.compose(text: "", attachments: attachments)
    #expect(prompt == """
    Use these paths as context:
    - /tmp/a.swift
    - /tmp/b.swift
    """)
}

@Test func mergingKeepsExistingOrderAndSkipsDuplicates() {
    let existing = [PromptAttachment(path: "/tmp/a.swift", name: "a.swift")]
    let added = [
        PromptAttachment(path: "/tmp/a.swift", name: "a.swift"),
        PromptAttachment(path: "/tmp/b.swift", name: "b.swift")
    ]

    #expect(PromptAttachment.merging(existing, with: added) == [
        PromptAttachment(path: "/tmp/a.swift", name: "a.swift"),
        PromptAttachment(path: "/tmp/b.swift", name: "b.swift")
    ])
}

@Test func makeFromURLsKeepsExistingFilesAndFolders() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Gantry-attachments-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appendingPathComponent("Context.swift")
    try "let value = 1\n".write(to: file, atomically: true, encoding: .utf8)
    let folder = root.appendingPathComponent("Sources", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let missing = root.appendingPathComponent("Missing.swift")

    let attachments = PromptAttachment.make(from: [file, folder, missing, file])

    #expect(attachments.count == 2)
    #expect(attachments[0].path == file.standardizedFileURL.path)
    #expect(attachments[0].name == "Context.swift")
    #expect(attachments[0].isDirectory == false)
    #expect(attachments[1].path == folder.standardizedFileURL.path)
    #expect(attachments[1].name == "Sources")
    #expect(attachments[1].isDirectory)
}

@Test func imagePathsRoundTripThroughComposedPrompt() {
    let prompt = PromptAttachmentComposer.compose(text: "Look", attachments: [
        PromptAttachment(path: "/tmp/shot.PNG", name: "shot.PNG"),
        PromptAttachment(path: "/tmp/a.swift", name: "a.swift"),
        PromptAttachment(path: "/tmp/photos.png", name: "photos.png", isDirectory: true)
    ])
    #expect(PromptAttachmentComposer.imagePaths(in: prompt) == ["/tmp/shot.PNG", "/tmp/photos.png"])
    #expect(PromptAttachment(path: "/tmp/photos.png", name: "p", isDirectory: true).isImage == false)
    #expect(PromptAttachmentComposer.imagePaths(in: "- not/absolute.png\nplain.png") == [])
}

@Test func savesPastedImageWithUserOnlyPermissions() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Gantry-paste-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let attachment = try PromptAttachment.savePastedImage(Data([1, 2, 3]), in: root)

    #expect(attachment.isImage)
    #expect(try Data(contentsOf: URL(fileURLWithPath: attachment.path)) == Data([1, 2, 3]))
    let mode = try FileManager.default.attributesOfItem(atPath: attachment.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
}

@Test func userMessageInlinesAttachedImages() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Gantry-inline-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let png = root.appendingPathComponent("a.png")
    try Data([9, 8, 7]).write(to: png)
    let heic = root.appendingPathComponent("b.heic")
    try Data([1]).write(to: heic)

    let prompt = PromptAttachmentComposer.compose(text: "See", attachments: [
        PromptAttachment(path: png.path, name: "a.png"),
        PromptAttachment(path: heic.path, name: "b.heic"),
        PromptAttachment(path: root.appendingPathComponent("gone.png").path, name: "gone.png")
    ])
    let json = try JSONSerialization.jsonObject(with: ClaudeWire.userMessage(prompt)) as? [String: Any]
    let content = (json?["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []

    #expect(content.count == 2)
    #expect(content[0]["text"] as? String == prompt)
    let source = content[1]["source"] as? [String: String]
    #expect(content[1]["type"] as? String == "image")
    #expect(source?["media_type"] == "image/png")
    #expect(source?["data"] == Data([9, 8, 7]).base64EncodedString())
}

@Test func removesOnlyStalePastedImages() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("Gantry-clean-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let old = try PromptAttachment.savePastedImage(Data([1]), in: root)
    let fresh = try PromptAttachment.savePastedImage(Data([2]), in: root)
    try FileManager.default.setAttributes(
        [.modificationDate: Date.now.addingTimeInterval(-40 * 24 * 3600)], ofItemAtPath: old.path
    )

    PromptAttachment.removePastedImages(in: root, olderThan: 30 * 24 * 3600)

    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: fresh.path))
}

@Test func composerWithNoAttachmentsLeavesTextAlone() {
    #expect(PromptAttachmentComposer.compose(text: "  Hello  ", attachments: []) == "Hello")
}
