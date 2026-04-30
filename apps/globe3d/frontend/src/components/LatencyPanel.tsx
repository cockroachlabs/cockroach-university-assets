import { useMemo } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import type { RegionConfig, RegionId, DatabaseConfig, TableConfig } from '../types'
import { LATENCIES } from '../types'

type OperationType = 'read' | 'write'

interface LatencyEstimate {
  clientRegion: RegionId
  readLatency: number
  writeLatency: number
  readPath: string
  writePath: string
}

function estimateLatencies(
  regions: RegionConfig[],
  dbConfig: DatabaseConfig,
  tableConfig: TableConfig,
  failedRegions: Set<RegionId>,
  failedNodes: Set<string>,
): LatencyEstimate[] {
  const isRegionDown = (rid: RegionId) => {
    if (failedRegions.has(rid)) return true
    let allDown = true
    for (let n = 0; n < 3; n++) {
      if (!failedNodes.has(`${rid}:${n}`)) { allDown = false; break }
    }
    return allDown
  }
  const activeRegions = dbConfig.regions.filter(r => !isRegionDown(r))
  const primary = failedRegions.has(dbConfig.primaryRegion)
    ? activeRegions[0]
    : dbConfig.primaryRegion

  if (!primary || activeRegions.length === 0) return []

  const getLatency = (from: RegionId, to: RegionId) => LATENCIES[`${from}:${to}`] ?? 0

  return regions
    .filter(r => !isRegionDown(r.id))
    .map(clientRegion => {
      let readLatency: number
      let writeLatency: number
      let readPath: string
      let writePath: string

      switch (tableConfig.locality) {
        case 'regional-by-table': {
          // Reads: go to leaseholder (in primary region)
          // Writes: go to leaseholder, then Raft consensus (2 closest replicas)
          const toLeaseHolder = getLatency(clientRegion.id, primary)
          readLatency = toLeaseHolder + 2 // +2ms local read
          readPath = clientRegion.id === primary
            ? 'Local leaseholder read'
            : `Client -> ${primary} (leaseholder)`

          // Write: client->LH + LH->replica (quorum) + apply
          const replicaLatencies = activeRegions
            .filter(r => r !== primary)
            .map(r => getLatency(primary, r))
            .sort((a, b) => a - b)
          const quorumLatency = replicaLatencies[0] ?? 0 // fastest replica for quorum
          writeLatency = toLeaseHolder + quorumLatency + 2
          writePath = clientRegion.id === primary
            ? `Local LH + Raft quorum (${quorumLatency}ms)`
            : `Client -> ${primary} + Raft quorum (${quorumLatency}ms)`
          break
        }

        case 'regional-by-row': {
          // Reads: go to local leaseholder (each region has one for its rows)
          readLatency = 2 // local read
          readPath = 'Local leaseholder (own rows)'

          // Writes: local leaseholder + Raft consensus to closest replica
          const otherRegions = activeRegions
            .filter(r => r !== clientRegion.id)
            .map(r => getLatency(clientRegion.id, r))
            .sort((a, b) => a - b)
          const quorumLat = otherRegions[0] ?? 0
          writeLatency = quorumLat + 2
          writePath = `Local LH + Raft quorum (${quorumLat}ms to closest replica)`
          break
        }

        case 'global': {
          // Reads: served by local non-voting replica (follower read)
          readLatency = 2
          readPath = 'Local non-voting replica (follower read)'

          // Writes: must go to leaseholder (primary) + Raft consensus
          const toLH = getLatency(clientRegion.id, primary)
          const replicaLats = activeRegions
            .filter(r => r !== primary)
            .map(r => getLatency(primary, r))
            .sort((a, b) => a - b)
          const qLat = replicaLats[0] ?? 0
          writeLatency = toLH + qLat + 2
          writePath = clientRegion.id === primary
            ? `Local LH + Raft quorum (${qLat}ms)`
            : `Client -> ${primary} (${toLH}ms) + Raft (${qLat}ms)`
          break
        }
      }

      return {
        clientRegion: clientRegion.id,
        readLatency,
        writeLatency,
        readPath,
        writePath,
      }
    })
}

function LatencyBar({
  value,
  max,
  color,
  type,
}: {
  value: number
  max: number
  color: string
  type: OperationType
}) {
  const width = Math.max(4, (value / max) * 100)
  return (
    <div className="flex items-center gap-2">
      <span className={`text-[8px] font-bold uppercase w-5 ${type === 'read' ? 'text-emerald-400/70' : 'text-amber-400/70'}`}>
        {type === 'read' ? 'R' : 'W'}
      </span>
      <div className="flex-1 h-2 rounded-full bg-white/5 overflow-hidden">
        <motion.div
          className="h-full rounded-full"
          style={{ backgroundColor: color }}
          initial={{ width: 0 }}
          animate={{ width: `${width}%` }}
          transition={{ duration: 0.5, ease: 'easeOut' }}
        />
      </div>
      <span className="text-[9px] font-mono text-white/60 w-10 text-right">{value}ms</span>
    </div>
  )
}

export default function LatencyPanel({
  regions,
  failedRegions,
  failedNodes,
  hasQuorum,
  dbConfig,
  tableConfig,
}: {
  regions: RegionConfig[]
  failedRegions: Set<RegionId>
  failedNodes: Set<string>
  hasQuorum: boolean
  dbConfig: DatabaseConfig | null
  tableConfig: TableConfig
}) {
  const estimates = useMemo(() => {
    if (!dbConfig) return []
    return estimateLatencies(regions, dbConfig, tableConfig, failedRegions, failedNodes)
  }, [regions, dbConfig, tableConfig, failedRegions, failedNodes])

  if (!dbConfig || estimates.length === 0) return null

  if (!hasQuorum) {
    return (
      <motion.div
        className="absolute bottom-4 right-4 w-72 glass-panel p-3"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
      >
        <div className="flex flex-col items-center justify-center py-4 gap-2">
          <div className="w-3 h-3 rounded-full bg-red-500 animate-pulse shadow-[0_0_12px_rgba(239,68,68,0.5)]" />
          <div className="text-[11px] font-bold text-red-400 uppercase tracking-widest">
            Database Unavailable
          </div>
          <div className="text-[9px] text-red-400/50 text-center font-mono">
            Quorum lost — reads and writes are blocked
          </div>
        </div>
      </motion.div>
    )
  }

  const maxLatency = Math.max(...estimates.flatMap(e => [e.readLatency, e.writeLatency]), 1)

  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={`${tableConfig.locality}-${dbConfig.primaryRegion}-${failedRegions.size}`}
        className="absolute bottom-4 right-4 w-72 glass-panel p-3"
        initial={{ opacity: 0, y: 10, scale: 0.95 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={{ opacity: 0, y: 10, scale: 0.95 }}
        transition={{ duration: 0.3 }}
      >
        <div className="flex items-center justify-between mb-2">
          <h4 className="text-[9px] font-bold uppercase tracking-widest text-white/40">
            Read / Write Latency
          </h4>
          <span className="text-[8px] font-mono text-crdb-accent/60">
            {tableConfig.locality.toUpperCase()}
          </span>
        </div>

        <div className="space-y-2.5">
          {estimates.map(est => {
            const region = regions.find(r => r.id === est.clientRegion)!
            return (
              <div key={est.clientRegion}>
                <div className="flex items-center gap-1.5 mb-1">
                  <div
                    className="w-1.5 h-1.5 rounded-full"
                    style={{ backgroundColor: region.color }}
                  />
                  <span className="text-[9px] font-bold" style={{ color: region.color }}>
                    {region.label}
                  </span>
                  <span className="text-[7px] text-white/20 ml-auto">client in {region.city}</span>
                </div>
                <div className="space-y-0.5 pl-3">
                  <LatencyBar value={est.readLatency} max={maxLatency} color="#34D399" type="read" />
                  <LatencyBar value={est.writeLatency} max={maxLatency} color="#FBBF24" type="write" />
                </div>
                <div className="pl-3 mt-0.5">
                  <div className="text-[7px] text-white/20 truncate" title={est.readPath}>
                    R: {est.readPath}
                  </div>
                  <div className="text-[7px] text-white/20 truncate" title={est.writePath}>
                    W: {est.writePath}
                  </div>
                </div>
              </div>
            )
          })}
        </div>

        {/* Teaching insight */}
        <motion.div
          className="mt-2.5 pt-2 border-t border-crdb-border"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.4 }}
        >
          <p className="text-[8px] text-white/25 leading-relaxed">
            {tableConfig.locality === 'regional-by-table' && (
              <>Reads and writes are fast in the primary region. Other regions pay cross-region latency to reach the leaseholder.</>
            )}
            {tableConfig.locality === 'regional-by-row' && (
              <>Each region has fast reads and writes for its own rows. Cross-region access pays the latency cost to that row's home region.</>
            )}
            {tableConfig.locality === 'global' && (
              <>Reads are fast everywhere (served by local non-voting replicas). Writes are slower because they must go through the leaseholder in the primary region for Raft consensus.</>
            )}
          </p>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  )
}
