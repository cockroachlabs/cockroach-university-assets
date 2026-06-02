---
name: monitor-cluster-health-in-cloud-console
description: Monitor CockroachDB Cloud cluster health, performance metrics, and resource utilization using the Cloud Console web interface. Learn to interpret health indicators, analyze metrics dashboards, identify performance issues, and set up proactive monitoring for production clusters.
metadata:
  domain: Cloud Ops
  bloom_level: Understand
  version: 1.0.0
  cockroachdb_version: v26.1.0+
  status: production
---

# Monitor Cluster Health in Cloud Console

**Domain**: Cloud Ops
**Bloom's Level**: Understand
**CockroachDB Version**: v26.1.0+

## What This Skill Teaches

This skill teaches you how to monitor CockroachDB Cloud cluster health and performance using the web-based Cloud Console. You'll learn to interpret health status indicators, analyze performance metrics, identify resource bottlenecks, and establish proactive monitoring practices for production environments.

**When to use this skill:**
- Daily operational health checks for production clusters
- Investigating performance degradation or application slowness
- Capacity planning and resource utilization analysis
- Troubleshooting cluster issues and outages
- Validating cluster behavior after changes or deployments
- Setting up proactive monitoring and alerting

**What this skill covers:**
- Cluster health status indicators and meanings
- Overview page quick health checks
- Monitoring dashboard metrics (CPU, memory, storage, latency)
- SQL activity monitoring (statements, transactions, sessions)
- Resource utilization analysis
- Interpreting performance trends and anomalies
- Setting up spend alerts and notifications
- Best practices for ongoing cluster monitoring

**Monitoring is essential for:**
- Preventing performance issues before they impact users
- Identifying optimization opportunities
- Validating capacity planning decisions
- Troubleshooting production incidents
- Understanding application query patterns
- Controlling cloud costs through usage tracking

## Instructions

### Understanding Cluster Health Status

**Health Status Indicators:**
```
Status Colors (Cluster Overview and List):

🟢 Healthy (Green):
  - All nodes operational
  - Replicas properly distributed
  - No critical alerts
  - Normal performance metrics
  - Action: Routine monitoring only

🟡 Warning (Yellow):
  - Minor issues detected
  - Examples:
    * Cluster scaling in progress
    * Scheduled maintenance
    * High resource utilization (70-85% CPU)
    * Elevated latency but within acceptable range
  - Action: Investigate, monitor closely

🔴 Critical (Red):
  - Major issues affecting availability or performance
  - Examples:
    * Node unavailable
    * Quorum loss imminent
    * Resource exhaustion (CPU > 95%, disk full)
    * Severe latency degradation
  - Action: Immediate investigation and remediation

⚪ Creating/Updating (Gray):
  - Cluster provisioning in progress
  - Configuration changes being applied
  - Normal during cluster creation or scaling
  - Action: Wait for completion, monitor progress
```

**Health Check Locations:**
```
Cluster List Page:
  Path: Clusters (left sidebar)
  Shows: Status indicator for each cluster
  Quick scan: Identify any non-green clusters

Cluster Overview Page:
  Path: Clusters → [Select Cluster] → Overview
  Shows:
    - Large status indicator at top
    - Detailed status messages (if not healthy)
    - Quick metrics summary (CPU, storage, connections)
    - Recent alerts or events
```

### Cluster Overview Page Monitoring

**Overview Page Components:**
```
Top Section (Health Summary):
  Cluster Status: Green/Yellow/Red indicator
  Version: CockroachDB version (e.g., v26.1.3)
  Regions: Number of regions (single or multi-region)
  vCPU: Total vCPU allocation (Dedicated only)
  Uptime: Time since last restart or creation

Connection Information:
  Connect Button: Quick access to connection strings
  SQL Shell Button: Launch web-based SQL client
  Hostname: Cluster connection endpoint
  Port: 26257 (standard SQL port)

Quick Metrics Tiles:
  CPU Usage:
    - Current percentage utilization
    - Color-coded: Green < 70%, Yellow 70-85%, Red > 85%

  Storage Used:
    - Current storage consumption (GiB)
    - Growth trend (increasing/stable)

  RU Consumption (Serverless only):
    - Current month RU usage
    - Percentage of free tier consumed
    - Spend amount if beyond free tier

  Active Connections:
    - Current open SQL connections
    - Warning if approaching connection limit
```

**Interpreting Quick Metrics:**
```
Normal State (Healthy):
  CPU: 30-60% average
  Storage: Steady growth or stable
  Connections: < 80% of max connections
  RUs (Serverless): Within expected usage pattern

Warning Signs:
  CPU: 70-85% sustained (1+ hours)
    → Action: Investigate query load, consider scaling

  Storage: Rapid growth (10%+ daily)
    → Action: Review data retention, check for data bloat

  Connections: > 80% of limit
    → Action: Check for connection leaks, configure pooling

  RUs: Unexpected spike or rapid consumption
    → Action: Identify expensive queries, optimize

Critical Issues:
  CPU: > 90% sustained
    → Immediate action: Scale up or reduce load

  Storage: Approaching capacity limit
    → Immediate action: Clean up data or expand storage

  Connections: At or near limit (cluster may reject new connections)
    → Immediate action: Terminate idle connections, fix app
```

### Monitoring Dashboard (Metrics Page)

**Accessing Metrics Dashboard:**
```
Path: Cluster → Monitoring → Metrics
Purpose: Detailed time-series metrics for performance analysis
Features:
  - Time range selector (10 min, 1 hour, 6 hours, 1 day, 7 days, 30 days, custom)
  - Auto-refresh toggle (10-second updates for live monitoring)
  - CSV export for offline analysis
  - Zoom and pan for detailed investigation
```

**Key Metrics and Interpretation:**
```
CPU Usage Graph:
  Metric: CPU utilization percentage (0-100%)
  What it shows:
    - Query processing load
    - Transaction overhead
    - Background operations (compaction, GC)

  Healthy patterns:
    - Stable baseline (30-60%)
    - Predictable daily cycles (e.g., higher during business hours)
    - Gradual increases (user growth)

  Warning patterns:
    - Sudden spikes (check SQL Activity for new expensive queries)
    - Sustained > 70% (capacity constraint approaching)
    - Sawtooth pattern (potential batch job or cron job)

  Critical patterns:
    - Flat 90-100% (cluster overloaded, need to scale)
    - Erratic fluctuations (investigate contention or connection issues)

Memory Usage Graph:
  Metric: Memory utilization percentage (0-100%)
  What it shows:
    - Cache efficiency
    - Active query memory usage
    - Node memory pressure

  Healthy patterns:
    - Stable 60-80% (good cache utilization)
    - Gradual growth with data size

  Warning patterns:
    - Approaching 90% (risk of OOM)
    - Sudden spikes (large query or sort operation)

  Critical patterns:
    - 95-100% sustained (OOM imminent, queries may fail)

Storage Usage Graph:
  Metric: Storage consumed (GiB)
  What it shows:
    - Total data + indexes + system tables
    - Includes replication factor (3x data typically)

  Healthy patterns:
    - Steady linear growth (normal data accumulation)
    - Stable (no net new data, expected for mature apps)

  Warning patterns:
    - Exponential growth (potential data bloat or retention issue)
    - Unexpected spikes (bulk data import)

  Critical patterns:
    - Approaching provisioned capacity (need expansion)

SQL Latency Graph (p50, p99):
  Metric: Query execution latency (milliseconds)
  p50: Median latency (50th percentile)
  p99: 99th percentile latency (worst 1% of queries)

  Healthy patterns:
    - p50: < 10ms, p99: < 50ms (typical for OLTP)
    - Stable over time
    - Predictable spikes during peak hours

  Warning patterns:
    - p99 increasing trend (potential index missing)
    - Occasional spikes (batch queries or maintenance)

  Critical patterns:
    - p50 > 100ms (serious performance issue)
    - p99 > 1000ms (users experiencing timeouts)
    - Sudden jump 10x+ (investigate immediately)

IOPS (Reads/Writes per second):
  Metric: Disk I/O operations per second
  What it shows:
    - Read/write throughput to storage
    - Storage subsystem load

  Healthy patterns:
    - Balanced reads and writes (typical 80/20 read/write)
    - Correlates with query load (CPU)

  Warning patterns:
    - Very high write IOPS (compaction storm or bulk inserts)
    - Read IOPS >> CPU (potential inefficient queries)

Network Throughput (Dedicated multi-region):
  Metric: Network bytes sent/received
  What it shows:
    - Cross-region replication traffic
    - Application query traffic

  Healthy patterns:
    - Steady with slight increase over time
    - Spikes during backups or cross-region writes

  Critical patterns:
    - Bandwidth saturation (network bottleneck)
```

**Using Time Range Selector:**
```
Recommended Time Ranges by Use Case:

Last 10 minutes:
  - Real-time debugging during incidents
  - Validating immediate impact of changes
  - Watching live deployment effects

Last 1 hour:
  - Default for routine monitoring
  - Investigating recent performance issues
  - Post-deployment validation

Last 6 hours:
  - Reviewing business day performance
  - Identifying daily traffic patterns

Last 24 hours:
  - Daily operations review
  - Comparing day-over-day performance
  - Identifying time-of-day patterns

Last 7 days:
  - Weekly trend analysis
  - Capacity planning (weekly growth)
  - Identifying weekly patterns (weekday vs weekend)

Last 30 days:
  - Monthly trend analysis
  - Long-term capacity planning
  - Budget and cost forecasting

Custom Range:
  - Historical incident analysis
  - Comparing specific dates (this Monday vs last Monday)
  - Pre/post migration comparison
```

### SQL Activity Monitoring

**Statements Page (Query Performance):**
```
Path: Cluster → Monitoring → Statements
Purpose: Analyze SQL query performance and identify slow queries

Columns:
  Statement Fingerprint:
    - Parameterized query (e.g., SELECT * FROM users WHERE id = $1)
    - Groups similar queries together
    - Click to see full query text and execution plan

  Execution Count:
    - Number of times query executed in time range
    - High count = frequently run (optimize for impact)

  Total Latency:
    - Cumulative time spent executing query
    - High total latency = optimization target

  Mean Latency:
    - Average execution time per query
    - Compare to p99 for variance understanding

  P99 Latency:
    - 99th percentile execution time
    - User-perceived "worst case" latency
    - Target: < 100ms for interactive queries

  Rows Read/Written:
    - Data volume accessed/modified
    - High rows read + high latency = potential index missing

Sorting Strategies:
  By Total Latency (default):
    - Identifies biggest overall performance impact
    - Prioritize: High latency + high execution count

  By Execution Count:
    - Find most frequently run queries
    - Small optimizations have large cumulative impact

  By P99 Latency:
    - Find slowest queries (user experience impact)
    - Target: Queries > 1 second p99

  By Rows Read:
    - Identify full table scans
    - Large row counts often indicate missing indexes
```

**Query Optimization Workflow:**
```
Step 1: Identify expensive query
  - Sort by Total Latency (descending)
  - Select top 5 queries

Step 2: Analyze query details
  - Click statement fingerprint
  - View: Full query text
  - Note: Tables accessed, WHERE clauses, JOIN conditions

Step 3: Check execution plan
  - Click "Explain Plan" tab
  - Look for:
    * "Scan" (table scan, bad for large tables)
    * "Index Join" (potentially inefficient)
    * "Sort" (expensive operation)

Step 4: Identify optimization opportunity
  - Missing index: See "Scan" on filtered column
  - Inefficient JOIN: Large row counts in plan
  - Over-fetching: SELECT * on wide table

Step 5: Implement optimization
  - Add index: CREATE INDEX idx_name ON table(column);
  - Rewrite query: Add WHERE clause, LIMIT, or pagination
  - Denormalize: Reduce JOINs by duplicating data

Step 6: Validate improvement
  - Re-run query or wait for app to use it
  - Check Statements page after 10-15 minutes
  - Compare new latency to baseline
  - Target: 50%+ reduction in p99 latency
```

**Transactions Page:**
```
Path: Cluster → Monitoring → Transactions
Purpose: Monitor transaction-level performance

Key Metrics:
  Transaction Throughput (TPS):
    - Transactions per second
    - Healthy: Stable or gradual increase
    - Warning: Sudden drop (investigate errors)

  Transaction Latency:
    - End-to-end transaction duration
    - Includes all statements in transaction
    - Higher than statement latency (expected)

  Contention Events:
    - Transactions waiting for locks
    - High contention = performance bottleneck
    - Action: Minimize transaction duration, redesign schema

  Retry Rate:
    - Percentage of transactions retried (serialization errors)
    - Healthy: < 5% retry rate
    - Warning: > 10% (review transaction logic)
    - Critical: > 25% (likely application issue)

Troubleshooting High Contention:
  1. Identify contended tables (click contention event details)
  2. Review application transaction patterns
  3. Minimize transaction scope (fewer operations)
  4. Reduce transaction duration (optimize queries)
  5. Consider schema changes (split hot tables)
```

**Sessions Page:**
```
Path: Cluster → Monitoring → Sessions
Purpose: Monitor active database connections

Active Sessions Table:
  User: SQL user name
  Client Address: Application server IP
  Session Start: When connection established
  Active Query: Currently executing query (if any)
  Status: Active, Idle, Idle in Transaction

  Warning Signs:
    - Many "Idle in Transaction" (application not closing transactions)
    - Very old session start times (connection leaks)
    - High session count approaching limit

Actions:
  Terminate Session:
    - Click session → Terminate
    - Use case: Kill runaway query or leaked connection
    - Caution: Application will see connection error

  Investigate Application:
    - Check connection pooling configuration
    - Verify application closes connections properly
    - Review transaction management (BEGIN/COMMIT)
```

### Spend and Usage Monitoring (Serverless)

**Serverless Spend Tracking:**
```
Path: Cluster → Overview (Serverless clusters)
Shows:
  - Current month RU consumption
  - Current month spend ($ amount if beyond free tier)
  - Remaining free tier allocation

Path: Billing → Usage
Shows:
  - Daily RU consumption graph
  - Hourly breakdown (for recent days)
  - Cost by cluster (if multiple Serverless clusters)

Spend Limit Configuration:
  Path: Cluster → Settings → Spend Limit
  Options:
    - $0/month: Free tier only, pause when exhausted
    - Custom amount: Set maximum monthly spend
    - No limit: Pay-as-you-go (requires payment method)

  When Limit Reached:
    - Cluster pauses automatically
    - Email notification to org administrators
    - Resume: Increase limit or wait for monthly reset

Spend Alerts:
  Path: Billing → Alerts
  Configure:
    - Threshold: E.g., $40 (if $50 spend limit)
    - Recipients: Team email list
    - Frequency: Daily or immediate
  Use case: Proactive notification before hitting limit
```

### Setting Up Proactive Monitoring

**Alert Configuration Strategy:**
```
Critical Alerts (Page On-Call):
  - Cluster status: Critical (red)
  - CPU > 90% sustained (15+ minutes)
  - Storage > 90% capacity
  - Spend limit reached (Serverless)
  - Backup job failures
  - Region unavailable (multi-region)

  Delivery: SMS, PagerDuty, Slack channel

Warning Alerts (Email Team):
  - Cluster status: Warning (yellow)
  - CPU 70-89% sustained (1+ hour)
  - Storage growth accelerating
  - Spend at 75% of limit
  - High query latency (p99 > 100ms)
  - Connection count > 80% of limit

  Delivery: Email, Slack channel

Informational Notifications:
  - Cluster scaling operations
  - Scheduled maintenance
  - Version upgrades
  - Weekly usage summary

  Delivery: Email, team wiki
```

**Daily Monitoring Checklist:**
```
Morning Health Check (5 minutes):

☐ Check Cluster List page for status indicators
  - All clusters green?
  - Any yellow/red clusters → Investigate

☐ Review Overview page for production clusters
  - CPU utilization: Normal range?
  - Storage growth: Expected rate?
  - Connections: Within normal range?

☐ Check Metrics dashboard (Last 24 hours)
  - CPU: Any unexpected spikes?
  - Latency: Within SLA?
  - IOPS: Unusual patterns?

☐ Review SQL Activity → Statements (Last 24 hours)
  - Any new slow queries (p99 > 100ms)?
  - Query count trending up/down (expected)?

☐ Check Spend/Usage (Serverless)
  - Daily RU consumption: Within budget?
  - Trend: On track for month-end?

☐ Review recent alerts/notifications
  - Any unresolved alerts?
  - Action items from previous day?

If all checks pass: No action needed
If issues found: Investigate and remediate
```

**Weekly Monitoring Review (30 minutes):**
```
☐ Analyze 7-day trends
  - CPU: Average utilization trending up?
  - Storage: Growth rate consistent?
  - Latency: Any degradation over week?

☐ Capacity planning assessment
  - Current utilization vs capacity
  - Projected growth over next 4 weeks
  - Need to scale up? (CPU > 60% avg)

☐ Cost analysis (if applicable)
  - Last 7 days spend vs budget
  - Unexpected cost drivers?
  - Optimization opportunities?

☐ Query performance review
  - Top 10 queries by total latency
  - Any new inefficient queries introduced?
  - Optimization wins from last week?

☐ Backup validation
  - All scheduled backups successful?
  - Retention policy appropriate?
  - Last test restore: When? (monthly minimum)

☐ Update monitoring documentation
  - New baselines after scaling
  - Performance SLAs met/missed
  - Action items for next week
```

## Common Patterns

### Pattern 1: Investigating Performance Degradation

**Scenario**: Application reports slow database queries suddenly.

```
Investigation Workflow:

Step 1: Confirm issue in monitoring (2 minutes)
  Path: Cluster → Monitoring → Metrics
  Time range: Last 1 hour
  Check:
    - SQL Latency: p99 increased? By how much?
    - CPU Usage: Spiking or sustained high?
    - IOPS: Unusual pattern?

  Result: p99 latency jumped from 10ms to 500ms (50x increase)

Step 2: Identify time of degradation (1 minute)
  - Note exact time on latency graph
  - Example: Started at 14:15 UTC

Step 3: Check for system changes (2 minutes)
  - Any deployments at 14:15?
  - Any schema changes (ALTER TABLE)?
  - Any infrastructure changes (scaling)?

Step 4: Identify slow queries (5 minutes)
  Path: Cluster → Monitoring → Statements
  Time range: Custom (14:00 - 14:30 to isolate incident)
  Sort by: P99 Latency (descending)

  Find: New query or existing query suddenly slow?
  Example: SELECT * FROM orders WHERE status = 'pending' (p99: 2000ms)

Step 5: Analyze execution plan (3 minutes)
  - Click slow query → Explain Plan
  - Look for: "Scan" (table scan without index)
  - Diagnosis: Missing index on status column

Step 6: Implement fix (5 minutes)
  SQL Shell:
    CREATE INDEX idx_orders_status ON orders(status);

  Wait: 2-5 minutes for index build (background operation)

Step 7: Validate resolution (5 minutes)
  - Monitor latency graph (should return to baseline)
  - Check Statements page (query latency improved?)
  - Test from application (user-perceived improvement?)

  Result: p99 latency returned to 15ms (97% improvement)

Total time: 20-25 minutes (investigation + fix)
```

### Pattern 2: Capacity Planning Using Metrics

**Scenario**: Production cluster approaching resource limits, plan scaling.

```
Analysis Workflow:

Step 1: Gather current utilization (10 minutes)
  Path: Cluster → Monitoring → Metrics
  Time range: Last 30 days

  Record:
    - CPU average: 65%
    - CPU peak: 88%
    - Storage: 180 GiB (growing ~3 GiB/day)
    - Connections peak: 450

Step 2: Project growth (5 minutes)
  CPU trend:
    - 30 days ago: 50% avg
    - Today: 65% avg
    - Growth: +15% in 30 days (+0.5%/day)
    - Projection: 80% in 30 days (approaching limit)

  Storage trend:
    - 30 days ago: 90 GiB
    - Today: 180 GiB
    - Growth: 90 GiB in 30 days (3 GiB/day)
    - Projection: 270 GiB in 30 days

Step 3: Determine scaling need (5 minutes)
  CPU:
    - Current: 4 vCPU @ 65% avg
    - Target: 50% avg utilization (30% headroom)
    - Required: 4 vCPU × (65/50) = 5.2 vCPU
    - Scale to: 8 vCPU (next size up)

  Storage:
    - Current: 180 GiB, growing 3 GiB/day
    - 90 days: 180 + (3 × 90) = 450 GiB
    - Storage auto-expands (no action needed)

Step 4: Plan scaling action (2 minutes)
  Decision: Scale from 4 vCPU to 8 vCPU
  Timing: Within 2 weeks (before 80% threshold)
  Process:
    - Schedule: Low-traffic window (Sunday 2 AM)
    - Method: Cluster → Settings → Edit Cluster → vCPU: 8
    - Downtime: Zero (rolling update)
    - Duration: 10-15 minutes
    - Validation: Monitor for 48 hours post-scaling

Step 5: Update budget (2 minutes)
  Cost impact:
    - Before: $360/month (4 vCPU)
    - After: $720/month (8 vCPU)
    - Increase: $360/month (+100%)

  Communicate:
    - Finance team: Budget increase approval
    - Engineering team: Capacity headroom restored

Total time: 25 minutes (analysis + planning)
```

### Pattern 3: Cost Optimization for Serverless

**Scenario**: Serverless cluster spending $80/month, target: reduce to $40.

```
Cost Reduction Workflow:

Step 1: Identify current consumption (5 minutes)
  Path: Billing → Usage
  Time range: Last 30 days
  Note:
    - Total RUs: 250 million/month
    - Free tier: 50 million
    - Billable: 200 million @ $0.20/M = $40
    - Storage: 15 GiB @ $0.50/GiB = $7.50
    - Total: $47.50/month (close to actual $80, find discrepancy)

  Recheck actual bill: $80 includes multiple clusters or higher rates

Step 2: Analyze consumption by day (5 minutes)
  Graph shows:
    - Weekdays: 8-10M RUs/day
    - Weekends: 2-3M RUs/day
    - Spike on 15th: 25M RUs (anomaly, investigate)

  Spike investigation:
    - Check Statements page for 15th
    - Find: Batch data export job ran (unplanned)
    - Action: Schedule exports during low-traffic or use Dedicated for batch

Step 3: Identify expensive queries (10 minutes)
  Path: Cluster → Monitoring → Statements
  Time range: Last 30 days
  Sort by: Total Latency (proxy for RU consumption)

  Top 5 queries:
    1. SELECT * FROM events WHERE timestamp > $1 (no LIMIT)
       - Execution count: 100k/day
       - Rows read avg: 10k per query
       - Estimated RUs: 100k × 10k × 1KB = 1B RUs/day (40M/month!)

    2. INSERT INTO logs (...) (individual inserts)
       - Execution count: 500k/day
       - Estimated RUs: 500k × 3 RU = 1.5M RUs/day (45M/month)

Step 4: Implement optimizations (varies)
  Optimization 1: Add LIMIT to SELECT query
    Before: SELECT * FROM events WHERE timestamp > $1
    After: SELECT * FROM events WHERE timestamp > $1 LIMIT 100

    Impact: 10k rows → 100 rows (99% reduction)
    RU savings: 40M → 400k/month (39.6M saved)

  Optimization 2: Batch INSERT operations
    Before: 500k individual INSERTs
    After: Batched INSERTs (500 rows per batch = 1000 batches)

    Impact: 500k × 3 RU → 1000 × 1500 RU = 1.5M RUs/day
    RU savings: 45M → 45M/month (minimal, but reduces latency)

  Optimization 3: Add index on timestamp column
    CREATE INDEX idx_events_timestamp ON events(timestamp);

    Impact: Reduce rows scanned for query 1
    RU savings: Additional 50% on remaining queries

Step 5: Project new cost (2 minutes)
  Original: 250M RUs → $40 (200M billable)
  After optimizations:
    - Query 1 reduction: -39.6M RUs
    - Index efficiency: -20M RUs (estimated)
    - New total: 190M RUs → $28 (140M billable)

  Projected savings: $40 → $28 (30% reduction)

  To reach $40 total budget: Add spend limit at $40/month

Total time: 25 minutes (analysis + optimization implementation)
Result: 30% cost reduction + controlled spending
```

## Troubleshooting

### Issue 1: Cluster Status Shows Warning

**Symptoms:**
- Yellow status indicator in cluster list
- Warning message on Overview page

**Common Causes and Resolutions:**
```
Cause 1: High CPU utilization (70-85%)
  Path: Monitoring → Metrics → CPU Usage
  Action:
    - Check Statements page for expensive queries
    - Optimize queries or add indexes
    - If sustained, plan to scale up vCPU

Cause 2: Scaling operation in progress
  Message: "Cluster scaling in progress"
  Action: Wait for completion (5-15 minutes), no action needed

Cause 3: Storage approaching capacity
  Path: Monitoring → Metrics → Storage Usage
  Action:
    - Review data retention policies
    - Clean up old data if applicable
    - Storage auto-expands (Dedicated) but monitor costs

Cause 4: Elevated latency
  Path: Monitoring → Metrics → SQL Latency
  Action: Investigate via Statements page, optimize slow queries
```

### Issue 2: Cannot See Recent Metrics

**Symptoms:**
- Metrics dashboard shows "No data" for recent time range
- Graphs appear empty or outdated

**Resolution:**
```
Step 1: Check time range selector
  - Ensure correct time range selected (not future dates)
  - Try "Last 1 hour" to see if any data appears

Step 2: Verify cluster is active
  - Check cluster status is Healthy (not Creating)
  - New clusters may take 5-10 minutes to populate metrics

Step 3: Refresh page
  - Hard refresh: Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)
  - Clear browser cache if issue persists

Step 4: Check auto-refresh
  - Enable auto-refresh toggle for live updates
  - Disable and re-enable if stuck

Step 5: Try different browser
  - Test in incognito/private mode
  - If works, clear cookies for cockroachlabs.cloud

Step 6: Contact support
  - If metrics missing for > 30 minutes
  - Provide: Cluster ID, time range, browser/OS
```

### Issue 3: High RU Consumption (Serverless) Unexplained

**Symptoms:**
- RU consumption spiking unexpectedly
- Monthly spend exceeding budget
- No corresponding application traffic increase

**Diagnosis and Resolution:**
```
Step 1: Identify spike timing
  Path: Billing → Usage
  Graph: Daily RU consumption
  Note: Date and time of spike

Step 2: Check SQL Activity during spike
  Path: Monitoring → Statements
  Time range: Custom (spike time period)
  Sort by: Total Latency

  Look for:
    - New queries not seen before
    - Existing queries with execution count 10x+ normal

Step 3: Common causes
  Runaway batch job:
    - Unoptimized data export or migration
    - Action: Optimize query, add LIMIT, or schedule off-hours

  Missing WHERE clause:
    - Query scanning entire table instead of subset
    - Action: Add WHERE clause or index

  Application bug:
    - Infinite loop calling database
    - Connection leak causing repeated queries
    - Action: Fix application code, deploy patch

  Attack or abuse:
    - Malicious user issuing expensive queries
    - Action: Review SQL audit logs, revoke user, add rate limiting

Step 4: Immediate mitigation
  - Lower spend limit to prevent further overages
  - Terminate active sessions if runaway query
  - Disable problematic application feature temporarily

Step 5: Long-term fix
  - Optimize identified queries
  - Add monitoring alerts for RU consumption spikes
  - Implement application-level query caching
```

## Best Practices

### Monitoring Cadence

**Daily:**
- Quick health check (5 minutes)
- Review cluster status indicators
- Check for alerts/notifications
- Scan metrics dashboard for anomalies

**Weekly:**
- Deep dive metrics analysis (30 minutes)
- Capacity planning review
- Cost/spend analysis (Serverless)
- Query performance optimization
- Backup validation

**Monthly:**
- Comprehensive performance review (1-2 hours)
- Long-term trend analysis (30-day view)
- Budget vs actual spend reconciliation
- Capacity planning for next quarter
- Update monitoring documentation and runbooks

### Metrics Baselines

**Establish Normal Ranges:**
```
For each cluster, document:

CPU Utilization:
  - Normal range: 30-60% (weekday average)
  - Peak acceptable: < 80%
  - Alert threshold: > 70% sustained (1 hour)

Memory Utilization:
  - Normal range: 60-75%
  - Alert threshold: > 85%

SQL Latency:
  - p50 target: < 10ms
  - p99 target: < 50ms (interactive queries)
  - Alert threshold: p99 > 100ms

Storage Growth:
  - Normal rate: X GiB/day (based on 30-day trend)
  - Alert threshold: 2x normal growth rate

Review baselines quarterly:
  - Adjust as application evolves
  - Update alert thresholds
  - Document changes in runbook
```

### Monitoring Tools Integration

**Export Metrics for External Monitoring:**
```
Dedicated Clusters (Advanced tier):
  - Export logs to Datadog, CloudWatch, Stackdriver
  - Integrate metrics with existing monitoring stack
  - Correlate database metrics with application metrics

Serverless Clusters:
  - Export usage data (CSV) for analysis
  - Build custom dashboards in BI tools
  - Integrate spend data with cost management systems

Alerting Integration:
  - PagerDuty for critical alerts
  - Slack for team notifications
  - Email for non-urgent updates
  - Webhook endpoints for custom integrations
```

### Documentation

**Maintain Monitoring Runbook:**
```
Contents:
  - Cluster inventory (names, purposes, owners)
  - Normal baseline metrics for each cluster
  - Alert thresholds and escalation procedures
  - Common issues and resolutions (this skill as reference)
  - Contact information (on-call, escalation)
  - Disaster recovery procedures

Update Frequency:
  - After each scaling operation
  - When adding/removing clusters
  - After major application changes
  - Quarterly comprehensive review

Accessibility:
  - Store in team wiki or shared documentation
  - Include in on-call handbook
  - Share with new team members during onboarding
```

## Related Skills

**Foundational:**
- `navigate-cockroachdb-cloud-console` - Console navigation basics
- `create-clusters-via-cloud-console` - Cluster creation and setup

**Performance Analysis:**
- `understand-sql-statement-tuning-fundamentals` - Query optimization
- `identify-slow-queries-with-db-console-statements-page` - Statement analysis
- `use-explain-to-analyze-query-execution-plans` - Execution plan interpretation

**Capacity Planning:**
- `scale-clusters-via-cloud-console` - Scaling operations
- `use-cockroachdb-cloud-basic-tier` - Serverless monitoring specifics
- `use-cockroachdb-cloud-standard-tier` - Dedicated monitoring specifics

**Troubleshooting:**
- `identify-and-analyze-database-contention` - Contention investigation
- `monitor-underreplicated-ranges` - Replication health
- `diagnose-node-failures-using-multiple-signals` - Node health

**Alerting and Automation:**
- `set-up-alerting-rules-for-critical-conditions` - Configure alerts
- `configure-prometheus-metrics-export` - Advanced metrics (Dedicated)

**Cost Management:**
- (Future: Cost optimization and spend management skills)

## References

**Official Documentation:**
- Cluster Overview Page: https://www.cockroachlabs.com/docs/cockroachcloud/cluster-overview-page
- Monitoring CockroachDB Cloud: https://www.cockroachlabs.com/docs/cockroachcloud/monitoring-page
- SQL Activity: https://www.cockroachlabs.com/docs/cockroachcloud/statements-page

**Metrics Reference:**
- Essential Metrics: https://www.cockroachlabs.com/docs/stable/essential-metrics
- Monitoring and Alerting: https://www.cockroachlabs.com/docs/stable/monitoring-and-alerting

**Console Access:**
- CockroachDB Cloud Console: https://cockroachlabs.cloud/
