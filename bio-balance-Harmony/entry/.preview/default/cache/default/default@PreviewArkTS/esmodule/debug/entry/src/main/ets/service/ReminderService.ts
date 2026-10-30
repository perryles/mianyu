import reminderAgentManager from "@ohos:reminderAgentManager";
import notificationManager from "@ohos:notificationManager";
import preferences from "@ohos:data.preferences";
import type common from "@ohos:app.ability.common";
import type { BusinessError } from "@ohos:base";
/**
 * 本地提醒服务（喝水 / 用药 / 久坐）。
 * 通过 reminderAgentManager 发布每日定时提醒，配置与已发布 reminderId 仅保存在本机 Preferences。
 * 提醒内容不包含任何健康明细数值，仅使用固定文案。
 */
export interface ReminderSetting {
    enabled: boolean;
    hour: number;
    minute: number;
}
export interface ReminderPreset {
    key: string;
    titleKey: string;
    contentKey: string;
    defaultHour: number;
    defaultMinute: number;
}
export const REMINDER_PRESETS: ReminderPreset[] = [
    { key: 'water', titleKey: 'reminder_water_title', contentKey: 'reminder_water_content', defaultHour: 10, defaultMinute: 0 },
    { key: 'medication', titleKey: 'reminder_medication_title', contentKey: 'reminder_medication_content', defaultHour: 8, defaultMinute: 0 },
    { key: 'sedentary', titleKey: 'reminder_sedentary_title', contentKey: 'reminder_sedentary_content', defaultHour: 14, defaultMinute: 0 }
];
const STORAGE_NAME: string = 'bio_balance_reminders';
const REMINDER_ID_PREFIX: string = 'reminderId_';
export class ReminderService {
    /**
     * 请求通知权限（用户可能拒绝，调用方需根据返回值处理开关回退）。
     */
    static async requestNotificationPermission(context: common.UIAbilityContext): Promise<boolean> {
        try {
            await notificationManager.requestEnableNotification(context);
            return true;
        }
        catch (error) {
            const code: number = (error as BusinessError).code;
            if (code === 1600004) {
                return false;
            }
            return false;
        }
    }
    static async loadSetting(context: common.Context, key: string): Promise<ReminderSetting> {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORAGE_NAME);
        const preset: ReminderPreset | undefined = REMINDER_PRESETS.find((item: ReminderPreset) => item.key === key);
        const defaultHour: number = preset !== undefined ? preset.defaultHour : 10;
        const defaultMinute: number = preset !== undefined ? preset.defaultMinute : 0;
        return {
            enabled: store.getSync(`${key}_enabled`, false) as boolean,
            hour: store.getSync(`${key}_hour`, defaultHour) as number,
            minute: store.getSync(`${key}_minute`, defaultMinute) as number
        };
    }
    /**
     * 保存提醒设置：开启时先取消旧提醒再发布并缓存新 reminderId，关闭时取消已发布提醒。
     */
    static async saveSetting(context: common.Context, key: string, setting: ReminderSetting): Promise<void> {
        const store: preferences.Preferences = await preferences.getPreferences(context, STORAGE_NAME);
        const oldId: number = store.getSync(`${REMINDER_ID_PREFIX}${key}`, -1) as number;
        if (setting.enabled) {
            // 与关闭路径对称：修改时间/开关时先取消旧提醒，避免新旧两条每日提醒并存。
            if (oldId >= 0) {
                try {
                    await reminderAgentManager.cancelReminder(oldId);
                }
                catch (error) {
                    // 取消旧提醒失败不阻塞发布；本地缓存会以新 reminderId 覆盖。
                }
            }
            const reminderId: number = await ReminderService.publish(context, key, setting);
            store.putSync(`${REMINDER_ID_PREFIX}${key}`, reminderId);
        }
        else {
            if (oldId >= 0) {
                try {
                    await reminderAgentManager.cancelReminder(oldId);
                }
                catch (error) {
                    // 取消失败不阻塞本地设置保存；reminderId 仍会被清除。
                }
            }
            store.deleteSync(`${REMINDER_ID_PREFIX}${key}`);
        }
        store.putSync(`${key}_enabled`, setting.enabled);
        store.putSync(`${key}_hour`, setting.hour);
        store.putSync(`${key}_minute`, setting.minute);
        await store.flush();
    }
    /**
     * 发布每日定时提醒，返回 reminderId。
     */
    static async publish(context: common.Context, key: string, setting: ReminderSetting): Promise<number> {
        const presetIndex: number = REMINDER_PRESETS.findIndex((item: ReminderPreset) => item.key === key);
        const preset: ReminderPreset | undefined = presetIndex >= 0 ? REMINDER_PRESETS[presetIndex] : undefined;
        const request: reminderAgentManager.ReminderRequestAlarm = {
            reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
            hour: setting.hour,
            minute: setting.minute,
            daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
            title: context.resourceManager.getStringByNameSync(preset !== undefined ? preset.titleKey : 'reminder_title'),
            content: context.resourceManager.getStringByNameSync(preset !== undefined ? preset.contentKey : 'reminder_fallback_content'),
            notificationId: 3000 + Math.max(0, presetIndex),
            ringDuration: 20
        };
        return reminderAgentManager.publishReminder(request);
    }
}
