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

## 三个可复用场景

### 1. Windows 安装包索引

```moonbit nocheck
let listing = @moonmspack.read_cab(cab_bytes)
for entry in listing.entries {
  println(entry.name)
}
```

适合在不调用外部解压程序的情况下，展示安装包中的文件清单。

### 2. 受限提取

```moonbit nocheck
///|
let listing = @moonmspack.read_cab(cab_bytes)

///|
let file = listing.entries[0]

///|
let content = @moonmspack.extract_cab_entry(cab_bytes, file, limits={
  max_entries: 1000,
  max_output: 16 * 1024 * 1024,
  max_window: 32768,
})
```

所有文件表、块表、压缩输出和偏移都经过边界限制，适合服务端上传文件检查。

### 3. CHM 文档目录扫描

```moonbit nocheck
let listing = @moonmspack.read_chm_entries(chm_bytes)
for entry in listing.entries {
  println(entry.name)
}
```

适合文档离线索引、帮助文件迁移和格式审计。压缩 CHM 内容在 LZX 完整解码完成前会明确报告不支持，不会返回错误数据。

## 当前可量化验证

- `moon test` 当前包含 3 个通过测试，覆盖格式探测、位读取、CAB Stored 列表与提取。
- 所有公开读取入口均执行输入长度检查；CAB 提取受 `Limits.max_output` 限制。
- 支持目标由 MoonBit 工具链统一构建，未依赖系统 `cabextract` 或 Windows API。
