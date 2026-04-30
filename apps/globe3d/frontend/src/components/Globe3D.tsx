import { useRef, useMemo, useState, useEffect } from 'react'
import { Canvas, useFrame } from '@react-three/fiber'
import { OrbitControls, Html, Line } from '@react-three/drei'
import * as THREE from 'three'
import * as topojson from 'topojson-client'
import landTopo from 'world-atlas/land-110m.json'
import type { RegionConfig, RegionId, DatabaseConfig, ReplicaInfo, FeatureToggles } from '../types'
import { latLngToVector3, LATENCIES } from '../types'

const GLOBE_RADIUS = 2

// ---------------------------------------------------------------------------
// Coastline data: convert TopoJSON -> GeoJSON -> 3D line segments
// ---------------------------------------------------------------------------

function extractCoastlines(radius: number): [number, number, number][][] {
  /* topojson.feature returns GeoJSON. We use `any` casts here because the
     world-atlas JSON shape doesn't perfectly match the library's generic
     overloads, but the runtime result is always valid GeoJSON. */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const topo = landTopo as any
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const geojson: any = topojson.feature(topo, topo.objects.land)

  const lines: [number, number, number][][] = []

  const processRing = (ring: number[][]) => {
    if (ring.length < 2) return
    const pts: [number, number, number][] = ring.map(([lng, lat]) =>
      latLngToVector3(lat, lng, radius),
    )
    lines.push(pts)
  }

  const processGeometry = (geom: { type: string; coordinates: number[][][][] | number[][][] }) => {
    if (geom.type === 'Polygon') {
      for (const ring of geom.coordinates as number[][][]) {
        processRing(ring)
      }
    } else if (geom.type === 'MultiPolygon') {
      for (const polygon of geom.coordinates as number[][][][]) {
        for (const ring of polygon) {
          processRing(ring)
        }
      }
    }
  }

  if (geojson.features) {
    for (const feat of geojson.features) {
      processGeometry(feat.geometry)
    }
  } else if (geojson.geometry) {
    processGeometry(geojson.geometry)
  }

  return lines
}

// ---------------------------------------------------------------------------
// Globe components
// ---------------------------------------------------------------------------

/** Faint latitude/longitude grid */
function GraticuleGrid() {
  const lines = useMemo(() => {
    const result: [number, number, number][][] = []

    // Latitude lines every 30 degrees
    for (let lat = -60; lat <= 60; lat += 30) {
      const ring: [number, number, number][] = []
      for (let lng = 0; lng <= 360; lng += 4) {
        ring.push(latLngToVector3(lat, lng - 180, GLOBE_RADIUS))
      }
      result.push(ring)
    }

    // Equator
    const equator: [number, number, number][] = []
    for (let lng = 0; lng <= 360; lng += 2) {
      equator.push(latLngToVector3(0, lng - 180, GLOBE_RADIUS))
    }
    result.push(equator)

    // Longitude lines every 30 degrees
    for (let lng = 0; lng < 360; lng += 30) {
      const meridian: [number, number, number][] = []
      for (let lat = -90; lat <= 90; lat += 4) {
        meridian.push(latLngToVector3(lat, lng - 180, GLOBE_RADIUS))
      }
      result.push(meridian)
    }

    return result
  }, [])

  return (
    <group>
      {lines.map((pts, i) => (
        <Line
          key={`grid-${i}`}
          points={pts}
          color="#1E3A5F"
          lineWidth={0.4}
          opacity={0.08}
          transparent
        />
      ))}
    </group>
  )
}

/** Coastline wireframe from Natural Earth data */
function Coastlines() {
  const coastlines = useMemo(() => extractCoastlines(GLOBE_RADIUS + 0.002), [])

  return (
    <group>
      {coastlines.map((pts, i) => (
        <Line
          key={`coast-${i}`}
          points={pts}
          color="#3B82F6"
          lineWidth={1}
          opacity={0.35}
          transparent
        />
      ))}
    </group>
  )
}

/** Compute positions for individual nodes spread around a region center */
function getNodePositions(lat: number, lng: number, count: number, radius: number): [number, number, number][] {
  if (count <= 1) return [latLngToVector3(lat, lng, radius)]
  const positions: [number, number, number][] = []
  const spread = 2.5 // degrees offset
  for (let i = 0; i < count; i++) {
    const angle = (i / count) * Math.PI * 2 - Math.PI / 2
    const offsetLat = lat + Math.sin(angle) * spread
    const offsetLng = lng + Math.cos(angle) * spread / Math.cos(lat * Math.PI / 180)
    positions.push(latLngToVector3(offsetLat, offsetLng, radius))
  }
  return positions
}

/** Individual node dot within a region */
function NodeDot({
  position,
  color,
  isFailed,
  replicas,
  nodeIndex,
}: {
  position: [number, number, number]
  color: string
  isFailed: boolean
  replicas: ReplicaInfo[]
  nodeIndex: number
}) {
  const meshRef = useRef<THREE.Mesh>(null)

  // Derive role from all replicas assigned to this node
  const isLeaseholder = replicas.some(r => r.isLeaseholder)
  const isVoting = replicas.some(r => r.isVoting)
  const isNonVoting = replicas.length > 0 && !isVoting

  // Badge text and color
  const badge = isLeaseholder
    ? { text: 'LH', color: '#FFD700', bg: 'rgba(255, 215, 0, 0.15)' }
    : isVoting
      ? { text: 'V', color, bg: 'rgba(255, 255, 255, 0.1)' }
      : isNonVoting
        ? { text: 'NV', color: '#9CA3AF', bg: 'rgba(255, 255, 255, 0.05)' }
        : null

  useFrame(({ clock }) => {
    if (meshRef.current && isLeaseholder && !isFailed) {
      const scale = 1 + Math.sin(clock.elapsedTime * 3 + nodeIndex) * 0.2
      meshRef.current.scale.setScalar(scale)
    }
  })

  const dotColor = isFailed ? '#EF4444' : color
  const size = isLeaseholder ? 0.04 : 0.03

  return (
    <group position={position}>
      {/* Node glow */}
      <mesh>
        <sphereGeometry args={[size * 2, 12, 12]} />
        <meshBasicMaterial color={dotColor} transparent opacity={isFailed ? 0.03 : 0.08} />
      </mesh>

      {/* Node core */}
      <mesh ref={meshRef}>
        <sphereGeometry args={[size, 12, 12]} />
        <meshBasicMaterial
          color={dotColor}
          transparent
          opacity={isFailed ? 0.15 : isNonVoting ? 0.4 : 0.85}
        />
      </mesh>

      {/* Non-voting ring indicator */}
      {isNonVoting && !isFailed && (
        <mesh rotation={[Math.PI / 2, 0, 0]}>
          <ringGeometry args={[size * 1.4, size * 1.7, 16]} />
          <meshBasicMaterial color={dotColor} transparent opacity={0.25} side={THREE.DoubleSide} />
        </mesh>
      )}

      {/* Leaseholder ring */}
      {isLeaseholder && !isFailed && (
        <mesh rotation={[Math.PI / 2, 0, 0]}>
          <ringGeometry args={[size * 1.8, size * 2.2, 24]} />
          <meshBasicMaterial color={dotColor} transparent opacity={0.5} side={THREE.DoubleSide} />
        </mesh>
      )}

      {/* Voting dot border */}
      {isVoting && !isLeaseholder && !isFailed && (
        <mesh rotation={[Math.PI / 2, 0, 0]}>
          <ringGeometry args={[size * 1.3, size * 1.5, 16]} />
          <meshBasicMaterial color={dotColor} transparent opacity={0.3} side={THREE.DoubleSide} />
        </mesh>
      )}

      {/* Text badge label */}
      {badge && !isFailed && (
        <Html
          center
          distanceFactor={6}
          style={{ pointerEvents: 'none' }}
        >
          <div
            className="text-[7px] font-bold px-1 rounded select-none whitespace-nowrap"
            style={{
              color: badge.color,
              backgroundColor: badge.bg,
              border: `1px solid ${badge.color}40`,
              transform: 'translateY(-10px)',
              textShadow: isLeaseholder ? `0 0 4px ${badge.color}` : 'none',
            }}
          >
            {badge.text}
          </div>
        </Html>
      )}

      {/* Failed region skull/X indicator */}
      {isFailed && (
        <Html
          center
          distanceFactor={6}
          style={{ pointerEvents: 'none' }}
        >
          <div
            className="text-[9px] font-bold select-none"
            style={{
              color: '#EF4444',
              transform: 'translateY(-10px)',
              textShadow: '0 0 6px rgba(239, 68, 68, 0.8)',
            }}
          >
            ✕
          </div>
        </Html>
      )}
    </group>
  )
}

/** Expanding pulse ring that plays once when replicas change */
function RedistributionPulse({
  position,
  color,
  trigger,
}: {
  position: [number, number, number]
  color: string
  trigger: number
}) {
  const ringRef = useRef<THREE.Mesh>(null)
  const matRef = useRef<THREE.MeshBasicMaterial>(null)
  const startTime = useRef(0)
  const active = useRef(false)

  useEffect(() => {
    if (trigger > 0) {
      startTime.current = performance.now() / 1000
      active.current = true
    }
  }, [trigger])

  useFrame(({ clock }) => {
    if (!active.current || !ringRef.current || !matRef.current) return
    const elapsed = clock.elapsedTime - startTime.current
    if (elapsed > 1.2) {
      active.current = false
      matRef.current.opacity = 0
      return
    }
    const t = elapsed / 1.2
    const scale = 1 + t * 3
    ringRef.current.scale.setScalar(scale)
    matRef.current.opacity = 0.6 * (1 - t)
  })

  return (
    <mesh ref={ringRef} position={position} rotation={[Math.PI / 2, 0, 0]}>
      <ringGeometry args={[0.08, 0.1, 32]} />
      <meshBasicMaterial ref={matRef} color={color} transparent opacity={0} side={THREE.DoubleSide} />
    </mesh>
  )
}

/** A glowing region marker on the globe surface with individual node dots */
function RegionMarker({
  region,
  isFailed,
  isPrimary,
  replicas,
  failedNodes,
  onClick,
}: {
  region: RegionConfig
  isFailed: boolean
  isPrimary: boolean
  replicas: ReplicaInfo[]
  failedNodes: Set<string>
  onClick: () => void
}) {
  const centerPos = useMemo(
    () => latLngToVector3(region.lat, region.lng, GLOBE_RADIUS + 0.05),
    [region.lat, region.lng],
  )

  const nodePositions = useMemo(
    () => getNodePositions(region.lat, region.lng, region.nodes, GLOBE_RADIUS + 0.05),
    [region.lat, region.lng, region.nodes],
  )

  const votingCount = replicas.filter(r => r.isVoting).length
  const nonVotingCount = replicas.filter(r => !r.isVoting).length
  const hasLeaseholder = replicas.some(r => r.isLeaseholder)

  const color = isFailed ? '#EF4444' : region.color

  // Track leaseholder arrival for gold migration pulse
  const hadLeaseholder = useRef(hasLeaseholder)
  const [lhArrived, setLhArrived] = useState(0)

  useEffect(() => {
    if (hasLeaseholder && !hadLeaseholder.current) {
      setLhArrived(c => c + 1) // trigger gold pulse
    }
    hadLeaseholder.current = hasLeaseholder
  }, [hasLeaseholder])

  // Track replica changes to trigger pulse animation
  const replicaSignature = useMemo(
    () => replicas.map(r => `${r.isVoting}:${r.isLeaseholder}`).join(','),
    [replicas],
  )
  const [pulseCount, setPulseCount] = useState(0)
  const prevSignature = useRef(replicaSignature)
  useEffect(() => {
    if (prevSignature.current !== replicaSignature && prevSignature.current !== '') {
      setPulseCount(c => c + 1)
    }
    prevSignature.current = replicaSignature
  }, [replicaSignature])

  // Map replicas to node positions (multiple replicas can land on the same node)
  const replicasByNode = useMemo(() => {
    const map = new Map<number, ReplicaInfo[]>()
    replicas.forEach((r, i) => {
      const nodeIdx = i % region.nodes
      const existing = map.get(nodeIdx) ?? []
      existing.push(r)
      map.set(nodeIdx, existing)
    })
    return map
  }, [replicas, region.nodes])

  return (
    <group>
      {/* Redistribution pulse */}
      <RedistributionPulse position={centerPos} color={color} trigger={pulseCount} />

      {/* Leaseholder migration gold pulse */}
      <RedistributionPulse position={centerPos} color="#FFD700" trigger={lhArrived} />

      {/* Clickable center area for setting primary */}
      <mesh position={centerPos} onClick={onClick}>
        <sphereGeometry args={[0.15, 8, 8]} />
        <meshBasicMaterial transparent opacity={0} />
      </mesh>

      {/* Primary region ring */}
      {isPrimary && !isFailed && (
        <mesh position={centerPos} rotation={[Math.PI / 2, 0, 0]}>
          <ringGeometry args={[0.16, 0.19, 32]} />
          <meshBasicMaterial color={color} transparent opacity={0.5} side={THREE.DoubleSide} />
        </mesh>
      )}

      {/* Individual node dots */}
      {nodePositions.map((pos, i) => (
        <NodeDot
          key={i}
          position={pos}
          color={color}
          isFailed={isFailed || failedNodes.has(`${region.id}:${i}`)}
          replicas={replicasByNode.get(i) ?? []}
          nodeIndex={i}
        />
      ))}

      {/* HTML label */}
      <Html
        position={[centerPos[0], centerPos[1] + 0.2, centerPos[2]]}
        center
        distanceFactor={6}
        style={{ pointerEvents: 'none' }}
      >
        <div
          className={`whitespace-nowrap text-center select-none ${isFailed ? 'opacity-30' : ''}`}
          style={{ transform: 'scale(0.8)' }}
        >
          <div
            className="text-[10px] font-bold tracking-wider uppercase"
            style={{ color }}
          >
            {region.label}
            {isPrimary && (
              <span className="ml-1 text-[8px] opacity-70">PRIMARY</span>
            )}
          </div>
          <div className="text-[8px] text-white/40 font-mono">
            {region.city} &middot; {region.nodes} nodes
          </div>
          {replicas.length > 0 && (
            <div className="flex items-center justify-center gap-1 mt-0.5">
              {votingCount > 0 && (
                <span className="text-[7px] px-1 rounded bg-white/10 text-white/60">
                  {votingCount}V
                </span>
              )}
              {nonVotingCount > 0 && (
                <span className="text-[7px] px-1 rounded bg-white/5 text-white/40">
                  {nonVotingCount}NV
                </span>
              )}
              {hasLeaseholder && (
                <span
                  className="text-[7px] px-1 rounded font-bold"
                  style={{ backgroundColor: color + '30', color }}
                >
                  LH
                </span>
              )}
            </div>
          )}
        </div>
      </Html>
    </group>
  )
}

/** A single animated data packet traveling along a curve */
function DataPacket({
  curvePath,
  color,
  speed,
  offset,
}: {
  curvePath: THREE.QuadraticBezierCurve3
  color: string
  speed: number
  offset: number
}) {
  const meshRef = useRef<THREE.Mesh>(null)
  const glowRef = useRef<THREE.Mesh>(null)

  useFrame(({ clock }) => {
    const t = ((clock.elapsedTime * speed + offset) % 1)
    const pos = curvePath.getPoint(t)
    if (meshRef.current) {
      meshRef.current.position.copy(pos)
    }
    if (glowRef.current) {
      glowRef.current.position.copy(pos)
      const pulse = 1 + Math.sin(clock.elapsedTime * 8) * 0.3
      glowRef.current.scale.setScalar(pulse)
    }
  })

  return (
    <group>
      {/* Glow */}
      <mesh ref={glowRef}>
        <sphereGeometry args={[0.04, 8, 8]} />
        <meshBasicMaterial color={color} transparent opacity={0.2} />
      </mesh>
      {/* Core */}
      <mesh ref={meshRef}>
        <sphereGeometry args={[0.018, 8, 8]} />
        <meshBasicMaterial color={color} transparent opacity={0.9} />
      </mesh>
    </group>
  )
}

/** Animated arc between two regions with data packets */
function ReplicationArc({
  from,
  to,
  color,
  showLatency,
  showDataPackets = true,
}: {
  from: RegionConfig
  to: RegionConfig
  color: string
  showLatency: boolean
  showDataPackets?: boolean
}) {
  const { curvePoints, curvePath } = useMemo(() => {
    const start = new THREE.Vector3(...latLngToVector3(from.lat, from.lng, GLOBE_RADIUS + 0.05))
    const end = new THREE.Vector3(...latLngToVector3(to.lat, to.lng, GLOBE_RADIUS + 0.05))

    const mid = new THREE.Vector3().addVectors(start, end).multiplyScalar(0.5)
    const midLen = mid.length()
    const arcHeight = start.distanceTo(end) * 0.4
    mid.multiplyScalar((GLOBE_RADIUS + 0.05 + arcHeight) / midLen)

    const path = new THREE.QuadraticBezierCurve3(start, mid, end)
    const pts = path.getPoints(50).map(p => [p.x, p.y, p.z] as [number, number, number])
    return { curvePoints: pts, curvePath: path }
  }, [from, to])

  const latencyKey = `${from.id}:${to.id}`
  const latency = LATENCIES[latencyKey] ?? 0

  const midPoint = useMemo(() => {
    const midIdx = Math.floor(curvePoints.length / 2)
    return curvePoints[midIdx]
  }, [curvePoints])

  // Speed inversely proportional to latency (higher latency = slower packets)
  const packetSpeed = latency > 100 ? 0.15 : latency > 50 ? 0.25 : 0.35

  return (
    <group>
      {/* Arc line */}
      <Line points={curvePoints} color={color} lineWidth={1.5} opacity={0.3} transparent />

      {/* Data packets traveling forward (from -> to) */}
      {showDataPackets && (
        <>
          <DataPacket curvePath={curvePath} color={color} speed={packetSpeed} offset={0} />
          <DataPacket curvePath={curvePath} color={color} speed={packetSpeed} offset={0.5} />
        </>
      )}

      {/* Latency label */}
      {showLatency && midPoint && (
        <Html position={midPoint} center distanceFactor={6} style={{ pointerEvents: 'none' }}>
          <div
            className="text-[8px] font-mono px-1.5 py-0.5 rounded-full border whitespace-nowrap"
            style={{
              color,
              borderColor: color + '40',
              backgroundColor: 'rgba(6, 9, 16, 0.8)',
            }}
          >
            {latency}ms
          </div>
        </Html>
      )}
    </group>
  )
}

/** Main 3D scene contents */
function Scene({
  regions,
  failedRegions,
  failedNodes,
  hasQuorum,
  dbConfig,
  replicas,
  featureToggles,
  onRegionClick,
}: {
  regions: RegionConfig[]
  failedRegions: Set<RegionId>
  failedNodes: Set<string>
  hasQuorum: boolean
  dbConfig: DatabaseConfig | null
  replicas: ReplicaInfo[]
  featureToggles: FeatureToggles
  onRegionClick: (id: RegionId) => void
}) {
  const groupRef = useRef<THREE.Group>(null)

  // Slow rotation
  useFrame(() => {
    if (groupRef.current) {
      groupRef.current.rotation.y += 0.001
    }
  })

  // Build arcs between active (non-failed) regions that have replicas
  const activeRegionIds = regions
    .filter(r => !failedRegions.has(r.id))
    .filter(r => replicas.some(rep => rep.regionId === r.id))
    .map(r => r.id)

  const arcs: { from: RegionConfig; to: RegionConfig }[] = []
  for (let i = 0; i < activeRegionIds.length; i++) {
    for (let j = i + 1; j < activeRegionIds.length; j++) {
      const fromR = regions.find(r => r.id === activeRegionIds[i])!
      const toR = regions.find(r => r.id === activeRegionIds[j])!
      arcs.push({ from: fromR, to: toR })
    }
  }

  return (
    <>
      <ambientLight intensity={0.3} />
      <pointLight position={[10, 10, 10]} intensity={0.5} />

      <group ref={groupRef}>
        {/* Faint graticule grid (behind coastlines) */}
        <GraticuleGrid />

        {/* Continent coastlines */}
        <Coastlines />

        {/* Region markers */}
        {regions.map(region => (
          <RegionMarker
            key={region.id}
            region={region}
            isFailed={failedRegions.has(region.id)}
            isPrimary={dbConfig?.primaryRegion === region.id}
            replicas={featureToggles.showReplicas ? replicas.filter(r => r.regionId === region.id) : []}
            failedNodes={failedNodes}
            onClick={() => onRegionClick(region.id)}
          />
        ))}

        {/* Replication arcs — hidden when quorum is lost (DB is down) */}
        {hasQuorum && arcs.map(({ from, to }) => (
          <ReplicationArc
            key={`${from.id}-${to.id}`}
            from={from}
            to={to}
            color={dbConfig?.primaryRegion === from.id ? from.color : to.color}
            showLatency={featureToggles.showLatency}
            showDataPackets={featureToggles.showDataPackets}
          />
        ))}

        {/* Quorum-lost overlay */}
        {!hasQuorum && dbConfig && (
          <Html center position={[0, -0.3, 0]} distanceFactor={4} style={{ pointerEvents: 'none' }}>
            <div className="text-center animate-pulse">
              <div className="text-red-500 text-sm font-bold tracking-widest uppercase mb-1" style={{ textShadow: '0 0 20px rgba(239,68,68,0.6)' }}>
                DATABASE UNAVAILABLE
              </div>
              <div className="text-red-400/60 text-[10px] font-mono">
                Quorum lost — insufficient voters
              </div>
            </div>
          </Html>
        )}
      </group>

      <OrbitControls
        enablePan={false}
        enableZoom={true}
        minDistance={3}
        maxDistance={8}
        autoRotate={false}
        makeDefault
      />
    </>
  )
}

export default function Globe3D({
  regions,
  failedRegions,
  failedNodes,
  hasQuorum,
  dbConfig,
  replicas,
  featureToggles,
  onRegionClick,
}: {
  regions: RegionConfig[]
  failedRegions: Set<RegionId>
  failedNodes: Set<string>
  hasQuorum: boolean
  dbConfig: DatabaseConfig | null
  replicas: ReplicaInfo[]
  featureToggles: FeatureToggles
  onRegionClick: (id: RegionId) => void
}) {
  return (
    <div className="globe-canvas w-full h-full">
      <Canvas
        camera={{ position: [0, 1.5, 5], fov: 45 }}
        style={{ background: 'transparent' }}
      >
        <Scene
          regions={regions}
          failedRegions={failedRegions}
          failedNodes={failedNodes}
          hasQuorum={hasQuorum}
          dbConfig={dbConfig}
          replicas={replicas}
          featureToggles={featureToggles}
          onRegionClick={onRegionClick}
        />
      </Canvas>
    </div>
  )
}
