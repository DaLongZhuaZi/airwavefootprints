import { RadioKind } from '../FieldwatchModels';
import {
  SIGNATURE_PACK_FORMAT, SIGNATURE_PACK_FORMAT_VERSION, SIGNATURE_PACK_LEGACY_FORMAT,
  SignatureDecodeEndian, SignatureDecodeField, SignatureDecodeSource, SignatureDecodeType, SignatureDecodeWhen,
  SignatureDecodeWhenOp, SignatureFleet, SignatureFleetDecode, SignaturePack, SignatureRule, SignatureRuleKind,
  signatureClassOf, signatureDecodeEndianOf, signatureDecodeSourceOf, signatureDecodeTypeOf, signatureDecodeWhenOpOf,
  signatureHexOnly, signatureRadioKindOf, signatureRuleKindOf
} from './FieldwatchSignatureModels';

/** 领域层只返回错误码，用户可见文案由 UI 通过资源解析。 */
export enum SignaturePackError {
  NONE = 'none',
  EMPTY = 'empty',
  MALFORMED = 'malformed',
  WRONG_FORMAT = 'wrong_format',
  NO_SIGNATURES = 'no_signatures',
  NO_STOCK = 'no_stock'
}

export class SignaturePackParseResult {
  public pack: SignaturePack = new SignaturePack();
  public error: SignaturePackError = SignaturePackError.NONE;
  public skippedDecode: number = 0;
  constructor(pack: SignaturePack = new SignaturePack(), error: SignaturePackError = SignaturePackError.NONE, skippedDecode: number = 0) {
    this.pack = pack; this.error = error; this.skippedDecode = skippedDecode;
  }
}

/**
 * 原始 JSON 形状。
 *
 * 注意：Android 侧的 Kotlin 序列化器会写出**显式 null**（stock 目录里有 437 个 `"radio": null`，
 * 以及 length/scale/unit/when 等上千个 null），而不是省略键。因此每个字段都必须同时容忍
 * `undefined` 与 `null`，否则解析会抛异常并让整个目录为空。
 */
interface RawSignatureRule {
  kind?: string | null; text?: string | null; companyId?: number | null; dataPrefixHex?: string | null;
  radio?: string | null; enabled?: boolean | null;
  /** 匹配偏移 / 分组 / 长度约束；旧目录没有这些键，缺省即 0（行为与从前一致）。 */
  offset?: number | null; group?: number | null; minLen?: number | null; maxLen?: number | null;
}
interface RawSignatureWhen {
  offset?: number | null; length?: number | null; op?: string | null; valueHex?: string | null; and?: RawSignatureWhen | null;
}
interface RawSignatureField {
  id?: string | null; label?: string | null; offset?: number | null; length?: number | null; type?: string | null;
  endian?: string | null; bitOffset?: number | null; bitWidth?: number | null; scale?: number | null;
  offsetAdd?: number | null; modulo?: number | null; unit?: string | null; enum?: Object | null; live?: boolean | null;
  liveEmphasis?: string[] | null; enumNotes?: Object | null; when?: RawSignatureWhen | null;
}
interface RawSignatureDecode {
  source?: string | null; serviceUuid?: string | null; companyId?: number | null; includeCompanyId?: boolean | null;
  fields?: RawSignatureField[] | null;
}
interface RawSignatureFleet {
  id?: string | null; name?: string | null; enabled?: boolean | null; matchAny?: boolean | null; colorIndex?: number | null;
  rules?: RawSignatureRule[] | null; minPeers?: number | null; peerWindowSec?: number | null; clusterByOui?: boolean | null;
  sequentialMac?: boolean | null; notes?: string | null; attentionNote?: string | null; builtIn?: boolean | null;
  userEdited?: boolean | null; deleted?: boolean | null;
  kind?: string | null; decode?: RawSignatureDecode | null;
}
interface RawSignaturePack {
  format?: string | null; formatVersion?: number | null; exportedAt?: string | null; appVersion?: string | null;
  catalogVersion?: number | null; fleets?: RawSignatureFleet[] | null;
}

function numberOr(value: number | null | undefined, fallback: number): number {
  return value === undefined || value === null || Number.isNaN(value) ? fallback : value;
}

function stringOr(value: string | null | undefined): string {
  return value === undefined || value === null ? '' : value;
}

function boolOr(value: boolean | null | undefined, fallback: boolean): boolean {
  return value === undefined || value === null ? fallback : value;
}

/** 可选数值：null 与 undefined 都表示“未设置”，不能退化成 0。 */
function optionalNumber(value: number | null | undefined): number | undefined {
  return value === undefined || value === null || Number.isNaN(value) ? undefined : value;
}

function stringArrayOr(value: string[] | null | undefined): string[] {
  return value === undefined || value === null ? [] : value;
}

/** 把 JSON 对象形式的命名值转成 Map；对象键是动态的，必须先枚举再断言。 */
function stringMapOf(source: Object | null | undefined): Map<string, string> | undefined {
  if (source === undefined || source === null) return undefined;
  const entries: [string, string][] = Object.entries(source) as [string, string][];
  if (entries.length === 0) return undefined;
  const map: Map<string, string> = new Map<string, string>();
  entries.forEach((entry: [string, string]): void => { map.set(entry[0], entry[1]); });
  return map;
}

function decodeWhenOf(raw: RawSignatureWhen | null | undefined): SignatureDecodeWhen | undefined {
  if (raw === undefined || raw === null) return undefined;
  const op: SignatureDecodeWhenOp = signatureDecodeWhenOpOf(stringOr(raw.op));
  const when: SignatureDecodeWhen = new SignatureDecodeWhen(numberOr(raw.offset, 0), op, stringOr(raw.valueHex), numberOr(raw.length, 1));
  when.and = decodeWhenOf(raw.and);
  return when;
}

function decodeFieldOf(raw: RawSignatureField, index: number): SignatureDecodeField {
  const field: SignatureDecodeField = new SignatureDecodeField();
  const label: string = stringOr(raw.label);
  field.id = stringOr(raw.id).length > 0 ? stringOr(raw.id) : 'field-' + index.toString();
  field.label = label.length > 0 ? label : field.id;
  field.offset = numberOr(raw.offset, 0);
  field.length = numberOr(raw.length, 0);
  field.type = signatureDecodeTypeOf(stringOr(raw.type));
  field.endian = signatureDecodeEndianOf(stringOr(raw.endian));
  field.bitOffset = numberOr(raw.bitOffset, -1);
  field.bitWidth = numberOr(raw.bitWidth, -1);
  field.scale = optionalNumber(raw.scale);
  field.offsetAdd = optionalNumber(raw.offsetAdd);
  field.modulo = optionalNumber(raw.modulo);
  field.unit = stringOr(raw.unit);
  field.enumLabels = stringMapOf(raw.enum);
  field.live = boolOr(raw.live, false);
  field.liveEmphasis = stringArrayOr(raw.liveEmphasis);
  field.enumNotes = stringMapOf(raw.enumNotes);
  field.gate = decodeWhenOf(raw.when);
  return field;
}

function decodeOf(raw: RawSignatureDecode | null | undefined): SignatureFleetDecode | undefined {
  if (raw === undefined || raw === null) return undefined;
  const source: SignatureDecodeSource = signatureDecodeSourceOf(stringOr(raw.source));
  const fields: SignatureDecodeField[] = [];
  const rawFields: RawSignatureField[] = raw.fields === undefined || raw.fields === null ? [] : raw.fields;
  rawFields.forEach((item: RawSignatureField, index: number): void => { fields.push(decodeFieldOf(item, index)); });
  return new SignatureFleetDecode(source, fields, stringOr(raw.serviceUuid), numberOr(raw.companyId, 0), boolOr(raw.includeCompanyId, false));
}

function ruleOf(raw: RawSignatureRule): SignatureRule {
  const kind: SignatureRuleKind = signatureRuleKindOf(stringOr(raw.kind));
  const radio: RadioKind | undefined = signatureRadioKindOf(stringOr(raw.radio));
  const rule: SignatureRule = new SignatureRule(kind, stringOr(raw.text), numberOr(raw.companyId, 0),
    stringOr(raw.dataPrefixHex), radio, boolOr(raw.enabled, true));
  rule.offset = numberOr(raw.offset, 0);
  rule.group = numberOr(raw.group, 0);
  rule.minLen = numberOr(raw.minLen, 0);
  rule.maxLen = numberOr(raw.maxLen, 0);
  return rule;
}

function fleetOf(raw: RawSignatureFleet): SignatureFleet {
  const fleet: SignatureFleet = new SignatureFleet(stringOr(raw.id), stringOr(raw.name), signatureClassOf(stringOr(raw.kind)));
  fleet.enabled = boolOr(raw.enabled, true);
  fleet.matchAny = boolOr(raw.matchAny, true);
  fleet.colorIndex = numberOr(raw.colorIndex, 0);
  fleet.minPeers = numberOr(raw.minPeers, 0);
  fleet.peerWindowSec = numberOr(raw.peerWindowSec, 60);
  fleet.clusterByOui = boolOr(raw.clusterByOui, false);
  fleet.sequentialMac = boolOr(raw.sequentialMac, false);
  fleet.notes = stringOr(raw.notes);
  fleet.attentionNote = stringOr(raw.attentionNote);
  fleet.builtIn = boolOr(raw.builtIn, false);
  fleet.userEdited = boolOr(raw.userEdited, false);
  fleet.deleted = boolOr(raw.deleted, false);
  fleet.decode = decodeOf(raw.decode);
  const rawRules: RawSignatureRule[] = raw.rules === undefined || raw.rules === null ? [] : raw.rules;
  rawRules.forEach((item: RawSignatureRule): void => { fleet.rules.push(ruleOf(item)); });
  return fleet;
}

/**
 * 解析 signature pack。未知键会被忽略（旧版本读新包时基础签名仍可匹配）；
 * 未知 decode source 只丢弃解码映射并计数，不丢弃签名本身。
 */
export function parseSignaturePack(text: string): SignaturePackParseResult {
  const trimmed: string = text.replace(/^\uFEFF/, '').trim();
  if (trimmed.length === 0) return new SignaturePackParseResult(new SignaturePack(), SignaturePackError.EMPTY);
  let raw: RawSignaturePack;
  try {
    raw = JSON.parse(trimmed) as RawSignaturePack;
  } catch (error) {
    return new SignaturePackParseResult(new SignaturePack(), SignaturePackError.MALFORMED);
  }
  if (raw === null || raw === undefined) return new SignaturePackParseResult(new SignaturePack(), SignaturePackError.MALFORMED);
  const format: string = stringOr(raw.format);
  if (format !== SIGNATURE_PACK_FORMAT && format !== SIGNATURE_PACK_LEGACY_FORMAT) {
    return new SignaturePackParseResult(new SignaturePack(), SignaturePackError.WRONG_FORMAT);
  }
  const rawFleets: RawSignatureFleet[] = raw.fleets === undefined || raw.fleets === null ? [] : raw.fleets;
  if (rawFleets.length === 0) return new SignaturePackParseResult(new SignaturePack(), SignaturePackError.NO_SIGNATURES);
  const pack: SignaturePack = new SignaturePack();
  pack.format = SIGNATURE_PACK_FORMAT;
  pack.formatVersion = numberOr(raw.formatVersion, SIGNATURE_PACK_FORMAT_VERSION);
  pack.exportedAt = stringOr(raw.exportedAt);
  pack.appVersion = stringOr(raw.appVersion);
  pack.catalogVersion = numberOr(raw.catalogVersion, 0);
  let skippedDecode: number = 0;
  rawFleets.forEach((item: RawSignatureFleet): void => {
    const fleet: SignatureFleet = fleetOf(item);
    if (fleet.decode !== undefined && fleet.decode.source === SignatureDecodeSource.UNSUPPORTED) {
      fleet.decode = undefined;
      skippedDecode += 1;
    }
    pack.fleets.push(fleet);
  });
  return new SignaturePackParseResult(pack, SignaturePackError.NONE, skippedDecode);
}

function quote(value: string): string { return JSON.stringify(value); }

function mapJson(map: Map<string, string> | undefined): string {
  if (map === undefined || map.size === 0) return '{}';
  const parts: string[] = [];
  map.forEach((value: string, key: string): void => { parts.push(quote(key) + ': ' + quote(value)); });
  return '{ ' + parts.join(', ') + ' }';
}

function whenJson(when: SignatureDecodeWhen, pad: string): string {
  const parts: string[] = [];
  parts.push(pad + '  "offset": ' + when.offset.toString());
  parts.push(pad + '  "length": ' + when.length.toString());
  parts.push(pad + '  "op": ' + quote(when.op));
  parts.push(pad + '  "valueHex": ' + quote(when.valueHex));
  if (when.and !== undefined) parts.push(pad + '  "and": ' + whenJson(when.and, pad + '  '));
  return '{\n' + parts.join(',\n') + '\n' + pad + '}';
}

function fieldJson(field: SignatureDecodeField, pad: string): string {
  const parts: string[] = [];
  parts.push(pad + '  "id": ' + quote(field.id));
  parts.push(pad + '  "label": ' + quote(field.label));
  parts.push(pad + '  "offset": ' + field.offset.toString());
  if (field.length > 0) parts.push(pad + '  "length": ' + field.length.toString());
  parts.push(pad + '  "type": ' + quote(field.type));
  parts.push(pad + '  "endian": ' + quote(field.endian));
  if (field.bitOffset >= 0) parts.push(pad + '  "bitOffset": ' + field.bitOffset.toString());
  if (field.bitWidth >= 0) parts.push(pad + '  "bitWidth": ' + field.bitWidth.toString());
  if (field.scale !== undefined) parts.push(pad + '  "scale": ' + field.scale.toString());
  if (field.offsetAdd !== undefined) parts.push(pad + '  "offsetAdd": ' + field.offsetAdd.toString());
  if (field.modulo !== undefined) parts.push(pad + '  "modulo": ' + field.modulo.toString());
  if (field.unit.length > 0) parts.push(pad + '  "unit": ' + quote(field.unit));
  if (field.enumLabels !== undefined && field.enumLabels.size > 0) parts.push(pad + '  "enum": ' + mapJson(field.enumLabels));
  if (field.live) parts.push(pad + '  "live": true');
  if (field.liveEmphasis.length > 0) parts.push(pad + '  "liveEmphasis": ' + JSON.stringify(field.liveEmphasis));
  if (field.enumNotes !== undefined && field.enumNotes.size > 0) parts.push(pad + '  "enumNotes": ' + mapJson(field.enumNotes));
  if (field.gate !== undefined) parts.push(pad + '  "when": ' + whenJson(field.gate, pad + '  '));
  return '{\n' + parts.join(',\n') + '\n' + pad + '}';
}

function decodeJson(decode: SignatureFleetDecode, pad: string): string {
  const parts: string[] = [];
  parts.push(pad + '  "source": ' + quote(decode.source === SignatureDecodeSource.SERVICE_DATA ? 'serviceData' : 'manufacturerData'));
  if (decode.serviceUuid.length > 0) parts.push(pad + '  "serviceUuid": ' + quote(decode.serviceUuid));
  if (decode.companyId > 0) parts.push(pad + '  "companyId": ' + decode.companyId.toString());
  if (decode.includeCompanyId) parts.push(pad + '  "includeCompanyId": true');
  if (decode.fields.length > 0) {
    const fields: string[] = [];
    decode.fields.forEach((field: SignatureDecodeField): void => { fields.push(fieldJson(field, pad + '    ')); });
    parts.push(pad + '  "fields": [\n' + fields.join(',\n') + '\n' + pad + '  ]');
  }
  return '{\n' + parts.join(',\n') + '\n' + pad + '}';
}

function ruleJson(rule: SignatureRule, pad: string): string {
  const parts: string[] = [];
  parts.push(pad + '  "kind": ' + quote(rule.kind));
  parts.push(pad + '  "text": ' + quote(rule.text));
  parts.push(pad + '  "companyId": ' + rule.companyId.toString());
  parts.push(pad + '  "dataPrefixHex": ' + quote(rule.dataPrefixHex));
  // 用 radioTag() 而不是三元表达式：星闪写成 'BLE' 会让规则在重新加载后变成 BLE 规则。
  if (rule.radio !== undefined) parts.push(pad + '  "radio": ' + quote(rule.radioTag()));
  parts.push(pad + '  "enabled": ' + (rule.enabled ? 'true' : 'false'));
  // 仅在非默认值时输出，让不带这些特性的既有条目保持字节级不变。
  if (rule.offset > 0) parts.push(pad + '  "offset": ' + rule.offset.toString());
  if (rule.group > 0) parts.push(pad + '  "group": ' + rule.group.toString());
  if (rule.minLen > 0) parts.push(pad + '  "minLen": ' + rule.minLen.toString());
  if (rule.maxLen > 0) parts.push(pad + '  "maxLen": ' + rule.maxLen.toString());
  return '{\n' + parts.join(',\n') + '\n' + pad + '}';
}

function fleetJson(fleet: SignatureFleet, pad: string): string {
  const parts: string[] = [];
  parts.push(pad + '  "id": ' + quote(fleet.id));
  parts.push(pad + '  "name": ' + quote(fleet.name));
  parts.push(pad + '  "enabled": ' + (fleet.enabled ? 'true' : 'false'));
  parts.push(pad + '  "matchAny": ' + (fleet.matchAny ? 'true' : 'false'));
  parts.push(pad + '  "colorIndex": ' + fleet.colorIndex.toString());
  const rules: string[] = [];
  fleet.rules.forEach((rule: SignatureRule): void => { rules.push(ruleJson(rule, pad + '    ')); });
  parts.push(pad + '  "rules": [\n' + rules.join(',\n') + '\n' + pad + '  ]');
  if (fleet.minPeers > 0) parts.push(pad + '  "minPeers": ' + fleet.minPeers.toString());
  if (fleet.peerWindowSec !== 60) parts.push(pad + '  "peerWindowSec": ' + fleet.peerWindowSec.toString());
  if (fleet.clusterByOui) parts.push(pad + '  "clusterByOui": true');
  if (fleet.sequentialMac) parts.push(pad + '  "sequentialMac": true');
  if (fleet.notes.length > 0) parts.push(pad + '  "notes": ' + quote(fleet.notes));
  if (fleet.attentionNote.length > 0) parts.push(pad + '  "attentionNote": ' + quote(fleet.attentionNote));
  if (fleet.builtIn) parts.push(pad + '  "builtIn": true');
  if (fleet.userEdited) parts.push(pad + '  "userEdited": true');
  if (fleet.deleted) parts.push(pad + '  "deleted": true');
  parts.push(pad + '  "kind": ' + quote(fleet.category.toUpperCase()));
  if (fleet.decode !== undefined) parts.push(pad + '  "decode": ' + decodeJson(fleet.decode, pad + '  '));
  return '{\n' + parts.join(',\n') + '\n' + pad + '}';
}

/** 序列化为与 Android Fieldwatch 互通的 fieldwatch-signatures JSON。 */
export function encodeSignaturePack(pack: SignaturePack): string {
  const fleets: string[] = [];
  pack.fleets.forEach((fleet: SignatureFleet): void => { fleets.push(fleetJson(fleet, '    ')); });
  const head: string[] = [];
  head.push('  "format": ' + quote(SIGNATURE_PACK_FORMAT));
  head.push('  "formatVersion": ' + SIGNATURE_PACK_FORMAT_VERSION.toString());
  head.push('  "exportedAt": ' + quote(pack.exportedAt));
  head.push('  "appVersion": ' + quote(pack.appVersion));
  head.push('  "catalogVersion": ' + pack.catalogVersion.toString());
  head.push('  "fleets": [\n' + fleets.join(',\n') + '\n  ]');
  return '{\n' + head.join(',\n') + '\n}\n';
}

/** 规则身份键：用于去重、指纹和 stock 覆盖时识别“同一条规则”。 */
export function signatureRuleKey(rule: SignatureRule): string {
  const radio: string = rule.radioTag();
  // offset / group / 长度约束必须计入身份键：
  // 否则「同前缀、不同偏移」的两条规则会被当成同一条，去重时静默丢掉一条。
  return [rule.kind, rule.text.toUpperCase(), rule.companyId.toString(), signatureHexOnly(rule.dataPrefixHex), radio,
    rule.enabled ? 'true' : 'false', rule.offset.toString(), rule.group.toString(),
    rule.minLen.toString(), rule.maxLen.toString()].join('|');
}

/** 签名指纹：不依赖 id，用于识别“内容相同但 id 不同”的导入包。 */
export function signatureFleetFingerprint(fleet: SignatureFleet): string {
  const keys: string[] = fleet.rules.map((rule: SignatureRule): string => signatureRuleKey(rule));
  keys.sort();
  return [
    fleet.matchAny ? 'ANY' : 'ALL',
    fleet.minPeers.toString(),
    fleet.peerWindowSec.toString(),
    fleet.clusterByOui ? 'true' : 'false',
    fleet.sequentialMac ? 'true' : 'false',
    keys.join(';')
  ].join('|');
}

export class SignatureImportResult {
  public added: number = 0;
  public merged: number = 0;
  public skipped: number = 0;
  public renamed: number = 0;
  public error: SignaturePackError = SignaturePackError.NONE;
  constructor(added: number = 0, merged: number = 0, skipped: number = 0, renamed: number = 0, error: SignaturePackError = SignaturePackError.NONE) {
    this.added = added; this.merged = merged; this.skipped = skipped; this.renamed = renamed; this.error = error;
  }
}

export class StockCatalogUpdateResult {
  public added: number = 0;
  public updated: number = 0;
  public catalogVersion: number = 0;
  public skippedDecode: number = 0;
  public error: SignaturePackError = SignaturePackError.NONE;
  constructor(added: number = 0, updated: number = 0, catalogVersion: number = 0, skippedDecode: number = 0, error: SignaturePackError = SignaturePackError.NONE) {
    this.added = added; this.updated = updated; this.catalogVersion = catalogVersion; this.skippedDecode = skippedDecode; this.error = error;
  }
}

function uniqueSignatureName(desired: string, taken: Set<string>): string {
  const base: string = desired.trim().length > 0 ? desired.trim() : 'Imported signature';
  if (!taken.has(base.toLowerCase())) {
    taken.add(base.toLowerCase());
    return base;
  }
  let candidate: string = base + ' (imported)';
  if (!taken.has(candidate.toLowerCase())) {
    taken.add(candidate.toLowerCase());
    return candidate;
  }
  let index: number = 2;
  while (taken.has((base + ' (imported ' + index.toString() + ')').toLowerCase())) index += 1;
  candidate = base + ' (imported ' + index.toString() + ')';
  taken.add(candidate.toLowerCase());
  return candidate;
}

/**
 * 导入合并：同 id 追加缺失规则并补齐解码映射；新行按指纹去重；重名自动改名。
 * 不删除任何现有目录内容。
 */
export function mergeSignatureFleets(existing: SignatureFleet[], incoming: SignatureFleet[], stockIds: Set<string>): SignatureFleet[] {
  const next: SignatureFleet[] = existing.slice();
  const indexById: Map<string, number> = new Map<string, number>();
  next.forEach((fleet: SignatureFleet, index: number): void => { indexById.set(fleet.id, index); });
  const fingerprints: Set<string> = new Set<string>();
  next.forEach((fleet: SignatureFleet): void => { fingerprints.add(signatureFleetFingerprint(fleet)); });
  const names: Set<string> = new Set<string>();
  next.forEach((fleet: SignatureFleet): void => { names.add(fleet.name.trim().toLowerCase()); });
  incoming.forEach((raw: SignatureFleet): void => {
    if (raw.rules.length === 0) return;
    const id: string = raw.id.length > 0 ? raw.id : 'sig-' + Date.now().toString() + '-' + Math.floor(Math.random() * 100000).toString();
    const existingIndex: number | undefined = indexById.get(id);
    if (existingIndex !== undefined) {
      const local: SignatureFleet = next[existingIndex];
      const have: Set<string> = new Set<string>();
      local.rules.forEach((rule: SignatureRule): void => { have.add(signatureRuleKey(rule)); });
      const missing: SignatureRule[] = raw.rules.filter((rule: SignatureRule): boolean => !have.has(signatureRuleKey(rule)));
      const decode: SignatureFleetDecode | undefined = raw.decode !== undefined ? raw.decode : local.decode;
      const decodeChanged: boolean = (raw.decode !== undefined) && (local.decode === undefined || raw.decode !== local.decode);
      if (missing.length === 0 && !decodeChanged) return;
      fingerprints.delete(signatureFleetFingerprint(local));
      missing.forEach((rule: SignatureRule): void => { local.rules.push(rule); });
      if (raw.decode !== undefined) local.decode = decode;
      fingerprints.add(signatureFleetFingerprint(local));
      return;
    }
    const fingerprint: string = signatureFleetFingerprint(raw);
    if (fingerprints.has(fingerprint)) return;
    const imported: SignatureFleet = new SignatureFleet(id, uniqueSignatureName(raw.name, names), raw.category, raw.rules.slice(), stockIds.has(id));
    imported.enabled = raw.enabled;
    imported.matchAny = raw.matchAny;
    imported.colorIndex = raw.colorIndex;
    imported.minPeers = raw.minPeers;
    imported.peerWindowSec = raw.peerWindowSec;
    imported.clusterByOui = raw.clusterByOui;
    imported.sequentialMac = raw.sequentialMac;
    imported.notes = raw.notes;
    imported.attentionNote = raw.attentionNote;
    imported.decode = raw.decode;
    next.push(imported);
    indexById.set(imported.id, next.length - 1);
    fingerprints.add(fingerprint);
  });
  next.sort((first: SignatureFleet, second: SignatureFleet): number => first.name.toLowerCase().localeCompare(second.name.toLowerCase()));
  return next;
}

function stockFieldsDiffer(local: SignatureFleet, overlaid: SignatureFleet): boolean {
  if (local.name !== overlaid.name) return true;
  if (local.category !== overlaid.category) return true;
  if (local.colorIndex !== overlaid.colorIndex) return true;
  if (local.notes !== overlaid.notes) return true;
  if (local.attentionNote !== overlaid.attentionNote) return true;
  if (local.matchAny !== overlaid.matchAny) return true;
  if (local.minPeers !== overlaid.minPeers) return true;
  if (local.peerWindowSec !== overlaid.peerWindowSec) return true;
  if (local.clusterByOui !== overlaid.clusterByOui) return true;
  if (local.sequentialMac !== overlaid.sequentialMac) return true;
  const localKeys: string = local.rules.map((rule: SignatureRule): string => signatureRuleKey(rule)).join(',');
  const overlaidKeys: string = overlaid.rules.map((rule: SignatureRule): string => signatureRuleKey(rule)).join(',');
  return localKeys !== overlaidKeys;
}

/**
 * 用新 stock 覆盖旧 stock 行：保留用户对该行的启用/停用状态、用户追加的额外规则和自定义行。
 * 不触碰关注列表与设置。
 */
export function overlayStockFleets(existing: SignatureFleet[], incoming: SignatureFleet[]): SignatureFleet[] {
  const stockIn: SignatureFleet[] = incoming.filter((fleet: SignatureFleet): boolean => (fleet.builtIn || fleet.id.startsWith('fleet-')) && fleet.rules.length > 0);
  const next: SignatureFleet[] = existing.slice();
  if (stockIn.length === 0) return next;
  const indexById: Map<string, number> = new Map<string, number>();
  next.forEach((fleet: SignatureFleet, index: number): void => { indexById.set(fleet.id, index); });
  stockIn.forEach((stock: SignatureFleet): void => {
    const existingIndex: number | undefined = indexById.get(stock.id);
    if (existingIndex === undefined) {
      const created: SignatureFleet = new SignatureFleet(stock.id, stock.name, stock.category, stock.rules.slice(), true);
      created.enabled = stock.enabled;
      created.matchAny = stock.matchAny;
      created.colorIndex = stock.colorIndex;
      created.minPeers = stock.minPeers;
      created.peerWindowSec = stock.peerWindowSec;
      created.clusterByOui = stock.clusterByOui;
      created.sequentialMac = stock.sequentialMac;
      created.notes = stock.notes;
      created.attentionNote = stock.attentionNote;
      created.decode = stock.decode;
      next.push(created);
      indexById.set(created.id, next.length - 1);
      return;
    }
    const local: SignatureFleet = next[existingIndex];
    if (!local.builtIn) return;
    // 用户删掉的内置行：保持墓碑，**不要复活**。
    // 没有这一条时，删除内置特征只生效到下次启动 —— 覆盖逻辑会把它原样加回来。
    if (local.deleted) return;
    // 用户手工编辑过的内置行：整行以本地为准。
    // 用户已显式接管这一行，再悄悄塞回 stock 的名称 / 规则会与他的编辑打架；
    // 要回到出厂值有「恢复默认目录」这条明确路径。
    if (local.userEdited) return;
    const stockKeys: Set<string> = new Set<string>();
    stock.rules.forEach((rule: SignatureRule): void => { stockKeys.add(signatureRuleKey(rule)); });
    const extras: SignatureRule[] = local.rules.filter((rule: SignatureRule): boolean => !stockKeys.has(signatureRuleKey(rule)));
    const overlaid: SignatureFleet = new SignatureFleet(stock.id, stock.name, stock.category, stock.rules.slice(), true);
    overlaid.enabled = local.enabled;
    overlaid.matchAny = stock.matchAny;
    overlaid.colorIndex = stock.colorIndex;
    overlaid.minPeers = stock.minPeers;
    overlaid.peerWindowSec = stock.peerWindowSec;
    overlaid.clusterByOui = stock.clusterByOui;
    overlaid.sequentialMac = stock.sequentialMac;
    overlaid.notes = stock.notes;
    overlaid.attentionNote = stock.attentionNote;
    overlaid.decode = stock.decode !== undefined ? stock.decode : local.decode;
    extras.forEach((rule: SignatureRule): void => { overlaid.rules.push(rule); });
    if (stockFieldsDiffer(local, overlaid)) next[existingIndex] = overlaid;
  });
  const incomingIds: Set<string> = new Set<string>();
  stockIn.forEach((fleet: SignatureFleet): void => { incomingIds.add(fleet.id); });
  const pruned: SignatureFleet[] = next.filter((fleet: SignatureFleet): boolean => !(fleet.builtIn && fleet.id === 'fleet-unknown' && !incomingIds.has('fleet-unknown')));
  pruned.sort((first: SignatureFleet, second: SignatureFleet): number => first.name.toLowerCase().localeCompare(second.name.toLowerCase()));
  return pruned;
}
