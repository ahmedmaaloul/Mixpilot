import Darwin

/// Which process macOS holds responsible for another one.
///
/// XPC services such as `com.apple.WebKit.GPU` (where Safari and Mail actually play sound) are
/// started by launchd, so their parent is PID 1; only the *responsible* PID leads back to the app.
/// The function is private SPI (`responsibility_get_pid_responsible_for_pid` in libsystem), so it is
/// looked up at runtime: if a macOS update removes it, grouping falls back to parent PIDs and bundle
/// IDs instead of crashing. Keep every use of private API in this file.
enum Responsibility {
    private typealias Function = @convention(c) (pid_t) -> pid_t

    private static let function: Function? = {
        // RTLD_DEFAULT: search every image loaded in the process.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: Function.self)
    }()

    /// Whether the lookup is available on this system (for diagnostics).
    static var isAvailable: Bool { function != nil }

    /// The responsible PID, or nil if it is unknown or the process is its own.
    static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let function, pid > 0 else { return nil }
        let responsible = function(pid)
        return responsible > 0 && responsible != pid ? responsible : nil
    }
}

/// Parent process lookup through `sysctl` (public API).
enum ProcessTree {
    /// The parent PID, or nil for processes started by launchd and on error.
    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 1 ? parent : nil
    }
}
