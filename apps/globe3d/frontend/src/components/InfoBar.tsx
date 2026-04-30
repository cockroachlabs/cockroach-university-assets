import { motion, AnimatePresence } from 'framer-motion'
import type { DatabaseConfig, TableConfig, RegionConfig, RegionId, ReplicaInfo, ClusterStatus } from '../types'

export default function InfoBar({
  dbConfig,
  tableConfig,
  regions,
  failedRegions,
  failedNodes,
  clusterConnected = false,
  replicas,
  clusterStatus,
}: {
  dbConfig: DatabaseConfig | null
  tableConfig: TableConfig
  regions: RegionConfig[]
  failedRegions: Set<RegionId>
  failedNodes?: Set<string>
  clusterConnected?: boolean
  replicas?: ReplicaInfo[]
  clusterStatus?: ClusterStatus
}) {
  const activeRegions = regions.filter(r => !failedRegions.has(r.id))
  const totalNodes = activeRegions.reduce((sum, r) => sum + r.nodes, 0)
  const failedCount = failedRegions.size
  const failedNodeCount = failedNodes?.size ?? 0

  const isNodeFailed = (regionId: RegionId, nodeIndex: number) =>
    failedRegions.has(regionId) || (failedNodes?.has(`${regionId}:${nodeIndex}`) ?? false)

  const allVoters = (replicas ?? []).filter(r => r.isVoting)
  const aliveVoters = allVoters.filter(r => !isNodeFailed(r.regionId, r.nodeIndex))
  const totalVoters = allVoters.length
  const aliveVoterCount = aliveVoters.length
  const hasQuorum = clusterStatus?.hasQuorum ?? (aliveVoterCount >= Math.floor(totalVoters / 2) + 1)
  const rf = totalVoters

  return (
    <div className="h-10 flex items-center px-4 border-b border-crdb-border bg-crdb-darker/90 gap-6">
      {/* Cluster info */}
      <div className="flex items-center gap-3">
        <div className="flex items-center gap-1.5">
          <div className={`w-1.5 h-1.5 rounded-full ${
            clusterConnected
              ? 'bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.5)]'
              : 'bg-amber-400 shadow-[0_0_6px_rgba(251,191,36,0.3)]'
          }`} />
          <span className="text-[10px] font-mono text-white/50">
            {clusterConnected ? 'Live' : 'Simulated'} &middot; {totalNodes} nodes across {activeRegions.length} regions
          </span>
        </div>

        {(failedCount > 0 || failedNodeCount > 0) && (
          <motion.div
            className="flex items-center gap-1.5"
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1, x: 0 }}
          >
            <div className="w-1.5 h-1.5 rounded-full bg-red-500 shadow-[0_0_6px_rgba(239,68,68,0.5)]" />
            <span className="text-[10px] font-mono text-red-400/70">
              {failedCount > 0 && `${failedCount} region${failedCount > 1 ? 's' : ''} down`}
              {failedCount > 0 && failedNodeCount > 0 && ' + '}
              {failedNodeCount > 0 && `${failedNodeCount} node${failedNodeCount > 1 ? 's' : ''} down`}
            </span>
          </motion.div>
        )}
      </div>

      {/* Quorum status */}
      <AnimatePresence mode="wait">
        {replicas && replicas.length > 0 && (
          <motion.div
            key={hasQuorum ? 'quorum-ok' : 'quorum-lost'}
            className="flex items-center gap-2"
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -10 }}
          >
            <span className="text-[10px] font-mono text-white/50 px-1.5 py-0.5 rounded bg-white/5">
              RF={rf}
            </span>
            <span className="text-[10px] font-mono text-white/50 px-1.5 py-0.5 rounded bg-white/5">
              {aliveVoterCount}/{totalVoters} voters
            </span>
            {hasQuorum ? (
              <span className="flex items-center gap-1.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-emerald-500/15 text-emerald-400">
                <div className="w-1.5 h-1.5 rounded-full bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.5)]" />
                {clusterStatus?.message || 'QUORUM OK'}
              </span>
            ) : (
              <motion.span
                className="flex items-center gap-1.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-red-500/15 text-red-400"
                animate={{ opacity: [0.7, 1.0, 0.7] }}
                transition={{ duration: 1.5, repeat: Infinity, ease: 'easeInOut' }}
              >
                <div className="w-1.5 h-1.5 rounded-full bg-red-500 shadow-[0_0_6px_rgba(239,68,68,0.5)]" />
                {clusterStatus?.message || 'QUORUM LOST'}
              </motion.span>
            )}
            {clusterStatus?.activePrimary && failedRegions.size > 0 && (
              <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-400">
                LH → {regions.find(r => r.id === clusterStatus.activePrimary)?.label}
              </span>
            )}
          </motion.div>
        )}
      </AnimatePresence>

      {/* Database status */}
      <AnimatePresence mode="wait">
        {dbConfig ? (
          <motion.div
            key="db"
            className="flex items-center gap-3 ml-auto"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <span className="text-[10px] font-mono text-crdb-accent/70">
              DB: {dbConfig.name}
            </span>
            <span className="text-[10px] font-mono text-white/30">
              Primary: {regions.find(r => r.id === dbConfig.primaryRegion)?.label}
            </span>
            <span
              className={`text-[9px] font-mono px-1.5 py-0.5 rounded ${
                dbConfig.survivalGoal === 'region'
                  ? 'bg-emerald-500/15 text-emerald-400'
                  : 'bg-amber-500/15 text-amber-400'
              }`}
            >
              SURVIVE {dbConfig.survivalGoal.toUpperCase()} FAILURE
            </span>
            <span className="text-[10px] font-mono text-white/30">
              Table: {tableConfig.locality.toUpperCase()}
            </span>
          </motion.div>
        ) : (
          <motion.div
            key="no-db"
            className="ml-auto"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <span className="text-[10px] font-mono text-white/20">
              No database configured - create one in the panel
            </span>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
