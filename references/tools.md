# 高清排版与拆图工具

`scripts/poster.swift` 使用 macOS 的 CoreText、AppKit 和 Vision。需要已安装可用的 Swift 工具链，无额外第三方包。它负责真实字体排字、图片合成、像素裁切与本地验收。背景生成与人物背景融合按当前图片工具规则执行。

## render

快速起稿时，将 `assets/layout-template.json` 复制到本次制作目录，填写所有 `{{字段}}`。模板中的五个内容模块、三个收获模块参考第三期，可按当期内容调整。将图片路径指向实际的 `background.png`、`portrait.png`、`logo.png`、`qr.png`。background 为文字留空的暗绿背景，portrait 为本期人物图片，logo 使用随 Skill 保存的原图，qr 使用本期报名原图。缺少图层素材时先补齐或按实际需要移除该图层。提交成品前检查所有占位字段已替换。

```sh
swift ~/.codex/skills/ai-action-pi-poster/scripts/poster.swift render design.json
```

路径相对于 JSON 文件。坐标以逻辑画布左上角为原点，格式为 `[x,y,width,height]`。所有文字独立保存在 JSON，改字后可以直接重出图。`output` 默认拒绝覆盖已有文件，用户要求更新同一文件时才设置 `overwrite: true`。

```json
{
  "canvas": {"width": 809, "height": 2037, "color": "#101210"},
  "outputWidth": 2160,
  "output": "海报_高清2160.png",
  "layers": [
    {"type": "image", "path": "background.png", "rect": [0,0,809,2037], "fit": "cover"},
    {"type": "image", "path": "logo.png", "rect": [40,24,90,90], "fit": "contain"},
    {"type": "text", "text": "AI行动π", "rect": [140,40,220,60], "font": "PingFangSC-Semibold", "size": 38, "color": "#F1F2EC"},
    {"type": "text", "text": "本期主题", "rect": [50,160,410,140], "font": "PingFangSC-Semibold", "size": 82, "color": "#BDFE32"},
    {"type": "image", "path": "qr.png", "rect": [550,1590,194,194], "fit": "contain", "interpolation": "nearest"}
  ]
}
```

上例展示格式，未包含完整活动资料。根据实际内容建立正式 design.json。

- 文本层支持 `alignment` 为 `left`、`center` 或 `right`，支持 `lineSpacing`。文字按实际字体排版并自动换行，框不足时中止导出并列出该段文字。
- 图片层支持 `fit` 为 `contain` 或 `cover`，默认 contain。可设置 `crop: [x,y,width,height]`，crop 使用源图片真实像素，destination 使用逻辑坐标。
- `rect` 层可设置 `fill`、`stroke`、`strokeWidth` 与 `radius`，用于简单信息卡片或竖线。
- `font` 省略时使用 `PingFangSC-Regular`。指定字体缺失时报告错误，由助手选择可用字体并检查版式。
- `outputWidth` 省略时为 2160，输出高度按逻辑画布等比例计算。
- 图片层 `alpha` 可在 0 到 1 之间设置。

## split

```sh
swift ~/.codex/skills/ai-action-pi-poster/scripts/poster.swift split split.json
```

裁切坐标和目标坐标都是实际像素。该模式逐像素拼接，每个 source 与 destination 的宽高须一致。每页使用同一源长图，允许重复页头、页尾，断点应在制作后看图确定。

```json
{
  "source": "海报_高清2160.png",
  "width": 2160,
  "height": 2880,
  "color": "#101210",
  "pages": [
    {
      "output": "朋友圈/01.png",
      "slices": [
        {"source": [0,0,2160,1816], "destination": [0,0,2160,1816]},
        {"source": [0,4187,2160,1064], "destination": [0,1816,2160,1064]}
      ]
    }
  ]
}
```

示例断点对应第三期长图，仅适用于版式相同的源图。

## inspect

```sh
swift ~/.codex/skills/ai-action-pi-poster/scripts/poster.swift inspect 海报.png 验收.json qr.png
```

第三个路径是可选的二维码原图或含同一二维码的原海报。报告包含真实尺寸、OCR 结果、识别出的二维码数量和内容是否一致，不打印报名链接。`验收.json` 可省略，省略时报告到标准输出。报告文件同样默认拒绝覆盖，可更换版本名。

OCR 会漏读 π 或混淆 AI/Al，最终看实际字形和文字配置。原尺寸视觉检查、时间地点核对与本人肖像确认由助手按真实情况完成或说明。
