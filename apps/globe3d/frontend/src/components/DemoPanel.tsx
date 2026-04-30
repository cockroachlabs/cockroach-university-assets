import { useState, useCallback } from 'react'
import { motion, AnimatePresence } from 'framer-motion'

interface DemoScenario {
  id: string
  name: string
  description: string
  icon: string
  color: string
  sql: string[]
  nextSteps: string
}

const FAILURE_DEMOS: DemoScenario[] = [
  {
    id: 'regional-by-table',
    name: 'Regional by Table',
    description: 'Pins all voting replicas in the primary region. Low-latency reads in primary, but losing the primary means losing quorum.',
    icon: 'RT',
    color: '#60A5FA',
    sql: [
      'CREATE DATABASE IF NOT EXISTS demo_regional',
      'ALTER DATABASE demo_regional SET PRIMARY REGION "us-east"',
      'ALTER DATABASE demo_regional ADD REGION IF NOT EXISTS "us-central"',
      'ALTER DATABASE demo_regional ADD REGION IF NOT EXISTS "us-west"',
      'CREATE TABLE IF NOT EXISTS demo_regional.users (id INT PRIMARY KEY, name STRING, email STRING)',
      'ALTER TABLE demo_regional.users SET LOCALITY REGIONAL BY TABLE IN PRIMARY REGION',
      "INSERT INTO demo_regional.users VALUES (1, 'Alice', 'alice@example.com'), (2, 'Bob', 'bob@example.com') ON CONFLICT (id) DO NOTHING",
    ],
    nextSteps: 'Kill the us-east region from the globe to see quorum lost. Restart it to recover.',
  },
  {
    id: 'regional-by-row',
    name: 'Regional by Row',
    description: 'Each row is homed in a specific region based on a computed column. Distributed leaseholders for low-latency local writes.',
    icon: 'RR',
    color: '#34D399',
    sql: [
      'CREATE DATABASE IF NOT EXISTS demo_row',
      'ALTER DATABASE demo_row SET PRIMARY REGION "us-east"',
      'ALTER DATABASE demo_row ADD REGION IF NOT EXISTS "us-central"',
      'ALTER DATABASE demo_row ADD REGION IF NOT EXISTS "us-west"',
      "CREATE TABLE IF NOT EXISTS demo_row.orders (id INT, region crdb_internal_region AS (CASE WHEN id % 3 = 0 THEN 'us-east' WHEN id % 3 = 1 THEN 'us-central' ELSE 'us-west' END) STORED, amount DECIMAL, PRIMARY KEY (region, id)) LOCALITY REGIONAL BY ROW",
      'INSERT INTO demo_row.orders (id, amount) SELECT generate_series(1, 100), random() * 1000 ON CONFLICT DO NOTHING',
    ],
    nextSteps: 'Kill any single region. Its rows become unavailable, but other regions\' rows are still served.',
  },
  {
    id: 'global-table',
    name: 'Global Table',
    description: 'Non-blocking reads from any region without going to the leaseholder. Ideal for reference data like configs or feature flags.',
    icon: 'GL',
    color: '#FBBF24',
    sql: [
      'CREATE DATABASE IF NOT EXISTS demo_global',
      'ALTER DATABASE demo_global SET PRIMARY REGION "us-east"',
      'ALTER DATABASE demo_global ADD REGION IF NOT EXISTS "us-central"',
      'ALTER DATABASE demo_global ADD REGION IF NOT EXISTS "us-west"',
      'CREATE TABLE IF NOT EXISTS demo_global.config (key STRING PRIMARY KEY, value STRING)',
      'ALTER TABLE demo_global.config SET LOCALITY GLOBAL',
      "INSERT INTO demo_global.config VALUES ('version', '1.0'), ('feature_flag', 'true') ON CONFLICT (key) DO NOTHING",
    ],
    nextSteps: 'Kill one region. Data remains readable from all surviving regions with zero latency increase for reads.',
  },
  {
    id: 'survive-region',
    name: 'Survive Region Failure',
    description: 'RF=5 spread 2-2-1 across 3 regions. The cluster can lose an entire region and still maintain quorum for writes.',
    icon: 'SR',
    color: '#F472B6',
    sql: [
      'CREATE DATABASE IF NOT EXISTS demo_survive',
      'ALTER DATABASE demo_survive SET PRIMARY REGION "us-east"',
      'ALTER DATABASE demo_survive ADD REGION IF NOT EXISTS "us-central"',
      'ALTER DATABASE demo_survive ADD REGION IF NOT EXISTS "us-west"',
      'ALTER DATABASE demo_survive SURVIVE REGION FAILURE',
      'CREATE TABLE IF NOT EXISTS demo_survive.critical_data (id INT PRIMARY KEY, data STRING)',
      "INSERT INTO demo_survive.critical_data VALUES (1, 'important'), (2, 'critical') ON CONFLICT (id) DO NOTHING",
    ],
    nextSteps: 'Kill any region from the globe. Quorum is maintained and data remains fully writable.',
  },
]

interface DemoPanelProps {
  clusterConnected: boolean
  onExecuteScenario: (sql: string[]) => Promise<unknown>
}

export default function DemoPanel({ clusterConnected, onExecuteScenario }: DemoPanelProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [running, setRunning] = useState<string | null>(null)
  const [completed, setCompleted] = useState<Set<string>>(new Set())
  const [error, setError] = useState<string | null>(null)

  const handleRun = useCallback(async (scenario: DemoScenario) => {
    if (!clusterConnected) {
      setError('Cluster not connected. These demos require a real 9-node multi-region cluster.')
      return
    }

    setRunning(scenario.id)
    setError(null)

    try {
      await onExecuteScenario(scenario.sql)
      setCompleted(prev => new Set(prev).add(scenario.id))
    } catch (err) {
      setError(`Failed to run ${scenario.name}: ${err}`)
    } finally {
      setRunning(null)
    }
  }, [clusterConnected, onExecuteScenario])

  return (
    <div className="absolute top-4 right-4 z-10">
      <button
        className={`px-3 py-2 rounded-lg text-xs font-bold transition-all ${
          isOpen
            ? 'bg-crdb-accent/20 text-crdb-accent border border-crdb-accent/40'
            : 'bg-crdb-darker/90 text-white/70 border border-white/10 hover:border-white/20 hover:text-white/90'
        }`}
        onClick={() => setIsOpen(prev => !prev)}
      >
        Failure Demos
      </button>

      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, y: -8, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -8, scale: 0.95 }}
            transition={{ duration: 0.15 }}
            className="absolute top-12 right-0 w-80 bg-crdb-darker/95 border border-crdb-border rounded-xl shadow-2xl overflow-hidden"
          >
            {/* Header */}
            <div className="px-4 py-3 border-b border-crdb-border">
              <h3 className="text-sm font-bold text-white/90">Multi-Region Failure Demos</h3>
              <p className="text-[10px] text-white/40 mt-0.5">
                {clusterConnected
                  ? 'Connected to cluster. Demos will execute real SQL.'
                  : 'Cluster not connected. Connect a 9-node cluster first.'}
              </p>
              {!clusterConnected && (
                <div className="mt-1.5 px-2 py-1 rounded bg-amber-500/10 border border-amber-500/20">
                  <span className="text-[9px] text-amber-400 font-medium">
                    These demos require a REAL multi-region cluster (no simulation).
                  </span>
                </div>
              )}
            </div>

            {/* Error */}
            {error && (
              <div className="mx-4 mt-2 px-2 py-1.5 rounded bg-red-500/10 border border-red-500/20">
                <span className="text-[9px] text-red-400">{error}</span>
              </div>
            )}

            {/* Scenario cards */}
            <div className="p-3 space-y-2 max-h-[60vh] overflow-y-auto">
              {FAILURE_DEMOS.map(scenario => {
                const isRunning = running === scenario.id
                const isCompleted = completed.has(scenario.id)

                return (
                  <div
                    key={scenario.id}
                    className={`p-3 rounded-lg border transition-all ${
                      isCompleted
                        ? 'border-emerald-500/30 bg-emerald-500/5'
                        : 'border-white/5 bg-white/[0.02] hover:border-white/10'
                    }`}
                  >
                    <div className="flex items-start gap-2">
                      <div
                        className="w-7 h-7 rounded-md flex items-center justify-center text-[8px] font-black tracking-wide flex-shrink-0"
                        style={{
                          backgroundColor: scenario.color + '18',
                          color: scenario.color,
                          border: `1px solid ${scenario.color}30`,
                        }}
                      >
                        {scenario.icon}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="text-[11px] font-bold text-white/80">{scenario.name}</div>
                        <div className="text-[9px] text-white/40 leading-snug mt-0.5">{scenario.description}</div>
                      </div>
                    </div>

                    {isCompleted && (
                      <div className="mt-2 px-2 py-1.5 rounded bg-white/[0.03] border border-white/5">
                        <div className="text-[8px] text-emerald-400/80 font-medium uppercase tracking-wider mb-0.5">Next:</div>
                        <div className="text-[9px] text-white/50">{scenario.nextSteps}</div>
                      </div>
                    )}

                    <button
                      className={`mt-2 w-full px-2 py-1.5 rounded text-[10px] font-bold uppercase tracking-wider transition-all ${
                        isRunning
                          ? 'bg-white/5 text-white/30 cursor-wait'
                          : !clusterConnected
                            ? 'bg-white/3 text-white/20 cursor-not-allowed'
                            : isCompleted
                              ? 'bg-emerald-500/10 text-emerald-400 hover:bg-emerald-500/20 border border-emerald-500/20'
                              : 'bg-crdb-accent/10 text-crdb-accent hover:bg-crdb-accent/20 border border-crdb-accent/20'
                      }`}
                      onClick={() => handleRun(scenario)}
                      disabled={isRunning || !clusterConnected}
                    >
                      {isRunning ? 'Running...' : isCompleted ? 'Re-run Setup' : 'Run Setup SQL'}
                    </button>
                  </div>
                )
              })}
            </div>

            {/* SQL count footer */}
            <div className="px-4 py-2 border-t border-crdb-border">
              <div className="text-[9px] text-white/20 text-center">
                {completed.size}/{FAILURE_DEMOS.length} scenarios set up
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
