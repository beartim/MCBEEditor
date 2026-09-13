# Windows 图标

- `MCBEEditor-transparent.png`：1254×1254 RGBA 图标母版，以 iOS 基岩方块图标为参考，通过内置图像生成工具重制。
- `MCBEEditor.ico`：从母版缩小并封装，包含 16、20、24、32、40、48、64、96、128、256 像素版本。所有尺寸保留 alpha。
- WPF 的 ApplicationIcon 和 PortableLauncher 的 Windows 资源脚本共用此 ICO。

本次最终采用的生成提示词：

> Use case: background-extraction. Asset type: production Windows application icon, transparent PNG. Edit target: attached MCBEEditor iOS icon. Recreate faithfully the SAME isolated isometric Minecraft bedrock cube, same orientation, exact outer hexagonal silhouette, gray and charcoal pixel blocks, proportions and original pattern, with sharp clean edges at high resolution. Remove ALL white backdrop, white haze and any drop shadow completely. True RGBA alpha transparency outside the cube, including edge antialiasing without white matte or halo. Fill square 1024x1024 canvas with the cube approximately 85% of width and 92% of height centered; generous but small transparent margins so it works in Windows 16/24/32/48/256px icons. All internal cube pixels opaque; retain original neutral gray tones with enough contrast for small sizes. No white square, no checkerboard pattern baked into image, no added objects, text, highlights, glow or shadow. Preserve design identity of source iOS icon. Deliver actual transparent PNG.
