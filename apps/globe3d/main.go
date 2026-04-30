package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	_ "github.com/lib/pq"
)

var (
	db       *sql.DB
	dbMu     sync.RWMutex
	dbName   = envOr("CRDB_DATABASE", "multi_region")
	connStr  = envOr("CRDB_URL", "postgresql://root@localhost:26257/defaultdb?sslmode=disable")
	listenAddr = envOr("LISTEN_ADDR", ":9090")
	staticDir  = envOr("STATIC_DIR", "./dist")
	containerPrefix = envOr("CONTAINER_PREFIX", "roach-")
)

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	var err error
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("connect: %v", err)
	}
	db.SetMaxOpenConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)

	mux := http.NewServeMux()

	// Cluster status & topology
	mux.HandleFunc("/api/health", handleHealth)
	mux.HandleFunc("/api/multiregion/status", handleStatus)
	mux.HandleFunc("/api/cluster/topology", handleTopology)
	mux.HandleFunc("/api/multiregion/replicas", handleReplicas)

	// Database management
	mux.HandleFunc("/api/multiregion/database/create", handleCreateDB)
	mux.HandleFunc("/api/multiregion/database/drop", handleDropDB)
	mux.HandleFunc("/api/multiregion/database/primary-region", handleSetPrimaryRegion)
	mux.HandleFunc("/api/multiregion/database/add-region", handleAddRegion)
	mux.HandleFunc("/api/multiregion/database/remove-region", handleRemoveRegion)
	mux.HandleFunc("/api/multiregion/database/survival-goal", handleSetSurvivalGoal)

	// Table locality
	mux.HandleFunc("/api/multiregion/table/locality", handleSetTableLocality)

	// Node/region control (Docker)
	mux.HandleFunc("/api/nodes/", handleNodeAction)
	mux.HandleFunc("/api/cluster/region/", handleRegionAction)

	// Demo scenarios
	mux.HandleFunc("/api/demos/scenario", handleDemoScenario)
	mux.HandleFunc("/api/demos/globe-scenarios", handleGlobeScenarios)

	// Static files (React frontend)
	mux.Handle("/", http.FileServer(http.Dir(staticDir)))

	log.Printf("Globe3D server listening on %s (db=%s)", listenAddr, connStr)
	log.Fatal(http.ListenAndServe(listenAddr, corsMiddleware(mux)))
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == "OPTIONS" {
			w.WriteHeader(204)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func jsonResp(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func jsonErr(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

// --- Health & Status ---

func handleHealth(w http.ResponseWriter, r *http.Request) {
	if err := db.Ping(); err != nil {
		jsonErr(w, 503, "database unreachable")
		return
	}
	jsonResp(w, map[string]string{"status": "ok"})
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	resp := map[string]any{"connected": false}

	if err := db.Ping(); err != nil {
		jsonResp(w, resp)
		return
	}
	resp["connected"] = true

	var dbInfo map[string]any
	row := db.QueryRow(fmt.Sprintf(`
		SELECT primary_region, survival_goal
		FROM [SHOW DATABASE]
		WHERE database_name = '%s'
	`, dbName))

	var primaryRegion, survivalGoal sql.NullString
	if err := row.Scan(&primaryRegion, &survivalGoal); err == nil && primaryRegion.Valid {
		regions := []string{}
		rows, err := db.Query(fmt.Sprintf("SELECT region FROM [SHOW REGIONS FROM DATABASE %s]", dbName))
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var r string
				rows.Scan(&r)
				regions = append(regions, r)
			}
		}
		dbInfo = map[string]any{
			"name":          dbName,
			"primaryRegion": primaryRegion.String,
			"regions":       regions,
			"survivalGoal":  survivalGoal.String,
		}
	}
	resp["database"] = dbInfo
	jsonResp(w, resp)
}

// --- Topology ---

type TopologyNode struct {
	NodeID        int    `json:"nodeId"`
	Address       string `json:"address"`
	Locality      string `json:"locality"`
	IsLive        bool   `json:"isLive"`
	RangeCount    int    `json:"rangeCount,omitempty"`
	LeaseCount    int    `json:"leaseCount,omitempty"`
	MemoryUsageMB int    `json:"memoryUsageMB,omitempty"`
	UptimeSeconds int    `json:"uptimeSeconds,omitempty"`
}

func handleTopology(w http.ResponseWriter, r *http.Request) {
	nodes := []TopologyNode{}
	regions := map[string][]string{}
	regionStatus := map[string]map[string]any{}

	rows, err := db.Query(`
		SELECT node_id, address, locality,
		       CASE WHEN is_live THEN true ELSE false END AS is_live,
		       range_count, lease_count
		FROM crdb_internal.gossip_liveness gl
		JOIN crdb_internal.gossip_nodes gn USING (node_id)
		LEFT JOIN (
			SELECT node_id, count(*) AS range_count,
			       count(*) FILTER (WHERE lease_holder = node_id) AS lease_count
			FROM crdb_internal.ranges_no_leases
			GROUP BY node_id
		) rc USING (node_id)
		ORDER BY node_id
	`)
	if err != nil {
		// Fallback: try without crdb_internal (may need SET allow_unsafe_internals)
		db.Exec("SET allow_unsafe_internals = true")
		rows, err = db.Query(`
			SELECT node_id, address, locality, is_live, range_count, lease_count
			FROM crdb_internal.gossip_liveness gl
			JOIN crdb_internal.gossip_nodes gn USING (node_id)
			LEFT JOIN (
				SELECT node_id, count(*) AS range_count, 0 AS lease_count
				FROM crdb_internal.ranges_no_leases
				GROUP BY node_id
			) rc USING (node_id)
			ORDER BY node_id
		`)
		if err != nil {
			jsonErr(w, 500, fmt.Sprintf("topology query: %v", err))
			return
		}
	}
	defer rows.Close()

	for rows.Next() {
		var n TopologyNode
		var rangeCount, leaseCount sql.NullInt64
		if err := rows.Scan(&n.NodeID, &n.Address, &n.Locality, &n.IsLive, &rangeCount, &leaseCount); err != nil {
			continue
		}
		if rangeCount.Valid {
			n.RangeCount = int(rangeCount.Int64)
		}
		if leaseCount.Valid {
			n.LeaseCount = int(leaseCount.Int64)
		}
		nodes = append(nodes, n)

		region := extractRegion(n.Locality)
		if region != "" {
			regions[region] = append(regions[region], fmt.Sprintf("node-%d", n.NodeID))
		}
	}

	// Build region status
	for region := range regions {
		live, dead := 0, 0
		nodeIds := []int{}
		for _, n := range nodes {
			if extractRegion(n.Locality) == region {
				nodeIds = append(nodeIds, n.NodeID)
				if n.IsLive {
					live++
				} else {
					dead++
				}
			}
		}
		regionStatus[region] = map[string]any{
			"region":    region,
			"liveNodes": live,
			"deadNodes": dead,
			"nodeIds":   nodeIds,
		}
	}

	jsonResp(w, map[string]any{
		"connected":    true,
		"nodes":        nodes,
		"regions":      regions,
		"regionStatus": regionStatus,
	})
}

func extractRegion(locality string) string {
	for _, part := range strings.Split(locality, ",") {
		kv := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(kv) == 2 && kv[0] == "region" {
			return kv[1]
		}
	}
	return ""
}

// --- Replicas ---

func handleReplicas(w http.ResponseWriter, r *http.Request) {
	db.Exec("SET allow_unsafe_internals = true")

	rows, err := db.Query(fmt.Sprintf(`
		SELECT range_id, replicas, voting_replicas, lease_holder
		FROM crdb_internal.ranges
		WHERE database_name = '%s'
		LIMIT 50
	`, dbName))
	if err != nil {
		jsonErr(w, 500, fmt.Sprintf("replicas: %v", err))
		return
	}
	defer rows.Close()

	type RangeInfo struct {
		RangeID        int   `json:"rangeId"`
		Replicas       []int `json:"replicas"`
		VotingReplicas []int `json:"votingReplicas"`
		LeaseHolder    int   `json:"leaseHolder"`
	}
	ranges := []RangeInfo{}

	for rows.Next() {
		var ri RangeInfo
		var replicasStr, votingStr string
		if err := rows.Scan(&ri.RangeID, &replicasStr, &votingStr, &ri.LeaseHolder); err != nil {
			continue
		}
		ri.Replicas = parseIntArray(replicasStr)
		ri.VotingReplicas = parseIntArray(votingStr)
		ranges = append(ranges, ri)
	}

	// Node-to-region mapping
	nodeRegions := map[string]string{}
	nrows, err := db.Query("SELECT node_id, locality FROM crdb_internal.gossip_nodes")
	if err == nil {
		defer nrows.Close()
		for nrows.Next() {
			var nodeID int
			var locality string
			nrows.Scan(&nodeID, &locality)
			nodeRegions[fmt.Sprintf("%d", nodeID)] = extractRegion(locality)
		}
	}

	jsonResp(w, map[string]any{
		"ranges":      ranges,
		"nodeRegions": nodeRegions,
	})
}

func parseIntArray(s string) []int {
	s = strings.Trim(s, "{}")
	if s == "" {
		return []int{}
	}
	result := []int{}
	for _, part := range strings.Split(s, ",") {
		var n int
		fmt.Sscanf(strings.TrimSpace(part), "%d", &n)
		result = append(result, n)
	}
	return result
}

// --- Database Management ---

func handleCreateDB(w http.ResponseWriter, r *http.Request) {
	var body struct {
		PrimaryRegion string `json:"primaryRegion"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	if body.PrimaryRegion == "" {
		body.PrimaryRegion = "us-east1"
	}

	stmts := []string{
		fmt.Sprintf("CREATE DATABASE IF NOT EXISTS %s", dbName),
		fmt.Sprintf("ALTER DATABASE %s SET PRIMARY REGION '%s'", dbName, body.PrimaryRegion),
	}

	for _, stmt := range stmts {
		if _, err := db.Exec(stmt); err != nil {
			jsonErr(w, 500, fmt.Sprintf("create db: %v", err))
			return
		}
	}

	// Create a demo table
	db.Exec(fmt.Sprintf(`
		CREATE TABLE IF NOT EXISTS %s.demo (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			name STRING,
			region crdb_internal_region AS (
				CASE WHEN id IS NOT NULL THEN gateway_region() END
			) STORED,
			created_at TIMESTAMP DEFAULT now()
		)
	`, dbName))

	jsonResp(w, map[string]string{"status": "ok", "database": dbName})
}

func handleDropDB(w http.ResponseWriter, r *http.Request) {
	if _, err := db.Exec(fmt.Sprintf("DROP DATABASE IF EXISTS %s CASCADE", dbName)); err != nil {
		jsonErr(w, 500, fmt.Sprintf("drop: %v", err))
		return
	}
	jsonResp(w, map[string]string{"status": "ok"})
}

func handleSetPrimaryRegion(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Region string `json:"region"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	if _, err := db.Exec(fmt.Sprintf("ALTER DATABASE %s SET PRIMARY REGION '%s'", dbName, body.Region)); err != nil {
		jsonErr(w, 500, fmt.Sprintf("set primary region: %v", err))
		return
	}
	jsonResp(w, map[string]string{"status": "ok"})
}

func handleAddRegion(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Region string `json:"region"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	if _, err := db.Exec(fmt.Sprintf("ALTER DATABASE %s ADD REGION '%s'", dbName, body.Region)); err != nil {
		jsonErr(w, 500, fmt.Sprintf("add region: %v", err))
		return
	}
	jsonResp(w, map[string]string{"status": "ok"})
}

func handleRemoveRegion(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Region string `json:"region"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	if _, err := db.Exec(fmt.Sprintf("ALTER DATABASE %s DROP REGION '%s'", dbName, body.Region)); err != nil {
		jsonErr(w, 500, fmt.Sprintf("remove region: %v", err))
		return
	}
	jsonResp(w, map[string]string{"status": "ok"})
}

func handleSetSurvivalGoal(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Goal string `json:"goal"`
	}
	json.NewDecoder(r.Body).Decode(&body)

	goalSQL := "ZONE FAILURE"
	if body.Goal == "region" {
		goalSQL = "REGION FAILURE"
	}

	if _, err := db.Exec(fmt.Sprintf("ALTER DATABASE %s SURVIVE %s", dbName, goalSQL)); err != nil {
		jsonErr(w, 500, fmt.Sprintf("survival goal: %v", err))
		return
	}
	jsonResp(w, map[string]string{"status": "ok"})
}

// --- Table Locality ---

func handleSetTableLocality(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Locality string `json:"locality"`
	}
	json.NewDecoder(r.Body).Decode(&body)

	var stmt string
	switch body.Locality {
	case "regional-by-table":
		stmt = fmt.Sprintf("ALTER TABLE %s.demo SET LOCALITY REGIONAL BY TABLE IN PRIMARY REGION", dbName)
	case "regional-by-row":
		stmt = fmt.Sprintf("ALTER TABLE %s.demo SET LOCALITY REGIONAL BY ROW", dbName)
	case "global":
		stmt = fmt.Sprintf("ALTER TABLE %s.demo SET LOCALITY GLOBAL", dbName)
	default:
		jsonErr(w, 400, "invalid locality")
		return
	}

	if _, err := db.Exec(stmt); err != nil {
		jsonErr(w, 500, fmt.Sprintf("set locality: %v", err))
		return
	}
	jsonResp(w, map[string]string{"status": "ok"})
}

// --- Node/Region Docker Control ---

func handleNodeAction(w http.ResponseWriter, r *http.Request) {
	// /api/nodes/{nodeId}/{action}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/nodes/"), "/")
	if len(parts) != 2 {
		jsonErr(w, 400, "expected /api/nodes/{id}/{kill|restart}")
		return
	}
	nodeID, action := parts[0], parts[1]
	container := containerPrefix + nodeID

	var cmd *exec.Cmd
	switch action {
	case "kill":
		cmd = exec.Command("docker", "stop", container)
	case "restart":
		cmd = exec.Command("docker", "start", container)
	default:
		jsonErr(w, 400, "action must be kill or restart")
		return
	}

	if out, err := cmd.CombinedOutput(); err != nil {
		jsonErr(w, 500, fmt.Sprintf("%s %s: %s (%v)", action, container, string(out), err))
		return
	}
	jsonResp(w, map[string]string{"status": "ok", "nodeId": nodeID, "action": action})
}

func handleRegionAction(w http.ResponseWriter, r *http.Request) {
	// /api/cluster/region/{regionName}/{action}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/cluster/region/"), "/")
	if len(parts) != 2 {
		jsonErr(w, 400, "expected /api/cluster/region/{name}/{kill|restart}")
		return
	}
	regionName, action := parts[0], parts[1]

	// Find containers for this region by listing docker containers with matching locality label
	out, err := exec.Command("docker", "ps", "-a", "--format", "{{.Names}}", "--filter", fmt.Sprintf("label=region=%s", regionName)).CombinedOutput()
	if err != nil {
		jsonErr(w, 500, fmt.Sprintf("list containers: %v", err))
		return
	}

	containers := []string{}
	for _, name := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if name != "" {
			containers = append(containers, name)
		}
	}

	if len(containers) == 0 {
		jsonErr(w, 404, fmt.Sprintf("no containers found for region %s", regionName))
		return
	}

	var dockerCmd string
	switch action {
	case "kill":
		dockerCmd = "stop"
	case "restart":
		dockerCmd = "start"
	default:
		jsonErr(w, 400, "action must be kill or restart")
		return
	}

	affected := []string{}
	for _, c := range containers {
		if err := exec.Command("docker", dockerCmd, c).Run(); err == nil {
			affected = append(affected, c)
		}
	}

	key := "killed"
	if action == "restart" {
		key = "restarted"
	}
	jsonResp(w, map[string]any{"status": "ok", "region": regionName, key: affected})
}

// --- Demo Scenarios ---

func handleDemoScenario(w http.ResponseWriter, r *http.Request) {
	var body struct {
		SQL []string `json:"sql"`
	}
	json.NewDecoder(r.Body).Decode(&body)

	type Result struct {
		Index  int    `json:"index"`
		SQL    string `json:"sql"`
		Status string `json:"status"`
		Error  string `json:"error,omitempty"`
	}
	results := []Result{}

	for i, stmt := range body.SQL {
		res := Result{Index: i, SQL: stmt, Status: "ok"}
		if _, err := db.Exec(stmt); err != nil {
			res.Status = "error"
			res.Error = err.Error()
		}
		results = append(results, res)
	}

	jsonResp(w, map[string]any{
		"status":  "ok",
		"results": results,
		"total":   len(results),
	})
}

func handleGlobeScenarios(w http.ResponseWriter, r *http.Request) {
	scenarios := map[string][]string{
		"setup-multiregion": {
			fmt.Sprintf("CREATE DATABASE IF NOT EXISTS %s", dbName),
			fmt.Sprintf("ALTER DATABASE %s SET PRIMARY REGION 'us-east1'", dbName),
			fmt.Sprintf("ALTER DATABASE %s ADD REGION 'eu-west1'", dbName),
			fmt.Sprintf("ALTER DATABASE %s ADD REGION 'ap-southeast1'", dbName),
		},
		"zone-survival": {
			fmt.Sprintf("ALTER DATABASE %s SURVIVE ZONE FAILURE", dbName),
		},
		"region-survival": {
			fmt.Sprintf("ALTER DATABASE %s SURVIVE REGION FAILURE", dbName),
		},
		"create-global-table": {
			fmt.Sprintf("CREATE TABLE IF NOT EXISTS %s.ref_data (id INT PRIMARY KEY, val STRING) LOCALITY GLOBAL", dbName),
		},
		"create-regional-by-row": {
			fmt.Sprintf("CREATE TABLE IF NOT EXISTS %s.user_data (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name STRING, region crdb_internal_region AS (CASE WHEN id IS NOT NULL THEN gateway_region() END) STORED) LOCALITY REGIONAL BY ROW", dbName),
		},
		"insert-sample-data": {
			fmt.Sprintf("INSERT INTO %s.demo (name) VALUES ('test-from-globe-ui')", dbName),
		},
	}

	jsonResp(w, map[string]any{"scenarios": scenarios})
}
