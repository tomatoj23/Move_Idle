#!/bin/sh
# 文档互引完整性检查（pre-commit 与 CI 同源，勿分叉）
#
# 来源：docs/research/doc-system-audit-2026-09-06.md 病灶 F2 —— 文档重排 / 回滚后遗留的悬空指针
# 是最容易腐、且人眼最难发现的一类问题（如 content-data-conventions.md 曾指向已删除的
# save-data-conventions.md）。本脚本把「文档重排后须 grep 引用锚点」这条纪律变成机器判据。
#
# 只检查仓库内 Markdown 之间的引用；跳过代码块、URL、.codebuddy/（被 gitignore，CI 上不存在）
# 与白名单（惰性创建的文件，存在与否都合法）。
#
# 用法：sh tools/check-doc-links.sh    （退出码 0 = 通过，1 = 存在悬空引用）

set -u

# 由 /domain-modeling 惰性创建，允许不存在；SKILL.md 是自制 skill 的定义文件，不在本仓库内
ALLOWLIST="CONTEXT-MAP.md SKILL.md"

files=""
for f in AGENTS.md CONTEXT.md; do
	[ -f "$f" ] && files="$files $f"
done
files="$files $(find docs schema -name '*.md' 2>/dev/null | sort)"

missing=""
for f in $files; do
	[ -f "$f" ] || continue
	dir=$(dirname "$f")
	in_fence=0
	while IFS= read -r line; do
		case "$line" in
			'```'*)
				in_fence=$(( (in_fence + 1) % 2 ))
				continue
				;;
		esac
		[ "$in_fence" -eq 1 ] && continue

		for tok in $(printf '%s\n' "$line" | grep -oE '[A-Za-z0-9_./-]+\.md' || true); do
			case "$tok" in
				*://*) continue ;;
				.codebuddy/*) continue ;;
			esac
			case " $ALLOWLIST " in *" $tok "*) continue ;; esac
			# 含路径：先按仓库根相对解析，再按引用文件所在目录解析
			if [ -e "$tok" ] || [ -e "$dir/$tok" ]; then continue; fi
			# 裸文件名：允许同名文件落在别处（如 AGENTS.md 里裸写 godot-standards.md）
			if [ -n "$(find . -path ./.git -prune -o -name "$(basename "$tok")" -print 2>/dev/null | head -n 1)" ]; then
				continue
			fi
			missing="$missing$f -> $tok\n"
		done
	done < "$f"
done

if [ -n "$missing" ]; then
	printf '悬空文档引用：\n'
	printf "$missing"
	printf '\n修复：改到正确的落点，或删除该引用。不要为了让本检查变绿而放宽模式。\n'
	exit 1
fi

printf 'doc-links OK\n'
exit 0
