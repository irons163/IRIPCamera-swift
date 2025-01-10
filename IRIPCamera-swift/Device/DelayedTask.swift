//
//  DelayedTask.swift
//  IRIPCamera-swift
//
//  Created by irons on 2025/1/8.
//

import UIKit

/// 延遲任務的封裝
class DelayedTask {
    private var workItem: DispatchWorkItem?

    /// 設置一個延遲執行的任務
    /// - Parameters:
    ///   - seconds: 延遲時間（秒）
    ///   - task: 延遲後執行的任務
    func schedule(after seconds: TimeInterval, task: @escaping () -> Void) {
        // 取消之前的任務（如果有）
        cancel()

        // 創建新的 DispatchWorkItem
        workItem = DispatchWorkItem(block: task)

        // 延遲執行任務
        if let workItem = workItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
        }
    }

    /// 取消任務
    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
