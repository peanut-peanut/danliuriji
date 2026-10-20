# 小王日记

一个 iOS 18+ 的私密生活记录与宠物成长相册首版，采用 SwiftUI 构建。

## 已实现
- 日常、运动、阅读、投资、饮食五类日记的筛选与搜索
- 新建、编辑、收藏、删除与 `UserDefaults` 本地持久化
- 蛋黄与六六的档案、生日、年龄和关联记录
- Face ID 开关与系统授权流程（真实设备验证）
- iPhone 12 起的自适应原生界面；最小系统版本 iOS 18

## 真机运行
1. 使用 Xcode 打开 `/Users/wangchenxu/xiaowangriji/小王日记.xcodeproj`。
2. 选择“小王日记”Target，在 **Signing & Capabilities** 中选择你的开发团队。
3. 将 Bundle Identifier 改为你账户下唯一的标识符，例如 `com.<你的名字>.xiaowangriji`。
4. 连接 iPhone，选择目标设备后运行。

当前媒体方格与头像为系统图标占位；收到 App 图标和宠物照片后替换资源即可。账号注册、云同步、相册视频导入将在服务端与安全策略确认后接入，当前版本不会保存明文账号密码。

## 保存后自动刷新模拟器

在项目根目录执行：

```bash
./scripts/watch-simulator.sh
```

脚本会启动 `iPhone 18 Pro` 模拟器，并在每次保存 `小王日记` 目录中的 Swift 或资源文件后，自动重新构建、安装并重启 App。按 `Ctrl-C` 停止监听。此方式会保留 App 的本地数据，但会重启正在展示的页面。

对于单个 SwiftUI 视图的即时调样式，可在 Xcode 打开 Canvas 并使用 Preview；它不会替代完整 App 的功能验证。

## 后端 API（无登录单用户模式）

后端在 [`/Users/wangchenxu/xiaowangriji/server`](/Users/wangchenxu/xiaowangriji/server)；当前不接登录，适用于本地开发或部署到你私有、受访问控制的服务器。

```bash
cd /Users/wangchenxu/xiaowangriji/server
pnpm start
```

默认地址为 `http://localhost:3000/api`：

- `GET /health`：健康检查
- `GET /openapi.json`：OpenAPI 契约
- `GET /pets`：蛋黄、六六的档案
- `GET|POST /diary-entries`、`GET|PATCH|DELETE /diary-entries/:id`：日记
- `POST /media`：原始图片/视频上传，传入 `Content-Type` 及 `X-Filename`
- `GET|POST /pet-assets`、`DELETE /pet-assets/:id`：宠物资源墙（支持 `petId`、`kind=image|video` 筛选）

开发期的数据保存在 `server/data/db.json`，上传的媒体保存在 `server/data/media/`，均被 Git 忽略。生产环境建议将 JSON Store 替换为 PostgreSQL / MySQL，并将媒体存储替换为 OSS；在服务暴露到公网前，必须配置网络访问控制或加入设备令牌认证。

运行 API 测试：

```bash
cd /Users/wangchenxu/xiaowangriji/server
pnpm test
```

## iOS API 环境路由

原生 iOS 没有浏览器开发服务器，因此不使用 Web Proxy。App 从 `Info.plist` 的 `APIBaseURL` 读取后端地址：

- **Debug**：`http://127.0.0.1:3000/api`，仅供 iOS 模拟器与本机 API 联调；Debug 才允许 HTTP。
- **Release / Archive**：使用 `$(PRODUCTION_API_BASE_URL)`；没有传入生产 HTTPS 地址时不会默默打包本机地址。

构建生产包时必须明确注入真实 API 域名，例如：

```bash
xcodebuild archive \
  -project /Users/wangchenxu/xiaowangriji/小王日记.xcodeproj \
  -scheme 小王日记 \
  -configuration Release \
  -archivePath /tmp/小王日记.xcarchive \
  PRODUCTION_API_BASE_URL=https://diary-api.peanutwcx.xyz/api
```

当前生产 API 已部署为 `https://diary-api.peanutwcx.xyz/api`。如未来迁移服务器，可在 Archive 命令中覆盖该值。不要把 `127.0.0.1` 用于真机或 Release 包：真机中的 `127.0.0.1` 指向手机自身，并不是开发电脑。

## 媒体存储（OSS）

生产 API 的图片和视频上传到 Alibaba Cloud OSS；数据库只保存 `filePath`，格式如下：

```text
xiaowang-diary/media/YYYY/MM/DD/<uuid>.<extension>
```

接口响应会根据该路径生成 HTTPS 访问 URL。Bucket 未配置自定义公开域名时，返回的是有效期 1 小时的 OSS 签名 URL；数据持久化不依赖这个临时 URL。删除宠物资源时，API 会同步删除其关联的 OSS 对象。

