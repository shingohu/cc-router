# CCRouter 项目长期记忆

## 架构与现状（2026-09-18 核查）
- CCRouter 是 Flutter 组件化框架，文档 `docs/CCRouter-v0.1-architecture.md` / `docs/CCRouter-route-design.md`。
- 设计核心：静态 `CCRouter` 门面 + 纯 Dart `ccrouter_core` Runtime + 四通道语义（Route/Command/Query/Action/Event）+ Service + Scope 生命周期 + 两层拦截器 + 多后端导航 Adapter（GoRouter）。
- **关键事实**：当前仓库只有 `ccrouter_contracts / ccrouter_core / ccrouter / ccrouter_go_router` 四个包。**没有 `ccrouter_annotations`、`ccrouter_generator`、`ccrouter_test` 包**——注册靠手写 `CCComponentRegistrar.register()`，注解驱动代码生成尚未开始（文档 Phase C）。InitTask DAG（文档 §13）也未实现。
- 对比业界：在契约语义/类型安全/Scope/无反射/多后端/安全 Origin 上领先 TheRouter/ARouter；在注解+代码生成+编译期校验+文档+初始化编排+测试替身+生态工具上落后。

## 用户偏好（本项目）
- 要求 AI 先核对业界成熟做法（ARouter/TheRouter/跨进程方案）再回答，避免凭空说教；理解偏题时主动纠正重新对齐。
- 倾向简单、非侵入、可叠加实现；重视编译期契约校验而非运行时反射。
