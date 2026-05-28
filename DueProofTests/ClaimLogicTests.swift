import SwiftData
import XCTest
@testable import DueProof

final class ClaimLogicTests: XCTestCase {
    func testSyncConfigurationMarksRestartOnlyWhenSettingChanges() throws {
        let suiteName = "DueProofTests.SyncConfiguration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertFalse(SyncConfiguration.isICloudSyncEnabled(defaults: defaults))
        XCTAssertFalse(defaults.bool(forKey: SyncConfiguration.iCloudSyncRequiresRestartKey))

        SyncConfiguration.setICloudSyncEnabled(false, defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: SyncConfiguration.iCloudSyncRequiresRestartKey))

        SyncConfiguration.setICloudSyncEnabled(true, defaults: defaults)
        XCTAssertTrue(SyncConfiguration.isICloudSyncEnabled(defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: SyncConfiguration.iCloudSyncRequiresRestartKey))

        SyncConfiguration.markLaunchConfigurationApplied(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: SyncConfiguration.iCloudSyncRequiresRestartKey))
    }

    func testUrgentAndExpiredCalculations() {
        let urgentDeadline = DateHelpers.calendar.date(byAdding: .day, value: 3, to: Date())!
        let overdueDeadline = DateHelpers.calendar.date(byAdding: .day, value: -1, to: Date())!
        let noDeadline = Claim(title: "Gift card", category: .giftCard, valueAtRisk: 25)

        let urgentClaim = Claim(title: "Return", category: .returnItem, valueAtRisk: 100, deadline: urgentDeadline)
        let overdueClaim = Claim(title: "Overdue return", category: .returnItem, valueAtRisk: 60, deadline: overdueDeadline)
        let expiredClaim = Claim(title: "Expired return", category: .returnItem, valueAtRisk: 60, status: .expired)

        XCTAssertTrue(urgentClaim.isUrgent)
        XCTAssertFalse(overdueClaim.isUrgent)
        XCTAssertTrue(overdueClaim.isOverdue)
        XCTAssertFalse(overdueClaim.isExpired)
        XCTAssertEqual(overdueClaim.effectiveStatus, .overdue)
        XCTAssertEqual(overdueClaim.urgencyLabel, "Overdue by 1 day")
        XCTAssertTrue(expiredClaim.isExpired)
        XCTAssertFalse(noDeadline.isUrgent)
        XCTAssertFalse(noDeadline.isExpired)
        XCTAssertTrue(noDeadline.countsTowardMoneyAtRisk)
    }

    func testDeadlineDerivedStatusesDoNotStayStale() {
        let distantDeadline = DateHelpers.calendar.date(byAdding: .day, value: 20, to: Date())!
        let staleUrgent = Claim(title: "Later return", category: .returnItem, valueAtRisk: 100, deadline: distantDeadline, status: .urgent)
        let staleOverdue = Claim(title: "Later rebate", category: .rebate, valueAtRisk: 50, deadline: distantDeadline, status: .overdue)
        let noDeadlineOverdue = Claim(title: "Gift card", category: .giftCard, valueAtRisk: 25, status: .overdue)

        XCTAssertEqual(ClaimStatus.normalizedStoredStatus(.urgent), .active)
        XCTAssertEqual(ClaimStatus.normalizedStoredStatus(.overdue), .active)
        XCTAssertFalse(ClaimStatus.editableCases.contains(.urgent))
        XCTAssertFalse(ClaimStatus.editableCases.contains(.overdue))
        XCTAssertEqual(staleUrgent.status, .active)
        XCTAssertEqual(staleOverdue.status, .active)
        XCTAssertEqual(noDeadlineOverdue.status, .active)
        XCTAssertEqual(staleUrgent.effectiveStatus, .active)
        XCTAssertEqual(staleOverdue.effectiveStatus, .active)
        XCTAssertEqual(noDeadlineOverdue.effectiveStatus, .active)
    }

    func testClaimInitializerNormalizesStorageBoundaryFields() throws {
        let deadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 7, to: Date()))
        let invalidReminder = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 8, to: Date()))
        let longTitle = String(repeating: "A", count: ClaimTextLimits.title + 40)
        let longPolicy = String(repeating: "P", count: ClaimTextLimits.policySummary + 40)
        let longNotes = String(repeating: "N", count: ClaimTextLimits.notes + 40)

        let claim = Claim(
            title: "  \(longTitle)  ",
            category: .returnItem,
            merchant: "   ",
            valueAtRisk: .infinity,
            deadline: deadline,
            reminderDate: invalidReminder,
            referenceNumber: "  \(String(repeating: "R", count: ClaimTextLimits.reference + 40))  ",
            policySummary: longPolicy,
            actionURLString: " support.example/returns ",
            notes: longNotes,
            status: .urgent,
            recoveredValue: .nan
        )

        XCTAssertEqual(claim.title.count, ClaimTextLimits.title)
        XCTAssertNil(claim.merchant)
        XCTAssertEqual(claim.valueAtRisk, 0)
        XCTAssertNil(claim.reminderDate)
        XCTAssertEqual(claim.referenceNumber?.count, ClaimTextLimits.reference)
        XCTAssertEqual(claim.primaryReference?.count, ClaimTextLimits.reference)
        XCTAssertEqual(claim.policySummary.count, ClaimTextLimits.policySummary)
        XCTAssertEqual(claim.actionURLString, "https://support.example/returns")
        XCTAssertEqual(claim.notes.count, ClaimTextLimits.notes)
        XCTAssertEqual(claim.status, .active)
        XCTAssertEqual(claim.recoveredValue, 0)
        XCTAssertNil(claim.completedAt)

        let untitled = Claim(title: "   ", category: .other, valueAtRisk: -10)
        XCTAssertEqual(untitled.title, "Untitled claim")
        XCTAssertEqual(untitled.valueAtRisk, 0)

        let recovered = Claim(
            title: "Recovered",
            category: .rebate,
            valueAtRisk: 100,
            status: .recovered,
            recoveredValue: 150,
            completedAt: deadline
        )
        XCTAssertEqual(recovered.recoveredValue, 100)
        XCTAssertEqual(recovered.completedAt, deadline)

        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let invalidDates = Claim(
            title: "Invalid dates",
            category: .rebate,
            valueAtRisk: 10,
            deadline: invalidDate,
            reminderDate: invalidDate,
            status: .recovered,
            createdAt: invalidDate,
            updatedAt: invalidDate,
            recoveredValue: 10,
            completedAt: invalidDate
        )

        XCTAssertNil(invalidDates.deadline)
        XCTAssertNil(invalidDates.reminderDate)
        XCTAssertTrue(invalidDates.createdAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertTrue(invalidDates.updatedAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertNil(invalidDates.completedAt)
    }

    func testActionURLNormalizationRejectsMalformedExplicitSchemes() {
        XCTAssertEqual(DueProofActionURL.normalizedString(from: "support.example/returns"), "https://support.example/returns")
        XCTAssertNil(DueProofActionURL.normalizedString(from: "http:example.com"))

        XCTAssertEqual(Claim.normalizedActionURLString("support.example/returns"), "https://support.example/returns")
        XCTAssertEqual(Claim.normalizedActionURLString("https://support.example/returns"), "https://support.example/returns")
        XCTAssertEqual(Claim.normalizedActionURLString("help@example.com"), "mailto:help@example.com")
        XCTAssertEqual(Claim.normalizedActionURLString("+1 555 123 4567"), "tel:+1%20555%20123%204567")

        XCTAssertNil(Claim.normalizedActionURLString("http:example.com"))
        XCTAssertNil(Claim.normalizedActionURLString("https:example.com"))
        XCTAssertNil(Claim.normalizedActionURLString("javascript:alert(1)"))
        XCTAssertNil(Claim.normalizedActionURLString("dueproof://claim/8EED90D8-87E6-4F1F-B978-7CE78F8D9071"))
    }

    func testSharedTextNormalizationBoundsProviderPayloads() {
        let longText = String(repeating: "A", count: DueProofSharedText.maximumTextCharacters + 500)

        let normalizedText = DueProofSharedText.normalizedText(from: longText)
        XCTAssertEqual(normalizedText?.count, DueProofSharedText.maximumTextCharacters)
        XCTAssertEqual(normalizedText, String(repeating: "A", count: DueProofSharedText.maximumTextCharacters))

        XCTAssertEqual(
            DueProofSharedText.normalizedText(from: Data("  Shared proof  ".utf8)),
            "Shared proof"
        )
        XCTAssertNil(DueProofSharedText.normalizedText(from: "   "))
        XCTAssertNil(DueProofSharedText.normalizedText(from: Data([0xff, 0xfe])))
        XCTAssertNil(
            DueProofSharedText.normalizedText(
                from: Data(repeating: 0x41, count: DueProofSharedText.maximumTextBytes + 1)
            )
        )
    }

    func testSharedFileNameNormalizationBoundsAndSanitizesProviderMetadata() {
        let longSuggestedName = "/private/tmp/\(String(repeating: "R", count: 200)).pdf"
        let fileName = DueProofSharedFileName.originalFileName(
            suggestedName: longSuggestedName,
            fallbackBaseName: "Shared Document",
            fileExtension: "pdf"
        )

        XCTAssertEqual((fileName as NSString).pathExtension, "pdf")
        XCTAssertFalse(fileName.contains("/"))
        XCTAssertFalse(fileName.contains(":"))
        XCTAssertLessThanOrEqual((fileName as NSString).deletingPathExtension.count, DueProofSharedFileName.maximumBaseNameCharacters)
        XCTAssertFalse(fileName.contains(".pdf.pdf"))

        XCTAssertEqual(
            DueProofSharedFileName.originalFileName(
                suggestedName: "receipt.pdf",
                fallbackBaseName: "Shared Document",
                fileExtension: "pdf"
            ),
            "receipt.pdf"
        )
        XCTAssertEqual(
            DueProofSharedFileName.originalFileName(
                suggestedName: "   ",
                fallbackBaseName: "Shared Photo",
                fileExtension: "jpg"
            ),
            "Shared Photo.jpg"
        )
        XCTAssertEqual(
            DueProofSharedFileName.originalFileName(
                suggestedName: "receipt",
                fallbackBaseName: "Shared Document",
                fileExtension: "../pdf"
            ),
            "receipt.dat"
        )
    }

    func testNormalizeStoredFieldsRepairsLoadedCorruptClaim() throws {
        let deadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 7, to: Date()))
        let invalidReminder = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 8, to: Date()))
        let completedAt = Date(timeIntervalSince1970: 1_767_225_600)
        let claim = Claim(title: "Baseline", category: .rebate, valueAtRisk: 10)
        claim.title = "   "
        claim.merchant = "  \(String(repeating: "M", count: ClaimTextLimits.merchant + 10))  "
        claim.valueAtRisk = .infinity
        claim.deadline = deadline
        claim.reminderDate = invalidReminder
        claim.referenceNumber = "  \(String(repeating: "R", count: ClaimTextLimits.reference + 10))  "
        claim.policySummary = String(repeating: "P", count: ClaimTextLimits.policySummary + 10)
        claim.actionURLString = "javascript:alert(1)"
        claim.notes = String(repeating: "N", count: ClaimTextLimits.notes + 10)
        claim.status = .overdue
        claim.recoveredValue = .nan
        claim.completedAt = completedAt

        XCTAssertTrue(claim.normalizeStoredFields())

        XCTAssertEqual(claim.title, "Untitled claim")
        XCTAssertEqual(claim.merchant?.count, ClaimTextLimits.merchant)
        XCTAssertEqual(claim.valueAtRisk, 0)
        XCTAssertNil(claim.reminderDate)
        XCTAssertEqual(claim.referenceNumber?.count, ClaimTextLimits.reference)
        XCTAssertEqual(claim.policySummary.count, ClaimTextLimits.policySummary)
        XCTAssertNil(claim.actionURLString)
        XCTAssertEqual(claim.notes.count, ClaimTextLimits.notes)
        XCTAssertEqual(claim.status, .active)
        XCTAssertEqual(claim.recoveredValue, 0)
        XCTAssertNil(claim.completedAt)

        let recovered = Claim(title: "Recovered", category: .rebate, valueAtRisk: 50)
        recovered.status = .recovered
        recovered.recoveredValue = 500
        recovered.completedAt = completedAt

        XCTAssertTrue(recovered.normalizeStoredFields())
        XCTAssertEqual(recovered.recoveredValue, 50)
        XCTAssertEqual(recovered.completedAt, completedAt)

        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let corruptDates = Claim(title: "Corrupt dates", category: .document, valueAtRisk: 10)
        corruptDates.deadline = invalidDate
        corruptDates.reminderDate = invalidDate
        corruptDates.createdAt = invalidDate
        corruptDates.updatedAt = invalidDate
        corruptDates.status = .recovered
        corruptDates.recoveredValue = 10
        corruptDates.completedAt = invalidDate

        XCTAssertTrue(corruptDates.normalizeStoredFields())
        XCTAssertNil(corruptDates.deadline)
        XCTAssertNil(corruptDates.reminderDate)
        XCTAssertTrue(corruptDates.createdAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertTrue(corruptDates.updatedAt.timeIntervalSinceReferenceDate.isFinite)
        XCTAssertNil(corruptDates.completedAt)
    }

    func testDaysUntilDeadline() {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
        let futureDate = DateHelpers.calendar.date(byAdding: .day, value: 5, to: referenceDate)!
        let pastDate = DateHelpers.calendar.date(byAdding: .day, value: -2, to: referenceDate)!

        XCTAssertEqual(DateHelpers.daysUntil(futureDate, from: referenceDate), 5)
        XCTAssertEqual(DateHelpers.daysUntil(pastDate, from: referenceDate), -2)
    }

    func testDateHelpersHandleInvalidDates() throws {
        let invalidDate = Date(timeIntervalSinceReferenceDate: .infinity)
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)

        XCTAssertEqual(DateHelpers.daysUntil(invalidDate, from: referenceDate), Int.max)
        XCTAssertFalse(DateHelpers.isPastDeadline(invalidDate, referenceDate: referenceDate))
        XCTAssertEqual(DateHelpers.shortDate(invalidDate), "Unknown date")
        XCTAssertEqual(DateHelpers.fullDate(invalidDate), "Unknown date")
        XCTAssertEqual(DateHelpers.fullDateTime(invalidDate), "Unknown date")
        XCTAssertEqual(DateHelpers.deadlineText(for: invalidDate), "Invalid deadline")
        XCTAssertNotNil(DateHelpers.defaultReminderDate(for: .returnItem, deadline: invalidDate, referenceDate: referenceDate))
    }

    func testCurrencyParsingRejectsNonFiniteValues() {
        XCTAssertNil(CurrencyFormatter.parse("inf"))
        XCTAssertNil(CurrencyFormatter.parse("infinity"))
        XCTAssertNil(CurrencyFormatter.parse("nan"))
        XCTAssertNil(CurrencyFormatter.parse("-12"))
        XCTAssertNil(CurrencyFormatter.parse(String(repeating: "9", count: 40)))
        XCTAssertNil(CurrencyFormatter.parse("\(CurrencyFormatter.maximumSupportedAmount + 0.02)"))
        XCTAssertEqual(CurrencyFormatter.parse("123.45"), 123.45)
        XCTAssertEqual(CurrencyFormatter.sanitizedAmount(.infinity), 0)
        XCTAssertEqual(CurrencyFormatter.sanitizedAmount(.nan), 0)
        XCTAssertEqual(CurrencyFormatter.sanitizedAmount(-12), 0)
        XCTAssertEqual(CurrencyFormatter.sanitizedAmount(12.34), 12.34)
        XCTAssertEqual(
            CurrencyFormatter.sanitizedAmount(CurrencyFormatter.maximumSupportedAmount + 10),
            CurrencyFormatter.maximumSupportedAmount
        )
    }

    func testCategoryReminderDefaultsProtectCommonDeadlineWindows() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
        let returnDeadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 30, to: referenceDate))
        let warrantyDeadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .year, value: 1, to: referenceDate))

        XCTAssertEqual(
            DateHelpers.daysUntil(try XCTUnwrap(DateHelpers.defaultReminderDate(for: .returnItem, deadline: returnDeadline, referenceDate: referenceDate)), from: referenceDate),
            23
        )
        XCTAssertEqual(
            DateHelpers.daysUntil(try XCTUnwrap(DateHelpers.defaultReminderDate(for: .warranty, deadline: warrantyDeadline, referenceDate: referenceDate)), from: referenceDate),
            335
        )
    }

    func testStatusTransitions() {
        let claim = Claim(title: "Rebate", category: .rebate, valueAtRisk: 42)

        claim.markRecovered()
        XCTAssertEqual(claim.status, .recovered)
        XCTAssertEqual(claim.recoveredValue, 42)
        XCTAssertNotNil(claim.completedAt)

        claim.status = .active
        claim.completedAt = nil
        claim.recoveredValue = 0
        claim.markUsed()
        XCTAssertEqual(claim.status, .used)
        XCTAssertNotNil(claim.completedAt)

        claim.status = .active
        claim.markExpired()
        XCTAssertEqual(claim.status, .expired)
        XCTAssertNotNil(claim.completedAt)
        XCTAssertEqual(claim.recoveredValue, 0)

        claim.status = .recovered
        claim.recoveredValue = 42
        claim.markIgnored()
        XCTAssertEqual(claim.status, .ignored)
        XCTAssertEqual(claim.recoveredValue, 0)
    }

    func testClaimMutationSnapshotRestoresUnsavedChanges() {
        let claim = Claim(
            title: "Original",
            category: .rebate,
            merchant: "Store",
            valueAtRisk: 42,
            deadline: Date(timeIntervalSince1970: 1_779_232_000),
            reminderDate: Date(timeIntervalSince1970: 1_779_145_600),
            referenceNumber: "ABC",
            policySummary: "Policy",
            actionURLString: "https://support.example",
            notes: "Notes"
        )
        let proof = ProofItem(type: .note, displayName: "Original note", claim: claim)
        claim.proofItemsList = [proof]
        let snapshot = ClaimMutationSnapshot(claim)

        claim.title = "Changed"
        claim.markRecovered()
        claim.proofItemsList = []
        snapshot.restore(to: claim)

        XCTAssertEqual(claim.title, "Original")
        XCTAssertEqual(claim.status, .active)
        XCTAssertEqual(claim.recoveredValue, 0)
        XCTAssertEqual(claim.proofItemsList.map(\.id), [proof.id])
        XCTAssertEqual(claim.actionURLString, "https://support.example")
    }

    @MainActor
    func testClaimMutationSnapshotRestoresDeletedClaimIntoContext() throws {
        let schema = Schema([Claim.self, ProofItem.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let claim = Claim(title: "Original", category: .rebate, valueAtRisk: 42, notes: "Keep this")
        let proof = ProofItem(type: .note, displayName: "Saved note", extractedText: "Proof", claim: claim)
        claim.proofItemsList = [proof]
        context.insert(claim)
        context.insert(proof)
        try context.save()

        let snapshot = ClaimMutationSnapshot(claim)
        modelDelete(claim, proof: proof, in: context)

        snapshot.restoreDeletedClaim(claim, into: context)
        try context.save()

        let fetchedClaims = try context.fetch(FetchDescriptor<Claim>())
        XCTAssertEqual(fetchedClaims.count, 1)
        XCTAssertEqual(fetchedClaims.first?.title, "Original")
        XCTAssertEqual(fetchedClaims.first?.notes, "Keep this")
        XCTAssertEqual(fetchedClaims.first?.proofItemsList.map(\.displayName), ["Saved note"])
    }

    @MainActor
    private func modelDelete(_ claim: Claim, proof: ProofItem, in context: ModelContext) {
        context.delete(proof)
        context.delete(claim)
    }

    func testActionMetadataIsSearchableAndURLValidated() {
        let claim = Claim(
            title: "Streaming trial",
            category: .subscription,
            merchant: "StreamCo",
            valueAtRisk: 19.99,
            referenceNumber: "SUB-987",
            policySummary: "Cancel before renewal to avoid annual charge.",
            actionURLString: "https://stream.example/cancel"
        )

        XCTAssertEqual(claim.actionURL?.host, "stream.example")
        XCTAssertTrue(ClaimSearchIntent.parse("SUB-987").matches(claim))
        XCTAssertTrue(ClaimSearchIntent.parse("annual charge").matches(claim))
        XCTAssertTrue(ClaimSearchIntent.parse("stream example cancel").matches(claim))

        claim.actionURLString = "support.example/returns"
        XCTAssertEqual(claim.actionURL?.absoluteString, "https://support.example/returns")
        XCTAssertEqual(Claim.normalizedActionURLString("help@example.com"), "mailto:help@example.com")
        XCTAssertEqual(Claim.normalizedActionURLString("mailto:help@example.com"), "mailto:help@example.com")
        XCTAssertEqual(Claim.normalizedActionURLString("5551234567"), "tel:5551234567")
        XCTAssertEqual(Claim.normalizedActionURLString("tel:+1-555-123-4567"), "tel:+1-555-123-4567")

        claim.actionURLString = "javascript:alert(1)"
        XCTAssertNil(claim.actionURL)
        XCTAssertNil(Claim.normalizedActionURLString("https://"))
        XCTAssertNil(Claim.normalizedActionURLString("file:///private/receipt.pdf"))
        XCTAssertNil(Claim.normalizedActionURLString("ftp://support.example/returns"))
        XCTAssertNil(Claim.normalizedActionURLString("mailto:not-an-email"))
        XCTAssertNil(Claim.normalizedActionURLString("tel:1"))
    }

    func testActionURLNormalizationCapsPastedOrImportedLinks() {
        let longURL = "https://support.example/" + String(repeating: "a", count: 1_000)
        let normalized = Claim.normalizedActionURLString(longURL)

        XCTAssertEqual(normalized?.count, ClaimTextLimits.actionURL)
        XCTAssertTrue(normalized?.hasPrefix("https://support.example/") == true)
    }

    func testClaimTextLimitsMatchSavedAndImportedBounds() {
        XCTAssertEqual(
            ClaimTextLimits.required("  \(String(repeating: "A", count: 220))  ", limit: ClaimTextLimits.title).count,
            ClaimTextLimits.title
        )
        XCTAssertNil(ClaimTextLimits.optional("   ", limit: ClaimTextLimits.merchant))
        XCTAssertEqual(
            ClaimTextLimits.required(String(repeating: "N", count: 5_000), limit: ClaimTextLimits.notes).count,
            ClaimTextLimits.notes
        )
    }

    func testValueSearchUsesSanitizedClaimAmounts() {
        let claim = Claim(title: "Corrupt value", category: .rebate, valueAtRisk: 20)
        claim.valueAtRisk = .nan

        XCTAssertTrue(ClaimSearchIntent.parse("under $1").matches(claim))
        XCTAssertFalse(ClaimSearchIntent.parse("over $1").matches(claim))

        claim.valueAtRisk = -500
        XCTAssertTrue(ClaimSearchIntent.parse("under $1").matches(claim))
        XCTAssertFalse(ClaimSearchIntent.parse("over $1").matches(claim))
    }

    func testClaimSearchUsesBoundedFieldsAndWholePhraseMatching() {
        let warranty = Claim(title: "Motherboard replacement", category: .warranty, valueAtRisk: 80)
        let other = Claim(title: "Loose receipt", category: .other, valueAtRisk: 5)
        let giftCard = Claim(title: "Balance", category: .giftCard, valueAtRisk: 25)

        XCTAssertTrue(ClaimSearchIntent.parse("motherboard").matches(warranty))
        XCTAssertFalse(ClaimSearchIntent.parse("motherboard").matches(other))
        XCTAssertTrue(ClaimSearchIntent.parse("gift   card").matches(giftCard))

        let invalidDeadline = Claim(title: "Corrupt deadline", category: .rebate, valueAtRisk: 10)
        invalidDeadline.deadline = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertTrue(ClaimSearchIntent.parse("no deadline").matches(invalidDeadline))

        let corruptSearchText = Claim(title: "Corrupt search text", category: .rebate, valueAtRisk: 10)
        corruptSearchText.notes = String(repeating: "N", count: 100_000)
        let proof = ProofItem(type: .note, displayName: "Proof note", claim: corruptSearchText)
        proof.extractedText = String(repeating: "E", count: ProofItemTextLimits.extractedText + 500) + " hidden-tail-token"
        corruptSearchText.proofItemsList = [proof]

        XCTAssertFalse(ClaimSearchIntent.parse("hidden-tail-token").matches(corruptSearchText))
    }

    func testOverdueSearchUsesCallerReferenceDate() throws {
        let futureReferenceDate = Date(timeIntervalSince1970: 2_524_608_000)
        let overdueAtReference = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: -1, to: futureReferenceDate))
        let overdueClaim = Claim(title: "Future overdue", category: .returnItem, valueAtRisk: 100, deadline: overdueAtReference)

        XCTAssertTrue(ClaimSearchIntent.parse("overdue").matches(overdueClaim, referenceDate: futureReferenceDate))

        let pastReferenceDate = Date(timeIntervalSince1970: 1_577_836_800)
        let futureAtReference = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 5, to: pastReferenceDate))
        let notOverdueAtReference = Claim(title: "Past upcoming", category: .rebate, valueAtRisk: 20, deadline: futureAtReference)

        XCTAssertFalse(ClaimSearchIntent.parse("overdue").matches(notOverdueAtReference, referenceDate: pastReferenceDate))
    }

    func testDeadlineSoonestOrderingKeepsOpenWorkAheadOfCompletedHistory() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
        let oldDeadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: -30, to: referenceDate))
        let overdueDeadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: -1, to: referenceDate))
        let urgentDeadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 2, to: referenceDate))
        let laterDeadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 20, to: referenceDate))

        let completed = Claim(title: "Completed old claim", category: .rebate, valueAtRisk: 50, deadline: oldDeadline, status: .recovered)
        let overdue = Claim(title: "Open overdue claim", category: .returnItem, valueAtRisk: 40, deadline: overdueDeadline)
        let urgent = Claim(title: "Open urgent claim", category: .subscription, valueAtRisk: 30, deadline: urgentDeadline)
        let later = Claim(title: "Open later claim", category: .warranty, valueAtRisk: 20, deadline: laterDeadline)
        let noDeadline = Claim(title: "Open no deadline", category: .giftCard, valueAtRisk: 10)
        let invalidDeadline = Claim(title: "Open invalid deadline", category: .document, valueAtRisk: 15)
        invalidDeadline.deadline = Date(timeIntervalSinceReferenceDate: .infinity)
        invalidDeadline.updatedAt = Date(timeIntervalSince1970: 1_767_225_700)
        noDeadline.updatedAt = Date(timeIntervalSince1970: 1_767_225_600)

        let sorted = [completed, noDeadline, invalidDeadline, later, urgent, overdue]
            .sorted { ClaimListOrdering.deadlineSoonest($0, $1, referenceDate: referenceDate) }

        XCTAssertEqual(
            sorted.map(\.title),
            ["Open overdue claim", "Open urgent claim", "Open later claim", "Open invalid deadline", "Open no deadline", "Completed old claim"]
        )
    }

    func testExternalRoutesBoundSearchAndRejectMalformedSharedImportIDs() throws {
        let route = AppRoute()
        let longQuery = String(repeating: "urgent%20", count: 80)
        let claimID = UUID(uuidString: "8EED90D8-87E6-4F1F-B978-7CE78F8D9071")!

        route.handle(try XCTUnwrap(URL(string: "DUEPROOF://SEARCH?q=\(longQuery)")))

        guard case let .search(query) = route.request?.destination else {
            return XCTFail("Expected search route")
        }
        XCTAssertLessThanOrEqual(query.count, 120)
        XCTAssertEqual(route.selectedTab, .claims)

        let previousRequest = route.request
        route.handle(try XCTUnwrap(URL(string: "dueproof://import-shared/not-a-uuid")))
        XCTAssertEqual(route.request, previousRequest)
        route.handle(try XCTUnwrap(URL(string: "dueproof://claim/\(claimID.uuidString)/extra")))
        XCTAssertEqual(route.request, previousRequest)
        route.handle(try XCTUnwrap(URL(string: "dueproof://import-shared/\(claimID.uuidString)/extra")))
        XCTAssertEqual(route.request, previousRequest)
        route.handle(try XCTUnwrap(URL(string: "dueproof://add/extra?category=rebate")))
        XCTAssertEqual(route.request, previousRequest)
        route.handle(try XCTUnwrap(URL(string: "dueproof://search/extra?q=rebate")))
        XCTAssertEqual(route.request, previousRequest)

        route.handle(try XCTUnwrap(URL(string: "dueproof://claim/\(claimID.uuidString)")))
        XCTAssertEqual(route.request?.destination, .claim(claimID))

        XCTAssertEqual(
            ClaimSearchIntent.normalizedQuery(String(repeating: "x", count: 300)).count,
            ClaimSearchIntent.maximumQueryLength
        )
        XCTAssertEqual(ClaimSearchIntent.normalizedQuery("  urgent\nrebate\tproof  "), "urgent rebate proof")
    }

    func testSpotlightRouteRequiresExactIdentifierPayload() {
        let route = AppRoute()
        let id = UUID(uuidString: "8EED90D8-87E6-4F1F-B978-7CE78F8D9071")!

        route.handleSpotlightIdentifier("claim:\(id.uuidString)claim:")
        XCTAssertNil(route.request)
        XCTAssertEqual(route.selectedTab, .dashboard)

        route.handleSpotlightIdentifier("claim:\(id.uuidString)")

        XCTAssertEqual(route.selectedTab, .claims)
        XCTAssertEqual(route.request?.destination, .claim(id))
    }

    @MainActor
    func testNotificationIdentifierIsStableAndClaimScoped() {
        let id = UUID(uuidString: "8EED90D8-87E6-4F1F-B978-7CE78F8D9071")!

        XCTAssertEqual(
            NotificationService.reminderIdentifier(for: id),
            "dueproof.claim.8EED90D8-87E6-4F1F-B978-7CE78F8D9071"
        )
    }

    @MainActor
    func testNotificationReminderUsesFireDateForDeadlineTextAndRejectsInvalidSchedules() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_767_225_600)
        let reminderDate = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 23, to: referenceDate))
        let deadline = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 30, to: referenceDate))
        let claim = Claim(
            title: "Return",
            category: .returnItem,
            valueAtRisk: 100,
            deadline: deadline,
            reminderDate: reminderDate
        )

        XCTAssertEqual(
            NotificationService.notificationBody(for: claim, referenceDate: referenceDate),
            "Your return deadline is in 30 days."
        )
        XCTAssertEqual(
            NotificationService.notificationBody(for: claim, referenceDate: reminderDate),
            "Your return deadline is in 7 days."
        )
        XCTAssertTrue(NotificationService.canScheduleReminder(for: claim, referenceDate: referenceDate))

        claim.reminderDate = try XCTUnwrap(DateHelpers.calendar.date(byAdding: .day, value: 31, to: referenceDate))
        XCTAssertFalse(NotificationService.canScheduleReminder(for: claim, referenceDate: referenceDate))

        claim.reminderDate = reminderDate
        claim.markRecovered()
        XCTAssertFalse(NotificationService.canScheduleReminder(for: claim, referenceDate: referenceDate))

        let corruptReminder = Claim(title: "Corrupt reminder", category: .rebate, valueAtRisk: 20)
        corruptReminder.reminderDate = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertFalse(NotificationService.canScheduleReminder(for: corruptReminder, referenceDate: referenceDate))

        let corruptDeadline = Claim(
            title: "Corrupt deadline",
            category: .rebate,
            valueAtRisk: 20,
            reminderDate: reminderDate
        )
        corruptDeadline.deadline = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertFalse(NotificationService.canScheduleReminder(for: corruptDeadline, referenceDate: referenceDate))
        let validSchedule = Claim(title: "Valid reminder", category: .rebate, valueAtRisk: 20, reminderDate: reminderDate)
        XCTAssertFalse(NotificationService.canScheduleReminder(for: validSchedule, referenceDate: Date(timeIntervalSinceReferenceDate: .infinity)))
        XCTAssertEqual(
            NotificationService.notificationBody(for: corruptDeadline, referenceDate: referenceDate),
            "Check your rebate proof in DueProof."
        )
    }
}
