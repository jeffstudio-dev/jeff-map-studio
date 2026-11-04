# 验证

要求 Godot 4.7.2 和 Python 3，不需要额外 Python 包。

```sh
python3 tools/run_tests.py --godot /absolute/path/to/godot --clean-install
```

所有默认入口均使用 `--headless` 在后台运行，包括单独执行 `tools/test_clean_install.py`，不会打开测试窗口或切换焦点。当前项目约定见根目录 `AGENTS.md`。

截图与接缝像素检查需要真实图形上下文，在 headless 下明确跳过。`--performance` 可以后台测量生成／铺图，但该结果不代表真实图形渲染性能。`--visual` 仅保留给用户明确要求的有窗口视觉验收，不作为日常测试选项。报告、日志和截图写入 `test_output/`，不会进入发布包。

- **core**：方形／六角坐标与原生 TileMap 一致，72 个生成器／网格／种子组合，确定性、连通、装饰随机流隔离、锁定保留、存取、错误参数、取消、纹理重复边界。
- **assets**：PNG 图集切分、缺失绑定、精确／通用规则、规则顺序不影响随机变体、原生 Terrain 读取、外部图集渲染、失败事务和素材资源回读。
- **integration**：真实工作区、完整网格／投影矩阵、升高地块选格、撤销重做、风格切换、取消、原生场景烘焙、运行时与纯数据生成一致、实际截图。
- **runtime_demo**：运行实际演示场景，验证启动生成、键盘切换视角／风格／网格和保存。
- **seams**：在真实图形环境中渲染不透明纯色平面，检查方形／六角、两种朝向、俯视／等角、两种过滤风格及三档缩放下的内部接缝。无图形环境时明确跳过。
- **blocks**：高度 0 地块的底座、侧面选格、邻接遮挡和擦除更新、厚度切换不改变地图数据、保存回读、独立地块确定性和透明度、侧面缓存更新、工作区预览及导出。
- **landmarks**：两套独立美术与透明度，六种装饰在三种形状的高度层显示，风格切换、保存回读、画笔放置、锁定保留、海岸灯塔分布和密度随机流隔离。
- **art_specs**：外观规范与概念图数据自检；草地颜色只来自色阶和点缀色；绘制确定性；16 个草地变体两两相邻无接缝；按区域选情绪且相邻格多为同一情绪；格内子变体只用于四周同类的格子。
- **performance**：512×512 方形与六角等角地图，记录实际耗时、每帧间隔、Godot 静态分配内存峰值、铺图期间取消。静态分配内存不等同于进程全部内存或显存。
- **clean-install**：仅复制插件到临时空项目，重新导入；验证 @tool 生成、应用到场景、EditorUndoRedo、保存和重载；最后在单独的游戏进程中运行保存的场景。临时测试插件不会进入插件发布包。

测试执行器会把 Godot 的 ERROR / SCRIPT ERROR 视为失败，即使进程退出码为 0。

后台编辑器测试使用 [`EditorInterface.save_scene_as(path, false)`](https://docs.godotengine.org/en/4.5/classes/class_editorinterface.html#class-editorinterface-method-save-scene-as) 保存场景并关闭缩略图生成，避免 dummy 渲染器读取不存在的缩略图纹理；随后照常回读和运行保存的场景。

重新生成原始示例资源：

```sh
godot --headless --path . --script tools/build_examples.gd
```

只重新导出四套材质的三种地块 PNG（无窗口，不生成安装包）：

```sh
godot --headless --path . --script tools/build_examples.gd -- --blocks-only
```

无窗口导出方形、尖顶六角和平顶六角的小地图拼接预览：

```sh
godot --headless --path . --script tools/render_map_samples.gd
```

输出在 `test_output/assembled_maps/`：整体图、透明图、岸边近景、可在 Map Studio 打开的 `.tres` 地图及 `report.json`。使用实际 `MapRenderer` 的 TileMapLayer 选块、图集区域、原点及排序锚点，以 CPU 最近邻拼接导出。覆盖草地、沙地、水域和 0–4 层高度，检查内部侧面隐藏、同高边缘像素覆盖和资源回读。此导出不是 GPU 截图，不验证图形后端的分数缩放／过滤接缝，不生成安装包。

打包（仅在用户完成本地测试并明确要求后执行）：

```sh
python3 tools/package.py
```

双风格带标志物小地图与单块后台预览：

```sh
godot --headless --path . --script tools/render_style_samples.gd
```

输出到 `test_output/style_landmarks/`；可编辑地图和透明地块同时保存到 `addons/jeff_map_studio/examples/styles/`。原始标志物图集重建命令为 `godot --headless --path . --script tools/import_landmarks.gd`。以上均不执行发布打包。

双风格地表／断面材质资源重建：`godot --headless --path . --script tools/import_surfaces.gd`。导入后再运行示例资源与预览导出脚本。2026-10-21 重绘版后台回归 902 项通过，预览导出另有 485 项；真实图形接缝检查仍跳过。
