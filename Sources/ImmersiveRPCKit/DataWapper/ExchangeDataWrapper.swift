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

@available(visionOS 26.0, *)
@Observable
class ExchangeDataWrapper {
    var exchangeData: ExchangeData
    
    init(data: Data, mcPeerId: Int) {
        self.exchangeData = ExchangeData(data: data, mcPeerId: mcPeerId)
    }
    
    init() {
        self.exchangeData = ExchangeData(data: Data(), mcPeerId: 0)
    }
    
    init(data: Data) {
        self.exchangeData = ExchangeData(data: data, mcPeerId: 0)
    }
    
    func setData(_ data: Data) {
        self.exchangeData = ExchangeData(data: data, mcPeerId: 0)
    }
    
    func setData(_ data: Data, to mcPeerId: Int) {
        self.exchangeData = ExchangeData(data: data, mcPeerId: mcPeerId)
    }
}
