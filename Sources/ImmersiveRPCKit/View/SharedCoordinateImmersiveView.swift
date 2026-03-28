//
//  SharedCoordinateImmersiveView.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/28.
//

import SwiftUI

/// Mixed Reality で複数 Peer 間の座標系共有が必要な場合に、アプリの ImmersiveView をラップするビュー。
///
/// 同一の ImmersiveSpace 内で `TransformationMatrixPreparationImmersiveView` と
/// アプリ独自のコンテンツを共存させ、`CoordinateSession.state` に応じてどちらが
/// アクティブかを自動で切り替えます。新しい ImmersiveSpace を開かないため、
/// ImmersiveView の座標系はそのまま保持されます。
///
/// - `state == .initial` のとき:
///   アプリのコンテンツが有効。RPCKit 側のエンティティは `isEnabled = false` で非表示。
/// - `state != .initial` のとき:
///   RPCKit 側のエンティティが有効。アプリのコンテンツは hit testing が無効になる。
///
/// ## 使い方
/// ```swift
/// ImmersiveSpace(id: "MySpace") {
///     SharedCoordinateImmersiveView(rpcModel: rpcModel, coordinateTransforms: coordinateTransforms) {
///         MyAppImmersiveView()
///     }
/// }
/// ```
@available(visionOS 26.0, *)
public struct SharedCoordinateImmersiveView<Content: View>: View {
    private let rpcModel: RPCModel
    private let coordinateTransforms: CoordinateTransforms
    private let content: () -> Content

    public init(
        rpcModel: RPCModel,
        coordinateTransforms: CoordinateTransforms,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.rpcModel = rpcModel
        self.coordinateTransforms = coordinateTransforms
        self.content = content
    }

    private var isCoordinateSessionActive: Bool {
        coordinateTransforms.session.state != .initial
    }

    public var body: some View {
        ZStack {
            content()
                .allowsHitTesting(!isCoordinateSessionActive)
                .frame(depth: 0)

            TransformationMatrixPreparationImmersiveView(
                rpcModel: rpcModel,
                coordinateTransforms: coordinateTransforms
            )
            .allowsHitTesting(isCoordinateSessionActive)
            .frame(depth: 0)
        }
    }
}
