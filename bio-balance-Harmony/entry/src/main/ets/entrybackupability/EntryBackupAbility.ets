import hilog from '@ohos.hilog';
import BackupExtensionAbility from '@ohos.application.BackupExtensionAbility';
import type { BundleVersion } from '@ohos.application.BackupExtensionAbility';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryBackupAbility';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'operation=backup');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion): Promise<void> {
    hilog.info(DOMAIN, TAG, 'operation=restore');
    await Promise.resolve();
  }
}
