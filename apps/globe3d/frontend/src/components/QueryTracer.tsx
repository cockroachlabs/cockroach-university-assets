import { useState, useMemo, useCallback, useEffect, useRef } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import type { RegionId, DatabaseConfig, ReplicaInfo } from '../types'
import { REGIONS, LATENCIES } from '../types'

type QueryType = 'leaseholder-read' | 'follower-read' | 'write'

interface TraceStep {
  from: RegionId
  to: RegionId
  label: string
  latencyMs: number
}

interface TraceResult {
  queryType: QueryType
  origin: RegionId
  steps: TraceStep[]
  totalLatency: number
}

/* ─── helpers ─── */
const getLatency = (a: RegionId, b: RegionId) => LATENCIES[`${a}:${b}`] ?? 0

function regionLabel(id: RegionId): string {
  return REGIONS.find(r => r.id === id)?.label ?? id
}

function regionColor(id: RegionId): string {
  return REGIONS.find(r => r.id === id)?.color ?? '#fff'
}

function latencyColor(ms: number): string {
  if (ms <= 10) return '#34D399'   // green
  if (ms <= 100) return '#FBBF24'  // amber
  return '#EF4444'                 // red
}

/* ─── trace computation ─── */
function computeTrace(
  queryType: QueryType,
  origin: RegionId,
  _dbConfig: DatabaseConfig,
  replicas: ReplicaInfo[],
  failedRegions: Set<RegionId>,
): TraceResult | null {
  const isDown = (r: RegionId) => failedRegions.has(r)

  const lhReplica = replicas.find(r => r.isLeaseholder && !isDown(r.regionId))
  if (!lhReplica) return null
  const lhRegion = lhReplica.regionId

  const votingRegions = [...new Set(
    replicas
      .filter(r => r.isVoting && !r.isLeaseholder && !isDown(r.regionId))
      .map(r => r.regionId)
  )]

  const steps: TraceStep[] = []

  switch (queryType) {
    case 'leaseholder-read': {
      const toLH = getLatency(origin, lhRegion)
      steps.push({
        from: origin,
        to: lhRegion,
        label: origin === lhRegion ? 'Local leaseholder read' : `Client \u2192 Leaseholder (${regionLabel(lhRegion)})`,
        latencyMs: toLH || 2,
      })
      if (origin !== lhRegion) {
        steps.push({
          from: lhRegion,
          to: origin,
          label: 'Response \u2192 Client',
          latencyMs: toLH,
        })
      }
      break
    }

    case 'follower-read': {
      // Check if there's a non-voting replica in the origin region
      const localNV = replicas.find(r => !r.isVoting && r.regionId === origin && !isDown(r.regionId))
      const localVoting = replicas.find(r => r.regionId === origin && !isDown(r.regionId))

      if (localNV || (localVoting && origin === lhRegion)) {
        // Can serve locally
        steps.push({
          from: origin,
          to: origin,
          label: 'Follower read from local replica',
          latencyMs: 2,
        })
      } else {
        // Fallback: go to nearest region with a replica
        const replicaRegions = [...new Set(replicas.filter(r => !isDown(r.regionId)).map(r => r.regionId))]
        const nearest = replicaRegions.sort((a, b) => getLatency(origin, a) - getLatency(origin, b))[0]
        if (!nearest) return null
        const lat = getLatency(origin, nearest)
        steps.push({
          from: origin,
          to: nearest,
          label: `Client \u2192 Nearest replica (${regionLabel(nearest)})`,
          latencyMs: lat || 2,
        })
        steps.push({
          from: nearest,
          to: origin,
          label: 'Response \u2192 Client',
          latencyMs: lat,
        })
      }
      break
    }

    case 'write': {
      // Step 1: Client -> Leaseholder
      const toLH = getLatency(origin, lhRegion)
      steps.push({
        from: origin,
        to: lhRegion,
        label: origin === lhRegion ? 'Write to local leaseholder' : `Client \u2192 Leaseholder (${regionLabel(lhRegion)})`,
        latencyMs: toLH || 2,
      })

      // Step 2: Raft consensus fan-out to voting replicas
      if (votingRegions.length > 0) {
        const sortedByLatency = votingRegions
          .map(r => ({ region: r, lat: getLatency(lhRegion, r) }))
          .sort((a, b) => a.lat - b.lat)

        // Need majority: LH + fastest replica(s)
        const quorumTarget = sortedByLatency[0]
        steps.push({
          from: lhRegion,
          to: quorumTarget.region,
          label: `Raft consensus \u2192 ${regionLabel(quorumTarget.region)}`,
          latencyMs: quorumTarget.lat || 2,
        })
        steps.push({
          from: quorumTarget.region,
          to: lhRegion,
          label: 'Raft ACK \u2192 Leaseholder',
          latencyMs: quorumTarget.lat || 2,
        })
      }

      // Step 3: Response back to client
      if (origin !== lhRegion) {
        steps.push({
          from: lhRegion,
          to: origin,
          label: 'Response \u2192 Client',
          latencyMs: toLH,
        })
      }
      break
    }
  }

  const totalLatency = steps.reduce((acc, s) => acc + s.latencyMs, 0)
  return { queryType, origin, steps, totalLatency }
}

/* ─── animated packet ─── */
function AnimatedPacket({
  steps,
  queryType,
  onComplete,
}: {
  steps: TraceStep[]
  queryType: QueryType
  onComplete: () => void
}) {
  const [currentStep, setCurrentStep] = useState(0)
  const [elapsedMs, setElapsedMs] = useState(0)
  const rafRef = useRef<number>(0)
  const startTimeRef = useRef(Date.now())

  const totalDuration = steps.reduce((acc, s) => acc + s.latencyMs, 0)

  // Animate the elapsed counter
  useEffect(() => {
    startTimeRef.current = Date.now()
    const tick = () => {
      const now = Date.now()
      const elapsed = now - startTimeRef.current
      // Scale: 1ms of latency = 15ms of animation time
      const simMs = elapsed / 15
      setElapsedMs(Math.min(Math.round(simMs), totalDuration))
      if (simMs < totalDuration) {
        rafRef.current = requestAnimationFrame(tick)
      }
    }
    rafRef.current = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(rafRef.current)
  }, [totalDuration])

  // Step through animation
  useEffect(() => {
    if (currentStep >= steps.length) {
      const timer = setTimeout(onComplete, 800)
      return () => clearTimeout(timer)
    }
    const stepDuration = steps[currentStep].latencyMs * 15 // scale factor
    const timer = setTimeout(() => {
      setCurrentStep(prev => prev + 1)
    }, Math.max(stepDuration, 200))
    return () => clearTimeout(timer)
  }, [currentStep, steps, onComplete])

  const packetColor = queryType === 'write' ? '#f97316' : '#06b6d4'

  // Region positions for 2D layout (matching the card layout)
  const regionPositions: Record<RegionId, { x: number; y: number }> = {
    'us-east': { x: 80, y: 100 },
    'eu-west': { x: 240, y: 60 },
    'ap-southeast': { x: 400, y: 120 },
  }

  return (
    <div className="relative">
      {/* Latency counter */}
      <div className="flex items-center justify-center gap-3 mb-4">
        <motion.div
          className="text-3xl font-mono font-black tabular-nums"
          style={{ color: latencyColor(elapsedMs) }}
          animate={{ scale: [1, 1.02, 1] }}
          transition={{ duration: 0.3, repeat: Infinity }}
        >
          {elapsedMs}
          <span className="text-lg ml-1 opacity-60">ms</span>
        </motion.div>
      </div>

      {/* SVG animation canvas */}
      <svg viewBox="0 0 480 180" className="w-full h-32">
        {/* Region nodes */}
        {REGIONS.map(region => {
          const pos = regionPositions[region.id]
          const isActive = steps.some(s => s.from === region.id || s.to === region.id)
          return (
            <g key={region.id}>
              {/* Glow */}
              {isActive && (
                <circle cx={pos.x} cy={pos.y} r={22} fill={regionColor(region.id)} opacity={0.1} />
              )}
              <circle
                cx={pos.x}
                cy={pos.y}
                r={16}
                fill="rgba(255,255,255,0.05)"
                stroke={regionColor(region.id)}
                strokeWidth={isActive ? 2 : 1}
                opacity={isActive ? 1 : 0.4}
              />
              <text
                x={pos.x}
                y={pos.y + 1}
                textAnchor="middle"
                dominantBaseline="middle"
                className="text-[8px] font-bold"
                fill={regionColor(region.id)}
              >
                {region.label.split('-')[0]}
              </text>
              <text
                x={pos.x}
                y={pos.y + 30}
                textAnchor="middle"
                className="text-[7px]"
                fill="rgba(255,255,255,0.3)"
              >
                {region.city}
              </text>
            </g>
          )
        })}

        {/* Path lines */}
        {steps.map((step, i) => {
          const from = regionPositions[step.from]
          const to = regionPositions[step.to]
          if (step.from === step.to) return null
          const isCompleted = i < currentStep
          const isCurrent = i === currentStep
          return (
            <g key={i}>
              <line
                x1={from.x}
                y1={from.y}
                x2={to.x}
                y2={to.y}
                stroke={isCompleted ? packetColor : isCurrent ? packetColor : 'rgba(255,255,255,0.08)'}
                strokeWidth={isCurrent ? 2 : 1}
                strokeDasharray={isCompleted ? 'none' : '4 4'}
                opacity={isCompleted ? 0.6 : isCurrent ? 1 : 0.3}
              />
              {/* Latency label on path */}
              {(isCompleted || isCurrent) && (
                <text
                  x={(from.x + to.x) / 2}
                  y={(from.y + to.y) / 2 - 8}
                  textAnchor="middle"
                  className="text-[7px] font-mono"
                  fill={packetColor}
                  opacity={0.8}
                >
                  {step.latencyMs}ms
                </text>
              )}
            </g>
          )
        })}

        {/* Animated packet dot */}
        {currentStep < steps.length && (() => {
          const step = steps[currentStep]
          const from = regionPositions[step.from]
          const to = regionPositions[step.to]
          if (step.from === step.to) {
            // Local operation: pulse at location
            return (
              <motion.circle
                cx={from.x}
                cy={from.y}
                r={6}
                fill={packetColor}
                animate={{
                  r: [6, 10, 6],
                  opacity: [1, 0.5, 1],
                }}
                transition={{ duration: 0.6, repeat: Infinity }}
                filter="url(#glow)"
              />
            )
          }
          return (
            <motion.circle
              cx={from.x}
              cy={from.y}
              r={5}
              fill={packetColor}
              animate={{
                cx: to.x,
                cy: to.y,
              }}
              transition={{
                duration: Math.max(step.latencyMs * 0.015, 0.2),
                ease: 'easeInOut',
              }}
              filter="url(#glow)"
            />
          )
        })()}

        {/* Glow filter */}
        <defs>
          <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="3" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>
      </svg>

      {/* Step log */}
      <div className="mt-2 space-y-1">
        {steps.map((step, i) => {
          const isCompleted = i < currentStep
          const isCurrent = i === currentStep
          return (
            <motion.div
              key={i}
              className={`flex items-center gap-2 px-2 py-1 rounded text-[9px] font-mono transition-colors ${
                isCompleted
                  ? 'bg-white/5 text-white/50'
                  : isCurrent
                    ? 'bg-white/8 text-white/80'
                    : 'text-white/20'
              }`}
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: i * 0.1 }}
            >
              <div
                className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${
                  isCompleted ? 'bg-emerald-400' : isCurrent ? 'bg-white animate-pulse' : 'bg-white/10'
                }`}
              />
              <span className="flex-1 truncate">{step.label}</span>
              <span className="flex-shrink-0" style={{ color: latencyColor(step.latencyMs) }}>
                +{step.latencyMs}ms
              </span>
            </motion.div>
          )
        })}
      </div>
    </div>
  )
}

/* ─── comparison bar ─── */
function ComparisonBar({
  origin,
  dbConfig,
  replicas,
  failedRegions,
}: {
  origin: RegionId
  dbConfig: DatabaseConfig
  replicas: ReplicaInfo[]
  failedRegions: Set<RegionId>
}) {
  const results = useMemo(() => {
    const types: QueryType[] = ['leaseholder-read', 'follower-read', 'write']
    return types.map(qt => ({
      type: qt,
      trace: computeTrace(qt, origin, dbConfig, replicas, failedRegions),
    }))
  }, [origin, dbConfig, replicas, failedRegions])

  const maxLat = Math.max(...results.map(r => r.trace?.totalLatency ?? 0), 1)

  const labels: Record<QueryType, string> = {
    'leaseholder-read': 'Leaseholder Read',
    'follower-read': 'Follower Read',
    'write': 'Write',
  }

  const colors: Record<QueryType, string> = {
    'leaseholder-read': '#06b6d4',
    'follower-read': '#34D399',
    'write': '#f97316',
  }

  return (
    <div className="mt-3 pt-3 border-t border-white/5">
      <div className="text-[8px] font-bold uppercase tracking-widest text-white/30 mb-2">
        Latency Comparison from {regionLabel(origin)}
      </div>
      <div className="space-y-1.5">
        {results.map(({ type, trace }) => {
          if (!trace) return null
          const pct = Math.max(4, (trace.totalLatency / maxLat) * 100)
          return (
            <div key={type} className="flex items-center gap-2">
              <span className="text-[8px] font-medium w-24 text-white/50 truncate">
                {labels[type]}
              </span>
              <div className="flex-1 h-3 rounded-full bg-white/5 overflow-hidden">
                <motion.div
                  className="h-full rounded-full"
                  style={{ backgroundColor: colors[type] }}
                  initial={{ width: 0 }}
                  animate={{ width: `${pct}%` }}
                  transition={{ duration: 0.6, ease: 'easeOut' }}
                />
              </div>
              <span
                className="text-[10px] font-mono font-bold w-12 text-right"
                style={{ color: latencyColor(trace.totalLatency) }}
              >
                {trace.totalLatency}ms
              </span>
            </div>
          )
        })}
      </div>
    </div>
  )
}

/* ─── main component ─── */
export default function QueryTracer({
  dbConfig,
  replicas,
  failedRegions,
}: {
  dbConfig: DatabaseConfig | null
  replicas: ReplicaInfo[]
  failedRegions: Set<RegionId>
}) {
  const [isOpen, setIsOpen] = useState(false)
  const [queryType, setQueryType] = useState<QueryType>('leaseholder-read')
  const [origin, setOrigin] = useState<RegionId>('us-east')
  const [isTracing, setIsTracing] = useState(false)
  const [traceResult, setTraceResult] = useState<TraceResult | null>(null)

  const activeRegions = useMemo(
    () => REGIONS.filter(r => !failedRegions.has(r.id)),
    [failedRegions],
  )

  // Reset origin if it becomes failed
  useEffect(() => {
    if (failedRegions.has(origin) && activeRegions.length > 0) {
      setOrigin(activeRegions[0].id)
    }
  }, [failedRegions, origin, activeRegions])

  const handleTrace = useCallback(() => {
    if (!dbConfig) return
    const result = computeTrace(queryType, origin, dbConfig, replicas, failedRegions)
    if (result) {
      setTraceResult(result)
      setIsTracing(true)
    }
  }, [queryType, origin, dbConfig, replicas, failedRegions])

  const handleAnimationComplete = useCallback(() => {
    setIsTracing(false)
  }, [])

  if (!dbConfig) return null

  const queryTypes: { id: QueryType; label: string; color: string; desc: string }[] = [
    { id: 'leaseholder-read', label: 'Leaseholder Read', color: '#06b6d4', desc: 'Read via leaseholder' },
    { id: 'follower-read', label: 'Follower Read', color: '#34D399', desc: 'Read from nearest replica' },
    { id: 'write', label: 'Write', color: '#f97316', desc: 'Write with Raft consensus' },
  ]

  return (
    <>
      {/* Floating trigger button */}
      <motion.button
        className="absolute top-4 right-4 z-10 flex items-center gap-2 px-3 py-2 rounded-lg
          bg-cyan-500/10 border border-cyan-500/30 text-cyan-400 text-xs font-bold
          hover:bg-cyan-500/20 hover:border-cyan-500/50 transition-colors backdrop-blur-sm"
        onClick={() => setIsOpen(true)}
        whileHover={{ scale: 1.03 }}
        whileTap={{ scale: 0.97 }}
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
          <path d="M2 12h5l3-9 4 18 3-9h5" />
        </svg>
        Trace Query
      </motion.button>

      {/* Overlay panel */}
      <AnimatePresence>
        {isOpen && (
          <motion.div
            className="absolute inset-0 z-20 flex items-center justify-center"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            {/* Backdrop */}
            <div
              className="absolute inset-0 bg-black/60 backdrop-blur-sm"
              onClick={() => { setIsOpen(false); setIsTracing(false); setTraceResult(null) }}
            />

            {/* Panel */}
            <motion.div
              className="relative w-[520px] max-h-[90%] overflow-y-auto rounded-xl border border-crdb-border
                bg-crdb-darker/95 backdrop-blur-md shadow-2xl shadow-black/50"
              initial={{ scale: 0.9, y: 20 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.9, y: 20 }}
              transition={{ type: 'spring', damping: 25, stiffness: 300 }}
            >
              {/* Header */}
              <div className="flex items-center justify-between px-5 py-4 border-b border-crdb-border">
                <div>
                  <h3 className="text-sm font-bold text-white/90 flex items-center gap-2">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#06b6d4" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M2 12h5l3-9 4 18 3-9h5" />
                    </svg>
                    Query Path Tracer
                  </h3>
                  <p className="text-[10px] text-white/40 mt-0.5">
                    Visualize how queries travel across regions
                  </p>
                </div>
                <button
                  className="w-7 h-7 flex items-center justify-center rounded-md text-white/30 hover:text-white/70 hover:bg-white/5 transition-all"
                  onClick={() => { setIsOpen(false); setIsTracing(false); setTraceResult(null) }}
                  title="Close"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="18" y1="6" x2="6" y2="18" />
                    <line x1="6" y1="6" x2="18" y2="18" />
                  </svg>
                </button>
              </div>

              <div className="px-5 py-4 space-y-4">
                {/* Query type selector */}
                <div>
                  <div className="text-[9px] font-bold uppercase tracking-widest text-white/30 mb-2">
                    Query Type
                  </div>
                  <div className="grid grid-cols-3 gap-2">
                    {queryTypes.map(qt => (
                      <button
                        key={qt.id}
                        className={`text-left p-2.5 rounded-lg border transition-all ${
                          queryType === qt.id
                            ? 'border-opacity-50 bg-opacity-10'
                            : 'border-white/5 bg-white/[0.02] hover:bg-white/5'
                        }`}
                        style={queryType === qt.id ? {
                          borderColor: qt.color + '80',
                          backgroundColor: qt.color + '15',
                        } : undefined}
                        onClick={() => { setQueryType(qt.id); setIsTracing(false) }}
                      >
                        <div
                          className="text-[10px] font-bold mb-0.5"
                          style={{ color: queryType === qt.id ? qt.color : 'rgba(255,255,255,0.5)' }}
                        >
                          {qt.label}
                        </div>
                        <div className="text-[8px] text-white/25">{qt.desc}</div>
                      </button>
                    ))}
                  </div>
                </div>

                {/* Origin region selector */}
                <div>
                  <div className="text-[9px] font-bold uppercase tracking-widest text-white/30 mb-2">
                    Client Region (Origin)
                  </div>
                  <div className="flex gap-2">
                    {activeRegions.map(region => (
                      <button
                        key={region.id}
                        className={`flex-1 flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg border transition-all ${
                          origin === region.id
                            ? 'border-opacity-40'
                            : 'border-white/5 bg-white/[0.02] hover:bg-white/5'
                        }`}
                        style={origin === region.id ? {
                          borderColor: region.color + '60',
                          backgroundColor: region.color + '12',
                        } : undefined}
                        onClick={() => { setOrigin(region.id); setIsTracing(false) }}
                      >
                        <div
                          className="w-2 h-2 rounded-full"
                          style={{ backgroundColor: region.color }}
                        />
                        <span
                          className="text-[10px] font-bold"
                          style={{ color: origin === region.id ? region.color : 'rgba(255,255,255,0.4)' }}
                        >
                          {region.label}
                        </span>
                      </button>
                    ))}
                  </div>
                </div>

                {/* Trace button */}
                <motion.button
                  className="w-full py-2.5 rounded-lg text-xs font-bold transition-colors"
                  style={{
                    backgroundColor: (queryType === 'write' ? '#f97316' : '#06b6d4') + '18',
                    color: queryType === 'write' ? '#f97316' : '#06b6d4',
                    border: `1px solid ${(queryType === 'write' ? '#f97316' : '#06b6d4')}40`,
                  }}
                  onClick={handleTrace}
                  whileTap={{ scale: 0.97 }}
                  disabled={isTracing}
                >
                  {isTracing ? 'Tracing...' : 'Run Trace'}
                </motion.button>

                {/* Animation area */}
                <AnimatePresence mode="wait">
                  {traceResult && (
                    <motion.div
                      key={`${traceResult.queryType}-${traceResult.origin}-${Date.now()}`}
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -10 }}
                      className="rounded-lg border border-crdb-border bg-black/30 p-4"
                    >
                      {isTracing ? (
                        <AnimatedPacket
                          steps={traceResult.steps}
                          queryType={traceResult.queryType}
                          onComplete={handleAnimationComplete}
                        />
                      ) : (
                        <div>
                          {/* Static result */}
                          <div className="flex items-center justify-center gap-3 mb-3">
                            <div
                              className="text-3xl font-mono font-black"
                              style={{ color: latencyColor(traceResult.totalLatency) }}
                            >
                              {traceResult.totalLatency}
                              <span className="text-lg ml-1 opacity-60">ms</span>
                            </div>
                            <div className="text-[9px] text-white/40">
                              total round-trip
                            </div>
                          </div>

                          {/* Step summary */}
                          <div className="space-y-1">
                            {traceResult.steps.map((step, i) => (
                              <div key={i} className="flex items-center gap-2 px-2 py-1 rounded bg-white/5 text-[9px] font-mono text-white/50">
                                <div className="w-1.5 h-1.5 rounded-full bg-emerald-400 flex-shrink-0" />
                                <span className="flex-1 truncate">{step.label}</span>
                                <span style={{ color: latencyColor(step.latencyMs) }}>+{step.latencyMs}ms</span>
                              </div>
                            ))}
                          </div>

                          {/* Comparison bar */}
                          <ComparisonBar
                            origin={origin}
                            dbConfig={dbConfig}
                            replicas={replicas}
                            failedRegions={failedRegions}
                          />
                        </div>
                      )}
                    </motion.div>
                  )}
                </AnimatePresence>

                {/* Teaching note */}
                {!traceResult && (
                  <div className="text-[9px] text-white/25 leading-relaxed p-3 rounded-lg bg-white/[0.02] border border-white/5">
                    <strong className="text-white/40">How it works:</strong>{' '}
                    Select a query type and client region, then hit "Run Trace" to see the
                    packet travel across regions with real latency estimates. Compare
                    leaseholder reads vs. follower reads to see the dramatic difference
                    in latency.
                  </div>
                )}
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  )
}
