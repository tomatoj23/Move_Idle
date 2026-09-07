// 校验器公共契约：结构化错误与报告。CLI 与编辑器（#28）共用。
export interface ValidationIssue {
  /** 内容类型 id（schema 文件名去 .json），结构级错误为 null */
  type: string | null;
  /** 对象 id；无法确定时为 null */
  id: string | null;
  /** 相对 content 根的 POSIX 风格路径 */
  file: string;
  /** 字段路径（如 mods[0].tiers[1].max）；文件/结构级为空串 */
  field: string;
  /** 人读原因（英文 ASCII，供 agent 检索） */
  reason: string;
}

export interface ValidationReport {
  ok: boolean;
  filesChecked: number;
  typeCounts: Record<string, number>;
  errors: ValidationIssue[];
}

export interface ValidatorOptions {
  contentDir: string;
  schemaDir: string;
}
