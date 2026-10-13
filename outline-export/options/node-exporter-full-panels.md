*Copied from `options/node-exporter-full-panels.md` in the ai-server repo; import it as a document named "Option: Node Exporter Full panels".*

Part of Step 9: Monitoring stack (document "Self-Hosted AI Server Setup Guide"). The Grafana dashboard Node Exporter Full (ID `1860`) has about 110 panels in 16 rows. Many stay empty on any server: they need a node-exporter collector that is off by default, or hardware the server does not have. This page lists every panel, what it costs to fill, and whether it is worth keeping.

## Hide or show everything?

Keep the useful rows open, collapse the rest, and turn on only the cheap collectors:

- **Collapsing a row costs nothing.** Grafana runs no queries for a collapsed row until someone opens it. Click a row title to collapse it, then **Save dashboard**. To remove a row completely, hover over it, click the gear, then **Remove**.
- **An empty panel costs nothing either.** It only means the metric is not collected.
- **Turning on a collector has a cost**, mostly in Prometheus disk space (each new metric line is stored every 30 seconds for 30 days) and a little CPU on every scrape. See [What turning on costs](#what-turning-on-costs).

Turning everything on is not worth it: the extra panels mostly matter for network appliances, time servers, and kernel tuning, not for an AI server.

## Why panels are empty

| Mark | Meaning | What to do |
|---|---|---|
| ✅ | Collected and shown | Nothing |
| ➕ | Needs a collector that is off by default | Turn it on if the panel is worth it ([Turning on collectors](#turning-on-collectors)) |
| 🌐 | Shows only the node-exporter container network, not the server network | node-exporter runs on the `edge` network, so it sees only its own container. The panel has numbers, but they are not the server traffic |
| ⛔ | The server has no such hardware or feature | Nothing; the panel stays empty. Collapse or remove it |
| ❔ | Depends on the server hardware | Shows data on some servers, not on others |

## Turning on collectors

The guide already turns on `--collector.processes` (System Processes). The others, in `/opt/stacks/node-exporter/compose.yaml` under `command:`:

| Collector | Fills | Cost | Recommendation |
|---|---|---|---|
| `--collector.processes` | Processes Detailed States, PIDs, Threads | Low: reads every process once per scrape; a few lines | On (already in the guide) |
| `--collector.tcpstat` | TCP Stat Persistent, Transient, Socket Queue | Low to medium: lists every TCP connection per scrape | Optional; shows the container network until node-exporter uses the server network (🌐) |
| `--collector.systemd` | Systemd section | Medium: asks systemd over D-Bus each scrape; about 5 lines per unit (hundreds of units) | Optional; also needs the D-Bus socket mounted (below) |
| `--collector.interrupts` | IRQ Detail | High: one line per CPU core per interrupt, often thousands | Leave off |

For systemd, also add this under `volumes:`; if `docker logs node-exporter` then shows a D-Bus permission error, leave the collector off:
```yaml
      - /run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket:ro
```

Apply with `cd /opt/stacks/node-exporter && docker compose up -d --force-recreate node-exporter`, then reload the dashboard.

## What turning on costs

| Part | Normal load | With every collector on |
|---|---|---|
| node-exporter | about 20–40 MB RAM, well under 1% CPU | a little more CPU per scrape (systemd and interrupts are the slow ones; see the Node Exporter Scrape Time panel) |
| Prometheus | about 1,000–3,000 lines from node-exporter | several thousand more (interrupts and systemd), so more disk within the 5 GB limit and a shorter history if the limit is reached first |
| Grafana | queries only the open rows, at each refresh | the same: collapsed rows still cost nothing |

## Every panel

**Cost** is what the panel adds to collect and store: **Low** comes with node-exporter already, **Medium** or **High** needs a collector turned on. **Show** is a suggestion for an AI server: **Keep** (open), **Optional** (collapsed, open when needed), **Hide** (collapse or remove).

### Quick CPU / Mem / Disk

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Pressure | How often CPU, memory, I/O, and interrupts made tasks wait (Linux PSI) | ✅ | Low | Keep |
| CPU Busy | CPU busy %, all cores together | ✅ | Low | Keep |
| Sys Load | Load per CPU core, as % | ✅ | Low | Keep |
| RAM Used | RAM in real use %, without cache | ✅ | Low | Keep |
| SWAP Used | Swap used % | ✅ | Low | Keep |
| Root FS Used | Space used on `/` | ✅ | Low | Keep |
| CPU Cores | Number of CPU cores | ✅ | Low | Keep |
| RAM Total | Installed RAM | ✅ | Low | Keep |
| SWAP Total | Swap size | ✅ | Low | Keep |
| RootFS Total | Size of `/` | ✅ | Low | Keep |
| Uptime | Time since the last boot | ✅ | Low | Keep |

### Basic CPU / Mem / Net / Disk

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| CPU Basic | CPU time by type: user, system, I/O wait, idle | ✅ | Low | Keep |
| Memory Basic | RAM used, cache, buffers, free, swap | ✅ | Low | Keep |
| Network Traffic Basic | Traffic per network card, in bits/s | 🌐 | Low | Keep |
| Disk Space Used Basic | Space used % per disk | ✅ | Low | Keep |

### CPU / Memory / Net / Disk

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| CPU | CPU time by state, including virtual machine guests | ✅ | Low | Keep |
| Memory | RAM in detail, including hardware memory errors | ✅ | Low | Keep |
| Network Traffic | Traffic in and out per network card | 🌐 | Low | Keep |
| Network Saturation | Traffic as % of the network card speed | 🌐 | Low | Keep |
| Disk IOps | Reads and writes per second per disk | ✅ | Low | Keep |
| Disk Throughput | MB/s read and written per disk | ✅ | Low | Keep |
| Filesystem Space Available | Free space per disk | ✅ | Low | Keep |
| Filesystem Used | Used space per disk | ✅ | Low | Keep |
| Disk I/O Utilization | % of time each disk is busy | ✅ | Low | Keep |
| Pressure Stall Information | CPU, memory, I/O waits over time (partial and full stalls) | ✅ | Low | Keep |

### Memory Meminfo

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Memory Committed | Memory promised to programs vs the limit | ✅ | Low | Optional |
| Memory Writeback and Dirty | Changed data waiting to be written to disk | ✅ | Low | Optional |
| Memory Slab | Kernel cache memory, freeable or not | ✅ | Low | Hide |
| Memory Shared and Mapped | Shared memory and memory-mapped files | ✅ | Low | Hide |
| Memory LRU Active / Inactive (%) | Recently used vs idle memory, as % | ✅ | Low | Hide |
| Memory LRU Active / Inactive Detail | The same, split by program data and file cache | ✅ | Low | Hide |
| Memory Kernel / CPU / IO | Small kernel memory areas | ✅ | Low | Hide |
| Memory Vmalloc | Kernel virtual memory for drivers | ✅ | Low | Hide |
| Memory Anonymous | Program memory not backed by files | ✅ | Low | Hide |
| Memory Unevictable and MLocked | Memory locked in RAM | ✅ | Low | Hide |
| Memory DirectMap | Kernel memory map by page size | ✅ | Low | Hide |
| Memory HugePages | Huge pages; usually 0 unless set up | ✅ | Low | Hide |

### Memory Vmstat

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Memory Pages In / Out | Memory pages read from and written to disk | ✅ | Low | Optional |
| Memory Pages Swap In / Out | Swap activity; high means not enough RAM | ✅ | Low | Keep |
| Memory Page Faults | Page faults; many major faults means memory pressure | ✅ | Low | Optional |
| OOM Killer | Programs killed because memory ran out | ✅ | Low | Keep |

### System Timesync

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Time Synchronized Drift | Clock error and offset from the time server | ✅ | Low | Optional |
| Time PLL Adjust | How fast the kernel corrects the clock | ✅ | Low | Hide |
| Time Synchronized Status | Whether the clock is in sync | ✅ | Low | Optional |
| PPS Frequency / Stability | Precision time signal (GPS clock) | ⛔ | Low | Hide |
| PPS Time Accuracy | Precision time signal jitter | ⛔ | Low | Hide |
| PPS Sync Events | Precision time signal errors | ⛔ | Low | Hide |

### System Processes

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Processes Status | Processes running and blocked | ✅ | Low | Keep |
| Processes Detailed States | Processes by state: running, sleeping, zombie | ➕ processes | Low | Optional |
| Processes Forks | New processes per second | ✅ | Low | Optional |
| CPU Saturation per Core | How long tasks wait for a CPU core | ✅ | Low | Optional |
| PIDs Number and Limit | Process IDs used vs the limit | ➕ processes | Low | Optional |
| Threads Number and Limit | Threads used vs the limit | ➕ processes | Low | Optional |

### System Misc

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Context Switches / Interrupts | Task switches and hardware interrupts per second | ✅ | Low | Optional |
| System Load | Load average over 1, 5, 15 minutes | ✅ | Low | Keep |
| CPU Frequency Scaling | Current CPU speed per core | ❔ | Low | Optional |
| CPU Schedule Timeslices | Scheduler switches per core | ✅ | Low | Hide |
| IRQ Detail | Interrupts by device and core | ➕ interrupts | High | Hide |
| Entropy | Randomness available to the system | ✅ | Low | Hide |

### Hardware Misc

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Hardware Temperature Monitor | CPU, board, and disk temperatures and their limits | ❔ | Low | Keep |
| Cooling Device Utilization | How hard fans and throttling work | ❔ | Low | Optional |
| Power Supply | Power supply online (AC, battery); usually empty on servers | ⛔ | Low | Hide |
| Hardware Fan Speed | Fan speed (RPM); often empty on servers that report fans through IPMI | ❔ | Low | Optional |

### Systemd

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Systemd Units State | Services by state; failed is the one to watch | ➕ systemd | Medium | Optional |
| Systemd Sockets Current | Open connections per systemd socket | ➕ systemd | Medium | Hide |
| Systemd Sockets Accepted | Accepted connections per systemd socket | ➕ systemd | Medium | Hide |
| Systemd Sockets Refused | Refused connections per systemd socket | ➕ systemd | Medium | Hide |

### Storage Disk

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Disk Read/Write IOps | Reads and writes per second per disk | ✅ | Low | Keep |
| Disk Read/Write Data | Bytes read and written per second | ✅ | Low | Keep |
| Disk Average Wait Time | Time a disk request takes; high means a slow or busy disk | ✅ | Low | Keep |
| Average Queue Size | Requests waiting per disk | ✅ | Low | Optional |
| Disk R/W Merged | Requests merged before reaching the disk | ✅ | Low | Hide |
| Time Spent Doing I/Os | % of time busy, including TRIM and cache flushes | ✅ | Low | Optional |
| Disk Ops Discards / Flush | TRIM and cache flush operations (SSD) | ✅ | Low | Hide |
| Disk Sectors Discarded Successfully | Sectors trimmed per second (SSD) | ✅ | Low | Hide |
| Instantaneous Queue Size | Requests in progress at the moment of the scrape | ✅ | Low | Hide |

### Storage Filesystem

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| File Descriptor | Open files on the whole server vs the limit | ✅ | Low | Optional |
| File Nodes Free | Free inodes per disk; at 0 no new files, even with free space | ✅ | Low | Keep |
| Filesystem in ReadOnly / Error | Disks switched to read-only or with errors | ✅ | Low | Keep |
| File Nodes Size | Total inodes per disk | ✅ | Low | Hide |

### Network Traffic

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Network Traffic by Packets | Packets per second per network card | 🌐 | Low | Optional |
| Network Traffic Errors | Packet errors; cable or driver problems | 🌐 | Low | Optional |
| Network Traffic Drop | Dropped packets; overload or buffer limits | 🌐 | Low | Optional |
| Network Traffic Compressed | Compressed packets (old dial-up links) | 🌐 | Low | Hide |
| Network Traffic Multicast | Multicast packets (mDNS, SSDP) | 🌐 | Low | Hide |
| Network Traffic NoHandler | Packets the kernel had no handler for | 🌐 | Low | Hide |
| Network Traffic Frame | Frame errors; cable or duplex problems | 🌐 | Low | Hide |
| Network Traffic Fifo | Buffer overruns on the network card | 🌐 | Low | Hide |
| Network Traffic Collision | Collisions (old half-duplex networks) | 🌐 | Low | Hide |
| Network Traffic Carrier Errors | Link signal errors; cable problems | 🌐 | Low | Hide |
| ARP Entries | Known neighbours on the network | 🌐 | Low | Hide |
| NF Conntrack | Tracked connections vs the limit (Docker uses this) | 🌐 | Low | Optional |
| Network Operational Status | Whether each network card is up and has a link | 🌐 | Low | Optional |
| Speed | Speed of each network card | 🌐 | Low | Optional |
| MTU | Largest packet size per network card | 🌐 | Low | Hide |

### Network Sockstat

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Sockstat TCP | TCP sockets in use, waiting, orphaned | 🌐 | Low | Optional |
| Sockstat UDP | UDP sockets in use | 🌐 | Low | Hide |
| Sockstat Used | All sockets in use | 🌐 | Low | Hide |
| Sockstat FRAG / RAW | Fragment and raw sockets | 🌐 | Low | Hide |
| Sockstat Memory Size | Kernel memory for socket buffers | 🌐 | Low | Hide |
| Sockstat Average Socket Memory | Memory per socket, for tuning | 🌐 | Low | Hide |
| TCP/UDP Kernel Buffer Memory Pages | Socket memory in kernel pages | 🌐 | Low | Hide |
| Softnet Packets | Packets processed and dropped per CPU | ✅ | Low | Hide |
| Softnet Out of Quota | Times the CPU could not keep up with packets | ✅ | Low | Hide |
| Softnet RPS | Packets spread over CPUs (RPS) | ✅ | Low | Hide |

### Network Netstat

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Netstat IP In / Out Octets | IP traffic in and out | 🌐 | Low | Hide |
| TCP In / Out | TCP segments per second | 🌐 | Low | Hide |
| UDP In / Out | UDP datagrams per second | 🌐 | Low | Hide |
| ICMP In / Out | ICMP (ping) messages per second | 🌐 | Low | Hide |
| TCP Errors | Retransmissions, timeouts, dropped connections | 🌐 | Low | Optional |
| UDP Errors | UDP delivery errors | 🌐 | Low | Hide |
| ICMP Errors | Bad ICMP messages | 🌐 | Low | Hide |
| TCP SynCookie | SYN flood protection events | 🌐 | Low | Hide |
| TCP Connections | Open TCP connections | 🌐 | Low | Optional |
| UDP Queue | UDP packets waiting in buffers | 🌐 | Low | Hide |
| TCP Direct Transition | New TCP connections per second, outgoing and incoming | 🌐 | Low | Hide |
| TCP Stat Persistent | TCP connections by state (established, waiting) | ➕ tcpstat 🌐 | Medium | Hide |
| TCP Stat Transient | Short-lived TCP states (opening, closing) | ➕ tcpstat 🌐 | Medium | Hide |
| TCP Socket Queue | Bytes waiting in TCP send and receive queues | ➕ tcpstat 🌐 | Medium | Hide |

### Node Exporter

| Panel | What it shows | Data | Cost | Show |
|---|---|---|---|---|
| Node Exporter Scrape Time | Time each collector takes per scrape | ✅ | Low | Optional |
| Exporter Process CPU Usage | CPU used by node-exporter itself | ✅ | Low | Optional |
| Exporter Processes Memory | Memory used by node-exporter itself | ✅ | Low | Hide |
| Exporter File Descriptor Usage | Open files of node-exporter itself | ✅ | Low | Hide |
| Node Exporter Scrape | Which collectors succeed or fail | ✅ | Low | Optional |

---

**Related:**
- Step 9: Monitoring stack (document "Self-Hosted AI Server Setup Guide") → Usage
