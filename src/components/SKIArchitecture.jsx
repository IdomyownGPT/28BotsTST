/**
 * SKI Architecture Visualization
 * Interactive React component showing the full system topology.
 *
 * Updated 2026-04-04:
 * - Model strategy: Bonsai Prism 8B (2x instances) replaces multiple large LLMs
 * - Port fix: DeerFlow Frontend moved from 3000 to 3100 (conflict with OpenClaw)
 */
import { useState } from "react";

const COLORS = {
  host: "#0f172a", vm: "#1e1b4b", docker: "#0c1a2e", vault: "#064e3b",
  lm: "#7c2d12", hermes: "#4a1d96", openclaw: "#0e4d6e", deerflow: "#1e3a5f",
  agentZero: "#3b1f00", user: "#1a1a2e", conn: "#38bdf8", connSMB: "#34d399",
  connAPI: "#f59e0b", connTelegram: "#60a5fa", text: "#e2e8f0", muted: "#94a3b8",
  accent: "#38bdf8", green: "#4ade80", yellow: "#fbbf24", red: "#f87171",
  purple: "#a78bfa",
};

const Badge = ({ color, children }) => (
  <span style={{
    background: color + "33", border: `1px solid ${color}66`, color,
    borderRadius: 4, padding: "1px 6px", fontSize: 10,
    fontFamily: "monospace", fontWeight: 700, letterSpacing: 0.5,
  }}>{children}</span>
);

const Port = ({ n, color = COLORS.accent }) => <Badge color={color}>:{n}</Badge>;

const Row = ({ children, gap = 8 }) => (
  <div style={{ display: "flex", gap, alignItems: "center", flexWrap: "wrap" }}>{children}</div>
);

const Box = ({ title, subtitle, badge, color, children, width, minWidth = 180, style = {} }) => (
  <div style={{
    background: color + "22", border: `1.5px solid ${color}55`, borderRadius: 10,
    padding: "12px 14px", width, minWidth, boxShadow: `0 0 20px ${color}15`, ...style,
  }}>
    <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
      <div style={{ width: 8, height: 8, borderRadius: "50%", background: color, boxShadow: `0 0 6px ${color}` }} />
      <span style={{ color, fontWeight: 800, fontSize: 13, letterSpacing: 0.3 }}>{title}</span>
      {badge && <Badge color={color}>{badge}</Badge>}
    </div>
    {subtitle && <div style={{ color: COLORS.muted, fontSize: 11, marginBottom: 8 }}>{subtitle}</div>}
    {children}
  </div>
);

const Item = ({ label, value, color = COLORS.muted, icon }) => (
  <div style={{ display: "flex", gap: 6, alignItems: "flex-start", marginBottom: 3 }}>
    <span style={{ color: COLORS.muted, fontSize: 11 }}>{icon || "\u00b7"}</span>
    <span style={{ color: COLORS.muted, fontSize: 11 }}>{label}</span>
    {value && <span style={{ color, fontSize: 11, fontFamily: "monospace" }}>{value}</span>}
  </div>
);

const ConnLine = ({ from, to, label, color = COLORS.conn, style = {} }) => (
  <div style={{
    display: "flex", alignItems: "center", gap: 8, padding: "4px 10px",
    background: color + "11", border: `1px solid ${color}33`, borderRadius: 6, ...style,
  }}>
    <span style={{ color, fontFamily: "monospace", fontSize: 11, fontWeight: 700 }}>{from}</span>
    <span style={{ color, fontSize: 16 }}>{"\u2192"}</span>
    <span style={{ color, fontFamily: "monospace", fontSize: 11, fontWeight: 700 }}>{to}</span>
    {label && <span style={{ color: COLORS.muted, fontSize: 10 }}>({label})</span>}
  </div>
);

export default function SKIArchitecture() {
  const [activeLayer, setActiveLayer] = useState(null);

  const layers = [
    { id: "user", label: "User / Marvin" },
    { id: "host", label: "Windows Server 2025" },
    { id: "vm", label: "Ubuntu VM" },
    { id: "vault", label: "Vault / Storage" },
    { id: "flows", label: "Data Flows" },
  ];

  const show = (id) => !activeLayer || activeLayer === id;

  return (
    <div style={{
      background: "#060b14", minHeight: "100vh",
      fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
      color: COLORS.text, padding: 24,
    }}>
      {/* Header */}
      <div style={{ marginBottom: 24, borderBottom: "1px solid #ffffff11", paddingBottom: 16 }}>
        <div style={{ display: "flex", alignItems: "baseline", gap: 16, flexWrap: "wrap" }}>
          <h1 style={{
            margin: 0, fontSize: 22, fontWeight: 900,
            background: "linear-gradient(135deg, #38bdf8, #a78bfa, #34d399)",
            WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent",
            letterSpacing: -0.5,
          }}>SKI — Sephirotische Kernintelligenz</h1>
          <Badge color="#38bdf8">v2.0</Badge>
          <Badge color="#4ade80">28Bots</Badge>
          <Badge color="#fbbf24">2026-04-04</Badge>
        </div>
        <p style={{ margin: "6px 0 0", color: COLORS.muted, fontSize: 12 }}>
          System Architecture | Components | Connections | Data Flows
        </p>
      </div>

      {/* Layer Filter */}
      <div style={{ display: "flex", gap: 8, marginBottom: 20, flexWrap: "wrap" }}>
        <span style={{ color: COLORS.muted, fontSize: 11, lineHeight: "26px" }}>Filter:</span>
        {layers.map(l => (
          <button key={l.id} onClick={() => setActiveLayer(activeLayer === l.id ? null : l.id)}
            style={{
              background: activeLayer === l.id ? "#38bdf822" : "transparent",
              border: `1px solid ${activeLayer === l.id ? "#38bdf8" : "#ffffff22"}`,
              color: activeLayer === l.id ? "#38bdf8" : COLORS.muted,
              borderRadius: 6, padding: "3px 10px", fontSize: 11, cursor: "pointer",
            }}>{l.label}</button>
        ))}
      </div>

      {/* Main Grid */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 16 }}>

        {/* COL 1: USER + HOST */}
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {show("user") && (
            <Box title="Marvin (User)" color="#60a5fa" badge="ADMIN">
              <Item label="Role" value="God & Creator" color="#60a5fa" icon="&#128100;" />
              <Item label="Interface" value="Telegram @MegamarphBot" color="#60a5fa" icon="&#128241;" />
              <Item label="Interface" value="Obsidian Vault UI" color="#60a5fa" icon="&#128211;" />
              <Item label="Interface" value="Browser :2026" color="#60a5fa" icon="&#127760;" />
              <Item label="Interface" value="SSH -> archat@VM" color="#60a5fa" icon="&#128272;" />
              <Item label="Interface" value="LM Studio GUI" color="#60a5fa" icon="&#128421;" />
              <div style={{ marginTop: 8, padding: "6px 8px", background: "#60a5fa11", borderRadius: 6 }}>
                <div style={{ color: "#60a5fa", fontSize: 10, marginBottom: 4 }}>PERMISSIONS</div>
                <Item label="Host Admin" value="Y" color={COLORS.green} icon="&#8226;" />
                <Item label="VM sudo" value="Y" color={COLORS.green} icon="&#8226;" />
                <Item label="Vault RW" value="Y" color={COLORS.green} icon="&#8226;" />
                <Item label="Docker" value="Y" color={COLORS.green} icon="&#8226;" />
              </div>
            </Box>
          )}

          {show("host") && (
            <Box title="Windows Server 2025" subtitle="192.168.178.90 (static)" color={COLORS.lm} badge="HOST">
              <Item label="CPU" value="AMD 12-Core" icon="&#9881;" />
              <Item label="RAM" value="64 GB" icon="&#128190;" />
              <Item label="GPU" value="RTX 3060 | 12GB VRAM" color="#f59e0b" icon="&#127918;" />
              <Item label="NVMe" value="1.5TB | ~30GB/s Cache" icon="&#9889;" />
              <Item label="NAS" value="12TB | 1Gbit" icon="&#128452;" />
              <div style={{ marginTop: 10, borderTop: "1px solid #ffffff11", paddingTop: 8 }}>
                <div style={{ color: COLORS.lm, fontSize: 10, marginBottom: 6 }}>SOFTWARE</div>
                <div style={{ background: "#7c2d1222", border: "1px solid #7c2d1244", borderRadius: 6, padding: 8, marginBottom: 6 }}>
                  <Row>
                    <span style={{ color: "#f97316", fontSize: 12, fontWeight: 800 }}>LM Studio</span>
                    <Port n="1234" color="#f97316" />
                    <Badge color="#4ade80">active</Badge>
                  </Row>
                  <Item label="Model" value="Bonsai Prism 8B (normal)" color="#fbbf24" icon="&#9733;" />
                  <Item label="Model" value="Bonsai Prism 8B (Symbolect)" color="#fbbf24" icon="&#9733;" />
                  <Item label="Embed" value="nomic-embed-text" color="#fbbf24" icon="&#9733;" />
                  <Item label="GPU" value="CUDA | RTX 3060" color="#f97316" icon="&#9889;" />
                  <Item label="API" value="/v1/ + /api/v1/" color="#f97316" icon="&#128268;" />
                  <Item label="VRAM" value="~4.5 GB / 12 GB" color="#4ade80" icon="&#128202;" />
                </div>
                <div style={{ background: "#06644422", border: "1px solid #06644444", borderRadius: 6, padding: 8 }}>
                  <Row>
                    <span style={{ color: "#34d399", fontSize: 12, fontWeight: 800 }}>Obsidian</span>
                    <Badge color="#34d399">Vault UI</Badge>
                  </Row>
                  <Item label="Vault" value="D:\28Bots_Core\Obsidian_Vault\root\" color="#34d399" icon="&#128193;" />
                  <Item label="SMB" value="\\192.168.178.90\SKI-Vault-Root" color="#34d399" icon="&#128279;" />
                </div>
              </div>
            </Box>
          )}
        </div>

        {/* COL 2: VM + DOCKER */}
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {show("vm") && (
            <Box title="28Bots-Orchestrator-GUI" subtitle="192.168.178.124 | archat | Ubuntu 24.04" color="#7c3aed" badge="HYPER-V VM">
              <Item label="CPU" value="AMD Ryzen 9 5900X x4" icon="&#9881;" />
              <Item label="RAM" value="9 GB (16GB recommended)" icon="&#128190;" />
              <Item label="GPU" value="Software Rendering (no CUDA)" color={COLORS.red} icon="&#10060;" />
              <Item label="Disk" value="107 GB | 62GB free" icon="&#128191;" />
              <Item label="Docker" value="v29.3.1" color={COLORS.green} icon="&#128051;" />
              <Item label="Hermes" value="v0.7.0 | 9 Profiles" color={COLORS.green} icon="&#129504;" />
              <div style={{ marginTop: 8, background: "#7c3aed11", borderRadius: 6, padding: 8 }}>
                <div style={{ color: "#a78bfa", fontSize: 10, marginBottom: 4 }}>VAULT MOUNT</div>
                <Item label="local" value="/mnt/28bots_core/Obsidian_Vault/" color="#34d399" icon="&#128193;" />
                <Item label="fstab" value="_netdev | cifs | vers=3.0" color={COLORS.muted} icon="&#9881;" />
                <Item label="NOTE" value="Check mount after reboot!" color={COLORS.yellow} icon="&#9888;" />
              </div>
              <div style={{ marginTop: 8, background: "#7c3aed11", borderRadius: 6, padding: 8 }}>
                <div style={{ color: "#a78bfa", fontSize: 10, marginBottom: 4 }}>HERMES PROFILES (9x)</div>
                {[
                  ["kether-alpha", "Generation"],
                  ["kether-beta", "Orchestration"],
                  ["kether-gamma", "Execution"],
                  ["tiferet-alpha", "Generation"],
                  ["tiferet-beta *", "DEFAULT"],
                  ["tiferet-gamma", "Execution"],
                  ["malkuth-alpha", "Generation"],
                  ["malkuth-beta", "Orchestration"],
                  ["malkuth-gamma", "Execution"],
                ].map(([p, r]) => (
                  <div key={p} style={{ display: "flex", justifyContent: "space-between", fontSize: 10, color: p.includes("*") ? "#fbbf24" : COLORS.muted }}>
                    <span>{p}</span><span style={{ color: "#a78bfa88" }}>{r}</span>
                  </div>
                ))}
              </div>
            </Box>
          )}

          {show("vm") && (
            <Box title="Docker Containers" color="#0ea5e9" badge="8 Containers">
              {[
                { name: "DeerFlow", color: "#38bdf8", port: "2026", ok: true, desc: "Super-Agent | LangGraph" },
                { name: "|- langgraph", color: "#7dd3fc", port: "2024", ok: true, desc: "Agent Engine | 10 Workers" },
                { name: "|- gateway", color: "#7dd3fc", port: "8001", ok: false, desc: "Config issue" },
                { name: "|- frontend", color: "#7dd3fc", port: "3100", ok: true, desc: "Next.js (moved from 3000)" },
                { name: "|- nginx", color: "#7dd3fc", port: "2026", ok: true, desc: "Reverse Proxy" },
                { name: "OpenClaw", color: "#34d399", port: "3000", ok: true, desc: "Tool-Gateway | Telegram" },
                { name: "Hermes", color: "#a78bfa", port: null, ok: true, desc: "Memory/Learning" },
                { name: "Agent Zero", color: "#fb923c", port: "8080", ok: true, desc: "Task Hierarchy" },
                { name: "Milvus VDB", color: "#f472b6", port: "19530", ok: true, desc: "Vector DB" },
              ].map(c => (
                <div key={c.name} style={{
                  display: "flex", alignItems: "center", gap: 6,
                  padding: "3px 0", borderBottom: "1px solid #ffffff08",
                }}>
                  <span style={{ fontSize: 10 }}>{c.ok ? "\u2705" : "\u26a0\ufe0f"}</span>
                  <span style={{ color: c.color, fontSize: 11, fontWeight: 700, minWidth: 110 }}>{c.name}</span>
                  {c.port && <Port n={c.port} color={c.color} />}
                  <span style={{ color: COLORS.muted, fontSize: 10 }}>{c.desc}</span>
                </div>
              ))}
            </Box>
          )}
        </div>

        {/* COL 3: VAULT + FLOWS */}
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {show("vault") && (
            <Box title="Obsidian Vault" subtitle="D:\28Bots_Core\Obsidian_Vault\root\" color={COLORS.vault} badge="SMB SHARE">
              <Item label="Host" value="D:\...\root\" color="#34d399" icon="&#127968;" />
              <Item label="VM" value="/mnt/28bots_core/Obsidian_Vault/" color="#34d399" icon="&#128039;" />
              <Item label="Container" value="/mnt/ski-vault/" color="#34d399" icon="&#128051;" />
              <div style={{ marginTop: 8, fontFamily: "monospace", fontSize: 10 }}>
                {[
                  ["SKI_Cookbook/", "#34d399"],
                  ["  M00/ ... M11/", COLORS.muted],
                  ["SKI_Bootstrap/", "#34d399"],
                  ["  TROUBLESHOOTING.md", COLORS.muted],
                  ["SKI_Pilot/", "#fbbf24"],
                  ["  SOUL.md", "#fbbf24"],
                  ["  SKI_PILOT_Overview.md", "#fbbf24"],
                ].map(([p, c]) => (
                  <div key={p} style={{ color: c, marginBottom: 1 }}>{p}</div>
                ))}
              </div>
            </Box>
          )}

          {show("flows") && (
            <Box title="Connections & Data Flows" color="#f59e0b">
              <div style={{ marginBottom: 8 }}>
                <div style={{ color: "#f59e0b", fontSize: 10, marginBottom: 6 }}>INFERENCE (API)</div>
                <ConnLine from="VM/Container" to="LM Studio :1234" label="OpenAI-compat /v1/" color="#f59e0b" />
                <div style={{ height: 4 }} />
                <ConnLine from="Hermes" to="Bonsai Prism 8B" label="via LM Studio" color="#a78bfa" />
                <div style={{ height: 4 }} />
                <ConnLine from="DeerFlow" to="Bonsai Prism 8B" label="via LM Studio" color="#38bdf8" />
              </div>
              <div style={{ marginBottom: 8 }}>
                <div style={{ color: "#34d399", fontSize: 10, marginBottom: 6 }}>VAULT (SMB/CIFS)</div>
                <ConnLine from="Host" to="VM" label="\SKI-Vault-Root" color="#34d399" />
                <div style={{ height: 4 }} />
                <ConnLine from="VM" to="Container" label="/mnt/ski-vault" color="#34d399" />
              </div>
              <div style={{ marginBottom: 8 }}>
                <div style={{ color: "#60a5fa", fontSize: 10, marginBottom: 6 }}>TELEGRAM</div>
                <ConnLine from="@MegamarphBot" to="OpenClaw :3000" label="Bot Token" color="#60a5fa" />
              </div>
              <div>
                <div style={{ color: "#fb923c", fontSize: 10, marginBottom: 6 }}>OPEN ITEMS</div>
                {[
                  ["DeerFlow Gateway", "Config fix pending", COLORS.yellow],
                  ["Telegram->DeerFlow", "Not yet connected", COLORS.yellow],
                  ["Symbolect Training", "M03 pending", COLORS.muted],
                  ["GPU Training", "WSL2 (M05/M06)", COLORS.muted],
                ].map(([item, note, color]) => (
                  <div key={item} style={{ display: "flex", justifyContent: "space-between", fontSize: 10, marginBottom: 3 }}>
                    <span style={{ color }}>{item}</span>
                    <span style={{ color: COLORS.muted }}>{note}</span>
                  </div>
                ))}
              </div>
            </Box>
          )}

          {show("vm") && (
            <Box title="3x3 Harness Matrix" color="#a78bfa" badge="PRISM">
              <div style={{ fontSize: 10, color: COLORS.muted, marginBottom: 8 }}>
                Row = Sephirah Level | Column = Role
              </div>
              <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 10 }}>
                <thead>
                  <tr>
                    {["", "a Generation", "b Orchestration *", "g Execution"].map(h => (
                      <th key={h} style={{ color: "#a78bfa", padding: "4px 6px", textAlign: "left", borderBottom: "1px solid #a78bfa33" }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {[
                    ["Kether", "kether-a", "kether-b", "kether-g"],
                    ["Tiferet", "tiferet-a", "tiferet-b *", "tiferet-g"],
                    ["Malkuth", "malkuth-a", "malkuth-b", "malkuth-g"],
                  ].map((row, i) => (
                    <tr key={i} style={{ background: i === 1 ? "#a78bfa11" : "transparent" }}>
                      {row.map((cell, j) => (
                        <td key={j} style={{
                          padding: "4px 6px",
                          color: cell.includes("*") ? "#fbbf24" : j === 0 ? "#a78bfa" : COLORS.muted,
                          fontWeight: cell.includes("*") ? 800 : 400,
                        }}>{cell}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
              <div style={{ marginTop: 8, fontSize: 10, color: COLORS.muted }}>
                * = Default | Pilot runs on tiferet-beta
              </div>
            </Box>
          )}
        </div>
      </div>

      {/* Status Bar */}
      <div style={{
        marginTop: 20, padding: "10px 16px", background: "#0f172a",
        border: "1px solid #ffffff11", borderRadius: 8,
        display: "flex", gap: 16, flexWrap: "wrap", alignItems: "center",
      }}>
        <span style={{ color: COLORS.muted, fontSize: 11 }}>STATUS:</span>
        {[
          ["LM Studio", "active", "#4ade80"],
          ["DeerFlow UI", "active", "#4ade80"],
          ["DeerFlow Gateway", "config issue", "#fbbf24"],
          ["Hermes 9 Profiles", "active", "#4ade80"],
          ["OpenClaw", "active", "#4ade80"],
          ["Agent Zero", "active", "#4ade80"],
          ["Vault Mount", "active", "#4ade80"],
          ["Telegram", "not connected", "#fbbf24"],
          ["Symbolect", "pending", "#f87171"],
        ].map(([label, status, color]) => (
          <span key={label} style={{ fontSize: 11 }}>
            <span style={{ color }}>{status}</span>{" "}
            <span style={{ color: COLORS.muted }}>{label}</span>
          </span>
        ))}
      </div>

      <div style={{ marginTop: 12, textAlign: "center", color: "#ffffff22", fontSize: 10 }}>
        SKI Architecture v2.0 | 28Bots | 2026-04-04 | Host: 192.168.178.90 | VM: 192.168.178.124
      </div>
    </div>
  );
}
