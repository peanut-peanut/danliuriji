export const openApi = {
  openapi: '3.1.0',
  info: { title: '小王日记 API', version: '0.1.0', description: '单用户、无登录的私有日记与宠物资源 API。生产部署前应在反向代理或下一版本加入访问控制。' },
  servers: [{ url: '/api' }],
  paths: {
    '/health': { get: { summary: '健康检查', responses: { 200: { description: '服务可用' } } } },
    '/pets': { get: { summary: '宠物档案', responses: { 200: { description: '蛋黄与六六' } } } },
    '/ai/polish': { post: { summary: '使用 DeepSeek 润色日记正文', description: '仅发送用户主动选择润色的正文；服务端需配置 DEEPSEEK_API_KEY。', responses: { 200: { description: '润色后的 body' }, 503: { description: 'AI 未配置' } } } },
    '/diary-entries': { get: { summary: '日记列表', parameters: [{ name: 'category', in: 'query' }], responses: { 200: { description: '日记数组' } } }, post: { summary: '创建日记', responses: { 201: { description: '已创建' } } } },
    '/diary-entries/{id}': { get: { summary: '日记详情', responses: { 200: { description: '日记' } } }, patch: { summary: '修改日记', responses: { 200: { description: '已更新' } } }, delete: { summary: '删除日记', responses: { 204: { description: '已删除' } } } },
    '/media': { post: { summary: '上传一个图片或视频', description: '请求体为原始文件；使用 Content-Type 和 X-Filename 请求头。', responses: { 201: { description: '媒体对象，可用于创建日记或宠物资源' } } } },
    '/media/{filename}': { get: { summary: '访问已上传媒体', responses: { 200: { description: '媒体文件' } } } },
    '/pet-assets': { get: { summary: '宠物资源列表', parameters: [{ name: 'petId', in: 'query' }, { name: 'kind', in: 'query', description: 'image 或 video' }], responses: { 200: { description: '资源数组' } } }, post: { summary: '创建宠物资源', responses: { 201: { description: '已创建' } } } },
    '/pet-assets/{id}': { delete: { summary: '删除宠物资源及其媒体', responses: { 204: { description: '已删除' } } } }
  }
};
