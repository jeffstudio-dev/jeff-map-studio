# 参考项目与来源

调研日期：2026-10-17。以下仓库用于理解设计与比较方案。本插件没有嵌入这些项目的源码、字体或美术，也不要求安装它们。仓库许可是调研时的记录，未来引入代码时需重新核对具体文件及版本。

| 仓库 | 调研许可 | 参考主题 |
|---|---|---|
| [gaea-godot/gaea](https://github.com/gaea-godot/gaea) | MIT | 模块化生成流程；2.0 文档标注早期开发 |
| [Portponky/better-terrain](https://github.com/Portponky/better-terrain) | Unlicense | 多种地形邻接、编辑器画笔、运行时批量更新 |
| [pablogila/TileMapDual](https://github.com/pablogila/TileMapDual) | MIT | 双网格过渡与方形／等角／六角；文档注明替代瓦片限制 |
| [Zehir/godot-hexagon-tile-map-layer](https://github.com/Zehir/godot-hexagon-tile-map-layer) | MIT | 六角坐标与 Godot 布局转换 |
| [ForlornU/HexagonalMapGodot](https://github.com/ForlornU/HexagonalMapGodot) | MIT | 六角自然地图生成示例 |
| [csbrandt/isometric-terrain](https://github.com/csbrandt/isometric-terrain) | MPL-2.0 | 等角高度、自然地形及生成／渲染分离 |
| [statico/godot-roguelike-example](https://github.com/statico/godot-roguelike-example) | 代码 MIT；美术另有许可 | 地牢生成、预览与素材映射 |

引擎行为参考 [TileSet](https://docs.godotengine.org/en/stable/classes/class_tileset.html)、[TileMapLayer](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html)、[Noise](https://docs.godotengine.org/en/stable/classes/class_noise.html) 官方文档，并以本机 Godot 4.7.2 实测验证。

## 本插件素材

- `icon.svg`：为本插件编写的原始 SVG。
- 程序纹理代码与原始示例采用本插件 MIT 许可。当前草地、沙地、水域另提供绘制纹理模式，`examples/textures`、顶面／侧面图集会包含这些绘制素材。
- `assets/surfaces`：内置 imagegen 生成的像素／手绘材质图集，包含三种地表和对应断面。具体提示词与来源和标志物一并记录于 `assets/landmarks/generation.json`。
- `assets/landmarks`：内置 imagegen 生成的像素与手绘标志物，原始透明图集与提示词记录均保存在项目中；见 [generation.json](../assets/landmarks/generation.json)。装饰图集和带物品示例使用这些图像。未从第三方仓库或用户参考图裁切美术。
- 自然／地牢配方与色板：本工程原始资源。
- 界面字体：使用操作系统字体回退列表，不随插件分发字体文件。

用户导入的图片与 TileSet 保留各自来源和许可；素材库的 `attribution` 字段可记录来源。
