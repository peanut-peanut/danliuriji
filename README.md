# 蛋六日记

一本给自己写的日记，也是蛋黄和六六的非官方传记。

SwiftUI · iOS 18+ · Node.js

## 里面有什么

- **记录**：文字、照片、视频，支持分类、搜索和收藏。
- **宠物**：蛋黄和六六的档案与专属相册。
- **展览**：按月整理照片，日子翻过去，照片留下来。
- **写作辅助**：DeepSeek 润色正文；在本机识别图片文字、拍摄时间和坐标，按需开启。

## 跑起来

需要 Xcode、Node.js 20+ 和 pnpm。

启动后端：

```bash
cd server
pnpm install
cp .env.example .env  # 首次配置；已有 .env 时跳过
pnpm dev
```

用 Xcode 打开 `蛋六日记.xcodeproj`，选择“蛋六日记”Scheme 和 iOS 模拟器运行。真机运行前，选择自己的签名团队，并把 `APIBaseURL` 改为手机可访问的后端地址。

Debug 默认连接 `http://127.0.0.1:3000/api`。真机上的 `127.0.0.1` 是手机自己。

在项目根目录运行以下脚本，可监听保存并自动重建、安装到 `iPhone 18 Pro` 模拟器：

```bash
./scripts/watch-simulator.sh
```

## 配置与数据

- **AI 润色**：在 `server/.env` 填入 `DEEPSEEK_API_KEY`。密钥只留在服务端，点击润色时才发送正文。
- **媒体**：本地开发保存到 `server/data/media/`；生产使用 OSS，配置项见 `server/.env.example`。
- **日记数据**：保存在 `server/data/db.json`。数据与 `.env` 不入库，备份请另行安排。
- **访问控制**：当前没有登录，部署到公网前需在网关限制访问。

接口说明：启动后访问 `/api/openapi.json`。运行后端测试：

```bash
pnpm --dir server test
```

## 发布到生产环境

在项目根目录执行以下任一命令即可发布服务端：

```bash
pnpm run deploy
# 或
npm run deploy
```

命令会显示发布目标并要求确认，随后备份服务器上的环境变量和日记数据，构建新镜像、切换 API，并检查 HTTPS 健康接口。用于 CI 或已确认的非交互发布时：

```bash
pnpm run deploy:yes
```

生产密钥和日记数据只保存在服务器，不会从本机上传。首次执行会从旧的 `xiaowang-diary-api` 服务迁移它们。

## 打包

```bash
xcodebuild archive \
  -project 蛋六日记.xcodeproj \
  -scheme 蛋六日记 \
  -configuration Release \
  -archivePath /tmp/蛋六日记.xcarchive \
  PRODUCTION_API_BASE_URL=https://diary-api.peanutwcx.xyz/api
```

Bundle ID 为 `com.danliu.diary`。从旧版安装到新版会被视为新 App，本机草稿与偏好不会自动迁移；服务端记录和历史媒体仍可读取。
