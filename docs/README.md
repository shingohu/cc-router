# 设计文档

这里集中存放 CCRouter 的架构和路由设计文档。文档用于说明目标模型、API 边界和实现约束；具体实现状态以仓库代码和测试为准。

- [v0.1 架构设计](CCRouter-v0.1-architecture.md)
- [路由子系统设计](CCRouter-route-design.md)
- [路由契约文件设计](CCRouter-route-contract-design.md)
- [混合路由改造设计](CCRouter-hybrid-routing-design.md)
- [注解路由生成器对比与借鉴记录](CCRouter-annotation-generator-comparison.md)
- [最终 API 收口复审清单](CCRouter-final-api-review.md)
- [核心价值与开发约定回归](CCRouter-core-principles-audit.md)

生成器输出的应用路由目录不属于手写设计文档。当前 Demo 的聚合路由目录位于
`demo/ccrouter_generated/cc_routes.json` 和
`demo/ccrouter_generated/cc_catalog.md`。
