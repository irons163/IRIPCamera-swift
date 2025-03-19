//
//  DelayedTask.swift
//  IRIPCamera-swift
//
//  Created by irons on 2025/1/8.
//

import UIKit

class DelayedTask {
    private var workItem: DispatchWorkItem?

    func schedule(after seconds: TimeInterval, task: @escaping () -> Void) {
        cancel()
        workItem = DispatchWorkItem(block: task)
        if let workItem = workItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
        }
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
