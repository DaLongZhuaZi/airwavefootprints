import { describe, it, expect } from '@ohos/hypium';
import {
  decodeRatingState, encodeRatingState, markRatingDeclined, markRatingRated, markRatingShown,
  RatingPromptState, RATING_COOLDOWN_MS, shouldPromptRating, storeDetailUri
} from '../main/ets/fieldwatch/domain/FieldwatchRatingPrompt';

export default function fieldwatchRatingPromptTest() {
  describe('FieldwatchRatingPrompt', () => {
    // 文档验收：同一用户 30 天内最多出现 1 次。
    it('shows at most once per 30 days', 0, () => {
      const now: number = 1000000000;
      const fresh: RatingPromptState = new RatingPromptState();
      expect(shouldPromptRating(fresh, now)).assertTrue();
      const shown: RatingPromptState = markRatingShown(fresh, now);
      expect(shouldPromptRating(shown, now + 1000)).assertFalse();
      // 差一毫秒仍在冷却期内。
      expect(shouldPromptRating(shown, now + RATING_COOLDOWN_MS - 1)).assertFalse();
      // 满 30 天可以再来一次。
      expect(shouldPromptRating(shown, now + RATING_COOLDOWN_MS)).assertTrue();
    });

    // 文档验收：拒绝后不再出现 —— 是**永久**，不是「下个 30 天再说」。
    it('never shows again after the user declines', 0, () => {
      const now: number = 1000000000;
      const declined: RatingPromptState = markRatingDeclined(new RatingPromptState(), now);
      expect(declined.declined).assertTrue();
      expect(shouldPromptRating(declined, now + 1)).assertFalse();
      expect(shouldPromptRating(declined, now + RATING_COOLDOWN_MS * 10)).assertFalse();
    });

    it('never shows again once the user has rated', 0, () => {
      const now: number = 1000000000;
      const rated: RatingPromptState = markRatingRated(new RatingPromptState(), now);
      expect(rated.rated).assertTrue();
      expect(shouldPromptRating(rated, now + RATING_COOLDOWN_MS * 10)).assertFalse();
    });

    // 状态要能落盘再读回，否则每次冷启动都会重新弹。
    it('round trips its state through the compact encoding', 0, () => {
      const now: number = 1793043000000;
      const shown: RatingPromptState = markRatingShown(new RatingPromptState(), now);
      const back: RatingPromptState = decodeRatingState(encodeRatingState(shown));
      expect(back.lastShownAt).assertEqual(now);
      expect(back.declined).assertFalse();
      expect(back.rated).assertFalse();
      // 坏数据当成「从未展示」，不能崩。
      expect(decodeRatingState('').lastShownAt).assertEqual(0);
      expect(decodeRatingState('garbage').lastShownAt).assertEqual(0);
      expect(decodeRatingState('1|0').lastShownAt).assertEqual(0);
    });

    it('builds the store detail link from the bundle name', 0, () => {
      const uri: string = storeDetailUri('com.dlzz.airwavefootprints');
      expect(uri.indexOf('store://appgallery.huawei.com/app/detail?id=') === 0).assertTrue();
      expect(uri.indexOf('com.dlzz.airwavefootprints') > 0).assertTrue();
    });
  });
}
