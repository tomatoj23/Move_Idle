# Windows / PowerShell 环境约束（本机）

状态：生效（2026-09-06）｜范围：本机开发环境（Windows + PowerShell 5.1 + Steam 版 Godot）。仓库 CI 跑在 Linux，**本页约束只对本地命令成立**。

触发：执行任何 `git` / `gh` / Godot CLI，或任何含非 ASCII（中文）的内容要落盘 / 传出前。

## 中文（非 ASCII）落盘通道

- PowerShell 通道（here-string、`Add-Content`、`>` / `Out-File` 重定向，**以及任何命令行参数里内嵌中文**）会把 UTF-8 中文误读成 GBK，**乱码且事后不可修**——乱码字节连编辑工具的 `old_str` 都无法精确匹配。
- 一切中文内容一律先用 `write_to_file` / `replace_in_file` 写成 UTF-8 文件，再让命令消费：
  - `git commit -F <file>`
  - `gh ... --body-file <file>`
  - `gh api ... -F body=@<file>` / `--input <file>`
- 临时文件同样必须用 `write_to_file` 生成，用完即删。
- **PowerShell 只碰 ASCII。** 无中文参数的命令（如 `gh issue edit --add-label ...`）可裸跑。
- 读 gh 的中文输出：`cmd /c "gh ... > 文件"` 落盘后 `read_file`；**`cmd /c` 必须独占一条 execute_command**（后接 `;` 会碎）。
- 验证中文是否落对：`git log --format=%B --output=<file>` 落盘再读文件。控制台 / 管道里的中文输出一律不可信。

## 命令输出捕获（Godot 两条路，按序选）

1. **首选**：`Start-Process -FilePath <godot> -ArgumentList ... -RedirectStandardOutput <f1> -RedirectStandardError <f2> -NoNewWindow -Wait`——两流分开落盘后 `findstr`。
2. **次选**：`cmd /c "\"...godot.exe\" --headless ... > file 2>&1"`——可用，但内嵌引号在 PowerShell 里易碎（曾报 filename syntax incorrect），同样 `cmd /c` 后接 `;` 会碎。
3. **禁用 `*>`**：对 Godot exe 会吞输出（空文件 + exit 0 假象）。
4. `findstr` 别拿全文锚点（如 `REGRESSION`）当过滤条件——每行都命中等于全文输出。

## 本机路径与启动方式

- **打开编辑器必须带 `-e`**：`godot --path <工程>` 不带 `-e` = 运行项目模式（找主场景跑）。正确写法 = `Start-Process -FilePath <编辑器> -ArgumentList "-e","--path","<工程绝对路径>"`。替用户启动 GUI 程序前先确认参数语义。
- **机器相关绝对路径不进远端仓库**（编辑器安装位置、skills 安装目录等）：见 `.codebuddy/memory/local-env.md`。
- 本地校验：`godot --headless --path game --script res://tools/validation/check_project.gd`（新增 `.gd` 前必须先 `--import`，见 `godot-standards.md`）。

## 本机 PATH 里没有 sh（跑仓库自带 shell 脚本时）

- `cmd /c "sh tools/check-doc-links.sh > f 2>&1"` **会失败**（`'sh' is not recognized`，exit 1）。仓库文档里写的 `sh tools/check-doc-links.sh` 在 CI（Linux）直接可用，**在本机 cmd 里不可用**。
- 本机两种可用写法：
  - `"C:\Program Files\Git\bin\sh.exe" tools/check-doc-links.sh`（cwd 需在仓库根）
  - `& "C:\Program Files\Git\bin\bash.exe" -c "cd /d/My_Projects/Move_Idle && sh tools/check-doc-links.sh"`
- **pre-commit 钩子不受影响**——它由 Git 自带的 sh 执行，与 PATH 无关。
- 判定脚本是否真跑过，看输出里有没有 `doc-links OK`；不要只看退出码。

## git / gh

- GraphQL 内嵌双引号会被 PowerShell 5.1 吞（语法错）；`--jq` 表达式引号易碎，改用管道 `ConvertFrom-Json`；`gh api` 用显式完整仓库路径。
- **并发会话共享同一个 git 索引**（非 Windows 专属，属同一类命令纪律）：`git add <具体路径>` 之后、`commit` 之前，另一会话往索引里加的东西会被**一起提交**（实测发生：一笔只该含 1 个文档的提交，把别人的 1 行标准页修正也带进去了）。提交前先 `git diff --cached --stat` 核对清单；`git add` 与 `git commit` 尽量紧邻执行。
- `cmd /c` 里用 `&` 串联多条命令时，**前一条带重定向的输出会被吞**（实测：`git config --get core.hooksPath > f 2>&1 & git ls-files ... >> f` 只留下后者输出，前者被误读成「键未配置」而误判钩子未装机）。配置 / 状态类查询**单独一条命令跑**，结论才可信。
