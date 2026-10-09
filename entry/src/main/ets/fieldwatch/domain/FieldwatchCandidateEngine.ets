import { RadioKind, Sighting, SignatureClass } from './FieldwatchModels';
import { SignatureFleet, SignatureRule, SignatureRuleKind } from './signatures/FieldwatchSignatureModels';

/** 候选特征的指纹类型，对应原版 RuleKind 的子集。 */
export enum CandidateRuleKind { NAME_GLOB = 'NAME_GLOB', VENDOR_IE = 'VENDOR_IE', SERVICE_UUID = 'SERVICE_UUID', MANUFACTURER_DATA = 'MANUFACTURER_DATA', OUI = 'OUI' }

/** 一个可由用户审核后写入目录的候选特征。 */
export class SignatureCandidate {
  public id: string = '';
  public proposedName: string = '';
  public radioKind: RadioKind = RadioKind.BLE;
  public distinctRadios: number = 0;
  public ruleKind: CandidateRuleKind = CandidateRuleKind.NAME_GLOB;
  public ruleText: string = '';
  public why: string = '';
  public examples: string[] = [];
  public extraCount: number = 0;
  public notes: string = '';
  /** 原版 STRONG_MIN_RADIOS=8。 */
  strong(): boolean { return this.distinctRadios >= SignatureCandidateEngine.STRONG_MIN_RADIOS; }
}

/** 候选报告：族列表 + 统计口径。 */
export class CandidateReport {
  public families: SignatureCandidate[] = [];
  public uniqueRadios: number = 0;
  public unmatchedRadios: number = 0;
  public skippedRandomized: number = 0;
  public skippedHouseLike: number = 0;
  public skippedOther: number = 0;
}

/**
 * 签名族判定（对齐原版 `SignatureCandidates.FamilyVerdict`）。
 *
 * 它回答的不是「这台设备命中了什么」，而是：
 * **「从这里建一条签名，会覆盖一族设备还是只有这一台？」**
 *
 *   TAGGED   —— 已经命中目录里的签名
 *   SINGLE   —— 没有可聚类的空中唯一 ID，或没有别的设备共享它
 *   POSSIBLE —— 有 2~7 台共享（样本偏薄）
 *   STRONG   —— 有 >=8 台共享（目录级模式）
 */
export enum FamilyVerdict { STRONG = 'strong', POSSIBLE = 'possible', SINGLE = 'single', TAGGED = 'tagged' }

/** 族判定的结果。 */
export class SignatureFamilyHint {
  public verdict: FamilyVerdict;
  public title: string;
  public body: string;
  public liveCount: number;
  public ruleLabel: string;
  constructor(verdict: FamilyVerdict, title: string, body: string, liveCount: number, ruleLabel: string) {
    this.verdict = verdict; this.title = title; this.body = body;
    this.liveCount = liveCount; this.ruleLabel = ruleLabel;
  }
}

/** 聚类用的内部指纹。导出以便详情页的「特征族」判定复用同一套指纹口径。 */
export class CandidateFingerprint {
  public key: string = '';
  public kind: CandidateRuleKind = CandidateRuleKind.NAME_GLOB;
  public text: string = '';
  constructor(key: string = '', kind: CandidateRuleKind = CandidateRuleKind.NAME_GLOB, text: string = '') {
    this.key = key; this.kind = kind; this.text = text;
  }
}

/** 一个聚类。 */
class CandidateCluster {
  public key: string = '';
  public primary: CandidateFingerprint = new CandidateFingerprint();
  public radioKind: RadioKind = RadioKind.BLE;
  public members: Set<string> = new Set<string>();
  public radios: Sighting[] = [];
  public proposedName: string = '';
  public why: string = '';
}

/**
 * 把未匹配的日志信号源按「共享的空中唯一 ID」聚类。
 *
 * 移植自原版 domain/SignatureCandidates.kt 的核心算法：
 * 指纹提取 -> 分桶聚类 -> 重叠合并（>=60%）-> 过滤 -> 生成候选。
 * 频次口径是**不同 MAC 数**，不是报文数；也不是所有未知设备都算候选。
 */
export class SignatureCandidateEngine {
  /** 原版 MAX_FAMILIES。 */
  public static readonly MAX_FAMILIES: number = 20;
  /** 原版 MIN_RADIOS：少于两台不成族。 */
  public static readonly MIN_RADIOS: number = 2;
  /** 原版 STRONG_MIN_RADIOS。 */
  public static readonly STRONG_MIN_RADIOS: number = 8;

  analyze(sightings: Sighting[], signatures: SignatureFleet[]): CandidateReport {
    const report: CandidateReport = new CandidateReport();
    report.uniqueRadios = sightings.length;
    const unmatched: Sighting[] = sightings.filter((item: Sighting): boolean => item.signatureIds.length === 0);
    report.unmatchedRadios = unmatched.length;
    const usable: Sighting[] = [];
    unmatched.forEach((item: Sighting): void => {
      if (this.hasStructuredId(item)) usable.push(item);
      else if (this.isRandomized(item)) report.skippedRandomized += 1;
      else if (this.isHouseLikeName(item.name)) report.skippedHouseLike += 1;
      else report.skippedOther += 1;
    });
    const merged: CandidateCluster[] = this.mergeOverlapping(this.buildClusters(usable));
    const viable: CandidateCluster[] = merged.filter((item: CandidateCluster): boolean => item.members.size >= SignatureCandidateEngine.MIN_RADIOS);
    const clustered: Set<string> = new Set<string>();
    viable.forEach((item: CandidateCluster): void => { item.members.forEach((key: string): void => { clustered.add(key); }); });
    report.skippedOther += usable.filter((item: Sighting): boolean => !clustered.has(item.key)).length;
    const sorted: CandidateCluster[] = viable.slice();
    sorted.sort((left: CandidateCluster, right: CandidateCluster): number => {
      if (right.members.size !== left.members.size) return right.members.size - left.members.size;
      const rank: number = this.kindRank(left.primary.kind) - this.kindRank(right.primary.kind);
      if (rank !== 0) return rank;
      return left.proposedName.toLowerCase() < right.proposedName.toLowerCase() ? -1 : 1;
    });
    report.families = sorted.slice(0, SignatureCandidateEngine.MAX_FAMILIES).map((item: CandidateCluster): SignatureCandidate => this.toCandidate(item));
    return report;
  }

  /** 由候选生成一条可写入目录的特征（原版 suggestFleet）。规则直接来自候选的指纹。 */
  toFleet(candidate: SignatureCandidate, id: string): SignatureFleet {
    const rule: SignatureRule = new SignatureRule(this.ruleKindOf(candidate), candidate.ruleText, 0, '', candidate.radioKind);
    if (candidate.ruleKind === CandidateRuleKind.MANUFACTURER_DATA) {
      const parts: string[] = candidate.ruleText.split(' ');
      const company: number = parseInt(parts[0], 16);
      rule.companyId = isNaN(company) ? 0 : company;
      rule.dataPrefixHex = parts.length > 1 ? parts[1] : '';
    }
    const category: SignatureClass = candidate.radioKind === RadioKind.WIFI ? SignatureClass.ISP : SignatureClass.OTHER;
    return new SignatureFleet(id, candidate.proposedName, category, [rule], false);
  }
  private ruleKindOf(candidate: SignatureCandidate): SignatureRuleKind {
    if (candidate.ruleKind === CandidateRuleKind.NAME_GLOB) return SignatureRuleKind.NAME_GLOB;
    if (candidate.ruleKind === CandidateRuleKind.VENDOR_IE) return SignatureRuleKind.VENDOR_IE_OUI;
    if (candidate.ruleKind === CandidateRuleKind.SERVICE_UUID) return SignatureRuleKind.SERVICE_UUID;
    if (candidate.ruleKind === CandidateRuleKind.MANUFACTURER_DATA) return SignatureRuleKind.MANUFACTURER_DATA;
    return SignatureRuleKind.OUI;
  }

  /**
   * 对**单台**设备做签名族判定（对齐原版 `SignatureCandidates.assessFamily`）。
   *
   * 逻辑与原版逐条对应：
   *   1. 已命中目录签名 -> TAGGED，并说明「第二条签名仍可能双标记」；
   *   2. 取该设备的空中唯一 ID 指纹；没有可聚类的 -> SINGLE；
   *   3. 对每个指纹统计**其它多少台在场设备**共享它；
   *   4. 取共享数最多的那个指纹；< 2 台 -> SINGLE，>= 8 -> STRONG，否则 POSSIBLE。
   *
   * `live` 传当前在场的全部设备（含自己，会排除）。
   */
  assessFamily(device: Sighting, live: Sighting[], matchedNames: string[]): SignatureFamilyHint {
    if (matchedNames.length > 0) {
      return new SignatureFamilyHint(FamilyVerdict.TAGGED, '已标记',
        '匹配到特征 ' + matchedNames.join('、')
          + '。第二条特征仍可能同时标记这台无线电（服务 UUID、产品 OUI）。', 0, '');
    }
    const prints: CandidateFingerprint[] = this.fingerprintsOf(device);
    if (prints.length === 0) {
      return new SignatureFamilyHint(FamilyVerdict.SINGLE, '仅此一台',
        '没有可聚类的空中唯一 ID。随机地址、家用型名称与通用芯片会被跳过。', 0, '');
    }
    const others: Sighting[] = live.filter((item: Sighting): boolean => item.key !== device.key);
    // 预先算好每台在场设备的指纹键集合，避免在嵌套闭包里反复提取。
    const otherKeys: string[][] = others.map((item: Sighting): string[] =>
      this.fingerprintsOf(item).map((fp: CandidateFingerprint): string => fp.key));
    // 用**下标**记录最优，而不是在闭包里给外部变量赋值：
    // ArkTS 不会跟踪闭包内的赋值，之后读该变量会被窄化成 never。
    let bestCount: number = 0;
    let bestIndex: number = -1;
    for (let index: number = 0; index < prints.length; index += 1) {
      const key: string = prints[index].key;
      let count: number = 0;
      for (let other: number = 0; other < otherKeys.length; other += 1) {
        if (otherKeys[other].indexOf(key) >= 0) count += 1;
      }
      if (count > bestCount) { bestCount = count; bestIndex = index; }
    }
    if (bestIndex < 0 || bestCount < 2) {
      const shown: string = bestIndex < 0 ? '' : prints[bestIndex].text;
      return new SignatureFamilyHint(FamilyVerdict.SINGLE, '仅此一台',
        '在场设备里没有别的 MAC 共享这个空中唯一 ID。从这里建的签名基本只标到这一个地址。',
        bestCount, shown);
    }
    const best: CandidateFingerprint = prints[bestIndex];
    const strong: boolean = bestCount >= 8;
    const kindLabel: string = this.familyKindLabel(best.kind);
    return new SignatureFamilyHint(
      strong ? FamilyVerdict.STRONG : FamilyVerdict.POSSIBLE,
      strong ? '强特征族' : '可能的特征族',
      '在场有 ' + bestCount.toString() + ' 台共享同一个' + kindLabel + '。'
        + (strong ? '这是目录级模式，不是单个 MAC。' : '样本偏薄 —— 可能是目录级模式。'),
      bestCount, best.text);
  }

  /** 指纹类型的中文名（原版 `idKindLabel`）。 */
  private familyKindLabel(kind: CandidateRuleKind): string {
    if (kind === CandidateRuleKind.NAME_GLOB) return '名称模式';
    if (kind === CandidateRuleKind.VENDOR_IE) return '厂商 IE';
    if (kind === CandidateRuleKind.SERVICE_UUID) return '服务 UUID';
    if (kind === CandidateRuleKind.MANUFACTURER_DATA) return '厂商数据前缀';
    if (kind === CandidateRuleKind.OUI) return 'IEEE OUI';
    return '空中唯一 ID';
  }

  // ── 指纹提取（原版 fingerprintsOf） ──
  private fingerprintsOf(item: Sighting): CandidateFingerprint[] {
    const out: CandidateFingerprint[] = [];
    const glob: string = this.nameGlobOf(item.name);
    if (glob.length > 0 && !this.isHouseLikeName(item.name)) {
      out.push(new CandidateFingerprint('glob:' + glob, CandidateRuleKind.NAME_GLOB, glob));
    }
    item.facts.vendorIeOuis.forEach((raw: string): void => {
      const hex: string = this.hexOf(raw).substring(0, 6);
      if (hex.length === 6 && SignatureCandidateEngine.PROTOCOL_IE.indexOf(hex) < 0) {
        out.push(new CandidateFingerprint('ie:' + hex, CandidateRuleKind.VENDOR_IE, this.colonHex(hex)));
      }
    });
    if (item.kind === RadioKind.BLE) {
      item.facts.serviceUuids.forEach((uuid: string): void => {
        const short: string = this.uuidShort(uuid);
        if (short.length > 0 && SignatureCandidateEngine.GENERIC_UUID.indexOf(short) < 0) {
          out.push(new CandidateFingerprint('uuid:' + short, CandidateRuleKind.SERVICE_UUID, short));
        }
      });
      const company: number = item.facts.manufacturerId;
      const prefix: string = this.hexOf(item.facts.manufacturerDataHex).substring(0, 2);
      // manufacturerId 是普通 number，默认 0；<= 0 表示没有制造商数据，不能当成公司 ID 0x0000。
      if (company > 0 && SignatureCandidateEngine.BROAD_COMPANY.indexOf(company) < 0 && prefix.length === 2) {
        out.push(new CandidateFingerprint('mfg:' + this.companyKey(company) + ':' + prefix, CandidateRuleKind.MANUFACTURER_DATA, this.companyKey(company) + ' ' + prefix));
      }
    }
    if (!this.isRandomized(item) && !this.isChipModuleVendor(item.facts.manufacturer) && !this.isSkippedOuiVendor(item.facts.manufacturer)) {
      const oui: string = this.ouiOf(item.address);
      if (oui.length >= 8) out.push(new CandidateFingerprint('oui:' + oui, CandidateRuleKind.OUI, oui));
    }
    return out;
  }

  private buildClusters(radios: Sighting[]): CandidateCluster[] {
    const buckets: Map<string, CandidateFingerprint> = new Map<string, CandidateFingerprint>();
    const members: Map<string, Sighting[]> = new Map<string, Sighting[]>();
    radios.forEach((item: Sighting): void => {
      this.fingerprintsOf(item).forEach((fp: CandidateFingerprint): void => {
        if (!buckets.has(fp.key)) { buckets.set(fp.key, fp); members.set(fp.key, []); }
        const list: Sighting[] = members.get(fp.key) as Sighting[];
        list.push(item);
      });
    });
    const out: CandidateCluster[] = [];
    buckets.forEach((fp: CandidateFingerprint, key: string): void => {
      const distinct: Sighting[] = this.distinctRadios(members.get(key) as Sighting[]);
      const cluster: CandidateCluster | undefined = this.clusterOf(fp, distinct);
      if (cluster !== undefined) out.push(cluster);
    });
    return out;
  }

  private clusterOf(fp: CandidateFingerprint, distinct: Sighting[]): CandidateCluster | undefined {
    if (distinct.length < SignatureCandidateEngine.MIN_RADIOS) return undefined;
    const cluster: CandidateCluster = new CandidateCluster();
    cluster.key = fp.key;
    cluster.primary = fp;
    distinct.forEach((item: Sighting): void => { cluster.members.add(item.key); });
    cluster.radios = distinct;
    const count: number = distinct.length;
    if (fp.kind === CandidateRuleKind.NAME_GLOB) {
      cluster.radioKind = distinct[0].kind;
      cluster.proposedName = this.globName(fp.text);

    } else if (fp.kind === CandidateRuleKind.VENDOR_IE) {
      cluster.radioKind = RadioKind.WIFI;
      cluster.proposedName = 'Vendor IE ' + fp.text;

    } else if (fp.kind === CandidateRuleKind.SERVICE_UUID) {
      cluster.radioKind = RadioKind.BLE;
      cluster.proposedName = 'UUID ' + fp.text;

    } else if (fp.kind === CandidateRuleKind.MANUFACTURER_DATA) {
      cluster.radioKind = RadioKind.BLE;
      cluster.proposedName = 'Company ' + fp.text;

    } else {
      if (!this.ouiViable(distinct)) return undefined;
      cluster.radioKind = RadioKind.WIFI;
      const vendor: string = distinct[0].facts.manufacturer;
      cluster.proposedName = vendor.length > 0 ? vendor : fp.text;

    }
    return cluster;
  }

  /** 重叠合并：交集占较小族的 60% 以上即合并（原版 mergeOverlapping）。 */
  private mergeOverlapping(clusters: CandidateCluster[]): CandidateCluster[] {
    if (clusters.length <= 1) return clusters;
    const ranked: CandidateCluster[] = clusters.slice();
    ranked.sort((left: CandidateCluster, right: CandidateCluster): number => this.kindRank(left.primary.kind) - this.kindRank(right.primary.kind));
    let i: number = 0;
    while (i < ranked.length) {
      const keep: CandidateCluster = ranked[i];
      let j: number = i + 1;
      while (j < ranked.length) {
        const other: CandidateCluster = ranked[j];
        const smaller: number = Math.min(keep.members.size, other.members.size);
        let overlap: number = 0;
        keep.members.forEach((key: string): void => { if (other.members.has(key)) overlap += 1; });
        if (smaller > 0 && overlap * 10 >= smaller * 6) {
          other.members.forEach((key: string): void => { keep.members.add(key); });
          keep.radios = this.distinctRadios(keep.radios.concat(other.radios));
          ranked.splice(j, 1);
        } else {
          j += 1;
        }
      }
      i += 1;
    }
    return ranked;
  }

  private toCandidate(cluster: CandidateCluster): SignatureCandidate {
    const candidate: SignatureCandidate = new SignatureCandidate();
    candidate.id = cluster.key;
    candidate.proposedName = this.sanitizeName(cluster.proposedName);
    candidate.radioKind = cluster.radioKind;
    candidate.distinctRadios = cluster.members.size;
    candidate.ruleKind = cluster.primary.kind;
    candidate.ruleText = cluster.primary.text;
    // why 必须在这里生成：clusterOf 阶段的计数是合并前的，合并后 members 会变大。
    candidate.why = this.whyText(cluster);
    const labels: string[] = [];
    cluster.radios.forEach((item: Sighting): void => {
      const label: string = item.name.length > 0 ? item.name : item.address;
      if (label.length > 0 && labels.indexOf(label) < 0) labels.push(label);
    });
    candidate.examples = labels.slice(0, 2);
    candidate.extraCount = Math.max(0, labels.length - 2);
    const word: string = cluster.radioKind === RadioKind.WIFI ? '个 AP' : '个广播源';
    candidate.notes = candidate.distinctRadios.toString() + ' ' + word + ' 在日志中命中 ' + this.ruleLabel(cluster.primary) + '。共享的空中 ID，不是单台 MAC。';
    return candidate;
  }

  /** 合并完成后统一生成说明文字，保证计数与展示的台数一致。 */
  private whyText(cluster: CandidateCluster): string {
    const count: number = cluster.members.size;
    const kind: CandidateRuleKind = cluster.primary.kind;
    if (kind === CandidateRuleKind.NAME_GLOB) return '同一名称通配在 ' + count.toString() + ' 台信号源上 —— 不是家用 SSID。';
    if (kind === CandidateRuleKind.VENDOR_IE) return '同一 vendor IE 出现在 ' + count.toString() + ' 个 BSSID 上。不是 WPS / P2P。';
    if (kind === CandidateRuleKind.SERVICE_UUID) return '同一服务 UUID 出现在 ' + count.toString() + ' 个 BLE 广播源上。';
    if (kind === CandidateRuleKind.MANUFACTURER_DATA) return '同一制造商数据前缀出现在 ' + count.toString() + ' 个 BLE 广播源上。';
    return '同一 IEEE OUI 出现在 ' + count.toString() + ' 个稳定 BSSID 上。不是芯片模组前缀。';
  }
  private ruleLabel(fp: CandidateFingerprint): string {
    if (fp.kind === CandidateRuleKind.NAME_GLOB) return fp.text;
    if (fp.kind === CandidateRuleKind.VENDOR_IE) return 'vendor IE ' + fp.text;
    if (fp.kind === CandidateRuleKind.SERVICE_UUID) return 'UUID ' + fp.text;
    if (fp.kind === CandidateRuleKind.MANUFACTURER_DATA) return 'mfg ' + fp.text;
    return 'OUI ' + fp.text;
  }

  // ── 过滤规则（原版常量表，逐条移植） ──
  /** 名称通配：`[TOKEN]xxx` 或 `PREFIX-hex`。 */
  nameGlobOf(name: string): string {
    const text: string = name.trim();
    if (text.length === 0 || text.startsWith('<') || this.isHouseLikeName(text)) return '';
    const bracket: RegExp = /^\[([A-Za-z][A-Za-z0-9 ]{2,20})\]/;
    const matched: RegExpMatchArray | null = text.match(bracket);
    if (matched !== null) {
      const token: string = matched[1];
      if (token.length >= 3 && !this.isSkippedPrefix(token)) return '[' + token + ']*';
    }
    let sepAt: number = -1;
    for (let index: number = 0; index < text.length; index += 1) {
      const ch: string = text.charAt(index);
      if (ch === '-' || ch === '_') { sepAt = index; break; }
    }
    if (sepAt < 3) return '';
    const prefix: string = text.substring(0, sepAt);
    if (this.isSkippedPrefix(prefix) || this.isHouseLikeName(prefix)) return '';
    if (prefix.length < 3) return '';
    const sep: string = text.charAt(sepAt);
    let suffix: string = text.substring(sepAt + 1);
    const space: number = suffix.indexOf(' ');
    if (space >= 0) suffix = suffix.substring(0, space);
    const hex: string = suffix.replace(/[^A-Za-z0-9]/g, '');
    const hexOnly: boolean = hex.length > 0 && hex.length === suffix.length && /^[0-9a-fA-F]+$/.test(hex);
    if (hexOnly && hex.length >= 6) return prefix + sep + '?'.repeat(hex.length);
    return prefix + '*';
  }
  /** 家用 / 通用 SSID：原版 HOUSE_WORDS + 形如单词的短名。 */
  isHouseLikeName(name: string): boolean {
    const text: string = name.trim();
    if (text.length === 0) return true;
    const tokens: string[] = text.toLowerCase().split(/[\s\-_]+/).filter((item: string): boolean => item.length > 0);
    if (tokens.length === 0) return true;
    const first: string = tokens[0];
    if (SignatureCandidateEngine.HOUSE_WORDS.some((word: string): boolean => word === first || first.startsWith(word))) return true;
    if (tokens.some((item: string): boolean => item === 'guest' || item.startsWith('guest'))) {
      const product: boolean = /\d/.test(first) || (first === first.toUpperCase() && first.length >= 4);
      if (!product) return true;
    }
    const space: number = text.indexOf(' ');
    const token: string = space < 0 ? text : text.substring(0, space);
    const noSep: boolean = token.indexOf('-') < 0 && token.indexOf('_') < 0;
    const letters: boolean = /^[A-Za-z]+$/.test(token);
    const titleOrLower: boolean = token !== token.toUpperCase();
    return noSep && letters && titleOrLower && token.length >= 3 && token.length <= 18 && !/\d/.test(token);
  }
  private isSkippedPrefix(prefix: string): boolean {
    const text: string = prefix.trim().toUpperCase().replace(/^\[/, '').replace(/\]$/, '');
    return SignatureCandidateEngine.SKIP_PREFIX.indexOf(text) >= 0 || text.length < 3;
  }
  private isChipModuleVendor(vendor: string): boolean {
    const text: string = vendor.toLowerCase();
    return SignatureCandidateEngine.CHIP_VENDOR.some((item: string): boolean => text.indexOf(item) >= 0);
  }
  private isSkippedOuiVendor(vendor: string): boolean {
    const text: string = vendor.toLowerCase();
    return SignatureCandidateEngine.SKIP_OUI_VENDOR.some((item: string): boolean => text.indexOf(item) >= 0);
  }
  /** OUI 族可行性：>=3 台，或 >=2 个不同且非家用的名称。 */
  private ouiViable(members: Sighting[]): boolean {
    if (members.length < SignatureCandidateEngine.MIN_RADIOS) return false;
    const names: string[] = [];
    members.forEach((item: Sighting): void => {
      const name: string = item.name.trim();
      if (name.length > 0 && !this.isHouseLikeName(name) && names.indexOf(name) < 0) names.push(name);
    });
    return members.length >= 3 || names.length >= 2;
  }
  private hasStructuredId(item: Sighting): boolean {
    if (this.nameGlobOf(item.name).length > 0 && !this.isHouseLikeName(item.name)) return true;
    if (item.facts.vendorIeOuis.some((raw: string): boolean => SignatureCandidateEngine.PROTOCOL_IE.indexOf(this.hexOf(raw).substring(0, 6)) < 0)) return true;
    if (item.kind === RadioKind.BLE && item.facts.serviceUuids.some((uuid: string): boolean => {
      const short: string = this.uuidShort(uuid);
      return short.length > 0 && SignatureCandidateEngine.GENERIC_UUID.indexOf(short) < 0;
    })) return true;
    // 同上：manufacturerId <= 0 表示没有制造商数据，不是「一个非广播公司」。
    if (item.kind === RadioKind.BLE && item.facts.manufacturerId > 0
      && SignatureCandidateEngine.BROAD_COMPANY.indexOf(item.facts.manufacturerId) < 0) return true;
    // 星闪的设备类型由广播直接声明，是一个**可信的结构化标识** ——
    // 有它就意味着这台设备明确说了自己是什么，够格作为签名候选。
    if (item.kind === RadioKind.NEARLINK && item.facts.nearLinkDeviceClass >= 0) return true;
    return !this.isRandomized(item) && !this.isChipModuleVendor(item.facts.manufacturer) && !this.isSkippedOuiVendor(item.facts.manufacturer);
  }
  /** 随机 / 隐私 MAC：本地管理位（第一个字节的 bit 1）。 */
  private isRandomized(item: Sighting): boolean {
    const hex: string = this.hexOf(item.address);
    if (hex.length < 2) return false;
    const first: number = parseInt(hex.substring(0, 2), 16);
    if (isNaN(first)) return false;
    return (first & 0x02) !== 0;
  }

  // ── 小工具 ──
  private distinctRadios(list: Sighting[]): Sighting[] {
    const seen: Set<string> = new Set<string>();
    const out: Sighting[] = [];
    list.forEach((item: Sighting): void => { if (!seen.has(item.key)) { seen.add(item.key); out.push(item); } });
    return out;
  }
  private uuidShort(raw: string): string {
    const hex: string = this.hexOf(raw).toUpperCase();
    if (hex.length === 4) return hex;
    if (hex.length >= 8) return hex.substring(4, 8);
    return '';
  }
  private ouiOf(address: string): string {
    const hex: string = this.hexOf(address).toUpperCase();
    if (hex.length < 6) return '';
    return hex.substring(0, 2) + ':' + hex.substring(2, 4) + ':' + hex.substring(4, 6);
  }
  private hexOf(raw: string): string { return raw.replace(/[^A-Za-z0-9]/g, ''); }
  private colonHex(hex: string): string {
    const parts: string[] = [];
    for (let index: number = 0; index < hex.length; index += 2) parts.push(hex.substring(index, index + 2));
    return parts.join(':');
  }
  private companyKey(company: number): string {
    let text: string = company.toString(16).toUpperCase();
    while (text.length < 4) text = '0' + text;
    return '0x' + text;
  }
  private globName(glob: string): string {
    let cut: number = glob.length;
    const marks: string[] = ['*', '?', '-', '_'];
    marks.forEach((mark: string): void => { const at: number = glob.indexOf(mark); if (at >= 0 && at < cut) cut = at; });
    const text: string = glob.substring(0, cut);
    return text.length > 0 ? text : glob.replace(/\*+$/, '');
  }
  private sanitizeName(name: string): string {
    const cleaned: string = name.replace(/[^A-Za-z0-9 _.\-\[\]]/g, '').substring(0, 22);
    return cleaned.length > 0 ? cleaned : name.substring(0, 22);
  }
  private kindRank(kind: CandidateRuleKind): number {
    if (kind === CandidateRuleKind.NAME_GLOB) return 0;
    if (kind === CandidateRuleKind.VENDOR_IE) return 1;
    if (kind === CandidateRuleKind.SERVICE_UUID) return 2;
    if (kind === CandidateRuleKind.MANUFACTURER_DATA) return 3;
    return 4;
  }

  // ── 原版常量表 ──
  private static readonly HOUSE_WORDS: string[] = ['guest', 'xfinity', 'xfinitywifi', 'hilton', 'toast', 'attwifi', 'androidap', 'iphone', 'ipad', 'myspectrum'];
  private static readonly SKIP_PREFIX: string[] = ['DIRECT', 'GUEST', 'HOME', 'WIFI', 'WIRELESS', 'SETUP', 'NETGEAR', 'LINKSYS', 'DLINK', 'TP-LINK', 'TPLINK', 'ATT', 'XFINITY', 'HILTON', 'TOAST', 'IPHONE', 'IPAD', 'ANDROID', 'MYWIFI', 'DEFAULT', 'TY'];
  private static readonly CHIP_VENDOR: string[] = ['espressif', 'mediatek', 'ampak', 'qualcomm', 'universal global scientific', 'realtek'];
  private static readonly SKIP_OUI_VENDOR: string[] = ['google', 'apple', 'samsung electronics', 'microsoft'];
  private static readonly PROTOCOL_IE: string[] = ['0050F2', '000FAC', '506F9A', '8CFDF0'];
  private static readonly BROAD_COMPANY: number[] = [0x004C, 0x00E0, 0x0075, 0x0006, 0x0001, 0x00D2];
  private static readonly GENERIC_UUID: string[] = ['FEF3', 'FCF1', 'FCB2', 'FFF0', 'FEAA', 'FFF2', 'FD5A', 'FEED', 'FEDD', 'FD44', '1800', '1801', '180A', '180F', '1812', '181A', 'FE2C'];
}