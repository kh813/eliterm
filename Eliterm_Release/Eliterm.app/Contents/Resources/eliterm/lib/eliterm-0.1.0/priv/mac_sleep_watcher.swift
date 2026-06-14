import Cocoa
import Darwin

class SleepWatcher {
    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(willSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        // Print ready
        print("READY")
        fflush(stdout)
    }

    @objc func willSleep(_ notification: Notification) {
        // Notify Elixir
        print("SLEEP_DETECTED")
        fflush(stdout)

        // Block sleep by waiting for Elixir to reply (up to 25 seconds to be safe before macOS forces sleep at 30s)
        let fd = FileHandle.standardInput.fileDescriptor
        var fds = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        
        // poll for 25000 milliseconds
        let ret = poll(&fds, 1, 25000)
        
        if ret > 0 {
            // Read the message from Elixir (e.g., MIGRATION_DONE)
            _ = readLine()
            print("ACK_SLEEP")
        } else {
            print("TIMEOUT_SLEEP")
        }
        fflush(stdout)
        
        // Returning from this handler allows the system to proceed with sleep
    }
}

let app = NSApplication.shared // Required to receive NSWorkspace notifications in a CLI
let watcher = SleepWatcher()
RunLoop.main.run()
