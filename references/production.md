# 视觉与排版制作

## 已确认的做法

第三期采用深绿暗底、荧光绿重点、暖白标题和正文、边缘流线、讲师半身照与圆角信息模块。海报参考中的文字结构由当期内容决定，五项拆解和三项收获只是这一期的组织方式。

品牌参考色为深黑绿 `#101210`、暖白 `#F1F2EC`、荧光绿 `#BDFE32`，背景辅色为青绿 `#177B62` 与紫色 `#6551A7`。用户要求沿用某张确认稿时，以该稿的视觉为优先。Logo 原图中的颜色保持原样。

优先使用当前照片的实际轮廓。背景融合需要图像编辑时，清楚列出人物身份、脸、发型、衣着、姿势和比例等保持项。看实际输出，发现肩宽、手臂或五官失真时回到原照片合成。

## 图片工具提示词模板

下列为适配当前活动的骨架，执行前替换必要字段。参考图先通过 `view_image` 查看。

```text
Use case: compositing / identity-preserve.
Image 1 is the confirmed AI行动π poster STYLE REFERENCE.
Image 2 is the actual speaker photograph, the only identity source.
Create a clean black-emerald event-poster background with restrained lime and green flowing lines, following the reference's visual hierarchy and intended canvas aspect ratio.
Integrate the actual speaker photograph in the upper-right portrait area. Preserve the exact face, expression, glasses, hairstyle, clothing, pose and natural body proportions. Keep hair, shoulders and arms complete within the intended crop. Blend the original photo background into the dark green poster background.
Reserve quiet dark spaces for the title at upper-left and the event-content modules below. Retain readable contrast and a calm registration area.
Keep all typography, brand logo and QR code OUT of this background plate; we will compose the original logo, real-font text and actual registration code separately.
Do not add unrelated props, revenue claims, case names or extra people.
```

仅调整现有海报时，可只处理所需区域。已经清晰且风格适合的背景直接复用。生成图片以后，按最终文字量调整真实字体排版。

## 高清排字

用 `scripts/poster.swift render` 读取独立 JSON。文字作为文本层绘制在最终像素画布上，避免把低分辨率旧字放大当成新字。宽度默认 2160 像素，逻辑画布可继续使用原稿尺寸，输出时整体等比例缩放。

每个文本层设置足够的文本框和适当字号。脚本检测文本框溢出，失败时调整文案、行数或空间。确认稿的字体可能随本机可用字体略变，视觉检查字重与换行。

原始二维码用独立图片层放入，保留其白边并使用 nearest 插值。Logo 等比例使用原文件，保持原有透明或背景属性。人物照片的生成或抠像不会替代本人对肖像相似度的判断。

## 朋友圈图

优先按主题与完整模块重组，避免平均切成同高碎片。第三期使用两张 3:4 图，第一张为主题、讲师与报名，第二张为分享内容与收获。新活动可根据内容采用其他分组和张数。

沿用第三期长图的同一布局时，可参考 809×2037 逻辑坐标的拼接区间，先乘以实际宽度÷809，再计算目标像素高度的最后一段余量。

- 图一为 `y=0..680` 加 `y=1568..约1967`。
- 图二为 `y=0..105`、`y=680..1556` 和 `y=1867..约1965`。

这些坐标只适用于第三期最终稿。新排版完成后重新确定断点。每张确认完整文字、二维码、白边与安全边距，再输出。

## 本次流程暴露的限制

低分辨率成品的图中文字会在放大后发虚。重新排字可改善文字清晰度，照片仍受原素材限制。第三期图像生成的人像曾出现比例失真，最终以用户指定照片为依据。二维码识别比对只能验证图案内容，报名入口是否可用需要实际打开或微信实扫。
