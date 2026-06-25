import Foundation

enum ChatUIMockData {
    private static let emmaID = UUID(uuidString: "A1000001-0000-4000-8000-000000000001")!
    private static let markID = UUID(uuidString: "A1000002-0000-4000-8000-000000000002")!
    private static let mayaID = UUID(uuidString: "A1000003-0000-4000-8000-000000000003")!

    static let conversations: [ChatConversationPreview] = [
        ChatConversationPreview(
            id: emmaID,
            title: "Emma",
            lastMessageText: "Saturday works for me too!",
            lastSenderName: String(localized: "chats.you"),
            lastMessageAt: Date().addingTimeInterval(-1_200),
            unreadCount: 0
        ),
        ChatConversationPreview(
            id: markID,
            title: "Mark",
            lastMessageText: "Are you free for a walk by the canal?",
            lastSenderName: "Mark",
            lastMessageAt: Date().addingTimeInterval(-8_600),
            unreadCount: 2
        ),
        ChatConversationPreview(
            id: mayaID,
            title: "Maya",
            lastMessageText: nil,
            lastSenderName: nil,
            lastMessageAt: nil,
            unreadCount: 0
        )
    ]

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
            text: "Hey! I liked your mood tag — coffee sounds perfect.",
            createdAt: Date().addingTimeInterval(-7_200),
            isMine: false
        ),
        ChatMessage(
            id: UUID(uuidString: "B1000002-0000-4000-8000-000000000002")!,
            text: "Thanks! I know a cozy place near Vondelpark.",
            createdAt: Date().addingTimeInterval(-6_800),
            isMine: true
        ),
        ChatMessage(
            id: UUID(uuidString: "B1000003-0000-4000-8000-000000000003")!,
            text: "Want to grab coffee this weekend?",
            createdAt: Date().addingTimeInterval(-3_600),
            isMine: false
        ),
        ChatMessage(
            id: UUID(uuidString: "B1000004-0000-4000-8000-000000000004")!,
            text: "Sounds great — Saturday works for me.",
            createdAt: Date().addingTimeInterval(-1_800),
            isMine: true
        ),
        ChatMessage(
            id: UUID(uuidString: "B1000005-0000-4000-8000-000000000005")!,
            text: "Saturday works for me too!",
            createdAt: Date().addingTimeInterval(-1_200),
            isMine: false
        )
    ]

    private static let markThread: [ChatMessage] = [
        ChatMessage(
            id: UUID(uuidString: "C1000001-0000-4000-8000-000000000001")!,
            text: "Hi! We matched on the walk mood.",
            createdAt: Date().addingTimeInterval(-86_400),
            isMine: false
        ),
        ChatMessage(
            id: UUID(uuidString: "C1000002-0000-4000-8000-000000000002")!,
            text: "Nice to meet you — I love evening walks.",
            createdAt: Date().addingTimeInterval(-85_000),
            isMine: true
        ),
        ChatMessage(
            id: UUID(uuidString: "C1000003-0000-4000-8000-000000000003")!,
            text: "Are you free for a walk by the canal?",
            createdAt: Date().addingTimeInterval(-8_600),
            isMine: false
        )
    ]
}
