# MoonMSPack

MoonBit 对 Microsoft Cabinet（CAB）和 Compiled HTML Help（CHM）格式的可嵌入解析库，移植自 `kyz/libmspack` 的相关设计与格式知识。

当前实现阶段：防御式读取器、CAB 目录解析、CHM 头部识别和统一格式探测已完成；MSZIP/LZX 解码、CHM 索引遍历和提取 API 正在继续实现。

## 设计边界

- 不替代 ZIP/TAR；不调用系统命令。
- 所有偏移和长度在读取前检查。
- API 接受内存 `Bytes`，方便 native、wasm-gc、wasm、js 共用。
- 初始版本不宣称支持 libmspack 的全部格式。

## 示例

```moonbit nocheck
let listing = @moonmspack.list(input)
println(listing.format)
for item in listing.entries { println(item.name) }
```

## 上游与许可证

上游：https://github.com/kyz/libmspack ，相关源文件为 LGPL-2.1。该项目保留上游归属说明，并将 MoonBit 实现与上游代码分离记录。
