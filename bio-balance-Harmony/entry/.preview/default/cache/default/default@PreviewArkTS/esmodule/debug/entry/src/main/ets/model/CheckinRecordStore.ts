import preferences from "@ohos:data.preferences";
import type common from "@ohos:app.ability.common";
const STORAGE_NAME: string = 'bio_balance_checkin_records';
/**
 * 日照记录（每日一条，分钟数）。
 */
export interface SunlightRecord {
    minutes: number;
    updatedAt: number;
}
/**
 * 咖啡因摄入记录。
 */
export interface CaffeineRecord {
    id: string;
    time: string;
    amount: number;
}
/**
 * 用药记录（本机保存名称与剂量，不上传健康明细）。
 */
export interface MedicationRecord {
    id: string;
    time: string;
    name: string;
    dose: string;
}
/**
 * 身体症状记录。
 */
export interface SymptomRecord {
    id: string;
    time: string;
    type: string;
    intensity: number;
}
/**
 * 每日记录实体（日照 / 咖啡因 / 用药 / 症状）。
 * 仅保存在本机 Preferences，按日期分 key 隔离，健康明细不向任何远端上传。
 */
export class CheckinRecordStore {
    private static async store(context: common.Context): Promise<preferences.Preferences> {
        return preferences.getPreferences(context, STORAGE_NAME);
    }
    /**
     * 生成日期 key，例如 2026-08-07。
     */
    static dateKey(date: Date = new Date()): string {
        const month = `${date.getMonth() + 1}`.padStart(2, '0');
        const day = `${date.getDate()}`.padStart(2, '0');
        return `${date.getFullYear()}-${month}-${day}`;
    }
    /**
     * 生成 HH:mm 时间文案。
     */
    static timeText(date: Date = new Date()): string {
        const hour = `${date.getHours()}`.padStart(2, '0');
        const minute = `${date.getMinutes()}`.padStart(2, '0');
        return `${hour}:${minute}`;
    }
    /**
     * 解析 JSON，数据缺失或损坏时回退到默认值，避免单条脏数据导致整页读取失败。
     */
    private static parseObject<T>(raw: string, fallback: T): T {
        if (raw.length === 0) {
            return fallback;
        }
        try {
            return JSON.parse(raw) as T;
        }
        catch (error) {
            return fallback;
        }
    }
    // ---------------- 日照 ----------------
    static async loadSunlight(context: common.Context, date: string): Promise<SunlightRecord> {
        const store = await CheckinRecordStore.store(context);
        const raw = store.getSync(`sunlight_${date}`, '') as string;
        return CheckinRecordStore.parseObject<SunlightRecord>(raw, { minutes: 0, updatedAt: 0 });
    }
    static async saveSunlight(context: common.Context, date: string, minutes: number): Promise<void> {
        const store = await CheckinRecordStore.store(context);
        const record: SunlightRecord = { minutes, updatedAt: Date.now() };
        store.putSync(`sunlight_${date}`, JSON.stringify(record));
        await store.flush();
    }
    // ---------------- 咖啡因 ----------------
    static async loadCaffeine(context: common.Context, date: string): Promise<CaffeineRecord[]> {
        const store = await CheckinRecordStore.store(context);
        const raw = store.getSync(`caffeine_${date}`, '[]') as string;
        return CheckinRecordStore.parseObject<CaffeineRecord[]>(raw, []);
    }
    static async addCaffeine(context: common.Context, date: string, amount: number): Promise<CaffeineRecord[]> {
        const list = await CheckinRecordStore.loadCaffeine(context, date);
        const record: CaffeineRecord = {
            id: `${Date.now()}_${list.length}`,
            time: CheckinRecordStore.timeText(),
            amount
        };
        list.push(record);
        const store = await CheckinRecordStore.store(context);
        store.putSync(`caffeine_${date}`, JSON.stringify(list));
        await store.flush();
        return list;
    }
    static async removeCaffeine(context: common.Context, date: string, id: string): Promise<CaffeineRecord[]> {
        const list = await CheckinRecordStore.loadCaffeine(context, date);
        const filtered = list.filter((record: CaffeineRecord) => record.id !== id);
        const store = await CheckinRecordStore.store(context);
        store.putSync(`caffeine_${date}`, JSON.stringify(filtered));
        await store.flush();
        return filtered;
    }
    // ---------------- 用药 ----------------
    static async loadMedication(context: common.Context, date: string): Promise<MedicationRecord[]> {
        const store = await CheckinRecordStore.store(context);
        const raw = store.getSync(`medication_${date}`, '[]') as string;
        return CheckinRecordStore.parseObject<MedicationRecord[]>(raw, []);
    }
    static async addMedication(context: common.Context, date: string, name: string, dose: string): Promise<MedicationRecord[]> {
        const list = await CheckinRecordStore.loadMedication(context, date);
        const record: MedicationRecord = {
            id: `${Date.now()}_${list.length}`,
            time: CheckinRecordStore.timeText(),
            name,
            dose
        };
        list.push(record);
        const store = await CheckinRecordStore.store(context);
        store.putSync(`medication_${date}`, JSON.stringify(list));
        await store.flush();
        return list;
    }
    static async removeMedication(context: common.Context, date: string, id: string): Promise<MedicationRecord[]> {
        const list = await CheckinRecordStore.loadMedication(context, date);
        const filtered = list.filter((record: MedicationRecord) => record.id !== id);
        const store = await CheckinRecordStore.store(context);
        store.putSync(`medication_${date}`, JSON.stringify(filtered));
        await store.flush();
        return filtered;
    }
    // ---------------- 症状 ----------------
    static async loadSymptoms(context: common.Context, date: string): Promise<SymptomRecord[]> {
        const store = await CheckinRecordStore.store(context);
        const raw = store.getSync(`symptom_${date}`, '[]') as string;
        return CheckinRecordStore.parseObject<SymptomRecord[]>(raw, []);
    }
    static async addSymptom(context: common.Context, date: string, type: string, intensity: number): Promise<SymptomRecord[]> {
        const list = await CheckinRecordStore.loadSymptoms(context, date);
        const record: SymptomRecord = {
            id: `${Date.now()}_${list.length}`,
            time: CheckinRecordStore.timeText(),
            type,
            intensity
        };
        list.push(record);
        const store = await CheckinRecordStore.store(context);
        store.putSync(`symptom_${date}`, JSON.stringify(list));
        await store.flush();
        return list;
    }
    static async removeSymptom(context: common.Context, date: string, id: string): Promise<SymptomRecord[]> {
        const list = await CheckinRecordStore.loadSymptoms(context, date);
        const filtered = list.filter((record: SymptomRecord) => record.id !== id);
        const store = await CheckinRecordStore.store(context);
        store.putSync(`symptom_${date}`, JSON.stringify(filtered));
        await store.flush();
        return filtered;
    }
}
