import Foundation

nonisolated enum MedicationSampleData {
    static let schedules: [MedicationScheduleItem] = [
        .init(time: "08:00", medicationID: "metformin", name: "二甲双胍", dose: "1 片", timing: "早餐后", status: .taken),
        .init(time: "14:30", medicationID: "vitamin-d3", name: "维生素 D3", dose: "1 粒", timing: "随餐", status: .upcoming),
        .init(time: "21:00", medicationID: "atorvastatin", name: "阿托伐他汀", dose: "1 片", timing: "睡前", status: .pending)
    ]

    static let recognized: [RecognizedMedication] = [
        .init(id: "recognized-amoxicillin", medicationID: "amoxicillin", name: "阿莫西林胶囊", specification: "0.5g", frequency: "每日 3 次"),
        .init(id: "recognized-ibuprofen", medicationID: "ibuprofen", name: "布洛芬缓释胶囊", specification: "0.3g", frequency: "每日 2 次")
    ]

    static let medications: [MedicationInfo] = [
        .init(id: "vitamin-d3", name: "维生素 D3 软胶囊", genericName: "维生素 D3", dosageForm: "软胶囊", specification: "400 IU / 粒", manufacturer: "示例制药企业", indications: "用于维生素 D 缺乏的预防与补充。", usage: "请按药品包装内附说明书或医生、药师指导使用。", precautions: "使用前核对药品名称、规格与有效期；正在使用其他药物时先咨询医生或药师。", adverseReactions: "不良反应信息请查看包装内附说明书；如有明显不适及时咨询专业人员。", contraindications: "对本品成分过敏者禁用，其他禁忌以包装内附说明书为准。", specialPopulation: "孕期、哺乳期、儿童、老年人及慢性病患者使用前请咨询医生或药师。"),
        .init(id: "metformin", name: "盐酸二甲双胍片", genericName: "盐酸二甲双胍", dosageForm: "片剂", specification: "0.5g / 片", manufacturer: "示例制药企业", indications: "适应症请以包装内附说明书及医生指导为准。", usage: "严格按医嘱与药品说明书使用，不自行调整剂量。", precautions: "用药前核对禁忌、相互作用及有效期。", adverseReactions: "具体信息请查阅包装内附说明书。", contraindications: "禁忌信息请以包装内附说明书为准。", specialPopulation: "特殊人群用药前应咨询医生或药师。"),
        .init(id: "atorvastatin", name: "阿托伐他汀钙片", genericName: "阿托伐他汀钙", dosageForm: "片剂", specification: "20mg / 片", manufacturer: "示例制药企业", indications: "适应症请以包装内附说明书及医生指导为准。", usage: "严格按医嘱与药品说明书使用，不自行调整剂量。", precautions: "用药前核对禁忌、相互作用及有效期。", adverseReactions: "具体信息请查阅包装内附说明书。", contraindications: "禁忌信息请以包装内附说明书为准。", specialPopulation: "特殊人群用药前应咨询医生或药师。"),
        .init(id: "amoxicillin", name: "阿莫西林胶囊", genericName: "阿莫西林", dosageForm: "胶囊剂", specification: "0.5g", manufacturer: "待用户核对", indications: "识别内容不作为适应症依据，请核对处方原件。", usage: "按处方原件及医生或药师指导使用。", precautions: "处方识别结果需人工核对，过敏史等信息以专业指导为准。", adverseReactions: "请查看包装内附说明书。", contraindications: "请查看包装内附说明书并咨询医生或药师。", specialPopulation: "特殊人群请咨询医生或药师。"),
        .init(id: "ibuprofen", name: "布洛芬缓释胶囊", genericName: "布洛芬", dosageForm: "缓释胶囊", specification: "0.3g", manufacturer: "待用户核对", indications: "识别内容不作为适应症依据，请核对处方原件。", usage: "按处方原件及医生或药师指导使用。", precautions: "处方识别结果需人工核对。", adverseReactions: "请查看包装内附说明书。", contraindications: "请查看包装内附说明书并咨询医生或药师。", specialPopulation: "特殊人群请咨询医生或药师。")
    ]

    static func info(for id: String) -> MedicationInfo {
        medications.first(where: { $0.id == id }) ?? medications[0]
    }
}
