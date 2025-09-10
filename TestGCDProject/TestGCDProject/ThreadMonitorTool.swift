//
//  ThreadMonitorTool.swift
//  SkyPiCameraiOSProject
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 skyworth. All rights reserved.
//

import Foundation
import Darwin
import UIKit

/// 线程监控和测试工具类
class ThreadMonitorTool {
    //MARK: - 线程数量获取
    /// 获取当前进程的线程数量
    /// - Returns: 线程数量，失败返回 -1
    static func getCurrentThreadCount() -> Int {
        var threadCount: mach_msg_type_number_t = 0
        var threadList: thread_act_array_t?
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if result == KERN_SUCCESS {
            //释放线程列表内存
            if let list = threadList {
                let size = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), size)
            }
            return Int(threadCount)
        }
        
        return -1
    }
    
    /// 监控线程数量变化并打印
    /// - Parameter label: 标签，用于标识当前监控点
    static func monitorThreads(label: String) {
        let threadCount = getCurrentThreadCount()
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] \(label) 当前线程数: \(threadCount)")
    }
    
    //带时间戳的打印函数
    static func printWithTime(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }

    /// 非阻塞地每秒监控线程数量，持续指定秒数
    private static var _activeMonitors: [DispatchSourceTimer] = []
    private static let _monitorQueue = DispatchQueue(label: "thread.monitor.timer", qos: .userInteractive)
    private static func startThreadCountMonitor(everySecondFor totalSeconds: Int, labelPrefix: String = "") {
        let timer = DispatchSource.makeTimerSource(queue: _monitorQueue)
        var tick = 0
        let unlimited = totalSeconds <= 0
        timer.setEventHandler {
            tick += 1
            monitorThreads(label: "\(labelPrefix)\(tick)秒后")
            if !unlimited && tick >= totalSeconds {
                timer.cancel()
            }
        }
        timer.setCancelHandler {
            //移除强引用
            if let idx = _activeMonitors.firstIndex(where: { $0 === timer }) {
                _activeMonitors.remove(at: idx)
            }
        }
        timer.schedule(deadline: .now() + 1, repeating: 1)
        _activeMonitors.append(timer)
        timer.resume()
    }
    
    //MARK: - 测试方法
    /// 测试信号量阻塞时是否会创建新线程
    static func testSemaphoreThreadCreation() {
        let semaphore = DispatchSemaphore(value: 1) //只允许1个并发
        monitorThreads(label: "开始前")
        
        //同时发起5个任务
        for i in 0..<500 {
            DispatchQueue.global(qos: .utility).async {
                monitorThreads(label: "任务 \(i) wait前")
                semaphore.wait() //只有一个能通过，其他4个阻塞
                
                monitorThreads(label: "任务 \(i) working")
                Thread.sleep(forTimeInterval: 2) //模拟耗时操作
                
                monitorThreads(label: "任务 \(i) success")
                semaphore.signal()
            }
        }
        
        //使用定时器每秒打印一次，共10秒（不阻塞主线程）
        startThreadCountMonitor(everySecondFor: 10)
    }

    /// 基于真实网络请求的信号量测试（保留原方法不变，仅将延时替换为 URLSession 请求）
    static func testSemaphoreThreadCreationWithNetwork() {
        let semaphore = DispatchSemaphore(value: 1) //只允许1个并发
        monitorThreads(label: "开始前")
        
        //同时发起5个任务
        for i in 0..<500 {
            DispatchQueue.global(qos: .utility).async {
                monitorThreads(label: "任务 \(i) wait前")
                semaphore.wait()//只有一个能通过，其他4个阻塞
                
                monitorThreads(label: "任务 \(i) working")
                
                //使用真实网络请求代替延时
                let url = URL(string: "https://httpbin.org/delay/3")!
                URLSession.shared.dataTask(with: url) { _, _, _ in
                    monitorThreads(label: "任务 \(i) success")
                    semaphore.signal()
                }.resume()
            }
        }
        
        //使用定时器每秒打印一次，共10秒（不阻塞主线程）
        startThreadCountMonitor(everySecondFor: 10)
    }
     
     /// 测试不使用信号量的情况对比
     static func testMassiveTasksWithoutSemaphore() {
         print("\n=== 测试大量网络请求（不使用信号量） ===")
         let taskCount = 50
         
         monitorThreads(label: "开始前")
         
         //同时提交50个任务，不使用信号量
         for i in 0..<taskCount {
             DispatchQueue.global(qos: .utility).async {
                 monitorThreads(label: "无限制任务 \(i) 开始")
                 //模拟网络请求耗时
                 Thread.sleep(forTimeInterval: 1)
                 monitorThreads(label: "无限制任务 \(i) 完成")
             }
         }
         
         //使用定时器每秒打印一次，共10秒（不阻塞主线程）
         startThreadCountMonitor(everySecondFor: 10)
     }
    
    /// 升级版：串行调度队列 + 信号量限流（避免大量线程阻塞）
    static func testSemaphoreThreadCreationWithNetworkOptimized() {
        print("\n=== 升级版：串行调度 + 信号量限流（减少线程占用） ===")
        let semaphore = DispatchSemaphore(value: 1) // 允许5个并发网络请求
        let taskCount = 500
        
        //串行队列，用户操作触发的任务 → 用 .userInitiated，保证优先级够高
        //关键：使用串行队列做任务调度，只会阻塞这一个调度线程
        let dispatcherQueue = DispatchQueue(label: "network.task.dispatcher",qos: .utility)
        
        monitorThreads(label: "开始前")
        
        //在串行队列上逐个处理任务调度
        for i in 0..<taskCount {
            dispatcherQueue.async {
                monitorThreads(label: "任务 \(i) 准备等待")
                //在串行队列上等待信号量（只阻塞调度线程）
                semaphore.wait()
                
                monitorThreads(label: "任务 \(i) 获得信号量")
                
                //网络请求是耗时 IO → 用 .utility，避免占用过高优先级
                //网络请求在全局队列异步执行，不阻塞调度线程
                let url = URL(string: "https://httpbin.org/delay/3")!
                URLSession.shared.dataTask(with: url) { _, _, _ in
                    monitorThreads(label: "任务 \(i) 网络完成")
                    semaphore.signal() // 释放信号量，让下一个任务继续
                }.resume()
            }
        }
        
        //使用定时器监控线程变化
        startThreadCountMonitor(everySecondFor: 0) // 持续监控
    }
    
    /// 升级版2：使用 OperationQueue 限制并发（更优雅的方案）
    static func testSemaphoreThreadCreationWithOperationQueue() {
        print("\n=== 升级版2：OperationQueue 限制并发 ===")
        let taskCount = 500
        
        //创建 OperationQueue，限制最大并发数
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1 //最多5个并发
        operationQueue.qualityOfService = .utility
        
        monitorThreads(label: "开始前")
        
        //添加所有任务到队列
        for i in 0..<taskCount {
            let operation = BlockOperation {
                monitorThreads(label: "任务 \(i) 开始执行")
                
                //使用 DispatchGroup 等待异步网络请求完成
                let group = DispatchGroup()
                group.enter()
                
                let url = URL(string: "https://httpbin.org/delay/3")!
                URLSession.shared.dataTask(with: url) { _, _, _ in
                    monitorThreads(label: "任务 \(i) 网络完成")
                    group.leave()
                }.resume()
                
                group.wait() //在 Operation 的线程中等待
            }
            
            operationQueue.addOperation(operation)
        }
        
        //使用定时器监控线程变化
        startThreadCountMonitor(everySecondFor: 0) //持续监控
    }
    
    /// 升级版3：完全异步限流器（无阻塞，最优方案）
    static func testSemaphoreThreadCreationWithAsyncLimiter() {
        print("\n=== 升级版3：完全异步限流器（无线程阻塞） ===")
        let taskCount = 500
        let maxConcurrent = 3
        
        monitorThreads(label: "开始前")
        
        //异步限流器：维护一个执行中的任务计数器
        var runningTasks = 0
        var pendingTasks: [Int] = Array(0..<taskCount)
        let limiterQueue = DispatchQueue(label: "async.limiter", attributes: .concurrent)
        
        func executeNextTask() {
            limiterQueue.async(flags: .barrier) {
                guard runningTasks < maxConcurrent, !pendingTasks.isEmpty else { return }
                
                let taskIndex = pendingTasks.removeFirst()
                runningTasks += 1
                
                monitorThreads(label: "任务 \(taskIndex) 开始执行")
                
                //URLSession 本身就是异步的，无需额外包裹
                let url = URL(string: "https://httpbin.org/delay/3")!
                URLSession.shared.dataTask(with: url) { _, _, _ in
                    monitorThreads(label: "任务 \(taskIndex) 网络完成")
                    
                    //完成后递减计数器，并尝试启动下一个任务
                    limiterQueue.async(flags: .barrier) {
                        runningTasks -= 1
                        executeNextTask() //递归启动下一个
                    }
                }.resume()
                
                //如果还有空位，继续启动更多任务
                executeNextTask()
            }
        }
        
        //启动初始批次的任务
        executeNextTask()
        
        //使用定时器监控线程变化
        startThreadCountMonitor(everySecondFor: 0) //持续监控
    }
    
    /// 升级版4：自定义 AsyncOperation（最优雅方案）
    static func testSemaphoreThreadCreationWithAsyncOperation() {
        print("\n=== 升级版4：自定义 AsyncOperation（最优雅方案） ===")
        let taskCount = 500
        
        // 创建 OperationQueue，限制最大并发数
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 5 // 最多5个并发
        operationQueue.qualityOfService = .utility
        
        monitorThreads(label: "开始前")
        
        // 添加所有任务到队列
        for i in 0..<taskCount {
            let operation = NetworkAsyncOperation(taskIndex: i)
            operationQueue.addOperation(operation)
        }
        
        // 使用定时器监控线程变化
        startThreadCountMonitor(everySecondFor: 0) // 持续监控
    }
    
    /// 深层分析：为什么全局队列+信号量无法限制线程，而barrier可以？
    /// 1、信号量方案：
    /// "阻塞式限流" → 线程等待资源
    /// 所有任务都已经开始执行，只是被阻塞
    /// GCD必须为每个"执行中"的任务维持线程
    /// 2、Barrier方案：
    /// "门控式限流" → 任务等待执行机会
    /// 只有满足条件的任务才真正开始执行
    /// 不满足条件的任务立即返回，不占用线程
    /// 类比理解
    /// 信号量 = 停车场：500辆车都开进停车场，在入口排队等2个车位
    /// Barrier = 门卫：门卫检查，只放2辆车进入，其余车在外面不进场
    
    /// 验证barrier + Thread.sleep的问题（无法并发）
    /// --- Barrier的工作机制：---
    /// flags: .barrier 确保同一时间只有一个barrier任务在执行
    /// 当barrier任务运行时，队列中的所有其他任务（包括并发任务）都要等待
    /// 只有当前barrier任务完全结束后，下一个barrier任务才能开始
    /// --- Barrier的设计目的：---
    /// 状态同步：安全地读写共享变量（runningTasks）
    /// 调度控制：决定何时启动新任务
    /// 不是用来执行耗时操作的！
    
    /// 终极对比：AsyncOperation vs Barrier（相同条件下测试）
    static func compareAsyncOperationVsBarrier() {
        print("\n=== 终极对比：AsyncOperation vs Barrier ===")
        
        // 阶段1：AsyncOperation测试
        print("\n🔹 阶段1：AsyncOperation 方案测试")
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 3
        operationQueue.qualityOfService = .utility
        
        let startTime1 = Date()
        monitorThreads(label: "AsyncOperation开始前")
        
        for i in 0..<10 {
            let operation = NetworkAsyncOperation(taskIndex: i)
            operationQueue.addOperation(operation)
        }
        
        // 等待8秒后开始第二阶段
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            let duration1 = Date().timeIntervalSince(startTime1)
            print("AsyncOperation 阶段耗时: \(duration1)秒")
            monitorThreads(label: "AsyncOperation阶段结束")
            
            // 阶段2：Barrier测试
            print("\n🔹 阶段2：Barrier 方案测试")
            var runningTasks = 0
            var pendingTasks = Array(0..<10)
            let limiterQueue = DispatchQueue(label: "barrier.comparison", attributes: .concurrent)
            
            let startTime2 = Date()
            monitorThreads(label: "Barrier开始前")
            
            func executeNext() {
                limiterQueue.async(flags: .barrier) {
                    guard runningTasks < 3, !pendingTasks.isEmpty else {
                        if pendingTasks.isEmpty && runningTasks == 0 {
                            let duration2 = Date().timeIntervalSince(startTime2)
                            print("Barrier 阶段耗时: \(duration2)秒")
                            monitorThreads(label: "Barrier阶段结束")
                        }
                        return
                    }
                    
                    let taskIndex = pendingTasks.removeFirst()
                    runningTasks += 1
                    
                    ThreadMonitorTool.monitorThreads(label: "Barrier任务\(taskIndex) 开始执行")
                    
                    let url = URL(string: "https://httpbin.org/delay/3")!
                    URLSession.shared.dataTask(with: url) { _, _, _ in
                        ThreadMonitorTool.monitorThreads(label: "Barrier任务\(taskIndex) 网络完成")
                        
                        limiterQueue.async(flags: .barrier) {
                            runningTasks -= 1
                            executeNext()
                        }
                    }.resume()
                    
                    executeNext()
                }
            }
            
            executeNext()
        }
        startThreadCountMonitor(everySecondFor: 0)
    }
}

//MARK: - 自定义异步操作类

/// 自定义异步Operation，真正做到异步且不阻塞线程
class NetworkAsyncOperation: Operation {
    private let taskIndex: Int
    
    //状态管理
    private var _isExecuting = false {
        willSet {
            willChangeValue(forKey: "isExecuting")
        }
        didSet {
            didChangeValue(forKey: "isExecuting")
        }
    }
    
    private var _isFinished = false {
        willSet {
            willChangeValue(forKey: "isFinished")
        }
        didSet {
            didChangeValue(forKey: "isFinished")
        }
    }
    
    //重写必要的属性
    override var isAsynchronous: Bool {
        return true
    }
    
    override var isExecuting: Bool {
        return _isExecuting
    }
    
    override var isFinished: Bool {
        return _isFinished
    }
    
    init(taskIndex: Int) {
        self.taskIndex = taskIndex
        super.init()
    }
    
    override func start() {
        //检查是否被取消
        guard !isCancelled else {
            finish()
            return
        }
        
        //开始执行
        _isExecuting = true
        
        ThreadMonitorTool.monitorThreads(label: "AsyncOp任务\(taskIndex) 开始执行")
        
        //异步网络请求
        let url = URL(string: "https://httpbin.org/delay/3")!
        URLSession.shared.dataTask(with: url) { [weak self] _, _, _ in
            guard let self = self else { return }
            
            ThreadMonitorTool.monitorThreads(label: "AsyncOp任务\(self.taskIndex) 网络完成")
            
            //完成操作
            self.finish()
        }.resume()
    }
    
    private func finish() {
        _isExecuting = false
        _isFinished = true
    }
}

// MARK: - 辅助枚举
extension ThreadMonitorTool {
    enum TestType {
        case semaphore          // 信号量阻塞测试
        case asyncNetwork       // 异步网络请求测试
        case blockingWait       // 阻塞等待测试
        case massiveWaiting     // 大量等待测试
        case massiveTasksWithSemaphore    // 大量任务使用信号量
        case massiveTasksWithoutSemaphore // 大量任务不使用信号量
        case asyncOperation     // 自定义异步Operation测试
        case barrierSleep      // barrier + sleep测试
        case barrierAsync      // barrier + async测试
        case executionTime     // 执行时间对比测试
        case compareAsyncVsBarrier // AsyncOperation vs Barrier 终极对比
    }
}

// MARK: - 使用示例

/*
 // 在你的 ViewController 或者其他地方调用：
 
 class SomeViewController: UIViewController {
     override func viewDidLoad() {
         super.viewDidLoad()
         
         // 运行所有测试
         ThreadMonitorTool.runAllThreadTests()
         
         // 或者运行单个测试
         // ThreadMonitorTool.runSingleTest(.semaphore)
     }
 }
 
 // 在你的网络请求代码中监控线程：
 func someNetworkMethod() {
     ThreadMonitorTool.monitorThreads(label: "网络请求前")
     
     // 你的网络请求代码...
     IMSRequestClient.asyncSend(request) { response in
         ThreadMonitorTool.monitorThreads(label: "网络回调中")
         // 处理响应...
     }
 }
 */
