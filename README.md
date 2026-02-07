# SwiftHttpClient

一个轻量的 Swift 异步 HTTP 客户端库，提供：
- 简洁的 `GET` / `POST` / `POST JSON` 封装
- 自动 JSON 解码
- URL 编码表单提交
- 统一网络日志输出
- 可选的指定域名 SSL 信任

## 环境要求
- Swift 5.10+
- iOS 13+
- macOS 10.15+

## 安装 (Swift Package Manager)
在 `Package.swift` 中添加依赖：

```swift
.package(url: "https://github.com/steventong/SwiftHttpClient", branch: "main")
```

并在目标中引入：

```swift
.product(name: "SwiftHttpClient", package: "SwiftHttpClient")
```

## 快速开始

```swift
import SwiftHttpClient
import Foundation

struct Todo: Decodable {
    let id: Int
    let title: String
}

let client = HTTPClient(timeout: 15)
let url = URL(string: "https://jsonplaceholder.typicode.com/todos/1")!
let todo: Todo = try await client.get(url: url)
print(todo.title)
```

## API 示例

### 1) GET

```swift
let result: Todo = try await client.get(
    url: URL(string: "https://example.com/todo/1")!,
    headers: ["Authorization": "Bearer token"]
)
```

### 2) POST (x-www-form-urlencoded)

```swift
struct LoginResponse: Decodable {
    let token: String
}

let response: LoginResponse = try await client.post(
    url: URL(string: "https://example.com/login")!,
    parameters: ["username": "demo", "password": "123456"]
)
```

### 3) POST JSON

```swift
struct CreateTodoRequest: Encodable {
    let title: String
    let completed: Bool
}

struct CreateTodoResponse: Decodable {
    let id: Int
}

let created: CreateTodoResponse = try await client.postJSON(
    url: URL(string: "https://example.com/todos")!,
    body: CreateTodoRequest(title: "Write docs", completed: false)
)
```

### 4) 健康检查

```swift
let ok = await client.check(url: URL(string: "https://example.com/health")!)
```

## 错误处理

库对常见错误做了统一封装：
- `HTTPClientError.invalidResponse`: 返回值不是 `HTTPURLResponse`
- `HTTPClientError.httpStatus(code:)`: HTTP 状态码非 2xx
- `HTTPClientError.decodingFailed(message:)`: JSON 解码失败

示例：

```swift
do {
    let todo: Todo = try await client.get(url: url)
    print(todo)
} catch let error as HTTPClientError {
    print(error.localizedDescription)
} catch {
    print(error.localizedDescription)
}
```

## 日志

所有请求通过 `NetworkLogger` 执行，会输出：
- 请求方法、URL、请求头、请求体
- 响应状态码、响应头、响应体
- 请求耗时
- 异常详情

## SSL 信任域名

如需对某个域名启用自定义信任，可使用：

```swift
let client = HTTPClient(timeout: 15, trustedSSLDomain: "api.example.com")
```

也可以在运行时动态更新：

```swift
let client = HTTPClient(timeout: 15)
client.updateTrustedSSLDomain("api.example.com") // 启用
client.updateTrustedSSLDomain(nil)               // 关闭
```

注意：该能力会放宽该域名的证书校验，仅建议在可控环境（如测试环境）使用。

## 许可证

本项目使用 [MIT License](https://opensource.org/licenses/MIT)。
详见 `/Users/tongwanglin/Workspace/XcodeProjects/SwiftHttpClient/LICENSE`。
