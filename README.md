# open-design-builder

每日自动为上游 [nexu-io/open-design](https://github.com/nexu-io/open-design) 构建 Linux x64 AppImage，并发布到本仓库的 Releases。

上游 Releases 目前只提供 macOS / Windows 安装包，本仓库补齐 Linux 版本。

## 工作流程

流水线定义在 [`.github/workflows/build-linux.yml`](.github/workflows/build-linux.yml)：

1. **定时触发**：每天 03:17 UTC；也可在 Actions 页面用 `workflow_dispatch` 手动运行。
2. **解析 tag**：通过 GitHub REST API `GET /repos/nexu-io/open-design/tags` 拉取上游 tag，筛选 `open-design-vX.Y.Z` 并取最新版本。
3. **幂等检查**：若本仓库已存在对应 `vX.Y.Z` 的 Release 则跳过，除非手动触发时勾选 `force`。
4. **构建**：checkout 上游对应 tag → `pnpm install --frozen-lockfile` → `pnpm exec tools-pack linux build --portable --app-version <version> --to appimage`。
5. **发布**：上传 AppImage 与 `.sha256` 校验文件；Release 描述首行是上游 Release 地址，其后是通过 API 获取的上游 Release 正文。

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
| `tag` | 指定版本，如 `v0.27.0`；留空则取上游最新 tag | 空 |
| `force` | 已有 Release 时仍重建并覆盖资产 | `false` |
| `containerized` | 在 `electronuserland/builder:base` Docker 内构建，兼容更旧的 glibc | `false` |

## 说明

- Workflow 使用仓库自带的 `GITHUB_TOKEN`，需要 `contents: write` 权限（已在 workflow 中声明）。
- 默认在 runner 上原生构建；需要更广的 glibc 兼容性时可勾选 `containerized`（依赖 Docker）。
- AppImage 未签名，未接入自动更新 feed。本仓库是社区构建，非上游官方发布产物。

最新产物见 [Releases](https://github.com/forkdo/open-design-builder/releases)。
