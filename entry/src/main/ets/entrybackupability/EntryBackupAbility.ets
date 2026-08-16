import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';

export default class EntryBackupAbility extends BackupExtensionAbility {
  onBackup(): void {
    console.info('[EntryBackupAbility] onBackup');
  }

  onRestore(bundleVersion: BundleVersion): void {
    console.info(`[EntryBackupAbility] onRestore ${bundleVersion.name} ${bundleVersion.code}`);
  }
}
