import Foundation
import SwiftData

enum MessengerPersistence {
    static let syncMetadataGlobalID = "global"
    static let schemaVersion = 3

    static var messengerSchema: Schema {
        Schema([
            LocalMessengerConversation.self,
            LocalMessengerMessage.self,
            LocalMessengerAttachment.self,
            LocalMessengerReactionAggregate.self,
            LocalMessengerReceipt.self,
            LocalMessengerSyncMetadata.self,
            LocalMessengerOutboxItem.self,
        ])
    }

    static func makeModelContainer(inMemoryOnly: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "MessengerLocalStore",
            schema: messengerSchema,
            isStoredInMemoryOnly: inMemoryOnly
        )

        return try ModelContainer(
            for: messengerSchema,
            configurations: [configuration]
        )
    }

    static func messengerModelTypes() -> [any PersistentModel.Type] {
        [
            LocalMessengerConversation.self,
            LocalMessengerMessage.self,
            LocalMessengerAttachment.self,
            LocalMessengerReactionAggregate.self,
            LocalMessengerReceipt.self,
            LocalMessengerSyncMetadata.self,
            LocalMessengerOutboxItem.self,
        ]
    }
}
