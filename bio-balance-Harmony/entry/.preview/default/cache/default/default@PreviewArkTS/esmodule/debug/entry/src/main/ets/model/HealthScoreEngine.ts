/**
 * 本地健康评分引擎（纯本地计算，不采集、不上传任何数据）。
 * 依据饮水、步数、心情与步数目标计算一个 0-100 的每日状态分。
 */
export class HealthScoreEngine {
    /**
     * 计算今日健康分。
     * @param waterCups 今日饮水杯数
     * @param steps 今日步数
     * @param mood 心情档位 1-5
     * @param stepGoal 每日步数目标
     * @returns 0-100 的分数
     */
    static calculate(waterCups: number, steps: number, mood: number, stepGoal: number): number {
        const safeGoal: number = stepGoal > 0 ? stepGoal : 8000;
        const safeWater: number = Math.max(0, waterCups);
        const safeSteps: number = Math.max(0, steps);
        const safeMood: number = Math.max(1, Math.min(5, mood));
        const hydrationScore: number = Math.min(safeWater / 8, 1) * 12;
        const stepScore: number = Math.min(safeSteps / safeGoal, 1) * 18;
        const moodScore: number = safeMood / 5 * 10;
        return Math.round(41 + hydrationScore + stepScore + moodScore);
    }
    /**
     * 计算 value / total 的百分比（0-100），total 非正数时返回 0。
     */
    static percentage(value: number, total: number): number {
        if (total <= 0) {
            return 0;
        }
        return Math.round(Math.max(0, value) / total * 100);
    }
}
