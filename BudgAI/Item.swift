//
//  Item.swift
//  BudgAI
//
//  Created by Alex Parker on 4/30/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
