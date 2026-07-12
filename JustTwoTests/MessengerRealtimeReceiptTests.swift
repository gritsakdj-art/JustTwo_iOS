import Foundation
import Testing
@testable import JustTwo

@MainActor
@Suite("Messenger Realtime Receipt Tests", .serialized)
struct MessengerRealtimeReceiptTests {
    private let conversationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let ownerProfileID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private let counterpartyProfileID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    private let messageA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let messageB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let messageC = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    @Test("canonical conversation.delivered decodes")
    func canonicalConversationDeliveredDecodes() throws {
        let event = try decodeEvent("""
        {
          "type": "conversation.delivered",
          "conversationID": "\(conversationID.uuidString)",
          "payload": {
            "profileID": "\(counterpartyProfileID.uuidString)",
            "messageID": "\(messageB.uuidString)",
            "lastDeliveredAt": "2026-06-26T13:18:31Z"
          }
        }
        """)

        guard case .conversationDelivered(let id, let payload) = event else {
            Issue.record("Expected conversation.delivered")
            return
        }
        #expect(id == conversationID)
        #expect(payload.profileID == counterpartyProfileID)
        #expect(payload.messageID == messageB)
    }

    @Test("canonical conversation.read decodes")
    func canonicalConversationReadDecodes() throws {
        let event = try decodeEvent("""
        {
          "type": "conversation.read",
          "conversationID": "\(conversationID.uuidString)",
          "payload": {
            "profileID": "\(counterpartyProfileID.uuidString)",
            "messageID": "\(messageB.uuidString)",
            "lastReadAt": "2026-06-26T13:18:32Z"
          }
        }
        """)

        guard case .conversationRead(let id, let payload) = event else {
            Issue.record("Expected conversation.read")
            return
        }
        #expect(id == conversationID)
        #expect(payload.profileID == counterpartyProfileID)
        #expect(payload.messageID == messageB)
    }

    @Test("malformed UUID is rejected safely")
    func malformedUUIDRejectedSafely() {
        let data = Data("""
        {
          "type": "conversation.read",
          "conversationID": "not-a-uuid",
          "payload": {
            "profileID": "\(counterpartyProfileID.uuidString)",
            "messageID": "\(messageB.uuidString)"
          }
        }
        """.utf8)

        #expect(throws: (any Error).self) {
            _ = try JSONCoding.decoder.decode(RealtimeEventDTO.self, from: data)
        }
    }

    @Test("counterparty delivered boundary upgrades outgoing prefix")
    func counterpartyDeliveredUpgradesOutgoingPrefix() async throws {
        let store = makeStore()
        try await seedConversation(store: store)
        try await seedOutgoingMessages(store: store)

        let result = try await store.applyRealtimeReceipt(
            ownerProfileID: ownerProfileID,
            conversationID: conversationID,
            participantProfileID: counterpartyProfileID,
            kind: .delivered,
            boundaryMessageID: messageB
        )

        #expect(result.didAdvanceParticipantBoundary)
        #expect(result.updatedMessageCount == 2)
        #expect(result.targetMessageFound)

        let messages = try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil)
        let byID = Dictionary(uniqueKeysWithValues: messages.compactMap { snapshot -> (UUID, String?)? in
            guard let id = UUID(uuidString: snapshot.id) else { return nil }
            return (id, snapshot.deliveryStatus)
        })

        #expect(byID[messageA] == MessageDeliveryStatus.delivered.rawValue)
        #expect(byID[messageB] == MessageDeliveryStatus.delivered.rawValue)
        #expect(byID[messageC] == MessageDeliveryStatus.sent.rawValue)
    }

    @Test("counterparty read boundary upgrades delivered and implies delivered")
    func counterpartyReadUpgradesPrefix() async throws {
        let store = makeStore()
        try await seedConversation(store: store)
        try await seedOutgoingMessages(store: store)

        _ = try await store.applyRealtimeReceipt(
            ownerProfileID: ownerProfileID,
            conversationID: conversationID,
            participantProfileID: counterpartyProfileID,
            kind: .read,
            boundaryMessageID: messageB
        )

        let messages = try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil)
        let byID = Dictionary(uniqueKeysWithValues: messages.compactMap { snapshot -> (UUID, String?)? in
            guard let id = UUID(uuidString: snapshot.id) else { return nil }
            return (id, snapshot.deliveryStatus)
        })

        #expect(byID[messageA] == MessageDeliveryStatus.read.rawValue)
        #expect(byID[messageB] == MessageDeliveryStatus.read.rawValue)
        #expect(byID[messageC] == MessageDeliveryStatus.sent.rawValue)
    }

    @Test("late delivered after read does not regress")
    func lateDeliveredAfterReadDoesNotRegress() async throws {
        let store = makeStore()
        try await seedConversation(store: store)
        try await seedOutgoingMessages(store: store)

        _ = try await store.applyRealtimeReceipt(
            ownerProfileID: ownerProfileID,
            conversationID: conversationID,
            participantProfileID: counterpartyProfileID,
            kind: .read,
            boundaryMessageID: messageC
        )

        let stale = try await store.applyRealtimeReceipt(
            ownerProfileID: ownerProfileID,
            conversationID: conversationID,
            participantProfileID: counterpartyProfileID,
            kind: .delivered,
            boundaryMessageID: messageB
        )

        #expect(stale == .noop)

        let messages = try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil)
        let byID = Dictionary(uniqueKeysWithValues: messages.compactMap { snapshot -> (UUID, String?)? in
            guard let id = UUID(uuidString: snapshot.id) else { return nil }
            return (id, snapshot.deliveryStatus)
        })
        #expect(byID[messageC] == MessageDeliveryStatus.read.rawValue)
    }

    @Test("self-echo updates participant receipt without promoting own outgoing ticks")
    func selfEchoDoesNotPromoteOutgoingMessages() async throws {
        let store = makeStore()
        try await seedConversation(store: store)
        try await seedOutgoingMessages(store: store)

        let result = try await store.applyRealtimeReceipt(
            ownerProfileID: ownerProfileID,
            conversationID: conversationID,
            participantProfileID: ownerProfileID,
            kind: .read,
            boundaryMessageID: messageB
        )

        #expect(result.didAdvanceParticipantBoundary)
        #expect(result.updatedMessageCount == 0)
        #expect(result.updatedConversationPreview == false)

        let messages = try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil)
        #expect(messages.allSatisfy { $0.deliveryStatus == MessageDeliveryStatus.sent.rawValue })
    }

    @Test("target missing schedules repair without unsafe updates")
    func targetMissingRequiresRepair() async throws {
        let store = makeStore()
        try await seedConversation(store: store)

        let result = try await store.applyRealtimeReceipt(
            ownerProfileID: ownerProfileID,
            conversationID: conversationID,
            participantProfileID: counterpartyProfileID,
            kind: .delivered,
            boundaryMessageID: messageB
        )

        #expect(result.requiresSyncRepair)
        #expect(result.updatedMessageCount == 0)
        #expect(try await store.fetchLocalMessages(conversationID: conversationID, limit: 10, before: nil).isEmpty)
    }

    @Test("ChatsView preview updates for outgoing last message")
    func chatsPreviewUpdatesForOutgoingLastMessage() async throws {
        let list = ConversationListViewModel.shared
        list.reset()
        let preview = ChatConversationPreview(
            id: conversationID,
            title: "Taylor",
            otherParticipantProfileID: counterpartyProfileID,
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: "Hello",
            lastSenderName: String(localized: "chats.you"),
            lastMessageAt: isoDate("2026-06-26T13:18:32Z"),
            unreadCount: 0,
            lastOutgoingDeliveryStatus: .sent
        )
        list.testingReplaceConversations([preview])

        let applied = list.applyRealtimeOutgoingDeliveryStatus(
            conversationID: conversationID,
            deliveryStatus: .read,
            ownerProfileID: ownerProfileID
        )

        #expect(applied)
        #expect(list.conversations.first?.lastOutgoingDeliveryStatus == .read)
        #expect(list.conversations.first?.lastMessageAt == preview.lastMessageAt)
    }

    @Test("incoming last preview does not adopt outgoing receipt status")
    func incomingPreviewDoesNotAdoptOutgoingReceipt() {
        let list = ConversationListViewModel.shared
        list.reset()
        let preview = ChatConversationPreview(
            id: conversationID,
            title: "Taylor",
            otherParticipantProfileID: counterpartyProfileID,
            avatarURL: nil,
            avatarPhotoID: nil,
            lastMessageText: "Hello",
            lastSenderName: "Taylor",
            lastMessageAt: isoDate("2026-06-26T13:18:32Z"),
            unreadCount: 1
        )
        list.testingReplaceConversations([preview])

        let applied = list.applyRealtimeOutgoingDeliveryStatus(
            conversationID: conversationID,
            deliveryStatus: .read,
            ownerProfileID: ownerProfileID
        )

        #expect(!applied)
        #expect(list.conversations.first?.lastOutgoingDeliveryStatus == nil)
    }

    @Test("realtime receipt handler does not schedule delivery ack")
    func realtimeReceiptDoesNotScheduleDeliveryAck() async {
        let coordinator = ConversationDeliveryAckCoordinator.makeForTesting()
        var deliveredCalls = 0
        coordinator.markDeliveredHandler = { _, _ in
            deliveredCalls += 1
        }

        MessengerRealtimeReceiptCoordinator.shared.handleConversationDelivered(
            conversationID: conversationID,
            payload: ConversationDeliveredPayload(
                profileID: counterpartyProfileID,
                lastDeliveredAt: isoDate("2026-06-26T13:18:31Z"),
                messageID: messageB
            )
        )

        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(deliveredCalls == 0)
        _ = coordinator
    }

    @MainActor
    @Test("logout reset cancels in-flight receipt apply before mutating next account")
    func logoutResetCancelsInFlightReceiptApply() async throws {
        let coordinator = MessengerRealtimeReceiptCoordinator.shared
        coordinator.reset()

        try await MessengerLocalStore.shared.upsertConversations([try seedConversationDTO()])
        try await MessengerLocalStore.shared.upsertMessages(
            [
                makeOutgoingMessage(id: messageA, createdAt: "2026-06-26T13:18:31Z", body: "A"),
                makeOutgoingMessage(id: messageB, createdAt: "2026-06-26T13:18:32Z", body: "B"),
                makeOutgoingMessage(id: messageC, createdAt: "2026-06-26T13:18:33Z", body: "C")
            ],
            conversationID: conversationID
        )

        coordinator.testingSetOwnerProfileID(ownerProfileID)
        coordinator.testingSuspendBeforeLocalApply = true

        let suspended = AsyncStream.makeStream(of: Void.self)
        coordinator.testingOnApplySuspended = {
            suspended.continuation.yield()
        }

        coordinator.handleConversationDelivered(
            conversationID: conversationID,
            payload: ConversationDeliveredPayload(
                profileID: counterpartyProfileID,
                lastDeliveredAt: isoDate("2026-06-26T13:18:31Z"),
                messageID: messageB
            )
        )

        for await _ in suspended.stream {
            break
        }

        coordinator.reset()
        coordinator.testingSetOwnerProfileID(UUID())

        let messagesBeforeResume = try await MessengerLocalStore.shared.fetchLocalMessages(
            conversationID: conversationID,
            limit: 10,
            before: nil
        )
        let statusBeforeResume = Dictionary(uniqueKeysWithValues: messagesBeforeResume.compactMap { snapshot -> (UUID, String?)? in
            guard let id = UUID(uuidString: snapshot.id) else { return nil }
            return (id, snapshot.deliveryStatus)
        })

        coordinator.testingResumeSuspendedLocalApplyForTests()
        await coordinator.testingDrainApplies()

        let messagesAfterResume = try await MessengerLocalStore.shared.fetchLocalMessages(
            conversationID: conversationID,
            limit: 10,
            before: nil
        )
        let statusAfterResume = Dictionary(uniqueKeysWithValues: messagesAfterResume.compactMap { snapshot -> (UUID, String?)? in
            guard let id = UUID(uuidString: snapshot.id) else { return nil }
            return (id, snapshot.deliveryStatus)
        })

        #expect(statusBeforeResume[messageB] == MessageDeliveryStatus.sent.rawValue)
        #expect(statusAfterResume[messageB] == MessageDeliveryStatus.sent.rawValue)
        #expect(!coordinator.testingIsApplyInFlight)
        #expect(coordinator.testingPendingRepairHintCount == 0)
    }

    @MainActor
    @Test("presence.changed routes to presence handler only")
    func presenceChangedRoutesToPresenceHandlerOnly() async throws {
        let presenceStore = PresenceStore.makeForTesting()
        let realtimeCoordinator = MessengerRealtimeCoordinator(
            realtimeClient: makeTestRealtimeClient(),
            eventRouter: RealtimeEventRouter.makeForTesting(),
            presenceStore: presenceStore
        )

        RealtimeTransportGuard.resetForTesting()
        let context = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)

        let otherProfileID = counterpartyProfileID
        MessengerDiagnosticsStore.shared.clear()

        realtimeCoordinator.testingHandle(
            .presenceChanged(payload: PresenceChangedPayload(
                profileID: otherProfileID,
                isOnline: true,
                lastSeenAt: nil
            )),
            context: context
        )

        let applied = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            presenceStore.isOnline(profileID: otherProfileID)
        }
        #expect(applied)
        #expect(receiptEventCount(in: MessengerDiagnosticsStore.shared) == 0)

        realtimeCoordinator.stop()
    }

    @MainActor
    @Test("conversation.read routes to receipt handler only")
    func conversationReadRoutesToReceiptHandlerOnly() async throws {
        let presenceStore = PresenceStore.makeForTesting()
        let realtimeCoordinator = MessengerRealtimeCoordinator(
            realtimeClient: makeTestRealtimeClient(),
            eventRouter: RealtimeEventRouter.makeForTesting(),
            presenceStore: presenceStore
        )

        MessengerRealtimeReceiptCoordinator.shared.reset()
        MessengerRealtimeReceiptCoordinator.shared.testingSetOwnerProfileID(ownerProfileID)

        RealtimeTransportGuard.resetForTesting()
        let context = RealtimeTransportGuard.beginConnection(presenceStore: presenceStore)

        MessengerDiagnosticsStore.shared.clear()
        let beforeReceiptCount = receiptEventCount(in: MessengerDiagnosticsStore.shared)

        realtimeCoordinator.testingHandle(
            .conversationRead(
                conversationID: conversationID,
                payload: ConversationReadPayload(
                    profileID: counterpartyProfileID,
                    lastReadAt: isoDate("2026-06-26T13:18:32Z"),
                    messageID: messageB
                )
            ),
            context: context
        )

        await MessengerRealtimeReceiptCoordinator.shared.testingDrainApplies()

        #expect(receiptEventCount(in: MessengerDiagnosticsStore.shared) == beforeReceiptCount + 1)
        #expect(!presenceStore.isOnline(profileID: counterpartyProfileID))

        realtimeCoordinator.stop()
    }
}

// MARK: - Fixtures

private extension MessengerRealtimeReceiptTests {
    func makeStore() -> MessengerLocalStore {
        MessengerLocalStore(inMemoryOnly: true, emitInitializationDiagnostic: false)
    }

    func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func decodeEvent(_ json: String) throws -> RealtimeEvent {
        let dto = try JSONCoding.decoder.decode(RealtimeEventDTO.self, from: Data(json.utf8))
        return dto.event
    }

    func receiptEventCount(in store: MessengerDiagnosticsStore) -> Int {
        store.events.filter {
            $0.event == MessengerDiagnosticEvent.messengerRealtimeReceiptReceived.rawValue
        }.count
    }

    func makeTestRealtimeClient() -> RealtimeClient {
        RealtimeClient(
            router: .shared,
            reconnectPolicy: RealtimeReconnectPolicy(
                initialDelay: 60,
                multiplier: 2,
                maxDelay: 60
            ),
            tokenProvider: { "test-token" }
        )
    }

    func waitUntil(
        timeoutNanoseconds: UInt64,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await MainActor.run(body: condition) {
                return true
            }
            await Task.yield()
        }

        return false
    }

    func seedConversation(store: MessengerLocalStore) async throws {
        try await store.upsertConversations([try seedConversationDTO()])
    }

    func seedConversationDTO() throws -> ConversationDTO {
        try JSONCoding.decoder.decode(ConversationDTO.self, from: Data("""
        {
          "id": "\(conversationID.uuidString)",
          "type": "direct",
          "status": "active",
          "connectionID": null,
          "otherParticipant": {
            "profile": {
              "id": "\(counterpartyProfileID.uuidString)",
              "displayName": "Taylor",
              "bio": null,
              "city": null,
              "primaryPhoto": null
            },
            "role": "member",
            "joinedAt": "2026-06-26T13:18:31Z",
            "lastReadAt": null,
            "lastDeliveredAt": null
          },
          "lastMessage": {
            "id": "\(messageC.uuidString)",
            "conversationID": "\(conversationID.uuidString)",
            "senderProfileID": "\(ownerProfileID.uuidString)",
            "kind": "text",
            "body": "Latest",
            "attachments": [],
            "replyTo": null,
            "reactions": [],
            "deliveryStatus": "sent",
            "clientMessageID": "client-latest",
            "createdAt": "2026-06-26T13:18:33Z",
            "editedAt": null,
            "deletedAt": null
          },
          "unreadCount": 0,
          "lastReadAt": null,
          "lastMessageAt": "2026-06-26T13:18:33Z",
          "createdAt": "2026-06-26T13:18:31Z",
          "updatedAt": "2026-06-26T13:18:33Z"
        }
        """.utf8))
    }

    func seedOutgoingMessages(store: MessengerLocalStore) async throws {
        let messages = [
            makeOutgoingMessage(id: messageA, createdAt: "2026-06-26T13:18:31Z", body: "A"),
            makeOutgoingMessage(id: messageB, createdAt: "2026-06-26T13:18:32Z", body: "B"),
            makeOutgoingMessage(id: messageC, createdAt: "2026-06-26T13:18:33Z", body: "C")
        ]
        try await store.upsertMessages(messages, conversationID: conversationID)
    }

    func makeOutgoingMessage(id: UUID, createdAt: String, body: String) -> MessageDTO {
        try! JSONCoding.decoder.decode(MessageDTO.self, from: Data("""
        {
          "id": "\(id.uuidString)",
          "conversationID": "\(conversationID.uuidString)",
          "senderProfileID": "\(ownerProfileID.uuidString)",
          "kind": "text",
          "body": "\(body)",
          "attachments": [],
          "replyTo": null,
          "reactions": [],
          "deliveryStatus": "sent",
          "clientMessageID": "client-\(id.uuidString.prefix(8))",
          "createdAt": "\(createdAt)",
          "editedAt": null,
          "deletedAt": null
        }
        """.utf8))
    }
}
