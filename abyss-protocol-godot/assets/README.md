# 素材来源

以下贴图来自本仓库原有的深渊协议美术目录 `output/imagegen/abyss-protocol-runtime/`，已复制为独立资源：

- `player.webp`：四列、两行的八方向角色图集，顺序为东、东南、南、西南、西、西北、北、东北。
- `brute.webp`：近战敌人。
- `drone.webp`：远程无人机。
- `warden.webp`：第六舱封锁卫士。
- `core.webp`：深渊主控体。
- `station.webp`：空间站地板纹理。

`icon.svg` 是本项目生成的矢量图标，`crosshair.svg` 是原创战斗准星。运行和导入本项目不需要访问原美术目录或 HTML。

## 中文字体

`fonts/NotoSansCJKsc-Regular.otf` 为开源思源黑体系列的 Noto Sans CJK 简体中文常规字体，来自 [Noto CJK 官方仓库](https://github.com/notofonts/noto-cjk)。原始授权文件位于 `fonts/OFL.txt`，使用 SIL Open Font License 1.1。字体完整随项目提供，运行时无需下载，也不依赖本机已安装的中文字体。

Godot 生成的 `.import` 元数据与资源一起保留；`.godot/` 导入缓存不进入版本控制。

## 声音

`audio/station_ambience.wav` 是本项目制作的十二秒无缝空间站环境合成声，没有采样第三方录音。战斗短音离线生成，由 `scripts/sound.gd` 预加载并使用固定声音池播放，具体来源见下文。

## 关节与武器图集

`rig/` 的八张 `rig*.webp` 为原作已有的八方向独立部位图集，来自相同本地美术目录。裁切、肩肘膝踝和手掌标定保存在 `scripts/rig_data.gd`；GDScript 原生骨骼投影实现位于 `scripts/android_rig.gd`，运行不调用旧 HTML。

`weapons/guns.webp`（三行枪械）和 `weapons/bows.webp`（三列弓）复制自原作已有的 `weapons/` 与 `bows/` 素材目录。握把、护木、枪口及弓弦锚点保存在 `scripts/weapon_art.gd`。环境声与图集全部随发行资源打包。


## 工业场景与展示字体

`cover_props.webp` 来自原作本地同名设备图集。`scripts/station_portrait.gd` 是本项目原创的矢量轨道站插画；`scripts/arena.gd` 的检修道、板材与舱壁也由原生绘制完成。

`fonts/NotoSerifCJKsc-SemiBold.otf` 来自 Noto CJK 官方仓库的 `Serif/OTF/SimplifiedChinese/`，SIL OFL 1.1 授权，完整字体未做修改，与 `fonts/OFL.txt` 一同分发。

九个短音 `gun/heavy/blade/bow/arc/impact/dash/ui/clear.wav` 是 `tools/make_audio.py` 生成的原创确定性 PCM 音频，没有第三方采样。可重新生成，运行时直接加载本地资源。
