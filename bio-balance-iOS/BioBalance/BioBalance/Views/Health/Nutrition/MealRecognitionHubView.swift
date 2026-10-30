/// MealRecognitionHubView 由健康首页饮食入口调用，作为「饮食识别」Hub 页。
/// 负责展示饮食记录列表、拍照识别入口、手动录入与餐次管理。

import PhotosUI
import AVFoundation
import SwiftUI
import UIKit

struct MealRecognitionHubView: View {
    @State private var session = MealRecognitionSession()
    @State private var records: [MealRecognitionRecord] = []
    @State private var showingSourcePicker = false
    @State private var showingCamera = false
    @State private var showingPhotoLibrary = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingResult: PhotoRecognitionResult?
    /// 识别中的原图，传给确认页做商品图展示。
    @State private var pendingPhotoImage: UIImage?
    @State private var selectedMealSlot: MealSlot = DrinkExperienceStore.shared.defaultMealSlot()
    @State private var showingManualEntry = false
    @State private var showingHistory = false
    @State private var showingDailyAnalysis = false
    @State private var selectedRecord: MealRecognitionRecord?
    @State private var showingCameraPermissionAlert = false
    /// 结果页有未保存修改时，返回前需要确认。
    @State private var confirmingDiscardResult = false

    private let store = DrinkExperienceStore.shared

    /// 识别中或存在待确认结果时，均以 fullScreenCover 呈现流程页。
    private var showsRecognitionFlow: Bool {
        session.isBusy || session.result != nil || session.failure != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            HealthDetailPageBackground()

            VStack(spacing: 0) {
                mealHeroColor
                    .frame(height: 210)
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)

            MealRecognitionHomeContent(
                records: records,
                isRecognizing: session.isBusy,
                recognitionError: session.failure?.title,
                onRecognize: { showingSourcePicker = true },
                onManualEntry: { showingManualEntry = true },
                onHistory: { showingHistory = true },
                onDailyAnalysis: { showingDailyAnalysis = true },
                onOpenRecord: { selectedRecord = $0 }
            )
        }
        .healthDetailNavigation(title: "餐食识别")
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            records = store.allMealRecords()
        }
        .task {
            if await store.synchronizePrivateCloud() {
                records = store.allMealRecords()
            }
        }
        .confirmationDialog("选择图片来源", isPresented: $showingSourcePicker, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("拍照") { requestCamera() }
            }
            Button("从相册选择") { showingPhotoLibrary = true }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showingCamera) {
            SystemImagePicker(sourceType: .camera) { image in
                handleCameraImage(image)
            }
        }
        .photosPicker(
            isPresented: $showingPhotoLibrary,
            selection: $selectedPhotoItem,
            matching: .images,
            preferredItemEncoding: .automatic
        )
        .onChange(of: selectedPhotoItem) { _, item in
            loadSelectedPhoto(item)
        }
        .fullScreenCover(isPresented: .init(get: { showsRecognitionFlow }, set: { if !$0 { requestCloseRecognitionFlow() } })) {
            MealRecognitionFlowContainer(
                session: session,
                initialSlot: selectedMealSlot,
                onEdited: { session.markEdited() },
                onSave: { recognition, slot, foods in
                    confirmRecognition(recognition, slot: slot, foods: foods)
                },
                onClose: { requestCloseRecognitionFlow() }
            )
        }
        .fullScreenCover(isPresented: $showingManualEntry) {
            MealManualEntryView(
                recentFoods: Array(records.flatMap(\.recognizedFoods).prefix(3)),
                initialSlot: store.defaultMealSlot(for: Date())
            ) { slot, foods in
                saveMealRecord(
                    slot: slot,
                    foods: foods,
                    calories: foods.reduce(0) { $0 + $1.calories }
                )
                showingManualEntry = false
            }
        }
        .navigationDestination(isPresented: $showingHistory) {
            MealHistoryView(records: records)
                .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(item: $selectedRecord) { record in
            MealRecordDetailView(record: record) {
                records = store.allMealRecords()
            }
            .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(isPresented: $showingDailyAnalysis) {
            MealDailyNutritionView(records: records.filter { Calendar.current.isDateInToday($0.capturedAt) })
                .toolbar(.hidden, for: .tabBar)
        }
        .alert("无法访问相机", isPresented: $showingCameraPermissionAlert) {
            Button("打开设置") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
            Button("从相册选择") { showingPhotoLibrary = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你可以前往系统设置开启相机权限，或使用相册选择照片。")
        }
        .confirmationDialog(
            "这次识别结果还没有记录，确定退出吗？",
            isPresented: $confirmingDiscardResult,
            titleVisibility: .visible
        ) {
            Button("退出并丢弃", role: .destructive) {
                session.finish()
            }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("已修改的内容不会被保存。")
        }
    }
}

private extension MealRecognitionHubView {
    var todaySummary: (totalCalories: Int, slots: [MealSlot: MealRecognitionRecord]) {
        store.todayMealSummary()
    }

    var mealHeroColor: Color {
        Color(hex: "E5F5EA")
    }

    /// 关闭识别流程：有未保存修改先确认，否则直接结束会话。
    func requestCloseRecognitionFlow() {
        if session.hasUnsavedEdits {
            confirmingDiscardResult = true
        } else {
            session.finish()
        }
    }

    func handleCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            // 压缩失败属于图片级错误，仍交给状态机走统一失败 UI。
            session.start(imageData: Data(), photoImage: image)
            return
        }
        handlePickedImageData(data, photoImage: image)
    }

    func handlePickedImageData(_ data: Data, photoImage: UIImage?) {
        selectedMealSlot = store.defaultMealSlot(for: Date())
        session.start(imageData: data, photoImage: photoImage)
    }

    func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                    throw PhotoRecognitionServiceError.invalidPhotoData
                }
                await MainActor.run {
                    selectedPhotoItem = nil
                    handlePickedImageData(data, photoImage: nil)
                }
            } catch {
                await MainActor.run {
                    selectedPhotoItem = nil
                    // 相册数据读取失败：不发起网络请求，直接进入可恢复失败态。
                    session.finish()
                    session.failBeforeStart(.invalidImage)
                }
            }
        }
    }

    func confirmRecognition(_ recognition: PhotoRecognitionResult, slot: MealSlot, foods: [MealFoodItem]) {
        selectedMealSlot = slot
        saveMealRecord(
            slot: slot,
            foods: foods,
            calories: foods.reduce(0) { $0 + $1.calories },
            recognition: recognition,
            preparedPhotoData: session.preparedImageDataForSave
        )
        session.finish()
    }

    /// AI 确认与手动录入共用同一落库路径，避免其中一条路径绕过同步逻辑。
    func saveMealRecord(
        slot: MealSlot,
        foods: [MealFoodItem],
        calories: Int,
        recognition: PhotoRecognitionResult? = nil,
        preparedPhotoData: Data? = nil
    ) {
        let recordID = UUID().uuidString
        // 确认后的餐食照片在本机保存压缩副本；原图随会话释放，不上传云端。
        let filenames = preparedPhotoData.flatMap { try? MealPhotoStore.shared.savePreparedJPEG($0, recordID: recordID) }
        let record = MealRecognitionRecord(
            id: recordID,
            mealSlot: slot,
            recognizedFoods: foods,
            estimatedCalories: max(0, calories),
            photoFileID: nil,
            photoURL: nil,
            capturedAt: recognition?.capturedAt ?? Date(),
            locationSummary: recognition?.locationSummary?.displayText,
            aiProviderID: recognition?.aiProviderID,
            aiModel: recognition?.aiModel,
            aiConfidence: recognition?.confidence,
            photoLocalFilename: filenames?.photo,
            thumbnailLocalFilename: filenames?.thumbnail,
            wasEditedByUser: foods.contains(where: \.wasEditedByUser)
        )
        store.saveMealRecord(record)
        records = store.allMealRecords()
    }

    func requestCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showingCamera = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run {
                    if granted { showingCamera = true } else { showingCameraPermissionAlert = true }
                }
            }
        case .denied, .restricted: showingCameraPermissionAlert = true
        @unknown default: showingCameraPermissionAlert = true
        }
    }
}

private extension View {
    func mealHubSurface() -> some View {
        background(Theme.Colors.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.95), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
    }
}
