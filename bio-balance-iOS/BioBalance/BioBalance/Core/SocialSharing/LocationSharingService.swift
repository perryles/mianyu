import CoreLocation
import Foundation

/// 好友共享的本地隐私选择。系统位置授权只表示 App 可以读取位置，不能代替
/// “把位置发送给好友”的单独同意，因此该开关默认关闭并独立保存。
nonisolated enum SocialSharingDataPolicy {
    static let approximateLocationSharingEnabledKey = "social.sharing.approximate-location-enabled.v1"
}

@MainActor
final class LocationSharingService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationSharingService()

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<SharedLocationSummary?, Never>?
    private var rawLocationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authorizationContinuation: CheckedContinuation<HealthMetricAccessState, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1_000
    }

    var accessState: HealthMetricAccessState {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        case .notDetermined, .restricted, .denied:
            return .unauthorized
        @unknown default:
            return .unauthorized
        }
    }

    func requestAuthorizationIfNeeded() async -> HealthMetricAccessState {
        guard manager.authorizationStatus == .notDetermined else {
            return accessState
        }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func fetchCurrentSummaryIfAuthorized() async -> SharedLocationSummary? {
        guard accessState == .authorized else { return nil }

        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func fetchCurrentLocationIfAuthorized() async -> CLLocation? {
        guard accessState == .authorized else { return nil }

        return await withCheckedContinuation { continuation in
            rawLocationContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            finishAuthorizationIfNeeded()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else {
                finish(nil)
                finishRaw(nil)
                return
            }
            finish(summary(from: location))
            finishRaw(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(nil)
            finishRaw(nil)
        }
    }

    private func finish(_ summary: SharedLocationSummary?) {
        locationContinuation?.resume(returning: summary)
        locationContinuation = nil
    }

    private func finishRaw(_ location: CLLocation?) {
        rawLocationContinuation?.resume(returning: location)
        rawLocationContinuation = nil
    }

    private func finishAuthorizationIfNeeded() {
        guard manager.authorizationStatus != .notDetermined else { return }
        authorizationContinuation?.resume(returning: accessState)
        authorizationContinuation = nil
    }

    private func summary(from location: CLLocation) -> SharedLocationSummary {
        let roundedLatitude = (location.coordinate.latitude * 100).rounded() / 100
        let roundedLongitude = (location.coordinate.longitude * 100).rounded() / 100
        let accuracy = max(location.horizontalAccuracy, 1_000)

        return SharedLocationSummary(
            latitude: roundedLatitude,
            longitude: roundedLongitude,
            horizontalAccuracyMeters: accuracy,
            label: "约 \(formatCoordinate(roundedLatitude)), \(formatCoordinate(roundedLongitude))",
            capturedAt: Date()
        )
    }

    private func formatCoordinate(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
