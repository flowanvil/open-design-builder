# open-design-builder

每日自动为上游 [nexu-io/open-design](https://github.com/nexu-io/open-design) 构建 Linux x64 AppImage，并发布到本仓库的 Releases。

上游 Releases 目前只提供 macOS / Windows 安装包，本仓库补齐 Linux 版本。

## 工作流程

流水线定义在 [`.github/workflows/build-linux.yml`](.github/workflows/build-linux.yml)：

1. **定时触发**：每天 03:17 UTC；也可在 Actions 页面用 `workflow_dispatch` 手动运行。
2. **解析 tag**：通过 GitHub REST API 拉取上游 `GET /repos/nexu-io/open-design/tags`，以及本仓库 `GET /repos/forkdo/open-design-builder/releases`（含 assets）。
3. **判定「已完成」**：只有**同时带 AppImage 与 `.sha256` 两个资产**的 Release 才算构建完成。`gh release create` 会先写 `vX.Y.Z` tag 再上传资产，所以只有 tag、资产不全的半截发布不能算数，否则游标会跳过它、永远不再重试。
4. **求差集**：以最早的已完成版本为**下界（floor）**，收集所有不低于 floor、且没有完整 Release 的上游 tag（按版本升序）。既能一次补齐同日发布的多个 tag，也能补上中间失败留下的空洞，且不会回溯 floor 之前的古老版本。
5. **过滤**：跳过没有已发布上游 Release 的 tag（发布描述需要它）。
6. **构建**：对每个待构建版本**依次**启动独立 job（`max-parallel: 1`，升序）；`fail-fast: true` 保证任一版本失败就停下后续 job，避免后面的版本先发布、把游标推过这个空洞。
7. **发布 + 校验**：上传 AppImage 与 `.sha256` 校验文件，随后再次调用 API 确认两个资产都确实存在，否则让该 job 失败。Release 描述首行是上游 Release 地址，其后是通过 API 获取的上游 Release 正文。

## 补打逻辑

同一天上游发布多个 tag 时不会出现漏打 — 所有比游标新的版本都会进入构建矩阵。

例如本仓库已打 `v0.1.0`，上游有 `v0.0.9 / v0.1.0 / v0.1.1 / v0.1.2`：

| 上游版本 | 是否构建 | 原因 |
|---|---|---|
| `v0.0.9` | 否 | 早于游标，不回溯历史 |
| `v0.1.0` | 否 | 与游标相同，已构建 |
| `v0.1.1` | 是 | 新于游标 |
| `v0.1.2` | 是 | 新于游标 |

首次运行（本仓库还没有任何完整 Release）只构建上游最新版本，避免把几十个历史版本全部重放。如需补某个旧版本，用手动触发的 `tag` + `force`。

两个额外保障：

- **空洞**：若 `v0.1.0`、`v0.1.2` 已完成而 `v0.1.1` 缺失，差集会单独补出 `v0.1.1`，不会被「最大值游标」跳过。
- **半截发布**：若某次上传失败只留下了 `v0.1.1` 的 tag（资产缺失），该版本不计入已完成，下一次运行会自动重试它以及之后的 `v0.1.2`。

每次运行都会在 Actions 的 Step Summary 里打印游标（最新完整版本）、floor（最早完整版本）、完整 Release 数量，以及本次要构建的版本列表。

## 命名约定

| 项目 | 格式 | 示例 |
|---|---|---|
| 上游 tag（用于 checkout / 查询） | `open-design-vX.Y.Z` | `open-design-v0.27.0` |
| 本仓库 Release tag 与标题 | `vX.Y.Z` | `v0.27.0` |
| AppImage | `open-design-X.Y.Z-linux-x64.AppImage` | `open-design-0.27.0-linux-x64.AppImage` |
| 校验文件 | `open-design-X.Y.Z-linux-x64.AppImage.sha256` | `open-design-0.27.0-linux-x64.AppImage.sha256` |

上游 tag 形如 `open-design-v0.27.0`，仅用于 checkout 与查询上游 Release；本仓库的 tag 使用 `v0.27.0`。

## 手动触发参数

| 输入 | 说明 | 默认 |
|---|---|---|
| `tag` | 只构建单个版本，如 `v0.27.0`；留空则补打所有新版本 | 空 |
| `force` | 配合 `tag` 使用：即使该版本已有完整 Release 也强制重建并覆盖资产 | `false` |
| `containerized` | 在 `electronuserland/builder:base` Docker 内构建，兼容更旧的 glibc | `false` |

## 运行 AppImage（FUSE / sidecar）

AppImage 直接执行依赖两段机制，缺一段都会失败：

| 现象 | 原因 |
|---|---|
| `dlopen(): error loading libfuse.so.2` / `AppImages require FUSE to run` | 系统缺 `libfuse.so.2`，AppImage runtime 无法挂载 SquashFS |
| `SidecarBootstrapGenerationRetiredError: sidecar bootstrap generation ... exited before a generation became ready`（日志里路径是 `/tmp/.mount_...`） | **已挂载但走的是 FUSE 模式**：每次启动页缓存都是冷的，内置 Node 负载通过 FUSE 按需换页，daemon sidecar 稳定错过启动预算（`apps/packaged/src/sidecars.ts` 把 Linux 预算放宽到 90s 仍可能不够） |

两者都**不是构建产物损坏**。上游 `tools-pack linux start` 固定用 `--appimage-extract-and-run`，实测启动从 >35s 降到 <5s。

**本仓库的构建已在 `AppRun` 里加了自动兜底**：直接 `./xxx.AppImage` 时，若检测到自己运行在 FUSE 挂载点 `/tmp/.mount_*` 下，会用 `OD_APPIMAGE_FALLBACK` 标记并自动以 `--appimage-extract-and-run` 重新执行外层 AppImage。所以只要系统能完成首次挂载（有 `libfuse2`），直接双击/命令行运行就会自动切到真实文件系统，sidecar 正常启动。解压后的那一次执行因为 `APPDIR` 不再是 `/tmp/.mount_*`，不会递归。CI 里会断言生成的 `AppRun` 带有这段兜底，防止上游模板变动后静默失效。

**完全没有 libfuse2 时**（连首次挂载都失败），runtime 在 `AppRun` 之前就退出，兜底来不及生效，仍需手动指定：

```bash
./open-design-0.27.0-linux-x64.AppImage --appimage-extract-and-run
# 或
APPIMAGE_EXTRACT_AND_RUN=1 ./open-design-0.27.0-linux-x64.AppImage
```

也可以装好 FUSE 后直接运行：

| 系统 | 命令 |
|---|---|
| Ubuntu 24.04+ / Debian 13+ | `sudo apt install libfuse2t64` |
| Ubuntu 22.04 及更早 / Debian 12 | `sudo apt install libfuse2` |
| 其他发行版 | 安装对应的 `fuse2` / `libfuse2` 包（多数现代桌面发行版默认已带） |

> 校验文件：`sha256sum -c open-design-0.27.0-linux-x64.AppImage.sha256`。若下载工具给文件名加了后缀（例如 `..._8b2847e0b98bc5640c7ca2ffbe12153e.AppImage`），先改回上表中的标准文件名再校验，或直接 `sha256sum <文件>` 与 `.sha256` 内容比对。

## 说明

- Workflow 使用仓库自带的 `GITHUB_TOKEN`，需要 `contents: write` 权限（已在 workflow 中声明）。
- 默认在 runner 上原生构建；需要更广的 glibc 兼容性时可勾选 `containerized`（依赖 Docker）。
- AppImage 未签名，未接入自动更新 feed。本仓库是社区构建，非上游官方发布产物。

最新产物见 [Releases](https://github.com/forkdo/open-design-builder/releases)。
