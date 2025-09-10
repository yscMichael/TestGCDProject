//
//  ViewController.swift
//  TestGCDProject
//
//  Created by 杨世川 on 2025/9/1.
//

import UIKit
import Darwin

class ViewController: UIViewController {
    var timer: Timer?
    
    // 使用信号量控制最大并发数为5
    private let semaphore = DispatchSemaphore(value: 1)
    // 使用自定义队列，避免与其他界面竞争线程资源
    private let queue = DispatchQueue(label: "ViewController.taskQueue", qos: .utility, attributes: .concurrent, target: DispatchQueue.global(qos: .utility))
    
    // UI 组件
    private let startButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    
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
        setupUI()
        //测试线程释放问题
        //下面两个证明GCD+信号量+延时/网络请求，发现线程数量一样，大概是70左右，证明这些方案不能很好的限制线程数量
        //ThreadMonitorTool.runSingleTest(.massiveTasksWithSemaphore)
        //ThreadMonitorTool.testSemaphoreThreadCreationWithNetwork()
        
        //串行调度队列 + GCD+信号量限流+网络请求，发现线程数量的确降低了，大概9个左右（备注：我觉得这里可以把GCD去掉）
        //ThreadMonitorTool.testSemaphoreThreadCreationWithNetworkOptimized()
        
        //OperationQueue，发现线程数量的确降低了，大概8个左右(备注：自己确认OperationQueue的BlockOperation会开辟线程吗？)
        //ThreadMonitorTool.testSemaphoreThreadCreationWithOperationQueue()
        
        //完全异步限流器（无阻塞，最优方案），发现线程数量的确降了，大概8个左右
        ThreadMonitorTool.testSemaphoreThreadCreationWithAsyncLimiter()
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground
        //1、开始按钮
        startButton.setTitle("开始1000个打印任务", for: .normal)
        startButton.titleLabel?.font = UIFont.systemFont(ofSize: 18)
        startButton.backgroundColor = UIColor.systemBlue
        startButton.setTitleColor(UIColor.white, for: .normal)
        startButton.layer.cornerRadius = 8
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(startButtonTapped), for: .touchUpInside)
        view.addSubview(startButton)
        //设置约束
        NSLayoutConstraint.activate([
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 200),
            startButton.widthAnchor.constraint(equalToConstant: 200),
            startButton.heightAnchor.constraint(equalToConstant: 50),
        ])
        
        //2、下一个按钮
        nextButton.setTitle("进入下一个界面", for: .normal)
        nextButton.titleLabel?.font = UIFont.systemFont(ofSize: 18)
        nextButton.backgroundColor = UIColor.systemBlue
        nextButton.setTitleColor(UIColor.white, for: .normal)
        nextButton.layer.cornerRadius = 8
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.addTarget(self, action: #selector(enterNextButton), for: .touchUpInside)
        view.addSubview(nextButton)
        //设置约束
        NSLayoutConstraint.activate([
            nextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nextButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 450),
            nextButton.widthAnchor.constraint(equalToConstant: 200),
            nextButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
    
    //进入下一个界面
    @objc private func enterNextButton(){
        printWithTime("进入下一个界面，ViewController任务继续在后台执行...")
        let secondViewCtrl = SecondViewController.init()
        self.present(secondViewCtrl, animated: true)
    }
    
    //信号量阻塞时的线程创建
    func testSemaphoreGCD() -> () {
        for i in 0..<5 {
            DispatchQueue.global(qos: .utility).async {
                let threadName = Thread.current.name ?? "unknown"
                print("任务 \(i) 在线程 \(Thread.current) 等待")
                
                self.semaphore.wait()
                
                print("任务 \(i) 在线程 \(Thread.current) 执行")
                Thread.sleep(forTimeInterval: 1)
                
                self.semaphore.signal()
            }
        }
    }
    
    @objc private func startButtonTapped() {
        startButton.isEnabled = false
        startButton.setTitle("任务执行中...", for: .normal)
        printWithTime("开始执行100个打印任务，最大并发数: 5")
        
        // 线程监控 - 开始前
        printWithTime("📊 开始前 - CPU核心数: \(ProcessInfo.processInfo.activeProcessorCount)")
        printWithTime("📊 开始前 - 当前进程线程统计开始...")
        
        for i in 0..<100 {
            queue.async { [self] in
                self.printTask(taskId: i)
            }
        }
        printWithTime("所有任务已提交完成")
        
        // 延迟检查线程使用情况
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [self] in
            printWithTime("📊 3秒后线程检查...")
            printThreadInfo()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [self] in
            printWithTime("📊 10秒后线程检查...")
            printThreadInfo()
        }
    }
    
    // 打印线程信息的辅助方法
    private func printThreadInfo() {
        // 获取当前进程的线程信息
        var threadCount: mach_msg_type_number_t = 0
        var threadList: thread_act_array_t?
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if result == KERN_SUCCESS {
            printWithTime("📊 当前进程总线程数: \(threadCount)")
            
            // 释放线程列表内存
            if let list = threadList {
                let size = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), size)
            }
        } else {
            printWithTime("📊 无法获取线程信息")
        }
    }
    
    // 打印函数 - 简单直接的同步版本
    private func printTask(taskId: Int) {
        printWithTime("ViewController任务-----\(taskId)---\(Thread.current) - 尝试获取信号量")
        
        // 获取信号量，控制并发数
        //semaphore.wait()
        
        // 随机延时1-3秒
        let randomDelay = Double.random(in: 1.0...3.0)
        printWithTime("ViewController任务 \(taskId) 开始执行，预计延时: \(String(format: "%.1f", randomDelay))秒")
        
        // 直接使用Thread.sleep模拟延时
        Thread.sleep(forTimeInterval: randomDelay)
        
        // 任务完成
        printWithTime("ViewController任务 \(taskId) 完成 - 延时 \(String(format: "%.1f", randomDelay))秒 - 线程: \(Thread.current)")
        printWithTime("ViewController任务 \(taskId) 释放信号量")
        
        // 释放信号量
        //semaphore.signal()
    }
}


