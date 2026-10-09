import { describe, it, expect } from '@ohos/hypium';
import { NGFTaskExecutor, ngfSystem } from 'ngf_framework';

export default function systemIntegrationTest() {
  describe('SystemIntegrationFacadeTest', () => {
    it('exposes current task contract', 0, () => {
      const tasks = ngfSystem.getAllTasks();
      expect(tasks !== undefined).assertTrue();
    });

    it('accepts a typed task executor', 0, () => {
      const executor: NGFTaskExecutor = async (_taskId: string, update: (progress: number, total: number, message: string) => void): Promise<void> => {
        update(1, 1, 'done');
      };
      expect(executor !== undefined).assertTrue();
    });
  });
}
