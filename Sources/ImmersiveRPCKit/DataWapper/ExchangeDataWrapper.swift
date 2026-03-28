//
//  ExchangeData.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation

struct ExchangeData {
    var data: Data
    var mcPeerId: Int
}

/// 送受信データの AsyncStream ラッパー
final class ExchangeDataWrapper: Sendable {
    /// 全送受信データを順序保証で配信する AsyncStream
    let stream: AsyncStream<ExchangeData>
    private let continuation: AsyncStream<ExchangeData>.Continuation

    init() {
        (stream, continuation) = AsyncStream<ExchangeData>.makeStream()
    }

    deinit {
        continuation.finish()
    }

    func setData(_ data: Data) {
        continuation.yield(ExchangeData(data: data, mcPeerId: 0))
    }

    func setData(_ data: Data, to mcPeerId: Int) {
        continuation.yield(ExchangeData(data: data, mcPeerId: mcPeerId))
    }
}
