//
//  ExchangeData.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation

public struct ExchangeData: Sendable {
    public var data: Data
    public var mcPeerId: Int
}

/// 送受信データの AsyncStream ラッパー
public final class ExchangeDataWrapper: Sendable {
    /// 全送受信データを順序保証で配信する AsyncStream
    public let stream: AsyncStream<ExchangeData>
    private let continuation: AsyncStream<ExchangeData>.Continuation

    public init() {
        (stream, continuation) = AsyncStream<ExchangeData>.makeStream()
    }

    deinit {
        continuation.finish()
    }

    public func setData(_ data: Data) {
        continuation.yield(ExchangeData(data: data, mcPeerId: 0))
    }

    public func setData(_ data: Data, to mcPeerId: Int) {
        continuation.yield(ExchangeData(data: data, mcPeerId: mcPeerId))
    }
}
