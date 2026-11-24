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

@Test func composerWithNoAttachmentsLeavesTextAlone() {
    #expect(PromptAttachmentComposer.compose(text: "  Hello  ", attachments: []) == "Hello")
}
