using System;
using System.Threading;
using Microsoft.Win32;

class WinSleepWatcher {
    static ManualResetEvent migrationDoneEvent = new ManualResetEvent(false);

    static void Main() {
        SystemEvents.PowerModeChanged += OnPowerChange;
        
        Console.WriteLine("READY");
        Console.Out.Flush();

        // Start a thread to read standard input
        Thread readerThread = new Thread(() => {
            while (true) {
                string line = Console.ReadLine();
                if (line == null) break; // EOF
                if (line.Trim() == "MIGRATION_DONE") {
                    migrationDoneEvent.Set();
                }
            }
        });
        readerThread.IsBackground = true;
        readerThread.Start();

        // Keep main thread alive
        Thread.Sleep(Timeout.Infinite);
    }

    static void OnPowerChange(object s, PowerModeChangedEventArgs e) {
        if (e.Mode == PowerModes.Suspend) {
            Console.WriteLine("SLEEP_DETECTED");
            Console.Out.Flush();
            
            // Block until migration done or 25s timeout
            bool done = migrationDoneEvent.WaitOne(25000);
            if (done) {
                Console.WriteLine("ACK_SLEEP");
            } else {
                Console.WriteLine("TIMEOUT_SLEEP");
            }
            Console.Out.Flush();
            migrationDoneEvent.Reset();
        }
    }
}
