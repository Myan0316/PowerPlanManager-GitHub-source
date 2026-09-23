# 上传 GitHub 与发布程序

## 适合提交的内容

提交根目录的 README、`.gitignore`、`.gitattributes`、`.editorconfig`，以及 `src/`、`scripts/`、`tests/`、`docs/`。这些文件足以阅读、运行、测试和构建项目。

`dist/`、`artifacts/`、`.local/` 已被忽略。EXE 和源码 ZIP 使用 GitHub Releases 附件分发；本机 `.pow` 备份、原始测试日志、迁移清单及个人绝对路径记录保留在本地。

## 当前仓库已有的历史

工程整理前的首次提交已经包含 EXE、重复解包文件、原始日志及本机路径。`.gitignore` 只能影响之后的文件选择，不能清除既有提交历史。本次整理保留了原 `.git`，没有改写或删除历史。

如果首次上传希望只包含整理后的工程，使用 `scripts/export-source.ps1` 生成的 `dist/PowerPlanManager-GitHub-source.zip`：

1. 解压到一个新目录，不复制原工程的 `.git`、`.local`、`dist` 或 `artifacts`。
2. 在新目录用 GitHub Desktop 创建本地仓库，检查待提交文件，再提交并发布到你的 GitHub 仓库。
3. 源码包内的 `SOURCE_MANIFEST.sha256` 用于核对导出文件，可随首次提交保留。

也可在新目录使用 Git：

```powershell
git init -b main
git add .
git status --short
git commit -m "Prepare Power Plan Manager source project"
```

仓库地址、公开/私有设置由发布时决定。若继续使用原仓库，先提交这次目录整理；正常推送仍会包含原始历史。不要以为新增忽略规则已经让历史文件消失。

## 发布 EXE

在 Windows PowerShell 5.1 下运行 `scripts/build.ps1`，完成验证后，为相应版本创建 GitHub Release。附件选择 `dist/` 中带版本的 EXE、对应 SHA-256，以及需要时重新生成的源码 ZIP。不要上传本地归档或测试备份。

更新版本时同步程序标题、启动器、构建和校验脚本中的版本，以及使用说明和报告。当前为 0.2.0，不能直接改文件名冒充新版本。

## 许可证

目前没有替作者选定许可证。决定允许他人怎样使用、修改和分发后，再加入对应 `LICENSE`；在此之前不要声称项目采用 MIT、Apache 或其他开源许可证。
