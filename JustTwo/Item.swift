//
//  Item.swift
//  JustTwo
//
//  Created by Dmitrii on 21.05.2026.
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
