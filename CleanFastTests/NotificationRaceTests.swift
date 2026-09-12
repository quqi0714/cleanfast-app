import Testing
import Foundation
import UserNotifications
@testable import CleanFast

@MainActor
private final class HeldNotificationCenter: NotificationCenterClient {
    var status: UNAuthorizationStatus = .authorized
    var holdSettings = false
    var holdAdd = false
    var holdPermission = false
    var holdRemoval = false
    var removalWaiter: CheckedContinuation<Void, Never>?
    var settingsWaiter: CheckedContinuation<UNAuthorizationStatus, Never>?
    var addWaiter: CheckedContinuation<Void, Never>?
    var permissionWaiter: CheckedContinuation<Bool, Never>?
    var pending: [String: UNNotificationRequest] = [:]
    var added: [UNNotificationRequest] = []

    func authorizationStatus() async -> UNAuthorizationStatus {
        if holdSettings {
            holdSettings = false
            return await withCheckedContinuation { settingsWaiter = $0 }
        }
        return status
    }
    func requestPermission() async -> Bool {
        if holdPermission {
            holdPermission = false
            return await withCheckedContinuation { permissionWaiter = $0 }
        }
        return status == .authorized
    }
    func add(_ request: UNNotificationRequest) async throws {
        if holdAdd {
            holdAdd = false
            await withCheckedContinuation { addWaiter = $0 }
        }
        // Deliberately ignores Task cancellation like a non-cancellable SDK call.
        pending[request.identifier] = request
        added.append(request)
    }
    func removePending(identifiers: [String]) async {
        if holdRemoval {
            holdRemoval = false
            await withCheckedContinuation { removalWaiter = $0 }
        }
        for id in identifiers { pending[id] = nil }
    }
    func releaseRemoval() { removalWaiter?.resume(); removalWaiter = nil }
    func releaseSettings() { settingsWaiter?.resume(returning: status); settingsWaiter = nil }
    func releaseAdd() { addWaiter?.resume(); addWaiter = nil }
    func releasePermission(_ granted: Bool) { permissionWaiter?.resume(returning: granted); permissionWaiter = nil }
}

@MainActor
struct NotificationRaceTests {
    private func waitFor(_ ready: () -> Bool) async throws {
        for _ in 0..<10_000 {
            if ready() { return }
            await Task.yield()
        }
        try #require(ready(), "Expected suspended system call was not reached")
    }
    private func submit(_ service: NotificationService, _ title: String) -> Task<NotificationService.ScheduleResult, Never> {
        service.scheduleTargetReached(at: Date().addingTimeInterval(3600), title: title, body: title)
    }
    private func makeVM(_ center: HeldNotificationCenter, mode: TimingMode = .manual) -> (FastingTimerViewModel, PersistenceService, NotificationService) {
        let defaults = UserDefaults(suiteName: "notification-race-\(UUID())")!
        let persistence = PersistenceService(defaults: defaults)
        persistence.notificationEnabled = true
        persistence.timingMode = mode
        let service = NotificationService(client: center)
        let vm = FastingTimerViewModel(persistence: persistence, startTicker: false, notifications: service)
        return (vm, persistence, service)
    }


    @Test func startupReturnsWhileNotificationRemovalIsSuspended() async throws {
        let center = HeldNotificationCenter()
        center.holdRemoval = true
        let (vm, _, service) = makeVM(center)
        // Initialization and UI state remain available before the system replies.
        #expect(vm.state == .notStarted)
        try await waitFor { center.removalWaiter != nil }
        vm.startFasting()
        #expect(vm.state == .fasting)
        #expect(center.added.isEmpty)
        center.releaseRemoval()
        await service.waitUntilIdle()
        #expect(center.pending.count == 1)
    }

    @Test func slowCancelledRemovalCannotDeleteNewerPlan() async throws {
        let center = HeldNotificationCenter()
        let service = NotificationService(client: center)
        #expect(await submit(service, "original").value == .scheduled)
        center.holdRemoval = true
        service.cancelAll()
        try await waitFor { center.removalWaiter != nil }
        let latest = submit(service, "latest")
        center.releaseRemoval()
        #expect(await latest.value == .scheduled)
        #expect(center.pending.values.map(\.content.title) == ["latest"])
    }

    @Test func cancellationDuringRemovalCannotStartPermissionOrAdd() async throws {
        let center = HeldNotificationCenter()
        center.holdRemoval = true
        let service = NotificationService(client: center)
        let old = submit(service, "old")
        try await waitFor { center.removalWaiter != nil }
        service.cancelAll()
        center.releaseRemoval()
        #expect(await old.value == .superseded)
        await service.waitUntilIdle()
        #expect(center.added.isEmpty)
        #expect(center.pending.isEmpty)
    }

    @Test func cancellationBeforeTaskStartsDoesNotSchedule() async {
        let center = HeldNotificationCenter()
        let service = NotificationService(client: center)
        let old = submit(service, "old")
        service.cancelAll()
        #expect(await old.value == .superseded)
        #expect(center.added.isEmpty)
    }

    @Test func cancellationDuringAuthorizationDoesNotSchedule() async throws {
        let center = HeldNotificationCenter()
        center.holdSettings = true
        let service = NotificationService(client: center)
        let old = submit(service, "old")
        try await waitFor { center.settingsWaiter != nil }
        service.cancelAll()
        center.releaseSettings()
        #expect(await old.value == .superseded)
        #expect(center.pending.isEmpty)
    }

    @Test func cancellationDuringAddCleansUpCompletedSystemWrite() async throws {
        let center = HeldNotificationCenter()
        center.holdAdd = true
        let service = NotificationService(client: center)
        let old = submit(service, "old")
        try await waitFor { center.addWaiter != nil }
        service.cancelAll()
        center.releaseAdd()
        #expect(await old.value == .superseded)
        #expect(center.pending.isEmpty)
    }

    @Test func oldAddCannotOverwriteOrDeleteNewPlan() async throws {
        let center = HeldNotificationCenter()
        center.holdAdd = true
        let service = NotificationService(client: center)
        let old = submit(service, "old")
        try await waitFor { center.addWaiter != nil }
        let latest = submit(service, "latest")
        center.releaseAdd()
        #expect(await old.value == .superseded)
        #expect(await latest.value == .scheduled)
        #expect(center.pending.values.map(\.content.title) == ["latest"])
    }

    @Test func seriesStopsAfterCancelledInFlightItem() async throws {
        let center = HeldNotificationCenter()
        center.holdAdd = true
        let service = NotificationService(client: center)
        let task = service.scheduleSeries((1...6).map {
            .init(fireDate: Date().addingTimeInterval(Double($0) * 3600), title: "\($0)", body: "")
        })
        try await waitFor { center.addWaiter != nil }
        service.cancelAll()
        center.releaseAdd()
        #expect(await task.value == .superseded)
        #expect(center.added.count == 1)
        #expect(center.pending.isEmpty)
    }

    @Test func stalePermissionGrantCannotReviveCancelledSchedule() async throws {
        let center = HeldNotificationCenter()
        center.status = .notDetermined
        center.holdPermission = true
        let service = NotificationService(client: center)
        let old = submit(service, "old")
        try await waitFor { center.permissionWaiter != nil }
        service.cancelAll()
        center.releasePermission(true)
        #expect(await old.value == .superseded)
        #expect(center.pending.isEmpty)
    }

    @Test func manualStartThenSkipInvalidatesWaitingPlan() async throws {
        let center = HeldNotificationCenter()
        center.holdSettings = true
        let (vm, _, service) = makeVM(center)
        vm.startFasting()
        try await waitFor { center.settingsWaiter != nil }
        vm.skipToday()
        center.releaseSettings()
        await service.waitUntilIdle()
        #expect(center.pending.isEmpty)
    }

    @Test func delayedPermissionCannotTurnRemindersBackOn() async throws {
        let center = HeldNotificationCenter()
        center.holdPermission = true
        let (vm, persistence, service) = makeVM(center)
        let on = vm.setNotificationsEnabled(true)
        try await waitFor { center.permissionWaiter != nil }
        _ = vm.setNotificationsEnabled(false)
        center.releasePermission(true)
        #expect(await on.value == false)
        await service.waitUntilIdle()
        #expect(persistence.notificationEnabled == false)
        #expect(center.pending.isEmpty)
    }

    @Test func delayedDenialCannotUndoNewPermissionChoice() async throws {
        let center = HeldNotificationCenter()
        center.holdPermission = true
        let (vm, persistence, _) = makeVM(center)
        let old = vm.setNotificationsEnabled(true)
        try await waitFor { center.permissionWaiter != nil }
        _ = vm.setNotificationsEnabled(false)
        let latest = vm.setNotificationsEnabled(true)
        #expect(await latest.value == true)
        center.releasePermission(false)
        #expect(await old.value == false)
        #expect(persistence.notificationEnabled == true)
    }

    @Test func targetChangeKeepsOnlyLatestDeadline() async throws {
        let center = HeldNotificationCenter()
        center.holdAdd = true
        let (vm, _, service) = makeVM(center)
        vm.startFasting()
        try await waitFor { center.addWaiter != nil }
        vm.updateTargetMinutes(18 * 60)
        center.releaseAdd()
        await service.waitUntilIdle()
        let request = try #require(center.pending.values.first)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        let date = try #require(trigger.nextTriggerDate())
        #expect(center.pending.count == 1)
        #expect(abs(date.timeIntervalSince(vm.session!.targetEndDate)) < 1)
    }

    @Test func automaticSkipKeepsOnlyFutureResumePlan() async throws {
        let center = HeldNotificationCenter()
        center.holdAdd = true
        let (vm, _, service) = makeVM(center, mode: .automatic)
        vm.startFasting()
        try await waitFor { center.addWaiter != nil }
        vm.skipToday()
        center.releaseAdd()
        await service.waitUntilIdle()
        #expect(center.pending.count == NotificationService.maxSeriesCount)
        let dates = center.pending.values.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
        #expect(dates.count == 6)
        #expect(dates.allSatisfy { $0 > Date().addingTimeInterval(16 * 3600) })
    }
}
