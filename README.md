# ImmersiveRPCKit

MultipeerConnectivity を使って visionOS アプリ間で型安全に RPC (Remote Procedure Call) を行うための Swift パッケージです。

- **Entity を定義するだけ** で型安全な RPC が利用できます
- `RPCModel` 本体は **変更不要** — Entity の追加は `init(entities:)` に渡すだけ
- **Broadcast / Unicast** を型レベルで区別 — `BroadcastMethod` を特定 Peer へ送るコードはコンパイルエラーになります
- **`run` 1 本で** ローカル実行・リモート送信・座標変換のパターンを使い分けられます
- 自動 ACK・失敗時の再送機能が内蔵されています

## 要件

| 項目     | バージョン |
| -------- | ---------- |
| visionOS | 26.0+      |
| Swift    | 6.2+       |

## インストール

```swift
dependencies: [
    .package(url: "https://github.com/kanakanho/ImmersiveRPCKit.git", from: "1.0.0")
],
targets: [
    .target(name: "YourTarget", dependencies: ["ImmersiveRPCKit"])
]
```

---

## セットアップ

### 1. Entity を定義する

Entity は RPC の「名前空間」です。`BroadcastMethod`（全 Peer へ broadcast）と `UnicastMethod`（特定 Peer へ unicast）を実装します。
片方が不要な場合は `NoMethod<HandlerType>` を typealias します。

```swift
// MARK: - Handler（ビジネスロジックを持つオブジェクト）

@Observable
class ChatHandler {
    var messages: [String] = []

    func send(text: String) -> RPCResult {
        messages.append(text)
        return RPCResult()
    }

    func directMessage(text: String, from peer: Int) -> RPCResult {
        messages.append("[DM:\(peer)] \(text)")
        return RPCResult()
    }
}

// MARK: - Entity

struct ChatEntity: RPCEntity {
    static let codingKey = "chat"

    // 全 Peer へ broadcast するメソッド
    enum BroadcastMethod: RPCBroadcastMethod {
        typealias Handler = ChatHandler
        case sendMessage(SendMessageParam)
        struct SendMessageParam: Codable { let text: String }

        func execute(on handler: ChatHandler) -> RPCResult {
            switch self {
            case .sendMessage(let p): return handler.send(text: p.text)
            }
        }
        enum CodingKeys: CodingKey { case sendMessage }
    }

    // 特定 Peer へ unicast するメソッド
    enum UnicastMethod: RPCUnicastMethod {
        typealias Handler = ChatHandler
        case directMessage(DirectMessageParam)
        struct DirectMessageParam: Codable { let text: String; let fromPeerId: Int }

        func execute(on handler: ChatHandler) -> RPCResult {
            switch self {
            case .directMessage(let p):
                return handler.directMessage(text: p.text, from: p.fromPeerId)
            }
        }
        enum CodingKeys: CodingKey { case directMessage }
    }
}
```

### 2. Info.plist に権限を追加する

MultipeerConnectivity はローカルネットワークと Bonjour サービスの権限が必要です。
`Info.plist`（または Xcode の Target → Info タブ）に以下を追加してください。

| Key                              | 値                                                            |
| -------------------------------- | ------------------------------------------------------------- |
| `NSLocalNetworkUsageDescription` | `"近くのデバイスと通信するために使用します"` など任意の説明文 |
| `NSBonjourServices`              | `_ImmersiveRPCKit._tcp`, `_ImmersiveRPCKit._udp`              |

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>近くのデバイスと通信するために使用します</string>
<key>NSBonjourServices</key>
<array>
    <string>_ImmersiveRPCKit._tcp</string>
    <string>_ImmersiveRPCKit._udp</string>
</array>
```

### 3. 通信オブジェクトを初期化する

アプリ起動時に以下のオブジェクトを生成し、環境に注入します。

```swift
import ImmersiveRPCKit

@main
struct MyApp: App {
    // 通信の送受信バッファ
    private let sendWrapper    = ExchangeDataWrapper()
    private let receiveWrapper = ExchangeDataWrapper()
    // Peer ID 管理
    private let peerWrapper    = MCPeerIDUUIDWrapper()

    // MultipeerConnectivity セッション管理
    private let peerManager: PeerManager

    // Entity ハンドラ（ビジネスロジック）
    private let chatHandler = ChatHandler()

    // RPC モデル
    private let rpcModel: RPCModel

    init() {
        peerManager = PeerManager(
            sendExchangeDataWrapper: sendWrapper,
            receiveExchangeDataWrapper: receiveWrapper,
            mcPeerIDUUIDWrapper: peerWrapper
        )
        rpcModel = RPCModel(
            sendExchangeDataWrapper: sendWrapper,
            receiveExchangeDataWrapper: receiveWrapper,
            mcPeerIDUUIDWrapper: peerWrapper,
            entities: [
                RPCEntityRegistration<ChatEntity>(handler: chatHandler)
            ]
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(rpcModel)
                .environment(chatHandler)
        }

        ImmersiveSpace(id: "MyImmersiveSpace") {
            MyAppImmersiveView()
        }
    }
}
```

### 4. PeerManager を起動・停止する

`PeerManager.start()` を呼ぶと Advertise と Browse が始まり、近くの Peer と自動接続します。
アプリがバックグラウンドに移行する際は `stop()` で停止してください。

```swift
struct ContentView: View {
    var body: some View {
        // ...
        .onAppear   { peerManager.start() }
        .onDisappear { peerManager.stop() }
    }
}
```

> [!TIP] **MultipeerConnectivity を使わない場合**  
> `PeerManager` は `sendWrapper`・`receiveWrapper`・`peerWrapper` の 3 つのオブジェクトを介して `RPCModel` と通信します。  
> これらに対応した独自の双方向通信システムを実装し、同じインターフェイスで `sendWrapper` へのデータ書き込みと `receiveWrapper` からのデータ読み取りを行えば、`PeerManager` の置き換えが可能です。  
> WebSocket や Network.framework など任意のトランスポート層に差し替え可能です。

---

## 座標共有（SharedCoordinate）を有効にする（オプション）

複数の visionOS デバイス間でワールド座標系を共有したい場合に追加で必要な手順です。
上の「セットアップ」が完了していることが前提です。

### 1. Info.plist に Hand Tracking 権限を追加する

座標取得に手のトラッキングを使用します。

| Key                               | 値                                                        |
| --------------------------------- | --------------------------------------------------------- |
| `NSHandsTrackingUsageDescription` | `"座標共有のために手の位置を使用します"` など任意の説明文 |

```xml
<key>NSHandsTrackingUsageDescription</key>
<string>座標共有のために手の位置を使用します</string>
```

### 2. CoordinateTransforms を追加して RPCModel に登録する

手順 3 の `RPCModel` 初期化コードに追記します。

```diff
struct MyApp: App {
+   private let coordinateTransforms = CoordinateTransforms()

    // RPCModel の entities に追加
    rpcModel = RPCModel(
        sendExchangeDataWrapper: sendWrapper,
        receiveExchangeDataWrapper: receiveWrapper,
        mcPeerIDUUIDWrapper: peerWrapper,
        entities: [
            RPCEntityRegistration<ChatEntity>(handler:  chatHandler),
+           RPCEntityRegistration<CoordinateTransformEntity>(handler: coordinateTransforms)
        ]
    )
}
```

### 3. ImmersiveSpace を SharedCoordinateImmersiveView でラップする

既存の ImmersiveSpace はそのままで、コンテンツを `SharedCoordinateImmersiveView` で包むだけです。
**新しい ImmersiveSpace を追加しないことが重要です**（座標系が保持されます）。

```diff
var body: some Scene {
    ImmersiveSpace(id: "MyImmersiveSpace") {
-       MyAppImmersiveView()
+       SharedCoordinateImmersiveView(
+           rpcModel: rpcModel,
+           coordinateTransforms: coordinateTransforms
+       ) {
+           MyAppImmersiveView()
+       }
    }
}
```

`CoordinateSession.state` に応じて自動で切り替わります。

| state      |  アプリコンテンツ  | 座標共有 UI（手追跡など） |
| ---------- | :----------------: | :-----------------------: |
| `.initial` |     アクティブ     |          非表示           |
| それ以外   | 非インタラクティブ |        アクティブ         |

### 4. 座標共有の操作 UI を Window に追加する

`TransformationMatrixPreparationView` を操作用の Window として表示します。
この View が座標共有フロー（Peer 選択 → 各自の座標取得 → アフィン行列の計算）を一括で管理します。

```diff
+ TransformationMatrixPreparationView(
+     rpcModel: rpcModel,
+     coordinateTransforms: coordinateTransforms
+ )
```

座標共有が完了すると `coordinateTransforms.affineMatrixs[otherPeerId]` にアフィン行列が格納されます。
また `RPCModel.affineMatrixProvider` に設定されるため、 `run(transforming:)` から自動適用できます。

---

## リクエスト型

`run` に渡すリクエストは **3 種類** あり、コンパイル時に用途が保証されます。

| 型                    | 生成方法                                           | 用途                                 |
| --------------------- | -------------------------------------------------- | ------------------------------------ |
| `RPCBroadcastRequest` | `Entity.request(_ method: BroadcastMethod)`        | broadcast のみ（特定 Peer 送信不可） |
| `RPCLocalRequest`     | `Entity.localRequest(_ method: UnicastMethod)`     | ローカル実行のみ（`to:` 不要）       |
| `RPCUnicastRequest`   | `Entity.request(_ method: UnicastMethod, to: Int)` | remote unicast・syncAll              |

```swift
// BroadcastMethod → RPCBroadcastRequest（特定 Peer への送信には使えない）
let broadcastReq = ChatEntity.request(.sendMessage(.init(text: "hello")))

// UnicastMethod → RPCLocalRequest（to: 不要・ローカル実行専用）
let localReq = ChatEntity.localRequest(.directMessage(.init(text: "hi", fromPeerId: myId)))

// UnicastMethod → RPCUnicastRequest（targetPeerId が必須）
let unicastReq = ChatEntity.request(.directMessage(.init(text: "hi", fromPeerId: myId)), to: remotePeerId)
```

---

## run — メインの API

`run` は **ローカル実行 × ネットワーク送信** の組み合わせをパターン別に提供します。
通常は `run` のみを使用し、`send` を直接呼ぶ必要はありません。

### パターン一覧

| メソッド                                 | リクエスト型                                  | ローカル実行 |     リモート送信     | 戻り値        |
| ---------------------------------------- | --------------------------------------------- | :----------: | :------------------: | ------------- |
| `run(localOnly:)`                        | `RPCLocalRequest`                             |      ✅      |          ❌          | `RPCResult`   |
| `run(remoteOnly:)`                       | `RPCUnicastRequest`                           |      ❌      |  ✅ unicast 1 Peer   | `RPCResult`   |
| `run(remoteOnly:toEach:)`                | `RPCUnicastRequest` + `RPCUnicastMultiTarget` |      ❌      | ✅ unicast 複数 Peer | `[RPCResult]` |
| `run(syncAll:)`                          | `RPCBroadcastRequest`                         |      ✅      |     ✅ broadcast     | `RPCResult`   |
| `run(syncAll:)`                          | `RPCUnicastRequest`                           |      ✅      |  ✅ unicast 1 Peer   | `RPCResult`   |
| `run(syncAll:toEach:)`                   | `RPCUnicastRequest` + `RPCUnicastMultiTarget` |      ✅      | ✅ unicast 複数 Peer | `[RPCResult]` |
| `run(transforming:requestFor:)`          | クロージャ `(Int) -> RPCUnicastRequest?`      |      ✅      |      ✅ unicast      | `[RPCResult]` |
| `run(transforming:_:_:affineMatrixFor:)` | `RPCTransformableUnicastMethod`               |      ✅      |      ✅ unicast      | `[RPCResult]` |
| `run(transforming:_:_:)`                 | 同上（`affineMatrixProvider` 使用）           |      ✅      |      ✅ unicast      | `[RPCResult]` |

---

### 送信先パターン早見表

「どの Peer にリクエストを届けたいか」から使う `run` を選べます。

| 自 Peer | 他 Peer（1件） | 他 Peer（複数件） | 使う `run`                                       |
| :-----: | :------------: | :---------------: | ------------------------------------------------ |
|   ✅    |       ❌       |        ❌         | `run(localOnly:)`                                |
|   ❌    |       ✅       |        ❌         | `run(remoteOnly: RPCUnicastRequest)`             |
|   ❌    |       ❌       |        ✅         | `run(remoteOnly:toEach:)`                        |
|   ✅    |       ✅       |        ❌         | `run(syncAll: RPCUnicastRequest)`                |
|   ✅    |       ❌       |        ✅         | `run(syncAll:toEach:)` / `run(transforming:...)` |
|   ✅    |       ✅       |        ✅         | `run(syncAll: RPCBroadcastRequest)`              |

> **自 Peer** = ローカルのハンドラを実行する  
> **他 Peer（1件）** = `targetPeerId` で指定した 1 つの Peer へ送信  
> **他 Peer（複数件）** = `RPCUnicastMultiTarget` で指定した複数の Peer へそれぞれ送信

---

### `run(localOnly:)` — ローカルのみ実行

ネットワーク送信は行わず、自端末のハンドラだけを呼びます。
`RPCLocalRequest` を受け取るため `to:` の指定は不要です（`BroadcastMethod` はコンパイルエラー）。

```swift
rpcModel.run(
    localOnly: ChatEntity.localRequest(.directMessage(.init(text: "local echo", fromPeerId: myId)))
)
```

---

### `run(remoteOnly:)` — unicast のみ送信

ローカルのハンドラは呼ばず、`request.targetPeerId` の Peer へ送信します。

```swift
rpcModel.run(
    remoteOnly: ChatEntity.request(.directMessage(.init(text: "hi", fromPeerId: myId)), to: remotePeerId)
)
```

---

### `run(syncAll:)` — ローカル実行 + unicast

ローカルでも実行し、成功したら `request.targetPeerId` の Peer へ送信します。
**ローカル実行が失敗した場合はネットワーク送信をスキップします。**

```swift
rpcModel.run(
    syncAll: ChatEntity.request(.directMessage(.init(text: "hi", fromPeerId: myId)), to: remotePeerId)
)
```

---

### `run(remoteOnly:toEach:)` — unicast 複数 Peer 送信

ローカルのハンドラは呼ばず、`toEach` で指定した複数 Peer へそれぞれ送信します。

```swift
rpcModel.run(
    remoteOnly: ChatEntity.request(.directMessage(.init(text: "hi", fromPeerId: myId)), to: 0),
    toEach: .peers([peer1, peer2])
)
```

---

### `run(syncAll:)` — ローカル実行 + broadcast

ローカルでも実行し、成功したら全 Peer へ broadcast します。
**ローカル実行が失敗した場合は broadcast をスキップします。**

```swift
rpcModel.run(
    syncAll: ChatEntity.request(.sendMessage(.init(text: "hello everyone")))
)
```

---

### `run(syncAll:toEach:)` — ローカル実行 + unicast 複数 Peer 送信

ローカルでも実行し、成功したら `toEach` で指定した複数 Peer へそれぞれ送信します。
**ローカル実行が失敗した場合はネットワーク送信をスキップします。**

```swift
rpcModel.run(
    syncAll: ChatEntity.request(.directMessage(.init(text: "hi", fromPeerId: myId)), to: 0),
    toEach: .peers([peer1, peer2])
)
```

---

### `run(transforming:requestFor:)` — クロージャで Peer ごとに変換

`to` で指定した Peer ID を 1 つずつクロージャに渡します。

- `nil` を返した Peer はスキップ
- 自端末（`mine.hash`）はローカル実行のみ（送信なし）
- ローカル実行が失敗した場合は以降の送信をスキップ

```swift
rpcModel.run(transforming: .all) { peerId in
    guard let affine = coordinateTransforms.affineMatrix(for: peerId) else { return nil }
    return CoordinateTransformEntity.request(
        .setTransform(.init(peerId: myPeerId, matrix: affine * localMatrix)),
        to: peerId
    )
}
```

---

### `run(transforming:_:_:affineMatrixFor:)` — アフィン行列を自動適用

`UnicastMethod` が `RPCTransformableUnicastMethod` に準拠していれば、
`applying(affineMatrix:)` に自動でアフィン行列を渡して変換した上で各 Peer へ送信します。

```swift
rpcModel.run(
    transforming: .all,
    ObjectEntity.self,
    .move(.init(matrix: localMatrix))
) { peerId in
    coordinateTransforms.affineMatrix(for: peerId)
}
```

`affineMatrixProvider` をあらかじめセットすれば、プロバイダ引数を省略できます。

> [!NOTE] **`SharedCoordinateImmersiveView` を使用している場合は自動設定されます。** 手動でセットする必要はありません。

`SharedCoordinateImmersiveView` を使わない場合は、手動でセットしてください。

`affineMatrixProvider` の指定

```swift
rpcModel.affineMatrixProvider = { peerId in
    coordinateTransforms.affineMatrix(for: peerId)
}
```

`affineMatrixProvider` 自動適用時の呼び出し

```swift
rpcModel.run(transforming: .all, ObjectEntity.self, .move(.init(matrix: localMatrix)))
```

#### `RPCTransformableUnicastMethod` の実装

```swift
enum UnicastMethod: RPCTransformableUnicastMethod {
    typealias Handler = ObjectHandler
    case move(MoveParam)
    struct MoveParam: Codable { let matrix: simd_float4x4 }

    func execute(on handler: ObjectHandler) -> RPCResult {
        switch self {
        case .move(let p): return handler.move(matrix: p.matrix)
        }
    }

    // アフィン行列を適用して変換済みメソッドを返す
    func applying(affineMatrix: simd_float4x4) -> Self {
        switch self {
        case .move(let p): return .move(.init(matrix: affineMatrix * p.matrix))
        }
    }

    enum CodingKeys: CodingKey { case move }
}
```

---

## RPCUnicastMultiTarget — 複数 Peer 送信先の指定

`run(remoteOnly:toEach:)` / `run(syncAll:toEach:)` / `run(transforming:...)` の複数 Peer 送信に渡します。
1 Peer への送信は `run(remoteOnly:)` / `run(syncAll:)` を使ってください。

| 値              | 送信先                                                     |
| --------------- | ---------------------------------------------------------- |
| `.all`          | `mcPeerIDUUIDWrapper.standby` の全 Peer へそれぞれ unicast |
| `.peer(Int)`    | 特定の 1 Peer（`transforming` での絞り込み等に使用）       |
| `.peers([Int])` | 複数の Peer それぞれへ unicast                             |

---

## 受信

受信は **自動**です。`RPCModel` は `receiveExchangeDataWrapper` を監視し、
デコードしたリクエストに対応するハンドラの `execute(on:)` を自動で呼び出します。

```swift
// chatHandler.messages が更新されると @Observable で View が再描画される
Text(chatHandler.messages.last ?? "")
```

---

## 再送機能

デフォルトですべてのメソッドは **失敗時に自動再送**されます。
特定のメソッドで無効にするには `allowRetry` を `false` に返します。

```swift
var allowRetry: Bool {
    switch self {
    case .sendMessage: return false   // 再送不要
    }
}
```

---

## 組み込み Entity

`RPCModel` は以下の内部 Entity を自動で登録します。ユーザーが意識する必要はありません。

| Entity                 | codingKey | 動作                                           |
| ---------------------- | --------- | ---------------------------------------------- |
| `AcknowledgmentEntity` | `"ack"`   | ACK 受信時にリクエストキューからエントリを削除 |
| `ErrorEntitiy`         | `"error"` | エラー受信時にコンソールへログ出力             |

---

## アーキテクチャ

```
呼び出し元
  │
  │  run(localOnly:)               → ローカル execute のみ（RPCLocalRequest 専用・to: 不要）
  │  run(remoteOnly:)              → unicast 1 Peer send のみ → RPCResult
  │  run(remoteOnly:toEach:)       → unicast 複数 Peer send のみ → [RPCResult]
  │  run(syncAll:)                 → ローカル execute + broadcast send
  │  run(syncAll:)                 → ローカル execute + unicast 1 Peer send → RPCResult
  │  run(syncAll:toEach:)          → ローカル execute + unicast 複数 Peer send → [RPCResult]
  │  run(transforming:requestFor:) → ローカル execute + Peer ごとに変換して unicast send
  │  run(transforming:_:_:...)     → ローカル execute + アフィン自動適用して unicast send
  │
  ▼
RPCModel
  ├─ ローカル実行:  MethodRegistry → handler.execute(on:)
  └─ ネットワーク: JSON エンコード → ExchangeDataWrapper → MultipeerConnectivity
                                                              │
                                                              ▼
                                                         受信側 RPCModel
                                                           MethodRegistry → handler.execute(on:)
                                                           成功 → ACK 自動送信
                                                           失敗 → Error 自動送信
```

---

## JSON ワイヤーフォーマット（参考）

```json
{
  "id": "<UUID>",
  "peerId": 12345,
  "method": {
    "<entityCodingKey>": {
      "b": { "<methodCase>": { ...params... } }
    }
  }
}
```

- `"b"` キー → `BroadcastMethod`
- `"u"` キー → `UnicastMethod`
