import Foundation
import SwiftData

enum AppModelContainerFactory {

    static func makeSharedContainer() -> ModelContainer {
        let schema = Schema([
            Item.self,
            LocalMessengerConversation.self,
            LocalMessengerMessage.self,
            LocalMessengerAttachment.self,
            LocalMessengerReactionAggregate.self,
            LocalMessengerReceipt.self,
            LocalMessengerSyncMetadata.self,
            LocalMessengerOutboxItem.self,
            LocalMessengerPendingMedia.self,
        ])

        let storeURL = persistentStoreURL
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            MessengerDiagnostics.event(
                .messengerSwiftDataContainerLoadFailed,
                metadata: [
                    "errorCategory": MessengerDiagnostics.sanitizeError(error),
                    "storeName": storeURL.lastPathComponent
                ]
            )

            removePersistentStoreFiles(at: storeURL)

            do {
                let container = try ModelContainer(for: schema, configurations: [configuration])
                MessengerDiagnostics.event(
                    .messengerSwiftDataContainerRecoveredAfterSchemaMismatch,
                    metadata: [
                        "storeName": storeURL.lastPathComponent,
                        "schemaVersion": "\(MessengerPersistence.schemaVersion)"
                    ]
                )
                return container
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    private static var persistentStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("JustTwo", isDirectory: true)
            .appendingPathComponent("App.store", isDirectory: false)
    }

    private static func removePersistentStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        let relatedPaths = [
            storeURL.path,
            storeURL.path + "-wal",
            storeURL.path + "-shm"
        ]

        for path in relatedPaths where fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
    }
}
