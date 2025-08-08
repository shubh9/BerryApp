//
//  Item.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-08-08.
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
