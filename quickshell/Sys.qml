pragma Singleton

// ═══════════════════════════════════════════════════════════════
// CPU and RAM — the two readings with no bus to listen to.
//
// Everything else on this bar is WATCHED: Pipewire, UPower, BlueZ and
// NetworkManager all push. These two do not exist as events anywhere,
// so they are the only polled numbers in the shell, and the poll is
// two FileView reloads -- no fork, no subprocess, no script.
//
// sysinfo.sh is NOT reused here, and that is deliberate rather than
// lazy: it is a waybar module that emits ANIMATION FRAMES (the drawer
// tween is literally made of monospace spaces, with the numbers as
// Pango markup). It emits a picture of a readout, not a readout.
//
// RAM reads in PERCENT. Settled and not reopening: 9.2G was a
// different unit sitting in a column of percentages.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property int cpu: 0
    property int ram: 0

    // 2 s. Fast enough that the number is not stale when you look at
    // it, slow enough that nobody can watch it flicker. A CPU percent
    // that updates every 200 ms is a readout you cannot read.
    readonly property int intervalMs: 2000

    // /proc/stat's first line is cumulative jiffies since boot, so a
    // percentage needs two samples and the difference between them.
    // The first tick therefore reports 0 and the second is the first
    // real number -- which is correct, not a warm-up hack.
    property var _prev: null

    FileView { id: statFile; path: "/proc/stat" }
    FileView { id: memFile; path: "/proc/meminfo" }

    Timer {
        interval: root.intervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            memFile.reload();
            root._readCpu();
            root._readRam();
        }
    }

    function _readCpu() {
        const line = (statFile.text() || "").split("\n")[0];
        if (!line.startsWith("cpu ")) return;
        const f = line.trim().split(/\s+/).slice(1).map(Number);
        // user nice system idle iowait irq softirq steal ...
        // idle is idle + iowait; everything else is work.
        const idle = f[3] + f[4];
        const total = f.reduce((a, b) => a + b, 0);
        if (root._prev) {
            const dt = total - root._prev.total;
            const di = idle - root._prev.idle;
            if (dt > 0) root.cpu = Math.max(0, Math.min(100, Math.round(100 * (dt - di) / dt)));
        }
        root._prev = { total: total, idle: idle };
    }

    function _readRam() {
        const t = memFile.text() || "";
        // MemAvailable is the kernel's own answer to "how much can a
        // new process actually get", which is the number a human means
        // by "used". MemFree is not that -- it excludes reclaimable
        // cache and reads alarmingly low on a healthy machine.
        const total = /MemTotal:\s+(\d+)/.exec(t);
        const avail = /MemAvailable:\s+(\d+)/.exec(t);
        if (!total || !avail) return;
        root.ram = Math.round(100 * (1 - Number(avail[1]) / Number(total[1])));
    }
}
