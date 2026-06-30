import Foundation

enum ChatUIMockData {
    private static let emmaID = UUID(uuidString: "A1000001-0000-4000-8000-000000000001")!
    private static let markID = UUID(uuidString: "A1000002-0000-4000-8000-000000000002")!
    private static let mayaID = UUID(uuidString: "A1000003-0000-4000-8000-000000000003")!
    private static let elizabethID = UUID(uuidString: "A1000004-0000-4000-8000-000000000004")!
    private static let alexID = UUID(uuidString: "A1000005-0000-4000-8000-000000000005")!

    static let conversations: [ChatConversationPreview] = [
        ChatConversationPreview(
            id: emmaID,
            title: "Emma",
            otherParticipantProfileID: UUID(uuidString: "F1000001-0000-4000-8000-000000000001"),
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: "Saturday works for me too!",
            lastSenderName: "You",
            lastMessageAt: Date().addingTimeInterval(-1_200),
            unreadCount: 0
        ),
        ChatConversationPreview(
            id: markID,
            title: "Mark",
            otherParticipantProfileID: UUID(uuidString: "F1000002-0000-4000-8000-000000000002"),
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: "Are you free for a walk by the canal?",
            lastSenderName: "Mark",
            lastMessageAt: Date().addingTimeInterval(-8_600),
            unreadCount: 2
        ),
        ChatConversationPreview(
            id: elizabethID,
            title: "Elizabeth",
            otherParticipantProfileID: UUID(uuidString: "F1000003-0000-4000-8000-000000000003"),
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: "That rooftop bar sounds perfect.",
            lastSenderName: "Elizabeth",
            lastMessageAt: Date().addingTimeInterval(-21_000),
            unreadCount: 5
        ),
        ChatConversationPreview(
            id: alexID,
            title: "Alex",
            otherParticipantProfileID: UUID(uuidString: "F1000004-0000-4000-8000-000000000004"),
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: "Message deleted",
            lastSenderName: "You",
            lastMessageAt: Date().addingTimeInterval(-96_000),
            unreadCount: 0
        ),
        ChatConversationPreview(
            id: mayaID,
            title: "Maya",
            otherParticipantProfileID: UUID(uuidString: "F1000005-0000-4000-8000-000000000005"),
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: nil,
            lastSenderName: nil,
            lastMessageAt: nil,
            unreadCount: 0
        )
    ]

    static let empty: [ChatConversationPreview] = []

    static var richThread: [ChatMessage] {
        emmaThread
    }

    static func messages(for conversationID: UUID) -> [ChatMessage] {
        switch conversationID {
        case emmaID:
            return emmaThread
        case markID:
            return markThread
        default:
            return []
        }
    }

    private static let emmaThread: [ChatMessage] = [
        ChatMessage(
            id: UUID(uuidString: "B1000001-0000-4000-8000-000000000001")!,
            displayText: "Hey! I liked your mood tag — coffee sounds perfect.",
            rawBody: "Hey! I liked your mood tag — coffee sounds perfect.",
            createdAt: Date().addingTimeInterval(-7_200),
            isMine: false,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: []
        ),
        ChatMessage(
            id: UUID(uuidString: "B1000002-0000-4000-8000-000000000002")!,
            displayText: "Want to grab coffee this weekend?",
            rawBody: "Want to grab coffee this weekend?",
            createdAt: Date().addingTimeInterval(-3_600),
            isMine: false,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: [
                ChatMessageReaction(emoji: "👍", count: 1, reactedByMe: true)
            ]
        ),
        ChatMessage(
            id: UUID(uuidString: "B1000003-0000-4000-8000-000000000003")!,
            displayText: "Sounds great — Saturday works for me.",
            rawBody: "Sounds great — Saturday works for me.",
            createdAt: Date().addingTimeInterval(-1_800),
            isMine: true,
            isDeleted: false,
            isEdited: false,
            replyPreview: ChatReplyPreview(
                id: UUID(uuidString: "B1000002-0000-4000-8000-000000000002")!,
                body: "Want to grab coffee this weekend?",
                isDeleted: false
            ),
            reactions: [
                ChatMessageReaction(emoji: "❤️", count: 1, reactedByMe: false)
            ]
        ),
        ChatMessage(
            id: UUID(uuidString: "B1000004-0000-4000-8000-000000000004")!,
            displayText: "Saturday works for me too!",
            rawBody: "Saturday works for me too!",
            createdAt: Date().addingTimeInterval(-1_200),
            isMine: false,
            isDeleted: false,
            isEdited: true,
            replyPreview: nil,
            reactions: [
                ChatMessageReaction(emoji: "👍", count: 2, reactedByMe: true),
                ChatMessageReaction(emoji: "😂", count: 1, reactedByMe: false)
            ]
        )
    ]

    private static let markThread: [ChatMessage] = [
        ChatMessage(
            id: UUID(uuidString: "C1000003-0000-4000-8000-000000000003")!,
            displayText: "Are you free for a walk by the canal?",
            rawBody: "Are you free for a walk by the canal?",
            createdAt: Date().addingTimeInterval(-8_600),
            isMine: false,
            isDeleted: false,
            isEdited: false,
            replyPreview: nil,
            reactions: []
        )
    ]
}
