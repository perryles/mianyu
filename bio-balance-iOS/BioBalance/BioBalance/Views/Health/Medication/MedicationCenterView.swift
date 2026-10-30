import SwiftUI

struct MedicationCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedMedicationOnboarding") private var hasCompletedOnboarding = false
    @State private var store = MedicationCenterStore()
    @State private var path: [MedicationRoute] = []

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                NavigationStack(path: $path) {
                    MedicationHomeView(store: store, path: $path, onClose: { dismiss() })
                        .navigationDestination(for: MedicationRoute.self) { route in
                            Group {
                                switch route {
                                case .plan: MedicationPlanView(store: store, path: $path)
                                case .prescription: PrescriptionRecognitionView(store: store, path: $path)
                                case .instruction(let id): MedicationInstructionView(info: MedicationSampleData.info(for: id), path: $path)
                                case .symptomReview: MedicationSymptomReviewView(path: $path)
                                case .symptomLog: BodySymptomObservationView()
                                }
                            }
                            .toolbar(.hidden, for: .tabBar)
                        }
                }
            } else {
                MedicationOnboardingView { destination in
                    hasCompletedOnboarding = true
                    path = destination.map { [$0] } ?? []
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-resetMedicationOnboarding") {
                hasCompletedOnboarding = false
                path.removeAll()
            }
#endif
        }
    }
}

#Preview { MedicationCenterView() }
