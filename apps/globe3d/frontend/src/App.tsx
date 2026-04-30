import { useState, useMemo, useCallback } from 'react'
import Globe3D from './components/Globe3D'
import ControlPanel from './components/ControlPanel'
import DemoPanel from './components/DemoPanel'
import InfoBar from './components/InfoBar'
import LatencyPanel from './components/LatencyPanel'
import QueryTracer from './components/QueryTracer'
import { useClusterSync } from './hooks/useClusterSync'
import type {
  RegionId,
  DatabaseConfig,
  SurvivalGoal,
  TableLocality,
  TableConfig,
  ReplicaInfo,
  ScenarioPreset,
  FeatureToggles,
} from './types'
import { REGIONS, DEFAULT_FEATURE_TOGGLES } from './types'

/** Check if a specific node is down (either entire region failed or individual node killed) */
function isNodeDown(regionId: RegionId, nodeIndex: number, failedRegions: Set<RegionId>, failedNodes: Set<string>): boolean {
  return failedRegions.has(regionId) || failedNodes.has(`${regionId}:${nodeIndex}`)
}

/** Check if ALL nodes in a region are down */
function isRegionEffectivelyDown(regionId: RegionId, nodeCount: number, failedRegions: Set<RegionId>, failedNodes: Set<string>): boolean {
  if (failedRegions.has(regionId)) return true
  for (let n = 0; n < nodeCount; n++) {
    if (!failedNodes.has(`${regionId}:${n}`)) return false
  }
  return true
}

/** Compute replica distribution based on db config, table locality, and failed regions/nodes */
function computeReplicas(
  dbConfig: DatabaseConfig | null,
  tableConfig: TableConfig,
  failedRegions: Set<RegionId>,
  failedNodes: Set<string>,
): ReplicaInfo[] {
  if (!dbConfig) return []

  const replicas: ReplicaInfo[] = []
  const allDbRegions = dbConfig.regions
  const nodeCount = 3 // all regions have 3 nodes
  const activeRegions = allDbRegions.filter(r => !isRegionEffectivelyDown(r, nodeCount, failedRegions, failedNodes))
  const primaryDown = isRegionEffectivelyDown(dbConfig.primaryRegion, nodeCount, failedRegions, failedNodes)
  const survival = dbConfig.survivalGoal

  if (activeRegions.length === 0) return []

  // --- GLOBAL locality (same for zone & region survival) ---
  if (tableConfig.locality === 'global') {
    const primary = primaryDown ? activeRegions[0] : dbConfig.primaryRegion
    // 1 voting replica per DB region (on node 0), LH in primary
    for (const rid of allDbRegions) {
      if (isRegionEffectivelyDown(rid, nodeCount, failedRegions, failedNodes)) continue
      // Place on first alive node in region
      const aliveNode = [0, 1, 2].find(n => !isNodeDown(rid, n, failedRegions, failedNodes)) ?? 0
      replicas.push({
        regionId: rid,
        nodeIndex: aliveNode,
        isVoting: true,
        isLeaseholder: rid === primary,
      })
    }
    return replicas
  }

  // --- ZONE survival (RF=3) ---
  if (survival === 'zone') {
    if (tableConfig.locality === 'regional-by-table') {
      // 3 voting replicas ALL in primary region (nodes 0,1,2)
      // We always emit them so the UI shows the topology
      const primary = dbConfig.primaryRegion
      // Find first alive node for leaseholder
      const lhNode = [0, 1, 2].find(n => !isNodeDown(primary, n, failedRegions, failedNodes))
      for (let n = 0; n < 3; n++) {
        replicas.push({
          regionId: primary,
          nodeIndex: n,
          isVoting: true,
          isLeaseholder: lhNode !== undefined && n === lhNode,
        })
      }
      // 1 non-voting replica in each OTHER db region (node 0) for follower reads
      for (const rid of allDbRegions) {
        if (rid === primary) continue
        if (isRegionEffectivelyDown(rid, nodeCount, failedRegions, failedNodes)) continue
        const aliveNode = [0, 1, 2].find(n => !isNodeDown(rid, n, failedRegions, failedNodes)) ?? 0
        replicas.push({
          regionId: rid,
          nodeIndex: aliveNode,
          isVoting: false,
          isLeaseholder: false,
        })
      }
    } else {
      // regional-by-row: each region is home for its own rows
      for (const homeRegion of allDbRegions) {
        if (isRegionEffectivelyDown(homeRegion, nodeCount, failedRegions, failedNodes)) continue
        // 3 voting replicas in the home region (nodes 0,1,2)
        const lhNode = [0, 1, 2].find(n => !isNodeDown(homeRegion, n, failedRegions, failedNodes))
        for (let n = 0; n < 3; n++) {
          replicas.push({
            regionId: homeRegion,
            nodeIndex: n,
            isVoting: true,
            isLeaseholder: lhNode !== undefined && n === lhNode,
          })
        }
        // 1 non-voting replica in each other region (node 0)
        for (const rid of allDbRegions) {
          if (rid === homeRegion || isRegionEffectivelyDown(rid, nodeCount, failedRegions, failedNodes)) continue
          const aliveNode = [0, 1, 2].find(n => !isNodeDown(rid, n, failedRegions, failedNodes)) ?? 0
          replicas.push({
            regionId: rid,
            nodeIndex: aliveNode,
            isVoting: false,
            isLeaseholder: false,
          })
        }
      }
    }
    return replicas
  }

  // --- REGION survival (RF=5, 2-2-1 spread) ---
  if (tableConfig.locality === 'regional-by-table') {
    // Determine effective primary: if all nodes down, LH migrates to first active region
    const primary = primaryDown ? activeRegions[0] : dbConfig.primaryRegion
    const otherRegions = allDbRegions.filter(r => r !== primary && !isRegionEffectivelyDown(r, nodeCount, failedRegions, failedNodes))

    // 2 in primary (LH on first alive node, V on second alive node)
    const primaryAlive = [0, 1, 2].filter(n => !isNodeDown(primary, n, failedRegions, failedNodes))
    if (primaryAlive.length >= 1) {
      replicas.push({ regionId: primary, nodeIndex: primaryAlive[0], isVoting: true, isLeaseholder: true })
    }
    if (primaryAlive.length >= 2) {
      replicas.push({ regionId: primary, nodeIndex: primaryAlive[1], isVoting: true, isLeaseholder: false })
    }

    // 2 in second region, 1 in third
    if (otherRegions.length >= 1) {
      const alive = [0, 1, 2].filter(n => !isNodeDown(otherRegions[0], n, failedRegions, failedNodes))
      if (alive.length >= 1) replicas.push({ regionId: otherRegions[0], nodeIndex: alive[0], isVoting: true, isLeaseholder: false })
      if (alive.length >= 2) replicas.push({ regionId: otherRegions[0], nodeIndex: alive[1], isVoting: true, isLeaseholder: false })
    }
    if (otherRegions.length >= 2) {
      const alive = [0, 1, 2].filter(n => !isNodeDown(otherRegions[1], n, failedRegions, failedNodes))
      if (alive.length >= 1) replicas.push({ regionId: otherRegions[1], nodeIndex: alive[0], isVoting: true, isLeaseholder: false })
    }
  } else {
    // regional-by-row with region survival
    for (const homeRegion of allDbRegions) {
      if (isRegionEffectivelyDown(homeRegion, nodeCount, failedRegions, failedNodes)) {
        // Home region fully down — LH migrates to first active other region
        const activeOthers = allDbRegions.filter(r => r !== homeRegion && !isRegionEffectivelyDown(r, nodeCount, failedRegions, failedNodes))
        if (activeOthers.length === 0) continue
        const newPrimary = activeOthers[0]
        const alive = [0, 1, 2].filter(n => !isNodeDown(newPrimary, n, failedRegions, failedNodes))
        if (alive.length >= 1) replicas.push({ regionId: newPrimary, nodeIndex: alive[0], isVoting: true, isLeaseholder: true })
        if (alive.length >= 2) replicas.push({ regionId: newPrimary, nodeIndex: alive[1], isVoting: true, isLeaseholder: false })
        const remaining = activeOthers.slice(1)
        if (remaining.length >= 1) {
          const rAlive = [0, 1, 2].filter(n => !isNodeDown(remaining[0], n, failedRegions, failedNodes))
          if (rAlive.length >= 1) replicas.push({ regionId: remaining[0], nodeIndex: rAlive[0], isVoting: true, isLeaseholder: false })
          if (rAlive.length >= 2) replicas.push({ regionId: remaining[0], nodeIndex: rAlive[1], isVoting: true, isLeaseholder: false })
        }
      } else {
        // Home region alive — 2-2-1 spread with home as primary
        const otherRegions = allDbRegions.filter(r => r !== homeRegion && !isRegionEffectivelyDown(r, nodeCount, failedRegions, failedNodes))
        const homeAlive = [0, 1, 2].filter(n => !isNodeDown(homeRegion, n, failedRegions, failedNodes))
        if (homeAlive.length >= 1) replicas.push({ regionId: homeRegion, nodeIndex: homeAlive[0], isVoting: true, isLeaseholder: true })
        if (homeAlive.length >= 2) replicas.push({ regionId: homeRegion, nodeIndex: homeAlive[1], isVoting: true, isLeaseholder: false })
        if (otherRegions.length >= 1) {
          const alive = [0, 1, 2].filter(n => !isNodeDown(otherRegions[0], n, failedRegions, failedNodes))
          if (alive.length >= 1) replicas.push({ regionId: otherRegions[0], nodeIndex: alive[0], isVoting: true, isLeaseholder: false })
          if (alive.length >= 2) replicas.push({ regionId: otherRegions[0], nodeIndex: alive[1], isVoting: true, isLeaseholder: false })
        }
        if (otherRegions.length >= 2) {
          const alive = [0, 1, 2].filter(n => !isNodeDown(otherRegions[1], n, failedRegions, failedNodes))
          if (alive.length >= 1) replicas.push({ regionId: otherRegions[1], nodeIndex: alive[0], isVoting: true, isLeaseholder: false })
        }
      }
    }
  }

  return replicas
}

export default function App() {
  const [failedRegions, setFailedRegions] = useState<Set<RegionId>>(new Set())
  const [failedNodes, setFailedNodes] = useState<Set<string>>(new Set())
  const [dbConfig, setDbConfig] = useState<DatabaseConfig | null>(null)
  const [tableConfig, setTableConfig] = useState<TableConfig>({
    name: 'users',
    locality: 'regional-by-table',
  })
  const [featureToggles, setFeatureToggles] = useState<FeatureToggles>(DEFAULT_FEATURE_TOGGLES)

  const toggleFeature = useCallback((key: keyof FeatureToggles) => {
    setFeatureToggles(prev => ({ ...prev, [key]: !prev[key] }))
  }, [])

  const { clusterConnected, topology, actions } = useClusterSync()

  const replicas = useMemo(
    () => computeReplicas(dbConfig, tableConfig, failedRegions, failedNodes),
    [dbConfig, tableConfig, failedRegions, failedNodes],
  )

  const clusterStatus = useMemo(() => {
    if (!dbConfig) return { hasQuorum: true, message: '', activePrimary: null as RegionId | null }

    const votingReplicas = replicas.filter(r => r.isVoting)
    // A voter is alive only if its specific node is alive
    const aliveVoters = votingReplicas.filter(r =>
      !isNodeDown(r.regionId, r.nodeIndex, failedRegions, failedNodes)
    )
    const totalVoters = votingReplicas.length
    const aliveCount = aliveVoters.length
    const quorumNeeded = Math.floor(totalVoters / 2) + 1
    const hasQuorum = aliveCount >= quorumNeeded

    // Determine where the leaseholder actually is
    const lhReplica = replicas.find(r =>
      r.isLeaseholder && !isNodeDown(r.regionId, r.nodeIndex, failedRegions, failedNodes)
    )
    const activePrimary = lhReplica?.regionId ?? null

    const totalFailed = failedRegions.size + failedNodes.size
    let message = ''
    if (!hasQuorum) {
      message = `QUORUM LOST — ${aliveCount}/${totalVoters} voters alive, need ${quorumNeeded}`
    } else if (totalFailed > 0) {
      message = `Quorum OK — ${aliveCount}/${totalVoters} voters alive`
    }

    return { hasQuorum, message, activePrimary }
  }, [replicas, failedRegions, failedNodes, dbConfig])

  const handleToggleRegionFail = useCallback((id: RegionId) => {
    const isCurrentlyFailed = failedRegions.has(id)

    setFailedRegions(prev => {
      const next = new Set(prev)
      if (next.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
    // When restoring a region, clear its individual node failures
    setFailedNodes(prev => {
      const next = new Set(prev)
      for (let n = 0; n < 3; n++) {
        next.delete(`${id}:${n}`)
      }
      return next
    })

    // Trigger real Docker operations when backend is available
    if (clusterConnected) {
      if (isCurrentlyFailed) {
        actions.restartRegion(id)
      } else {
        actions.killRegion(id)
      }
    }
  }, [failedRegions, clusterConnected, actions])

  // Map regionId + nodeIndex to Docker container name for real cluster ops
  const regionToContainerPrefix: Record<RegionId, number> = {
    'us-east': 1,       // crdb-node-1, crdb-node-2, crdb-node-3
    'eu-west': 4,       // crdb-node-4, crdb-node-5, crdb-node-6
    'ap-southeast': 7,  // crdb-node-7, crdb-node-8, crdb-node-9
  }

  const handleToggleNodeFail = useCallback((regionId: RegionId, nodeIndex: number) => {
    const key = `${regionId}:${nodeIndex}`
    const isCurrentlyFailed = failedNodes.has(key)

    setFailedNodes(prev => {
      const next = new Set(prev)
      if (next.has(key)) {
        next.delete(key)
      } else {
        next.add(key)
      }
      return next
    })

    // Trigger real Docker operations when backend is available
    if (clusterConnected) {
      const baseIndex = regionToContainerPrefix[regionId] ?? 1
      const containerName = `crdb-node-${baseIndex + nodeIndex}`
      if (isCurrentlyFailed) {
        actions.restartNode(containerName)
      } else {
        actions.killNode(containerName)
      }
    }
  }, [failedNodes, clusterConnected, actions])

  const handleSetPrimaryRegion = useCallback((id: RegionId) => {
    setDbConfig(prev => {
      if (!prev) return prev
      const regions = prev.regions.includes(id) ? prev.regions : [...prev.regions, id]
      return { ...prev, primaryRegion: id, regions }
    })
    if (clusterConnected) actions.setPrimaryRegion(id)
  }, [clusterConnected, actions])

  const handleRegionClick = useCallback((id: RegionId) => {
    setDbConfig(prev => {
      if (!prev) return prev
      if (!prev.regions.includes(id)) return prev
      return { ...prev, primaryRegion: id }
    })
    if (clusterConnected) actions.setPrimaryRegion(id)
  }, [clusterConnected, actions])

  const handleAddRegionToDb = useCallback((id: RegionId) => {
    setDbConfig(prev => {
      if (!prev) return prev
      if (prev.regions.includes(id)) return prev
      return { ...prev, regions: [...prev.regions, id] }
    })
    if (clusterConnected) actions.addRegion(id)
  }, [clusterConnected, actions])

  const handleRemoveRegionFromDb = useCallback((id: RegionId) => {
    setDbConfig(prev => {
      if (!prev) return prev
      if (id === prev.primaryRegion) return prev
      return { ...prev, regions: prev.regions.filter(r => r !== id) }
    })
    if (clusterConnected) actions.removeRegion(id)
  }, [clusterConnected, actions])

  const handleCreateDb = useCallback(() => {
    setDbConfig({
      name: 'multi_region',
      primaryRegion: 'us-east',
      regions: ['us-east', 'eu-west', 'ap-southeast'],
      survivalGoal: 'zone',
    })
    if (clusterConnected) actions.createDatabase('us-east1')
  }, [clusterConnected, actions])

  const handleDropDb = useCallback(() => {
    setDbConfig(null)
    if (clusterConnected) actions.dropDatabase()
  }, [clusterConnected, actions])

  const handleSetSurvivalGoal = useCallback((goal: SurvivalGoal) => {
    setDbConfig(prev => {
      if (!prev) return prev
      return { ...prev, survivalGoal: goal }
    })
    if (clusterConnected) actions.setSurvivalGoal(goal)
  }, [clusterConnected, actions])

  const handleSetTableLocality = useCallback((locality: TableLocality) => {
    setTableConfig(prev => ({ ...prev, locality }))
    if (clusterConnected) actions.setTableLocality(locality)
  }, [clusterConnected, actions])

  const handleLoadScenario = useCallback((scenario: ScenarioPreset) => {
    // Set database config
    setDbConfig({ ...scenario.dbConfig })
    // Set table locality
    setTableConfig(prev => ({ ...prev, locality: scenario.tableLocality }))
    // Set failed regions
    setFailedRegions(new Set(scenario.failedRegions))
    // Clear any individual node failures
    setFailedNodes(new Set())
  }, [])

  return (
    <div className="h-screen flex flex-col bg-crdb-darker overflow-hidden">
      {/* Top bar */}
      <InfoBar
        dbConfig={dbConfig}
        tableConfig={tableConfig}
        regions={REGIONS}
        failedRegions={failedRegions}
        failedNodes={failedNodes}
        clusterConnected={clusterConnected}
        replicas={replicas}
        clusterStatus={clusterStatus}
      />

      {/* Main content */}
      <div className="flex-1 flex min-h-0">
        {/* Globe */}
        <div className="flex-1 min-w-0 relative">
          <Globe3D
            regions={REGIONS}
            failedRegions={failedRegions}
            failedNodes={failedNodes}
            dbConfig={dbConfig}
            replicas={replicas}
            featureToggles={featureToggles}
            hasQuorum={clusterStatus.hasQuorum}
            onRegionClick={handleRegionClick}
          />

          {/* Failure Demo Panel */}
          <DemoPanel
            clusterConnected={clusterConnected}
            onExecuteScenario={actions.executeDemoScenario}
          />

          {/* Globe legend overlay */}
          <div className="absolute bottom-4 left-4 flex flex-col gap-1">
            <div className="flex items-center gap-2 text-[9px] text-white/30">
              <div className="w-3 h-3 rounded-full border-2 border-white/20" />
              <span>Voting Replica</span>
            </div>
            <div className="flex items-center gap-2 text-[9px] text-white/30">
              <div className="w-3 h-3 rounded-full border border-dashed border-white/15" />
              <span>Non-Voting Replica</span>
            </div>
            <div className="flex items-center gap-2 text-[9px] text-white/30">
              <div className="w-3 h-0.5 bg-white/20" />
              <span>Replication Arc</span>
            </div>
            <div className="flex items-center gap-2 text-[9px] text-white/30">
              <div className="w-3 h-3 rounded-full ring-2 ring-white/20 ring-offset-1 ring-offset-crdb-darker" />
              <span>Primary Region</span>
            </div>
          </div>

          {/* Query Path Tracer */}
          <QueryTracer
            dbConfig={dbConfig}
            replicas={replicas}
            failedRegions={failedRegions}
          />

          {/* Read/Write latency comparison panel */}
          <LatencyPanel
            regions={REGIONS}
            failedRegions={failedRegions}
            failedNodes={failedNodes}
            dbConfig={dbConfig}
            tableConfig={tableConfig}
            hasQuorum={clusterStatus.hasQuorum}
          />
        </div>

        {/* Control Panel */}
        <ControlPanel
          regions={REGIONS}
          failedRegions={failedRegions}
          failedNodes={failedNodes}
          dbConfig={dbConfig}
          tableConfig={tableConfig}
          replicas={replicas}
          topology={topology}
          featureToggles={featureToggles}
          onToggleRegionFail={handleToggleRegionFail}
          onToggleNodeFail={handleToggleNodeFail}
          onSetPrimaryRegion={handleSetPrimaryRegion}
          onAddRegionToDb={handleAddRegionToDb}
          onRemoveRegionFromDb={handleRemoveRegionFromDb}
          onCreateDb={handleCreateDb}
          onDropDb={handleDropDb}
          onSetSurvivalGoal={handleSetSurvivalGoal}
          onSetTableLocality={handleSetTableLocality}
          onToggleFeature={toggleFeature}
          onLoadScenario={handleLoadScenario}
        />
      </div>
    </div>
  )
}
