//
//  SecondViewController.swift
//  TestGCDProject
//
//  Created by 杨世川 on 2025/9/1.
//

import UIKit

class SecondViewController: UIViewController {
    
    // 使用独立的队列，避免与ViewController竞争
    private let secondQueue = DispatchQueue(label: "SecondViewController.taskQueue", qos: .userInitiated, attributes: .concurrent)
    
    // 创建独立的操作队列，不依赖GCD的全局线程池
    private let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "SecondViewController.OperationQueue"
        queue.maxConcurrentOperationCount = 10 // 最大并发数
        queue.qualityOfService = .userInitiated
        return queue
    }()
    
    // 自定义线程池
//    private let customThreadPool = CustomThreadPool(maxThreadCount: 5, queueCapacity: 100)
    
    // 时间格式化器
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    // 带时间戳的打印函数
    private func printWithTime(_ message: String) {
        let timestamp = timeFormatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.white
        
        //添加测试按钮
        let testButton = UIButton.init(frame: CGRect(x: 100, y: 100, width: 100, height: 50))
        testButton.setTitle("测试线程", for: .normal)
        testButton.addTarget(self, action: #selector(testThread), for: .touchUpInside)
        testButton.backgroundColor = UIColor.red
        self.view.addSubview(testButton)
        
        // 添加多任务测试按钮
        let multiTaskButton = UIButton.init(frame: CGRect(x: 100, y: 200, width: 150, height: 50))
        multiTaskButton.setTitle("测试10个任务", for: .normal)
        multiTaskButton.addTarget(self, action: #selector(testMultiTasks), for: .touchUpInside)
        multiTaskButton.backgroundColor = UIColor.blue
        self.view.addSubview(multiTaskButton)
        
        // 添加OperationQueue测试按钮
        let operationButton = UIButton.init(frame: CGRect(x: 100, y: 350, width: 200, height: 50))
        operationButton.setTitle("OperationQueue测试", for: .normal)
        operationButton.addTarget(self, action: #selector(testOperationQueue), for: .touchUpInside)
        operationButton.backgroundColor = UIColor.green
        self.view.addSubview(operationButton)
        
        // 添加Thread测试按钮
        let threadButton = UIButton.init(frame: CGRect(x: 100, y: 400, width: 200, height: 50))
        threadButton.setTitle("独立Thread测试", for: .normal)
        threadButton.addTarget(self, action: #selector(testIndependentThread), for: .touchUpInside)
        threadButton.backgroundColor = UIColor.purple
        self.view.addSubview(threadButton)
        
        // 添加自定义线程池测试按钮
        let customPoolButton = UIButton.init(frame: CGRect(x: 100, y: 450, width: 200, height: 50))
        customPoolButton.setTitle("自定义线程池测试", for: .normal)
        customPoolButton.addTarget(self, action: #selector(testCustomThreadPool), for: .touchUpInside)
        customPoolButton.backgroundColor = UIColor.orange
        self.view.addSubview(customPoolButton)
        
        // 添加关闭按钮
        let closeButton = UIButton.init(frame: CGRect(x: 100, y: 550, width: 100, height: 50))
        closeButton.setTitle("关闭", for: .normal)
        closeButton.addTarget(self, action: #selector(closeView), for: .touchUpInside)
        closeButton.backgroundColor = UIColor.gray
        self.view.addSubview(closeButton)
        
        
        //测试GCD
        self.testGCD()
    }
    
    @objc func testGCD() -> () {
        let semaphore = DispatchSemaphore(value: 3) // 只允许3个并发
        let taskCount = 50 // 模拟50个任务
        
        self.monitorThreads(label: "SecondViewController___开始前")
        
        // 同时提交50个任务
        for i in 0..<taskCount {
            DispatchQueue.global(qos: .utility).async {
                self.monitorThreads(label: "SecondViewController___任务 \(i) 准备等待")
                
                semaphore.wait()  // 大部分会在这里等待
                
                self.monitorThreads(label: "SecondViewController___任务 \(i) 获得信号量")
                
                // 模拟网络请求耗时
                Thread.sleep(forTimeInterval: 1)
                
                self.monitorThreads(label: "SecondViewController___任务 \(i) 完成")
                semaphore.signal()
            }
        }
        
//        // 观察线程数变化
//        for second in 1...10 {
//            Thread.sleep(forTimeInterval: 1)
//            self.monitorThreads(label: "SecondViewController___\(second)秒后")
//        }
    }
    
    
    func getCurrentThreadCount() -> Int {
        var threadCount: mach_msg_type_number_t = 0
        var threadList: thread_act_array_t?
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if result == KERN_SUCCESS {
            // 释放线程列表内存
            if let list = threadList {
                let size = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), size)
            }
            return Int(threadCount)
        }
        
        return -1
    }
    
    func monitorThreads(label: String) {
        let threadCount = getCurrentThreadCount()
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] \(label) 当前线程数: \(threadCount)")
    }
    
    
    
    @objc func testThread() -> () {
        secondQueue.async { [self] in
            printWithTime("🔴SecondViewController 任务开始 - 线程: \(Thread.current)")
            Thread.sleep(forTimeInterval: 3.0)
            printWithTime("🔴SecondViewController 任务完成 - 线程: \(Thread.current)")
        }
    }
    
    @objc func testMultiTasks() -> () {
        for i in 0..<10 {
            secondQueue.async { [self] in
                printWithTime("🔵 SecondViewController GCD任务\(i) 开始 - 线程: \(Thread.current)")
                let delay = Double.random(in: 1.0...3.0)
                Thread.sleep(forTimeInterval: delay)
                printWithTime("🔵 SecondViewController GCD任务\(i) 完成 - 延时\(String(format: "%.1f", delay))秒")
            }
        }
    }
    
    @objc func testOperationQueue() -> () {
        for i in 0..<10 {
            let operation = BlockOperation { [self] in
                printWithTime("🟢 OperationQueue任务\(i) 开始 - 线程: \(Thread.current)")
                let delay = Double.random(in: 1.0...3.0)
                Thread.sleep(forTimeInterval: delay)
                printWithTime("🟢 OperationQueue任务\(i) 完成 - 延时\(String(format: "%.1f", delay))秒")
            }
            operationQueue.addOperation(operation)
        }
    }
    
    @objc func testIndependentThread() -> () {
        printWithTime("🟣 开始创建独立Thread测试")
        
        // 先检查当前线程数
        printThreadCount(prefix: "🟣 创建前")
        
        // 限制创建数量，避免线程爆炸
        let threadCount = 5 // 只创建5个线程进行测试
        
        for i in 0..<threadCount {
            // 创建真正独立的线程，不依赖任何线程池
            let thread = Thread { [self] in
                printWithTime("🟣 独立Thread任务\(i) 开始 - 线程: \(Thread.current)")
                let delay = Double.random(in: 1.0...3.0)
                Thread.sleep(forTimeInterval: delay)
                printWithTime("🟣 独立Thread任务\(i) 完成 - 延时\(String(format: "%.1f", delay))秒")
                
                // 任务完成后检查线程数
                DispatchQueue.main.async { [self] in
                    printThreadCount(prefix: "🟣 任务\(i)完成后")
                }
            }
            thread.name = "SecondViewController.IndependentThread.\(i)"
            thread.start()
        }
        
        // 创建后检查线程数
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            printThreadCount(prefix: "🟣 创建后")
        }
    }
    
    // 打印线程数量的辅助方法
    private func printThreadCount(prefix: String) {
        var threadCount: mach_msg_type_number_t = 0
        var threadList: thread_act_array_t?
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if result == KERN_SUCCESS {
            printWithTime("\(prefix) - 当前进程总线程数: \(threadCount)")
            
            if let list = threadList {
                let size = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), size)
            }
        } else {
            printWithTime("\(prefix) - 无法获取线程信息")
        }
    }
    
    @objc func testCustomThreadPool() -> () {
//        printWithTime("🟠 开始自定义线程池测试")
//        
//        // 检查线程池状态
//        let statusBefore = customThreadPool.getStatus()
//        printWithTime("🟠 测试前状态:\n\(statusBefore.description)")
//        
//        // 提交10个任务
//        for i in 0..<10 {
//            customThreadPool.execute { [self] in
//                printWithTime("🟠 自定义线程池任务\(i) 开始 - 线程: \(Thread.current)")
//                let delay = Double.random(in: 1.0...3.0)
//                Thread.sleep(forTimeInterval: delay)
//                printWithTime("🟠 自定义线程池任务\(i) 完成 - 延时\(String(format: "%.1f", delay))秒")
//            }
//        }
//        
//        // 延迟检查状态
//        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
////            let statusAfter = customThreadPool.getStatus()
////            printWithTime("🟠 1秒后状态:\n\(statusAfter.description)")
//        }
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [self] in
////            let statusFinal = customThreadPool.getStatus()
////            printWithTime("🟠 5秒后最终状态:\n\(statusFinal.description)")
//        }
    }
    
    @objc func closeView() -> () {
        // 关闭自定义线程池
//        customThreadPool.shutdown()
        self.dismiss(animated: true)
    }
}
