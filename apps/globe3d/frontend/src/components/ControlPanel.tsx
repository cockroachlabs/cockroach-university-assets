import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import type { RegionConfig, RegionId, DatabaseConfig, SurvivalGoal, TableLocality, TableConfig, ReplicaInfo, ScenarioPreset, FeatureToggles } from '../types'
import type { TopologyData } from '../hooks/useClusterSync'
import { LATENCIES, SCENARIO_PRESETS } from '../types'

function getTeachingContent(survivalGoal: SurvivalGoal, tableLocality: TableLocality): {
  title: string
  explanation: string
  replicaPattern: string
  sqlHint: string
} {
  if (survivalGoal === 'zone' && tableLocality === 'regional-by-table') {
    return {
      title: 'Zone Failure Survival',
      explanation:
        'RF=3. All 3 voting replicas in the primary region (one per node). Other regions get non-voting replicas for follower reads. If the primary region fails, the cluster loses quorum — this is the trade-off for low write latency.',
      replicaPattern: 'Primary: 1 LH + 2V | Others: 1 NV each',
      sqlHint: 'ALTER DATABASE db SURVIVE ZONE FAILURE;',
    }
  }
  if (survivalGoal === 'zone' && tableLocality === 'regional-by-row') {
    return {
      title: 'Zone Failure + Row-Level Homing',
      explanation:
        'Each region is home to its own rows. 3 voting replicas per row in the home region. Non-voting replicas in other regions enable follower reads. Row-level leaseholders give every region fast local writes for its own data.',
      replicaPattern: 'Each region: 1 LH + 2V for its rows | Others: 1 NV',
      sqlHint: 'ALTER TABLE t SET LOCALITY REGIONAL BY ROW;',
    }
  }
  if (survivalGoal === 'zone' && tableLocality === 'global') {
    return {
      title: 'Zone Failure + Global Table',
      explanation:
        'All replicas are voting (1 per region). Uses CockroachDB\'s non-blocking transaction protocol — reads are fast from ANY region without going to the leaseholder. Writes are slower due to cross-region consensus.',
      replicaPattern: 'Each region: 1V (all voting) | Primary has LH',
      sqlHint: 'ALTER TABLE t SET LOCALITY GLOBAL;',
    }
  }
  if (survivalGoal === 'region' && tableLocality === 'regional-by-table') {
    return {
      title: 'Region Failure Survival',
      explanation:
        'RF=5, spread 2-2-1 across 3 regions. The cluster can lose an entire region and still maintain quorum (3/5 voters alive). Write latency increases because consensus requires cross-region round-trips.',
      replicaPattern: 'Primary: 1 LH + 1V | 2nd region: 2V | 3rd region: 1V',
      sqlHint: 'ALTER DATABASE db SURVIVE REGION FAILURE;',
    }
  }
  if (survivalGoal === 'region' && tableLocality === 'regional-by-row') {
    return {
      title: 'Region Failure + Row-Level Homing',
      explanation:
        'RF=5 per row, spread 2-2-1. Each region\'s rows have a local leaseholder with 5 voting replicas spread across regions. If a region fails, its rows\' leaseholders migrate to another region.',
      replicaPattern: 'Home: 1 LH + 1V | Others: 2V + 1V (spread)',
      sqlHint: 'ALTER TABLE t SET LOCALITY REGIONAL BY ROW;',
    }
  }
  // region + global
  return {
    title: 'Region Failure + Global Table',
    explanation:
      'Same as Zone + Global: 1 voting replica per region, non-blocking reads everywhere. Region survival doesn\'t change global table behavior — it\'s already resilient by design.',
    replicaPattern: 'Each region: 1V (all voting) | Primary has LH',
    sqlHint: 'ALTER TABLE t SET LOCALITY GLOBAL;',
  }
}

type NodeSlot = 'LH' | 'V' | 'NV' | 'empty'

function getReplicaDistribution(
  survivalGoal: SurvivalGoal,
  tableLocality: TableLocality
): { primary: NodeSlot[]; second: NodeSlot[]; third: NodeSlot[] } {
  if (survivalGoal === 'zone' && tableLocality === 'regional-by-table') {
    return { primary: ['LH', 'V', 'V'], second: ['NV', 'empty', 'empty'], third: ['NV', 'empty', 'empty'] }
  }
  if (survivalGoal === 'zone' && tableLocality === 'regional-by-row') {
    // Each region is home to its own rows — show primary's perspective
    return { primary: ['LH', 'V', 'V'], second: ['NV', 'empty', 'empty'], third: ['NV', 'empty', 'empty'] }
  }
  if (survivalGoal === 'zone' && tableLocality === 'global') {
    return { primary: ['LH', 'empty', 'empty'], second: ['V', 'empty', 'empty'], third: ['V', 'empty', 'empty'] }
  }
  if (survivalGoal === 'region' && tableLocality === 'regional-by-table') {
    return { primary: ['LH', 'V', 'empty'], second: ['V', 'V', 'empty'], third: ['V', 'empty', 'empty'] }
  }
  if (survivalGoal === 'region' && tableLocality === 'regional-by-row') {
    return { primary: ['LH', 'V', 'empty'], second: ['V', 'V', 'empty'], third: ['V', 'empty', 'empty'] }
  }
  // region + global
  return { primary: ['LH', 'empty', 'empty'], second: ['V', 'empty', 'empty'], third: ['V', 'empty', 'empty'] }
}

function NodeDot({ slot, failed }: { slot: NodeSlot; failed: boolean }) {
  if (failed) {
    return (
      <div className="flex items-center gap-1">
        <div className="w-4 h-4 rounded-full bg-red-500/20 border border-red-500/40 flex items-center justify-center">
          <span className="text-[7px] text-red-400 font-bold">✕</span>
        </div>
        <span className="text-[7px] text-red-400/50 font-mono">--</span>
      </div>
    )
  }

  const styles: Record<NodeSlot, { bg: string; border: string; text: string; label: string }> = {
    LH: { bg: 'bg-amber-400/30', border: 'border-amber-400/60', text: 'text-amber-300', label: 'LH' },
    V: { bg: 'bg-blue-400/25', border: 'border-blue-400/50', text: 'text-blue-300', label: 'V' },
    NV: { bg: 'bg-white/8', border: 'border-white/15', text: 'text-white/30', label: 'NV' },
    empty: { bg: 'bg-white/3', border: 'border-white/8', text: 'text-white/15', label: '·' },
  }

  const s = styles[slot]
  return (
    <div className="flex items-center gap-1">
      <div className={`w-4 h-4 rounded-full ${s.bg} border ${s.border} flex items-center justify-center`}>
        <span className={`text-[6px] font-bold ${s.text}`}>{s.label}</span>
      </div>
      <span className={`text-[7px] font-mono ${s.text}`}>{s.label}</span>
    </div>
  )
}

function ReplicaDistributionDiagram({
  dbConfig,
  tableConfig,
  regions,
  failedRegions,
}: {
  dbConfig: DatabaseConfig
  tableConfig: TableConfig
  regions: RegionConfig[]
  failedRegions: Set<RegionId>
}) {
  const dist = getReplicaDistribution(dbConfig.survivalGoal, tableConfig.locality)
  const dbRegions = dbConfig.regions
  const primaryIdx = dbRegions.indexOf(dbConfig.primaryRegion)

  // Order: primary first, then the others in DB order
  const ordered = [
    dbRegions[primaryIdx],
    ...dbRegions.filter((_, i) => i !== primaryIdx),
  ]

  const slotsByRegion: Record<string, NodeSlot[]> = {}
  slotsByRegion[ordered[0]] = dist.primary
  if (ordered[1]) slotsByRegion[ordered[1]] = dist.second
  if (ordered[2]) slotsByRegion[ordered[2]] = dist.third

  const hasNV = (slots: NodeSlot[]) => slots.some(s => s === 'NV')

  // For regional-by-row, show note
  const isRegionalByRow = tableConfig.locality === 'regional-by-row'

  return (
    <div>
      <SectionHeader>Replica Distribution</SectionHeader>
      <div className="p-3 rounded-lg border border-crdb-border bg-crdb-card/40">
        {isRegionalByRow && (
          <div className="text-[8px] text-white/30 mb-2 italic">
            Showing replica layout for rows homed in {regions.find(r => r.id === dbConfig.primaryRegion)?.label ?? 'primary'}
          </div>
        )}
        <div className="grid gap-2" style={{ gridTemplateColumns: `repeat(${ordered.length}, 1fr)` }}>
          {ordered.map(rid => {
            const region = regions.find(r => r.id === rid)!
            const failed = failedRegions.has(rid)
            const slots = slotsByRegion[rid] ?? ['empty', 'empty', 'empty']
            const isPrimary = rid === dbConfig.primaryRegion

            return (
              <div
                key={rid}
                className={`relative flex flex-col items-center gap-1 p-2 rounded-lg border ${
                  failed
                    ? 'border-red-500/30 bg-red-500/5 opacity-60'
                    : 'border-white/5 bg-white/[0.02]'
                }`}
              >
                {/* Region label */}
                <div className="text-[9px] font-bold mb-1 text-center" style={{ color: failed ? '#EF4444' : region.color }}>
                  {region.label.split('-').slice(0, 2).join('-')}
                </div>

                {/* Node slots */}
                <div className="flex flex-col gap-1">
                  {slots.map((slot, i) => (
                    <NodeDot key={i} slot={slot} failed={failed} />
                  ))}
                </div>

                {/* Role label */}
                <div className="text-[7px] font-bold mt-1 tracking-wider uppercase" style={{ color: failed ? '#EF444480' : isPrimary ? region.color : 'rgba(255,255,255,0.25)' }}>
                  {isPrimary ? 'Primary' : hasNV(slots) ? 'Follower' : 'Voter'}
                </div>

                {/* Follower read indicator */}
                {!failed && hasNV(slots) && (
                  <div className="text-[7px] text-purple-400/70 mt-0.5 flex items-center gap-0.5">
                    <span>📖</span>
                    <span className="font-medium">Follower Reads</span>
                  </div>
                )}
              </div>
            )
          })}
        </div>

        {/* Legend */}
        <div className="flex items-center gap-3 mt-2 pt-2 border-t border-white/5">
          {[
            { label: 'LH', desc: 'Leaseholder', color: 'text-amber-300' },
            { label: 'V', desc: 'Voting', color: 'text-blue-300' },
            { label: 'NV', desc: 'Non-voting', color: 'text-white/30' },
          ].map(item => (
            <div key={item.label} className="flex items-center gap-1">
              <span className={`text-[7px] font-bold ${item.color}`}>{item.label}</span>
              <span className="text-[7px] text-white/20">{item.desc}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

function SectionHeader({ children }: { children: React.ReactNode }) {
  return (
    <h3 className="text-[10px] font-bold uppercase tracking-widest text-white/30 mb-2">
      {children}
    </h3>
  )
}

function RegionCard({
  region,
  isFailed,
  isInDb,
  isPrimary,
  onToggleFail,
  onSetPrimary,
  onAddToDb,
  onRemoveFromDb,
  hasDb,
  failedNodes,
  replicas,
  topology,
  onToggleNodeFail,
}: {
  region: RegionConfig
  isFailed: boolean
  isInDb: boolean
  isPrimary: boolean
  onToggleFail: () => void
  onSetPrimary: () => void
  onAddToDb: () => void
  onRemoveFromDb: () => void
  hasDb: boolean
  failedNodes: Set<string>
  replicas: ReplicaInfo[]
  topology: TopologyData | null
  onToggleNodeFail: (nodeIndex: number) => void
}) {
  return (
    <div
      className={`p-3 rounded-lg border transition-all ${
        isFailed
          ? 'border-red-500/40 bg-red-500/5 opacity-50'
          : 'border-crdb-border bg-crdb-card/40'
      }`}
    >
      <div className="flex items-center gap-2 mb-2">
        <div
          className="w-2.5 h-2.5 rounded-full"
          style={{ backgroundColor: isFailed ? '#EF4444' : region.color }}
        />
        <span className="text-xs font-bold" style={{ color: isFailed ? '#EF4444' : region.color }}>
          {region.label}
        </span>
        <span className="text-[9px] text-white/30 font-mono ml-auto">{region.city}</span>
      </div>

      <div className="text-[10px] text-white/50 mb-2">
        {region.nodes} nodes
        {isPrimary && (
          <span
            className="ml-2 px-1.5 py-0.5 rounded text-[8px] font-bold"
            style={{ backgroundColor: region.color + '20', color: region.color }}
          >
            PRIMARY
          </span>
        )}
      </div>

      {/* Individual Nodes with Replica Roles */}
      <div className="mt-2 mb-2">
        <div className="text-[8px] text-white/30 uppercase tracking-wider mb-1.5">Nodes</div>
        <div className="space-y-1">
          {Array.from({ length: region.nodes }, (_, i) => {
            const nodeKey = `${region.id}:${i}`
            const nodeFailed = isFailed || failedNodes.has(nodeKey)
            const nodeReplicas = replicas.filter(r => r.regionId === region.id && r.nodeIndex === i)
            const isLH = nodeReplicas.some(r => r.isLeaseholder)
            const isV = nodeReplicas.some(r => r.isVoting && !r.isLeaseholder)
            const isNV = nodeReplicas.some(r => !r.isVoting)
            const hasReplica = nodeReplicas.length > 0

            return (
              <div
                key={i}
                className={`flex items-center gap-2 px-2 py-1.5 rounded-lg border transition-all ${
                  nodeFailed
                    ? 'border-red-500/20 bg-red-500/5 opacity-50'
                    : hasReplica
                      ? 'border-white/5 bg-white/[0.02]'
                      : 'border-transparent bg-transparent'
                }`}
              >
                {/* Node status indicator */}
                <div className={`w-4 h-4 rounded-full border flex items-center justify-center flex-shrink-0 ${
                  nodeFailed
                    ? 'bg-red-500/20 border-red-500/40'
                    : isLH
                      ? 'bg-amber-400/30 border-amber-400/60 shadow-[0_0_6px_rgba(251,191,36,0.3)]'
                      : isV
                        ? 'bg-blue-400/25 border-blue-400/50'
                        : isNV
                          ? 'bg-purple-400/20 border-purple-400/40'
                          : 'bg-white/3 border-white/8'
                }`}>
                  {nodeFailed ? (
                    <span className="text-[7px] text-red-400 font-bold">✕</span>
                  ) : isLH ? (
                    <span className="text-[6px] font-bold text-amber-300">LH</span>
                  ) : isV ? (
                    <span className="text-[6px] font-bold text-blue-300">V</span>
                  ) : isNV ? (
                    <span className="text-[6px] font-bold text-purple-300">NV</span>
                  ) : (
                    <span className="text-[6px] text-white/15">-</span>
                  )}
                </div>

                {/* Node info */}
                <div className="flex-1 min-w-0">
                  <div className={`text-[9px] font-mono leading-tight ${
                    nodeFailed ? 'text-red-400/60' : 'text-white/60'
                  }`}>
                    n{i}
                    {nodeFailed && <span className="text-red-400 ml-1">(down)</span>}
                  </div>
                  {!nodeFailed && hasReplica && (
                    <div className="text-[7px] leading-tight mt-0.5">
                      {isLH && (
                        <span className="text-amber-300/80">Leaseholder</span>
                      )}
                      {isV && (
                        <span className="text-blue-300/70">Voting Replica</span>
                      )}
                      {isNV && (
                        <span className="text-purple-300/60">Non-Voting (Follower Reads)</span>
                      )}
                    </div>
                  )}
                  {!nodeFailed && !hasReplica && (
                    <div className="text-[7px] text-white/15 leading-tight mt-0.5">No replica</div>
                  )}
                  {/* Per-node metrics from topology (when available) */}
                  {!nodeFailed && topology?.nodes && (() => {
                    const regionNodes = topology.nodes.filter((tn: { locality: string }) => {
                      const r = tn.locality.split(',').find((p: string) => p.trim().startsWith('region='))?.split('=')[1]
                      return r && (r === region.id || r === region.id.replace(/-/g, ''))
                    })
                    const tNode = regionNodes[i]
                    if (!tNode || (!(tNode.rangeCount ?? 0) && !(tNode.leaseCount ?? 0))) return null
                    return (
                      <div className="flex gap-2 mt-0.5">
                        {(tNode.rangeCount ?? 0) > 0 && (
                          <span className="text-[7px] text-white/25" title="Range count">{tNode.rangeCount}R</span>
                        )}
                        {(tNode.leaseCount ?? 0) > 0 && (
                          <span className="text-[7px] text-amber-300/40" title="Lease count">{tNode.leaseCount}L</span>
                        )}
                        {(tNode.memoryUsageMB ?? 0) > 0 && (
                          <span className="text-[7px] text-blue-300/30" title="Memory usage">{tNode.memoryUsageMB}MB</span>
                        )}
                      </div>
                    )
                  })()}
                </div>

                {/* Kill/Restore button */}
                {!isFailed && (
                  <button
                    className={`text-[8px] px-1.5 py-0.5 rounded transition-colors flex-shrink-0 ${
                      failedNodes.has(nodeKey)
                        ? 'bg-emerald-500/15 text-emerald-400 hover:bg-emerald-500/25'
                        : 'bg-red-500/10 text-red-400/50 hover:bg-red-500/20 hover:text-red-400'
                    }`}
                    onClick={() => onToggleNodeFail(i)}
                  >
                    {failedNodes.has(nodeKey) ? 'Restore' : 'Kill'}
                  </button>
                )}
              </div>
            )
          })}
        </div>
      </div>

      <div className="flex gap-1">
        <button
          className={`flex-1 px-2 py-1 rounded text-[9px] font-medium transition-colors ${
            isFailed
              ? 'bg-emerald-500/15 text-emerald-400 hover:bg-emerald-500/25'
              : 'bg-red-500/10 text-red-400 hover:bg-red-500/20'
          }`}
          onClick={onToggleFail}
        >
          {isFailed ? 'Restore' : 'Kill Region'}
        </button>

        {hasDb && !isFailed && (
          <>
            {isInDb ? (
              <>
                {!isPrimary && (
                  <button
                    className="px-2 py-1 rounded text-[9px] font-medium bg-white/5 text-white/50 hover:bg-white/10 hover:text-white/80 transition-colors"
                    onClick={onSetPrimary}
                  >
                    Set Primary
                  </button>
                )}
                {!isPrimary && (
                  <button
                    className="px-2 py-1 rounded text-[9px] font-medium bg-white/5 text-white/40 hover:bg-red-500/10 hover:text-red-400 transition-colors"
                    onClick={onRemoveFromDb}
                  >
                    Remove
                  </button>
                )}
              </>
            ) : (
              <button
                className="px-2 py-1 rounded text-[9px] font-medium bg-white/5 text-white/50 hover:bg-white/10 hover:text-white/80 transition-colors"
                onClick={onAddToDb}
              >
                Add to DB
              </button>
            )}
          </>
        )}
      </div>
    </div>
  )
}

export default function ControlPanel({
  regions,
  failedRegions,
  failedNodes,
  replicas,
  topology,
  dbConfig,
  tableConfig,
  featureToggles,
  onToggleRegionFail,
  onToggleNodeFail,
  onSetPrimaryRegion,
  onAddRegionToDb,
  onRemoveRegionFromDb,
  onCreateDb,
  onDropDb,
  onSetSurvivalGoal,
  onSetTableLocality,
  onToggleFeature,
  onLoadScenario,
}: {
  regions: RegionConfig[]
  failedRegions: Set<RegionId>
  failedNodes: Set<string>
  replicas: ReplicaInfo[]
  topology: TopologyData | null
  dbConfig: DatabaseConfig | null
  tableConfig: TableConfig
  featureToggles: FeatureToggles
  onToggleRegionFail: (id: RegionId) => void
  onToggleNodeFail: (regionId: RegionId, nodeIndex: number) => void
  onSetPrimaryRegion: (id: RegionId) => void
  onAddRegionToDb: (id: RegionId) => void
  onRemoveRegionFromDb: (id: RegionId) => void
  onCreateDb: () => void
  onDropDb: () => void
  onSetSurvivalGoal: (goal: SurvivalGoal) => void
  onSetTableLocality: (locality: TableLocality) => void
  onToggleFeature: (key: keyof FeatureToggles) => void
  onLoadScenario: (scenario: ScenarioPreset) => void
}) {
  const [scenariosOpen, setScenariosOpen] = useState(false)
  return (
    <div className="w-80 flex-shrink-0 h-full overflow-y-auto border-l border-crdb-border bg-crdb-darker/80 p-4 flex flex-col gap-5">
      {/* Header */}
      <div>
        <h2 className="text-sm font-bold text-white/90 mb-1">Multi-Region Explorer</h2>
        <p className="text-[10px] text-white/40">Configure regions, survival goals, and table locality</p>
      </div>

      {/* Quick Start Scenarios */}
      <div>
        <button
          className="w-full flex items-center justify-between group"
          onClick={() => setScenariosOpen(prev => !prev)}
        >
          <SectionHeader>Quick Start Scenarios</SectionHeader>
          <motion.span
            animate={{ rotate: scenariosOpen ? 180 : 0 }}
            transition={{ duration: 0.2 }}
            className="text-[10px] text-white/30 group-hover:text-white/50 transition-colors"
          >
            &#x25BC;
          </motion.span>
        </button>
        <AnimatePresence initial={false}>
          {scenariosOpen && (
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={{ duration: 0.25, ease: 'easeInOut' }}
              className="overflow-hidden"
            >
              <div className="grid grid-cols-2 gap-2 pt-2">
                {SCENARIO_PRESETS.map(scenario => {
                  const iconColors: Record<string, string> = {
                    'US': '#60A5FA',
                    'GL': '#FBBF24',
                    'EU': '#34D399',
                    'DR': '#EF4444',
                  }
                  const color = iconColors[scenario.icon] ?? '#60A5FA'
                  const isActive = dbConfig !== null
                    && dbConfig.primaryRegion === scenario.dbConfig.primaryRegion
                    && dbConfig.survivalGoal === scenario.dbConfig.survivalGoal
                    && tableConfig.locality === scenario.tableLocality
                    && JSON.stringify([...failedRegions].sort()) === JSON.stringify([...scenario.failedRegions].sort())

                  return (
                    <motion.button
                      key={scenario.id}
                      className={`relative text-left p-2.5 rounded-lg border transition-all ${
                        isActive
                          ? 'border-crdb-accent/40 bg-crdb-accent/10'
                          : 'border-crdb-border bg-crdb-card/30 hover:border-white/15 hover:bg-crdb-card/60'
                      }`}
                      onClick={() => {
                        onLoadScenario(scenario)
                        setScenariosOpen(false)
                      }}
                      whileTap={{ scale: 0.96 }}
                    >
                      {/* Icon badge */}
                      <div
                        className="w-6 h-6 rounded-md flex items-center justify-center mb-1.5 text-[8px] font-black tracking-wide"
                        style={{
                          backgroundColor: color + '18',
                          color: color,
                          border: `1px solid ${color}30`,
                        }}
                      >
                        {scenario.icon}
                      </div>
                      <div className="text-[10px] font-bold text-white/80 leading-tight mb-0.5">
                        {scenario.name}
                      </div>
                      <div className="text-[8px] text-white/30 leading-snug line-clamp-2">
                        {scenario.description.split('.')[0]}.
                      </div>
                      {isActive && (
                        <div className="absolute top-1.5 right-1.5 w-1.5 h-1.5 rounded-full bg-crdb-accent" />
                      )}
                    </motion.button>
                  )
                })}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Regions */}
      <div>
        <SectionHeader>Regions</SectionHeader>
        <div className="flex flex-col gap-2">
          {regions.map(region => (
            <RegionCard
              key={region.id}
              region={region}
              isFailed={failedRegions.has(region.id)}
              isInDb={dbConfig?.regions.includes(region.id) ?? false}
              isPrimary={dbConfig?.primaryRegion === region.id}
              onToggleFail={() => onToggleRegionFail(region.id)}
              onSetPrimary={() => onSetPrimaryRegion(region.id)}
              onAddToDb={() => onAddRegionToDb(region.id)}
              onRemoveFromDb={() => onRemoveRegionFromDb(region.id)}
              hasDb={dbConfig !== null}
              failedNodes={failedNodes}
              replicas={replicas}
              topology={topology}
              onToggleNodeFail={(nodeIndex) => onToggleNodeFail(region.id, nodeIndex)}
            />
          ))}
        </div>
      </div>

      {/* Database */}
      <div>
        <SectionHeader>Database</SectionHeader>
        {dbConfig === null ? (
          <motion.button
            className="w-full py-2.5 rounded-lg text-xs font-bold bg-crdb-accent/15 text-crdb-accent border border-crdb-accent/30 hover:bg-crdb-accent/25 transition-colors"
            onClick={onCreateDb}
            whileTap={{ scale: 0.97 }}
          >
            CREATE DATABASE multi_region
          </motion.button>
        ) : (
          <div className="space-y-3">
            <div className="p-3 rounded-lg border border-crdb-border bg-crdb-card/40">
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-mono font-bold text-white/80">{dbConfig.name}</span>
                <button
                  className="text-[9px] text-red-400/60 hover:text-red-400 transition-colors"
                  onClick={onDropDb}
                >
                  DROP
                </button>
              </div>

              {/* SQL preview */}
              <pre className="text-[9px] font-mono text-white/30 bg-black/30 rounded p-2 mb-2 overflow-x-auto">
{`ALTER DATABASE ${dbConfig.name}
  PRIMARY REGION "${dbConfig.primaryRegion}"
  REGIONS "${dbConfig.regions.join('", "')}"
  SURVIVE ${dbConfig.survivalGoal === 'zone' ? 'ZONE' : 'REGION'} FAILURE;`}
              </pre>

              {/* Survival Goal */}
              <div className="mb-2">
                <div className="text-[9px] text-white/40 mb-1">Survival Goal</div>
                <div className="flex gap-1">
                  {(['zone', 'region'] as SurvivalGoal[]).map(goal => (
                    <button
                      key={goal}
                      className={`flex-1 px-2 py-1.5 rounded text-[10px] font-bold uppercase tracking-wider transition-colors ${
                        dbConfig.survivalGoal === goal
                          ? goal === 'zone'
                            ? 'bg-amber-500/15 text-amber-400 border border-amber-500/30'
                            : 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30'
                          : 'bg-white/5 text-white/30 hover:text-white/50'
                      }`}
                      onClick={() => onSetSurvivalGoal(goal)}
                    >
                      {goal === 'zone' ? 'Zone Failure' : 'Region Failure'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Regions list */}
              <div>
                <div className="text-[9px] text-white/40 mb-1">Active Regions</div>
                <div className="flex flex-wrap gap-1">
                  {dbConfig.regions.map(rid => {
                    const r = regions.find(rr => rr.id === rid)!
                    return (
                      <span
                        key={rid}
                        className="px-2 py-0.5 rounded-full text-[9px] font-medium border"
                        style={{
                          color: r.color,
                          borderColor: r.color + '30',
                          backgroundColor: r.color + '10',
                        }}
                      >
                        {r.label}
                        {rid === dbConfig.primaryRegion && ' *'}
                      </span>
                    )
                  })}
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Table Locality */}
      {dbConfig && (
        <div>
          <SectionHeader>Table Locality</SectionHeader>
          <div className="p-3 rounded-lg border border-crdb-border bg-crdb-card/40 space-y-2">
            <div className="text-[10px] font-mono text-white/60 mb-1">{tableConfig.name}</div>
            {(['regional-by-table', 'regional-by-row', 'global'] as TableLocality[]).map(locality => (
              <button
                key={locality}
                className={`w-full text-left px-3 py-2 rounded-lg text-[10px] font-medium transition-colors ${
                  tableConfig.locality === locality
                    ? 'bg-crdb-accent/15 text-crdb-accent border border-crdb-accent/30'
                    : 'bg-white/3 text-white/40 hover:text-white/60 hover:bg-white/5 border border-transparent'
                }`}
                onClick={() => onSetTableLocality(locality)}
              >
                <div className="font-bold uppercase tracking-wider text-[9px] mb-0.5">
                  {locality === 'regional-by-table'
                    ? 'Regional by Table'
                    : locality === 'regional-by-row'
                    ? 'Regional by Row'
                    : 'Global'}
                </div>
                <div className="text-[8px] opacity-60">
                  {locality === 'regional-by-table'
                    ? 'Leaseholder pinned to primary region. Low-latency reads in primary.'
                    : locality === 'regional-by-row'
                    ? 'Each row has a home region. Distributed leaseholders.'
                    : 'Non-voting replicas everywhere. Fast reads globally, slower writes.'}
                </div>
              </button>
            ))}
            {/* SQL Preview */}
            <pre className="text-[9px] font-mono text-white/30 bg-black/30 rounded p-2 overflow-x-auto">
{tableConfig.locality === 'regional-by-table'
  ? `ALTER TABLE ${tableConfig.name}\n  SET LOCALITY REGIONAL BY TABLE\n  IN PRIMARY REGION;`
  : tableConfig.locality === 'regional-by-row'
  ? `ALTER TABLE ${tableConfig.name}\n  SET LOCALITY REGIONAL BY ROW;`
  : `ALTER TABLE ${tableConfig.name}\n  SET LOCALITY GLOBAL;`}
            </pre>
          </div>
        </div>
      )}

      {/* How It Works */}
      {dbConfig && (() => {
        const teaching = getTeachingContent(dbConfig.survivalGoal, tableConfig.locality)
        return (
          <div>
            <SectionHeader>How It Works</SectionHeader>
            <div className="p-3 rounded-lg border border-crdb-border bg-crdb-card/40 space-y-2">
              <div className="text-[11px] font-bold text-crdb-accent">{teaching.title}</div>
              <p className="text-[9px] text-white/50 leading-relaxed">{teaching.explanation}</p>
              <div>
                <div className="text-[9px] text-white/40 mb-1">Replica Pattern:</div>
                <div className="font-mono text-[9px] text-white/60 bg-black/30 rounded px-2 py-1.5">
                  {teaching.replicaPattern}
                </div>
              </div>
              <div>
                <div className="text-[9px] text-white/40 mb-1">SQL:</div>
                <div className="font-mono text-[9px] text-crdb-accent/50 bg-black/30 rounded px-2 py-1.5">
                  {teaching.sqlHint}
                </div>
              </div>
            </div>
          </div>
        )
      })()}

      {/* Replica Distribution Diagram */}
      {dbConfig && (
        <ReplicaDistributionDiagram
          dbConfig={dbConfig}
          tableConfig={tableConfig}
          regions={regions}
          failedRegions={failedRegions}
        />
      )}

      {/* Feature Toggles */}
      <div>
        <SectionHeader>Globe Features</SectionHeader>
        <div className="grid grid-cols-2 gap-1.5 mb-4">
          {([
            { key: 'showLatency' as const, label: 'Latency', desc: 'Arc latency labels' },
            { key: 'showReplicas' as const, label: 'Replicas', desc: 'LH/V/NV badges' },
            { key: 'showDataPackets' as const, label: 'Packets', desc: 'Animated data flow' },
            { key: 'showZoneConfigs' as const, label: 'Zones', desc: 'Zone config overlay' },
          ]).map(toggle => (
            <button
              key={toggle.key}
              className={`text-left px-2.5 py-1.5 rounded-lg text-[9px] transition-colors border ${
                featureToggles[toggle.key]
                  ? 'bg-crdb-accent/15 text-crdb-accent border-crdb-accent/30'
                  : 'bg-white/3 text-white/30 hover:text-white/50 border-transparent'
              }`}
              onClick={() => onToggleFeature(toggle.key)}
            >
              <div className="font-bold">{toggle.label}</div>
              <div className="text-[7px] opacity-60 mt-0.5">{toggle.desc}</div>
            </button>
          ))}
        </div>
      </div>

      {/* Latency Matrix */}
      <div>
        <SectionHeader>Latency Matrix</SectionHeader>
        <div className="overflow-x-auto">
          <table className="w-full text-[9px] font-mono">
            <thead>
              <tr>
                <th className="text-left text-white/30 p-1" />
                {regions.map(r => (
                  <th
                    key={r.id}
                    className="text-center p-1 font-bold"
                    style={{ color: failedRegions.has(r.id) ? '#EF4444' : r.color }}
                  >
                    {r.label.split('-')[0]}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {regions.map(from => (
                <tr key={from.id}>
                  <td
                    className="text-right pr-2 font-bold p-1"
                    style={{ color: failedRegions.has(from.id) ? '#EF4444' : from.color }}
                  >
                    {from.label.split('-')[0]}
                  </td>
                  {regions.map(to => {
                    const key = `${from.id}:${to.id}`
                    const latency = LATENCIES[key] ?? 0
                    const isCrossRegion = from.id !== to.id
                    const isFailed = failedRegions.has(from.id) || failedRegions.has(to.id)
                    return (
                      <td
                        key={to.id}
                        className={`text-center p-1 ${
                          isFailed
                            ? 'text-red-500/30 line-through'
                            : isCrossRegion
                            ? 'text-white/60'
                            : 'text-emerald-400/60'
                        }`}
                      >
                        {isFailed ? '--' : `${latency}ms`}
                      </td>
                    )
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Info */}
      <div className="mt-auto pt-4 border-t border-crdb-border">
        <p className="text-[9px] text-white/20 leading-relaxed">
          Click a region on the globe to set it as primary.
          Use the controls above to configure multi-region topology.
        </p>
      </div>
    </div>
  )
}
