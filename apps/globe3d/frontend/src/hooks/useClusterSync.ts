import { useState, useEffect, useCallback, useRef } from 'react'
import type { RegionId, SurvivalGoal, TableLocality, ChallengeMode } from '../types'

interface ClusterState {
  connected: boolean
  database: {
    name: string
    primaryRegion: string
    regions: string[]
    survivalGoal: string
    tableLocality: string
  } | null
}

interface ReplicaData {
  ranges: {
    rangeId: number
    replicas: number[]
    votingReplicas: number[]
    leaseHolder: number
  }[]
  nodeRegions: Record<string, string>
}

export interface TopologyNode {
  nodeId: number
  address: string
  locality: string
  isLive: boolean
  rangeCount?: number
  leaseCount?: number
  memoryUsageMB?: number
  uptimeSeconds?: number
}

export interface TopologyData {
  connected: boolean
  nodes: TopologyNode[]
  regions: Record<string, string[]>
  regionStatus?: Record<string, {
    region: string
    liveNodes: number
    deadNodes: number
    nodeIds: number[]
  }>
}

export interface DemoScenarioResult {
  status: string
  results: { index: number; sql: string; status: string; error?: string }[]
  total: number
}

async function apiCall<T>(path: string, options?: RequestInit): Promise<T | null> {
  try {
    const res = await fetch(`/api${path}`, {
      headers: { 'Content-Type': 'application/json' },
      ...options,
    })
    if (!res.ok) return null
    return await res.json()
  } catch {
    return null
  }
}

/**
 * Hook that syncs the Multi-Region Explorer with the real CockroachDB cluster.
 * Falls back gracefully to simulated mode when no backend is available.
 *
 * Provides:
 * - Cluster status polling
 * - Multi-region database operations
 * - Node-level kill/restart (real Docker operations)
 * - Region-level kill/restart (real Docker operations)
 * - Demo scenario SQL execution
 * - Real-time topology polling
 */
export function useClusterSync() {
  const [clusterConnected, setClusterConnected] = useState(false)
  const [replicaData, setReplicaData] = useState<ReplicaData | null>(null)
  const [topology, setTopology] = useState<TopologyData | null>(null)
  const [challengeMode, setChallengeMode] = useState<ChallengeMode | null>(null)
  const pollRef = useRef<ReturnType<typeof setInterval>>()

  // Check cluster status
  const checkStatus = useCallback(async () => {
    const status = await apiCall<ClusterState>('/multiregion/status')
    if (status) {
      setClusterConnected(status.connected)
    } else {
      setClusterConnected(false)
    }
    return status
  }, [])

  // Fetch replica distribution
  const fetchReplicas = useCallback(async () => {
    const data = await apiCall<ReplicaData>('/multiregion/replicas')
    if (data) setReplicaData(data)
  }, [])

  // Fetch cluster topology (node liveness, regions)
  const fetchTopology = useCallback(async () => {
    const data = await apiCall<TopologyData>('/cluster/topology')
    if (data) setTopology(data)
    return data
  }, [])

  // API actions — database management
  const createDatabase = useCallback(async (primaryRegion: string) => {
    await apiCall('/multiregion/database/create', {
      method: 'POST',
      body: JSON.stringify({ primaryRegion }),
    })
    await fetchReplicas()
  }, [fetchReplicas])

  const dropDatabase = useCallback(async () => {
    await apiCall('/multiregion/database/drop', { method: 'POST' })
    setReplicaData(null)
  }, [])

  const setPrimaryRegion = useCallback(async (region: string) => {
    await apiCall('/multiregion/database/primary-region', {
      method: 'POST',
      body: JSON.stringify({ region }),
    })
    await fetchReplicas()
  }, [fetchReplicas])

  const addRegion = useCallback(async (region: string) => {
    await apiCall('/multiregion/database/add-region', {
      method: 'POST',
      body: JSON.stringify({ region }),
    })
    await fetchReplicas()
  }, [fetchReplicas])

  const removeRegion = useCallback(async (region: string) => {
    await apiCall('/multiregion/database/remove-region', {
      method: 'POST',
      body: JSON.stringify({ region }),
    })
    await fetchReplicas()
  }, [fetchReplicas])

  const setSurvivalGoal = useCallback(async (goal: SurvivalGoal) => {
    await apiCall('/multiregion/database/survival-goal', {
      method: 'POST',
      body: JSON.stringify({ goal }),
    })
  }, [])

  const setTableLocality = useCallback(async (locality: TableLocality) => {
    await apiCall('/multiregion/table/locality', {
      method: 'POST',
      body: JSON.stringify({ locality }),
    })
    await fetchReplicas()
  }, [fetchReplicas])

  // Node-level operations (real Docker ops)
  const killNode = useCallback(async (nodeId: string) => {
    const result = await apiCall<{ status: string; nodeId: string }>(`/nodes/${nodeId}/kill`, {
      method: 'POST',
    })
    // Refresh topology after kill
    await fetchTopology()
    return result
  }, [fetchTopology])

  const restartNode = useCallback(async (nodeId: string) => {
    const result = await apiCall<{ status: string; nodeId: string }>(`/nodes/${nodeId}/restart`, {
      method: 'POST',
    })
    // Refresh topology after restart
    await fetchTopology()
    return result
  }, [fetchTopology])

  // Region-level operations (real Docker ops)
  const killRegion = useCallback(async (regionName: string) => {
    const result = await apiCall<{ status: string; region: string; killed: string[] }>(`/cluster/region/${regionName}/kill`, {
      method: 'POST',
    })
    await fetchTopology()
    return result
  }, [fetchTopology])

  const restartRegion = useCallback(async (regionName: string) => {
    const result = await apiCall<{ status: string; region: string; restarted: string[] }>(`/cluster/region/${regionName}/restart`, {
      method: 'POST',
    })
    await fetchTopology()
    return result
  }, [fetchTopology])

  // Demo scenario SQL execution
  const executeDemoScenario = useCallback(async (sql: string[]) => {
    return await apiCall<DemoScenarioResult>('/demos/scenario', {
      method: 'POST',
      body: JSON.stringify({ sql }),
    })
  }, [])

  // Fetch challenge mode
  const fetchChallengeMode = useCallback(async () => {
    const data = await apiCall<ChallengeMode>('/challenge/mode')
    if (data) setChallengeMode(data)
    return data
  }, [])

  // Fetch pre-built demo scenario SQL arrays
  const fetchDemoScenarios = useCallback(async () => {
    return await apiCall<{
      scenarios: Record<string, string[]>
    }>('/demos/globe-scenarios')
  }, [])

  // Poll for status, topology, replicas, and challenge mode
  useEffect(() => {
    checkStatus()
    fetchTopology()
    fetchChallengeMode()
    pollRef.current = setInterval(async () => {
      const status = await checkStatus()
      await fetchTopology()
      await fetchChallengeMode()
      if (status?.connected && status.database) {
        await fetchReplicas()
      }
    }, 5000)

    return () => {
      if (pollRef.current) clearInterval(pollRef.current)
    }
  }, [checkStatus, fetchReplicas, fetchTopology, fetchChallengeMode])

  // Map CockroachDB region names to our RegionId
  const mapRegionName = useCallback((crdbRegion: string): RegionId | null => {
    const mapping: Record<string, RegionId> = {
      'us-east1': 'us-east',
      'us-east': 'us-east',
      'europe-west1': 'eu-west',
      'eu-west': 'eu-west',
      'eu-west1': 'eu-west',
      'asia-southeast1': 'ap-southeast',
      'ap-southeast': 'ap-southeast',
      'ap-southeast1': 'ap-southeast',
    }
    return mapping[crdbRegion] ?? null
  }, [])

  return {
    clusterConnected,
    replicaData,
    topology,
    challengeMode,
    mapRegionName,
    actions: {
      createDatabase,
      dropDatabase,
      setPrimaryRegion,
      addRegion,
      removeRegion,
      setSurvivalGoal,
      setTableLocality,
      checkStatus,
      fetchReplicas,
      fetchTopology,
      killNode,
      restartNode,
      killRegion,
      restartRegion,
      executeDemoScenario,
      fetchDemoScenarios,
    },
  }
}
