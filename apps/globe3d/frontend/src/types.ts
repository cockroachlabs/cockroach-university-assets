export type RegionId = 'us-east' | 'eu-west' | 'ap-southeast'

export interface RegionConfig {
  id: RegionId
  label: string
  city: string
  lat: number
  lng: number
  color: string
  nodes: number
}

export type SurvivalGoal = 'zone' | 'region'

export type TableLocality = 'regional-by-table' | 'regional-by-row' | 'global'

export interface DatabaseConfig {
  name: string
  primaryRegion: RegionId
  regions: RegionId[]
  survivalGoal: SurvivalGoal
}

export interface TableConfig {
  name: string
  locality: TableLocality
  regionalByRowColumn?: string
}

export interface ReplicaInfo {
  regionId: RegionId
  nodeIndex: number
  isVoting: boolean
  isLeaseholder: boolean
}

export interface ClusterStatus {
  hasQuorum: boolean
  message: string
  activePrimary: RegionId | null
}

export interface FeatureToggles {
  showLatency: boolean
  showReplicas: boolean
  showDataPackets: boolean
  showZoneConfigs: boolean
}

export const DEFAULT_FEATURE_TOGGLES: FeatureToggles = {
  showLatency: true,
  showReplicas: true,
  showDataPackets: true,
  showZoneConfigs: false,
}

export const REGIONS: RegionConfig[] = [
  {
    id: 'us-east',
    label: 'US-East',
    city: 'Virginia',
    lat: 37.43,
    lng: -79.1,
    color: '#60A5FA',
    nodes: 3,
  },
  {
    id: 'eu-west',
    label: 'EU-West',
    city: 'Ireland',
    lat: 53.14,
    lng: -7.6,
    color: '#34D399',
    nodes: 3,
  },
  {
    id: 'ap-southeast',
    label: 'AP-Southeast',
    city: 'Singapore',
    lat: 1.35,
    lng: 103.82,
    color: '#FBBF24',
    nodes: 3,
  },
]

export const LATENCIES: Record<string, number> = {
  'us-east:eu-west': 85,
  'us-east:ap-southeast': 180,
  'eu-west:ap-southeast': 140,
  'eu-west:us-east': 85,
  'ap-southeast:us-east': 180,
  'ap-southeast:eu-west': 140,
  'us-east:us-east': 2,
  'eu-west:eu-west': 2,
  'ap-southeast:ap-southeast': 2,
}

export interface ScenarioPreset {
  id: string
  name: string
  description: string
  icon: string
  dbConfig: DatabaseConfig
  tableLocality: TableLocality
  failedRegions: RegionId[]
}

export const SCENARIO_PRESETS: ScenarioPreset[] = [
  {
    id: 'us-multi-region',
    name: 'US Multi-Region',
    description: 'All 3 regions, zone survival, regional-by-table. Low-latency reads in the primary US region with follower reads elsewhere.',
    icon: 'US',
    dbConfig: {
      name: 'multi_region',
      primaryRegion: 'us-east',
      regions: ['us-east', 'eu-west', 'ap-southeast'],
      survivalGoal: 'zone',
    },
    tableLocality: 'regional-by-table',
    failedRegions: [],
  },
  {
    id: 'global-banking',
    name: 'Global Banking',
    description: 'All 3 regions, region survival, global tables. Non-blocking reads from any region — ideal for reference data like exchange rates.',
    icon: 'GL',
    dbConfig: {
      name: 'multi_region',
      primaryRegion: 'us-east',
      regions: ['us-east', 'eu-west', 'ap-southeast'],
      survivalGoal: 'region',
    },
    tableLocality: 'global',
    failedRegions: [],
  },
  {
    id: 'eu-compliance',
    name: 'EU Data Residency',
    description: 'EU-West as primary with regional-by-row. Each region owns its rows — EU data stays in EU, meeting GDPR residency requirements.',
    icon: 'EU',
    dbConfig: {
      name: 'multi_region',
      primaryRegion: 'eu-west',
      regions: ['eu-west', 'us-east', 'ap-southeast'],
      survivalGoal: 'zone',
    },
    tableLocality: 'regional-by-row',
    failedRegions: [],
  },
  {
    id: 'disaster-recovery',
    name: 'Disaster Recovery',
    description: 'Region survival with AP-Southeast killed. See how CockroachDB maintains quorum and migrates leaseholders during a region outage.',
    icon: 'DR',
    dbConfig: {
      name: 'multi_region',
      primaryRegion: 'us-east',
      regions: ['us-east', 'eu-west', 'ap-southeast'],
      survivalGoal: 'region',
    },
    tableLocality: 'regional-by-table',
    failedRegions: ['ap-southeast'],
  },
]

// --- Challenge Mode (Progressive Disclosure) ---

export interface ChallengeFeatures {
  createDatabase: boolean
  dropDatabase: boolean
  setPrimary: boolean
  addRegion: boolean
  removeRegion: boolean
  survivalGoal: 'none' | 'zone-only' | 'both'
  nodeKill: boolean
  regionKill: boolean
  tableLocality: boolean
  quickStartScenarios: boolean
}

export interface ChallengeMode {
  challenge: number
  features: ChallengeFeatures
}

export const CHALLENGE_LABELS: Record<number, string> = {
  1: 'Deploy & Explore',
  2: 'Configure Primary Region',
  3: 'Zone Survival',
  4: 'Region Survival',
  5: 'Table Locality Patterns',
  6: 'Chaos Engineering',
}

/** Convert lat/lng to 3D position on a unit sphere */
export function latLngToVector3(lat: number, lng: number, radius: number = 1): [number, number, number] {
  const phi = (90 - lat) * (Math.PI / 180)
  const theta = (lng + 180) * (Math.PI / 180)
  const x = -(radius * Math.sin(phi) * Math.cos(theta))
  const y = radius * Math.cos(phi)
  const z = radius * Math.sin(phi) * Math.sin(theta)
  return [x, y, z]
}
